// Node v26.x benchmark ports — distilled from
// `nodejs/node/benchmark/buffers/` into a single DunJS-runnable
// micro-bench. Excludes the `common.createBenchmark` framework
// (which uses child_process + JSON config matrix) and just runs
// each inner `main` function with one representative config.
//
// Goal: measure DunJS performance on these v26 hot paths +
// guard against future regressions (e.g. if the hex decoder
// gets touched, the buffer-hex-encode/decode bench should not
// slow down 2×).
//
// Reports `Total throughput: N ops/sec` so `/bench-compare` and
// similar tooling can extract a single number.

const buffer = require("buffer");
const assert = require("assert");

const TARGET_MS = 200;     // run each test for at least this long
let totalOps = 0;
let totalElapsedMs = 0;

function bench(name, fn) {
  // Warmup so JIT (V8/JSC) compiles the hot path.
  for (let i = 0; i < 1000; i++) fn();

  let iters = 1000;
  let elapsed = 0;
  while (elapsed < TARGET_MS) {
    const t0 = Date.now();
    for (let i = 0; i < iters; i++) fn();
    elapsed = Date.now() - t0;
    if (elapsed < TARGET_MS) iters *= 2;
  }
  const opsPerSec = Math.round((iters / elapsed) * 1000);
  totalOps += iters;
  totalElapsedMs += elapsed;
  console.log("  " + name + ": " + opsPerSec.toLocaleString() + " ops/sec");
  return opsPerSec;
}

console.log("=== buffer-bytelength-string (port of v26 bench) ===");
{
  const samples = {
    one_byte:    "hello brendan!!!",
    two_bytes:   "ΰαβγδεζηθικλμνξο",
    three_bytes: "挰挱挲挳挴挵挶挷挸挹挺挻挼挽挾挿",
    four_bytes:  "𠜎𠜱𠝹𠱓𠱸𠲖𠳏𠳕𠴕𠵼𠵿𠸎𠸏𠹷𠺝𠺢",
    latin1:      "Un homme sage est supérieur à toutes les insultes",
  };
  for (const enc of ["utf8", "base64", "latin1", "hex"]) {
    for (const type of ["one_byte", "two_bytes", "four_bytes"]) {
      const data = samples[type].repeat(16);
      bench("bytelength " + enc + "/" + type,
        () => { Buffer.byteLength(data, enc); });
    }
  }
}

console.log("\n=== buffer-hex-encode/decode (v26 bench) ===");
{
  const buf = Buffer.alloc(64);
  for (let i = 0; i < buf.length; i++) buf[i] = i & 0xff;
  const hex = buf.toString("hex");
  bench("buf.toString('hex') 64B", () => buf.toString("hex"));
  bench("Buffer.from(hex, 'hex') 64B", () => Buffer.from(hex, "hex"));
}

console.log("\n=== buffer-isutf8 / isAscii (v26 bench, Node v19.5+ API) ===");
{
  // Short input
  const short = new TextEncoder().encode("hello world");
  // Long input
  const longInput = new TextEncoder().encode("hello world".repeat(200));
  // Unicode input
  const uni = new TextEncoder().encode("∀x∈ℝ: ⌈x⌉ = −⌊−x⌋".repeat(50));

  bench("isUtf8(short ASCII)",   () => { assert.ok(buffer.isUtf8(short)); });
  bench("isUtf8(long ASCII)",    () => { assert.ok(buffer.isUtf8(longInput)); });
  bench("isUtf8(Unicode)",       () => { assert.ok(buffer.isUtf8(uni)); });
  bench("isAscii(short)",        () => { assert.ok(buffer.isAscii(short)); });
  bench("isAscii(long)",         () => { assert.ok(buffer.isAscii(longInput)); });
}

console.log("\n=== buffer-concat (v26 bench) ===");
{
  const a = Buffer.from("hello");
  const b = Buffer.from(" ");
  const c = Buffer.from("world");
  bench("concat 3 small", () => Buffer.concat([a, b, c]));
  bench("concat with totalLength", () => Buffer.concat([a, b, c], 11));
}

console.log("\n=== buffer-creation (v26 bench) ===");
{
  bench("Buffer.alloc(64)",      () => Buffer.alloc(64));
  bench("Buffer.alloc(1024)",    () => Buffer.alloc(1024));
  bench("Buffer.from('hello')",  () => Buffer.from("hello"));
  bench("Buffer.from([1,2,3])",  () => Buffer.from([1, 2, 3]));
}

const overallOpsPerSec = Math.round((totalOps / totalElapsedMs) * 1000);
console.log("\nTotal throughput: " + overallOpsPerSec.toLocaleString() + " ops/sec");
