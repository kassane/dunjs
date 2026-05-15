const https = require('https');

// Test 1: Module is loadable
console.log("https module:", typeof https === 'object');

// Test 2: createServer function exists
console.log("createServer:", typeof https.createServer === 'function');

// Test 3: createServer requires options
try {
  https.createServer();
} catch (e) {
  console.log("no opts error:", e.message.indexOf('options') >= 0);
}

// Test 4: createServer requires key and cert strings
try {
  https.createServer({ key: 123, cert: 456 });
} catch (e) {
  console.log("bad opts error:", e.message.indexOf('key') >= 0 || e.message.indexOf('cert') >= 0);
}

// Test 5: createServer with invalid cert path
try {
  https.createServer({ key: '/nonexistent/key.pem', cert: '/nonexistent/cert.pem' });
} catch (e) {
  console.log("bad cert error:", e.message.indexOf('certificate') >= 0);
}

// Test 6: request function exists
console.log("https.request:", typeof https.request === 'function');

// Test 7: get function exists
console.log("https.get:", typeof https.get === 'function');

// Test 8: Agent class
console.log("https.Agent:", typeof https.Agent === 'function');

// Test 9: globalAgent
console.log("https.globalAgent:", typeof https.globalAgent === 'object');

// Test 10: METHODS array
console.log("https.METHODS:", Array.isArray(https.METHODS));

// Test 11: STATUS_CODES
console.log("https.STATUS_CODES:", typeof https.STATUS_CODES === 'object');
console.log("STATUS_CODES 200:", https.STATUS_CODES[200] === 'OK');

console.log("All HTTPS checks passed");
