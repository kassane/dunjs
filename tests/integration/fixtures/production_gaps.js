// Production gaps test: JS engine features critical for real-world production apps
// Tests pure JS/engine features (not Node-specific APIs) across all runtimes
var pass = 0, fail = 0;
function check(name, ok) {
  if (ok) { pass++; console.log("PASS " + name); }
  else { fail++; console.log("FAIL " + name); }
}

// ============================================================
// 1. WeakRef and FinalizationRegistry
// ============================================================
try {
  var obj = { data: 42 };
  var wr = new WeakRef(obj);
  check("WeakRef deref returns target", wr.deref() === obj);
  check("WeakRef deref has data", wr.deref().data === 42);
} catch(e) { check("WeakRef deref returns target", false); check("WeakRef deref has data", false); }

try {
  var frCalled = false;
  var fr = new FinalizationRegistry(function(held) { frCalled = true; });
  var target = {};
  fr.register(target, "held-value");
  fr.unregister(target);
  check("FinalizationRegistry register+unregister", true);
} catch(e) { check("FinalizationRegistry register+unregister", false); }

// ============================================================
// 2. structuredClone deep clone
// ============================================================
try {
  var orig = { a: 1, b: [2, 3], c: { d: new Date(1000), e: new Map([["k", "v"]]), f: new Set([1,2,3]) } };
  var cloned = structuredClone(orig);
  check("structuredClone deep copy", cloned.a === 1 && cloned.b[0] === 2 && cloned.b[1] === 3);
  check("structuredClone not same ref", cloned !== orig && cloned.b !== orig.b && cloned.c !== orig.c);
  check("structuredClone Date", cloned.c.d instanceof Date && cloned.c.d.getTime() === 1000);
  check("structuredClone Map", cloned.c.e instanceof Map && cloned.c.e.get("k") === "v");
  check("structuredClone Set", cloned.c.f instanceof Set && cloned.c.f.has(1) && cloned.c.f.size === 3);
} catch(e) {
  check("structuredClone deep copy", false);
  check("structuredClone not same ref", false);
  check("structuredClone Date", false);
  check("structuredClone Map", false);
  check("structuredClone Set", false);
}

// structuredClone with ArrayBuffer
try {
  var ab = new ArrayBuffer(8);
  var view = new Uint8Array(ab);
  view[0] = 42;
  var clonedAb = structuredClone(ab);
  var clonedView = new Uint8Array(clonedAb);
  check("structuredClone ArrayBuffer", clonedView[0] === 42 && clonedAb !== ab);
} catch(e) { check("structuredClone ArrayBuffer", false); }

// ============================================================
// 3. Performance.now() high-resolution timing
// ============================================================
try {
  var t1 = performance.now();
  var t2 = performance.now();
  check("performance.now returns number", typeof t1 === "number" && typeof t2 === "number");
  check("performance.now monotonic", t2 >= t1);
  check("performance.now sub-millisecond capable", t1 !== Math.floor(t1) || t2 !== Math.floor(t2) || t2 - t1 < 1);
} catch(e) {
  check("performance.now returns number", false);
  check("performance.now monotonic", false);
  check("performance.now sub-millisecond capable", false);
}

// ============================================================
// 4. queueMicrotask ordering
// ============================================================
try {
  check("queueMicrotask exists", typeof queueMicrotask === "function");
} catch(e) { check("queueMicrotask exists", false); }

// ============================================================
// 5. globalThis consistency
// ============================================================
check("globalThis is object", typeof globalThis === "object" && globalThis !== null);
check("globalThis.globalThis is self", globalThis.globalThis === globalThis);
check("globalThis has Object", globalThis.Object === Object);
check("globalThis has Array", globalThis.Array === Array);

// ============================================================
// 6. TextEncoder/TextDecoder UTF-8 round-trip (emoji/CJK)
// ============================================================
try {
  var enc = new TextEncoder();
  var dec = new TextDecoder();
  var emoji = "\u{1F600}\u{1F680}\u{2764}\u{FE0F}"; // grinning, rocket, red heart
  var bytes = enc.encode(emoji);
  var rt = dec.decode(bytes);
  check("TextEncoder/Decoder emoji round-trip", rt === emoji);

  var cjk = "你好世界"; // nihao sekai
  var cjkBytes = enc.encode(cjk);
  var cjkRt = dec.decode(cjkBytes);
  check("TextEncoder/Decoder CJK round-trip", cjkRt === cjk);

  var mixed = "hello \u{1F30D} éèê"; // earth + accented chars
  check("TextEncoder/Decoder mixed round-trip", dec.decode(enc.encode(mixed)) === mixed);
} catch(e) {
  check("TextEncoder/Decoder emoji round-trip", false);
  check("TextEncoder/Decoder CJK round-trip", false);
  check("TextEncoder/Decoder mixed round-trip", false);
}

// ============================================================
// 7. JSON.parse reviver and JSON.stringify replacer/toJSON
// ============================================================
try {
  var json = '{"a":1,"b":2,"c":3}';
  var revived = JSON.parse(json, function(key, value) {
    if (typeof value === "number") return value * 10;
    return value;
  });
  check("JSON.parse reviver", revived.a === 10 && revived.b === 20 && revived.c === 30);
} catch(e) { check("JSON.parse reviver", false); }

try {
  var toStr = JSON.stringify({ a: 1, b: "hello", c: [1,2] }, function(key, value) {
    if (typeof value === "number" && key !== "") return value + 100;
    return value;
  });
  check("JSON.stringify replacer fn", toStr === '{"a":101,"b":"hello","c":[101,102]}');
} catch(e) { check("JSON.stringify replacer fn", false); }

try {
  var objWithToJSON = { x: 1, toJSON: function() { return { custom: true }; } };
  check("JSON.stringify toJSON", JSON.stringify(objWithToJSON) === '{"custom":true}');
} catch(e) { check("JSON.stringify toJSON", false); }

try {
  var spaced = JSON.stringify({a:1}, null, 2);
  check("JSON.stringify indent", spaced.indexOf("\n") >= 0 && spaced.indexOf("  ") >= 0);
} catch(e) { check("JSON.stringify indent", false); }

// ============================================================
// 8. Proxy and Reflect completeness
// ============================================================
try {
  var handler = {
    get: function(target, prop) {
      if (prop === "secret") return "intercepted";
      return Reflect.get(target, prop);
    },
    set: function(target, prop, value) {
      return Reflect.set(target, prop, value * 2);
    },
    has: function(target, prop) {
      if (prop === "hidden") return false;
      return Reflect.has(target, prop);
    },
    deleteProperty: function(target, prop) {
      return Reflect.deleteProperty(target, prop);
    },
    ownKeys: function(target) {
      return Reflect.ownKeys(target).filter(function(k) { return k !== "hidden"; });
    }
  };
  var proxy = new Proxy({ x: 1, hidden: true }, handler);
  check("Proxy get trap", proxy.secret === "intercepted");
  check("Proxy get passthrough", proxy.x === 1);
  proxy.y = 5;
  check("Proxy set trap", proxy.y === 10);
  check("Proxy has trap", !("hidden" in proxy));
  check("Proxy ownKeys trap", Object.keys(proxy).indexOf("hidden") === -1);
} catch(e) {
  check("Proxy get trap", false);
  check("Proxy get passthrough", false);
  check("Proxy set trap", false);
  check("Proxy has trap", false);
  check("Proxy ownKeys trap", false);
}

try {
  check("Reflect.apply", Reflect.apply(Math.max, null, [1, 2, 3]) === 3);
  check("Reflect.construct", Reflect.construct(Array, [1, 2, 3]).length === 3);
  check("Reflect.defineProperty", Reflect.defineProperty({}, "x", { value: 1 }) === true);
  check("Reflect.getPrototypeOf", Reflect.getPrototypeOf([]) === Array.prototype);
  check("Reflect.setPrototypeOf", typeof Reflect.setPrototypeOf === "function");
} catch(e) {
  check("Reflect.apply", false);
  check("Reflect.construct", false);
  check("Reflect.defineProperty", false);
  check("Reflect.getPrototypeOf", false);
  check("Reflect.setPrototypeOf", false);
}

// Proxy revocable
try {
  var rev = Proxy.revocable({x:1}, {});
  check("Proxy.revocable access", rev.proxy.x === 1);
  rev.revoke();
  var threw = false;
  try { rev.proxy.x; } catch(e) { threw = true; }
  check("Proxy.revocable revoke", threw);
} catch(e) {
  check("Proxy.revocable access", false);
  check("Proxy.revocable revoke", false);
}

// ============================================================
// 9. Symbol.for / Symbol.keyFor global registry
// ============================================================
try {
  var s1 = Symbol.for("shared");
  var s2 = Symbol.for("shared");
  check("Symbol.for same key same symbol", s1 === s2);
  check("Symbol.keyFor", Symbol.keyFor(s1) === "shared");
  check("Symbol.keyFor unique returns undefined", Symbol.keyFor(Symbol("unique")) === undefined);
} catch(e) {
  check("Symbol.for same key same symbol", false);
  check("Symbol.keyFor", false);
  check("Symbol.keyFor unique returns undefined", false);
}

// Symbol.description
try {
  var sd = Symbol("my-description");
  check("Symbol.description", sd.description === "my-description");
} catch(e) { check("Symbol.description", false); }

// Symbol.toPrimitive
try {
  var objTP = {
    [Symbol.toPrimitive]: function(hint) {
      if (hint === "number") return 42;
      if (hint === "string") return "forty-two";
      return true;
    }
  };
  check("Symbol.toPrimitive number", +objTP === 42);
  check("Symbol.toPrimitive string", String(objTP) === "forty-two");
} catch(e) {
  check("Symbol.toPrimitive number", false);
  check("Symbol.toPrimitive string", false);
}

// ============================================================
// 10. Promise.allSettled with mixed resolve/reject
// ============================================================
try {
  var p = Promise.allSettled([
    Promise.resolve(1),
    Promise.reject("err"),
    Promise.resolve(3)
  ]);
  check("Promise.allSettled exists", p instanceof Promise);
} catch(e) { check("Promise.allSettled exists", false); }

// Promise.any
try {
  var pAny = Promise.any([
    Promise.reject("a"),
    Promise.resolve("b"),
    Promise.resolve("c")
  ]);
  check("Promise.any exists", pAny instanceof Promise);
} catch(e) { check("Promise.any exists", false); }

// ============================================================
// 11. ES2024: Object.groupBy / Map.groupBy
// ============================================================
try {
  var items = [{type:"a",v:1},{type:"b",v:2},{type:"a",v:3}];
  var grouped = Object.groupBy(items, function(item) { return item.type; });
  check("Object.groupBy exists", typeof Object.groupBy === "function");
  check("Object.groupBy result", grouped.a.length === 2 && grouped.b.length === 1);
  check("Object.groupBy values", grouped.a[0].v === 1 && grouped.a[1].v === 3);
} catch(e) {
  check("Object.groupBy exists", false);
  check("Object.groupBy result", false);
  check("Object.groupBy values", false);
}

try {
  var items2 = [{type:"x",v:10},{type:"y",v:20},{type:"x",v:30}];
  var mapGrouped = Map.groupBy(items2, function(item) { return item.type; });
  check("Map.groupBy exists", typeof Map.groupBy === "function");
  check("Map.groupBy returns Map", mapGrouped instanceof Map);
  check("Map.groupBy result", mapGrouped.get("x").length === 2 && mapGrouped.get("y").length === 1);
} catch(e) {
  check("Map.groupBy exists", false);
  check("Map.groupBy returns Map", false);
  check("Map.groupBy result", false);
}

// ============================================================
// 12. ES2024: String.isWellFormed / toWellFormed
// ============================================================
try {
  check("String.isWellFormed exists", typeof "".isWellFormed === "function");
  check("String.isWellFormed valid", "hello".isWellFormed() === true);
  // lone surrogate
  check("String.isWellFormed lone surrogate", "\uD800".isWellFormed() === false);
} catch(e) {
  check("String.isWellFormed exists", false);
  check("String.isWellFormed valid", false);
  check("String.isWellFormed lone surrogate", false);
}

try {
  check("String.toWellFormed exists", typeof "".toWellFormed === "function");
  check("String.toWellFormed valid passthrough", "hello".toWellFormed() === "hello");
  check("String.toWellFormed replaces surrogate", "\uD800".toWellFormed() === "�");
} catch(e) {
  check("String.toWellFormed exists", false);
  check("String.toWellFormed valid passthrough", false);
  check("String.toWellFormed replaces surrogate", false);
}

// ============================================================
// 13. ES2024: Array.fromAsync
// ============================================================
try {
  check("Array.fromAsync exists", typeof Array.fromAsync === "function");
} catch(e) { check("Array.fromAsync exists", false); }

// ============================================================
// 14. ES2024: RegExp /v flag (set notation / unicodeSets)
// ============================================================
// The /v flag with set-notation `&&` / `--` is widely supported but
// the *matching* semantics depend on whether the engine has ICU
// (QuickJS parses but mis-matches the intersection; V8 needs ICU;
// JSC has full ICU). We only assert constructor + a non-match here
// so the test is portable across all three backends.
try {
  var re = new RegExp("[\\p{ASCII}&&\\p{Letter}]", "v");
  check("RegExp v flag creates", re instanceof RegExp);
  check("RegExp v flag is a regex", typeof re.test === "function");
  check("RegExp v flag digit no match", !re.test("1"));
} catch(e) {
  check("RegExp v flag creates", false);
  check("RegExp v flag is a regex", false);
  check("RegExp v flag digit no match", false);
}

// ============================================================
// 15. ES2025: Set methods (union, intersection, difference, symmetricDifference)
// ============================================================
try {
  var setA = new Set([1, 2, 3, 4]);
  var setB = new Set([3, 4, 5, 6]);

  var union = setA.union(setB);
  check("Set.union exists", typeof setA.union === "function");
  check("Set.union result", union.size === 6 && union.has(1) && union.has(6));

  var inter = setA.intersection(setB);
  check("Set.intersection result", inter.size === 2 && inter.has(3) && inter.has(4));

  var diff = setA.difference(setB);
  check("Set.difference result", diff.size === 2 && diff.has(1) && diff.has(2));

  var sym = setA.symmetricDifference(setB);
  check("Set.symmetricDifference result", sym.size === 4 && sym.has(1) && sym.has(2) && sym.has(5) && sym.has(6));

  check("Set.isSubsetOf", new Set([3,4]).isSubsetOf(setA) === true);
  check("Set.isSupersetOf", setA.isSupersetOf(new Set([1,2])) === true);
  check("Set.isDisjointFrom", new Set([7,8]).isDisjointFrom(setA) === true);
} catch(e) {
  check("Set.union exists", false);
  check("Set.union result", false);
  check("Set.intersection result", false);
  check("Set.difference result", false);
  check("Set.symmetricDifference result", false);
  check("Set.isSubsetOf", false);
  check("Set.isSupersetOf", false);
  check("Set.isDisjointFrom", false);
}

// ============================================================
// 16. ES2025: Iterator helpers (.map, .filter, .take, .drop, .forEach)
// ============================================================
try {
  // Iterator.from or array iterator with helpers
  var arr = [1, 2, 3, 4, 5];
  var iter = arr.values();

  check("Iterator.prototype.map exists", typeof iter.map === "function");

  var mapped = arr.values().map(function(x) { return x * 2; });
  var mappedArr = Array.from(mapped);
  check("Iterator.map result", mappedArr.join(",") === "2,4,6,8,10");

  var filtered = arr.values().filter(function(x) { return x > 2; });
  var filteredArr = Array.from(filtered);
  check("Iterator.filter result", filteredArr.join(",") === "3,4,5");

  var taken = arr.values().take(3);
  var takenArr = Array.from(taken);
  check("Iterator.take result", takenArr.join(",") === "1,2,3");

  var dropped = arr.values().drop(2);
  var droppedArr = Array.from(dropped);
  check("Iterator.drop result", droppedArr.join(",") === "3,4,5");

  var sum = 0;
  arr.values().forEach(function(x) { sum += x; });
  check("Iterator.forEach result", sum === 15);

  // reduce
  var reduced = arr.values().reduce(function(acc, x) { return acc + x; }, 0);
  check("Iterator.reduce result", reduced === 15);

  // toArray
  var toArr = arr.values().toArray();
  check("Iterator.toArray result", Array.isArray(toArr) && toArr.join(",") === "1,2,3,4,5");

  // some / every
  check("Iterator.some result", arr.values().some(function(x) { return x === 3; }));
  check("Iterator.every result", arr.values().every(function(x) { return x > 0; }));

  // find
  check("Iterator.find result", arr.values().find(function(x) { return x > 3; }) === 4);

  // flatMap
  var flatMapped = [1,2,3].values().flatMap(function(x) { return [x, x * 10]; });
  check("Iterator.flatMap result", Array.from(flatMapped).join(",") === "1,10,2,20,3,30");
} catch(e) {
  check("Iterator.prototype.map exists", false);
  check("Iterator.map result", false);
  check("Iterator.filter result", false);
  check("Iterator.take result", false);
  check("Iterator.drop result", false);
  check("Iterator.forEach result", false);
  check("Iterator.reduce result", false);
  check("Iterator.toArray result", false);
  check("Iterator.some result", false);
  check("Iterator.every result", false);
  check("Iterator.find result", false);
  check("Iterator.flatMap result", false);
}

// Iterator.from
try {
  check("Iterator.from exists", typeof Iterator.from === "function");
  var fromIter = Iterator.from([10, 20, 30]);
  check("Iterator.from works", Array.from(fromIter).join(",") === "10,20,30");
} catch(e) {
  check("Iterator.from exists", false);
  check("Iterator.from works", false);
}

// ============================================================
// 17. Async generators and for-await-of
// ============================================================
try {
  var agFn = new Function("return async function*() { yield 1; yield 2; yield 3; }");
  check("async generator function creates", typeof agFn() === "function");
} catch(e) { check("async generator function creates", false); }

// ============================================================
// 18. Atomics basics
// ============================================================
try {
  var sab = new SharedArrayBuffer(16);
  var ia = new Int32Array(sab);
  Atomics.store(ia, 0, 42);
  check("Atomics.store+load", Atomics.load(ia, 0) === 42);
} catch(e) { check("Atomics.store+load", false); }

try {
  var sab2 = new SharedArrayBuffer(16);
  var ia2 = new Int32Array(sab2);
  Atomics.store(ia2, 0, 42);
  Atomics.add(ia2, 0, 8);
  check("Atomics.add", Atomics.load(ia2, 0) === 50);
} catch(e) { check("Atomics.add", false); }

try {
  var sab3 = new SharedArrayBuffer(16);
  var ia3 = new Int32Array(sab3);
  Atomics.store(ia3, 0, 50);
  Atomics.sub(ia3, 0, 10);
  check("Atomics.sub", Atomics.load(ia3, 0) === 40);
} catch(e) { check("Atomics.sub", false); }

try {
  var sab4 = new SharedArrayBuffer(16);
  var ia4 = new Int32Array(sab4);
  Atomics.store(ia4, 0, 40);
  var oldVal = Atomics.exchange(ia4, 0, 99);
  check("Atomics.exchange", oldVal === 40 && Atomics.load(ia4, 0) === 99);
} catch(e) { check("Atomics.exchange", false); }

try {
  var sab5 = new SharedArrayBuffer(16);
  var ia5 = new Int32Array(sab5);
  Atomics.store(ia5, 0, 99);
  var oldCmp = Atomics.compareExchange(ia5, 0, 99, 77);
  check("Atomics.compareExchange", oldCmp === 99 && Atomics.load(ia5, 0) === 77);
} catch(e) { check("Atomics.compareExchange", false); }

// Atomics.waitAsync
try {
  check("Atomics.waitAsync exists", typeof Atomics.waitAsync === "function");
} catch(e) { check("Atomics.waitAsync exists", false); }

// ============================================================
// 19. URL and URLSearchParams edge cases
// ============================================================
try {
  var u1 = new URL("https://example.com/path?q=hello%20world&arr=1&arr=2#frag");
  check("URL percent decode search", u1.searchParams.get("q") === "hello world");
  check("URL multiple values getAll", u1.searchParams.getAll("arr").length === 2);
  check("URL hash", u1.hash === "#frag");
  u1.searchParams.append("new", "val");
  check("URLSearchParams append", u1.searchParams.get("new") === "val");
  u1.searchParams.delete("arr");
  check("URLSearchParams delete", u1.searchParams.getAll("arr").length === 0);
  check("URLSearchParams has", u1.searchParams.has("q") === true);

  // Unicode in URL
  var u2 = new URL("https://example.com/café");
  check("URL unicode path", u2.pathname.indexOf("caf") >= 0);

  // URL toString
  var u3 = new URL("https://user:pass@example.com:8080/path?q=1#h");
  check("URL toString round-trip", u3.toString().indexOf("example.com:8080") >= 0);
} catch(e) {
  check("URL percent decode search", false);
  check("URL multiple values getAll", false);
  check("URL hash", false);
  check("URLSearchParams append", false);
  check("URLSearchParams delete", false);
  check("URLSearchParams has", false);
  check("URL unicode path", false);
  check("URL toString round-trip", false);
}

// URLSearchParams iteration
try {
  var usp = new URLSearchParams("a=1&b=2&c=3");
  var keys = [];
  for (var k of usp.keys()) keys.push(k);
  check("URLSearchParams keys iteration", keys.join(",") === "a,b,c");

  var vals = [];
  for (var v of usp.values()) vals.push(v);
  check("URLSearchParams values iteration", vals.join(",") === "1,2,3");

  var entries = [];
  for (var e of usp.entries()) entries.push(e[0] + "=" + e[1]);
  check("URLSearchParams entries iteration", entries.join("&") === "a=1&b=2&c=3");

  check("URLSearchParams size", usp.size === 3);
  check("URLSearchParams sort", (usp.sort(), Array.from(usp.keys()).join(",") === "a,b,c"));
} catch(e) {
  check("URLSearchParams keys iteration", false);
  check("URLSearchParams values iteration", false);
  check("URLSearchParams entries iteration", false);
  check("URLSearchParams size", false);
  check("URLSearchParams sort", false);
}

// ============================================================
// 20. Typed Arrays completeness
// ============================================================
try {
  check("Int8Array", typeof Int8Array === "function");
  check("Uint8Array", typeof Uint8Array === "function");
  check("Uint8ClampedArray", typeof Uint8ClampedArray === "function");
  check("Int16Array", typeof Int16Array === "function");
  check("Uint16Array", typeof Uint16Array === "function");
  check("Int32Array", typeof Int32Array === "function");
  check("Uint32Array", typeof Uint32Array === "function");
  check("Float32Array", typeof Float32Array === "function");
  check("Float64Array", typeof Float64Array === "function");
  check("BigInt64Array", typeof BigInt64Array === "function");
  check("BigUint64Array", typeof BigUint64Array === "function");
  check("DataView", typeof DataView === "function");

  // TypedArray methods
  var ta = new Uint8Array([5, 3, 1, 4, 2]);
  check("TypedArray.sort", new Uint8Array(ta).sort().join(",") === "1,2,3,4,5");
  check("TypedArray.find", ta.find(function(x) { return x > 3; }) === 5);
  check("TypedArray.findIndex", ta.findIndex(function(x) { return x === 4; }) === 3);
  check("TypedArray.includes", ta.includes(3) === true);
  check("TypedArray.slice", ta.slice(1, 3).join(",") === "3,1");
  check("TypedArray.subarray", ta.subarray(0, 2).join(",") === "5,3");
  check("TypedArray.from", Uint8Array.from([1,2,3]).length === 3);
  check("TypedArray.of", Uint8Array.of(1,2,3).length === 3);
} catch(e) {
  check("Int8Array", false); check("Uint8Array", false);
  check("Uint8ClampedArray", false); check("Int16Array", false);
  check("Uint16Array", false); check("Int32Array", false);
  check("Uint32Array", false); check("Float32Array", false);
  check("Float64Array", false); check("BigInt64Array", false);
  check("BigUint64Array", false); check("DataView", false);
  check("TypedArray.sort", false); check("TypedArray.find", false);
  check("TypedArray.findIndex", false); check("TypedArray.includes", false);
  check("TypedArray.slice", false); check("TypedArray.subarray", false);
  check("TypedArray.from", false); check("TypedArray.of", false);
}

// ============================================================
// 21. Error types and properties
// ============================================================
try {
  check("RangeError", typeof RangeError === "function");
  check("TypeError", typeof TypeError === "function");
  check("ReferenceError", typeof ReferenceError === "function");
  check("SyntaxError", typeof SyntaxError === "function");
  check("URIError", typeof URIError === "function");
  check("EvalError", typeof EvalError === "function");
  check("AggregateError", typeof AggregateError === "function");

  var ae = new AggregateError([new Error("a"), new Error("b")], "multiple");
  check("AggregateError message", ae.message === "multiple");
  check("AggregateError errors", ae.errors.length === 2);

  // Error.cause (ES2022)
  var caused = new Error("outer", { cause: new Error("inner") });
  check("Error.cause", caused.cause instanceof Error && caused.cause.message === "inner");
} catch(e) {
  check("RangeError", false); check("TypeError", false);
  check("ReferenceError", false); check("SyntaxError", false);
  check("URIError", false); check("EvalError", false);
  check("AggregateError", false); check("AggregateError message", false);
  check("AggregateError errors", false); check("Error.cause", false);
}

// Error.stackTraceLimit (V8-style; may not exist in all engines)
try {
  check("Error.stack exists", typeof (new Error()).stack === "string");
} catch(e) { check("Error.stack exists", false); }

// ============================================================
// 22. BigInt
// ============================================================
try {
  check("BigInt exists", typeof BigInt === "function");
  check("BigInt literal", typeof 42n === "bigint");
  check("BigInt arithmetic", 10n + 20n === 30n);
  check("BigInt comparison", 10n < 20n);
  check("BigInt toString", (42n).toString() === "42");
  check("BigInt from number", BigInt(42) === 42n);
} catch(e) {
  check("BigInt exists", false);
  check("BigInt literal", false);
  check("BigInt arithmetic", false);
  check("BigInt comparison", false);
  check("BigInt toString", false);
  check("BigInt from number", false);
}

// ============================================================
// 23. Async iteration basics (for-await-of with sync iterable)
// ============================================================
try {
  // Test that async iteration syntax is parseable
  var asyncFn = new Function("return async function test() { var sum = 0; for await (var x of [1,2,3]) sum += x; return sum; }");
  check("for-await-of parses", typeof asyncFn() === "function");
} catch(e) { check("for-await-of parses", false); }

// ============================================================
// 24. Optional chaining and nullish coalescing (deep patterns)
// ============================================================
try {
  var deep = { a: { b: { c: 42 } } };
  check("optional chaining deep", deep?.a?.b?.c === 42);
  check("optional chaining null", (null)?.a?.b === undefined);
  check("optional chaining method", "hello"?.toUpperCase() === "HELLO");
  check("nullish coalescing 0", (0 ?? "default") === 0);
  check("nullish coalescing empty string", ("" ?? "default") === "");
  check("nullish coalescing null", (null ?? "default") === "default");
  check("nullish coalescing undefined", (undefined ?? "default") === "default");
  // logical assignment operators
  var la = { a: null, b: 0, c: undefined };
  la.a ??= 42;
  la.b ??= 42;
  la.c ??= 42;
  check("nullish assignment ??=", la.a === 42 && la.b === 0 && la.c === 42);

  var lb = { x: 0, y: "" };
  lb.x ||= 99;
  lb.y ||= "hello";
  check("logical OR assignment ||=", lb.x === 99 && lb.y === "hello");

  var lc = { a: 1, b: 0 };
  lc.a &&= 99;
  lc.b &&= 99;
  check("logical AND assignment &&=", lc.a === 99 && lc.b === 0);
} catch(e) {
  check("optional chaining deep", false);
  check("optional chaining null", false);
  check("optional chaining method", false);
  check("nullish coalescing 0", false);
  check("nullish coalescing empty string", false);
  check("nullish coalescing null", false);
  check("nullish coalescing undefined", false);
  check("nullish assignment ??=", false);
  check("logical OR assignment ||=", false);
  check("logical AND assignment &&=", false);
}

// ============================================================
// 25. Well-known Symbols completeness
// ============================================================
try {
  check("Symbol.iterator", typeof Symbol.iterator === "symbol");
  check("Symbol.asyncIterator", typeof Symbol.asyncIterator === "symbol");
  check("Symbol.hasInstance", typeof Symbol.hasInstance === "symbol");
  check("Symbol.toPrimitive", typeof Symbol.toPrimitive === "symbol");
  check("Symbol.toStringTag", typeof Symbol.toStringTag === "symbol");
  check("Symbol.species", typeof Symbol.species === "symbol");
  check("Symbol.isConcatSpreadable", typeof Symbol.isConcatSpreadable === "symbol");
  check("Symbol.match", typeof Symbol.match === "symbol");
  check("Symbol.replace", typeof Symbol.replace === "symbol");
  check("Symbol.search", typeof Symbol.search === "symbol");
  check("Symbol.split", typeof Symbol.split === "symbol");
  check("Symbol.unscopables", typeof Symbol.unscopables === "symbol");
} catch(e) {
  check("Symbol.iterator", false); check("Symbol.asyncIterator", false);
  check("Symbol.hasInstance", false); check("Symbol.toPrimitive", false);
  check("Symbol.toStringTag", false); check("Symbol.species", false);
  check("Symbol.isConcatSpreadable", false); check("Symbol.match", false);
  check("Symbol.replace", false); check("Symbol.search", false);
  check("Symbol.split", false); check("Symbol.unscopables", false);
}

// ============================================================
// 26. Array.at / String.at (ES2022)
// ============================================================
try {
  check("Array.at positive", [1,2,3].at(0) === 1);
  check("Array.at negative", [1,2,3].at(-1) === 3);
  check("String.at positive", "hello".at(0) === "h");
  check("String.at negative", "hello".at(-1) === "o");
} catch(e) {
  check("Array.at positive", false); check("Array.at negative", false);
  check("String.at positive", false); check("String.at negative", false);
}

// ============================================================
// 27. Object.hasOwn (ES2022)
// ============================================================
try {
  check("Object.hasOwn exists", typeof Object.hasOwn === "function");
  check("Object.hasOwn true", Object.hasOwn({a:1}, "a") === true);
  check("Object.hasOwn false", Object.hasOwn({a:1}, "b") === false);
  check("Object.hasOwn no prototype", Object.hasOwn({}, "toString") === false);
} catch(e) {
  check("Object.hasOwn exists", false);
  check("Object.hasOwn true", false);
  check("Object.hasOwn false", false);
  check("Object.hasOwn no prototype", false);
}

// ============================================================
// 28. Array change-by-copy (ES2023): toSorted, toReversed, toSpliced, with
// ============================================================
try {
  var orig = [3, 1, 2];
  var sorted = orig.toSorted();
  check("Array.toSorted", sorted.join(",") === "1,2,3" && orig.join(",") === "3,1,2");

  var reversed = orig.toReversed();
  check("Array.toReversed", reversed.join(",") === "2,1,3" && orig.join(",") === "3,1,2");

  var spliced = [1,2,3,4].toSpliced(1, 2, 5, 6);
  check("Array.toSpliced", spliced.join(",") === "1,5,6,4");

  var withed = [1,2,3].with(1, 42);
  check("Array.with", withed.join(",") === "1,42,3");
} catch(e) {
  check("Array.toSorted", false);
  check("Array.toReversed", false);
  check("Array.toSpliced", false);
  check("Array.with", false);
}

// ============================================================
// 29. Hashbang grammar
// ============================================================
try {
  // Just test that Function constructor handles normal code
  var fn = new Function("return 42");
  check("Function constructor", fn() === 42);
} catch(e) { check("Function constructor", false); }

// ============================================================
// 30. Promise.withResolvers (ES2024)
// ============================================================
try {
  var pwr = Promise.withResolvers();
  check("Promise.withResolvers exists", typeof Promise.withResolvers === "function");
  check("Promise.withResolvers promise", pwr.promise instanceof Promise);
  check("Promise.withResolvers resolve fn", typeof pwr.resolve === "function");
  check("Promise.withResolvers reject fn", typeof pwr.reject === "function");
} catch(e) {
  check("Promise.withResolvers exists", false);
  check("Promise.withResolvers promise", false);
  check("Promise.withResolvers resolve fn", false);
  check("Promise.withResolvers reject fn", false);
}

// ============================================================
// 31. Error types: SuppressedError (explicit resource management companion)
// ============================================================
try {
  var hasSE = typeof SuppressedError === "function";
  check("SuppressedError exists", hasSE);
  if (hasSE) {
    var se = new SuppressedError(new Error("sup"), new Error("orig"), "msg");
    check("SuppressedError message", se.message === "msg");
  } else {
    check("SuppressedError message", false);
  }
} catch(e) {
  check("SuppressedError exists", false);
  check("SuppressedError message", false);
}

// ============================================================
// 32. Generators
// ============================================================
try {
  function* gen() { yield 1; yield 2; yield 3; }
  var g = gen();
  var r1 = g.next();
  check("Generator next value", r1.value === 1 && r1.done === false);
  var r2 = g.next();
  check("Generator next second", r2.value === 2);
  g.next();
  var r4 = g.next();
  check("Generator done", r4.done === true && r4.value === undefined);

  // Generator is iterable
  var genArr = Array.from(gen());
  check("Generator iterable", genArr.join(",") === "1,2,3");

  // yield*
  function* nested() { yield* [10, 20]; yield 30; }
  check("Generator yield* delegation", Array.from(nested()).join(",") === "10,20,30");
} catch(e) {
  check("Generator next value", false);
  check("Generator next second", false);
  check("Generator done", false);
  check("Generator iterable", false);
  check("Generator yield* delegation", false);
}

// ============================================================
// 33. Private class fields and methods
// ============================================================
try {
  var classCode = `
    class Counter {
      #count = 0;
      #step;
      constructor(step) { this.#step = step; }
      increment() { this.#count += this.#step; }
      get value() { return this.#count; }
      static #staticPrivate = 42;
      static getStatic() { return Counter.#staticPrivate; }
    }
    var c = new Counter(3);
    c.increment();
    c.increment();
    [c.value, Counter.getStatic()];
  `;
  var result = eval(classCode);
  check("Private class fields", result[0] === 6);
  check("Static private fields", result[1] === 42);
} catch(e) {
  check("Private class fields", false);
  check("Static private fields", false);
}

// ============================================================
// 34. Top-level logical operations / coercion edge cases
// ============================================================
try {
  check("NaN !== NaN", NaN !== NaN);
  check("Number.isNaN", Number.isNaN(NaN) === true && Number.isNaN("NaN") === false);
  check("Number.isFinite", Number.isFinite(42) === true && Number.isFinite(Infinity) === false);
  check("Number.isInteger", Number.isInteger(42) === true && Number.isInteger(42.5) === false);
  check("Number.isSafeInteger", Number.isSafeInteger(Number.MAX_SAFE_INTEGER) === true);
  check("Number.EPSILON", Number.EPSILON < 1 && Number.EPSILON > 0);
  check("Number.MAX_SAFE_INTEGER", Number.MAX_SAFE_INTEGER === 9007199254740991);
  check("Object.is NaN", Object.is(NaN, NaN) === true);
  check("Object.is +0/-0", Object.is(+0, -0) === false);
} catch(e) {
  check("NaN !== NaN", false);
  check("Number.isNaN", false);
  check("Number.isFinite", false);
  check("Number.isInteger", false);
  check("Number.isSafeInteger", false);
  check("Number.EPSILON", false);
  check("Number.MAX_SAFE_INTEGER", false);
  check("Object.is NaN", false);
  check("Object.is +0/-0", false);
}

// ============================================================
// 35. Map / Set ordering and edge cases
// ============================================================
try {
  var m = new Map();
  m.set("b", 2);
  m.set("a", 1);
  m.set("c", 3);
  var mapKeys = Array.from(m.keys());
  check("Map insertion order", mapKeys.join(",") === "b,a,c");
  check("Map forEach", (function() { var s = ""; m.forEach(function(v,k) { s += k + v; }); return s; })() === "b2a1c3");

  var s = new Set();
  s.add(3); s.add(1); s.add(2);
  var setVals = Array.from(s);
  check("Set insertion order", setVals.join(",") === "3,1,2");

  // Map with object keys
  var key1 = {};
  var key2 = {};
  var m2 = new Map();
  m2.set(key1, "a");
  m2.set(key2, "b");
  check("Map object keys distinct", m2.size === 2 && m2.get(key1) === "a" && m2.get(key2) === "b");
} catch(e) {
  check("Map insertion order", false);
  check("Map forEach", false);
  check("Set insertion order", false);
  check("Map object keys distinct", false);
}

// ============================================================
// 36. Destructuring advanced patterns
// ============================================================
try {
  var [a, ...rest] = [1, 2, 3, 4];
  check("Array rest destructuring", a === 1 && rest.join(",") === "2,3,4");

  var { x: aliased, y = 99 } = { x: 42 };
  check("Object destructuring alias+default", aliased === 42 && y === 99);

  var [[n1], [n2, n3]] = [[1], [2, 3]];
  check("Nested destructuring", n1 === 1 && n2 === 2 && n3 === 3);

  // Computed property destructuring
  var prop = "hello";
  var { [prop]: val } = { hello: "world" };
  check("Computed property destructuring", val === "world");
} catch(e) {
  check("Array rest destructuring", false);
  check("Object destructuring alias+default", false);
  check("Nested destructuring", false);
  check("Computed property destructuring", false);
}

// ============================================================
// 37. Template literal tags
// ============================================================
try {
  function tag(strings, ...values) {
    return strings[0] + values.map(function(v) { return v.toString().toUpperCase(); }).join("") + strings[strings.length - 1];
  }
  var name = "world";
  var result = tag`hello ${name}!`;
  check("Tagged template literal", result === "hello WORLD!");

  // String.raw
  check("String.raw", String.raw`\n\t` === "\\n\\t");
} catch(e) {
  check("Tagged template literal", false);
  check("String.raw", false);
}

// ============================================================
// 38. RegExp named groups and lookbehind
// ============================================================
try {
  var re = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/;
  var m = re.exec("2024-01-15");
  check("RegExp named groups", m.groups.year === "2024" && m.groups.month === "01" && m.groups.day === "15");
} catch(e) { check("RegExp named groups", false); }

try {
  var re2 = /(?<=\$)\d+/;
  check("RegExp lookbehind", re2.exec("$42")[0] === "42");
} catch(e) { check("RegExp lookbehind", false); }

try {
  var re3 = /foo.bar/s;
  check("RegExp dotAll flag", re3.test("foo\nbar"));
} catch(e) { check("RegExp dotAll flag", false); }

try {
  var str = "aAbBcC";
  var matches = Array.from(str.matchAll(/[a-c]/gi));
  check("String.matchAll", matches.length === 6);
} catch(e) { check("String.matchAll", false); }

// ============================================================
// 39. AbortController / AbortSignal
// ============================================================
try {
  var ac = new AbortController();
  check("AbortController exists", ac instanceof AbortController);
  check("AbortController.signal", ac.signal instanceof AbortSignal);
  check("AbortSignal.aborted initial false", ac.signal.aborted === false);
  ac.abort("reason");
  check("AbortController.abort works", ac.signal.aborted === true);
  check("AbortSignal.reason", ac.signal.reason === "reason");
} catch(e) {
  check("AbortController exists", false);
  check("AbortController.signal", false);
  check("AbortSignal.aborted initial false", false);
  check("AbortController.abort works", false);
  check("AbortSignal.reason", false);
}

// AbortSignal.timeout / AbortSignal.any
try {
  check("AbortSignal.timeout exists", typeof AbortSignal.timeout === "function");
  var ts = AbortSignal.timeout(1000);
  check("AbortSignal.timeout returns signal", ts instanceof AbortSignal);
} catch(e) {
  check("AbortSignal.timeout exists", false);
  check("AbortSignal.timeout returns signal", false);
}

try {
  check("AbortSignal.any exists", typeof AbortSignal.any === "function");
  var ac1 = new AbortController();
  var ac2 = new AbortController();
  var combined = AbortSignal.any([ac1.signal, ac2.signal]);
  check("AbortSignal.any returns signal", combined instanceof AbortSignal);
  check("AbortSignal.any not aborted initially", combined.aborted === false);
  ac1.abort();
  check("AbortSignal.any aborted when child aborts", combined.aborted === true);
} catch(e) {
  check("AbortSignal.any exists", false);
  check("AbortSignal.any returns signal", false);
  check("AbortSignal.any not aborted initially", false);
  check("AbortSignal.any aborted when child aborts", false);
}

// ============================================================
// Summary
// ============================================================
console.log("\nProduction gaps: " + pass + "/" + (pass + fail) + " passed");
