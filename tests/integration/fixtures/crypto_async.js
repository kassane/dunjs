// Test async crypto methods
var crypto = require('crypto');
var checks = 0;
var passed = 0;
var pending = 0;

function check(name, condition) {
  checks++;
  if (condition) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
  pending--;
  if (pending === 0) finish();
}

function finish() {
  // Sync checks
  checks++;
  if (typeof crypto.randomFillSync === 'function') { passed++; console.log('PASS: randomFillSync exists'); }
  else console.log('FAIL: randomFillSync exists');

  checks++;
  if (typeof crypto.createSign === 'function') { passed++; console.log('PASS: createSign exists'); }
  else console.log('FAIL: createSign exists');

  checks++;
  if (typeof crypto.createVerify === 'function') { passed++; console.log('PASS: createVerify exists'); }
  else console.log('FAIL: createVerify exists');

  checks++;
  if (typeof crypto.constants === 'object') { passed++; console.log('PASS: constants exists'); }
  else console.log('FAIL: constants exists');

  checks++;
  if (typeof crypto.constants.RSA_PKCS1_PADDING === 'number') { passed++; console.log('PASS: constants.RSA_PKCS1_PADDING'); }
  else console.log('FAIL: constants.RSA_PKCS1_PADDING');

  // createSign returns object with update and sign
  checks++;
  var signer = crypto.createSign('SHA256');
  if (typeof signer.update === 'function' && typeof signer.sign === 'function') {
    passed++; console.log('PASS: createSign API');
  } else console.log('FAIL: createSign API');

  // createVerify returns object with update and verify
  checks++;
  var verifier = crypto.createVerify('SHA256');
  if (typeof verifier.update === 'function' && typeof verifier.verify === 'function') {
    passed++; console.log('PASS: createVerify API');
  } else console.log('FAIL: createVerify API');

  console.log('---');
  console.log('Total: ' + passed + '/' + checks + ' passed');
}

// Async pbkdf2
pending++;
crypto.pbkdf2('password', 'salt', 100000, 32, 'sha256', function(err, derivedKey) {
  check('pbkdf2 no error', err === null);
});

// Async pbkdf2 - result type
pending++;
crypto.pbkdf2('password', 'salt', 1000, 16, 'sha256', function(err, derivedKey) {
  check('pbkdf2 result', derivedKey !== null && derivedKey !== undefined);
});

// Async scrypt
pending++;
crypto.scrypt('password', 'salt', 32, function(err, derivedKey) {
  check('scrypt no error', err === null);
});

// Async scrypt - result
pending++;
crypto.scrypt('password', 'salt', 16, function(err, derivedKey) {
  check('scrypt result', derivedKey !== null && derivedKey !== undefined);
});

// randomFill
pending++;
var buf = new Uint8Array(16);
crypto.randomFill(buf, function(err, filled) {
  var hasNonZero = false;
  for (var i = 0; i < filled.length; i++) {
    if (filled[i] !== 0) hasNonZero = true;
  }
  check('randomFill works', err === null && hasNonZero);
});
