const fs=require('node:fs'),crypto=require('node:crypto');
const release='/home/deploy/seftly-releases/20261013-1.3.0-699f21b';
const base='/home/deploy/seftly-releases/backups/20261013-1.3.0-699f21b';
const dotenv=require(release+'/node_modules/dotenv');
const prior=dotenv.parse(fs.readFileSync(base+'/runtime.env'));
const revision='1.3.0-699f21b-working-tree';
(async()=>{
  const backup=JSON.parse(fs.readFileSync(base+'/verification.json'));if(!backup.verificationDatabaseRemoved)throw Error('Unverified backup');
  let text=fs.readFileSync(base+'/runtime.env','utf8');
  // Guardian collection settings remain off by default; preserve existing secrets and history.
  const settings={RELEASE_REVISION:revision,FEATURE_AUDIO_ENABLED:'true',FEATURE_NOTIFICATIONS_ENABLED:'true',FEATURE_CALL_SMS_ENABLED:'false',FEATURE_COMMUNICATIONS_ENABLED:'true',COMMUNICATION_DATA_KEY:prior.COMMUNICATION_DATA_KEY||crypto.randomBytes(32).toString('hex'),FEATURE_SAFETY_ENABLED:'false',SAFETY_APPROVED_MODELS:''};
  for(const[key,value]of Object.entries(settings)){const line=key+'='+JSON.stringify(value),pattern=new RegExp('^'+key+'=.*$','m');text=pattern.test(text)?text.replace(pattern,()=>line):text+'\n'+line;}
  fs.writeFileSync(release+'/.env',text+'\n',{mode:0o600});fs.chownSync(release+'/.env',1000,1000);
  Object.assign(process.env,dotenv.parse(text));require(release+'/dist/config/env');
  const {MongoClient}=require(release+'/node_modules/mongodb'),client=new MongoClient(prior.MONGO_URI);
  await client.connect();try {
    const stage='seftly_stage_20261013_1_3';
    if((await client.db('admin').admin().listDatabases({nameOnly:true})).databases.some(x=>x.name===stage))throw Error('Stage database already exists');
    const uri=new URL(prior.MONGO_URI);if(uri.username&&!uri.searchParams.has('authSource'))uri.searchParams.set('authSource',client.db().databaseName);uri.pathname='/'+stage;
    fs.writeFileSync(release+'/stage.env',text+'\nMONGO_URI='+JSON.stringify(uri.toString())+'\nPORT=4101\nFEATURE_AUDIO_ENABLED=true\nFEATURE_NOTIFICATIONS_ENABLED=true\n',{mode:0o600});
    console.log('Private production configuration validated; staging uses an empty isolated database.');
  } finally{await client.close();}
})().catch(()=>{console.error('Release preparation gate failed; production remains unchanged.');process.exitCode=1;});
