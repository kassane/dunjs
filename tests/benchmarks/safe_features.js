// Safe features parity test — cross-runtime comparison
// Tests safety-critical APIs, Web APIs, Node.js compat, ES2023+
// Run: ./build/dun run --allow-all tests/benchmarks/safe_features.js
// Run: node tests/benchmarks/safe_features.js
// Run: bun run tests/benchmarks/safe_features.js
// Run: deno run --allow-all --unstable-detect-cjs tests/benchmarks/safe_features.js

var pass = 0, fail = 0;
function test(name, fn) {
    try {
        if (fn()) { pass++; }
        else { fail++; console.log('FAIL: ' + name); }
    } catch(e) {
        fail++; console.log('FAIL: ' + name + ' (' + e.message + ')');
    }
}

// ══════════════════════════════════════════════════════════════
// 1. Core JS Safety (typeof, null handling, error types)
// ══════════════════════════════════════════════════════════════
console.log('=== Core JS Safety ===');

test('typeof undefined', function() { return typeof undefined === 'undefined'; });
test('typeof null', function() { return typeof null === 'object'; });
test('typeof NaN', function() { return typeof NaN === 'number' && isNaN(NaN); });
test('typeof Infinity', function() { return typeof Infinity === 'number' && !isFinite(Infinity); });
test('Number.isFinite', function() { return Number.isFinite(42) && !Number.isFinite(Infinity); });
test('Number.isNaN', function() { return Number.isNaN(NaN) && !Number.isNaN(42); });
test('Number.isInteger', function() { return Number.isInteger(42) && !Number.isInteger(42.5); });
test('Number.isSafeInteger', function() { return Number.isSafeInteger(42) && !Number.isSafeInteger(2**53); });
test('parseInt edge cases', function() { return parseInt('0x10') === 16 && isNaN(parseInt('not_a_num')); });
test('JSON.parse safety', function() {
    try { JSON.parse('{invalid}'); return false; } catch(e) { return e instanceof SyntaxError; }
});
test('JSON.stringify circular ref', function() {
    var obj = {}; obj.self = obj;
    try { JSON.stringify(obj); return false; } catch(e) { return true; }
});
test('Error types', function() {
    return new TypeError('t') instanceof Error &&
           new RangeError('r') instanceof Error &&
           new SyntaxError('s') instanceof Error &&
           new ReferenceError('r') instanceof Error;
});
test('Error.cause', function() { return new Error('a', {cause: 'b'}).cause === 'b'; });
test('Error.stack', function() { return typeof new Error('test').stack === 'string'; });

// ══════════════════════════════════════════════════════════════
// 2. String Safety
// ══════════════════════════════════════════════════════════════
console.log('\n=== String Safety ===');

test('Unicode handling', function() { return '\u{1F600}'.length === 2; });
test('String.fromCodePoint', function() { return String.fromCodePoint(128512) === '\u{1F600}'; });
test('codePointAt', function() { return '\u{1F600}'.codePointAt(0) === 128512; });
test('normalize NFC', function() { return typeof 'test'.normalize === 'function'; });
test('includes', function() { return 'hello world'.includes('world'); });
test('startsWith/endsWith', function() { return 'hello'.startsWith('hel') && 'hello'.endsWith('llo'); });
test('repeat', function() { return 'ab'.repeat(3) === 'ababab'; });
test('padStart/padEnd', function() { return '1'.padStart(3,'0') === '001' && '1'.padEnd(3,'0') === '100'; });
test('trimStart/trimEnd', function() { return '  hi  '.trimStart() === 'hi  ' && '  hi  '.trimEnd() === '  hi'; });
test('replaceAll', function() { return 'aaa'.replaceAll('a','b') === 'bbb'; });
test('at negative index', function() { return 'hello'.at(-1) === 'o'; });
test('matchAll', function() { return [...'aaa'.matchAll(/a/g)].length === 3; });

// ══════════════════════════════════════════════════════════════
// 3. Array Safety
// ══════════════════════════════════════════════════════════════
console.log('\n=== Array Safety ===');

test('Array.isArray', function() { return Array.isArray([]) && !Array.isArray({}); });
test('Array.from iterable', function() { return Array.from('abc').join('') === 'abc'; });
test('Array.of', function() { return Array.of(1,2,3).length === 3; });
test('flat/flatMap', function() { return [1,[2,[3]]].flat(Infinity).length === 3; });
test('findLast/findLastIndex', function() { return [1,2,3].findLast(function(x){return x<3;}) === 2; });
test('at negative', function() { return [1,2,3].at(-1) === 3; });
test('structuredClone array', function() {
    var a = [1, {b: 2}, [3]];
    var b = structuredClone(a);
    b[1].b = 99;
    return a[1].b === 2 && b[1].b === 99;
});
test('spread + rest', function() {
    var arr = [1,2,3];
    var copy = [...arr];
    return copy.length === 3 && copy !== arr;
});
test('Array.prototype.fill', function() { return new Array(3).fill(0).join('') === '000'; });
test('Array.prototype.copyWithin', function() { return [1,2,3,4,5].copyWithin(0,3).join(',') === '4,5,3,4,5'; });

// ══════════════════════════════════════════════════════════════
// 4. Object Safety
// ══════════════════════════════════════════════════════════════
console.log('\n=== Object Safety ===');

test('Object.freeze', function() { var o = Object.freeze({a:1}); try { o.a = 2; } catch(e) {} return o.a === 1; });
test('Object.seal', function() { var o = Object.seal({a:1}); o.a = 2; try { o.b = 3; } catch(e) {} return o.a === 2 && !('b' in o); });
test('Object.keys/values/entries', function() {
    var o = {a:1,b:2};
    return Object.keys(o).length === 2 && Object.values(o).length === 2 && Object.entries(o).length === 2;
});
test('Object.assign', function() {
    var t = Object.assign({}, {a:1}, {b:2});
    return t.a === 1 && t.b === 2;
});
test('Object.hasOwn', function() { return Object.hasOwn({a:1}, 'a') && !Object.hasOwn({a:1}, 'b'); });
test('Object.fromEntries', function() { return Object.fromEntries([['a',1],['b',2]]).a === 1; });
test('Proxy', function() {
    var p = new Proxy({}, { get: function(t,k) { return k === 'x' ? 42 : undefined; } });
    return p.x === 42;
});
test('Reflect', function() { return Reflect.ownKeys({a:1,b:2}).length === 2; });

// ══════════════════════════════════════════════════════════════
// 5. Promise / Async Safety
// ══════════════════════════════════════════════════════════════
console.log('\n=== Promise Safety ===');

test('Promise.resolve', function() { return typeof Promise.resolve(1).then === 'function'; });
test('Promise.reject', function() { return typeof Promise.reject(1).catch === 'function'; });
test('Promise.all', function() { return typeof Promise.all === 'function'; });
test('Promise.race', function() { return typeof Promise.race === 'function'; });
test('Promise.allSettled', function() { return typeof Promise.allSettled === 'function'; });
test('Promise.any', function() { return typeof Promise.any === 'function'; });
test('Promise.withResolvers', function() {
    if (typeof Promise.withResolvers !== 'function') return false;
    var p = Promise.withResolvers();
    return typeof p.resolve === 'function' && typeof p.reject === 'function';
});
test('queueMicrotask', function() { return typeof queueMicrotask === 'function'; });
test('async function', function() { return typeof (async function(){}) === 'function'; });

// ══════════════════════════════════════════════════════════════
// 6. Web APIs (Safety-Critical)
// ══════════════════════════════════════════════════════════════
console.log('\n=== Web APIs ===');

test('TextEncoder', function() { return new TextEncoder().encoding === 'utf-8'; });
test('TextEncoder encode', function() {
    var enc = new TextEncoder().encode('hello');
    return enc.length === 5 && enc[0] === 104;
});
test('TextDecoder', function() { return new TextDecoder().encoding === 'utf-8'; });
test('TextDecoder decode', function() {
    var dec = new TextDecoder().decode(new Uint8Array([104,105]));
    return dec === 'hi';
});
test('atob/btoa roundtrip', function() { return atob(btoa('hello world')) === 'hello world'; });
test('btoa binary', function() { return btoa('\x00\x01\x02') === 'AAEC'; });
test('structuredClone', function() {
    var o = {a: 1, b: {c: 2}};
    var c = structuredClone(o);
    c.b.c = 99;
    return o.b.c === 2;
});
test('AbortController', function() {
    var ac = new AbortController();
    return typeof ac.signal === 'object' && typeof ac.abort === 'function';
});
test('AbortSignal.abort', function() {
    var s = AbortSignal.abort();
    return s.aborted === true;
});
test('EventTarget', function() {
    var et = new EventTarget();
    var called = false;
    et.addEventListener('test', function() { called = true; });
    et.dispatchEvent(new Event('test'));
    return called;
});
test('Event', function() { return new Event('test').type === 'test'; });
test('CustomEvent', function() {
    var ce = new CustomEvent('test', {detail: 42});
    return ce.detail === 42;
});
test('DOMException', function() {
    var de = new DOMException('test', 'AbortError');
    return de.name === 'AbortError' && de.message === 'test';
});
test('performance.now', function() { return typeof performance.now === 'function' && typeof performance.now() === 'number'; });
test('URL', function() {
    var u = new URL('https://example.com:8080/path?q=1#h');
    return u.hostname === 'example.com' && u.port === '8080' && u.pathname === '/path';
});
test('URLSearchParams', function() {
    var p = new URLSearchParams('a=1&b=2');
    return p.get('a') === '1' && p.get('b') === '2';
});
test('Blob', function() {
    var b = new Blob(['hello']);
    return b.size === 5 && b.type === '';
});
test('Headers', function() {
    var h = new Headers({'Content-Type': 'text/plain'});
    return h.get('content-type') === 'text/plain';
});
test('crypto.randomUUID', function() {
    var uuid = crypto.randomUUID();
    return typeof uuid === 'string' && uuid.length === 36 && uuid[14] === '4';
});
test('crypto.getRandomValues', function() {
    var arr = new Uint8Array(16);
    crypto.getRandomValues(arr);
    var allZero = true;
    for (var i = 0; i < 16; i++) if (arr[i] !== 0) allZero = false;
    return !allZero;
});

// ══════════════════════════════════════════════════════════════
// 7. Streams API
// ══════════════════════════════════════════════════════════════
console.log('\n=== Streams API ===');

test('ReadableStream', function() { return typeof ReadableStream === 'function'; });
test('WritableStream', function() { return typeof WritableStream === 'function'; });
test('TransformStream', function() { return typeof TransformStream === 'function'; });

// ══════════════════════════════════════════════════════════════
// 8. MessageChannel / BroadcastChannel
// ══════════════════════════════════════════════════════════════
console.log('\n=== Messaging ===');

test('MessageChannel', function() {
    var mc = new MessageChannel();
    return typeof mc.port1 === 'object' && typeof mc.port2 === 'object';
});
test('BroadcastChannel', function() {
    var bc = new BroadcastChannel('test');
    var ok = typeof bc.postMessage === 'function';
    bc.close();
    return ok;
});

// ══════════════════════════════════════════════════════════════
// 9. Timers
// ══════════════════════════════════════════════════════════════
console.log('\n=== Timers ===');

test('setTimeout', function() { return typeof setTimeout === 'function'; });
test('clearTimeout', function() { return typeof clearTimeout === 'function'; });
test('setInterval', function() { return typeof setInterval === 'function'; });
test('clearInterval', function() { return typeof clearInterval === 'function'; });
test('setImmediate', function() { return typeof setImmediate === 'function'; });

// ══════════════════════════════════════════════════════════════
// 10. Process
// ══════════════════════════════════════════════════════════════
console.log('\n=== Process ===');

test('process.platform', function() { return typeof process.platform === 'string'; });
test('process.arch', function() { return typeof process.arch === 'string'; });
test('process.pid', function() { return typeof process.pid === 'number'; });
test('process.cwd', function() { return typeof process.cwd() === 'string'; });
test('process.env', function() { return typeof process.env === 'object'; });
test('process.exit', function() { return typeof process.exit === 'function'; });
test('process.argv', function() { return Array.isArray(process.argv); });
test('process.version', function() { return typeof process.version === 'string'; });
test('process.on', function() { return typeof process.on === 'function'; });

// ══════════════════════════════════════════════════════════════
// 11. Console
// ══════════════════════════════════════════════════════════════
console.log('\n=== Console ===');

test('console.log', function() { return typeof console.log === 'function'; });
test('console.error', function() { return typeof console.error === 'function'; });
test('console.warn', function() { return typeof console.warn === 'function'; });
test('console.info', function() { return typeof console.info === 'function'; });
test('console.debug', function() { return typeof console.debug === 'function'; });
test('console.time/timeEnd', function() { return typeof console.time === 'function' && typeof console.timeEnd === 'function'; });
test('console.count/countReset', function() { return typeof console.count === 'function' && typeof console.countReset === 'function'; });
test('console.table', function() { return typeof console.table === 'function'; });
test('console.dir', function() { return typeof console.dir === 'function'; });
test('console.trace', function() { return typeof console.trace === 'function'; });

// ══════════════════════════════════════════════════════════════
// 12. Node.js Modules
// ══════════════════════════════════════════════════════════════
console.log('\n=== Node.js Modules ===');

// fs
try {
    var fs = require('fs');
    test('fs.readFileSync', function() { return typeof fs.readFileSync === 'function'; });
    test('fs.writeFileSync', function() { return typeof fs.writeFileSync === 'function'; });
    test('fs.existsSync', function() { return typeof fs.existsSync === 'function'; });
    test('fs.statSync', function() { return typeof fs.statSync === 'function'; });
    test('fs.lstatSync', function() { return typeof fs.lstatSync === 'function'; });
    test('fs.mkdirSync', function() { return typeof fs.mkdirSync === 'function'; });
    test('fs.readdirSync', function() { return typeof fs.readdirSync === 'function'; });
    test('fs.rmSync', function() { return typeof fs.rmSync === 'function'; });
    test('fs.copyFileSync', function() { return typeof fs.copyFileSync === 'function'; });
    test('fs.renameSync', function() { return typeof fs.renameSync === 'function'; });
    test('fs.symlinkSync', function() { return typeof fs.symlinkSync === 'function'; });
    test('fs.readlinkSync', function() { return typeof fs.readlinkSync === 'function'; });
    test('fs.linkSync', function() { return typeof fs.linkSync === 'function'; });
    test('fs.truncateSync', function() { return typeof fs.truncateSync === 'function'; });
    test('fs.openSync', function() { return typeof fs.openSync === 'function'; });
    test('fs.closeSync', function() { return typeof fs.closeSync === 'function'; });
    test('fs.readSync', function() { return typeof fs.readSync === 'function'; });
    test('fs.writeSync', function() { return typeof fs.writeSync === 'function'; });
    test('fs.fstatSync', function() { return typeof fs.fstatSync === 'function'; });
    test('fs.fsyncSync', function() { return typeof fs.fsyncSync === 'function'; });
    test('fs.fdatasyncSync', function() { return typeof fs.fdatasyncSync === 'function'; });
    test('fs.createReadStream', function() { return typeof fs.createReadStream === 'function'; });
    test('fs.createWriteStream', function() { return typeof fs.createWriteStream === 'function'; });
    test('fs.watch', function() { return typeof fs.watch === 'function'; });
    test('fs.accessSync', function() { return typeof fs.accessSync === 'function'; });
    test('fs.chmodSync', function() { return typeof fs.chmodSync === 'function'; });
    test('fs.chownSync', function() { return typeof fs.chownSync === 'function'; });
    test('fs.realpathSync', function() { return typeof fs.realpathSync === 'function'; });
    test('fs.appendFileSync', function() { return typeof fs.appendFileSync === 'function'; });
    test('fs.unlinkSync', function() { return typeof fs.unlinkSync === 'function'; });
} catch(e) { console.log('SKIP: fs module (' + e.message + ')'); }

// path
try {
    var path = require('path');
    test('path.join', function() { return typeof path.join === 'function'; });
    test('path.resolve', function() { return typeof path.resolve === 'function'; });
    test('path.dirname', function() { return typeof path.dirname === 'function'; });
    test('path.basename', function() { return typeof path.basename === 'function'; });
    test('path.extname', function() { return typeof path.extname === 'function'; });
    test('path.isAbsolute', function() { return typeof path.isAbsolute === 'function'; });
    test('path.normalize', function() { return typeof path.normalize === 'function'; });
    test('path.relative', function() { return typeof path.relative === 'function'; });
    test('path.parse', function() { return typeof path.parse === 'function'; });
    test('path.sep', function() { return typeof path.sep === 'string'; });
} catch(e) { console.log('SKIP: path module (' + e.message + ')'); }

// os
try {
    var os = require('os');
    test('os.platform', function() { return typeof os.platform() === 'string'; });
    test('os.arch', function() { return typeof os.arch() === 'string'; });
    test('os.cpus', function() { return Array.isArray(os.cpus()); });
    test('os.totalmem', function() { return typeof os.totalmem() === 'number'; });
    test('os.freemem', function() { return typeof os.freemem() === 'number'; });
    test('os.hostname', function() { return typeof os.hostname() === 'string'; });
    test('os.homedir', function() { return typeof os.homedir() === 'string'; });
    test('os.tmpdir', function() { return typeof os.tmpdir() === 'string'; });
    test('os.type', function() { return typeof os.type() === 'string'; });
    test('os.uptime', function() { return typeof os.uptime() === 'number'; });
    test('os.EOL', function() { return typeof os.EOL === 'string'; });
} catch(e) { console.log('SKIP: os module (' + e.message + ')'); }

// crypto
try {
    var cryptoMod = require('crypto');
    test('crypto.randomUUID', function() { return typeof cryptoMod.randomUUID === 'function'; });
    test('crypto.randomBytes', function() { return typeof cryptoMod.randomBytes === 'function'; });
    test('crypto.createHash', function() { return typeof cryptoMod.createHash === 'function'; });
    test('crypto.createHash sha256', function() {
        var h = cryptoMod.createHash('sha256').update('hello').digest('hex');
        return typeof h === 'string' && h.length === 64;
    });
} catch(e) { console.log('SKIP: crypto module (' + e.message + ')'); }

// buffer
try {
    test('Buffer.from', function() { return Buffer.from('hello').length === 5; });
    test('Buffer.alloc', function() { return Buffer.alloc(10).length === 10; });
    test('Buffer.concat', function() {
        return Buffer.concat([Buffer.from('a'), Buffer.from('b')]).length === 2;
    });
    test('Buffer.isBuffer', function() { return Buffer.isBuffer(Buffer.from('x')); });
    test('Buffer.toString', function() { return Buffer.from('hello').toString() === 'hello'; });
    test('Buffer.toString hex', function() { return Buffer.from('hi').toString('hex') === '6869'; });
    test('Buffer.toString base64', function() { return Buffer.from('hi').toString('base64') === 'aGk='; });
    test('Buffer.from hex', function() { return Buffer.from('6869', 'hex').toString() === 'hi'; });
    test('Buffer.from base64', function() { return Buffer.from('aGk=', 'base64').toString() === 'hi'; });
} catch(e) { console.log('SKIP: Buffer (' + e.message + ')'); }

// events
try {
    var events = require('events');
    var EventEmitter = events.EventEmitter || events;
    test('EventEmitter', function() { return typeof EventEmitter === 'function'; });
    test('EventEmitter on/emit', function() {
        var ee = new EventEmitter();
        var v = 0;
        ee.on('test', function(x) { v = x; });
        ee.emit('test', 42);
        return v === 42;
    });
    test('EventEmitter once', function() {
        var ee = new EventEmitter();
        var count = 0;
        ee.once('test', function() { count++; });
        ee.emit('test');
        ee.emit('test');
        return count === 1;
    });
    test('EventEmitter removeListener', function() {
        var ee = new EventEmitter();
        var fn = function() {};
        ee.on('test', fn);
        ee.removeListener('test', fn);
        return ee.listenerCount('test') === 0;
    });
} catch(e) { console.log('SKIP: events module (' + e.message + ')'); }

// child_process
try {
    var cp = require('child_process');
    test('child_process.execSync', function() { return typeof cp.execSync === 'function'; });
    test('child_process.spawnSync', function() { return typeof cp.spawnSync === 'function'; });
} catch(e) { console.log('SKIP: child_process (' + e.message + ')'); }

// stream
try {
    var stream = require('stream');
    test('stream.Readable', function() { return typeof stream.Readable === 'function'; });
    test('stream.Writable', function() { return typeof stream.Writable === 'function'; });
    test('stream.Transform', function() { return typeof stream.Transform === 'function'; });
    test('stream.Duplex', function() { return typeof stream.Duplex === 'function'; });
    test('stream.PassThrough', function() { return typeof stream.PassThrough === 'function'; });
    test('stream.pipeline', function() { return typeof stream.pipeline === 'function'; });
} catch(e) { console.log('SKIP: stream (' + e.message + ')'); }

// zlib
try {
    var zlib = require('zlib');
    test('zlib.deflateSync', function() { return typeof zlib.deflateSync === 'function'; });
    test('zlib.inflateSync', function() { return typeof zlib.inflateSync === 'function'; });
    test('zlib.gzipSync', function() { return typeof zlib.gzipSync === 'function'; });
    test('zlib.gunzipSync', function() { return typeof zlib.gunzipSync === 'function'; });
    test('zlib roundtrip', function() {
        var input = 'Hello, zlib compression test!';
        var deflated = zlib.deflateSync(input);
        var inflated = zlib.inflateSync(deflated);
        var str = '';
        if (typeof inflated === 'string') return inflated === input;
        for (var i = 0; i < inflated.length; i++) str += String.fromCharCode(inflated[i]);
        return str === input;
    });
} catch(e) { console.log('SKIP: zlib (' + e.message + ')'); }

// dns
try {
    var dns = require('dns');
    test('dns.lookup', function() { return typeof dns.lookup === 'function'; });
    test('dns.resolve4', function() { return typeof dns.resolve4 === 'function'; });
} catch(e) { console.log('SKIP: dns (' + e.message + ')'); }

// http
try {
    var http = require('http');
    test('http.createServer', function() { return typeof http.createServer === 'function'; });
} catch(e) { console.log('SKIP: http (' + e.message + ')'); }

// net
try {
    var net = require('net');
    test('net.createServer', function() { return typeof net.createServer === 'function'; });
    test('net.createConnection', function() { return typeof net.createConnection === 'function'; });
} catch(e) { console.log('SKIP: net (' + e.message + ')'); }

// url
try {
    var url = require('url');
    test('url.URL', function() { return typeof url.URL === 'function' || typeof URL === 'function'; });
} catch(e) { console.log('SKIP: url (' + e.message + ')'); }

// querystring
try {
    var qs = require('querystring');
    test('querystring.parse', function() { return typeof qs.parse === 'function'; });
    test('querystring.stringify', function() { return typeof qs.stringify === 'function'; });
    test('querystring roundtrip', function() {
        var obj = qs.parse('a=1&b=2');
        return obj.a === '1' && obj.b === '2';
    });
} catch(e) { console.log('SKIP: querystring (' + e.message + ')'); }

// util
try {
    var util = require('util');
    test('util.inspect', function() { return typeof util.inspect === 'function'; });
    test('util.format', function() { return typeof util.format === 'function'; });
    test('util.promisify', function() { return typeof util.promisify === 'function'; });
    test('util.types', function() { return typeof util.types === 'object'; });
} catch(e) { console.log('SKIP: util (' + e.message + ')'); }

// assert
try {
    var assert = require('assert');
    test('assert ok', function() { assert(true); return true; });
    test('assert.strictEqual', function() { assert.strictEqual(1, 1); return true; });
    test('assert.deepStrictEqual', function() { assert.deepStrictEqual({a:1}, {a:1}); return true; });
    test('assert.throws', function() {
        assert.throws(function() { throw new Error('test'); });
        return true;
    });
} catch(e) { console.log('SKIP: assert (' + e.message + ')'); }

// string_decoder
try {
    var sd = require('string_decoder');
    var StringDecoder = sd.StringDecoder;
    test('StringDecoder', function() { return typeof StringDecoder === 'function'; });
} catch(e) { console.log('SKIP: string_decoder (' + e.message + ')'); }

// ══════════════════════════════════════════════════════════════
// 13. ES2023+ Features
// ══════════════════════════════════════════════════════════════
console.log('\n=== ES2023+ ===');

test('Array.findLast', function() { return [1,2,3,4].findLast(function(x) { return x % 2 === 0; }) === 4; });
test('Array.findLastIndex', function() { return [1,2,3,4].findLastIndex(function(x) { return x % 2 === 0; }) === 3; });
test('Array.toReversed', function() { return typeof [].toReversed === 'function'; });
test('Array.toSorted', function() { return typeof [].toSorted === 'function'; });
test('Array.toSpliced', function() { return typeof [].toSpliced === 'function'; });
test('Array.with', function() { return typeof [].with === 'function'; });
test('Object.groupBy', function() { return typeof Object.groupBy === 'function'; });
test('Map.groupBy', function() { return typeof Map.groupBy === 'function'; });
test('Symbol.dispose', function() { return typeof Symbol.dispose === 'symbol'; });
test('RegExp v flag', function() {
    try { new RegExp('[\\p{L}]', 'v'); return true; } catch(e) { return false; }
});

// ══════════════════════════════════════════════════════════════
// 14. Typed Arrays & ArrayBuffer
// ══════════════════════════════════════════════════════════════
console.log('\n=== Typed Arrays ===');

test('Uint8Array', function() { return new Uint8Array(4).length === 4; });
test('Int32Array', function() { return new Int32Array(4).length === 4; });
test('Float64Array', function() { return new Float64Array(4).length === 4; });
test('ArrayBuffer', function() { return new ArrayBuffer(8).byteLength === 8; });
test('DataView', function() {
    var dv = new DataView(new ArrayBuffer(8));
    dv.setInt32(0, 42);
    return dv.getInt32(0) === 42;
});
test('SharedArrayBuffer', function() { return typeof SharedArrayBuffer === 'function'; });
test('Atomics', function() { return typeof Atomics === 'object' && typeof Atomics.add === 'function'; });

// ══════════════════════════════════════════════════════════════
// 15. Iterator Helpers (ES2025)
// ══════════════════════════════════════════════════════════════
console.log('\n=== Iterator Helpers ===');

test('Iterator.from', function() { return typeof Iterator === 'function' && typeof Iterator.from === 'function'; });
test('iterator.map', function() {
    try { return typeof [].values().map === 'function'; } catch(e) { return false; }
});
test('iterator.filter', function() {
    try { return typeof [].values().filter === 'function'; } catch(e) { return false; }
});
test('iterator.take', function() {
    try { return typeof [].values().take === 'function'; } catch(e) { return false; }
});

// ══════════════════════════════════════════════════════════════
// 16. Miscellaneous Safety
// ══════════════════════════════════════════════════════════════
console.log('\n=== Misc Safety ===');

test('globalThis', function() { return typeof globalThis === 'object'; });
test('WeakRef', function() { return typeof WeakRef === 'function'; });
test('FinalizationRegistry', function() { return typeof FinalizationRegistry === 'function'; });
test('WeakMap', function() { return typeof WeakMap === 'function'; });
test('WeakSet', function() { return typeof WeakSet === 'function'; });
test('Symbol.iterator', function() { return typeof Symbol.iterator === 'symbol'; });
test('Symbol.asyncIterator', function() { return typeof Symbol.asyncIterator === 'symbol'; });
test('Symbol.toPrimitive', function() { return typeof Symbol.toPrimitive === 'symbol'; });
test('navigator.userAgent', function() {
    try { return typeof navigator.userAgent === 'string'; } catch(e) { return false; }
});

// ══════════════════════════════════════════════════════════════
// Summary
// ══════════════════════════════════════════════════════════════
console.log('\n=== Summary ===');
console.log('Total: ' + (pass + fail) + ' | Pass: ' + pass + ' | Fail: ' + fail);
console.log('Score: ' + pass + '/' + (pass + fail));
