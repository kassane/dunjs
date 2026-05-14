// WebCrypto subtle API integration test
// Tests: subtle.digest, subtle.importKey, subtle.sign, subtle.verify,
//        subtle.encrypt, subtle.decrypt (AES-GCM, AES-CBC)

var pass = 0, fail = 0, pending = 0;
function check(name, cond) {
  if (cond) { pass++; }
  else { fail++; console.log('FAIL: ' + name); }
}

function toHex(arr) {
  return Array.from(arr).map(function(b) { return b.toString(16).padStart(2, '0'); }).join('');
}

function done() {
  console.log('');
  console.log('WebCrypto subtle: ' + pass + '/' + (pass + fail) + ' passed');
}

// Sync checks first
check('crypto.subtle exists', typeof crypto.subtle === 'object');
check('crypto.subtle.digest is function', typeof crypto.subtle.digest === 'function');
check('crypto.subtle.importKey is function', typeof crypto.subtle.importKey === 'function');
check('crypto.subtle.sign is function', typeof crypto.subtle.sign === 'function');
check('crypto.subtle.verify is function', typeof crypto.subtle.verify === 'function');
check('crypto.subtle.encrypt is function', typeof crypto.subtle.encrypt === 'function');
check('crypto.subtle.decrypt is function', typeof crypto.subtle.decrypt === 'function');

var cryptoMod = require('crypto');
check('require crypto.subtle exists', typeof cryptoMod.subtle === 'object');
check('require crypto.subtle.digest', typeof cryptoMod.subtle.digest === 'function');

// Chain all async operations via .then() to ensure JSC/V8 event loop processes them
crypto.subtle.digest('SHA-256', new Uint8Array(0))
.then(function(emptyDigest) {
  check('digest returns Uint8Array', emptyDigest instanceof Uint8Array);
  check('digest SHA-256 empty length', emptyDigest.length === 32);
  var emptyHex = toHex(emptyDigest);
  check('digest SHA-256 empty value', emptyHex === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

  return crypto.subtle.digest('SHA-256', new TextEncoder().encode('hello'));
})
.then(function(helloDigest) {
  var helloHex = toHex(helloDigest);
  check('digest SHA-256 hello', helloHex === '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');

  return crypto.subtle.digest('SHA-1', new TextEncoder().encode('hello'));
})
.then(function(sha1Digest) {
  check('digest SHA-1 length', sha1Digest.length === 20);
  check('digest SHA-1 hello', toHex(sha1Digest) === 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d');

  return crypto.subtle.digest('SHA-384', new TextEncoder().encode('hello'));
})
.then(function(sha384Digest) {
  check('digest SHA-384 length', sha384Digest.length === 48);

  return crypto.subtle.digest('SHA-512', new TextEncoder().encode('hello'));
})
.then(function(sha512Digest) {
  check('digest SHA-512 length', sha512Digest.length === 64);

  return crypto.subtle.digest({name: 'SHA-256'}, new TextEncoder().encode('hello'));
})
.then(function(objAlgoDigest) {
  check('digest with object algo', toHex(objAlgoDigest) === '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');

  // HMAC tests
  var keyData = new TextEncoder().encode('my-secret-key-for-hmac-testing!');
  return crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
})
.then(function(key) {
  check('importKey returns object', typeof key === 'object');
  check('importKey type is secret', key.type === 'secret');
  check('importKey algorithm.name', key.algorithm.name === 'HMAC');

  var data = new TextEncoder().encode('data to sign');
  return crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-256' }, key, data).then(function(sig) {
    return { key: key, data: data, sig: sig };
  });
})
.then(function(ctx) {
  check('sign returns Uint8Array', ctx.sig instanceof Uint8Array);
  check('sign HMAC-SHA256 length', ctx.sig.length === 32);

  return crypto.subtle.verify({ name: 'HMAC', hash: 'SHA-256' }, ctx.key, ctx.sig, ctx.data)
    .then(function(valid) { return { ctx: ctx, valid: valid }; });
})
.then(function(r) {
  check('verify correct signature', r.valid === true);

  var wrongData = new TextEncoder().encode('wrong data');
  return crypto.subtle.verify({ name: 'HMAC', hash: 'SHA-256' }, r.ctx.key, r.ctx.sig, wrongData);
})
.then(function(isInvalid) {
  check('verify wrong data', isInvalid === false);

  // SHA-384 HMAC
  var keyData = new TextEncoder().encode('my-secret-key-for-hmac-testing!');
  return crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-384' }, false, ['sign']);
})
.then(function(key384) {
  var data = new TextEncoder().encode('data to sign');
  return crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-384' }, key384, data);
})
.then(function(sig384) {
  check('sign HMAC-SHA384 length', sig384.length === 48);

  // SHA-512 HMAC
  var keyData = new TextEncoder().encode('my-secret-key-for-hmac-testing!');
  return crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-512' }, false, ['sign']);
})
.then(function(key512) {
  var data = new TextEncoder().encode('data to sign');
  return crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-512' }, key512, data);
})
.then(function(sig512) {
  check('sign HMAC-SHA512 length', sig512.length === 64);

  // AES-GCM tests
  var aesKey = new Uint8Array(32);
  for (var i = 0; i < 32; i++) aesKey[i] = i;
  return crypto.subtle.importKey('raw', aesKey, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
})
.then(function(aesGcmKey) {
  var iv = new Uint8Array(12);
  for (var i = 0; i < 12; i++) iv[i] = i + 100;
  var plaintext = new TextEncoder().encode('Hello, WebCrypto AES-GCM!');

  return crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, aesGcmKey, plaintext)
    .then(function(encrypted) { return { key: aesGcmKey, iv: iv, plaintext: plaintext, encrypted: encrypted }; });
})
.then(function(ctx) {
  check('AES-GCM encrypt returns data', ctx.encrypted instanceof Uint8Array);
  check('AES-GCM ciphertext has tag', ctx.encrypted.length === ctx.plaintext.length + 16);

  return crypto.subtle.decrypt({ name: 'AES-GCM', iv: ctx.iv }, ctx.key, ctx.encrypted);
})
.then(function(decrypted) {
  check('AES-GCM decrypt returns data', decrypted instanceof Uint8Array);
  var decryptedText = new TextDecoder().decode(decrypted);
  check('AES-GCM round-trip', decryptedText === 'Hello, WebCrypto AES-GCM!');

  // AES-CBC tests
  var aesKey = new Uint8Array(32);
  for (var i = 0; i < 32; i++) aesKey[i] = i;
  return crypto.subtle.importKey('raw', aesKey, { name: 'AES-CBC' }, false, ['encrypt', 'decrypt']);
})
.then(function(aesCbcKey) {
  var cbcIv = new Uint8Array(16);
  for (var i = 0; i < 16; i++) cbcIv[i] = i + 50;
  var cbcPlaintext = new TextEncoder().encode('Hello, WebCrypto AES-CBC!');

  return crypto.subtle.encrypt({ name: 'AES-CBC', iv: cbcIv }, aesCbcKey, cbcPlaintext)
    .then(function(encrypted) { return { key: aesCbcKey, iv: cbcIv, plaintext: cbcPlaintext, encrypted: encrypted }; });
})
.then(function(ctx) {
  check('AES-CBC encrypt returns data', ctx.encrypted instanceof Uint8Array);
  check('AES-CBC ciphertext padded', ctx.encrypted.length === 32);

  return crypto.subtle.decrypt({ name: 'AES-CBC', iv: ctx.iv }, ctx.key, ctx.encrypted);
})
.then(function(cbcDecrypted) {
  check('AES-CBC decrypt returns data', cbcDecrypted instanceof Uint8Array);
  var cbcDecryptedText = new TextDecoder().decode(cbcDecrypted);
  check('AES-CBC round-trip', cbcDecryptedText === 'Hello, WebCrypto AES-CBC!');

  // AES-128-GCM test
  var aes128Key = new Uint8Array(16);
  for (var i = 0; i < 16; i++) aes128Key[i] = i + 200;
  return crypto.subtle.importKey('raw', aes128Key, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
})
.then(function(aes128GcmKey) {
  var iv = new Uint8Array(12);
  for (var i = 0; i < 12; i++) iv[i] = i + 100;
  var plaintext = new TextEncoder().encode('Hello, WebCrypto AES-GCM!');

  return crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, aes128GcmKey, plaintext)
    .then(function(enc128) { return { key: aes128GcmKey, iv: iv, enc128: enc128 }; });
})
.then(function(ctx) {
  return crypto.subtle.decrypt({ name: 'AES-GCM', iv: ctx.iv }, ctx.key, ctx.enc128);
})
.then(function(dec128) {
  check('AES-128-GCM round-trip', new TextDecoder().decode(dec128) === 'Hello, WebCrypto AES-GCM!');

  // Deterministic HMAC check
  var keyData = new TextEncoder().encode('my-secret-key-for-hmac-testing!');
  return crypto.subtle.importKey('raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
})
.then(function(detKey) {
  var data = new TextEncoder().encode('data to sign');
  return Promise.all([
    crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-256' }, detKey, data),
    crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-256' }, detKey, data)
  ]);
})
.then(function(sigs) {
  check('HMAC deterministic', toHex(sigs[0]) === toHex(sigs[1]));
  done();
})
.catch(function(e) {
  console.log('ERROR: ' + e.message);
  done();
});
