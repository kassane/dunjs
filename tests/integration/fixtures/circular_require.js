// Test circular require() handling (matches Node.js behavior)
const fs = require('fs');
const os = require('os');
const path = require('path');

var tmpDir = os.tmpdir() + '/dun-circ-' + Date.now();
fs.mkdirSync(tmpDir, { recursive: true });

// Classic circular dependency pattern from Node.js docs
fs.writeFileSync(tmpDir + '/a.js', [
    "console.log('a starting');",
    "exports.done = false;",
    "var b = require('./b.js');",
    "console.log('in a, b.done =', b.done);",
    "exports.done = true;",
    "console.log('a done');"
].join('\n'));

fs.writeFileSync(tmpDir + '/b.js', [
    "console.log('b starting');",
    "exports.done = false;",
    "var a = require('./a.js');",
    "console.log('in b, a.done =', a.done);",
    "exports.done = true;",
    "console.log('b done');"
].join('\n'));

fs.writeFileSync(tmpDir + '/main.js', [
    "console.log('main starting');",
    "var a = require('./a.js');",
    "var b = require('./b.js');",
    "console.log('in main, a.done =', a.done, ', b.done =', b.done);"
].join('\n'));

// Module.exports reassignment in circular deps
fs.writeFileSync(tmpDir + '/x.js', [
    "var y = require('./y.js');",
    "module.exports = { x: true, yVal: y.y };"
].join('\n'));

fs.writeFileSync(tmpDir + '/y.js', [
    "exports.y = true;"
].join('\n'));

// Run via child_process
var cp = require('child_process');
var dunBin = process.execPath || process.argv[0];

var result = cp.execSync(dunBin + ' run ' + tmpDir + '/main.js --allow-all', { encoding: 'utf8' });
process.stdout.write(result);

// Test module.exports reassignment
fs.writeFileSync(tmpDir + '/test_x.js',
    "var x = require('./x.js'); console.log('x:', x.x, 'yVal:', x.yVal);");
var result2 = cp.execSync(dunBin + ' run ' + tmpDir + '/test_x.js --allow-all', { encoding: 'utf8' });
process.stdout.write(result2);

// Require cache: second require returns same object
fs.writeFileSync(tmpDir + '/counter.js', [
    "var count = 0;",
    "module.exports = { inc: function() { return ++count; } };"
].join('\n'));

fs.writeFileSync(tmpDir + '/cache_test.js', [
    "var c1 = require('./counter.js');",
    "var c2 = require('./counter.js');",
    "console.log('same ref:', c1 === c2);",
    "console.log('count:', c1.inc(), c2.inc());"
].join('\n'));

var result3 = cp.execSync(dunBin + ' run ' + tmpDir + '/cache_test.js --allow-all', { encoding: 'utf8' });
process.stdout.write(result3);

// Cleanup
fs.rmSync(tmpDir, { recursive: true });
