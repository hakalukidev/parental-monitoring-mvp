const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeWebsiteTarget: normalize } = require('../dist/services/webTargets');
test('domain inputs normalize scheme, case, www, root dots and international hosts', () => {
  for (const input of ['example.com','www.example.com','http://example.com','https://www.example.com',' EXAMPLE.COM. ','HTTP://WWW.EXAMPLE.COM/']) assert.deepEqual(normalize('DOMAIN',input),{ruleType:'DOMAIN',target:'example.com'});
  assert.equal(normalize('DOMAIN','m.example.com').target,'m.example.com');
  assert.equal(normalize('DOMAIN','*.example.com').target,'*.example.com');
  assert.equal(normalize('DOMAIN','bücher.de').target,'xn--bcher-kva.de');
});
test('paths promote to exact URLs without broadening or lowercasing paths', () => {
  assert.deepEqual(normalize('DOMAIN','example.com/Study?q=Test#section'),{ruleType:'URL',target:'https://example.com/Study?q=Test'});
  assert.equal(normalize('URL','https://www.example.com:443/Study').target,'https://example.com/Study');
  assert.equal(normalize('DOMAIN','https://example.com.evil.test').target,'example.com.evil.test');
});
test('unsupported schemes, credentials, wildcards, malformed names and IDNA deviations fail', () => {
  for (const input of ['javascript:alert(1)','file:///tmp/file','ftp://example.com','https://u:p@example.com','https://example.com\\evil','*example.com','example..com','bad name.com','-bad.com','*.example.com/path','https://faß.de']) assert.throws(()=>normalize('DOMAIN',input), input);
  assert.throws(()=>normalize('URL','*.example.com'));
});
