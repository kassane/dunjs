import { existsSync, writeFileSync, readFileSync, mkdirSync, unlinkSync, readdirSync } from 'dun:fs';

const tmpFile = '/tmp/dun_test_fs_ops.txt';

// write + read
writeFileSync(tmpFile, 'hello dun');
console.log(readFileSync(tmpFile));

// exists
console.log(existsSync(tmpFile));
console.log(existsSync('/no/such/path/xyz'));

// unlink
unlinkSync(tmpFile);
console.log(existsSync(tmpFile));

// mkdir + readdir
const tmpDir = '/tmp/dun_test_dir_' + Date.now();
mkdirSync(tmpDir);
writeFileSync(tmpDir + '/a.txt', 'a');
writeFileSync(tmpDir + '/b.txt', 'b');
const entries = readdirSync(tmpDir).sort();
console.log(entries.join(','));

// cleanup
unlinkSync(tmpDir + '/a.txt');
unlinkSync(tmpDir + '/b.txt');
