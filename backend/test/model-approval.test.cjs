const {test}=require('node:test');
const assert=require('node:assert/strict');
const {approvedSafetyModels}=require('../dist/services/activityValidation');
test('production rejects test-only safety model approvals',()=>{
  const prior={NODE_ENV:process.env.NODE_ENV,SAFETY_APPROVED_MODELS:process.env.SAFETY_APPROVED_MODELS};
  try {
    process.env.NODE_ENV='production';process.env.SAFETY_APPROVED_MODELS='test-only-stub-v1,fixture-model,licensed-evaluated-v1';
    assert.deepEqual(approvedSafetyModels(),['licensed-evaluated-v1']);
    process.env.NODE_ENV='test';assert.equal(approvedSafetyModels().length,3);
  } finally {for(const [key,value] of Object.entries(prior))value===undefined?delete process.env[key]:process.env[key]=value;}
});
