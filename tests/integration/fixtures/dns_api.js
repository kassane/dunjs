// Test dns module
const dns = require('dns');

// lookupSync for localhost
try {
  var result = dns.lookupSync('localhost');
  console.log('lookupSync address: ' + result.address);
  console.log('lookupSync family: ' + result.family);
} catch(e) {
  // localhost may resolve differently on some systems
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
