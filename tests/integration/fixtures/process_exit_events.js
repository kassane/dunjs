// Test process.on('exit') and process.on('beforeExit')
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// process.on('exit') receives exit code
var exitCalled = false;
var exitCode = -1;
process.on('exit', function(code) {
  exitCalled = true;
  exitCode = code;
  // This output happens at exit time
  console.log('exit handler called with code:', code);
});

// process.on('beforeExit') fires before exit
var beforeExitCalled = false;
process.on('beforeExit', function(code) {
  beforeExitCalled = true;
  console.log('beforeExit handler called with code:', code);
});

// Multiple exit listeners
var exitCount = 0;
process.on('exit', function() { exitCount++; });
process.on('exit', function() {
  console.log('exit listener count:', exitCount + 1);
});

// Verify process.on returns process (chainable)
var ret = process.on('exit', function() {});
check('process.on returns process', ret === process);

console.log('process_exit_events: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
