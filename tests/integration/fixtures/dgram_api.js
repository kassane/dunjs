// dgram (UDP) module API tests
var passed = 0;
var total = 0;

function check(label, condition) {
  total++;
  if (condition) { passed++; console.log('PASS: ' + label); }
  else { console.log('FAIL: ' + label); }
}

var dgram = require('dgram');

// Module existence
check('dgram module exists', typeof dgram === 'object');
check('dgram.createSocket is function', typeof dgram.createSocket === 'function');

// Create UDP4 socket
var sock = dgram.createSocket('udp4');
check('createSocket returns object', typeof sock === 'object');
check('socket has bind method', typeof sock.bind === 'function');
check('socket has send method', typeof sock.send === 'function');
check('socket has close method', typeof sock.close === 'function');
check('socket has address method', typeof sock.address === 'function');
check('socket has setBroadcast method', typeof sock.setBroadcast === 'function');
check('socket has setTTL method', typeof sock.setTTL === 'function');
check('socket has on method', typeof sock.on === 'function');
check('socket has once method', typeof sock.once === 'function');
check('socket has removeAllListeners method', typeof sock.removeAllListeners === 'function');
check('socket has ref method', typeof sock.ref === 'function');
check('socket has unref method', typeof sock.unref === 'function');
check('socket type is udp4', sock.type === 'udp4');

// Create with options object
var sock2 = dgram.createSocket({ type: 'udp4', reuseAddr: true });
check('createSocket with options object', typeof sock2 === 'object');

// Bind
sock.bind(0); // bind to any available port
var addr = sock.address();
check('address returns object after bind', typeof addr === 'object');
check('address has port', typeof addr.port === 'number' && addr.port > 0);
check('address has family', addr.family === 'IPv4');
check('address has address', typeof addr.address === 'string');

// Event registration
var eventRegistered = false;
sock.on('message', function(msg, rinfo) { eventRegistered = true; });
check('on returns socket for chaining', sock.on('close', function(){}) === sock);

// setBroadcast and setTTL (just verify they don't throw)
try {
  sock.setBroadcast(true);
  check('setBroadcast does not throw', true);
} catch(e) { check('setBroadcast does not throw', false); }

try {
  sock.setTTL(128);
  check('setTTL does not throw', true);
} catch(e) { check('setTTL does not throw', false); }

// Close
sock.close();
check('close does not throw', true);
sock2.close();

// dgram.Socket alias
check('dgram.Socket exists', typeof dgram.Socket === 'function');

console.log('\n' + passed + '/' + total + ' dgram checks passed');
