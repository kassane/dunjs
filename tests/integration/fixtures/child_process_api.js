// Test child_process module
const cp = require('child_process');

// execSync
var out = cp.execSync('echo hello_child');
console.log('execSync: ' + out.toString().trim());

// spawnSync
var result = cp.spawnSync('echo', ['spawn_test']);
console.log('spawnSync status: ' + result.status);
console.log('spawnSync stdout: ' + result.stdout.toString().trim());
console.log('spawnSync error: ' + result.error);

// execSync with failure
try {
  cp.execSync('false');
  console.log('should not reach');
} catch(e) {
  console.log('exec fail caught: true');
}

console.log('child_process done');
