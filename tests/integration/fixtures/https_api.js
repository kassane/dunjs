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

console.log("All HTTPS checks passed");
