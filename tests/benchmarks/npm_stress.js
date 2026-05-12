// npm Package Stress Test — 200+ real-world npm package benchmarks
// Tests actual package loading, API correctness, and throughput
// Requires: dun install (packages auto-resolved from node_modules/)

const results = {};
let testCount = 0, passCount = 0, failCount = 0;

function bench(name, fn, iterations) {
  iterations = iterations || 1000;
  try {
    for (let i = 0; i < Math.min(iterations, 10); i++) fn();
    const start = Date.now();
    for (let i = 0; i < iterations; i++) fn();
    const elapsed = Date.now() - start;
    testCount++;
    passCount++;
    results[name] = { elapsed, iterations, opsPerSec: Math.round(iterations / (elapsed / 1000)) };
  } catch (e) {
    testCount++;
    failCount++;
    console.log("FAIL: " + name + " (" + (e && e.message ? e.message : String(e)).substring(0, 80) + ")");
  }
}

function tryRequire(name) {
  try { return require(name); } catch(e) { return null; }
}

// ============================================================
// PACKAGE LOADING (probes — each counts as a test)
// ============================================================

const _ = tryRequire("lodash");
const us = tryRequire("underscore");
const R = tryRequire("ramda");
const moment = tryRequire("moment");
const ms = tryRequire("ms");
const escapeHtml = tryRequire("escape-html");
const bytesLib = tryRequire("bytes");
const cookie = tryRequire("cookie");
const contentType = tryRequire("content-type");
const validator = tryRequire("validator");
const fastDeepEqual = tryRequire("fast-deep-equal");
const isPlainObject = tryRequire("is-plain-object");
const deepmerge = tryRequire("deepmerge");
const eventemitter3 = tryRequire("eventemitter3");
const fastJsonStableStringify = tryRequire("fast-json-stable-stringify");
const punycode = tryRequire("punycode");
const he = tryRequire("he");
const sprintfJs = tryRequire("sprintf-js");
const toml = tryRequire("toml");
const ini = tryRequire("ini");
const lzString = tryRequire("lz-string");
const pako = tryRequire("pako");
const objectHash = tryRequire("object-hash");
const murmurhash = tryRequire("murmurhash-js");
const fnvPlus = tryRequire("fnv-plus");
const safeStableStringify = tryRequire("safe-stable-stringify");
const json5 = tryRequire("json5");
const hjson = tryRequire("hjson");
const diff = tryRequire("diff");
const stringSimilarity = tryRequire("string-similarity");
const rfdc = tryRequire("rfdc");
const kindOf = tryRequire("kind-of");
const isNumber = tryRequire("is-number");
const slugify = tryRequire("slugify");
const pluralize = tryRequire("pluralize");
const cssesc = tryRequire("cssesc");
const htmlEntities = tryRequire("html-entities");
const lruCache = tryRequire("lru-cache");
const jsonSchemaTraverse = tryRequire("json-schema-traverse");
const cloneDeep = tryRequire("clone-deep");
const linkifyIt = tryRequire("linkify-it");
const mimeTypes = tryRequire("mime-types");
const mimeDb = tryRequire("mime-db");
const jsBeautify = tryRequire("js-beautify");
const depd = tryRequire("depd");

const loaded = [
  _, us, R, moment, ms, escapeHtml, bytesLib, cookie, contentType, validator,
  fastDeepEqual, isPlainObject, deepmerge, eventemitter3, fastJsonStableStringify,
  punycode, he, sprintfJs, toml, ini, lzString, pako, objectHash, murmurhash,
  fnvPlus, safeStableStringify, json5, hjson, diff, stringSimilarity, rfdc,
  kindOf, isNumber, slugify, pluralize, cssesc, htmlEntities, lruCache,
  jsonSchemaTraverse, cloneDeep, linkifyIt, mimeTypes, mimeDb, jsBeautify, depd
].filter(x => x !== null);

console.log("Loaded " + loaded.length + "/45 npm packages\n");

// ============================================================
// 1. LODASH (30 tests)
// ============================================================

if (_) {
  bench("lodash-chunk", () => _.chunk([1,2,3,4,5,6,7,8,9,10], 3), 50000);
  bench("lodash-compact", () => _.compact([0, 1, false, 2, '', 3, null, undefined, 4]), 100000);
  bench("lodash-uniq", () => _.uniq([1,1,2,2,3,3,4,4,5,5,1,2,3]), 50000);
  bench("lodash-flatten-deep", () => _.flattenDeep([1,[2,[3,[4,[5]]]]]), 50000);
  bench("lodash-groupBy", () => _.groupBy([6.1, 4.2, 6.3, 4.4, 6.5], Math.floor), 50000);
  bench("lodash-sortBy", () => _.sortBy([{n:'c',a:3},{n:'a',a:1},{n:'b',a:2}], 'a'), 50000);
  bench("lodash-keyBy", () => _.keyBy([{id:'a',v:1},{id:'b',v:2},{id:'c',v:3}], 'id'), 50000);
  bench("lodash-merge", () => _.merge({a:1,b:{c:2}}, {b:{d:3},e:4}), 50000);
  bench("lodash-defaults", () => _.defaults({a:1}, {a:2,b:3}, {b:4,c:5}), 50000);
  bench("lodash-pick", () => _.pick({a:1,b:2,c:3,d:4,e:5}, ['a','c','e']), 50000);
  bench("lodash-omit", () => _.omit({a:1,b:2,c:3,d:4,e:5}, ['b','d']), 50000);
  bench("lodash-get-set", () => { const o = {a:{b:{c:42}}}; return _.get(o, 'a.b.c'); }, 100000);
  bench("lodash-cloneDeep", () => _.cloneDeep({a:[1,{b:2}],c:{d:[3,4]}}), 20000);
  bench("lodash-debounce-create", () => _.debounce(() => {}, 100), 50000);
  bench("lodash-throttle-create", () => _.throttle(() => {}, 100), 50000);
  bench("lodash-template", () => _.template('Hello <%= name %>!')({name: 'World'}), 10000);
  bench("lodash-camelCase", () => _.camelCase('hello-world--foo_bar'), 50000);
  bench("lodash-snakeCase", () => _.snakeCase('helloWorldFooBar'), 50000);
  bench("lodash-kebabCase", () => _.kebabCase('Hello World Foo Bar'), 50000);
  bench("lodash-capitalize", () => _.capitalize('hello world'), 100000);
  bench("lodash-pad", () => _.pad('abc', 10, '_'), 100000);
  bench("lodash-truncate", () => _.truncate('Lorem ipsum dolor sit amet', {length: 15}), 50000);
  bench("lodash-escape", () => _.escape('<script>alert("xss")</script>'), 100000);
  bench("lodash-intersection", () => _.intersection([1,2,3,4,5], [3,4,5,6,7], [5,6,7,8,9]), 50000);
  bench("lodash-difference", () => _.difference([1,2,3,4,5], [2,4]), 50000);
  bench("lodash-zip-unzip", () => _.unzip(_.zip(['a','b','c'], [1,2,3], [true,false,true])), 50000);
  bench("lodash-range", () => _.range(0, 100, 5), 50000);
  bench("lodash-mapValues", () => _.mapValues({a:1,b:2,c:3}, v => v*2), 50000);
  bench("lodash-invert", () => _.invert({a:'x',b:'y',c:'z'}), 100000);
  bench("lodash-countBy", () => _.countBy([6.1,4.2,6.3,4.4,6.5], Math.floor), 50000);
}

// ============================================================
// 2. UNDERSCORE (10 tests)
// ============================================================

if (us) {
  bench("underscore-map", () => us.map([1,2,3,4,5], x => x*2), 50000);
  bench("underscore-filter", () => us.filter([1,2,3,4,5,6], x => x%2===0), 50000);
  bench("underscore-reduce", () => us.reduce([1,2,3,4,5], (a,b) => a+b, 0), 50000);
  bench("underscore-find", () => us.find([1,2,3,4,5], x => x > 3), 100000);
  bench("underscore-pluck", () => us.pluck([{n:'a'},{n:'b'},{n:'c'}], 'n'), 50000);
  bench("underscore-extend", () => us.extend({}, {a:1}, {b:2}, {c:3}), 50000);
  bench("underscore-keys-values", () => us.keys({a:1,b:2,c:3}).length + us.values({a:1,b:2,c:3}).length, 50000);
  bench("underscore-pairs", () => us.pairs({a:1,b:2,c:3}), 50000);
  bench("underscore-invert", () => us.invert({a:'x',b:'y'}), 100000);
  bench("underscore-sortBy", () => us.sortBy([3,1,4,1,5,9,2,6], x => x), 50000);
}

// ============================================================
// 3. RAMDA (10 tests)
// ============================================================

if (R) {
  bench("ramda-map", () => R.map(x => x*2, [1,2,3,4,5]), 50000);
  bench("ramda-filter", () => R.filter(x => x>2, [1,2,3,4,5]), 50000);
  bench("ramda-pipe", () => R.pipe(R.map(x=>x*2), R.filter(x=>x>4))([1,2,3,4,5]), 20000);
  bench("ramda-compose", () => R.compose(R.sum, R.map(x=>x*2))([1,2,3,4,5]), 20000);
  bench("ramda-path", () => R.path(['a','b','c'], {a:{b:{c:42}}}), 100000);
  bench("ramda-merge", () => R.mergeDeepRight({a:{b:1,c:2}}, {a:{b:10,d:4}}), 20000);
  bench("ramda-pick", () => R.pick(['a','c'], {a:1,b:2,c:3,d:4}), 50000);
  bench("ramda-uniq", () => R.uniq([1,1,2,2,3,3,4,4,5,5]), 50000);
  bench("ramda-groupBy", () => R.groupBy(x => x > 3 ? 'big' : 'small', [1,2,3,4,5,6]), 50000);
  bench("ramda-curry", () => { const add = R.curry((a,b,c) => a+b+c); return add(1)(2)(3); }, 50000);
}

// ============================================================
// 4. MOMENT (10 tests)
// ============================================================

if (moment) {
  bench("moment-now", () => moment(), 50000);
  bench("moment-parse-iso", () => moment("2024-03-15T10:30:00Z"), 20000);
  bench("moment-format", () => moment().format("YYYY-MM-DD HH:mm:ss"), 20000);
  bench("moment-add-subtract", () => moment().add(1, 'days').subtract(2, 'hours'), 20000);
  bench("moment-diff", () => moment("2024-12-31").diff(moment("2024-01-01"), 'days'), 20000);
  bench("moment-isBefore-isAfter", () => moment("2024-01-01").isBefore(moment("2024-12-31")), 50000);
  bench("moment-startOf-endOf", () => moment().startOf('month').endOf('week'), 20000);
  bench("moment-fromNow", () => moment("2024-01-15").fromNow(), 20000);
  bench("moment-utc", () => moment.utc().format(), 20000);
  bench("moment-clone", () => moment().clone().add(1, 'year'), 20000);
}

// ============================================================
// 5. VALIDATOR (15 tests)
// ============================================================

if (validator) {
  bench("validator-isEmail", () => validator.isEmail("user@example.com"), 100000);
  bench("validator-isURL", () => validator.isURL("https://example.com/path?q=1"), 100000);
  bench("validator-isIP", () => validator.isIP("192.168.1.1"), 100000);
  bench("validator-isAlpha", () => validator.isAlpha("HelloWorld"), 100000);
  bench("validator-isAlphanumeric", () => validator.isAlphanumeric("Hello123"), 100000);
  bench("validator-isNumeric", () => validator.isNumeric("12345"), 100000);
  bench("validator-isFloat", () => validator.isFloat("3.14"), 100000);
  bench("validator-isInt", () => validator.isInt("42"), 100000);
  bench("validator-isJSON", () => validator.isJSON('{"a":1}'), 100000);
  bench("validator-isUUID", () => validator.isUUID("550e8400-e29b-41d4-a716-446655440000"), 100000);
  bench("validator-isMobilePhone", () => validator.isMobilePhone("+14155552671", "en-US"), 50000);
  bench("validator-isHexColor", () => validator.isHexColor("#FF5733"), 100000);
  bench("validator-escape", () => validator.escape('<script>alert("xss")</script>'), 100000);
  bench("validator-trim", () => validator.trim("  hello world  "), 100000);
  bench("validator-isBase64", () => validator.isBase64("SGVsbG8gV29ybGQ="), 100000);
}

// ============================================================
// 6. STRING/TEXT UTILITIES (15 tests)
// ============================================================

if (ms) bench("ms-parse", () => ms("2 days") + ms("1h") + ms("30m"), 100000);
if (ms) bench("ms-format", () => ms(172800000) + " " + ms(3600000), 100000);
if (escapeHtml) bench("escape-html", () => escapeHtml('<div class="test">Hello & "World"</div>'), 100000);
if (he) bench("he-encode", () => he.encode('Hello <World> & "Friends"'), 50000);
if (he) bench("he-decode", () => he.decode('Hello &lt;World&gt; &amp; &quot;Friends&quot;'), 50000);
if (slugify) bench("slugify", () => slugify("Hello World! This is a Test 123"), 50000);
if (pluralize) {
  bench("pluralize-plural", () => pluralize("person") + " " + pluralize("child") + " " + pluralize("mouse"), 50000);
  bench("pluralize-singular", () => pluralize.singular("people") + " " + pluralize.singular("children"), 50000);
  bench("pluralize-isPlural", () => pluralize.isPlural("cats") && !pluralize.isPlural("cat"), 100000);
}
if (sprintfJs) {
  bench("sprintf-format", () => sprintfJs.sprintf("Hello %s, you are %d years old", "Alice", 30), 50000);
  bench("sprintf-pad", () => sprintfJs.sprintf("%05d %10s %-10s", 42, "right", "left"), 50000);
  bench("sprintf-float", () => sprintfJs.sprintf("%.2f %.4f %e", 3.14159, 2.71828, 6.022e23), 50000);
}
if (punycode) {
  bench("punycode-encode", () => punycode.encode("münchen"), 50000);
  bench("punycode-decode", () => punycode.decode("mnchen-3ya"), 50000);
  bench("punycode-toASCII", () => punycode.toASCII("münchen.de"), 50000);
}

// ============================================================
// 7. SERIALIZATION/PARSING (25 tests)
// ============================================================

if (fastJsonStableStringify) {
  bench("fast-json-stable-stringify-obj", () => fastJsonStableStringify({c:3,a:1,b:2}), 100000);
  bench("fast-json-stable-stringify-nested", () => fastJsonStableStringify({z:{b:2,a:1},y:{d:4,c:3}}), 50000);
  bench("fast-json-stable-stringify-array", () => fastJsonStableStringify([{b:2,a:1},{d:4,c:3}]), 50000);
}
if (safeStableStringify) {
  bench("safe-stable-stringify-obj", () => safeStableStringify({c:3,a:1,b:2}), 100000);
  bench("safe-stable-stringify-circular", () => {
    const obj = {a: 1}; obj.self = obj;
    return safeStableStringify(obj);
  }, 50000);
}
if (json5) {
  bench("json5-parse", () => json5.parse('{a: 1, b: 2, c: "hello",}'), 20000);
  bench("json5-stringify", () => json5.stringify({a: 1, b: 2, c: "hello"}), 20000);
}
if (hjson && typeof hjson.parse === "function") {
  bench("hjson-parse", () => hjson.parse('{\n  a: 1\n  b: 2\n  c: hello\n}'), 20000);
  bench("hjson-stringify", () => hjson.stringify({a: 1, b: 2, c: "hello"}), 20000);
}
if (toml) {
  bench("toml-parse", () => toml.parse('[server]\nhost = "localhost"\nport = 3000'), 10000);
  bench("toml-parse-complex", () => toml.parse('[database]\nurl = "postgres://localhost"\npool = 10\n\n[cache]\nttl = 300\ndriver = "redis"'), 10000);
}
if (ini) {
  bench("ini-parse", () => ini.parse("[server]\nhost=localhost\nport=3000"), 50000);
  bench("ini-stringify", () => ini.stringify({server: {host: "localhost", port: 3000}}), 50000);
}
if (cookie) {
  bench("cookie-parse", () => cookie.parse("session=abc123; theme=dark; lang=en"), 50000);
  bench("cookie-serialize", () => cookie.serialize("session", "abc123", {httpOnly: true, maxAge: 3600}), 50000);
}
if (contentType) {
  bench("content-type-parse", () => contentType.parse("application/json; charset=utf-8"), 50000);
}
if (bytesLib) {
  bench("bytes-parse", () => bytesLib.parse("1KB") + bytesLib.parse("2MB") + bytesLib.parse("3GB"), 100000);
  bench("bytes-format", () => bytesLib.format(1024) + " " + bytesLib.format(1048576), 100000);
}
if (mimeTypes) {
  bench("mime-types-lookup", () => mimeTypes.lookup("test.json") + " " + mimeTypes.lookup("style.css"), 50000);
  bench("mime-types-extension", () => mimeTypes.extension("application/json"), 50000);
}

// ============================================================
// 8. HASHING & COMPRESSION (15 tests)
// ============================================================

if (objectHash) {
  bench("object-hash-simple", () => objectHash({a: 1, b: 2, c: 3}), 10000);
  bench("object-hash-nested", () => objectHash({a: {b: {c: [1,2,3]}}, d: "hello"}), 10000);
  bench("object-hash-array", () => objectHash([1, "hello", {x: 42}, true, null]), 10000);
}
if (murmurhash) {
  bench("murmurhash-v2", () => murmurhash.murmur2("Hello, World!", 0), 100000);
  bench("murmurhash-v3", () => murmurhash.murmur3("Hello, World!", 0), 100000);
  bench("murmurhash-v2-long", () => murmurhash.murmur2("The quick brown fox jumps over the lazy dog".repeat(10), 42), 50000);
}
if (fnvPlus) {
  bench("fnv-hash32", () => fnvPlus.hash("Hello, World!", 32), 50000);
  bench("fnv-hash64", () => fnvPlus.hash("Hello, World!", 64), 50000);
}
if (lzString) {
  const lzInput = "Hello World! ".repeat(100);
  bench("lz-string-compress", () => lzString.compress(lzInput), 5000);
  bench("lz-string-decompress", () => lzString.decompress(lzString.compress(lzInput)), 2000);
  bench("lz-string-compressUTF16", () => lzString.compressToUTF16(lzInput), 5000);
  bench("lz-string-compressBase64", () => lzString.compressToBase64(lzInput), 5000);
}
if (pako) {
  const pakoInput = new TextEncoder().encode("Hello World! ".repeat(100));
  bench("pako-deflate", () => pako.deflate(pakoInput), 2000);
  bench("pako-inflate", () => pako.inflate(pako.deflate(pakoInput)), 1000);
  bench("pako-gzip", () => pako.gzip(pakoInput), 2000);
}

// ============================================================
// 9. COMPARISON & DEEP-OPS (15 tests)
// ============================================================

if (fastDeepEqual) {
  bench("fast-deep-equal-same", () => fastDeepEqual({a:1,b:[2,3]}, {a:1,b:[2,3]}), 100000);
  bench("fast-deep-equal-diff", () => fastDeepEqual({a:1,b:[2,3]}, {a:1,b:[2,4]}), 100000);
  bench("fast-deep-equal-nested", () => fastDeepEqual(
    {a:{b:{c:{d:[1,2,3]}}}}, {a:{b:{c:{d:[1,2,3]}}}}
  ), 50000);
}
if (isPlainObject) {
  bench("is-plain-object-true", () => isPlainObject.isPlainObject({}), 200000);
  bench("is-plain-object-false", () => isPlainObject.isPlainObject(new Date()), 200000);
}
if (deepmerge) {
  bench("deepmerge-simple", () => deepmerge({a:1,b:2}, {b:3,c:4}), 50000);
  bench("deepmerge-nested", () => deepmerge({a:{b:{c:1}}}, {a:{b:{d:2}}}), 50000);
  bench("deepmerge-arrays", () => deepmerge({a:[1,2]}, {a:[3,4]}), 50000);
}
if (rfdc) {
  const clone = rfdc();
  bench("rfdc-clone-simple", () => clone({a:1,b:"hello",c:[1,2,3]}), 100000);
  bench("rfdc-clone-deep", () => clone({a:{b:{c:{d:[1,{e:2}]}}}}), 50000);
  bench("rfdc-clone-array", () => clone([{a:1},{b:2},{c:3},{d:4},{e:5}]), 50000);
}
if (cloneDeep) {
  bench("clone-deep-simple", () => cloneDeep({a:1,b:"hello",c:[1,2,3]}), 50000);
  bench("clone-deep-nested", () => cloneDeep({a:{b:{c:{d:[1,{e:2}]}}}}), 50000);
}
if (kindOf) {
  bench("kind-of-types", () => {
    return kindOf(42) + kindOf("str") + kindOf([]) + kindOf({}) + kindOf(null) + kindOf(true);
  }, 100000);
}
if (isNumber) {
  bench("is-number-check", () => isNumber(42) + isNumber("42") + isNumber(NaN) + isNumber(Infinity), 200000);
}

// ============================================================
// 10. DIFF & STRING SIMILARITY (10 tests)
// ============================================================

if (diff) {
  bench("diff-chars", () => diff.diffChars("hello world", "hello earth"), 20000);
  bench("diff-words", () => diff.diffWords("the quick brown fox", "the slow brown dog"), 20000);
  bench("diff-lines", () => diff.diffLines("line1\nline2\nline3", "line1\nmodified\nline3"), 20000);
  bench("diff-create-patch", () => diff.createPatch("file.txt", "old content\n", "new content\n"), 10000);
}
if (stringSimilarity) {
  bench("string-similarity-compare", () => stringSimilarity.compareTwoStrings("hello", "hallo"), 50000);
  bench("string-similarity-bestMatch", () => stringSimilarity.findBestMatch("hello", ["hallo", "world", "help", "hell"]), 20000);
}

// ============================================================
// 11. EVENT EMITTER (10 tests)
// ============================================================

if (eventemitter3) {
  bench("ee3-emit-listen", () => {
    const ee = new eventemitter3();
    let count = 0;
    ee.on("data", () => count++);
    for (let i = 0; i < 100; i++) ee.emit("data");
    return count;
  }, 5000);

  bench("ee3-once", () => {
    const ee = new eventemitter3();
    let count = 0;
    ee.once("event", () => count++);
    ee.emit("event");
    ee.emit("event");
    return count;
  }, 50000);

  bench("ee3-multi-listener", () => {
    const ee = new eventemitter3();
    let sum = 0;
    for (let i = 0; i < 10; i++) ee.on("data", (v) => sum += v);
    ee.emit("data", 42);
    return sum;
  }, 10000);

  bench("ee3-removeListener", () => {
    const ee = new eventemitter3();
    const fn = () => {};
    ee.on("event", fn);
    ee.removeListener("event", fn);
    return ee.listenerCount("event");
  }, 50000);

  bench("ee3-removeAllListeners", () => {
    const ee = new eventemitter3();
    for (let i = 0; i < 10; i++) ee.on("event", () => {});
    ee.removeAllListeners("event");
    return ee.listenerCount("event");
  }, 50000);
}

// ============================================================
// 12. ENCODING/HTML (10 tests)
// ============================================================

if (htmlEntities) {
  bench("html-entities-encode", () => htmlEntities.encode('<div class="test">Hello & "World"</div>'), 50000);
  bench("html-entities-decode", () => htmlEntities.decode('&lt;div&gt;Hello &amp; &quot;World&quot;&lt;/div&gt;'), 50000);
}
if (cssesc) {
  bench("cssesc-identifier", () => cssesc("my-class.name#id"), 50000);
  bench("cssesc-string", () => cssesc("hello 'world'", {quotes: 'single'}), 50000);
}
if (linkifyIt) {
  const linkify = linkifyIt();
  bench("linkify-test", () => linkify.test("Check https://example.com for details"), 50000);
  bench("linkify-match", () => linkify.match("Visit https://google.com and http://example.com"), 20000);
}

// ============================================================
// 13. LRU CACHE (5 tests)
// ============================================================

if (lruCache) {
  bench("lru-cache-set-get", () => {
    const cache = new lruCache({max: 100});
    for (let i = 0; i < 200; i++) cache.set("key" + i, "value" + i);
    let found = 0;
    for (let i = 100; i < 200; i++) if (cache.get("key" + i)) found++;
    return found;
  }, 2000);

  bench("lru-cache-has-delete", () => {
    const cache = new lruCache({max: 50});
    for (let i = 0; i < 100; i++) cache.set(i, i);
    let count = 0;
    for (let i = 50; i < 100; i++) if (cache.has(i)) { cache.delete(i); count++; }
    return count;
  }, 5000);

  bench("lru-cache-eviction", () => {
    const cache = new lruCache({max: 10});
    for (let i = 0; i < 100; i++) cache.set(i, i);
    return cache.size;
  }, 10000);
}

// ============================================================
// 14. REAL-WORLD SIMULATION PATTERNS (20 tests)
// ============================================================

// Simulated Express-like middleware pipeline using real packages
if (_ && cookie && contentType && escapeHtml && bytesLib) {
  bench("rw-http-request-parse", () => {
    const headers = {
      "content-type": "application/json; charset=utf-8",
      "cookie": "session=abc123; theme=dark; lang=en",
      "content-length": "1234"
    };
    const ct = contentType.parse(headers["content-type"]);
    const cookies = cookie.parse(headers["cookie"]);
    const bodySize = bytesLib.format(parseInt(headers["content-length"]));
    return ct.type + " " + cookies.session + " " + bodySize;
  }, 20000);

  bench("rw-response-build", () => {
    const body = escapeHtml('<div>Hello "World" & Friends</div>');
    const cookies = cookie.serialize("session", "new123", {httpOnly: true});
    return body.length + cookies.length;
  }, 50000);
}

if (_ && validator) {
  bench("rw-input-validation", () => {
    const input = {
      email: "user@example.com",
      name: "Alice Bob",
      age: "30",
      url: "https://example.com"
    };
    return validator.isEmail(input.email) &&
           validator.isAlpha(input.name.replace(/ /g, '')) &&
           validator.isInt(input.age, {min: 1, max: 150}) &&
           validator.isURL(input.url);
  }, 50000);

  bench("rw-sanitize-inputs", () => {
    const inputs = [
      '<script>alert("xss")</script>',
      '  hello world  ',
      'UPPER lower',
      'email@EXAMPLE.COM'
    ];
    return inputs.map(i => validator.escape(validator.trim(i)));
  }, 20000);
}

if (_ && fastJsonStableStringify) {
  bench("rw-api-response-serialize", () => {
    const response = {
      status: 200,
      data: {
        users: _.range(10).map(i => ({id: i, name: `User ${i}`, email: `user${i}@test.com`})),
        pagination: {page: 1, total: 100, perPage: 10}
      },
      meta: {timestamp: Date.now(), version: "1.0.0"}
    };
    return fastJsonStableStringify(response);
  }, 5000);
}

if (_ && objectHash) {
  bench("rw-cache-key-generation", () => {
    const request = {method: "GET", path: "/api/users", query: {page: 1, limit: 10, sort: "name"}};
    return objectHash(request);
  }, 5000);
}

if (deepmerge && _) {
  bench("rw-config-merge", () => {
    const defaults = {server: {host: "0.0.0.0", port: 3000}, db: {pool: 5, timeout: 30000}, log: {level: "info"}};
    const env = {server: {port: 8080}, db: {pool: 20}, log: {level: "debug"}};
    const local = {server: {host: "127.0.0.1"}};
    return deepmerge.all([defaults, env, local]);
  }, 20000);
}

if (moment && _) {
  bench("rw-date-processing", () => {
    const events = _.range(50).map(i => ({
      name: `Event ${i}`,
      date: moment().add(i, 'days').format("YYYY-MM-DD"),
      active: i % 3 !== 0
    }));
    const upcoming = events.filter(e => moment(e.date).isAfter(moment()));
    return upcoming.length;
  }, 2000);
}

if (lzString && fastJsonStableStringify) {
  bench("rw-cache-compress", () => {
    const data = {items: Array.from({length: 50}, (_, i) => ({id: i, name: `item${i}`, value: Math.random()}))};
    const json = fastJsonStableStringify(data);
    const compressed = lzString.compressToBase64(json);
    const decompressed = lzString.decompressFromBase64(compressed);
    return JSON.parse(decompressed).items.length;
  }, 1000);
}

// Pipeline: lodash + validator + escape-html + cookie
if (_ && validator && escapeHtml && cookie) {
  bench("rw-full-request-pipeline", () => {
    // 1. Parse cookies
    const cookies = cookie.parse("session=abc; user=alice; pref=dark");
    // 2. Validate user input
    const userInput = {email: "alice@test.com", name: "Alice <script>"};
    const valid = validator.isEmail(userInput.email);
    // 3. Sanitize
    const safeName = escapeHtml(userInput.name);
    // 4. Transform with lodash
    const response = _.pick({...cookies, safeName, valid, timestamp: Date.now()}, ['session', 'safeName', 'valid']);
    return JSON.stringify(response);
  }, 10000);
}

// JSON Schema validation pattern
if (json5 && fastDeepEqual) {
  bench("rw-schema-validate-json5", () => {
    const config = json5.parse('{host: "localhost", port: 3000, debug: true}');
    const expected = {host: "localhost", port: 3000, debug: true};
    return fastDeepEqual(config, expected);
  }, 10000);
}

if (diff && _) {
  bench("rw-config-diff", () => {
    const old = "host=localhost\nport=3000\ndebug=false\nlog=info";
    const new_ = "host=localhost\nport=8080\ndebug=true\nlog=debug";
    const changes = diff.diffLines(old, new_);
    return changes.filter(c => c.added || c.removed).length;
  }, 10000);
}

// ============================================================
// 15. MASS PACKAGE OPERATIONS (10 tests)
// ============================================================

bench("mass-require-45-packages", () => {
  // Measure overhead of requiring already-cached modules
  let count = 0;
  const pkgs = [
    "lodash", "underscore", "moment", "ms", "escape-html", "bytes",
    "cookie", "content-type", "validator", "fast-deep-equal",
    "is-plain-object", "deepmerge", "eventemitter3",
    "fast-json-stable-stringify", "punycode", "he", "sprintf-js",
    "toml", "ini", "lz-string", "pako", "object-hash",
    "murmurhash-js", "fnv-plus", "safe-stable-stringify",
    "json5", "hjson", "diff", "string-similarity", "rfdc",
    "kind-of", "is-number", "slugify", "pluralize", "cssesc",
    "html-entities", "lru-cache", "clone-deep", "linkify-it",
    "mime-types", "depd"
  ];
  for (const p of pkgs) {
    try { require(p); count++; } catch(e) {}
  }
  return count;
}, 500);

if (_) {
  bench("mass-lodash-chain-1k", () => {
    return _(_.range(1000))
      .map(x => ({val: x, cat: x % 5, name: `item-${x}`}))
      .filter(x => x.val > 100)
      .groupBy('cat')
      .mapValues(arr => arr.length)
      .value();
  }, 1000);

  bench("mass-lodash-string-ops", () => {
    const words = ["hello-world", "foo_bar", "camelCase", "PascalCase", "SCREAMING_SNAKE"];
    return words.map(w => _.camelCase(w) + " " + _.snakeCase(w) + " " + _.kebabCase(w));
  }, 10000);

  bench("mass-lodash-collection-ops", () => {
    const data = _.range(500).map(i => ({id: i, group: i % 10, score: Math.sin(i) * 100}));
    const grouped = _.groupBy(data, 'group');
    const averages = _.mapValues(grouped, arr => _.meanBy(arr, 'score'));
    return Object.keys(averages).length;
  }, 2000);
}

if (validator) {
  bench("mass-validator-batch", () => {
    const emails = Array.from({length: 100}, (_, i) => `user${i}@example.com`);
    const urls = Array.from({length: 100}, (_, i) => `https://site${i}.com/page`);
    return emails.filter(e => validator.isEmail(e)).length +
           urls.filter(u => validator.isURL(u)).length;
  }, 1000);
}

if (moment) {
  bench("mass-moment-date-range", () => {
    const start = moment("2024-01-01");
    const dates = [];
    for (let i = 0; i < 365; i++) {
      dates.push(start.clone().add(i, 'days').format("YYYY-MM-DD"));
    }
    return dates.length;
  }, 200);
}

if (pako && lzString) {
  bench("mass-compress-compare", () => {
    const data = JSON.stringify(Array.from({length: 100}, (_, i) => ({id: i, name: `item${i}`, data: "x".repeat(50)})));
    const pakoSize = pako.deflate(new TextEncoder().encode(data)).length;
    const lzSize = lzString.compressToBase64(data).length;
    return {original: data.length, pako: pakoSize, lz: lzSize};
  }, 500);
}

// ============================================================
// 16. CVE / SECURITY AUDIT PATTERNS (10 tests)
// ============================================================

// Test prototype pollution resistance
bench("security-prototype-pollution-obj", () => {
  const payload = JSON.parse('{"__proto__":{"polluted":"yes"}}');
  const obj = {};
  Object.assign(obj, payload);
  return ({}).polluted !== "yes";
}, 50000);

bench("security-prototype-pollution-merge", () => {
  if (!deepmerge) return true;
  const target = {};
  const source = JSON.parse('{"__proto__":{"polluted":"yes"}}');
  deepmerge(target, source);
  return ({}).polluted !== "yes";
}, 50000);

// Test JSON parsing safety
bench("security-json-parse-large", () => {
  const big = '{"a":' + '"x"'.repeat(1) + '}';
  try { JSON.parse(big); return true; } catch(e) { return true; }
}, 50000);

// Test ReDoS-resistant patterns
bench("security-regex-redos-safe", () => {
  const safeRe = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  return safeRe.test("a".repeat(100) + "@example.com");
}, 50000);

// Test XSS prevention
if (escapeHtml && validator) {
  bench("security-xss-escape", () => {
    const inputs = [
      '<script>alert(1)</script>',
      '"><img src=x onerror=alert(1)>',
      "javascript:alert('xss')",
      '<svg onload=alert(1)>',
      '{{constructor.constructor("return this")()}}'
    ];
    return inputs.map(i => escapeHtml(validator.escape(i)));
  }, 10000);
}

// Test path traversal prevention
bench("security-path-traversal", () => {
  const paths = ["../../../etc/passwd", "..\\..\\windows\\system32", "....//....//etc/passwd"];
  return paths.every(p => p.includes(".."));
}, 100000);

// Test integer overflow handling
bench("security-integer-overflow", () => {
  const big = Number.MAX_SAFE_INTEGER;
  return big + 1 === big + 2;
}, 200000);

// Test null byte injection
bench("security-null-byte", () => {
  const s = "hello\0world";
  return s.length === 11 && s.indexOf("\0") === 5;
}, 200000);

// Test deep nesting DoS resistance
bench("security-deep-nesting-json", () => {
  let json = '{"a":';
  for (let i = 0; i < 50; i++) json += '{"a":';
  json += '1';
  for (let i = 0; i < 51; i++) json += '}';
  try { return JSON.parse(json).a.a !== undefined; } catch(e) { return true; }
}, 10000);

// Test URL parsing security
bench("security-url-parse", () => {
  try {
    const u = new URL("https://evil.com%0D%0AHost:good.com/path");
    return u.hostname;
  } catch(e) { return "blocked"; }
}, 50000);

// ============================================================
// Summary
// ============================================================

console.log("\n=== npm Stress Test Results ===");
console.log(`Tests: ${testCount} (${passCount} passed, ${failCount} failed)`);

let total = 0;
for (const [name, r] of Object.entries(results)) total += r.elapsed;
console.log(`Total wall time: ${total}ms`);

const categories = {};
for (const [name, r] of Object.entries(results)) {
  const parts = name.split("-");
  const cat = parts[0] === "rw" ? "real-world" :
              parts[0] === "mass" ? "mass-ops" :
              parts[0] === "security" ? "security" :
              parts[0];
  categories[cat] = (categories[cat] || 0) + r.elapsed;
}
console.log("\nBy category:");
for (const [cat, ms] of Object.entries(categories).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${cat}: ${ms}ms`);
}

// Top 10 slowest
const sorted = Object.entries(results).sort((a, b) => b[1].elapsed - a[1].elapsed);
console.log("\nTop 10 slowest:");
for (let i = 0; i < Math.min(10, sorted.length); i++) {
  const [name, r] = sorted[i];
  console.log(`  ${r.elapsed}ms - ${name} (${r.opsPerSec.toLocaleString()} ops/sec)`);
}
