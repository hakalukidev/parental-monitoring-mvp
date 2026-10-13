// Synthetic families only. No production child record is used as a feature fixture.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const release='/home/deploy/seftly-releases/20261013-1.3.0-699f21b',phase=process.argv[2];
if(!['stage','production'].includes(phase))throw Error('Invalid phase');
const settings=require(release+'/node_modules/dotenv').parse(fs.readFileSync(release+(phase==='stage'?'/stage.env':'/.env')));
Object.assign(process.env,settings);
const {MongoClient,ObjectId}=require(release+'/node_modules/mongodb');
const {io}=require('/home/deploy/seftly-releases/qa-tools/node_modules/socket.io-client');
const database=new MongoClient(settings.MONGO_URI),url=phase==='stage'?'http://127.0.0.1:4101':'https://api.hakaluki.dev';
const prefix='seftlyqa13'+Date.now(),password=crypto.randomBytes(24).toString('hex'),parents=[],children=[],sockets=[],steps=[];
let server,socketServer;
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function api(method,route,body,token,status=200){
  const response=await fetch(url+route,{method,headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(12000)});
  assert.ok((Array.isArray(status)?status:[status]).includes(response.status),method+' '+route+' returned '+response.status);
  return response.status===204?null:response.json();
}
async function socket(token){const s=io(url,{transports:['websocket'],auth:{token},forceNew:true,reconnection:false,timeout:8000});sockets.push(s);await new Promise((resolve,reject)=>{s.once('connect',resolve);s.once('connect_error',()=>reject(Error('Authenticated socket failed')));});return s;}
const emit=(s,event,data)=>new Promise((resolve,reject)=>s.timeout(5000).emit(event,data,(error,result)=>error?reject(Error('Socket timeout: '+event)):resolve(result)));
async function cleanup(){
  sockets.forEach(s=>s.disconnect());await delay(200);
  const childIds=children.map(c=>new ObjectId(c.id)),parentIds=parents.map(p=>new ObjectId(p.user.id)),userIds=[...childIds,...parentIds];
  const stringIds=children.flatMap(c=>[c.id,...['screen','camera','audio','microphone'].map(k=>k+':'+c.id)]);
  for(const collection of await database.db().listCollections({},{nameOnly:true}).toArray()){
    if(collection.name==='users')continue;
    await database.db().collection(collection.name).deleteMany({$or:[{childId:{$in:childIds}},{parentId:{$in:parentIds}},{userId:{$in:userIds}},{_id:{$in:stringIds}}]});
  }
  if(userIds.length)await database.db().collection('users').deleteMany({_id:{$in:userIds},$or:[{email:{$regex:'^'+prefix}},{parentId:{$in:parentIds}}]});
  assert.equal(await database.db().collection('users').countDocuments({_id:{$in:userIds}}),0);
}
(async()=>{
  await database.connect();
  if(phase==='stage'){
    assert.equal(database.db().databaseName,'seftly_stage_20261013_1_3');
    assert.equal(await database.db().collection('users').countDocuments({}),0);
    await require(release+'/dist/config/db').connectDB();
    server=require('node:http').createServer(require(release+'/dist/app').createApp());
    socketServer=new(require(release+'/node_modules/socket.io').Server)(server);
    require(release+'/dist/socket/io').setIO(socketServer);require(release+'/dist/socket').registerSocketHandlers(socketServer);
    await new Promise(r=>server.listen(4101,'127.0.0.1',r));
  }
  assert.equal((await api('GET','/health')).status,'ok');const ready=await api('GET','/ready');
  assert.equal(ready.status,'ready');assert.equal(ready.revision,'1.3.0-699f21b-working-tree');
  await api('GET','/api/config',null,null,401);steps.push('TLS/public health, readiness, release revision and unauthenticated config denial');
  for(let index=0;index<2;index++){
    const email=prefix+'p'+index+'@example.test';
    const parent=await api('POST','/api/auth/register',{name:'Seftly deployment QA',email,password,confirmPassword:password},null,201);parents.push(parent);
    assert.equal((await api('POST','/api/auth/login',{email,password})).user.id,parent.user.id);
    const username=prefix+'c'+index,created=await api('POST','/api/children',{name:'Synthetic QA child',username,password,confirmPassword:password},parent.accessToken,201);
    children.push({id:created.id});Object.assign(children[index],await api('POST','/api/auth/child-login',{email:username,password}));
    await api('POST','/api/devices/register',{deviceName:'Temporary synthetic fixture',platform:'Android',mediaConsentVersion:2,audioCheckInVersion:1,policyProtocolVersion:2,timeZone:'Asia/Dhaka'},children[index].accessToken,201);
  }
  const config=await api('GET','/api/config',null,parents[0].accessToken);assert.equal(config.mediaProtocolVersion,2);assert.equal(config.webRuleProtocolVersion,2);
  await api('POST','/api/auth/refresh',{refreshToken:parents[0].refreshToken});
  await api('GET','/api/children/'+children[1].id,null,parents[0].accessToken,[403,404]);
  await api('GET','/api/children',null,children[0].accessToken,403);
  steps.push('Two synthetic families: parent/child login, refresh, capability registration, ownership and role checks');
  const childId=children[0].id,pToken=parents[0].accessToken,cToken=children[0].accessToken;
  const preview=await api('POST','/api/children/'+childId+'/web-rules/preview',{ruleType:'DOMAIN',target:'https://www.Example.com/Study?q=Test#ignored',action:'BLOCK'},pToken);
  assert.equal(preview.target,'https://example.com/Study?q=Test');assert.equal(preview.ruleType,'URL');
  await api('POST','/api/children/'+children[1].id+'/web-rules/preview',{ruleType:'DOMAIN',target:'example.com',action:'BLOCK'},pToken,403);
  const createdRule=await api('POST','/api/children/'+childId+'/web-rules',{ruleType:'DOMAIN',target:'WWW.EXAMPLE.COM',action:'BLOCK'},pToken,201);
  assert.equal(createdRule.rule.target,'example.com');
  steps.push('Website canonical preview/create and denied cross-family preview');
  const parentSocket=await socket(pToken),otherParent=await socket(parents[1].accessToken),childSocket=await socket(cToken);await delay(150);
  for(const kind of ['screen-share','camera-stream',...(config.features.audioCheckIn?['audio-session']:[])]){
    const requested=await api('POST','/api/'+kind+'/request',{childId},pToken,201),id=requested.sessionId;
    assert.equal((await emit(otherParent,'join_session',{sessionId:id})).code,'403');
    const event=kind==='screen-share'?'screen_share':kind==='camera-stream'?'camera_stream':'audio_session';
    assert.equal((await emit(childSocket,event+'_accept',{sessionId:id})).ok,true);
    assert.equal((await emit(childSocket,'webrtc_offer',{sessionId:id,sdp:{type:'offer',sdp:'synthetic negotiation fixture'}})).ok,true);
    assert.equal((await emit(parentSocket,'webrtc_answer',{sessionId:id,sdp:{type:'answer',sdp:'synthetic negotiation fixture'}})).ok,true);
    assert.equal((await emit(childSocket,'media_connected',{sessionId:id})).ok,true);
    await api('POST','/api/'+kind+'/'+id+'/stop',{},pToken);
    assert.equal((await emit(childSocket,'ice_candidate',{sessionId:id,candidate:{candidate:'fixture'}})).code,'409');
  }
  if(!config.features.audioCheckIn)await api('POST','/api/audio-session/request',{childId},pToken,503);
  steps.push('Media participant isolation, accept/negotiation/Stop/replay and audio feature gate; synthetic signaling only');
  await api('GET','/api/activity/policy/'+childId,null,parents[1].accessToken,403);
  const event={kind:'NOTIFICATION',eventId:'synthetic-posted',eventAt:new Date().toISOString(),packageName:'dev.seftly.notificationfixture',eventType:'POSTED'};
  if(config.features.notificationActivity){
    await api('PUT','/api/activity/policy/'+childId,{notificationsEnabled:true,monitoredPackages:[event.packageName]},pToken);
    await api('POST','/api/activity/capabilities',{notificationAccess:'GRANTED',listenerConnected:true,callLogAccess:'DENIED_OR_RESTRICTED',smsAccess:'DENIED_OR_RESTRICTED',safetyModel:'UNAVAILABLE',sourceCoverage:'SELECTED_MEDIA_ONLY',queuedEvents:1,droppedEvents:0},cToken);
    await api('POST','/api/activity/ingest',{clientChildId:childId,events:[event]},cToken);
    assert.equal((await api('POST','/api/activity/ingest',{events:[event]},cToken)).duplicates,1);
    await api('POST','/api/activity/ingest',{events:[{...event,body:'TEST secret 000000'}]},cToken,422);
    assert.equal((await api('GET','/api/activity/'+childId+'/NOTIFICATION',null,pToken)).records.length,1);
    await api('GET','/api/activity/'+childId+'/NOTIFICATION',null,parents[1].accessToken,403);
    await api('DELETE','/api/activity/'+childId+'/NOTIFICATION',{confirmation:'DELETE_ACTIVITY'},pToken);
    await api('POST','/api/activity/ingest',{events:[event]},cToken);
    assert.equal((await api('GET','/api/activity/'+childId+'/NOTIFICATION',null,pToken)).records.length,0);
  }else{await api('PUT','/api/activity/policy/'+childId,{notificationsEnabled:true},pToken,503);await api('POST','/api/activity/ingest',{events:[event]},cToken,409);}
  await api('PUT','/api/activity/policy/'+childId,{safetyEnabled:true},pToken,503);
  if(!config.features.communicationHistory)await api('PUT','/api/activity/policy/'+childId,{callsEnabled:true},pToken,503);
  steps.push('Activity ownership, collector gates and (when enabled) metadata-only ingestion, deduplication, deletion and replay prevention');
  if(config.features.communicationHistory){
    const route='/api/communications/'+childId,at=new Date(Date.now()-1000).toISOString();
    await api('PUT','/api/activity/policy/'+childId,{callsEnabled:true,smsEnabled:true,fullCommunicationHistoryEnabled:true,messageBodiesEnabled:true,contactsEnabled:false,initialImportDays:1,retentionDays:7},pToken);
    await api('POST','/api/communications/capabilities',{protocolVersion:2,androidApi:30,callLogAccess:'GRANTED',smsAccess:'GRANTED',contactsAccess:'DENIED_OR_RESTRICTED',defaultSmsRole:false,defaultDialerRole:false,callCoverage:'PUBLIC_CALL_LOG',smsCoverage:'PUBLIC_SMS_PROVIDER',mmsCoverage:'UNAVAILABLE',queuedRecords:0,droppedRecords:0},cToken);
    const record={recordId:'abc123',sourceId:'999',kind:'SMS',transport:'SMS',direction:'INCOMING',eventAt:at,observedAt:at,address:'+15550101234',threadId:'1',body:'Synthetic school reminder',contentStatus:'AVAILABLE'},batch={clientChildId:childId,records:[record]};
    await api('POST','/api/communications/ingest',batch,cToken);
    assert.equal((await api('POST','/api/communications/ingest',batch,cToken)).duplicates,1);
    assert.equal((await api('GET',route+'/SMS?search=school',null,pToken)).records[0].details.body,record.body);
    await api('GET',route+'/SMS',null,parents[1].accessToken,403);
    await api('DELETE',route+'/SMS',{confirmation:'DELETE_COMMUNICATIONS'},parents[1].accessToken,403);
    const raw=JSON.stringify(await database.db().collection('communicationrecords').find({childId:new ObjectId(childId)}).toArray());
    assert.ok(!raw.includes(record.body)&&!raw.includes(record.address));
    await api('POST','/api/communications/ingest',{clientChildId:childId,records:[{...record,sourceId:'1000',recordId:'abc124',body:'Your OTP is 123456'}]},cToken);
    const messages=await api('GET',route+'/SMS',null,pToken);assert.ok(messages.records.some(r=>r.contentStatus==='WITHHELD_SECURITY'&&!r.details.body));
    assert.equal((await api('GET',route+'/SMS/stats',null,pToken)).weekly.reduce((sum,r)=>sum+r.count,0),2);
    await api('DELETE',route+'/SMS',{confirmation:'DELETE_COMMUNICATIONS'},pToken);
    await api('POST','/api/communications/ingest',batch,cToken);
    assert.equal((await api('GET',route+'/SMS',null,pToken)).total,0);
    steps.push('Detailed synthetic SMS encryption, authorized decryption/search, secret suppression, weekly statistics, ownership, deduplication and deletion replay');
  }
  await api('POST','/api/auth/logout',{},pToken,204);await api('GET','/api/children',null,pToken,401);
  await cleanup();steps.push('Logout revocation and synthetic fixture cleanup');
  const report={phase,verifiedAt:new Date().toISOString(),baseUrl:url,revision:ready.revision,features:config.features,steps,passed:true};
  fs.writeFileSync(release+'/'+phase+'-verification.json',JSON.stringify(report,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(report));
  if(phase==='stage'){await database.db().dropDatabase();fs.unlinkSync(release+'/stage.env');}
})().catch(async error=>{console.error('Release smoke failed:',error.message.replace(/Bearer\s+\S+/g,'Bearer [redacted]'));process.exitCode=1;try{await cleanup();}catch{console.error('Synthetic cleanup needs follow-up');}})
.finally(async()=>{if(socketServer)await new Promise(r=>socketServer.close(r));if(server?.listening)await new Promise(r=>server.close(r));await database.close();if(phase==='stage')await require(release+'/node_modules/mongoose').disconnect();});
