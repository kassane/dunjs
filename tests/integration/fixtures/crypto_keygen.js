var crypto = require('crypto');
var checks = 0, passed = 0;
function check(name, cond) { checks++; if(cond){passed++;console.log('PASS: '+name);}else console.log('FAIL: '+name); }

check('generateKeyPairSync exists', typeof crypto.generateKeyPairSync === 'function');
check('createDiffieHellman exists', typeof crypto.createDiffieHellman === 'function');

// RSA key generation
var rsa = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
check('rsa publicKey', typeof rsa.publicKey === 'string');
check('rsa privateKey', typeof rsa.privateKey === 'string');
check('rsa publicKey starts with PEM', rsa.publicKey.indexOf('-----BEGIN PUBLIC KEY-----') === 0);
check('rsa privateKey starts with PEM', rsa.privateKey.indexOf('-----BEGIN PRIVATE KEY-----') === 0);

// Sign with generated RSA key
var sign = crypto.createSign('sha256');
sign.update('test data');
var sig = sign.sign(rsa.privateKey, 'hex');
check('rsa sign produces hex', sig.length > 0);

var verify = crypto.createVerify('sha256');
verify.update('test data');
check('rsa verify succeeds', verify.verify(rsa.publicKey, sig, 'hex'));

// DiffieHellman
var dh = crypto.createDiffieHellman(512);
check('dh object created', typeof dh === 'object');
check('dh.generateKeys', typeof dh.generateKeys === 'function');
check('dh.getPrime', typeof dh.getPrime === 'function');
check('dh.getGenerator', typeof dh.getGenerator === 'function');

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
