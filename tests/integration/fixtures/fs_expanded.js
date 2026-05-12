// Expanded fs module integration test
const fs = require('fs');
const path = require('path');
const os = require('os');

var tmpDir = os.tmpdir() + '/dun-fs-test-' + Date.now();
fs.mkdirSync(tmpDir, {recursive: true});

// writeFileSync + readFileSync
fs.writeFileSync(tmpDir + '/test.txt', 'hello world');
console.log('write+read:', fs.readFileSync(tmpDir + '/test.txt') === 'hello world');

// appendFileSync
fs.appendFileSync(tmpDir + '/test.txt', '!!!');
console.log('append:', fs.readFileSync(tmpDir + '/test.txt') === 'hello world!!!');

// copyFileSync
fs.copyFileSync(tmpDir + '/test.txt', tmpDir + '/copy.txt');
console.log('copy:', fs.readFileSync(tmpDir + '/copy.txt') === 'hello world!!!');

// renameSync
fs.renameSync(tmpDir + '/copy.txt', tmpDir + '/renamed.txt');
console.log('rename:', fs.existsSync(tmpDir + '/renamed.txt') && !fs.existsSync(tmpDir + '/copy.txt'));

// accessSync
try {
    fs.accessSync(tmpDir + '/test.txt');
    console.log('access: true');
} catch(e) {
    console.log('access: false');
}

// realpathSync
var real = fs.realpathSync(tmpDir + '/test.txt');
console.log('realpath:', real.length > 0);

// readdirSync
var files = fs.readdirSync(tmpDir);
console.log('readdir count:', files.length);

// rmSync individual file
fs.rmSync(tmpDir + '/renamed.txt');
console.log('rmSync file:', !fs.existsSync(tmpDir + '/renamed.txt'));

// rmSync recursive
fs.rmSync(tmpDir, {recursive: true});
console.log('rmSync dir:', !fs.existsSync(tmpDir));

console.log('All expanded fs tests passed');
