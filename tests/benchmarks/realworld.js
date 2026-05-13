// Real-world performance benchmarks
// Tests practical workloads that matter for server/CLI applications

const results = {};

function bench(name, fn, iterations) {
  // Warmup
  for (let i = 0; i < Math.min(iterations, 100); i++) fn();

  const start = Date.now();
  for (let i = 0; i < iterations; i++) fn();
  const elapsed = Date.now() - start;
  results[name] = { elapsed, iterations, opsPerSec: Math.round(iterations / (elapsed / 1000)) };
  console.log(`${name}: ${elapsed}ms (${results[name].opsPerSec.toLocaleString()} ops/sec)`);
}

// 1. JSON serialization/deserialization (API server workload)
const sampleData = {
  users: Array.from({ length: 100 }, (_, i) => ({
    id: i,
    name: `User ${i}`,
    email: `user${i}@example.com`,
    age: 20 + (i % 50),
    active: i % 3 !== 0,
    tags: ["tag1", "tag2", "tag3"],
    address: { street: `${i} Main St`, city: "Testville", zip: `${10000 + i}` },
    scores: [Math.random() * 100, Math.random() * 100, Math.random() * 100]
  }))
};
const jsonStr = JSON.stringify(sampleData);
bench("json-serialize-100users", () => JSON.stringify(sampleData), 5000);
bench("json-parse-100users", () => JSON.parse(jsonStr), 5000);

// 2. URL parsing (web framework routing)
bench("url-parse", () => {
  new URL("https://api.example.com:8443/v2/users/123/posts?page=5&limit=20&sort=date#comments");
}, 50000);

// 3. String processing (template engine / log parsing)
const logLine = '2024-01-15T10:30:45.123Z [INFO] request_id=abc-123-def method=GET path=/api/v2/users status=200 duration=45ms bytes=1234';
bench("regex-log-parse", () => {
  const ts = logLine.match(/^(\S+)/)[1];
  const level = logLine.match(/\[(\w+)\]/)[1];
  const fields = {};
  for (const m of logLine.matchAll(/(\w+)=(\S+)/g)) {
    fields[m[1]] = m[2];
  }
  return { ts, level, fields };
}, 50000);

// 4. Array manipulation (data processing pipeline)
bench("array-pipeline-1k", () => {
  const data = Array.from({ length: 1000 }, (_, i) => ({
    value: Math.sin(i) * 100,
    category: ["A", "B", "C"][i % 3],
    active: i % 5 !== 0
  }));
  return data
    .filter(d => d.active)
    .map(d => ({ ...d, normalized: d.value / 100 }))
    .reduce((acc, d) => {
      acc[d.category] = (acc[d.category] || 0) + d.normalized;
      return acc;
    }, {});
}, 2000);

// 5. Map/Set operations (cache/lookup workload)
bench("map-ops-10k", () => {
  const m = new Map();
  for (let i = 0; i < 10000; i++) m.set(`key-${i}`, { id: i, data: `value-${i}` });
  let found = 0;
  for (let i = 0; i < 10000; i += 2) if (m.has(`key-${i}`)) found++;
  for (let i = 0; i < 10000; i += 3) m.delete(`key-${i}`);
  return found;
}, 200);

// 6. Closure/callback chain (middleware pipeline pattern)
bench("callback-chain-100", () => {
  let val = 0;
  const fns = [];
  for (let i = 0; i < 100; i++) {
    fns.push((v) => v + 1);
  }
  for (const fn of fns) val = fn(val);
  return val;
}, 50000);

// 7. Object creation/property access (ORM/model pattern)
bench("object-create-props", () => {
  const objects = [];
  for (let i = 0; i < 500; i++) {
    const obj = Object.create(null);
    obj.id = i;
    obj.name = `item-${i}`;
    obj.value = Math.random();
    obj.tags = [i % 10, i % 20];
    obj.nested = { a: 1, b: { c: 2 } };
    objects.push(obj);
  }
  let sum = 0;
  for (const obj of objects) sum += obj.value + obj.nested.b.c;
  return sum;
}, 5000);

// 8. TextEncoder/TextDecoder (binary protocol handling)
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const testStr = "Hello, World! 🌍 This is a UTF-8 encoding benchmark with some unicode: café résumé naïve";
bench("text-encode-decode", () => {
  const encoded = encoder.encode(testStr);
  const decoded = decoder.decode(encoded);
  return decoded;
}, 50000);

// 9. Error creation (error handling hot path)
bench("error-create-stack", () => {
  try {
    throw new Error("test error");
  } catch (e) {
    return e.stack;
  }
}, 10000);

// 10. Deep object clone via structuredClone
const deepObj = {
  a: [1, 2, { b: [3, 4, { c: "hello" }] }],
  d: { e: { f: { g: 42 } } },
  arr: Array.from({ length: 50 }, (_, i) => ({ id: i, name: `item${i}` }))
};
bench("structured-clone", () => structuredClone(deepObj), 5000);

// 11. Base64 encode/decode (data URI, auth tokens)
const b64Input = "The quick brown fox jumps over the lazy dog. 0123456789 !@#$%^&*()";
bench("base64-roundtrip", () => {
  const encoded = btoa(b64Input);
  const decoded = atob(encoded);
  return decoded;
}, 50000);

// 12. String concatenation (template rendering)
bench("string-concat-build", () => {
  let html = "<html><body><ul>";
  for (let i = 0; i < 200; i++) {
    html += `<li class="item-${i}" data-id="${i}"><span>${"Item " + i}</span></li>`;
  }
  html += "</ul></body></html>";
  return html.length;
}, 2000);

// 13. Sorting (data grid / table display)
bench("sort-10k-objects", () => {
  const arr = Array.from({ length: 10000 }, (_, i) => ({
    name: `user-${(i * 7919) % 10000}`,
    score: Math.sin(i) * 1000,
    date: i * 86400
  }));
  arr.sort((a, b) => a.score - b.score || a.name.localeCompare(b.name));
  return arr[0];
}, 100);

// 14. RegExp compilation + matching (input validation)
bench("regex-validate-emails", () => {
  const re = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
  const emails = [
    "user@example.com", "bad@", "test.user+tag@domain.co.uk",
    "invalid", "a@b.c", "user@sub.domain.example.com",
    "user@123.456.789.0", "name@domain"
  ];
  return emails.filter(e => re.test(e));
}, 50000);

// 15. WeakRef / FinalizationRegistry (memory-sensitive caching)
bench("weakref-cache-pattern", () => {
  const cache = new Map();
  for (let i = 0; i < 100; i++) {
    const obj = { id: i, data: `cached-${i}` };
    cache.set(i, new WeakRef(obj));
  }
  let alive = 0;
  for (let i = 0; i < 100; i++) {
    const ref = cache.get(i);
    if (ref && ref.deref()) alive++;
  }
  return alive;
}, 10000);

// Summary
console.log("\n--- Summary ---");
let total = 0;
for (const [name, r] of Object.entries(results)) {
  total += r.elapsed;
}
console.log(`Total wall time: ${total}ms`);
console.log(`Benchmarks run: ${Object.keys(results).length}`);
