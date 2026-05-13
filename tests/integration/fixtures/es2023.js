// Test modern JS features supported by all backends (QuickJS, JSC, V8 10.x)

// Array.prototype.findLast (ES2023)
const arr = [1, 2, 3, 4, 5];
console.log(arr.findLast(x => x < 4)); // 3

// Array.prototype.findLastIndex (ES2023)
console.log(arr.findLastIndex(x => x < 4)); // 2

// Optional chaining (ES2020)
const obj = { a: { b: { c: 42 } } };
console.log(obj.a.b.c);       // 42
console.log(obj.x?.y?.z);     // undefined

// Nullish coalescing (ES2020)
console.log(null ?? "default");    // "default"
console.log(undefined ?? "fallback"); // "fallback"
console.log(0 ?? "nope");         // 0

// Array.prototype.at (ES2022)
console.log(arr.at(-1)); // 5
console.log(arr.at(0));  // 1

// Object.hasOwn (ES2022)
const proto = { inherited: true };
const child = Object.create(proto);
child.own = true;
console.log(Object.hasOwn(child, "own"));       // true
console.log(Object.hasOwn(child, "inherited")); // false

// String.prototype.replaceAll (ES2021)
console.log("aabbcc".replaceAll("b", "x")); // "aaxxcc"

// Promise.allSettled (ES2020)
Promise.allSettled([
    Promise.resolve("ok"),
    Promise.reject("fail")
]).then(results => {
    console.log(results[0].status); // "fulfilled"
    console.log(results[1].status); // "rejected"
});
