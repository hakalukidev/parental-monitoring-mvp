// Run on the authorized VPS. Secrets and record identifiers stay in a root-only backup.
const fs = require('node:fs'), path = require('node:path'), cp = require('node:child_process'), crypto = require('node:crypto');
const live = '/home/deploy/parental-monitoring-mvp/backend';
const base = '/home/deploy/seftly-releases/backups/20261013-1.3.0-699f21b';
const config = require(live + '/node_modules/dotenv').parse(fs.readFileSync(live + '/.env'));
const {MongoClient} = require(live + '/node_modules/mongodb');
function run(command, args, name) {
  const result = cp.spawnSync(command, args, {encoding:'utf8'});
  fs.writeFileSync(base + '/' + name, (result.stdout || '') + (result.stderr || ''), {mode:0o600});
  if (result.status !== 0) throw Error(command + ' failed; inspect the private backup log');
}
(async () => {
  fs.mkdirSync(base, {mode:0o700});
  fs.copyFileSync(live + '/.env', base + '/runtime.env'); fs.chmodSync(base + '/runtime.env', 0o600);
  run('runuser',['-u','deploy','--','pm2','jlist'],'pm2-before.json');
  run('tar',['--dereference','-czf',base+'/backend-before.tgz','-C',path.dirname(live),'backend'],'application-backup.log');
  const client = new MongoClient(config.MONGO_URI, {serverSelectionTimeoutMS:5000});
  await client.connect();
  try {
    const source = client.db().databaseName, restore = 'seftly_restore_verify_20261013_1_3';
    if (source === restore || (await client.db('admin').admin().listDatabases({nameOnly:true})).databases.some(x=>x.name===restore)) throw Error('Unsafe restore namespace');
    const snapshot = {};
    for (const collection of await client.db().listCollections({}, {nameOnly:true}).toArray()) {
      snapshot[collection.name] = (await client.db().collection(collection.name).find({}, {projection:{_id:1}}).toArray()).map(x=>x._id.toString());
    }
    fs.writeFileSync(base+'/record-ids-before.json',JSON.stringify(snapshot),{mode:0o600});
    const dumpConfig = base+'/dump-tools.yml', restoreConfig = base+'/restore-tools.yml';
    fs.writeFileSync(dumpConfig,'uri: '+JSON.stringify(config.MONGO_URI)+'\n',{mode:0o600});
    run('mongodump',['--config',dumpConfig,'--db',source,'--out',base+'/database'],'dump.log');
    const uri = new URL(config.MONGO_URI);
    if (uri.username && !uri.searchParams.has('authSource')) uri.searchParams.set('authSource',source);
    uri.pathname='/';
    fs.writeFileSync(restoreConfig,'uri: '+JSON.stringify(uri.toString())+'\n',{mode:0o600});
    run('mongorestore',['--config',restoreConfig,'--nsInclude',source+'.*','--nsFrom',source+'.*','--nsTo',restore+'.*',base+'/database'],'restore.log');
    const counts = {}, indexes = {};
    for (const file of fs.readdirSync(base+'/database/'+source).filter(x=>x.endsWith('.bson'))) {
      const bytes=fs.readFileSync(base+'/database/'+source+'/'+file); let count=0,offset=0;
      while(offset<bytes.length) {const size=bytes.readInt32LE(offset);if(size<5||offset+size>bytes.length)throw Error('Invalid BSON backup');offset+=size;count++;}
      const name=file.slice(0,-5), restored=client.db(restore).collection(name);
      if(await restored.countDocuments({})!==count)throw Error('Restore count mismatch');
      const metadata=JSON.parse(fs.readFileSync(base+'/database/'+source+'/'+name+'.metadata.json'));
      const actual=await restored.indexes();if(actual.length!==metadata.indexes.length)throw Error('Restore index mismatch');
      counts[name]=count;indexes[name]=actual.length;
    }
    await client.db(restore).dropDatabase();fs.unlinkSync(dumpConfig);fs.unlinkSync(restoreConfig);
    run('tar',['-czf',base+'/database-backup.tgz','-C',base,'database'],'database-archive.log');
    const hashes={};for(const file of ['backend-before.tgz','database-backup.tgz'])hashes[file]=crypto.createHash('sha256').update(fs.readFileSync(base+'/'+file)).digest('hex');
    const report={verifiedAt:new Date().toISOString(),sourceDatabase:source,restoredCollectionCounts:counts,restoredIndexCounts:indexes,verificationDatabaseRemoved:true,hashes,backupType:'logical standalone backup; live writers remained active'};
    fs.writeFileSync(base+'/verification.json',JSON.stringify(report,null,2)+'\n',{mode:0o600});
    console.log(JSON.stringify(report));
  } finally {await client.close();}
})().catch(()=>{console.error('Backup gate failed; inspect root-only logs. Production was not switched.');process.exitCode=1;});
