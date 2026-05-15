// Production parity gap analysis
// Test Node.js patterns that real-world apps rely on
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// === Process API completeness ===
check('process.versions', typeof process.versions === 'object');
check('process.versions.node', typeof process.versions.node === 'string');
check('process.title', typeof process.title === 'string');
check('process.execPath', typeof process.execPath === 'string');
check('process.argv is array', Array.isArray(process.argv));
check('process.env is object', typeof process.env === 'object');
check('process.cwd function', typeof process.cwd === 'function');
check('process.exit function', typeof process.exit === 'function');
check('process.pid number', typeof process.pid === 'number');
check('process.platform', typeof process.platform === 'string');
check('process.arch', typeof process.arch === 'string');
check('process.version', typeof process.version === 'string');
check('process.hrtime', typeof process.hrtime === 'function');
check('process.hrtime.bigint', typeof process.hrtime.bigint === 'function');
check('process.nextTick', typeof process.nextTick === 'function');
check('process.stdout', typeof process.stdout === 'object');
check('process.stderr', typeof process.stderr === 'object');
check('process.stdin', typeof process.stdin === 'object');
check('process.on function', typeof process.on === 'function');
check('process.emit function', typeof process.emit === 'function');
check('process.memoryUsage', typeof process.memoryUsage === 'function');

// === Encoding edge cases ===
check('Buffer.from base64', Buffer.from('aGVsbG8=', 'base64').toString() === 'hello');
check('Buffer.from hex', Buffer.from('68656c6c6f', 'hex').toString() === 'hello');
check('Buffer toString base64', Buffer.from('hello').toString('base64') === 'aGVsbG8=');
check('Buffer toString hex', Buffer.from('hello').toString('hex') === '68656c6c6f');

// === JSON module ===
check('JSON.parse basic', JSON.parse('{"a":1}').a === 1);
check('JSON.stringify', JSON.stringify({a:1}) === '{"a":1}');
check('JSON.parse reviver', JSON.parse('{"a":1}', function(k,v){return typeof v==='number'?v*2:v}).a === 2);
check('JSON.stringify replacer', JSON.stringify({a:1,b:2}, ['a']) === '{"a":1}');
check('JSON.stringify space', JSON.stringify({a:1}, null, 2).indexOf('  ') >= 0);

// === Error types ===
check('TypeError', typeof TypeError === 'function');
check('RangeError', typeof RangeError === 'function');
check('SyntaxError', typeof SyntaxError === 'function');
check('ReferenceError', typeof ReferenceError === 'function');
check('URIError', typeof URIError === 'function');
check('EvalError', typeof EvalError === 'function');
check('Error.captureStackTrace', typeof Error.captureStackTrace === 'function');
check('Error.stackTraceLimit', typeof Error.stackTraceLimit === 'number');

// === Encoding globals ===
check('encodeURIComponent', encodeURIComponent('hello world') === 'hello%20world');
check('decodeURIComponent', decodeURIComponent('hello%20world') === 'hello world');
check('encodeURI', typeof encodeURI === 'function');
check('decodeURI', typeof decodeURI === 'function');

// === Date ===
check('Date.now', typeof Date.now() === 'number');
check('new Date valid', !isNaN(new Date().getTime()));
check('Date.parse', typeof Date.parse === 'function');
check('Date toISOString', typeof new Date().toISOString === 'function');
check('Date toJSON', typeof new Date().toJSON === 'function');

// === Timers ===
check('setTimeout', typeof setTimeout === 'function');
check('setInterval', typeof setInterval === 'function');
check('clearTimeout', typeof clearTimeout === 'function');
check('clearInterval', typeof clearInterval === 'function');
check('queueMicrotask', typeof queueMicrotask === 'function');

// === Symbol well-known ===
check('Symbol.iterator', typeof Symbol.iterator === 'symbol');
check('Symbol.asyncIterator', typeof Symbol.asyncIterator === 'symbol');
check('Symbol.toPrimitive', typeof Symbol.toPrimitive === 'symbol');
check('Symbol.hasInstance', typeof Symbol.hasInstance === 'symbol');
check('Symbol.toStringTag', typeof Symbol.toStringTag === 'symbol');

// === Collections ===
check('Map', typeof Map === 'function');
check('Set', typeof Set === 'function');
check('WeakMap', typeof WeakMap === 'function');
check('WeakSet', typeof WeakSet === 'function');
check('WeakRef', typeof WeakRef === 'function');

// === Typed arrays ===
check('Uint8Array', typeof Uint8Array === 'function');
check('Int32Array', typeof Int32Array === 'function');
check('Float64Array', typeof Float64Array === 'function');
check('ArrayBuffer', typeof ArrayBuffer === 'function');
check('DataView', typeof DataView === 'function');
check('SharedArrayBuffer', typeof SharedArrayBuffer === 'function');
check('Atomics', typeof Atomics === 'object');

// === Reflect/Proxy ===
check('Reflect', typeof Reflect === 'object');
check('Proxy', typeof Proxy === 'function');
check('Reflect.ownKeys', typeof Reflect.ownKeys === 'function');
check('Reflect.has', typeof Reflect.has === 'function');

// === Console completeness ===
check('console.log', typeof console.log === 'function');
check('console.error', typeof console.error === 'function');
check('console.warn', typeof console.warn === 'function');
check('console.info', typeof console.info === 'function');
check('console.debug', typeof console.debug === 'function');
check('console.time', typeof console.time === 'function');
check('console.timeEnd', typeof console.timeEnd === 'function');
check('console.trace', typeof console.trace === 'function');
check('console.assert', typeof console.assert === 'function');
check('console.table', typeof console.table === 'function');
check('console.dir', typeof console.dir === 'function');

// === Regex ===
check('RegExp named groups', /(?<year>\d{4})/.exec('2024').groups.year === '2024');
check('RegExp dotAll', /./s.test('\n'));
check('RegExp lookbehind', /(?<=a)b/.test('ab'));
check('String.matchAll', typeof ''.matchAll === 'function');

// === String methods ===
check('String.padStart', '5'.padStart(3, '0') === '005');
check('String.padEnd', '5'.padEnd(3, '0') === '500');
check('String.trimStart', '  hi'.trimStart() === 'hi');
check('String.trimEnd', 'hi  '.trimEnd() === 'hi');
check('String.replaceAll', 'aabbcc'.replaceAll('b', 'x') === 'aaxxcc');
check('String.at', 'hello'.at(-1) === 'o');

// === Array methods ===
check('Array.flat', [1,[2,[3]]].flat(Infinity).join(',') === '1,2,3');
check('Array.flatMap', [1,2].flatMap(function(x){return[x,x*2]}).join(',') === '1,2,2,4');
check('Array.at', [1,2,3].at(-1) === 3);
check('Array.findLast', [1,2,3,4].findLast(function(x){return x%2===0}) === 4);
check('Array.findLastIndex', [1,2,3,4].findLastIndex(function(x){return x%2===0}) === 3);
check('Array.toSorted', typeof [].toSorted === 'function');
check('Array.toReversed', typeof [].toReversed === 'function');

// === Object methods ===
check('Object.entries', Object.entries({a:1}).length === 1);
check('Object.fromEntries', Object.fromEntries([['a',1]]).a === 1);
check('Object.hasOwn', Object.hasOwn({a:1}, 'a') === true);
check('Object.groupBy', typeof Object.groupBy === 'function');
check('structuredClone', typeof structuredClone === 'function');

// === Promise ===
check('Promise', typeof Promise === 'function');
check('Promise.all', typeof Promise.all === 'function');
check('Promise.race', typeof Promise.race === 'function');
check('Promise.allSettled', typeof Promise.allSettled === 'function');
check('Promise.any', typeof Promise.any === 'function');
check('Promise.withResolvers', typeof Promise.withResolvers === 'function');

// === globalThis ===
check('globalThis', typeof globalThis === 'object');
check('globalThis.global', globalThis.global === globalThis);

// === TextEncoder/TextDecoder ===
check('TextEncoder', typeof TextEncoder === 'function');
check('TextDecoder', typeof TextDecoder === 'function');
var enc = new TextEncoder();
check('TextEncoder.encode', enc.encode('hi').length === 2);
var dec = new TextDecoder();
check('TextDecoder.decode', dec.decode(enc.encode('hello')) === 'hello');

// === Performance ===
check('performance.now', typeof performance.now === 'function');
check('performance.now returns number', typeof performance.now() === 'number');

console.log('production_gaps2: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
