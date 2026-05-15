// Web APIs integration test — tests all new Web standard globals
// Tests: performance, EventTarget, Event, AbortController, AbortSignal,
//        DOMException, Promise.withResolvers, setImmediate, navigator,
//        Blob, File, FormData, Headers, Request, Response,
//        MessageChannel, BroadcastChannel, ReadableStream, WritableStream,
//        TransformStream, crypto.getRandomValues, console.time/count/table,
//        require.resolve

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) { pass++; }
  else { fail++; console.log('FAIL: ' + name); }
}

// === performance ===
check('performance exists', typeof performance === 'object');
check('performance.now()', typeof performance.now() === 'number');
check('performance.now() > 0', performance.now() >= 0);
check('performance.timeOrigin', typeof performance.timeOrigin === 'number');

// === EventTarget / Event ===
check('EventTarget exists', typeof EventTarget === 'function');
check('Event exists', typeof Event === 'function');
const et = new EventTarget();
let called = false;
et.addEventListener('test', () => { called = true; });
et.dispatchEvent(new Event('test'));
check('EventTarget dispatch', called);

// Event properties
const ev = new Event('click', { cancelable: true, bubbles: true });
check('Event.type', ev.type === 'click');
check('Event.cancelable', ev.cancelable === true);
check('Event.bubbles', ev.bubbles === true);
ev.preventDefault();
check('Event.defaultPrevented', ev.defaultPrevented === true);

// CustomEvent
const ce = new CustomEvent('custom', { detail: { foo: 42 } });
check('CustomEvent.detail', ce.detail.foo === 42);

// removeEventListener
const et2 = new EventTarget();
let count = 0;
const handler = () => { count++; };
et2.addEventListener('x', handler);
et2.dispatchEvent(new Event('x'));
et2.removeEventListener('x', handler);
et2.dispatchEvent(new Event('x'));
check('removeEventListener', count === 1);

// once option
const et3 = new EventTarget();
let onceCount = 0;
et3.addEventListener('y', () => { onceCount++; }, { once: true });
et3.dispatchEvent(new Event('y'));
et3.dispatchEvent(new Event('y'));
check('addEventListener once', onceCount === 1);

// === AbortController / AbortSignal ===
check('AbortController exists', typeof AbortController === 'function');
check('AbortSignal exists', typeof AbortSignal === 'function');
const ac = new AbortController();
check('signal.aborted initially false', ac.signal.aborted === false);
ac.abort();
check('signal.aborted after abort', ac.signal.aborted === true);
check('signal.reason', ac.signal.reason instanceof DOMException);

// AbortSignal.abort()
const aborted = AbortSignal.abort('custom reason');
check('AbortSignal.abort()', aborted.aborted === true);
check('AbortSignal.abort() reason', aborted.reason === 'custom reason');

// throwIfAborted
let threw = false;
try { ac.signal.throwIfAborted(); } catch (e) { threw = true; }
check('throwIfAborted', threw);

// === DOMException ===
check('DOMException exists', typeof DOMException === 'function');
const de = new DOMException('test', 'AbortError');
check('DOMException.message', de.message === 'test');
check('DOMException.name', de.name === 'AbortError');

// === Promise.withResolvers ===
check('Promise.withResolvers exists', typeof Promise.withResolvers === 'function');
const { promise, resolve, reject } = Promise.withResolvers();
check('withResolvers returns promise', promise instanceof Promise);
check('withResolvers resolve fn', typeof resolve === 'function');
check('withResolvers reject fn', typeof reject === 'function');

// === setImmediate ===
check('setImmediate exists', typeof setImmediate === 'function');
check('clearImmediate exists', typeof clearImmediate === 'function');

// === navigator ===
check('navigator exists', typeof navigator === 'object');
check('navigator.userAgent', typeof navigator.userAgent === 'string');
check('navigator.platform', typeof navigator.platform === 'string');
check('navigator.language', navigator.language === 'en-US');
check('navigator.onLine', navigator.onLine === true);
check('navigator.hardwareConcurrency', typeof navigator.hardwareConcurrency === 'number');

// === Blob ===
check('Blob exists', typeof Blob === 'function');
const blob = new Blob(['hello', ' ', 'world'], { type: 'text/plain' });
check('Blob.size', blob.size > 0);
check('Blob.type', blob.type === 'text/plain');

// === File ===
check('File exists', typeof File === 'function');
const file = new File(['content'], 'test.txt', { type: 'text/plain' });
check('File.name', file.name === 'test.txt');
check('File.lastModified', typeof file.lastModified === 'number');

// === FormData ===
check('FormData exists', typeof FormData === 'function');
const fd = new FormData();
fd.append('key1', 'value1');
fd.append('key2', 'value2');
check('FormData.get', fd.get('key1') === 'value1');
check('FormData.has', fd.has('key2') === true);
fd.delete('key2');
check('FormData.delete', fd.has('key2') === false);
fd.set('key1', 'newvalue');
check('FormData.set', fd.get('key1') === 'newvalue');
fd.append('multi', 'a');
fd.append('multi', 'b');
check('FormData.getAll', fd.getAll('multi').length === 2);

// === Headers ===
check('Headers exists', typeof Headers === 'function');
const h = new Headers({ 'Content-Type': 'text/html' });
check('Headers.get', h.get('content-type') === 'text/html');
h.set('x-custom', 'test');
check('Headers.has', h.has('x-custom'));
h.append('x-multi', 'a');
h.append('x-multi', 'b');
check('Headers.get multi', h.get('x-multi') === 'a, b');
h.delete('x-custom');
check('Headers.delete', !h.has('x-custom'));

// === Request ===
check('Request exists', typeof Request === 'function');
const req = new Request('https://example.com/api', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: '{"key":"value"}'
});
check('Request.url', req.url === 'https://example.com/api');
check('Request.method', req.method === 'POST');
check('Request.headers', req.headers instanceof Headers);
const reqClone = req.clone();
check('Request.clone', reqClone.url === req.url);

// === Response ===
check('Response exists', typeof Response === 'function');
const res = new Response('hello', { status: 200, statusText: 'OK' });
check('Response.status', res.status === 200);
check('Response.statusText', res.statusText === 'OK');
check('Response.ok', res.ok === true);
const jsonRes = Response.json({ a: 1 });
check('Response.json()', jsonRes.status === 200);
const redirectRes = Response.redirect('https://example.com', 301);
check('Response.redirect()', redirectRes.status === 301);

// === MessageChannel ===
check('MessageChannel exists', typeof MessageChannel === 'function');
check('MessagePort exists', typeof MessagePort === 'function');
const mc = new MessageChannel();
let received = null;
mc.port2.onmessage = (e) => { received = e.data; };
mc.port2.start();
mc.port1.postMessage('hello');
check('MessageChannel works', received === 'hello');

// === BroadcastChannel ===
check('BroadcastChannel exists', typeof BroadcastChannel === 'function');
const bc1 = new BroadcastChannel('test');
const bc2 = new BroadcastChannel('test');
let bcReceived = null;
bc2.onmessage = (e) => { bcReceived = e.data; };
bc1.postMessage('broadcast');
check('BroadcastChannel works', bcReceived === 'broadcast');
bc1.close();
bc2.close();

// === ReadableStream ===
check('ReadableStream exists', typeof ReadableStream === 'function');
const rs = new ReadableStream({
  start(controller) {
    controller.enqueue('chunk1');
    controller.enqueue('chunk2');
    controller.close();
  }
});
const reader = rs.getReader();
check('ReadableStream.getReader', reader !== null);

// === WritableStream ===
check('WritableStream exists', typeof WritableStream === 'function');
const chunks = [];
const ws = new WritableStream({
  write(chunk) { chunks.push(chunk); }
});

// === TransformStream ===
check('TransformStream exists', typeof TransformStream === 'function');

// === crypto.getRandomValues ===
check('crypto exists', typeof crypto === 'object');
check('crypto.getRandomValues exists', typeof crypto.getRandomValues === 'function');
const arr = new Uint8Array(16);
crypto.getRandomValues(arr);
let hasNonZero = false;
for (let i = 0; i < arr.length; i++) if (arr[i] !== 0) hasNonZero = true;
check('getRandomValues fills array', hasNonZero);
check('crypto.randomUUID exists', typeof crypto.randomUUID === 'function');
const uuid = crypto.randomUUID();
check('crypto.randomUUID format', /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid));

// === console.time/timeEnd ===
check('console.time exists', typeof console.time === 'function');
check('console.timeEnd exists', typeof console.timeEnd === 'function');
check('console.timeLog exists', typeof console.timeLog === 'function');

// === console.count ===
check('console.count exists', typeof console.count === 'function');
check('console.countReset exists', typeof console.countReset === 'function');

// === console.table ===
check('console.table exists', typeof console.table === 'function');

// === console.dir/trace/clear ===
check('console.dir exists', typeof console.dir === 'function');
check('console.trace exists', typeof console.trace === 'function');
check('console.clear exists', typeof console.clear === 'function');

// === require.resolve ===
check('require.resolve exists', typeof require.resolve === 'function');
check('require.resolve builtin', require.resolve('fs') === 'fs');
check('require.cache exists', typeof require.cache === 'object');

// === CompressionStream / DecompressionStream ===
check('CompressionStream exists', typeof CompressionStream === 'function');
const cs = new CompressionStream('gzip');
check('CompressionStream.format', cs.format === 'gzip');
check('CompressionStream.readable', cs.readable instanceof ReadableStream);
check('CompressionStream.writable', cs.writable instanceof WritableStream);
let csThrew = false;
try { new CompressionStream('bad'); } catch (e) { csThrew = true; }
check('CompressionStream bad format throws', csThrew);

check('DecompressionStream exists', typeof DecompressionStream === 'function');
const ds = new DecompressionStream('deflate');
check('DecompressionStream.format', ds.format === 'deflate');
check('DecompressionStream.readable', ds.readable instanceof ReadableStream);
check('DecompressionStream.writable', ds.writable instanceof WritableStream);
let dsThrew = false;
try { new DecompressionStream('bad'); } catch (e) { dsThrew = true; }
check('DecompressionStream bad format throws', dsThrew);

console.log(`\nWeb APIs: ${pass}/${pass + fail} passed`);
if (fail > 0) console.log(`${fail} FAILED`);
