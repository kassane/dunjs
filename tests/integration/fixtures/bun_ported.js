// Bun-ported regression tests — distillation of behavioral expectations
// from oven-sh/bun's `test/js/node/buffer*.test.ts` plus
// `bench/deepEqual/*.js` / `bench/expect-to-equal/*.js`.
//
// Provenance: each check cites the upstream Bun test that motivated it.
// Goal: catch DunJS gaps that real-world apps hit when they run Bun-
// compatible code. We use the existing DunJS `check(name, cond)` pattern
// (no @jest/globals / bun:test dependency) so the test runs cleanly on
// QJS / JSC / V8.

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log("FAIL:", name);
}

// ─────────────────────────────────────────────────────────────────
// 1. Buffer encoding round-trips — port of `buffer-utf16.test.ts`
// ─────────────────────────────────────────────────────────────────
// Bun's utf16-le test: verify all 256 byte values round-trip
// through `Buffer.from(s, "utf-16le").toString("hex")`. Catches
// the encoding bug class that v1.1.3 latin1 + v1.1.4 NUL hit.

(function buffer_utf16_le_round_trip() {
  const row = (i) => Buffer.from(
    Array.from({length: 16}, (_, j) => String.fromCharCode(i * 16 + j)).join(""),
    "utf-16le"
  ).toString("hex");

  // First and last rows fully verified.
  check("utf16le row 0", row(0) === "00000100020003000400050006000700080009000a000b000c000d000e000f00");
  check("utf16le row 15 (0xf0..0xff)", row(15) === "f000f100f200f300f400f500f600f700f800f900fa00fb00fc00fd00fe00ff00");
  // Mid-row: ASCII codepoint 0x41 ('A') in LE is "4100"
  check("utf16le 'A' encodes as 4100", Buffer.from("A", "utf-16le").toString("hex") === "4100");
})();

// ─────────────────────────────────────────────────────────────────
// 2. Buffer.from(string, encoding) zero-length cases — port of
//    `buffer-from-encoding-leak.test.ts`
// ─────────────────────────────────────────────────────────────────
// All-invalid input must produce a zero-length Buffer without UB
// and without leaking the staging allocation (we can't measure
// RSS portably; verify the correctness invariant).

(function buffer_zero_length_decodes() {
  check("hex of 'zz' is empty Buffer",
    Buffer.from("zz", "hex").length === 0);
  check("hex of 'z' is empty Buffer",
    Buffer.from("z", "hex").length === 0);
  check("base64 of '   ' is empty Buffer",
    Buffer.from("   ", "base64").length === 0);
  // Sanity: ensure decoded bytes equal what we expect
  check("hex of 'ff' decodes to one byte 0xff",
    (() => { const b = Buffer.from("ff", "hex"); return b.length === 1 && b[0] === 0xff; })());
})();

// ─────────────────────────────────────────────────────────────────
// 3. Buffer.concat invariants — port of `buffer-concat.test.ts`
// ─────────────────────────────────────────────────────────────────
(function buffer_concat() {
  const a = Buffer.from("hello");
  const b = Buffer.from(" ");
  const c = Buffer.from("world");

  check("concat normal", Buffer.concat([a, b, c]).toString() === "hello world");

  // totalLength: exact length truncates to it
  check("concat totalLength = 11 (exact)", Buffer.concat([a, b, c], 11).toString() === "hello world");
  // totalLength bigger: pads with zeros
  const r2 = Buffer.concat([a, b, c], 15);
  check("concat totalLength = 15 (pads zeros)", r2.length === 15 && r2[14] === 0);
  check("concat totalLength = 15 keeps prefix", r2.toString("utf8", 0, 11) === "hello world");
  // totalLength smaller: truncates
  check("concat totalLength = 5 (truncates)", Buffer.concat([a, b, c], 5).toString() === "hello");
  // Empty array
  check("concat empty array", Buffer.concat([]).length === 0);
  // Single-element
  check("concat single", Buffer.concat([a]).toString() === "hello");
})();

// ─────────────────────────────────────────────────────────────────
// 4. Deep equality — port of `bench/deepEqual/{map,set}.js`
// ─────────────────────────────────────────────────────────────────
// Bun uses `expect(a).toEqual(b)` for deep equality on Map/Set.
// DunJS exposes `Bun.deepEquals(a, b)` — same semantics. The
// upstream bench verifies Map/Set/CustomMap/CustomSet equality.

(function deep_equals() {
  check("primitives equal", Bun.deepEquals("hello", "hello"));
  check("primitives not equal", !Bun.deepEquals("hello", "world"));
  check("objects equal regardless of key order",
    Bun.deepEquals({ a: 1, b: 2 }, { b: 2, a: 1 }));
  check("objects with extra key not equal",
    !Bun.deepEquals({ a: 1, b: 2 }, { a: 1, b: 2, c: 3 }));
  check("arrays equal",
    Bun.deepEquals([1, 2, 3], [1, 2, 3]));
  check("arrays different length not equal",
    !Bun.deepEquals([1, 2, 3], [1, 2, 3, 4]));
  check("nested arrays of objects equal",
    Bun.deepEquals([{a: 1}, {b: 2, c: 3, d: 4}], [{a: 1}, {b: 2, c: 3, d: 4}]));
  check("nested object mutation breaks equality",
    (() => {
      const x = [{a: 1}, {b: 2}];
      const y = [{a: 1}, {b: 2}];
      const eq1 = Bun.deepEquals(x, y);
      x[0].a = 99;
      return eq1 && !Bun.deepEquals(x, y);
    })());

  // Symbol-keyed properties — Bun's bench notes these are NOT
  // expected to equal because Symbol keys are per-Symbol identity.
  const ka = { [Symbol("test")]: 1 };
  const kb = { [Symbol("test")]: 1 };
  check("Symbol-keyed props compare by identity",
    !Bun.deepEquals(ka, kb));
})();

// ─────────────────────────────────────────────────────────────────
// 5. EventEmitter primitives — port of `bench/emitter/microbench.mjs`
//    invariants (not the perf, the behavior)
// ─────────────────────────────────────────────────────────────────
(function emitter() {
  const { EventEmitter } = require("events");
  const e = new EventEmitter();
  let count = 0;
  e.on("data", () => count++);
  e.emit("data");
  e.emit("data");
  check("EventEmitter.on + emit fires listener", count === 2);

  // once() fires exactly once
  let onceCount = 0;
  e.once("ping", () => onceCount++);
  e.emit("ping");
  e.emit("ping");
  check("EventEmitter.once fires exactly once", onceCount === 1);

  // setMaxListeners + listenerCount
  e.setMaxListeners(100);
  for (let i = 0; i < 50; i++) e.on("many", () => {});
  check("listenerCount('many') = 50", e.listenerCount("many") === 50);
})();

// ─────────────────────────────────────────────────────────────────
// 6. Hex / base64 / latin1 round-trips — combined Buffer regression
//    (covers the v1.1.3 / v1.1.4 CVE-class fixes that DunJS shipped)
// ─────────────────────────────────────────────────────────────────
(function encoding_round_trips() {
  // Latin-1 high bytes (0x80–0xFF) — pre-v1.1.3 these silently
  // dropped on DunJS-JSC; ensure they still round-trip.
  const high = Buffer.from([0x80, 0x90, 0xC0, 0xFF]);
  check("latin1 high-byte round-trip",
    Buffer.from(high.toString("latin1"), "latin1").equals(high));

  // Hex of all 256 byte values
  const all256 = Buffer.alloc(256);
  for (let i = 0; i < 256; i++) all256[i] = i;
  check("hex round-trip 256 bytes",
    Buffer.from(all256.toString("hex"), "hex").equals(all256));

  // Base64 round-trip
  check("base64 round-trip 256 bytes",
    Buffer.from(all256.toString("base64"), "base64").equals(all256));

  // NUL byte in middle of string
  const withNul = Buffer.from([0x41, 0x00, 0x42]);
  check("latin1 round-trip with embedded NUL",
    Buffer.from(withNul.toString("latin1"), "latin1").equals(withNul));
})();

console.log(`\n${passed}/${total} Bun-ported behaviors verified`);
if (passed !== total) {
  console.log("FAIL: some Bun-test invariants don't hold on DunJS");
  process.exit(1);
}
