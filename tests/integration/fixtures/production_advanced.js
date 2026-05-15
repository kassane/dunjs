// Advanced production parity tests — HTTP buffers, fs withFileTypes, spawn env, net options
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// === fs.readdirSync withFileTypes ===
try {
  var fs = require('fs');

  // withFileTypes returns Dirent objects
  var entries = fs.readdirSync('.', { withFileTypes: true });
  check('readdirSync withFileTypes returns array', Array.isArray(entries));
  check('readdirSync withFileTypes length > 0', entries.length > 0);

  var first = entries[0];
  check('Dirent has name', typeof first.name === 'string');
  check('Dirent has isFile', typeof first.isFile === 'function');
  check('Dirent has isDirectory', typeof first.isDirectory === 'function');
  check('Dirent has isSymbolicLink', typeof first.isSymbolicLink === 'function');

  // Find known entries
  var buildDir = entries.filter(function(e) { return e.name === 'build'; })[0];
  var dubJson = entries.filter(function(e) { return e.name === 'dub.json'; })[0];

  if (buildDir) {
    check('build isDirectory', buildDir.isDirectory());
    check('build !isFile', !buildDir.isFile());
  } else { total += 2; }

  if (dubJson) {
    check('dub.json isFile', dubJson.isFile());
    check('dub.json !isDirectory', !dubJson.isDirectory());
  } else { total += 2; }

  // Without withFileTypes (regression check)
  var plain = fs.readdirSync('.');
  check('readdirSync plain returns strings', typeof plain[0] === 'string');

  // node_modules withFileTypes
  var nmEntries = fs.readdirSync('node_modules', { withFileTypes: true });
  var nmDirs = nmEntries.filter(function(e) { return e.isDirectory(); });
  check('node_modules has directories', nmDirs.length > 0);
} catch(e) { console.log('FAIL: fs withFileTypes:', e.message); total += 13; }

// === child_process spawnSync with trailing newlines ===
try {
  var cp = require('child_process');

  // Trailing newline preserved
  var r1 = cp.spawnSync('echo', ['hello']);
  check('spawnSync preserves trailing newline', r1.stdout === 'hello\n');

  // Multi-line output preserved
  var r2 = cp.spawnSync('printf', ['line1\\nline2\\n']);
  check('spawnSync multi-line', r2.stdout === 'line1\nline2\n');

  // Empty output
  var r3 = cp.spawnSync('true', []);
  check('spawnSync empty output', r3.stdout === '');

  // Status code
  var r4 = cp.spawnSync('false', []);
  check('spawnSync exit code', r4.status !== 0);

  // env option
  var r5 = cp.spawnSync('env', [], { env: { MY_VAR: 'test123', PATH: '/usr/bin' } });
  check('spawnSync env option', r5.stdout.indexOf('MY_VAR=test123') >= 0);

  // execSync trailing newline preserved
  var r6 = cp.execSync('echo world');
  check('execSync output', r6.indexOf('world') >= 0);
} catch(e) { console.log('FAIL: child_process:', e.message); total += 6; }

// === net.connect options form ===
try {
  var net = require('net');

  // net.connect({port, host}) should be a function
  check('net.connect is function', typeof net.connect === 'function');
  check('net.createConnection is function', typeof net.createConnection === 'function');

  // Socket constructor
  check('net.Socket is function', typeof net.Socket === 'function');

  // net.isIP
  check('net.isIP("1.2.3.4")', net.isIP('1.2.3.4') === 4);
  check('net.isIPv4("1.2.3.4")', net.isIPv4('1.2.3.4') === true);
  check('net.isIPv6("::1")', net.isIPv6('::1') === true);
  check('net.isIP("invalid")', net.isIP('invalid') === 0);
} catch(e) { console.log('FAIL: net:', e.message); total += 7; }

// === Buffer advanced ===
try {
  // Buffer.from with base64
  var b64 = Buffer.from('SGVsbG8gV29ybGQ=', 'base64');
  check('Buffer base64 decode', b64.toString() === 'Hello World');

  // Buffer.from with hex
  var hex = Buffer.from('48656c6c6f', 'hex');
  check('Buffer hex decode', hex.toString() === 'Hello');

  // Buffer.concat
  var a = Buffer.from('Hello');
  var b = Buffer.from(' World');
  var c = Buffer.concat([a, b]);
  check('Buffer.concat', c.toString() === 'Hello World');

  // Buffer.alloc with fill
  var filled = Buffer.alloc(5, 0x41);
  check('Buffer.alloc fill', filled.toString() === 'AAAAA');

  // Buffer.isBuffer
  check('Buffer.isBuffer', Buffer.isBuffer(Buffer.from('x')));
  check('Buffer.isBuffer false', !Buffer.isBuffer('x'));

  // Buffer.byteLength
  check('Buffer.byteLength', Buffer.byteLength('hello') === 5);

  // Buffer slice (subarray)
  var sl = Buffer.from('Hello World').slice(6);
  check('Buffer.slice', sl.toString() === 'World');

  // Buffer comparison
  var cmp = Buffer.from('abc').compare(Buffer.from('abc'));
  check('Buffer.compare equal', cmp === 0);
  check('Buffer.compare less', Buffer.from('abc').compare(Buffer.from('abd')) < 0);

  // Buffer.from array
  var arr = Buffer.from([72, 101, 108, 108, 111]);
  check('Buffer.from array', arr.toString() === 'Hello');

  // Buffer indexOf
  var buf = Buffer.from('Hello World');
  check('Buffer.indexOf', buf.indexOf('World') === 6);
  check('Buffer.indexOf not found', buf.indexOf('xyz') === -1);
} catch(e) { console.log('FAIL: Buffer advanced:', e.message); total += 14; }

// === crypto advanced ===
try {
  var crypto = require('crypto');

  // Multiple hash algorithms
  var sha256 = crypto.createHash('sha256').update('test').digest('hex');
  check('sha256', sha256.length === 64);

  var sha512 = crypto.createHash('sha512').update('test').digest('hex');
  check('sha512', sha512.length === 128);

  var md5 = crypto.createHash('md5').update('test').digest('hex');
  check('md5', md5.length === 32);

  // HMAC
  var hmac = crypto.createHmac('sha256', 'secret').update('data').digest('hex');
  check('hmac-sha256', hmac.length === 64);

  // randomBytes
  var rb = crypto.randomBytes(16);
  check('randomBytes length', rb.length === 16);
  check('randomBytes is Buffer', Buffer.isBuffer(rb));

  // randomUUID
  var uuid = crypto.randomUUID();
  check('randomUUID format', uuid.length === 36 && uuid[14] === '4');

  // pbkdf2Sync
  check('pbkdf2Sync exists', typeof crypto.pbkdf2Sync === 'function');

  // timingSafeEqual
  var a = Buffer.from('hello');
  var b = Buffer.from('hello');
  check('timingSafeEqual', crypto.timingSafeEqual(a, b) === true);

  // getCiphers, getHashes
  check('getCiphers array', Array.isArray(crypto.getCiphers()));
  check('getHashes array', Array.isArray(crypto.getHashes()));
} catch(e) { console.log('FAIL: crypto advanced:', e.message); total += 12; }

// === Stream advanced ===
try {
  var stream = require('stream');

  // Stream module returns a function (constructor)
  check('stream is function', typeof stream === 'function');

  // Stream.Readable
  check('stream.Readable exists', typeof stream.Readable === 'function');
  check('stream.Writable exists', typeof stream.Writable === 'function');
  check('stream.Transform exists', typeof stream.Transform === 'function');
  check('stream.Duplex exists', typeof stream.Duplex === 'function');
  check('stream.PassThrough exists', typeof stream.PassThrough === 'function');
  check('stream.pipeline exists', typeof stream.pipeline === 'function');
  check('stream.finished exists', typeof stream.finished === 'function');
} catch(e) { console.log('FAIL: stream:', e.message); total += 8; }

// === EventEmitter patterns ===
try {
  var events = require('events');
  var EventEmitter = events.EventEmitter || events;

  var ee = new EventEmitter();

  // Event ordering
  var order = [];
  ee.on('test', function() { order.push(1); });
  ee.on('test', function() { order.push(2); });
  ee.prependListener('test', function() { order.push(0); });
  ee.emit('test');
  check('EventEmitter ordering', order.join(',') === '0,1,2');

  // once
  var onceCount = 0;
  ee.once('once-test', function() { onceCount++; });
  ee.emit('once-test');
  ee.emit('once-test');
  check('EventEmitter once', onceCount === 1);

  // removeListener
  var removed = false;
  var fn = function() { removed = true; };
  ee.on('rm', fn);
  ee.removeListener('rm', fn);
  ee.emit('rm');
  check('EventEmitter removeListener', removed === false);

  // listenerCount
  ee.on('lc', function() {});
  ee.on('lc', function() {});
  check('EventEmitter listenerCount', ee.listenerCount('lc') === 2);

  // eventNames
  check('EventEmitter eventNames', Array.isArray(ee.eventNames()));

  // maxListeners
  ee.setMaxListeners(50);
  check('EventEmitter maxListeners', ee.getMaxListeners() === 50);

  // error event
  var errorCaught = false;
  ee.on('error', function(e) { errorCaught = true; });
  ee.emit('error', new Error('test'));
  check('EventEmitter error event', errorCaught === true);
} catch(e) { console.log('FAIL: EventEmitter:', e.message); total += 7; }

// === URL advanced ===
try {
  var u = new URL('https://user:pass@example.com:8080/path?key=value#hash');
  check('URL protocol', u.protocol === 'https:');
  check('URL hostname', u.hostname === 'example.com');
  check('URL port', u.port === '8080');
  check('URL pathname', u.pathname === '/path');
  check('URL search', u.search === '?key=value');
  check('URL hash', u.hash === '#hash');
  check('URL username', u.username === 'user');
  check('URL password', u.password === 'pass');

  // URLSearchParams
  var sp = new URLSearchParams('a=1&b=2&a=3');
  check('URLSearchParams get', sp.get('a') === '1');
  check('URLSearchParams getAll', sp.getAll('a').length === 2);
  check('URLSearchParams has', sp.has('b'));
  check('URLSearchParams toString', sp.toString() === 'a=1&b=2&a=3');
} catch(e) { console.log('FAIL: URL:', e.message); total += 12; }

// === process advanced ===
try {
  check('process.pid is number', typeof process.pid === 'number');
  check('process.arch is string', typeof process.arch === 'string');
  check('process.platform is string', typeof process.platform === 'string');
  check('process.version starts with v', process.version.charAt(0) === 'v');
  check('process.env is object', typeof process.env === 'object');
  check('process.cwd is function', typeof process.cwd === 'function');
  check('process.exit is function', typeof process.exit === 'function');
  check('process.argv is array', Array.isArray(process.argv));
  check('process.hrtime is function', typeof process.hrtime === 'function');
  check('process.memoryUsage is function', typeof process.memoryUsage === 'function');
} catch(e) { console.log('FAIL: process:', e.message); total += 10; }

// === JSON edge cases ===
try {
  // JSON.stringify with replacer
  var obj = { a: 1, b: 2, c: 3 };
  var r = JSON.stringify(obj, ['a', 'c']);
  check('JSON.stringify replacer array', r === '{"a":1,"c":3}');

  // JSON.stringify with space
  var r2 = JSON.stringify({ x: 1 }, null, 2);
  check('JSON.stringify space', r2.indexOf('\n') >= 0);

  // JSON.parse reviver
  var r3 = JSON.parse('{"a":1,"b":2}', function(k, v) {
    return typeof v === 'number' ? v * 2 : v;
  });
  check('JSON.parse reviver', r3.a === 2 && r3.b === 4);

  // JSON with special chars
  var r4 = JSON.stringify({ msg: 'hello "world"\nnewline\ttab' });
  check('JSON special chars', r4.indexOf('\\n') >= 0 && r4.indexOf('\\t') >= 0);
} catch(e) { console.log('FAIL: JSON:', e.message); total += 4; }

// === Error types ===
try {
  check('TypeError', new TypeError('x') instanceof TypeError);
  check('RangeError', new RangeError('x') instanceof RangeError);
  check('SyntaxError', new SyntaxError('x') instanceof SyntaxError);
  check('ReferenceError', new ReferenceError('x') instanceof ReferenceError);
  check('URIError', new URIError('x') instanceof URIError);
  check('Error.cause', new Error('x', { cause: 'reason' }).cause === 'reason');
  check('Error.stack', typeof new Error('x').stack === 'string');
} catch(e) { console.log('FAIL: Error types:', e.message); total += 7; }

// === Regex advanced ===
try {
  // Named groups
  var m = 'hello-123'.match(/(?<word>\w+)-(?<num>\d+)/);
  check('regex named groups', m.groups.word === 'hello' && m.groups.num === '123');

  // matchAll
  var iter = 'a1b2c3'.matchAll(/[a-z](\d)/g);
  var results = Array.from(iter);
  check('matchAll count', results.length === 3);
  check('matchAll groups', results[0][1] === '1' && results[2][1] === '3');

  // lookbehind
  var lb = 'price: $100'.match(/(?<=\$)\d+/);
  check('regex lookbehind', lb[0] === '100');

  // dotAll flag
  var ds = 'hello\nworld'.match(/hello.world/s);
  check('regex dotAll', ds !== null);
} catch(e) { console.log('FAIL: regex:', e.message); total += 5; }

// === Promise patterns ===
try {
  // Promise.resolve
  check('Promise.resolve', typeof Promise.resolve(42).then === 'function');
  var rp = Promise.reject('err'); rp.catch(function(){}); check('Promise.reject', typeof rp.then === 'function');
  check('Promise.all', typeof Promise.all([]).then === 'function');
  check('Promise.race', typeof Promise.race([]).then === 'function');
  check('Promise.allSettled', typeof Promise.allSettled([]).then === 'function');
  check('Promise.any', typeof Promise.any !== 'undefined');
  check('Promise.withResolvers', typeof Promise.withResolvers === 'function');
} catch(e) { console.log('FAIL: Promise:', e.message); total += 7; }

// === Map/Set/WeakMap/WeakSet ===
try {
  var m = new Map([['a', 1], ['b', 2]]);
  check('Map size', m.size === 2);
  check('Map get', m.get('a') === 1);
  check('Map has', m.has('b'));

  var s = new Set([1, 2, 3, 2, 1]);
  check('Set size', s.size === 3);
  check('Set has', s.has(2));

  check('WeakMap exists', typeof WeakMap === 'function');
  check('WeakSet exists', typeof WeakSet === 'function');
} catch(e) { console.log('FAIL: Map/Set:', e.message); total += 7; }

console.log('production_advanced: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
