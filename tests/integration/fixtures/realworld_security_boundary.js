// Real-world: Security boundary tests — verify permission denials work correctly

var errors = [];

// Try fs operations without permission
try {
  var fs = require('fs');
  fs.readFileSync('/etc/passwd');
  errors.push('read should have been denied');
} catch (e) {
  console.log('read denied: ' + (e.message.indexOf('allow-read') !== -1 || e.message.indexOf('denied') !== -1));
}

// Try write without permission
try {
  var fs2 = require('fs');
  fs2.writeFileSync('/tmp/dun_security_test.txt', 'hack');
  errors.push('write should have been denied');
} catch (e) {
  console.log('write denied: ' + (e.message.indexOf('allow-write') !== -1 || e.message.indexOf('denied') !== -1));
}

// Built-in modules should still be accessible (no fs permission needed to load them)
var path = require('path');
console.log('path.join works: ' + (path.join('a', 'b') === 'a/b'));

var crypto = require('crypto');
var uuid = crypto.randomUUID();
console.log('crypto works: ' + (uuid.length === 36));

// Math and JS builtins always work (no permissions needed)
console.log('math works: ' + (Math.max(1, 2, 3) === 3));
console.log('json works: ' + (JSON.parse('{"a":1}').a === 1));
console.log('date works: ' + (typeof Date.now() === 'number'));

if (errors.length > 0) {
  console.log('ERRORS: ' + errors.join(', '));
} else {
  console.log('all security checks passed');
}
