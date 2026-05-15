// child_process.spawn and execFile tests
var passed = 0;
var total = 0;

function check(label, condition) {
  total++;
  if (condition) { passed++; console.log('PASS: ' + label); }
  else { console.log('FAIL: ' + label); }
}

var cp = require('child_process');

// spawn exists
check('spawn is function', typeof cp.spawn === 'function');
check('execFile is function', typeof cp.execFile === 'function');

// spawn echo
var child = cp.spawn('echo', ['hello', 'world']);
check('spawn returns object', typeof child === 'object');
check('spawn has pid', typeof child.pid === 'number' && child.pid > 0);
check('spawn has stdout', typeof child.stdout === 'object');
check('spawn has stderr', typeof child.stderr === 'object');
check('spawn has stdin', typeof child.stdin === 'object');
check('spawn has on method', typeof child.on === 'function');
check('spawn has once method', typeof child.once === 'function');
check('spawn has kill method', typeof child.kill === 'function');
check('spawn killed is false initially', child.killed === false);

// stdout has on
check('stdout has on method', typeof child.stdout.on === 'function');

// stderr has on
check('stderr has on method', typeof child.stderr.on === 'function');

// stdin has write/end
check('stdin has write method', typeof child.stdin.write === 'function');
check('stdin has end method', typeof child.stdin.end === 'function');

// execFile echo
var result = cp.execFile('echo', ['test', 'output'], function(err, stdout, stderr) {
  check('execFile callback called', true);
  check('execFile no error', err === null || err === undefined);
  check('execFile stdout has content', typeof stdout === 'string' && stdout.indexOf('test output') >= 0);
  check('execFile stderr is string', typeof stderr === 'string');

  console.log('\n' + passed + '/' + total + ' spawn/execFile checks passed');
});
