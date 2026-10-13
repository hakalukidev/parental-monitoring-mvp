const {test}=require('node:test'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {sealCommunication,openCommunication,communicationSearchTerms,securityMessage}=require('../dist/services/communicationPrivacy');
test('communication content is authenticated-encrypted, identity-bound and searchable without plaintext indexes',()=>{
  process.env.COMMUNICATION_DATA_KEY=crypto.randomBytes(32).toString('hex');
  const record={phoneNumber:'+15550101234',contactName:'Synthetic Guardian',body:'School pickup reminder'},id='synthetic-child:SMS:source';
  const sealed=sealCommunication(id,record),again=sealCommunication(id,record);
  assert.notEqual(sealed,again);assert.deepEqual(openCommunication(id,sealed),record);
  assert.throws(()=>openCommunication('another-child:SMS:source',sealed));
  assert.ok(!sealed.includes(record.phoneNumber)&&!sealed.includes(record.body));
  const words=communicationSearchTerms(record.body);assert.equal(words.length,3);assert.ok(words.every(x=>/^[a-f0-9]{64}$/.test(x)));
  assert.deepEqual(communicationSearchTerms('School PICKUP'),words.slice(0,2));
  assert.deepEqual(communicationSearchTerms('+1 (555) 010-1234'),communicationSearchTerms('15550101234'));
  assert.ok(communicationSearchTerms('+1 (555) 010-1234 Synthetic Guardian School pickup').includes(communicationSearchTerms('15550101234')[0]));
  const old=process.env.COMMUNICATION_DATA_KEY;process.env.COMMUNICATION_DATA_KEY=crypto.randomBytes(32).toString('hex');assert.throws(()=>openCommunication(id,sealed));process.env.COMMUNICATION_DATA_KEY=old;
});
test('security-message suppression excludes codes, passwords and credential links without claiming perfect classification',()=>{
  for(const text of ['Your OTP is 123456','Verification code: 1234','WiFi password: secret','Reset your account','https://example.test/?token=secret','ওটিপি ১২৩৪৫৬'])assert.equal(securityMessage(text),true);
  assert.equal(securityMessage('Your science project is ready'),false);
  assert.equal(securityMessage('Synthetic statement','QA-BANK'),true);
});
