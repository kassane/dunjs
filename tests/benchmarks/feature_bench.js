// Feature benchmark suite — cross-runtime comparison (DunJS / Bun / Deno / Node)
// Run: dun bench tests/benchmarks/feature_bench.js
// Run: bun run tests/benchmarks/feature_bench.js
// Run: deno run tests/benchmarks/feature_bench.js
// Run: node tests/benchmarks/feature_bench.js

const results = [];

function benchmark(name, fn, warmup = 100, minMs = 200) {
    for (let i = 0; i < warmup; i++) fn();

    let iters = 1;
    let elapsed = 0;
    while (elapsed < minMs) {
        const start = Date.now();
        for (let j = 0; j < iters; j++) fn();
        elapsed = Date.now() - start;
        if (elapsed < minMs) iters *= 2;
    }
    const nsPerOp = Math.round((elapsed * 1e6) / iters);
    const opsPerSec = Math.round((iters / elapsed) * 1000);
    results.push({ name, nsPerOp, opsPerSec, iters });
    console.log(`  ${name}: ${nsPerOp}ns/op (${opsPerSec.toLocaleString()} ops/sec)`);
}

// ── Crypto ──────────────────────────────────────────────────────────
console.log("\n=== Crypto ===");

const crypto = require("crypto");

benchmark("crypto.randomUUID", () => {
    crypto.randomUUID();
});

benchmark("crypto.createHash SHA-256", () => {
    crypto.createHash("sha256").update("hello world benchmark data").digest("hex");
});

// ── Buffer ──────────────────────────────────────────────────────────
console.log("\n=== Buffer ===");

benchmark("Buffer.from string", () => {
    const b = Buffer.from("hello world benchmark data string");
});

benchmark("Buffer.alloc 1024", () => {
    Buffer.alloc(1024);
});

benchmark("Buffer.concat", () => {
    const a = Buffer.from("hello");
    const b = Buffer.from("world");
    Buffer.concat([a, b]);
});

// ── URL Parsing ─────────────────────────────────────────────────────
console.log("\n=== URL ===");

benchmark("new URL()", () => {
    new URL("https://example.com:8080/path?query=value&foo=bar#fragment");
});

benchmark("URLSearchParams", () => {
    const p = new URLSearchParams("a=1&b=2&c=3&d=4&e=5");
    p.get("c");
});

// ── JSON ────────────────────────────────────────────────────────────
console.log("\n=== JSON ===");

const jsonObj = { users: Array.from({length: 100}, (_, i) => ({ id: i, name: "user" + i, active: i % 2 === 0 })) };
const jsonStr = JSON.stringify(jsonObj);

benchmark("JSON.parse (100 objects)", () => {
    JSON.parse(jsonStr);
});

benchmark("JSON.stringify (100 objects)", () => {
    JSON.stringify(jsonObj);
});

// ── String Operations ───────────────────────────────────────────────
console.log("\n=== String ===");

benchmark("string split/join", () => {
    "the quick brown fox jumps over the lazy dog".split(" ").join("-");
});

benchmark("string replace (regex)", () => {
    "hello world hello world hello".replace(/hello/g, "hi");
});

benchmark("template literal", () => {
    const name = "world";
    const greeting = `Hello, ${name}! Today is ${new Date().getFullYear()}.`;
});

// ── Array Operations ────────────────────────────────────────────────
console.log("\n=== Array ===");

benchmark("Array.from + map", () => {
    Array.from({length: 100}, (_, i) => i * 2);
});

benchmark("array.filter + reduce", () => {
    const arr = Array.from({length: 100}, (_, i) => i);
    arr.filter(x => x % 2 === 0).reduce((a, b) => a + b, 0);
});

benchmark("array.sort 100 elements", () => {
    const arr = Array.from({length: 100}, () => Math.random());
    arr.sort((a, b) => a - b);
});

// ── Object Operations ───────────────────────────────────────────────
console.log("\n=== Object ===");

benchmark("Object.keys/values/entries", () => {
    const obj = { a: 1, b: 2, c: 3, d: 4, e: 5 };
    Object.keys(obj);
    Object.values(obj);
    Object.entries(obj);
});

benchmark("Object.assign merge", () => {
    const a = { x: 1, y: 2, z: 3 };
    const b = { y: 20, w: 40 };
    Object.assign({}, a, b);
});

benchmark("structuredClone", () => {
    structuredClone({ a: 1, b: [2, 3], c: { d: 4 } });
});

// ── TextEncoder/TextDecoder ─────────────────────────────────────────
console.log("\n=== Encoding ===");

benchmark("TextEncoder encode", () => {
    new TextEncoder().encode("Hello, World! 🌍 UTF-8 encoding benchmark string");
});

benchmark("TextDecoder decode", () => {
    const encoded = new TextEncoder().encode("Hello, World! 🌍 UTF-8 decoding benchmark");
    new TextDecoder().decode(encoded);
});

benchmark("btoa/atob round-trip", () => {
    const encoded = btoa("Hello, World! Base64 benchmark");
    atob(encoded);
});

// ── Map/Set ─────────────────────────────────────────────────────────
console.log("\n=== Map/Set ===");

benchmark("Map set/get 100", () => {
    const m = new Map();
    for (let i = 0; i < 100; i++) m.set("key" + i, i);
    for (let i = 0; i < 100; i++) m.get("key" + i);
});

benchmark("Set add/has 100", () => {
    const s = new Set();
    for (let i = 0; i < 100; i++) s.add(i);
    for (let i = 0; i < 100; i++) s.has(i);
});

// ── Promise ─────────────────────────────────────────────────────────
console.log("\n=== Promise ===");

benchmark("Promise.resolve", () => {
    Promise.resolve(42);
});

benchmark("Promise.all (5)", () => {
    Promise.all([
        Promise.resolve(1),
        Promise.resolve(2),
        Promise.resolve(3),
        Promise.resolve(4),
        Promise.resolve(5),
    ]);
});

// ── Summary ─────────────────────────────────────────────────────────
console.log("\n=== Summary ===");
console.log(`${results.length} benchmarks completed`);
let totalOps = 0;
for (const r of results) totalOps += r.opsPerSec;
console.log(`Total throughput: ${totalOps.toLocaleString()} ops/sec`);
