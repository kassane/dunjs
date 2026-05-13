// Iterator and collection tests (inspired by Deno iterable_test.ts)

// Map
const map = new Map();
map.set("a", 1);
map.set("b", 2);
map.set("c", 3);
console.log(map.size);
console.log(map.get("b"));
console.log(map.has("d"));

// Set
const set = new Set([1, 2, 3, 2, 1]);
console.log(set.size);
console.log([...set].join(","));

// WeakRef
let obj = { value: 42 };
const ref = new WeakRef(obj);
console.log(ref.deref().value);

// for...of
const arr = [10, 20, 30];
const collected = [];
for (const v of arr) collected.push(v * 2);
console.log(collected.join(","));

// Array.from
console.log(Array.from("abc").join(","));
console.log(Array.from({ length: 3 }, (_, i) => i + 1).join(","));

// Object.entries / Object.fromEntries
const entries = Object.entries({ x: 1, y: 2 });
console.log(entries.map(e => e.join(":")).join(","));
const rebuilt = Object.fromEntries(entries);
console.log(JSON.stringify(rebuilt));

// Array methods chain
const nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const result = nums
    .filter(n => n % 2 === 0)
    .map(n => n * n)
    .reduce((sum, n) => sum + n, 0);
console.log(result);
