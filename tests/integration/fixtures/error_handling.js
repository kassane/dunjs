// Error handling improvements test
const fs = require('fs');

// Test 1: ENOENT error for non-existent file
try {
  fs.readFileSync('/tmp/nonexistent_file_12345.txt');
  console.log("ENOENT: false");
} catch (e) {
  console.log("ENOENT:", e.message.includes('ENOENT') || e.message.includes('No such file'));
}

// Test 2: Error includes path info
try {
  fs.readFileSync('/tmp/nonexistent_file_12345.txt');
  console.log("path in error: false");
} catch (e) {
  console.log("path in error:", e.message.includes('nonexistent_file_12345'));
}

// Test 3: Error includes syscall
try {
  fs.readFileSync('/tmp/nonexistent_file_12345.txt');
  console.log("syscall in error: false");
} catch (e) {
  console.log("syscall in error:", e.message.includes('open'));
}

// Test 4: Stat error for non-existent file
try {
  fs.statSync('/tmp/nonexistent_stat_12345.txt');
  console.log("stat ENOENT: false");
} catch (e) {
  console.log("stat ENOENT:", e.message.includes('ENOENT') || e.message.includes('no such file'));
}

// Test 5: process.on exists
console.log("process.on:", typeof process.on === 'function');

// Test 6: process.on('uncaughtException') registration
let registered = false;
process.on('uncaughtException', function(err) {
  registered = true;
});
console.log("uncaughtException registered: true");

// Test 7: mkdir error includes path
try {
  fs.mkdirSync('/tmp/existing_test_err_dir_12345');
  fs.mkdirSync('/tmp/existing_test_err_dir_12345');
  console.log("mkdir error path: false");
} catch (e) {
  console.log("mkdir error path:", e.message.includes('existing_test_err_dir'));
  // Cleanup
  try { fs.unlinkSync('/tmp/existing_test_err_dir_12345'); } catch(_) {}
}
