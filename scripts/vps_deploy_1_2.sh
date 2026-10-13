#!/usr/bin/env bash
set -euo pipefail
seftly_live=/home/deploy/parental-monitoring-mvp/backend
seftly_previous=/home/deploy/seftly-releases/20261013-73ee98e
seftly_release=/home/deploy/seftly-releases/20261013-1.2.0-699f21b
seftly_backup=/home/deploy/seftly-releases/backups/20261013-1.2.0-73ee98e
seftly_switched=0
rollback() {
  seftly_status=$?
  if [ "$seftly_status" -ne 0 ] && [ "$seftly_switched" -eq 1 ]; then
    ln -s "$seftly_previous" "$seftly_live.rollback-next"
    mv -Tf "$seftly_live.rollback-next" "$seftly_live"
    runuser -u deploy -- pm2 reload parental-monitoring-backend --update-env > "$seftly_release/rollback-pm2.log" 2>&1
    curl --retry 6 --retry-delay 1 --retry-all-errors -fsS https://api.hakaluki.dev/ready
    printf '\nPrevious application restored; database preserved.\n'
  fi
  exit "$seftly_status"
}
trap rollback EXIT
test "$(readlink -f "$seftly_live")" = "$seftly_previous"
python3 - "$seftly_release" "$seftly_backup" <<'PY'
import json, pathlib, sys
release, backup = map(pathlib.Path, sys.argv[1:])
assert json.loads((release/'stage-verification.json').read_text())['passed']
assert json.loads((backup/'verification.json').read_text())['verificationDatabaseRemoved']
PY
# Apply only indexes on the two new collections; no syncIndexes or historical TTL backfill.
node - "$seftly_release" <<'JS'
const fs=require('fs'),release=process.argv[2];
Object.assign(process.env,require(release+'/node_modules/dotenv').parse(fs.readFileSync(release+'/.env')));
const mongoose=require(release+'/node_modules/mongoose');
(async()=>{
 await mongoose.connect(process.env.MONGO_URI,{autoIndex:false});
 for(const [file,name] of [['ActivityEvent','ActivityEvent'],['AudioSession','AudioSession']]) {
  const model=require(release+'/dist/models/'+file)[name];
  if(await model.countDocuments({})!==0)throw Error('Expected empty new collection before first rollout');
  await model.createIndexes();
 }
 console.log('Only new activity/audio collection indexes applied.');
})().catch(()=>{console.error('New collection index gate failed.');process.exitCode=1;}).finally(()=>mongoose.disconnect());
JS
ln -s "$seftly_release" "$seftly_live.release-next"
chown -h deploy:deploy "$seftly_live.release-next"
mv -Tf "$seftly_live.release-next" "$seftly_live"
seftly_switched=1
runuser -u deploy -- pm2 reload parental-monitoring-backend --update-env > "$seftly_release/deploy-pm2.log" 2>&1
curl --retry 8 --retry-delay 1 --retry-all-errors -fsS https://api.hakaluki.dev/ready | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d["status"]=="ready" and d["revision"]=="1.2.0-699f21b-working-tree"; print(json.dumps(d))'
node /home/deploy/seftly-releases/vps_smoke_1_2.cjs production
node - "$seftly_release" "$seftly_backup" <<'JS'
const fs=require('fs'),release=process.argv[2],base=process.argv[3];
const settings=require(release+'/node_modules/dotenv').parse(fs.readFileSync(release+'/.env'));
const {MongoClient}=require(release+'/node_modules/mongodb'),client=new MongoClient(settings.MONGO_URI);
(async()=>{
 await client.connect();const snapshot=JSON.parse(fs.readFileSync(base+'/record-ids-before.json')),retained={};
 for(const [name,ids] of Object.entries(snapshot)) {
  const current=new Set((await client.db().collection(name).find({},{projection:{_id:1}}).toArray()).map(x=>x._id.toString()));
  if(ids.some(id=>!current.has(id)))throw Error('Preexisting record missing after release');
  retained[name]=ids.length;
 }
 const report={verifiedAt:new Date().toISOString(),preexistingIdsRetained:retained,passed:true};
 fs.writeFileSync(release+'/data-preservation.json',JSON.stringify(report,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(report));
})().catch(()=>{console.error('Data-preservation check failed.');process.exitCode=1;}).finally(()=>client.close());
JS
runuser -u deploy -- pm2 save > "$seftly_release/pm2-save.log" 2>&1
printf 'PRODUCTION_1_2_DEPLOYMENT_VERIFIED\n'
