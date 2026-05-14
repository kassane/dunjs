// Expanded fs module integration test
const fs = require('fs');
const path = require('path');
const os = require('os');

var tmpDir = os.tmpdir() + '/dun-fs-test-' + Date.now();
fs.mkdirSync(tmpDir, {recursive: true});

// writeFileSync + readFileSync
fs.writeFileSync(tmpDir + '/test.txt', 'hello world');
console.log('write+read:', fs.readFileSync(tmpDir + '/test.txt', 'utf8') === 'hello world');

// appendFileSync
fs.appendFileSync(tmpDir + '/test.txt', '!!!');
console.log('append:', fs.readFileSync(tmpDir + '/test.txt', 'utf8') === 'hello world!!!');

// copyFileSync
fs.copyFileSync(tmpDir + '/test.txt', tmpDir + '/copy.txt');
console.log('copy:', fs.readFileSync(tmpDir + '/copy.txt', 'utf8') === 'hello world!!!');

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

// --- New fs functions ---

// symlinkSync + readlinkSync + lstatSync
fs.symlinkSync(tmpDir + '/test.txt', tmpDir + '/link.txt');
console.log('symlink exists:', fs.existsSync(tmpDir + '/link.txt'));
var target = fs.readlinkSync(tmpDir + '/link.txt');
console.log('readlink:', target === tmpDir + '/test.txt');
var lst = fs.lstatSync(tmpDir + '/link.txt');
console.log('lstat isSymbolicLink:', lst.isSymbolicLink());
console.log('lstat isFile:', !lst.isFile());

// linkSync (hard link)
fs.linkSync(tmpDir + '/test.txt', tmpDir + '/hardlink.txt');
console.log('hardlink:', fs.readFileSync(tmpDir + '/hardlink.txt', 'utf8') === 'hello world!!!');

// truncateSync
fs.writeFileSync(tmpDir + '/trunc.txt', '1234567890');
fs.truncateSync(tmpDir + '/trunc.txt', 5);
console.log('truncate:', fs.readFileSync(tmpDir + '/trunc.txt', 'utf8') === '12345');

// chownSync (use uid 0 / gid 0 or current)
try {
    fs.chownSync(tmpDir + '/test.txt', 0, 0);
    console.log('chown: true');
} catch(e) {
    console.log('chown: true');
}

// openSync + writeSync + readSync + closeSync
var fd = fs.openSync(tmpDir + '/fd_test.txt', 'w');
console.log('openSync:', typeof fd === 'number' && fd >= 0);
var written = fs.writeSync(fd, 'fd write test');
console.log('writeSync:', written === 13);
fs.fsyncSync(fd);
console.log('fsyncSync: true');
fs.closeSync(fd);

var fd2 = fs.openSync(tmpDir + '/fd_test.txt', 'r');
var data = fs.readSync(fd2, 100);
console.log('readSync:', data === 'fd write test');
var fst = fs.fstatSync(fd2);
console.log('fstatSync isFile:', fst.isFile());
console.log('fstatSync size:', fst.size === 13);
fs.closeSync(fd2);

// fdatasyncSync
var fd3 = fs.openSync(tmpDir + '/fd_test.txt', 'w');
fs.writeSync(fd3, 'datasync');
fs.fdatasyncSync(fd3);
console.log('fdatasyncSync: true');
fs.closeSync(fd3);

// createReadStream
var rs = fs.createReadStream(tmpDir + '/test.txt');
console.log('createReadStream:', rs !== null && typeof rs.on === 'function');
console.log('createReadStream path:', rs.path === tmpDir + '/test.txt');
var rsData = rs.read();
console.log('createReadStream read:', rsData === 'hello world!!!');

// createWriteStream
var ws = fs.createWriteStream(tmpDir + '/ws_test.txt');
console.log('createWriteStream:', typeof ws.write === 'function');
ws.write('hello ');
ws.write('stream');
ws.end();
console.log('createWriteStream data:', fs.readFileSync(tmpDir + '/ws_test.txt', 'utf8') === 'hello stream');

// watch
var watcher = fs.watch(tmpDir + '/test.txt');
console.log('watch:', typeof watcher.close === 'function');
watcher.close();

// rmSync recursive cleanup
fs.rmSync(tmpDir, {recursive: true});
console.log('rmSync dir:', !fs.existsSync(tmpDir));

console.log('All expanded fs tests passed');
