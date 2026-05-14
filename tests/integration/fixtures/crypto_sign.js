// Test crypto.createSign() and crypto.createVerify() with real OpenSSL signing
var crypto = require('crypto');
var checks = 0, passed = 0;
function check(name, cond) { checks++; if(cond){passed++;console.log('PASS: '+name);}else console.log('FAIL: '+name); }

// Test createSign/createVerify exist as functions
check('createSign is function', typeof crypto.createSign === 'function');
check('createVerify is function', typeof crypto.createVerify === 'function');

// Test Sign object has correct methods
var sign = crypto.createSign('sha256');
check('sign object created', typeof sign === 'object' && sign !== null);
check('sign.update is function', typeof sign.update === 'function');
check('sign.sign is function', typeof sign.sign === 'function');

// Test sign.update returns this (chaining)
var ret = sign.update('hello');
check('sign.update returns this', ret === sign);

// Test Verify object has correct methods
var verify = crypto.createVerify('sha256');
check('verify object created', typeof verify === 'object' && verify !== null);
check('verify.update is function', typeof verify.update === 'function');
check('verify.verify is function', typeof verify.verify === 'function');

// Test verify.update returns this (chaining)
var ret2 = verify.update('hello');
check('verify.update returns this', ret2 === verify);

// Test case-insensitive algorithm names
var sign2 = crypto.createSign('SHA256');
check('SHA256 uppercase works', typeof sign2.sign === 'function');

var sign3 = crypto.createSign('RSA-SHA256');
check('RSA-SHA256 prefix works', typeof sign3.sign === 'function');

// Pre-generated 1024-bit RSA key pair (PKCS#8 format) for deterministic testing
var privateKey = '-----BEGIN PRIVATE KEY-----\n' +
'MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAMjRIMyvv+Sk2dRD\n' +
'hijGNsfxAhicaD16SuUUFE4mqUho2nkyLUMDboXtLzRcQzlMc0Oh8H0ka/Vclw6X\n' +
'qG1lCnEwlznuI3Zoh3/wN9BoxlmmaWr+xMOEyLmf8Nh992+1ohpRElfxwID9BWyH\n' +
'FaZbaWQN0G28F3+IiB+pIQ7UoqrbAgMBAAECgYBXZw4LiILQlR9pz2nY3UyCgVcU\n' +
'Nx73gv6N7ctYqGMNbPWJwlkIzbmQ+MaO14k6qxeP3C+7h9qlFAN7Cm74Df4YuEPD\n' +
'41t1SBnD+bboCC0ndw+AcMb5zg5A1qUNVQQNHjphU32YcC4ZuKzlmoylg4pp1gdB\n' +
'W8jTDyp1ohmpkV9qoQJBAOmrep1mwLKrhd3OnYhX8O8HYFpj6J4Ap9uqYBqzEshI\n' +
'VWxLdWOJq13ZhEmoHCRYTVqyL+sdFuTrLFLrrkzqi4UCQQDcAe6RLssAt+7XCwS3\n' +
'0XWRA/02kRS5+nJK6u0vvRwuAqUR4F/URHWQwJU1i7HrGpb3B8YZjCvlp5sEy2eK\n' +
'CzrfAkAMeNSglh1u6+zHPAH4hwkbGP+xk2eVF1/eP6fFhQ1Zl1LH5vcrCuwUpEmF\n' +
'TO3Dmtr2HlCkcfcI3OyOuHmjLVmpAkEArZBAmvylXf29SJ0CrdlqvGq/OmseRNIV\n' +
'lJDdaYnxT0L64q12LEmNzhKAI+v/ApDJhDz3xXPVtamSHCgzmK3fVQJAcPPLn2vO\n' +
'4ZyncmSsKdctlSCcpKnhQDzOLqZbJT6+DHYdcbhhVvIJ5rq3wu9A22E6vDzFK3xi\n' +
'qlCnPhmpk6HwbQ==\n' +
'-----END PRIVATE KEY-----\n';

var publicKey = '-----BEGIN PUBLIC KEY-----\n' +
'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDI0SDMr7/kpNnUQ4YoxjbH8QIY\n' +
'nGg9ekrlFBROJqlIaNp5Mi1DA26F7S80XEM5THNDofB9JGv1XJcOl6htZQpxMJc5\n' +
'7iN2aId/8DfQaMZZpmlq/sTDhMi5n/DYffdvtaIaURJX8cCA/QVshxWmW2lkDdBt\n' +
'vBd/iIgfqSEO1KKq2wIDAQAB\n' +
'-----END PUBLIC KEY-----\n';

// Test sign + verify round-trip with hex encoding
var signer = crypto.createSign('sha256');
signer.update('test message');
var signature = signer.sign(privateKey, 'hex');
check('sign produces hex output', typeof signature === 'string' && signature.length > 0);

// Verify valid signature
var verifier = crypto.createVerify('sha256');
verifier.update('test message');
var isValid = verifier.verify(publicKey, signature, 'hex');
check('verify valid signature', isValid === true);

// Verify with wrong data should fail
var verifier2 = crypto.createVerify('sha256');
verifier2.update('wrong message');
var isInvalid = verifier2.verify(publicKey, signature, 'hex');
check('verify wrong data returns false', isInvalid === false);

// Test base64 encoding
var signer2 = crypto.createSign('sha256');
signer2.update('test message');
var sig64 = signer2.sign(privateKey, 'base64');
check('sign base64 output', typeof sig64 === 'string' && sig64.length > 0);

var verifier3 = crypto.createVerify('sha256');
verifier3.update('test message');
var isValid64 = verifier3.verify(publicKey, sig64, 'base64');
check('verify base64 signature', isValid64 === true);

// Test key object format
var signer3 = crypto.createSign('sha256');
signer3.update('object key test');
var sig3 = signer3.sign({key: privateKey}, 'hex');
check('sign with key object', typeof sig3 === 'string' && sig3.length > 0);

// Test HMAC still works (regression check)
var hmac = crypto.createHmac('sha256', 'test-key');
hmac.update('hello');
var hmacResult = hmac.digest('hex');
check('hmac still works', hmacResult.length === 64);

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
