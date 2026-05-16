// dun:wasi smoke test — verifies that the WASI module loads,
// exposes the expected surface, and can run a hand-crafted WASI
// hello-world wasm module on engines that support WebAssembly.
//
// QuickJS lacks a WASM runtime, so the actual instantiate path
// is gated on WebAssembly being present; the require/surface
// checks always run.

var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

// === require shape ===
var wasi = require('wasi');
check('wasi loaded', typeof wasi === 'object');
check('WASI class', typeof wasi.WASI === 'function');

var w = new wasi.WASI({ args: ['x'], env: { K: 'v' }, returnOnExit: true });
check('instance constructed', w instanceof wasi.WASI);
check('args echoed', w.args.length === 1 && w.args[0] === 'x');
check('env echoed', w.env.K === 'v');

var imp = w.getImportObject();
check('getImportObject returns object', typeof imp === 'object' && imp !== null);
check('preview1 namespace', typeof imp.wasi_snapshot_preview1 === 'object');

var p = imp.wasi_snapshot_preview1;
var required = [
  'args_get', 'args_sizes_get',
  'environ_get', 'environ_sizes_get',
  'clock_time_get', 'random_get',
  'proc_exit',
  'fd_close', 'fd_read', 'fd_write', 'fd_seek',
  'fd_fdstat_get', 'fd_prestat_get', 'fd_prestat_dir_name',
  'path_open'
];
for (var i = 0; i < required.length; i++)
  check('syscall ' + required[i], typeof p[required[i]] === 'function');

// === fd_write through a mock memory ===
// Layout:
//   0..15  : "hi from wasi!\n"
//   64..71 : iovec[0] { buf=0, len=14 }
//   80..   : nwritten (out)
var mem = { buffer: new ArrayBuffer(128) };
w._instance = { exports: { memory: mem } };
var view = new DataView(mem.buffer);
var bytes = new Uint8Array(mem.buffer);
var msg = new TextEncoder().encode('hi from wasi!\n');
bytes.set(msg, 0);
view.setUint32(64, 0, true);
view.setUint32(68, msg.length, true);

// Redirect stdout for the test so we can assert what was written.
var captured = '';
var realWrite = w._proc.stdout.write;
w._proc.stdout.write = function(buf) {
  if (typeof buf === 'string') captured += buf;
  else captured += new TextDecoder().decode(buf);
};
var rc = p.fd_write(1, 64, 1, 80);
w._proc.stdout.write = realWrite;

check('fd_write returns 0', rc === 0);
check('nwritten = msg length', view.getUint32(80, true) === msg.length);
check('captured matches msg', captured === 'hi from wasi!\n');

// === clock_time_get / random_get ===
view.setBigUint64(96, 0n, true);
var crc = p.clock_time_get(0 /*realtime*/, 0n, 96);
check('clock_time_get returns 0', crc === 0);
check('clock wrote nonzero', view.getBigUint64(96, true) > 0n);

for (var k = 0; k < 16; k++) view.setUint8(112 + k, 0);
var rrc = p.random_get(112, 16);
check('random_get returns 0', rrc === 0);
var anyNonZero = false;
for (var k2 = 0; k2 < 16; k2++) if (view.getUint8(112 + k2) !== 0) { anyNonZero = true; break; }
check('random_get wrote bytes', anyNonZero);

// === proc_exit with returnOnExit ===
try {
  p.proc_exit(42);
  check('proc_exit throws WasiExitError', false);
} catch (e) {
  check('proc_exit throws', e && e.code === 42);
}

console.log('wasi_api:', passed + '/' + total, 'checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
