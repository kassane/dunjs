// FS benchmark suite — cross-runtime comparison (DunJS / Bun / Deno / Node)
// Tests the 16 newly added fs functions plus core fs operations
// Run: ./build/dun run --allow-all tests/benchmarks/fs_bench.js
// Run: node tests/benchmarks/fs_bench.js
// Run: bun run tests/benchmarks/fs_bench.js
// Run: deno run --allow-all tests/benchmarks/fs_bench.js

const fs = require('fs');
const path = require('path');
const os = require('os');

const results = [];

function benchmark(name, fn, warmup, minMs) {
    warmup = warmup || 50;
    minMs = minMs || 200;
    try {
        for (var i = 0; i < warmup; i++) fn();
    } catch(e) {
        console.log('  ' + name + ': SKIP (' + e.message + ')');
        return;
    }

    var iters = 1;
    var elapsed = 0;
    while (elapsed < minMs) {
        var start = Date.now();
        for (var j = 0; j < iters; j++) fn();
        elapsed = Date.now() - start;
        if (elapsed < minMs) iters *= 2;
    }
    var nsPerOp = Math.round((elapsed * 1e6) / iters);
    var opsPerSec = Math.round((iters / elapsed) * 1000);
    results.push({ name: name, nsPerOp: nsPerOp, opsPerSec: opsPerSec, iters: iters });
    console.log('  ' + name + ': ' + nsPerOp + 'ns/op (' + opsPerSec.toLocaleString() + ' ops/sec)');
}

var tmpDir = os.tmpdir() + '/dun-fs-bench-' + Date.now();
fs.mkdirSync(tmpDir, {recursive: true});

// Prepare test files
fs.writeFileSync(tmpDir + '/small.txt', 'hello world');
fs.writeFileSync(tmpDir + '/medium.txt', 'x'.repeat(4096));
fs.writeFileSync(tmpDir + '/large.txt', 'y'.repeat(65536));

// ── Core FS Operations ─────────────────────────────────────────
console.log('\n=== Core FS ===');

benchmark('writeFileSync (small)', function() {
    fs.writeFileSync(tmpDir + '/bench_write.txt', 'benchmark data');
});

benchmark('readFileSync (small)', function() {
    fs.readFileSync(tmpDir + '/small.txt');
});

benchmark('readFileSync (4KB)', function() {
    fs.readFileSync(tmpDir + '/medium.txt');
});

benchmark('readFileSync (64KB)', function() {
    fs.readFileSync(tmpDir + '/large.txt');
});

benchmark('existsSync', function() {
    fs.existsSync(tmpDir + '/small.txt');
});

benchmark('statSync', function() {
    fs.statSync(tmpDir + '/small.txt');
});

benchmark('readdirSync', function() {
    fs.readdirSync(tmpDir);
});

// ── appendFileSync ──────────────────────────────────────────────
console.log('\n=== Append ===');

fs.writeFileSync(tmpDir + '/append_bench.txt', '');
benchmark('appendFileSync', function() {
    fs.appendFileSync(tmpDir + '/append_bench.txt', 'x');
});

// ── copyFileSync ────────────────────────────────────────────────
console.log('\n=== Copy ===');

benchmark('copyFileSync (small)', function() {
    fs.copyFileSync(tmpDir + '/small.txt', tmpDir + '/copy_bench.txt');
});

benchmark('copyFileSync (4KB)', function() {
    fs.copyFileSync(tmpDir + '/medium.txt', tmpDir + '/copy_bench2.txt');
});

// ── renameSync ──────────────────────────────────────────────────
console.log('\n=== Rename ===');

benchmark('renameSync', function() {
    fs.writeFileSync(tmpDir + '/rename_src.txt', 'data');
    fs.renameSync(tmpDir + '/rename_src.txt', tmpDir + '/rename_dst.txt');
});

// ── accessSync ──────────────────────────────────────────────────
console.log('\n=== Access ===');

benchmark('accessSync', function() {
    try { fs.accessSync(tmpDir + '/small.txt'); } catch(e) {}
});

// ── realpathSync ────────────────────────────────────────────────
console.log('\n=== Realpath ===');

benchmark('realpathSync', function() {
    fs.realpathSync(tmpDir + '/small.txt');
});

// ── NEW: lstatSync ──────────────────────────────────────────────
console.log('\n=== lstatSync ===');

benchmark('lstatSync', function() {
    fs.lstatSync(tmpDir + '/small.txt');
});

// ── NEW: symlinkSync + readlinkSync ─────────────────────────────
console.log('\n=== Symlink ===');

var symCounter = 0;
benchmark('symlinkSync + unlinkSync', function() {
    var lnk = tmpDir + '/sym_bench_' + symCounter++;
    fs.symlinkSync(tmpDir + '/small.txt', lnk);
    fs.unlinkSync(lnk);
});

fs.symlinkSync(tmpDir + '/small.txt', tmpDir + '/sym_read.txt');
benchmark('readlinkSync', function() {
    fs.readlinkSync(tmpDir + '/sym_read.txt');
});

// ── NEW: linkSync (hard link) ───────────────────────────────────
console.log('\n=== Hard Link ===');

var hlCounter = 0;
benchmark('linkSync + unlinkSync', function() {
    var lnk = tmpDir + '/hl_bench_' + hlCounter++;
    fs.linkSync(tmpDir + '/small.txt', lnk);
    fs.unlinkSync(lnk);
});

// ── NEW: truncateSync ───────────────────────────────────────────
console.log('\n=== Truncate ===');

fs.writeFileSync(tmpDir + '/trunc_bench.txt', 'x'.repeat(1024));
benchmark('truncateSync', function() {
    fs.truncateSync(tmpDir + '/trunc_bench.txt', 512);
});

// ── NEW: openSync + writeSync + closeSync ───────────────────────
console.log('\n=== FD Operations ===');

benchmark('openSync + closeSync', function() {
    var fd = fs.openSync(tmpDir + '/fd_bench.txt', 'w');
    fs.closeSync(fd);
});

benchmark('openSync + writeSync + closeSync', function() {
    var fd = fs.openSync(tmpDir + '/fd_bench2.txt', 'w');
    fs.writeSync(fd, 'benchmark fd write');
    fs.closeSync(fd);
});

benchmark('openSync + readSync + closeSync', function() {
    var fd = fs.openSync(tmpDir + '/small.txt', 'r');
    fs.readSync(fd, Buffer.alloc(100), 0, 11, 0);
    fs.closeSync(fd);
});

// ── NEW: fstatSync ──────────────────────────────────────────────
console.log('\n=== fstatSync ===');

var fstatFd = fs.openSync(tmpDir + '/small.txt', 'r');
benchmark('fstatSync', function() {
    fs.fstatSync(fstatFd);
});
fs.closeSync(fstatFd);

// ── NEW: fsyncSync + fdatasyncSync ──────────────────────────────
console.log('\n=== Sync ===');

benchmark('fsyncSync', function() {
    var fd = fs.openSync(tmpDir + '/sync_bench.txt', 'w');
    fs.writeSync(fd, 'sync data');
    fs.fsyncSync(fd);
    fs.closeSync(fd);
});

benchmark('fdatasyncSync', function() {
    var fd = fs.openSync(tmpDir + '/dsync_bench.txt', 'w');
    fs.writeSync(fd, 'datasync data');
    fs.fdatasyncSync(fd);
    fs.closeSync(fd);
});

// ── NEW: createReadStream ───────────────────────────────────────
console.log('\n=== Streams ===');

// Stream benchmarks are tricky across runtimes, test existence
try {
    var rs = fs.createReadStream(tmpDir + '/small.txt');
    console.log('  createReadStream: supported (' + (typeof rs.on) + ')');
    rs.destroy();
    rs.on('error', function() {});
} catch(e) {
    console.log('  createReadStream: ' + e.message);
}

try {
    var ws = fs.createWriteStream(tmpDir + '/ws_bench.txt');
    console.log('  createWriteStream: supported (' + (typeof ws.write) + ')');
    ws.destroy();
    ws.on('error', function() {});
} catch(e) {
    console.log('  createWriteStream: ' + e.message);
}

// ── NEW: watch ──────────────────────────────────────────────────
console.log('\n=== Watch ===');

try {
    var watcher = fs.watch(tmpDir + '/small.txt');
    console.log('  watch: supported (' + (typeof watcher.close) + ')');
    watcher.close();
} catch(e) {
    console.log('  watch: ' + e.message);
}

// ── Cleanup ─────────────────────────────────────────────────────
fs.rmSync(tmpDir, {recursive: true});

// ── Summary ─────────────────────────────────────────────────────
console.log('\n=== Summary ===');
console.log(results.length + ' benchmarks completed');
var totalOps = 0;
for (var i = 0; i < results.length; i++) totalOps += results[i].opsPerSec;
console.log('Total throughput: ' + totalOps.toLocaleString() + ' ops/sec');
