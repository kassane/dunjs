// Test Node.js-style console.log object formatting
// Verifies that console.log produces Node-compatible output for all types

// Objects
console.log({a: 1, b: "hello"});
// Arrays
console.log([1, 2, 3]);
// Nested
console.log({x: [1, {y: 2}]});
// Empty
console.log([]);
console.log({});
// Date
console.log(new Date(0));
// RegExp
console.log(/test/gi);
// Map
console.log(new Map([["key", "val"]]));
// Set
console.log(new Set([1, 2, 3]));
// TypedArray
console.log(new Uint8Array([10, 20, 30]));
// Function
console.log(function myFunc() {});
// Depth limiting
console.log({a: {b: {c: {d: 1}}}});
// Circular
var c = {}; c.self = c; console.log(c);
// Mixed args
console.log("result:", {ok: true}, [1]);
// Null/undefined as objects
console.log(null);
console.log(undefined);
// Symbol
console.log(Symbol("test"));
// Empty typed array
console.log(new Uint8Array(0));
// Empty Map/Set
console.log(new Map());
console.log(new Set());
// util.inspect
var util = require("util");
console.log(util.inspect({key: "value"}));
