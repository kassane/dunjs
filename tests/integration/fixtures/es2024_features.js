var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// ES2020
check('optional chaining', ({ a: { b: 1 } })?.a?.b === 1);
check('optional chaining missing', ({})?.x?.y === undefined);
check('nullish coalescing null', (null ?? 'default') === 'default');
check('nullish coalescing 0', (0 ?? 'default') === 0);
check('BigInt typeof', typeof 0n === 'bigint');
check('BigInt arithmetic', 9007199254740993n + 1n === 9007199254740994n);

// ES2021
check('logical assignment ??=', (() => { var a = null; a ??= 42; return a === 42; })());
check('logical assignment ||=', (() => { var b = 0; b ||= 99; return b === 99; })());
check('logical assignment &&=', (() => { var c = 1; c &&= 2; return c === 2; })());
check('String.prototype.replaceAll', 'aabaa'.replaceAll('a', 'x') === 'xxbxx');
check('WeakRef', typeof new WeakRef({}).deref === 'function');
check('FinalizationRegistry', typeof new FinalizationRegistry(() => {}).register === 'function');
check('Promise.any', typeof Promise.any === 'function');

// ES2022
check('Array.at', [1,2,3].at(-1) === 3);
check('String.at', 'abc'.at(-1) === 'c');
check('Object.hasOwn', Object.hasOwn({ a: 1 }, 'a') && !Object.hasOwn({ a: 1 }, 'b'));
check('Error.cause', new Error('x', { cause: new Error('y') }).cause.message === 'y');

// ES2023
check('Array.findLast', [1,2,3,4].findLast(x => x < 3) === 2);
check('Array.findLastIndex', [1,2,3,4].findLastIndex(x => x < 3) === 1);
check('Array.toSorted', (() => { var a = [3,1,2]; var b = a.toSorted(); return b[0] === 1 && a[0] === 3; })());
check('Array.toReversed', (() => { var a = [1,2,3]; var b = a.toReversed(); return b[0] === 3 && a[0] === 1; })());
check('Array.with', [1,2,3].with(1, 99)[1] === 99);

// ES2024
check('Object.groupBy', (() => {
  var g = Object.groupBy([{t:'a',v:1},{t:'b',v:2},{t:'a',v:3}], x => x.t);
  return g.a.length === 2 && g.b.length === 1;
})());
check('Promise.withResolvers', typeof Promise.withResolvers === 'function');

// SharedArrayBuffer + Atomics
check('SharedArrayBuffer', (() => {
  var sab = new SharedArrayBuffer(16);
  var arr = new Int32Array(sab);
  Atomics.store(arr, 0, 42);
  return Atomics.load(arr, 0) === 42;
})());

// Web APIs
check('structuredClone deep', (() => {
  var o = { a: [1, [2]] }; var c = structuredClone(o);
  c.a[1].push(3); return o.a[1].length === 1;
})());
check('TextEncoder/TextDecoder', new TextDecoder().decode(new TextEncoder().encode('hi')) === 'hi');
check('AbortController', (() => {
  var ac = new AbortController(); ac.abort(); return ac.signal.aborted === true;
})());
check('performance.now', typeof performance.now() === 'number');
check('crypto.randomUUID', (() => {
  var id = crypto.randomUUID(); return id.length === 36 && id[14] === '4';
})());
check('queueMicrotask', typeof queueMicrotask === 'function');

// Proxy + Reflect
check('Proxy', (() => {
  var p = new Proxy({a:1}, {get(t,k) { return k in t ? t[k] : 'def'; }});
  return p.a === 1 && p.b === 'def';
})());
check('Reflect.ownKeys', Reflect.ownKeys({a:1, [Symbol('s')]:2}).length === 2);

console.log('es2024_features: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
