// Local synthetic fixture only. Never reads the real application's tokens or database.
const fs=require('node:fs');
const file='/private/tmp/seftly-device-fixture.json',fixture=JSON.parse(fs.readFileSync(file));
if(fixture.email!=='qa-parent@example.test'||fixture.username!=='qa-child')throw Error('Unexpected fixture');
async function request(method,path,body,retry=true){
 const response=await fetch('http://127.0.0.1:4001'+path,{method,headers:{'content-type':'application/json',authorization:'Bearer '+fixture.parent.accessToken},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(10000)});
 if(response.status===401&&retry){
  const refreshed=await fetch('http://127.0.0.1:4001/api/auth/refresh',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({refreshToken:fixture.parent.refreshToken})});
  if(!refreshed.ok)throw Error('QA fixture login expired');Object.assign(fixture.parent,await refreshed.json());fs.writeFileSync(file,JSON.stringify(fixture),{mode:0o600});return request(method,path,body,false);
 }
 if(!response.ok)throw Error('QA request failed: '+response.status);return response.json();
}
(async()=>{
 const child=fixture.child.id,action=process.argv[2];
 if(action==='notifications-on'||action==='notifications-off'){
  await request('PUT','/api/activity/policy/'+child,{notificationsEnabled:action.endsWith('-on'),monitoredPackages:['dev.seftly.notificationfixture'],retentionDays:7});console.log('Synthetic notification policy updated.');
 }else if(action==='communications-on'){
  await request('PUT','/api/activity/policy/'+child,{callsEnabled:true,smsEnabled:true,fullCommunicationHistoryEnabled:true,messageBodiesEnabled:true,contactsEnabled:false,mmsEnabled:true,initialImportDays:1,retentionDays:7});console.log('Synthetic public-provider communications policy enabled.');
 }else if(action==='communications'){
  const policy=await request('GET','/api/communications/policy/'+child);
  const calls=await request('GET','/api/communications/'+child+'/CALL'),messages=await request('GET','/api/communications/'+child+'/SMS');
  for(const record of [...calls.records,...messages.records]){const address=record.details.phoneNumber||record.details.address||'';if(address&&!address.replace(/\D/g,'').startsWith('1555010'))throw Error('Unexpected non-fixture communication');}
  console.log(JSON.stringify({capabilities:policy.capabilities,calls:calls.records,messages:messages.records}));
 }else if(action==='status'){
  const policy=await request('GET','/api/activity/policy/'+child);console.log(JSON.stringify({online:policy.online,capabilities:policy.capabilities,lastCheckIns:policy.lastCheckIns}));
 }else if(action==='notifications'){
  const result=await request('GET','/api/activity/'+child+'/NOTIFICATION');
  for(const record of result.records){if(record.packageName!=='dev.seftly.notificationfixture'||record.body!==undefined||record.text!==undefined||record.title!==undefined)throw Error('Unexpected private content in fixture result');}
  console.log(JSON.stringify({count:result.total,records:result.records.map(r=>({packageName:r.packageName,eventType:r.eventType,eventAt:r.eventAt}))}));
 }else throw Error('Unknown fixture action');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
