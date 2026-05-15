// TLS module API tests
var passed = 0;
var total = 0;

function check(label, condition) {
  total++;
  if (condition) { passed++; console.log('PASS: ' + label); }
  else { console.log('FAIL: ' + label); }
}

var tls = require('tls');

// Module existence
check('tls module exists', typeof tls === 'object');
check('tls.connect is function', typeof tls.connect === 'function');
check('tls.getCiphers is function', typeof tls.getCiphers === 'function');
check('tls.TLSSocket is function', typeof tls.TLSSocket === 'function');
check('tls.createServer is function', typeof tls.createServer === 'function');

// Constants
check('DEFAULT_MIN_VERSION is TLSv1.2', tls.DEFAULT_MIN_VERSION === 'TLSv1.2');
check('DEFAULT_MAX_VERSION is TLSv1.3', tls.DEFAULT_MAX_VERSION === 'TLSv1.3');
check('DEFAULT_CIPHERS is string', typeof tls.DEFAULT_CIPHERS === 'string' && tls.DEFAULT_CIPHERS.length > 0);

// getCiphers returns array
var ciphers = tls.getCiphers();
check('getCiphers returns array', Array.isArray(ciphers));
check('getCiphers has entries', ciphers.length > 0);
check('cipher names are lowercase strings', typeof ciphers[0] === 'string' && ciphers[0] === ciphers[0].toLowerCase());

// TLSSocket constructor
var sock = new tls.TLSSocket();
check('TLSSocket creates object', typeof sock === 'object');
check('TLSSocket has encrypted', sock.encrypted === true);
check('TLSSocket has write method', typeof sock.write === 'function');
check('TLSSocket has end method', typeof sock.end === 'function');
check('TLSSocket has destroy method', typeof sock.destroy === 'function');
check('TLSSocket has on method', typeof sock.on === 'function');
check('TLSSocket has once method', typeof sock.once === 'function');
check('TLSSocket has setEncoding method', typeof sock.setEncoding === 'function');
check('TLSSocket has setTimeout method', typeof sock.setTimeout === 'function');
check('TLSSocket has getPeerCertificate method', typeof sock.getPeerCertificate === 'function');
check('TLSSocket has getCipher method', typeof sock.getCipher === 'function');
check('TLSSocket has getProtocol method', typeof sock.getProtocol === 'function');

// createServer throws helpful error
try {
  tls.createServer({});
  check('createServer throws', false);
} catch(e) {
  check('createServer throws', e.message.indexOf('https.createServer') >= 0);
}

console.log('\n' + passed + '/' + total + ' tls checks passed');
