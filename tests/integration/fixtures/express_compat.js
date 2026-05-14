// Test express.js-like patterns to verify npm ecosystem compatibility
var checks = 0;
var passed = 0;

function check(name, condition) {
  checks++;
  if (condition) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

// --- Module system ---
check('require is function', typeof require === 'function');
check('require.resolve exists', typeof require.resolve === 'function');

// --- EventEmitter patterns (express uses extensively) ---
var events = require('events');
var ee = new events.EventEmitter();
check('EventEmitter constructor', ee instanceof events.EventEmitter);
check('setMaxListeners', typeof ee.setMaxListeners === 'function');
ee.setMaxListeners(50);
check('listenerCount', ee.listenerCount('test') === 0);
check('eventNames', Array.isArray(ee.eventNames()));
check('prependListener', typeof ee.prependListener === 'function');

// once() as promise
var onceResult = events.once(ee, 'data');
check('EventEmitter.once returns promise', onceResult instanceof Promise);

// --- Stream patterns (body parsing) ---
var stream = require('stream');
var readable = new stream.Readable({
  read: function() {
    this.push('hello');
    this.push(null);
  }
});
check('Readable instance', readable instanceof stream.Readable);
check('Readable has pipe', typeof readable.pipe === 'function');
check('Readable has on', typeof readable.on === 'function');

var transform = new stream.Transform({
  transform: function(chunk, enc, cb) {
    cb(null, chunk.toString().toUpperCase());
  }
});
check('Transform instance', transform instanceof stream.Transform);

// Pipeline (express uses this for streaming)
check('pipeline exists', typeof stream.pipeline === 'function');
check('stream.promises exists', typeof stream.promises === 'object');

// --- Buffer patterns (body parsing) ---
var buf1 = Buffer.from('hello');
check('Buffer.from string', buf1.length === 5);
check('Buffer.toString', buf1.toString() === 'hello');
check('Buffer.toString utf8', buf1.toString('utf8') === 'hello');
check('Buffer.toString hex', buf1.toString('hex') === '68656c6c6f');
check('Buffer.toString base64', buf1.toString('base64') === 'aGVsbG8=');

var buf2 = Buffer.from('776f726c64', 'hex');
check('Buffer.from hex', buf2.toString() === 'world');

var buf3 = Buffer.concat([buf1, buf2]);
check('Buffer.concat', buf3.toString() === 'helloworld');

check('Buffer.isBuffer', Buffer.isBuffer(buf1) === true);
check('Buffer.isBuffer string', Buffer.isBuffer('test') === false);
check('Buffer.byteLength', Buffer.byteLength('hello') === 5);
check('Buffer.alloc', Buffer.alloc(10).length === 10);
check('Buffer.allocUnsafe', Buffer.allocUnsafe(10).length === 10);

// --- URL patterns (routing) ---
var url = require('url');
var u = new URL('http://example.com/path?key=val#hash');
check('URL pathname', u.pathname === '/path');
check('URL search', u.search === '?key=val');
check('URL hash', u.hash === '#hash');
check('URL hostname', u.hostname === 'example.com');
check('URLSearchParams get', u.searchParams.get('key') === 'val');

// --- Path patterns (file serving) ---
var path = require('path');
check('path.join', path.join('/foo', 'bar', 'baz') === '/foo/bar/baz');
check('path.resolve', typeof path.resolve('.') === 'string');
check('path.extname', path.extname('file.js') === '.js');
check('path.basename', path.basename('/foo/bar.js') === 'bar.js');
check('path.dirname', path.dirname('/foo/bar.js') === '/foo');
check('path.parse', typeof path.parse('/foo/bar.js') === 'object');
check('path.format', typeof path.format === 'function');
check('path.relative', typeof path.relative === 'function');
check('path.isAbsolute', path.isAbsolute('/foo') === true);

// --- Crypto patterns (sessions, CSRF, cookies) ---
var crypto = require('crypto');
var hash = crypto.createHash('sha256').update('test').digest('hex');
check('sha256 hash', hash.length === 64);

var hmac = crypto.createHmac('sha256', 'secret').update('data').digest('hex');
check('hmac', hmac.length === 64);

var rb = crypto.randomBytes(32);
check('randomBytes', rb.length === 32);
check('randomUUID', crypto.randomUUID().length === 36);

check('timingSafeEqual', typeof crypto.timingSafeEqual === 'function');

// --- Querystring patterns ---
var qs = require('querystring');
var parsed = qs.parse('foo=bar&baz=qux');
check('qs.parse', parsed.foo === 'bar' && parsed.baz === 'qux');
check('qs.stringify', qs.stringify({a: '1', b: '2'}) === 'a=1&b=2');

// --- Process patterns (middleware, error handling) ---
check('process.env', typeof process.env === 'object');
check('process.cwd', typeof process.cwd() === 'string');
check('process.nextTick', typeof process.nextTick === 'function');
check('process.version', process.version.startsWith('v'));
check('process.versions', typeof process.versions === 'object');

// --- Util patterns ---
var util = require('util');
check('util.format', util.format('hello %s', 'world') === 'hello world');
check('util.inherits', typeof util.inherits === 'function');
check('util.promisify', typeof util.promisify === 'function');
check('util.types', typeof util.types === 'object');
check('util.deprecate', typeof util.deprecate === 'function');

// --- HTTP patterns ---
var http = require('http');
check('http.createServer', typeof http.createServer === 'function');
check('http.STATUS_CODES', typeof http.STATUS_CODES === 'object');
check('http.STATUS_CODES 200', http.STATUS_CODES[200] === 'OK');
check('http.STATUS_CODES 404', http.STATUS_CODES[404] === 'Not Found');
check('http.METHODS', Array.isArray(http.METHODS));
check('http.METHODS includes GET', http.METHODS.indexOf('GET') >= 0);
check('http.Agent', typeof http.Agent === 'function');
check('http.globalAgent', typeof http.globalAgent === 'object');

// --- Assert patterns (testing frameworks) ---
var assert = require('assert');
check('assert ok', typeof assert === 'function');
check('assert.strictEqual', typeof assert.strictEqual === 'function');
check('assert.deepStrictEqual', typeof assert.deepStrictEqual === 'function');
check('assert.throws', typeof assert.throws === 'function');

// --- OS patterns (deployment detection) ---
var os = require('os');
check('os.platform', typeof os.platform() === 'string');
check('os.hostname', typeof os.hostname() === 'string');
check('os.tmpdir', typeof os.tmpdir() === 'string');
check('os.cpus', Array.isArray(os.cpus()));
check('os.totalmem', os.totalmem() > 0);
check('os.userInfo', typeof os.userInfo() === 'object');
check('os.networkInterfaces', typeof os.networkInterfaces() === 'object');

// --- Console patterns ---
check('console.log', typeof console.log === 'function');
check('console.error', typeof console.error === 'function');
check('console.warn', typeof console.warn === 'function');
check('console.time', typeof console.time === 'function');
check('console.timeEnd', typeof console.timeEnd === 'function');

// --- Timer patterns (rate limiting, timeouts) ---
check('setTimeout', typeof setTimeout === 'function');
check('setInterval', typeof setInterval === 'function');
check('clearTimeout', typeof clearTimeout === 'function');
check('clearInterval', typeof clearInterval === 'function');
check('setImmediate', typeof setImmediate === 'function');

// --- Promise patterns ---
check('Promise.all', typeof Promise.all === 'function');
check('Promise.race', typeof Promise.race === 'function');
check('Promise.allSettled', typeof Promise.allSettled === 'function');

// --- JSON patterns ---
var obj = JSON.parse('{"a":1,"b":"hello","c":[1,2,3]}');
check('JSON.parse', obj.a === 1 && obj.b === 'hello');
check('JSON.stringify', JSON.stringify(obj) === '{"a":1,"b":"hello","c":[1,2,3]}');

// --- Error handling patterns ---
try {
  JSON.parse('invalid json');
  check('JSON.parse error', false);
} catch(e) {
  check('JSON.parse error', e instanceof SyntaxError);
}

// --- Symbol patterns ---
check('Symbol.iterator', typeof Symbol.iterator === 'symbol');
check('Symbol.asyncIterator', typeof Symbol.asyncIterator === 'symbol');
check('Symbol.hasInstance', typeof Symbol.hasInstance === 'symbol');
check('Symbol.toPrimitive', typeof Symbol.toPrimitive === 'symbol');

// --- Globals ---
check('globalThis', typeof globalThis === 'object');
check('TextEncoder', typeof TextEncoder === 'function');
check('TextDecoder', typeof TextDecoder === 'function');
check('atob', typeof atob === 'function');
check('btoa', typeof btoa === 'function');
check('structuredClone', typeof structuredClone === 'function');

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
