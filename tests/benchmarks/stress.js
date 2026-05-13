// Comprehensive stress benchmark — 200+ tests across all JS engine capabilities
// Tests practical workloads that stress JIT compilation, GC, and runtime APIs

const results = {};
let testCount = 0;

function bench(name, fn, iterations) {
  iterations = iterations || 10000;
  try {
    for (let i = 0; i < Math.min(iterations, 50); i++) fn();
    const start = Date.now();
    for (let i = 0; i < iterations; i++) fn();
    const elapsed = Date.now() - start;
    testCount++;
    results[name] = { elapsed, iterations, opsPerSec: Math.round(iterations / (elapsed / 1000)) };
  } catch(e) {
    testCount++;
    console.log("FAIL: " + name + " (" + (e && e.message ? e.message : String(e)).substring(0, 80) + ")");
  }
}

// ============================================================
// 1. STRING OPERATIONS (30 tests)
// ============================================================

bench("str-charCodeAt-scan", () => {
  const s = "The quick brown fox jumps over the lazy dog 🌍";
  let sum = 0;
  for (let i = 0; i < s.length; i++) sum += s.charCodeAt(i);
  return sum;
}, 100000);

bench("str-concat-small", () => {
  let s = "";
  for (let i = 0; i < 100; i++) s += "x";
  return s;
}, 50000);

bench("str-concat-template", () => {
  let s = "";
  for (let i = 0; i < 100; i++) s = `${s}item${i}`;
  return s.length;
}, 10000);

bench("str-split-join", () => {
  return "a,b,c,d,e,f,g,h,i,j".split(",").join("-");
}, 100000);

bench("str-indexOf-search", () => {
  const haystack = "The quick brown fox jumps over the lazy dog";
  return haystack.indexOf("fox") + haystack.indexOf("dog") + haystack.indexOf("missing");
}, 200000);

bench("str-slice-substr", () => {
  const s = "abcdefghijklmnopqrstuvwxyz";
  return s.slice(5, 15) + s.substring(10, 20) + s.slice(-5);
}, 200000);

bench("str-toUpperCase", () => "hello world café résumé".toUpperCase(), 100000);
bench("str-toLowerCase", () => "HELLO WORLD CAFÉ RÉSUMÉ".toLowerCase(), 100000);
bench("str-trim-variants", () => {
  const s = "   hello world   ";
  return s.trim() + s.trimStart() + s.trimEnd();
}, 100000);

bench("str-startsWith-endsWith", () => {
  const s = "Hello, World!";
  return s.startsWith("Hello") && s.endsWith("!") && s.includes("World");
}, 200000);

bench("str-repeat", () => "abc".repeat(100), 50000);
bench("str-padStart-padEnd", () => "42".padStart(10, "0") + "hi".padEnd(10, "."), 100000);
bench("str-replace-single", () => "hello world hello".replace("hello", "hi"), 100000);
bench("str-replaceAll", () => "aababaab".replaceAll("ab", "x"), 100000);

bench("str-normalize-nfc", () => {
  const s = "café";
  return s.normalize("NFC");
}, 50000);

bench("str-fromCharCode-batch", () => {
  let s = "";
  for (let i = 65; i < 91; i++) s += String.fromCharCode(i);
  return s;
}, 100000);

bench("str-codePointAt-emoji", () => {
  const s = "Hello 🌍🎉🚀 World";
  let sum = 0;
  for (let i = 0; i < s.length; i++) sum += s.codePointAt(i) || 0;
  return sum;
}, 100000);

bench("str-match-simple", () => "abc123def456".match(/\d+/g), 100000);

bench("str-localeCompare", () => {
  return "apple".localeCompare("banana") + "café".localeCompare("cafe");
}, 50000);

bench("str-raw-template", () => String.raw`hello\nworld\t${1+1}`, 200000);

bench("str-search-lastIndexOf", () => {
  const s = "abcabc";
  return s.search(/bc/) + s.lastIndexOf("bc");
}, 200000);

bench("str-at-negative", () => "hello"[0] + "hello".at(-1), 200000);

bench("str-build-html-200", () => {
  let html = "<ul>";
  for (let i = 0; i < 200; i++) html += `<li class="item-${i}">${i}</li>`;
  html += "</ul>";
  return html.length;
}, 2000);

bench("str-unicode-heavy", () => {
  const s = "日本語テスト 中文测试 한국어 العربية";
  return s.length + s.split("").reverse().join("");
}, 50000);

bench("str-json-stringify-string", () => JSON.stringify("hello \"world\" \n\t\r\\"), 100000);

bench("str-number-format", () => {
  return (1234567.89).toFixed(2) + (0.1 + 0.2).toPrecision(15);
}, 100000);

bench("str-parseInt-parseFloat", () => {
  return parseInt("12345") + parseFloat("3.14159") + parseInt("ff", 16);
}, 200000);

bench("str-encodeURI", () => {
  return encodeURIComponent("hello world & foo=bar") + decodeURIComponent("hello%20world");
}, 100000);

bench("str-array-join-large", () => {
  const arr = [];
  for (let i = 0; i < 1000; i++) arr.push("item" + i);
  return arr.join(",");
}, 5000);

bench("str-regex-replace-complex", () => {
  return "2024-01-15T10:30:45.123Z".replace(
    /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/,
    "$2/$3/$1 $4:$5:$6"
  );
}, 100000);

// ============================================================
// 2. ARRAY OPERATIONS (30 tests)
// ============================================================

bench("arr-push-pop-1k", () => {
  const arr = [];
  for (let i = 0; i < 1000; i++) arr.push(i);
  let sum = 0;
  while (arr.length) sum += arr.pop();
  return sum;
}, 5000);

bench("arr-unshift-shift", () => {
  const arr = [];
  for (let i = 0; i < 100; i++) arr.unshift(i);
  let sum = 0;
  while (arr.length) sum += arr.shift();
  return sum;
}, 10000);

bench("arr-map-filter-reduce", () => {
  const arr = Array.from({length: 500}, (_, i) => i);
  return arr.map(x => x * 2).filter(x => x % 3 === 0).reduce((a, b) => a + b, 0);
}, 5000);

bench("arr-sort-numbers", () => {
  const arr = Array.from({length: 1000}, () => Math.random() * 10000 | 0);
  arr.sort((a, b) => a - b);
  return arr[0];
}, 1000);

bench("arr-sort-strings", () => {
  const arr = Array.from({length: 500}, (_, i) => `item-${(i * 7919) % 500}`);
  arr.sort();
  return arr[0];
}, 2000);

bench("arr-indexOf-includes", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  return arr.indexOf(500) + arr.indexOf(999) + (arr.includes(750) ? 1 : 0);
}, 10000);

bench("arr-find-findIndex", () => {
  const arr = Array.from({length: 1000}, (_, i) => ({id: i, val: i * 2}));
  return arr.find(x => x.id === 500).val + arr.findIndex(x => x.id === 750);
}, 5000);

bench("arr-findLast", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  return arr.findLast(x => x < 500);
}, 10000);

bench("arr-every-some", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  return arr.every(x => x >= 0) && arr.some(x => x > 500);
}, 10000);

bench("arr-flat-flatMap", () => {
  const arr = [[1, 2], [3, [4, 5]], [6]];
  return arr.flat(2).length + [1, 2, 3].flatMap(x => [x, x * 2]).length;
}, 50000);

bench("arr-from-iterator", () => {
  return Array.from({length: 500}, (_, i) => i * i);
}, 10000);

bench("arr-spread-concat", () => {
  const a = [1, 2, 3], b = [4, 5, 6], c = [7, 8, 9];
  return [...a, ...b, ...c].length + a.concat(b, c).length;
}, 50000);

bench("arr-slice-splice", () => {
  const arr = Array.from({length: 100}, (_, i) => i);
  const sliced = arr.slice(10, 50);
  const copy = [...arr];
  copy.splice(10, 5, 99, 98, 97);
  return sliced.length + copy.length;
}, 20000);

bench("arr-reverse-fill", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  arr.reverse();
  arr.fill(0, 100, 200);
  return arr[0] + arr[100];
}, 10000);

bench("arr-copyWithin", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  arr.copyWithin(0, 500, 600);
  return arr[0];
}, 10000);

bench("arr-entries-keys-values", () => {
  const arr = [1, 2, 3, 4, 5];
  let sum = 0;
  for (const [k, v] of arr.entries()) sum += k + v;
  return sum;
}, 50000);

bench("arr-at-negative", () => {
  const arr = [1, 2, 3, 4, 5];
  return arr.at(0) + arr.at(-1) + arr.at(-2);
}, 200000);

bench("arr-isArray-checks", () => {
  return Array.isArray([]) + Array.isArray({}) + Array.isArray("") + Array.isArray(null);
}, 200000);

bench("arr-destructure-swap", () => {
  let a = 1, b = 2;
  for (let i = 0; i < 100; i++) [a, b] = [b, a];
  return a + b;
}, 50000);

bench("arr-reduce-groupBy", () => {
  const data = Array.from({length: 500}, (_, i) => ({cat: ["A","B","C"][i%3], val: i}));
  return data.reduce((acc, d) => {
    (acc[d.cat] = acc[d.cat] || []).push(d.val);
    return acc;
  }, {});
}, 5000);

bench("arr-nested-3d", () => {
  const m = [];
  for (let i = 0; i < 10; i++) {
    m[i] = [];
    for (let j = 0; j < 10; j++) {
      m[i][j] = [];
      for (let k = 0; k < 10; k++) m[i][j][k] = i * 100 + j * 10 + k;
    }
  }
  return m[5][5][5];
}, 5000);

bench("arr-sparse-access", () => {
  const arr = [];
  arr[0] = 1; arr[100] = 2; arr[999] = 3;
  return arr.length + (arr[50] === undefined ? 1 : 0);
}, 100000);

bench("arr-typed-uint8", () => {
  const buf = new Uint8Array(1024);
  for (let i = 0; i < 1024; i++) buf[i] = i & 0xff;
  let sum = 0;
  for (let i = 0; i < 1024; i++) sum += buf[i];
  return sum;
}, 10000);

bench("arr-typed-float64", () => {
  const buf = new Float64Array(256);
  for (let i = 0; i < 256; i++) buf[i] = Math.sin(i);
  let sum = 0;
  for (let i = 0; i < 256; i++) sum += buf[i];
  return sum;
}, 10000);

bench("arr-typed-int32-sort", () => {
  const buf = new Int32Array(1000);
  for (let i = 0; i < 1000; i++) buf[i] = (i * 7919) % 10000;
  buf.sort();
  return buf[0];
}, 2000);

bench("arr-arraybuffer-view", () => {
  const buf = new ArrayBuffer(16);
  const u8 = new Uint8Array(buf);
  const u32 = new Uint32Array(buf);
  u32[0] = 0xDEADBEEF;
  return u8[0] + u8[1] + u8[2] + u8[3];
}, 50000);

bench("arr-dataview-rw", () => {
  const buf = new ArrayBuffer(32);
  const dv = new DataView(buf);
  dv.setInt32(0, 42);
  dv.setFloat64(8, 3.14);
  return dv.getInt32(0) + dv.getFloat64(8);
}, 50000);

bench("arr-typed-set-subarray", () => {
  const src = new Uint8Array([1,2,3,4,5,6,7,8]);
  const dst = new Uint8Array(16);
  dst.set(src, 4);
  return dst.subarray(4, 8).length;
}, 50000);

bench("arr-for-of-iteration", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  let sum = 0;
  for (const x of arr) sum += x;
  return sum;
}, 5000);

bench("arr-forEach-perf", () => {
  const arr = Array.from({length: 1000}, (_, i) => i);
  let sum = 0;
  arr.forEach(x => sum += x);
  return sum;
}, 5000);

// ============================================================
// 3. OBJECT OPERATIONS (25 tests)
// ============================================================

bench("obj-create-literal", () => {
  const obj = {a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8};
  return obj.a + obj.h;
}, 200000);

bench("obj-create-null-proto", () => {
  const obj = Object.create(null);
  obj.key = "value";
  return obj.key;
}, 200000);

bench("obj-assign-spread", () => {
  const a = {x: 1, y: 2}, b = {y: 3, z: 4};
  return {...a, ...b, w: 5};
}, 100000);

bench("obj-keys-values-entries", () => {
  const obj = {a: 1, b: 2, c: 3, d: 4, e: 5};
  return Object.keys(obj).length + Object.values(obj).length + Object.entries(obj).length;
}, 100000);

bench("obj-hasOwn", () => {
  const obj = {a: 1, b: 2, c: 3};
  return Object.hasOwn(obj, "a") && Object.hasOwn(obj, "b") && !Object.hasOwn(obj, "d");
}, 200000);

bench("obj-freeze-seal", () => {
  const obj = {a: 1, b: 2};
  Object.freeze(obj);
  try { obj.a = 99; } catch(e) {}
  return obj.a;
}, 100000);

bench("obj-defineProperty", () => {
  const obj = {};
  Object.defineProperty(obj, "x", {value: 42, writable: false, enumerable: true});
  return obj.x;
}, 100000);

bench("obj-getOwnPropertyDescriptor", () => {
  const obj = {a: 1, b: 2};
  const d = Object.getOwnPropertyDescriptor(obj, "a");
  return d.value + (d.writable ? 1 : 0);
}, 100000);

bench("obj-computed-keys", () => {
  const prefix = "key";
  const obj = {};
  for (let i = 0; i < 100; i++) obj[prefix + i] = i;
  return Object.keys(obj).length;
}, 20000);

bench("obj-fromEntries", () => {
  const entries = Array.from({length: 50}, (_, i) => [`key${i}`, i]);
  return Object.fromEntries(entries);
}, 20000);

bench("obj-destructure-deep", () => {
  const data = {a: {b: {c: {d: {e: 42}}}}};
  const {a: {b: {c: {d: {e}}}}} = data;
  return e;
}, 200000);

bench("obj-property-access-chain", () => {
  const obj = {a: {b: {c: {d: {e: {f: 42}}}}}};
  return obj.a.b.c.d.e.f;
}, 200000);

bench("obj-optional-chaining", () => {
  const obj = {a: {b: {c: 42}}};
  return (obj?.a?.b?.c || 0) + (obj?.x?.y?.z || 0);
}, 200000);

bench("obj-in-operator", () => {
  const obj = {a: 1, b: 2, c: 3, d: 4, e: 5};
  return ("a" in obj) + ("f" in obj) + ("b" in obj);
}, 200000);

bench("obj-for-in-loop", () => {
  const obj = {};
  for (let i = 0; i < 100; i++) obj["key" + i] = i;
  let sum = 0;
  for (const key in obj) sum += obj[key];
  return sum;
}, 10000);

bench("obj-delete-property", () => {
  const obj = {a: 1, b: 2, c: 3, d: 4, e: 5};
  delete obj.c;
  delete obj.e;
  return Object.keys(obj).length;
}, 100000);

bench("obj-getter-setter", () => {
  const obj = {
    _val: 0,
    get val() { return this._val; },
    set val(v) { this._val = v; }
  };
  obj.val = 42;
  return obj.val;
}, 200000);

bench("obj-symbol-key", () => {
  const s = Symbol("test");
  const obj = {};
  obj[s] = 42;
  return obj[s];
}, 100000);

bench("obj-proxy-get", () => {
  const target = {a: 1, b: 2, c: 3};
  const handler = { get(t, k) { return t[k] * 2; } };
  const p = new Proxy(target, handler);
  return p.a + p.b + p.c;
}, 50000);

bench("obj-proxy-set-validate", () => {
  const handler = {
    set(t, k, v) { if (typeof v === "number") { t[k] = v; return true; } return false; }
  };
  const p = new Proxy({}, handler);
  p.x = 42;
  return p.x;
}, 50000);

bench("obj-weakmap-cache", () => {
  const wm = new WeakMap();
  const keys = Array.from({length: 100}, () => ({}));
  for (const k of keys) wm.set(k, Math.random());
  let sum = 0;
  for (const k of keys) sum += wm.get(k);
  return sum;
}, 10000);

bench("obj-reflect-api", () => {
  const obj = {a: 1};
  Reflect.set(obj, "b", 2);
  return Reflect.get(obj, "a") + Reflect.get(obj, "b") + Reflect.has(obj, "a");
}, 100000);

bench("obj-json-roundtrip-deep", () => {
  const obj = {a: [1, {b: [2, {c: 3}]}], d: "hello", e: true, f: null};
  return JSON.parse(JSON.stringify(obj));
}, 50000);

bench("obj-structuredClone-nested", () => {
  const obj = {arr: [1, 2, {nested: true}], str: "hello"};
  return structuredClone(obj);
}, 20000);

bench("obj-prototype-chain", () => {
  function Base() { this.x = 1; }
  Base.prototype.getX = function() { return this.x; };
  function Child() { Base.call(this); this.y = 2; }
  Child.prototype = Object.create(Base.prototype);
  const c = new Child();
  return c.getX() + c.y;
}, 100000);

// ============================================================
// 4. MAP / SET (15 tests)
// ============================================================

bench("map-set-get-10k", () => {
  const m = new Map();
  for (let i = 0; i < 10000; i++) m.set(`key-${i}`, i);
  let sum = 0;
  for (let i = 0; i < 10000; i++) sum += m.get(`key-${i}`);
  return sum;
}, 100);

bench("map-has-delete", () => {
  const m = new Map();
  for (let i = 0; i < 1000; i++) m.set(i, i * 2);
  let count = 0;
  for (let i = 0; i < 1000; i += 2) if (m.has(i)) { m.delete(i); count++; }
  return count;
}, 1000);

bench("map-iterate-entries", () => {
  const m = new Map(Array.from({length: 1000}, (_, i) => [i, i * 2]));
  let sum = 0;
  for (const [k, v] of m) sum += k + v;
  return sum;
}, 2000);

bench("map-object-keys", () => {
  const m = new Map();
  const keys = Array.from({length: 100}, () => ({}));
  for (const k of keys) m.set(k, Math.random());
  return m.size;
}, 10000);

bench("map-forEach", () => {
  const m = new Map(Array.from({length: 500}, (_, i) => [`k${i}`, i]));
  let sum = 0;
  m.forEach((v) => sum += v);
  return sum;
}, 5000);

bench("set-add-has-1k", () => {
  const s = new Set();
  for (let i = 0; i < 1000; i++) s.add(i);
  let found = 0;
  for (let i = 0; i < 1000; i++) if (s.has(i)) found++;
  return found;
}, 2000);

bench("set-union-intersect", () => {
  const a = new Set([1,2,3,4,5,6,7,8,9,10]);
  const b = new Set([5,6,7,8,9,10,11,12,13,14]);
  const union = new Set([...a, ...b]);
  const intersect = new Set([...a].filter(x => b.has(x)));
  return union.size + intersect.size;
}, 20000);

bench("set-delete-iteration", () => {
  const s = new Set(Array.from({length: 500}, (_, i) => i));
  for (let i = 0; i < 500; i += 3) s.delete(i);
  let sum = 0;
  for (const v of s) sum += v;
  return sum;
}, 2000);

bench("set-from-array-dedup", () => {
  const arr = Array.from({length: 1000}, (_, i) => i % 100);
  return new Set(arr).size;
}, 10000);

bench("weakmap-set-get", () => {
  const wm = new WeakMap();
  const objs = Array.from({length: 200}, () => ({}));
  for (const o of objs) wm.set(o, Math.random());
  let sum = 0;
  for (const o of objs) sum += wm.get(o);
  return sum;
}, 5000);

bench("weakset-add-has", () => {
  const ws = new WeakSet();
  const objs = Array.from({length: 200}, () => ({}));
  for (const o of objs) ws.add(o);
  let found = 0;
  for (const o of objs) if (ws.has(o)) found++;
  return found;
}, 5000);

bench("weakref-deref", () => {
  const objs = Array.from({length: 100}, () => ({}));
  const refs = objs.map(o => new WeakRef(o));
  let alive = 0;
  for (const r of refs) if (r.deref()) alive++;
  return alive;
}, 10000);

bench("map-chained-ops", () => {
  const m = new Map();
  for (let i = 0; i < 500; i++) m.set(i, i);
  const arr = [...m.values()].filter(v => v % 2 === 0).map(v => v * 3);
  return arr.length;
}, 2000);

bench("set-spread-array", () => {
  const s = new Set([1,2,3,4,5,6,7,8,9,10]);
  return [...s].reduce((a,b) => a+b, 0);
}, 50000);

bench("map-size-clear", () => {
  const m = new Map();
  for (let i = 0; i < 1000; i++) m.set(i, i);
  const size = m.size;
  m.clear();
  return size + m.size;
}, 5000);

// ============================================================
// 5. REGEXP (15 tests)
// ============================================================

bench("regex-simple-test", () => /^hello/.test("hello world"), 200000);

bench("regex-email-validate", () => {
  const re = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  return re.test("user@example.com") + re.test("bad@") + re.test("a+b@c.co");
}, 100000);

bench("regex-matchAll-groups", () => {
  const s = "price: $12.50, tax: $1.25, total: $13.75";
  const matches = [...s.matchAll(/\$(\d+\.\d+)/g)];
  return matches.length;
}, 50000);

bench("regex-named-groups", () => {
  const m = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/.exec("2024-03-15");
  return m.groups.year + m.groups.month + m.groups.day;
}, 100000);

bench("regex-replace-callback", () => {
  return "hello WORLD".replace(/[a-z]+/g, m => m.toUpperCase());
}, 100000);

bench("regex-split", () => {
  return "one::two:::three::::four".split(/:+/);
}, 100000);

bench("regex-lookbehind", () => {
  return "price: $100, cost: €200".match(/(?<=\$)\d+/g);
}, 100000);

bench("regex-lookahead", () => {
  return "100px 200em 300%".match(/\d+(?=px)/g);
}, 100000);

bench("regex-sticky-flag", () => {
  const re = /\d+/y;
  re.lastIndex = 0;
  const s = "123abc456";
  const m = re.exec(s);
  return m ? m[0] : "";
}, 200000);

bench("regex-unicode-flag", () => {
  return /café/u.test("I like café");
}, 100000);

bench("regex-complex-pattern", () => {
  const urlRe = /^(https?):\/\/([^/:]+)(:\d+)?(\/[^?#]*)(\?[^#]*)?(#.*)?$/;
  return urlRe.exec("https://example.com:8080/path?q=1#hash");
}, 100000);

bench("regex-greedy-vs-lazy", () => {
  const s = "<div>hello</div><div>world</div>";
  return s.match(/<div>.*?<\/div>/g);
}, 100000);

bench("regex-backreference", () => {
  return /(\w+)\s+\1/.test("hello hello");
}, 200000);

bench("regex-multiline", () => {
  const s = "line1\nline2\nline3";
  return s.match(/^line\d$/gm);
}, 100000);

bench("regex-compile-new", () => {
  for (let i = 0; i < 10; i++) new RegExp(`pattern${i}`, "gi");
  return true;
}, 20000);

// ============================================================
// 6. JSON (10 tests)
// ============================================================

bench("json-parse-small", () => JSON.parse('{"a":1,"b":"hello","c":true}'), 100000);

bench("json-parse-nested", () => {
  return JSON.parse('{"a":{"b":{"c":{"d":[1,2,3]}}}}');
}, 100000);

bench("json-stringify-small", () => JSON.stringify({a: 1, b: "hello", c: true}), 100000);

bench("json-stringify-array-100", () => {
  const arr = Array.from({length: 100}, (_, i) => ({id: i, name: `item${i}`}));
  return JSON.stringify(arr);
}, 5000);

bench("json-roundtrip-large", () => {
  const data = {users: Array.from({length: 50}, (_, i) => ({id: i, name: `u${i}`, scores: [1,2,3]}))};
  return JSON.parse(JSON.stringify(data));
}, 5000);

bench("json-stringify-replacer", () => {
  const obj = {a: 1, b: 2, secret: "hidden", c: 3};
  return JSON.stringify(obj, (k, v) => k === "secret" ? undefined : v);
}, 50000);

bench("json-parse-reviver", () => {
  return JSON.parse('{"date":"2024-01-15","count":"42"}', (k, v) => {
    if (k === "count") return parseInt(v);
    return v;
  });
}, 50000);

bench("json-stringify-indent", () => {
  return JSON.stringify({a: 1, b: [1, 2], c: {d: 3}}, null, 2);
}, 50000);

bench("json-parse-number-heavy", () => {
  return JSON.parse("[1.5,2.7,3.14159,0.001,1e10,1e-5,999999999]");
}, 100000);

bench("json-toJSON-custom", () => {
  const obj = {
    x: 1,
    toJSON() { return {x: this.x, serialized: true}; }
  };
  return JSON.stringify(obj);
}, 100000);

// ============================================================
// 7. MATH & NUMBERS (15 tests)
// ============================================================

bench("math-basic-ops", () => {
  let x = 1.5;
  for (let i = 0; i < 100; i++) x = (x * 3.14 + 2.71) / (x + 1);
  return x;
}, 50000);

bench("math-trig", () => {
  return Math.sin(1.5) + Math.cos(2.5) + Math.tan(0.5) + Math.atan2(1, 2);
}, 200000);

bench("math-sqrt-pow", () => {
  let sum = 0;
  for (let i = 1; i <= 100; i++) sum += Math.sqrt(i) + Math.pow(i, 1.5);
  return sum;
}, 50000);

bench("math-floor-ceil-round", () => {
  return Math.floor(3.7) + Math.ceil(3.2) + Math.round(3.5) + Math.trunc(-3.7);
}, 200000);

bench("math-min-max-clamp", () => {
  return Math.min(1, 2, 3) + Math.max(4, 5, 6) + Math.min(Math.max(5, 1), 10);
}, 200000);

bench("math-random-dist", () => {
  let sum = 0;
  for (let i = 0; i < 100; i++) sum += Math.random();
  return sum / 100;
}, 50000);

bench("math-log-exp", () => {
  return Math.log(100) + Math.exp(2) + Math.log2(8) + Math.log10(1000);
}, 200000);

bench("math-abs-sign", () => {
  return Math.abs(-42) + Math.sign(-5) + Math.sign(5) + Math.sign(0);
}, 200000);

bench("math-bitwise-ops", () => {
  let x = 0xDEADBEEF;
  x = (x << 3) | (x >>> 5);
  x = x ^ 0x12345678;
  x = x & 0xFFFF0000;
  return x;
}, 200000);

bench("math-bigint-ops", () => {
  let n = 1n;
  for (let i = 0n; i < 50n; i++) n = n * (i + 1n);
  return n.toString().length;
}, 10000);

bench("math-number-conversions", () => {
  return Number("42") + Number(true) + Number(null) + Number("3.14") + +"99";
}, 200000);

bench("math-isFinite-isNaN", () => {
  return Number.isFinite(42) + Number.isNaN(NaN) + Number.isInteger(3.0) + Number.isSafeInteger(2**53);
}, 200000);

bench("math-clz32-fround", () => {
  return Math.clz32(1) + Math.clz32(1000) + Math.fround(1.337);
}, 200000);

bench("math-hypot-cbrt", () => {
  return Math.hypot(3, 4) + Math.cbrt(27) + Math.hypot(1, 2, 3);
}, 200000);

bench("math-ieee754-edge", () => {
  return Number.EPSILON + Number.MAX_SAFE_INTEGER + Number.MIN_SAFE_INTEGER;
}, 200000);

// ============================================================
// 8. PROMISES & ASYNC (10 tests — sync measurement of creation overhead)
// ============================================================

bench("promise-create-resolve", () => {
  return new Promise(resolve => resolve(42));
}, 50000);

bench("promise-then-chain", () => {
  return Promise.resolve(1).then(x => x + 1).then(x => x + 1);
}, 20000);

bench("promise-all-small", () => {
  return Promise.all([
    Promise.resolve(1), Promise.resolve(2), Promise.resolve(3),
    Promise.resolve(4), Promise.resolve(5)
  ]);
}, 20000);

bench("promise-race", () => {
  return Promise.race([Promise.resolve("fast"), new Promise(() => {})]);
}, 20000);

bench("promise-allSettled", () => {
  return Promise.allSettled([
    Promise.resolve(1), Promise.reject("err"), Promise.resolve(3)
  ]);
}, 20000);

bench("promise-any", () => {
  return Promise.any([Promise.reject("a"), Promise.resolve("b"), Promise.reject("c")]);
}, 20000);

bench("promise-constructor-overhead", () => {
  const promises = [];
  for (let i = 0; i < 100; i++) promises.push(new Promise(r => r(i)));
  return promises.length;
}, 5000);

bench("promise-finally", () => {
  let count = 0;
  return Promise.resolve(42).finally(() => count++);
}, 20000);

bench("promise-catch-handler", () => {
  return Promise.reject("err").catch(e => e + " caught");
}, 20000);

bench("promise-nested-then", () => {
  return Promise.resolve(1)
    .then(x => Promise.resolve(x + 1))
    .then(x => Promise.resolve(x + 1))
    .then(x => Promise.resolve(x + 1));
}, 10000);

// ============================================================
// 9. ERROR HANDLING (10 tests)
// ============================================================

bench("error-try-catch", () => {
  try { throw new Error("test"); } catch(e) { return e.message; }
}, 50000);

bench("error-subtypes", () => {
  try { null.x; } catch(e) { return e instanceof TypeError; }
}, 50000);

bench("error-cause", () => {
  const e = new Error("outer", {cause: new Error("inner")});
  return e.cause.message;
}, 100000);

bench("error-stack-trace", () => {
  function a() { return new Error("trace"); }
  function b() { return a(); }
  function c() { return b(); }
  return c().stack.length > 0;
}, 50000);

bench("error-custom-class", () => {
  class AppError extends Error {
    constructor(msg, code) { super(msg); this.code = code; }
  }
  const e = new AppError("fail", 404);
  return e.code + e.message.length;
}, 100000);

bench("error-try-finally", () => {
  let x = 0;
  try { x = 1; } finally { x += 1; }
  return x;
}, 200000);

bench("error-no-throw-path", () => {
  try { return 42; } catch(e) { return -1; }
}, 200000);

bench("error-instanceof-check", () => {
  const e = new RangeError("out");
  return (e instanceof RangeError) + (e instanceof Error) + (e instanceof TypeError);
}, 200000);

bench("error-evalError", () => {
  try { throw new EvalError("bad eval"); } catch(e) { return e.name; }
}, 100000);

bench("error-aggregate", () => {
  const e = new AggregateError([new Error("a"), new Error("b")], "multi");
  return e.errors.length;
}, 100000);

// ============================================================
// 10. CLASSES & CLOSURES (15 tests)
// ============================================================

bench("class-basic-create", () => {
  class Point { constructor(x, y) { this.x = x; this.y = y; } }
  return new Point(1, 2);
}, 200000);

bench("class-method-call", () => {
  class Calc {
    constructor(v) { this.v = v; }
    add(n) { return this.v + n; }
    mul(n) { return this.v * n; }
  }
  const c = new Calc(10);
  return c.add(5) + c.mul(3);
}, 100000);

bench("class-inheritance", () => {
  class Animal { constructor(n) { this.name = n; } speak() { return this.name; } }
  class Dog extends Animal { speak() { return super.speak() + " barks"; } }
  return new Dog("Rex").speak();
}, 100000);

bench("class-static-method", () => {
  class MathHelper { static double(x) { return x * 2; } static triple(x) { return x * 3; } }
  return MathHelper.double(21) + MathHelper.triple(14);
}, 200000);

bench("class-getter-setter", () => {
  class Temp {
    #celsius;
    constructor(c) { this.#celsius = c; }
    get fahrenheit() { return this.#celsius * 9/5 + 32; }
    set fahrenheit(f) { this.#celsius = (f - 32) * 5/9; }
  }
  const t = new Temp(100);
  return t.fahrenheit;
}, 100000);

bench("class-private-fields", () => {
  class Counter {
    #count = 0;
    increment() { this.#count++; }
    get value() { return this.#count; }
  }
  const c = new Counter();
  for (let i = 0; i < 10; i++) c.increment();
  return c.value;
}, 100000);

bench("closure-counter", () => {
  function makeCounter() { let n = 0; return { inc() { n++; }, get() { return n; } }; }
  const c = makeCounter();
  for (let i = 0; i < 100; i++) c.inc();
  return c.get();
}, 50000);

bench("closure-memoize", () => {
  function memoize(fn) {
    const cache = new Map();
    return function(x) { if (!cache.has(x)) cache.set(x, fn(x)); return cache.get(x); };
  }
  const fib = memoize(function f(n) { return n < 2 ? n : f(n-1) + f(n-2); });
  return fib(30);
}, 10000);

bench("closure-iife", () => {
  return (function(x) { return x * x; })(42);
}, 200000);

bench("closure-currying", () => {
  const add = a => b => c => a + b + c;
  return add(1)(2)(3);
}, 200000);

bench("closure-compose", () => {
  const compose = (...fns) => x => fns.reduceRight((v, f) => f(v), x);
  const transform = compose(x => x * 2, x => x + 10, x => x * 3);
  return transform(5);
}, 50000);

bench("closure-partial-apply", () => {
  function partial(fn, ...args) { return (...rest) => fn(...args, ...rest); }
  const add3 = partial((a, b, c) => a + b + c, 1, 2);
  return add3(3);
}, 100000);

bench("closure-event-handler-pattern", () => {
  const handlers = [];
  for (let i = 0; i < 50; i++) handlers.push((e) => e + i);
  let sum = 0;
  for (const h of handlers) sum += h(1);
  return sum;
}, 20000);

bench("closure-scope-chain-deep", () => {
  function a(x) { return function b(y) { return function c(z) { return x + y + z; }; }; }
  return a(1)(2)(3);
}, 200000);

bench("class-instanceof-chain", () => {
  class A {} class B extends A {} class C extends B {}
  const obj = new C();
  return (obj instanceof C) + (obj instanceof B) + (obj instanceof A);
}, 200000);

// ============================================================
// 11. GENERATORS & ITERATORS (10 tests)
// ============================================================

bench("gen-basic-yield", () => {
  function* range(n) { for (let i = 0; i < n; i++) yield i; }
  let sum = 0;
  for (const x of range(100)) sum += x;
  return sum;
}, 10000);

bench("gen-fibonacci", () => {
  function* fib() { let a = 0, b = 1; while (true) { yield a; [a, b] = [b, a + b]; } }
  const it = fib();
  let last;
  for (let i = 0; i < 50; i++) last = it.next().value;
  return last;
}, 10000);

bench("gen-lazy-filter", () => {
  function* filter(iter, pred) { for (const x of iter) if (pred(x)) yield x; }
  function* range(n) { for (let i = 0; i < n; i++) yield i; }
  let count = 0;
  for (const x of filter(range(1000), x => x % 2 === 0)) count++;
  return count;
}, 2000);

bench("gen-yield-star", () => {
  function* a() { yield 1; yield 2; }
  function* b() { yield* a(); yield 3; yield* a(); }
  return [...b()].length;
}, 50000);

bench("gen-return-value", () => {
  function* g() { yield 1; yield 2; return 42; }
  const it = g();
  it.next(); it.next();
  return it.next().value;
}, 100000);

bench("gen-throw-catch", () => {
  function* g() { try { yield 1; } catch(e) { yield e; } }
  const it = g();
  it.next();
  return it.throw("error").value;
}, 50000);

bench("iterator-protocol", () => {
  const iterable = {
    [Symbol.iterator]() {
      let i = 0;
      return { next() { return i < 10 ? {value: i++, done: false} : {done: true}; } };
    }
  };
  let sum = 0;
  for (const x of iterable) sum += x;
  return sum;
}, 50000);

bench("iterator-spread-protocol", () => {
  const range = {
    from: 1, to: 5,
    [Symbol.iterator]() {
      let cur = this.from;
      const to = this.to;
      return { next() { return cur <= to ? {value: cur++, done: false} : {done: true}; } };
    }
  };
  return [...range].length;
}, 50000);

bench("gen-infinite-take", () => {
  function* naturals() { let n = 1; while (true) yield n++; }
  function take(iter, n) { const r = []; for (const x of iter) { r.push(x); if (r.length >= n) break; } return r; }
  return take(naturals(), 100).length;
}, 10000);

bench("gen-pipeline", () => {
  function* map(iter, fn) { for (const x of iter) yield fn(x); }
  function* filter(iter, fn) { for (const x of iter) if (fn(x)) yield x; }
  function* range(n) { for (let i = 0; i < n; i++) yield i; }
  let sum = 0;
  for (const x of map(filter(range(1000), x => x % 3 === 0), x => x * 2)) sum += x;
  return sum;
}, 2000);

// ============================================================
// 12. SYMBOL & WELL-KNOWN SYMBOLS (5 tests)
// ============================================================

bench("symbol-create-describe", () => {
  const s = Symbol("test");
  return s.description;
}, 200000);

bench("symbol-toPrimitive", () => {
  const obj = {
    [Symbol.toPrimitive](hint) {
      if (hint === "number") return 42;
      if (hint === "string") return "hello";
      return true;
    }
  };
  return +obj + `${obj}`;
}, 100000);

bench("symbol-iterator-custom", () => {
  const obj = {
    data: [10, 20, 30],
    [Symbol.iterator]() {
      let i = 0;
      return { next: () => i < this.data.length ? {value: this.data[i++]} : {done: true} };
    }
  };
  return [...obj].reduce((a,b) => a+b, 0);
}, 50000);

bench("symbol-hasInstance", () => {
  class EvenNumber { static [Symbol.hasInstance](n) { return typeof n === "number" && n % 2 === 0; } }
  return (4 instanceof EvenNumber) + (3 instanceof EvenNumber);
}, 100000);

bench("symbol-for-keyFor", () => {
  const s1 = Symbol.for("shared");
  const s2 = Symbol.for("shared");
  return (s1 === s2) + Symbol.keyFor(s1).length;
}, 100000);

// ============================================================
// 13. DATE (5 tests)
// ============================================================

bench("date-create-now", () => new Date(), 200000);
bench("date-parse-iso", () => new Date("2024-03-15T10:30:00Z").getTime(), 50000);
bench("date-getters", () => {
  const d = new Date(2024, 2, 15, 10, 30, 45);
  return d.getFullYear() + d.getMonth() + d.getDate() + d.getHours() + d.getMinutes();
}, 200000);
bench("date-toISOString", () => new Date().toISOString(), 50000);
bench("date-arithmetic", () => {
  const d1 = new Date(2024, 0, 1);
  const d2 = new Date(2024, 11, 31);
  return Math.floor((d2 - d1) / 86400000);
}, 100000);

// ============================================================
// 14. ENCODING & BINARY (10 tests)
// ============================================================

bench("textencoder-ascii", () => {
  const enc = new TextEncoder();
  return enc.encode("Hello, World!").length;
}, 100000);

bench("textencoder-unicode", () => {
  const enc = new TextEncoder();
  return enc.encode("日本語テスト 🌍🎉").length;
}, 100000);

bench("textdecoder-utf8", () => {
  const dec = new TextDecoder();
  const bytes = new Uint8Array([72, 101, 108, 108, 111]);
  return dec.decode(bytes);
}, 100000);

bench("textencoder-decoder-roundtrip", () => {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  return dec.decode(enc.encode("café résumé naïve"));
}, 50000);

bench("base64-encode-short", () => btoa("Hello"), 200000);
bench("base64-decode-short", () => atob("SGVsbG8="), 200000);
bench("base64-roundtrip-long", () => {
  const s = "The quick brown fox jumps over the lazy dog. 0123456789!@#$%^&*()";
  return atob(btoa(s));
}, 50000);

bench("uint8array-from-string", () => {
  const enc = new TextEncoder();
  const buf = enc.encode("hello world");
  let sum = 0;
  for (let i = 0; i < buf.length; i++) sum += buf[i];
  return sum;
}, 100000);

bench("arraybuffer-transfer", () => {
  const buf = new ArrayBuffer(1024);
  const u8 = new Uint8Array(buf);
  for (let i = 0; i < 1024; i++) u8[i] = i & 0xff;
  const u32 = new Uint32Array(buf);
  return u32[0];
}, 50000);

bench("typed-array-conversion", () => {
  const f32 = new Float32Array([1.5, 2.5, 3.5, 4.5]);
  const u8 = new Uint8Array(f32.buffer);
  return u8.length;
}, 100000);

// ============================================================
// 15. CONTROL FLOW & MISC (15 tests)
// ============================================================

bench("switch-statement-10", () => {
  let sum = 0;
  for (let i = 0; i < 10; i++) {
    switch(i) {
      case 0: sum += 1; break; case 1: sum += 2; break;
      case 2: sum += 3; break; case 3: sum += 4; break;
      case 4: sum += 5; break; case 5: sum += 6; break;
      case 6: sum += 7; break; case 7: sum += 8; break;
      case 8: sum += 9; break; case 9: sum += 10; break;
    }
  }
  return sum;
}, 200000);

bench("ternary-chain", () => {
  const x = 42;
  return x > 100 ? "big" : x > 50 ? "medium" : x > 25 ? "small" : "tiny";
}, 200000);

bench("nullish-coalescing-chain", () => {
  const a = null, b = undefined, c = 0, d = "";
  return (a ?? b ?? c ?? d ?? "default");
}, 200000);

bench("logical-assignment", () => {
  let a = null, b = 0, c = "";
  a ??= 42;
  b ||= 99;
  c &&= "hello";
  return a + b;
}, 200000);

bench("optional-chaining-deep", () => {
  const obj = {a: {b: {c: {d: 42}}}};
  return obj?.a?.b?.c?.d + (obj?.x?.y?.z ?? 0);
}, 200000);

bench("destructure-complex", () => {
  const data = {a: 1, b: [2, 3, [4, 5]], c: {d: 6}};
  const {a, b: [b1, b2, [b3, b4]], c: {d}} = data;
  return a + b1 + b2 + b3 + b4 + d;
}, 100000);

bench("spread-rest-params", () => {
  function sum(...args) { return args.reduce((a, b) => a + b, 0); }
  return sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
}, 100000);

bench("tagged-template", () => {
  function tag(strings, ...vals) { return strings.join("") + vals.join(""); }
  return tag`hello ${1} world ${2}`;
}, 100000);

bench("eval-simple", () => {
  return eval("1 + 2 + 3");
}, 10000);

bench("typeof-checks", () => {
  return typeof 1 + typeof "" + typeof true + typeof undefined + typeof null + typeof {};
}, 200000);

bench("instanceof-checks", () => {
  const d = new Date();
  const a = [];
  const r = /test/;
  return (d instanceof Date) + (a instanceof Array) + (r instanceof RegExp);
}, 200000);

bench("for-loop-classic", () => {
  let sum = 0;
  for (let i = 0; i < 10000; i++) sum += i;
  return sum;
}, 5000);

bench("while-loop-countdown", () => {
  let n = 10000, sum = 0;
  while (n > 0) sum += n--;
  return sum;
}, 5000);

bench("do-while-loop", () => {
  let n = 0, sum = 0;
  do { sum += n++; } while (n < 1000);
  return sum;
}, 10000);

bench("label-break-continue", () => {
  let sum = 0;
  outer: for (let i = 0; i < 10; i++) {
    for (let j = 0; j < 10; j++) {
      if (j === 5) continue outer;
      sum += i * 10 + j;
    }
  }
  return sum;
}, 50000);

// ============================================================
// 16. REAL-WORLD PATTERNS (20 tests)
// ============================================================

bench("rw-config-parse", () => {
  const config = '{"host":"localhost","port":3000,"db":{"url":"postgres://...","pool":10},"cache":{"ttl":300},"cors":{"origins":["*"]}}';
  const c = JSON.parse(config);
  return c.port + c.db.pool + c.cache.ttl;
}, 50000);

bench("rw-middleware-chain", () => {
  const middlewares = [];
  for (let i = 0; i < 20; i++) middlewares.push((ctx, next) => { ctx.count++; return next(); });
  const ctx = {count: 0};
  let idx = 0;
  function dispatch() { if (idx < middlewares.length) return middlewares[idx++](ctx, dispatch); }
  dispatch();
  return ctx.count;
}, 50000);

bench("rw-event-emitter-pattern", () => {
  const events = {};
  function on(name, fn) { (events[name] = events[name] || []).push(fn); }
  function emit(name, data) { (events[name] || []).forEach(fn => fn(data)); }
  on("data", d => d.count++);
  on("data", d => d.total += d.count);
  const state = {count: 0, total: 0};
  for (let i = 0; i < 100; i++) emit("data", state);
  return state.total;
}, 10000);

bench("rw-router-match", () => {
  const routes = [
    {pattern: /^\/api\/users\/(\d+)$/, handler: "getUser"},
    {pattern: /^\/api\/users$/, handler: "listUsers"},
    {pattern: /^\/api\/posts\/(\d+)\/comments$/, handler: "getComments"},
    {pattern: /^\/api\/health$/, handler: "health"},
  ];
  function match(path) {
    for (const r of routes) { const m = path.match(r.pattern); if (m) return {handler: r.handler, params: m.slice(1)}; }
    return null;
  }
  return match("/api/users/123").handler + match("/api/posts/42/comments").handler;
}, 50000);

bench("rw-template-engine", () => {
  const tpl = "Hello {{name}}, you have {{count}} messages!";
  const data = {name: "Alice", count: 42};
  return tpl.replace(/\{\{(\w+)\}\}/g, (_, key) => data[key] || "");
}, 50000);

bench("rw-csv-parse-simple", () => {
  const csv = "name,age,city\nAlice,30,NYC\nBob,25,LA\nCharlie,35,SF\nDiana,28,Boston\nEve,32,Seattle";
  const lines = csv.split("\n");
  const headers = lines[0].split(",");
  return lines.slice(1).map(line => {
    const vals = line.split(",");
    const obj = {};
    headers.forEach((h, i) => obj[h] = vals[i]);
    return obj;
  });
}, 20000);

bench("rw-uuid-generate", () => {
  const hex = "0123456789abcdef";
  let uuid = "";
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) uuid += "-";
    else uuid += hex[Math.random() * 16 | 0];
  }
  return uuid;
}, 50000);

bench("rw-debounce-create", () => {
  function debounce(fn, ms) {
    let timer;
    return function(...args) { clearTimeout(timer); timer = setTimeout(() => fn.apply(this, args), ms); };
  }
  const fn = debounce(x => x * 2, 100);
  return typeof fn;
}, 100000);

bench("rw-deep-equal", () => {
  function deepEqual(a, b) {
    if (a === b) return true;
    if (typeof a !== typeof b) return false;
    if (typeof a !== "object" || a === null) return false;
    const ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    return ka.every(k => deepEqual(a[k], b[k]));
  }
  return deepEqual({a: {b: [1,2,3]}, c: "hello"}, {a: {b: [1,2,3]}, c: "hello"});
}, 20000);

bench("rw-lru-cache", () => {
  class LRU {
    constructor(cap) { this.cap = cap; this.cache = new Map(); }
    get(k) { if (!this.cache.has(k)) return -1; const v = this.cache.get(k); this.cache.delete(k); this.cache.set(k, v); return v; }
    put(k, v) { if (this.cache.has(k)) this.cache.delete(k); else if (this.cache.size >= this.cap) this.cache.delete(this.cache.keys().next().value); this.cache.set(k, v); }
  }
  const c = new LRU(50);
  for (let i = 0; i < 200; i++) c.put(i, i * 2);
  let sum = 0;
  for (let i = 150; i < 200; i++) sum += c.get(i);
  return sum;
}, 5000);

bench("rw-observable-pattern", () => {
  class Observable {
    constructor() { this.subs = []; }
    subscribe(fn) { this.subs.push(fn); return () => { this.subs = this.subs.filter(s => s !== fn); }; }
    notify(data) { this.subs.forEach(fn => fn(data)); }
  }
  const obs = new Observable();
  let total = 0;
  obs.subscribe(v => total += v);
  obs.subscribe(v => total += v * 2);
  for (let i = 0; i < 100; i++) obs.notify(i);
  return total;
}, 5000);

bench("rw-state-machine", () => {
  const machine = {
    state: "idle",
    transitions: {
      idle: {START: "running"},
      running: {PAUSE: "paused", STOP: "idle"},
      paused: {RESUME: "running", STOP: "idle"}
    },
    send(event) {
      const next = this.transitions[this.state]?.[event];
      if (next) this.state = next;
      return this.state;
    }
  };
  machine.send("START"); machine.send("PAUSE"); machine.send("RESUME"); machine.send("STOP");
  return machine.state;
}, 100000);

bench("rw-query-builder", () => {
  class Query {
    constructor(t) { this.t = t; this.w = []; this.o = null; this.l = null; }
    where(c) { this.w.push(c); return this; }
    orderBy(f) { this.o = f; return this; }
    limit(n) { this.l = n; return this; }
    build() { let q = `SELECT * FROM ${this.t}`; if (this.w.length) q += ` WHERE ${this.w.join(" AND ")}`; if (this.o) q += ` ORDER BY ${this.o}`; if (this.l) q += ` LIMIT ${this.l}`; return q; }
  }
  return new Query("users").where("age > 18").where("active = true").orderBy("name").limit(10).build();
}, 50000);

bench("rw-diff-objects", () => {
  function diff(a, b) {
    const changes = {};
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
      if (a[k] !== b[k]) changes[k] = {from: a[k], to: b[k]};
    }
    return changes;
  }
  return diff({a: 1, b: 2, c: 3}, {a: 1, b: 99, d: 4});
}, 50000);

bench("rw-retry-logic", () => {
  function retry(fn, maxRetries) {
    let attempt = 0;
    while (attempt < maxRetries) {
      try { return fn(attempt); } catch(e) { attempt++; }
    }
    throw new Error("Max retries exceeded");
  }
  return retry((n) => { if (n < 2) throw new Error("fail"); return "success"; }, 5);
}, 50000);

bench("rw-pipe-transform", () => {
  const pipe = (...fns) => x => fns.reduce((v, f) => f(v), x);
  const process = pipe(
    x => x.trim(),
    x => x.toLowerCase(),
    x => x.replace(/\s+/g, "-"),
    x => x.replace(/[^a-z0-9-]/g, ""),
    x => x.slice(0, 50)
  );
  return process("  Hello World! This is a Test  ");
}, 50000);

bench("rw-schema-validate", () => {
  function validate(schema, data) {
    for (const [key, type] of Object.entries(schema)) {
      if (typeof data[key] !== type) return false;
    }
    return true;
  }
  const schema = {name: "string", age: "number", active: "boolean"};
  return validate(schema, {name: "Alice", age: 30, active: true});
}, 100000);

bench("rw-pagination", () => {
  const items = Array.from({length: 1000}, (_, i) => ({id: i, name: `Item ${i}`}));
  function paginate(arr, page, size) {
    const start = (page - 1) * size;
    return {data: arr.slice(start, start + size), total: arr.length, pages: Math.ceil(arr.length / size)};
  }
  return paginate(items, 5, 20);
}, 10000);

bench("rw-tree-traverse", () => {
  function buildTree(depth) {
    if (depth === 0) return {val: 1, children: []};
    return {val: depth, children: [buildTree(depth - 1), buildTree(depth - 1)]};
  }
  function sum(node) {
    return node.val + node.children.reduce((s, c) => s + sum(c), 0);
  }
  return sum(buildTree(8));
}, 500);

bench("rw-flatten-deep", () => {
  function flattenDeep(arr) {
    const result = [];
    const stack = [...arr];
    while (stack.length) {
      const item = stack.pop();
      if (Array.isArray(item)) stack.push(...item);
      else result.push(item);
    }
    return result;
  }
  return flattenDeep([1, [2, [3, [4, [5]]]], [6, [7]]]).length;
}, 50000);

// ============================================================
// Summary
// ============================================================

console.log(`\nStress Benchmark Complete: ${testCount} tests`);
let total = 0;
for (const [name, r] of Object.entries(results)) total += r.elapsed;
console.log(`Total wall time: ${total}ms`);

// Category summary
const categories = {};
for (const [name, r] of Object.entries(results)) {
  const cat = name.split("-")[0];
  categories[cat] = (categories[cat] || 0) + r.elapsed;
}
console.log("\nBy category:");
for (const [cat, ms] of Object.entries(categories).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${cat}: ${ms}ms`);
}
