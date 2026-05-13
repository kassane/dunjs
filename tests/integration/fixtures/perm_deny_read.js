// Verify that fs operations are denied without --allow-read
const fs = require('fs');

try {
  fs.readFileSync('./perm_deny_read.js');
  console.log('SHOULD NOT REACH');
} catch (e) {
  console.log(e.message);
}

try {
  fs.existsSync('./perm_deny_read.js');
  console.log('SHOULD NOT REACH');
} catch (e) {
  console.log(e.message);
}
