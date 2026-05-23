// Node-ported regression tests — distilled from
// nodejs/node `test/parallel/test-buffer-badhex.js` +
// `test/parallel/test-buffer-bytelength.js`.
//
// Each block cites the Node test it came from. Goal: catch DunJS
// gaps that real-world Node code hits when running through our
// runtime. We use the existing DunJS `check(name, cond)` pattern
// (no `node:test` / `common.js` dep) so the test runs cleanly on
// QJS / JSC / V8.
//
// History: this port surfaced two real gaps that are now fixed:
//   1. `buf.write(str, offset, "hex")` ignored the encoding arg
//      entirely — wrote the JS string as raw UTF-8 bytes instead
//      of decoding hex pairs. Node `test-buffer-badhex` line-1
//      failure.
//   2. `Buffer.byteLength(arrayBuf)` returned 0 because we only
//      checked `length` (Buffer/TypedArray) not `byteLength`
//      (ArrayBuffer/DataView).  Plus all the string-encoding
//      length calculations (`hex`/`base64`/`utf-16le`/`ascii`/
//      `latin1`) were missing — returned the raw UTF-8 byte
//      length instead of the encoded length.

const assert = require("assert");
let passed = 0, total = 0;
function check(name, fn) {
  total++;
  try { fn(); passed++; }
  catch (e) { console.log("FAIL:", name, "—", e.message || e); }
}

// ─────────────────────────────────────────────────────────────────
// 1. Buffer.prototype.write — port of `test-buffer-badhex.js`
// ─────────────────────────────────────────────────────────────────
check("write 'abcdxx' as hex returns 2", () => {
  const buf = Buffer.alloc(4);
  assert.strictEqual(buf.write("abcdxx", 0, "hex"), 2);
  assert.deepStrictEqual(buf, Buffer.from([0xab, 0xcd, 0x00, 0x00]));
  assert.strictEqual(buf.toString("hex"), "abcd0000");
});

check("write 'abcdef01' as hex returns 4", () => {
  const buf = Buffer.alloc(4);
  assert.strictEqual(buf.write("abcdef01", 0, "hex"), 4);
  assert.strictEqual(buf.toString("hex"), "abcdef01");
});

check("write 'abcdxx' at offset 1 as hex returns 2", () => {
  const buf = Buffer.alloc(5);
  assert.strictEqual(buf.write("abcdxx", 1, "hex"), 2);
  assert.strictEqual(buf.toString("hex"), "00abcd0000");
});

check("write 'xxabcd' as hex returns 0 (first pair invalid)", () => {
  const buf = Buffer.alloc(4);
  assert.strictEqual(buf.write("xxabcd", 0, "hex"), 0);
  assert.deepStrictEqual(buf, Buffer.from([0, 0, 0, 0]));
});

check("write 'cdxxab' as hex returns 1 (stops at xx)", () => {
  const buf = Buffer.alloc(4);
  assert.strictEqual(buf.write("cdxxab", 0, "hex"), 1);
  assert.deepStrictEqual(buf, Buffer.from([0xcd, 0, 0, 0]));
});

check("round-trip all 256 bytes through hex", () => {
  const buf = Buffer.alloc(256);
  for (let i = 0; i < 256; i++) buf[i] = i;
  const hex = buf.toString("hex");
  assert.deepStrictEqual(Buffer.from(hex, "hex"), buf);
});

check("bad hex in middle truncates at first invalid", () => {
  // Per Node: insert "xx" into 256-byte hex → only first half decoded
  const buf = Buffer.alloc(256);
  for (let i = 0; i < 256; i++) buf[i] = i;
  const hex = buf.toString("hex");
  const badHex = hex.slice(0, 256) + "xx" + hex.slice(256, 510);
  assert.deepStrictEqual(Buffer.from(badHex, "hex"), buf.slice(0, 128));
});

// ─────────────────────────────────────────────────────────────────
// 2. Buffer.byteLength — port of `test-buffer-bytelength.js`
// ─────────────────────────────────────────────────────────────────
check("byteLength of Buffer", () => {
  assert.strictEqual(Buffer.byteLength(Buffer.from("abc")), 3);
});
check("byteLength of incomplete multi-byte UTF-8 buffer", () => {
  const buf = Buffer.from([0xe4, 0xb8, 0xad, 0xe6, 0x96]);
  assert.strictEqual(Buffer.byteLength(buf), 5);
});
check("byteLength of ArrayBuffer", () => {
  assert.strictEqual(Buffer.byteLength(new ArrayBuffer(8)), 8);
});
check("byteLength of TypedArrays (byte-size aware)", () => {
  assert.strictEqual(Buffer.byteLength(new Int8Array(8)), 8);
  assert.strictEqual(Buffer.byteLength(new Uint8Array(8)), 8);
  assert.strictEqual(Buffer.byteLength(new Int16Array(8)), 16);
  assert.strictEqual(Buffer.byteLength(new Uint32Array(8)), 32);
  assert.strictEqual(Buffer.byteLength(new Float32Array(8)), 32);
  assert.strictEqual(Buffer.byteLength(new Float64Array(8)), 64);
});
check("byteLength of DataView", () => {
  assert.strictEqual(Buffer.byteLength(new DataView(new ArrayBuffer(2))), 2);
});

check("byteLength of empty string in various encodings", () => {
  assert.strictEqual(Buffer.byteLength("", "ascii"), 0);
  assert.strictEqual(Buffer.byteLength("", "HeX"), 0);
});

check("byteLength of UTF-8 strings (codepoints → bytes)", () => {
  assert.strictEqual(Buffer.byteLength("∑éllö wørl∂!", "utf-8"), 19);
  assert.strictEqual(Buffer.byteLength("κλμνξο", "utf8"), 12);
  assert.strictEqual(Buffer.byteLength("hello world"), 11);
});

check("byteLength of hex string is len/2", () => {
  assert.strictEqual(Buffer.byteLength("aabb00ccddee", "hex"), 6);
});

check("byteLength of base64 string is decoded length", () => {
  assert.strictEqual(Buffer.byteLength("aGVsbG8gd29ybGQ=", "base64"), 11);
});

check("byteLength of utf-16le string is units*2", () => {
  assert.strictEqual(Buffer.byteLength("abc", "utf-16le"), 6);
});

check("byteLength with unrecognized encoding falls back to utf8", () => {
  assert.strictEqual(Buffer.byteLength("hello world", "abc"), 11);
});

console.log(`\n${passed}/${total} Node-ported behaviors verified`);
if (passed !== total) {
  console.log("FAIL: some Node-test invariants don't hold on DunJS");
  process.exit(1);
}
