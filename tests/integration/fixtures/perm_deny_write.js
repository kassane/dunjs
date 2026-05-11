// Verify that fs write operations are denied without --allow-write
const fs = require('fs');

try {
  fs.writeFileSync('/tmp/dun_perm_test.txt', 'data');
  console.log('SHOULD NOT REACH');
} catch (e) {
  console.log(e.message);
}
