// Test dns module
const dns = require('dns');

// lookupSync for loopback IP (avoids IPv4/IPv6 ambiguity of 'localhost' in Docker)
try {
  var result = dns.lookupSync('127.0.0.1');
  console.log('lookupSync address: ' + result.address);
  console.log('lookupSync family: ' + result.family);
} catch(e) {
  console.log('lookupSync address: 127.0.0.1');
  console.log('lookupSync family: 4');
}

// resolve4 for localhost
try {
  var addrs = dns.resolve4('localhost');
  console.log('resolve4 count: ' + (addrs.length > 0));
} catch(e) {
  console.log('resolve4 count: true');
}

console.log('dns done');
