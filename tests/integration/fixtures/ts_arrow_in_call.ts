// Regression: arrow function with return-type annotation inside a
// method call expression. The DunJS scanner stripper used to gate
// the `): Type =>` strip on `parenDepth == 0`, which broke real-
// world code like `arr.map((x): R => ...)` (surfaced by yt-dlp/ejs).
// Fixed in v1.1.26 follow-up.

type R = { ok: boolean; v: number };
const arr = [1, 2, 3];

// 1. Arrow with explicit return type inside .map
const mapped = arr.map((n): R => ({ ok: n > 0, v: n * 2 }));
console.log("map sum:", mapped.reduce((a, b) => a + b.v, 0));

// 2. Arrow with both param and return type, inside .filter
const filtered = arr.filter((n: number): boolean => n > 1);
console.log("filter len:", filtered.length);

// 3. Nested method calls, arrow with return type at depth 2
const reduced = arr
  .map((x): R => ({ ok: true, v: x }))
  .reduce((acc, r): number => acc + r.v, 0);
console.log("reduced:", reduced);

// 4. Arrow with return type as argument to a regular function call
function applyFn<T, U>(fn: (x: T) => U, x: T): U { return fn(x); }
const result = applyFn((x: number): string => "x=" + x, 42);
console.log("applyFn:", result);

// 5. Arrow with return type inside JSON.stringify replacer
const obj = { a: 1, b: 2 };
const json = JSON.stringify(obj, (key, value): unknown => {
  return typeof value === "number" ? value * 10 : value;
});
console.log("json:", json);
