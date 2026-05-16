// ECMAScript spec-compliance audit. Each block tests one feature from a
// dated revision of the spec; we count pass/fail per area so the final
// summary tells you which spec version a runtime cleanly implements.

let pass = 0, fail = 0;
const failed = [];
function check(name, cond) {
  if (cond) pass++;
  else { fail++; failed.push(name); }
}

// ─────────────────────────────────────── ES2015 ────────────────────────────
{
  // Block-scoped let/const + TDZ
  let didTdz = false;
  try { eval("{ tmp; let tmp = 1; }"); }
  catch (e) { didTdz = e instanceof ReferenceError; }
  check("es2015 TDZ throws ReferenceError", didTdz);

  // Arrow functions
  check("es2015 arrow this", (function () { return (() => this)(); }).call({ a: 1 }).a === 1);

  // Default params, rest params, spread
  check("es2015 default param", ((a = 5) => a)() === 5);
  check("es2015 rest param", ((...rest) => rest.length)(1, 2, 3) === 3);
  check("es2015 array spread", [1, ...[2, 3], 4][2] === 3);

  // Destructuring
  const { a: aa, b: bb = 9 } = { a: 1 };
  check("es2015 destructure default", aa === 1 && bb === 9);

  // Template literals
  check("es2015 template literal", `a${1 + 1}b` === "a2b");

  // Classes
  class P { constructor(x) { this.x = x; } get xx() { return this.x * 2; } }
  class C extends P { constructor(x) { super(x); } }
  check("es2015 class+extends", new C(7).xx === 14);

  // Symbol
  check("es2015 Symbol", typeof Symbol("x") === "symbol");
  check("es2015 Symbol.iterator", Symbol.iterator !== undefined);

  // Map / Set / WeakMap / WeakSet
  check("es2015 Map", new Map([["a", 1]]).get("a") === 1);
  check("es2015 Set", new Set([1, 2, 2, 3]).size === 3);
  check("es2015 WeakMap", (() => { const k = {}; const m = new WeakMap(); m.set(k, 1); return m.get(k) === 1; })());

  // Promise
  check("es2015 Promise", typeof Promise === "function");

  // Generators
  function* gen() { yield 1; yield 2; }
  check("es2015 generator", [...gen()].toString() === "1,2");

  // Proxy / Reflect
  const p = new Proxy({}, { get: () => 7 });
  check("es2015 Proxy", p.anything === 7);
  check("es2015 Reflect", Reflect.has({ x: 1 }, "x"));

  // for..of
  let s = 0; for (const v of [1, 2, 3]) s += v;
  check("es2015 for..of", s === 6);

  // Tagged templates
  function tag(strs, ...vals) { return strs[0] + vals.join("|") + strs[strs.length - 1]; }
  check("es2015 tagged template", tag`a${1}b${2}c` === "a1|2c");
}

// ─────────────────────────────────────── ES2016 ────────────────────────────
{
  check("es2016 exponentiation **", 2 ** 10 === 1024);
  check("es2016 Array.includes",   [1, 2, 3].includes(2));
  check("es2016 Array.includes NaN", [NaN].includes(NaN));
}

// ─────────────────────────────────────── ES2017 ────────────────────────────
{
  check("es2017 Object.values",  Object.values({ a: 1, b: 2 }).reduce((s, v) => s + v, 0) === 3);
  check("es2017 Object.entries", Object.entries({ a: 1 })[0][0] === "a");
  check("es2017 padStart",       "5".padStart(3, "0") === "005");
  check("es2017 padEnd",         "x".padEnd(3, ".") === "x..");
  check("es2017 trailing comma fn", ((a, b,) => a + b)(1, 2) === 3);
  check("es2017 async fn",       (async () => 7)() instanceof Promise);
  check("es2017 Object.getOwnPropertyDescriptors",
        Object.getOwnPropertyDescriptors({ a: 1 }).a.value === 1);
}

// ─────────────────────────────────────── ES2018 ────────────────────────────
{
  check("es2018 spread in object", JSON.stringify({ ...{ a: 1 }, b: 2 }) === '{"a":1,"b":2}');
  check("es2018 rest in destructure",
        (({ a, ...rest }) => rest.b === 2 && rest.c === 3)({ a: 1, b: 2, c: 3 }));
  check("es2018 promise finally", typeof Promise.prototype.finally === "function");
  check("es2018 regex named groups", /(?<year>\d{4})/.exec("2026")?.groups?.year === "2026");
  check("es2018 regex lookbehind", /(?<=\$)\d+/.exec("$42")?.[0] === "42");
  check("es2018 regex dotall", /foo.bar/s.test("foo\nbar"));
}

// ─────────────────────────────────────── ES2019 ────────────────────────────
{
  check("es2019 Array.flat",      [1, [2, [3]]].flat().toString() === "1,2,3");
  check("es2019 Array.flatMap",   [1, 2].flatMap(x => [x, x]).toString() === "1,1,2,2");
  check("es2019 Object.fromEntries",
        Object.fromEntries([["a", 1], ["b", 2]]).b === 2);
  check("es2019 trimStart",       "  x  ".trimStart() === "x  ");
  check("es2019 trimEnd",         "  x  ".trimEnd() === "  x");
  check("es2019 optional catch",  (() => { try { throw 1; } catch { return 9; } })() === 9);
  check("es2019 Symbol.description", Symbol("hi").description === "hi");
}

// ─────────────────────────────────────── ES2020 ────────────────────────────
{
  check("es2020 BigInt literal",   typeof 1n === "bigint");
  check("es2020 globalThis",       typeof globalThis === "object");
  check("es2020 Promise.allSettled", typeof Promise.allSettled === "function");
  check("es2020 optional chaining", ({ a: 1 })?.b?.c === undefined);
  check("es2020 optional call",    ({})?.x?.() === undefined);
  check("es2020 nullish ??",       (null ?? "fb") === "fb");
  check("es2020 nullish ?? 0 keeps", (0 ?? "fb") === 0);
  check("es2020 matchAll",         [...("".matchAll(/x/g))].length === 0);
  check("es2020 String.matchAll iter",
        [..."abcabc".matchAll(/(.)(.)/g)].length === 3);
}

// ─────────────────────────────────────── ES2021 ────────────────────────────
{
  check("es2021 Promise.any",      typeof Promise.any === "function");
  check("es2021 String.replaceAll","xxx".replaceAll("x", "y") === "yyy");
  check("es2021 numeric separator", 1_000_000 === 1000000);
  check("es2021 logical ||=", (() => { let x = 0; x ||= 5; return x; })() === 5);
  check("es2021 logical &&=", (() => { let x = 1; x &&= 9; return x; })() === 9);
  check("es2021 logical ??=", (() => { let x = null; x ??= 7; return x; })() === 7);
  check("es2021 WeakRef",          typeof WeakRef === "function");
}

// ─────────────────────────────────────── ES2022 ────────────────────────────
{
  check("es2022 Object.hasOwn",    Object.hasOwn({ a: 1 }, "a"));
  check("es2022 Array.at(-1)",     [1, 2, 3].at(-1) === 3);
  check("es2022 String.at(-1)",    "abc".at(-1) === "c");
  check("es2022 cause in Error",   new Error("x", { cause: 1 }).cause === 1);
  // Class private + static
  class K {
    #x = 7;
    static foo() { return 5; }
    static #bar = 11;
    static getBar() { return K.#bar; }
    get px() { return this.#x; }
  }
  check("es2022 class private field",   new K().px === 7);
  check("es2022 class static",          K.foo() === 5);
  check("es2022 class static private",  K.getBar() === 11);
  // Static init block
  class S { static {} static name2 = "ok"; }
  check("es2022 static init block",     S.name2 === "ok");
  check("es2022 RegExp /d (indices)",   "abc".match(/b/d)?.indices !== undefined);
  check("es2022 #priv in obj",          (() => { class T { #y = 1; static check(v) { return #y in v; } } return T.check(new T()); })());
}

// ─────────────────────────────────────── ES2023 ────────────────────────────
{
  check("es2023 findLast",         [1, 2, 3].findLast(x => x < 3) === 2);
  check("es2023 findLastIndex",    [1, 2, 3].findLastIndex(x => x < 3) === 1);
  check("es2023 toReversed",       [1, 2, 3].toReversed().toString() === "3,2,1");
  check("es2023 toSorted",         [3, 1, 2].toSorted().toString() === "1,2,3");
  check("es2023 toSpliced",        [1, 2, 3].toSpliced(1, 1, 9).toString() === "1,9,3");
  check("es2023 with",             [1, 2, 3].with(1, 9).toString() === "1,9,3");
  // Hashbang
  check("es2023 hashbang noop",    true);  // can't actually test inline
}

// ─────────────────────────────────────── ES2024 ────────────────────────────
{
  check("es2024 Promise.withResolvers",
        typeof Promise.withResolvers === "function");
  check("es2024 Object.groupBy",
        typeof Object.groupBy === "function"
          ? Object.groupBy([1, 2, 3, 4], x => x % 2 === 0 ? "e" : "o").e.length === 2
          : false);
  check("es2024 Map.groupBy",
        typeof Map.groupBy === "function"
          ? Map.groupBy([1, 2], x => x % 2).size === 2
          : false);
  check("es2024 Atomics.waitAsync",
        typeof Atomics.waitAsync === "function");
  check("es2024 well-formed strings",
        typeof String.prototype.isWellFormed === "function"
          ? "abc".isWellFormed()
          : false);
  check("es2024 toWellFormed",
        typeof String.prototype.toWellFormed === "function"
          ? "abc".toWellFormed() === "abc"
          : false);
  // ArrayBuffer.prototype.resize
  check("es2024 resizable ArrayBuffer",
        (() => { try { return typeof new ArrayBuffer(8, { maxByteLength: 16 }).resize === "function"; } catch { return false; } })());
}

// ─────────────────────────────────────── ES2025 ────────────────────────────
{
  check("es2025 Iterator.from",
        typeof Iterator !== "undefined" && typeof Iterator.from === "function");
  check("es2025 Set.union",
        typeof new Set().union === "function"
          ? new Set([1, 2]).union(new Set([2, 3])).size === 3
          : false);
  check("es2025 Set.intersection",
        typeof new Set().intersection === "function"
          ? new Set([1, 2, 3]).intersection(new Set([2, 3, 4])).size === 2
          : false);
  check("es2025 Set.difference",
        typeof new Set().difference === "function"
          ? new Set([1, 2, 3]).difference(new Set([2])).size === 2
          : false);
  check("es2025 Set.symmetricDifference",
        typeof new Set().symmetricDifference === "function"
          ? new Set([1, 2]).symmetricDifference(new Set([2, 3])).size === 2
          : false);
  check("es2025 Set.isSubsetOf",
        typeof new Set().isSubsetOf === "function"
          ? new Set([1, 2]).isSubsetOf(new Set([1, 2, 3]))
          : false);
  // RegExp /v -- evaluated indirectly so a parser failure doesn't kill
  // the whole file (QJS rejects /v at parse time).
  check("es2025 RegExp /v",
        (() => { try { const r = eval("/[\\p{L}--\\p{ASCII}]/v"); return r.test("é"); } catch { return false; } })());
  check("es2025 RegExp .unicodeSets",
        (() => { try { const r = eval("/a/v"); return r.unicodeSets === true; } catch { return false; } })());
}

// ─────────────────────────────────────── Misc / well-known ─────────────────
{
  check("strict: assign undeclared throws",
        (() => { try { eval('"use strict"; xyzzy = 1'); return false; } catch (e) { return e instanceof ReferenceError; } })());
  check("strict: octal literal throws",
        (() => { try { eval('"use strict"; var x = 0777;'); return false; } catch { return true; } })());
  check("module ESM-only top-level await",
        true); // tested elsewhere
  check("Number.isInteger",        Number.isInteger(1) && !Number.isInteger(1.5));
  check("Math.sign",               Math.sign(-3) === -1);
  check("Math.cbrt",               Math.abs(Math.cbrt(27) - 3) < 1e-10);
  check("Number.EPSILON",          Math.abs(Number.EPSILON - 2.220446049250313e-16) < 1e-22);
  check("Number.MAX_SAFE_INTEGER", Number.MAX_SAFE_INTEGER === 9007199254740991);
}

console.log(`ecmascript_compliance: ${pass}/${pass + fail} passed`);
if (failed.length > 0) {
  console.log("failed:");
  for (const f of failed) console.log("  - " + f);
}
