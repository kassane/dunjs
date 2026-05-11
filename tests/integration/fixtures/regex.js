// RegExp tests (inspired by Node test-regexp.js)

// Basic match
console.log("hello world".match(/world/) !== null);

// Groups
const m = "2024-01-15".match(/(\d{4})-(\d{2})-(\d{2})/);
console.log(m[1], m[2], m[3]);

// Named groups (ES2018)
const nm = "2024-01-15".match(/(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/);
console.log(nm.groups.year, nm.groups.month, nm.groups.day);

// Replace
console.log("foo bar baz".replace(/bar/, "qux"));
console.log("aaa".replace(/a/g, "b"));

// Split
console.log("a,b,,c".split(",").join("|"));

// Test
console.log(/^\d+$/.test("123"));
console.log(/^\d+$/.test("abc"));

// Flags
const re = /abc/gi;
console.log(re.flags);

// matchAll (ES2020)
const text = "test1 test2 test3";
const matches = [...text.matchAll(/test(\d)/g)];
console.log(matches.length);
console.log(matches.map(m => m[1]).join(","));
