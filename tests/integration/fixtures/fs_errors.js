const fs = require('fs');

// Test 1: ENOENT error from readFileSync
try {
  fs.readFileSync('/nonexistent/file.txt');
} catch (e) {
  console.log("1 instanceof Error:", e instanceof Error);
  console.log("1 code:", e.code);
  console.log("1 errno:", e.errno);
  console.log("1 syscall:", e.syscall);
  console.log("1 path:", e.path);
}

// Test 2: ENOENT from statSync
try {
  fs.statSync('/nonexistent/file.txt');
} catch (e) {
  console.log("2 code:", e.code);
  console.log("2 syscall:", e.syscall);
}

// Test 3: Permission error has code
try {
  fs.writeFileSync('/root/protected.txt', 'hello');
} catch (e) {
  console.log("3 code:", e.code);
  console.log("3 has path:", typeof e.path === 'string');
}

// Test 4: Error message format
try {
  fs.readFileSync('/no/such/file.txt');
} catch (e) {
  console.log("4 msg has code:", e.message.indexOf("ENOENT") >= 0);
}

// Test 5: Check error can be caught and re-thrown
try {
  try {
    fs.readFileSync('/no/such/dir/file');
  } catch (inner) {
    throw inner;
  }
} catch (outer) {
  console.log("5 rethrown code:", outer.code);
  console.log("5 rethrown errno:", outer.errno);
}

console.log("All fs error checks passed");
