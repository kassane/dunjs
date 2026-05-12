// Cross-runtime feature test
let pass = 0, fail = 0;
function test(name, fn) {
  try { if (fn()) { pass++; } else { fail++; console.log("FAIL: " + name); } }
  catch(e) { fail++; console.log("FAIL: " + name + " (" + e.message + ")"); }
}

// Core JS
test("typeof", () => typeof undefined === "undefined");
test("arrow functions", () => ((x) => x+1)(1) === 2);
test("template literals", () => `hello ${"world"}` === "hello world");
test("destructuring", () => { const {a,b} = {a:1,b:2}; return a+b === 3; });
test("spread", () => [...[1,2,3]].length === 3);
test("Promise", () => typeof Promise === "function");
test("async/await", () => typeof (async()=>{}) === "function");
test("Map/Set", () => new Map([[1,2]]).get(1) === 2 && new Set([1,2,3]).size === 3);
test("Symbol", () => typeof Symbol("test") === "symbol");
test("class", () => { class A { x() { return 1; } } return new A().x() === 1; });
test("generators", () => { function* g() { yield 1; yield 2; } return [...g()].length === 2; });
test("for..of", () => { let s=0; for(let x of [1,2,3]) s+=x; return s===6; });
test("WeakMap/WeakRef", () => typeof WeakMap === "function" && typeof WeakRef === "function");
test("Optional chaining", () => ({a:{b:1}})?.a?.b === 1);
test("Nullish coalescing", () => (null ?? "ok") === "ok");
test("Array.from", () => Array.from("abc").length === 3);
test("Object.entries", () => Object.entries({a:1}).length === 1);
test("String.padStart", () => "1".padStart(3,"0") === "001");
test("Array.flat", () => [1,[2,[3]]].flat(Infinity).length === 3);
test("Promise.allSettled", () => typeof Promise.allSettled === "function");
test("globalThis", () => typeof globalThis === "object");
test("structuredClone", () => typeof structuredClone === "function");
test("atob/btoa", () => atob(btoa("hello")) === "hello");
test("JSON.parse", () => JSON.parse('{"a":1}').a === 1);
test("RegExp named groups", () => /(?<year>\d+)/.exec("2024").groups.year === "2024");
test("Error.cause", () => new Error("a", {cause: "b"}).cause === "b");
test("Array.findLast", () => typeof [].findLast === "function");
test("Object.hasOwn", () => Object.hasOwn({a:1}, "a") === true);
test("Array.at", () => [1,2,3].at(-1) === 3);
test("String.replaceAll", () => "aaa".replaceAll("a","b") === "bbb");
test("TextEncoder", () => new TextEncoder().encoding === "utf-8");
test("TextDecoder", () => new TextDecoder().encoding === "utf-8");
test("console.log", () => { console.log; return typeof console.log === "function"; });
test("setTimeout", () => typeof setTimeout === "function");
test("queueMicrotask", () => typeof queueMicrotask === "function");
test("process.platform", () => typeof process !== "undefined" && typeof process.platform === "string");
test("process.cwd", () => typeof process !== "undefined" && typeof process.cwd === "function");
test("process.exit", () => typeof process !== "undefined" && typeof process.exit === "function");
test("process.on", () => typeof process !== "undefined" && typeof process.on === "function");

console.log("\nTotal: " + pass + "/" + (pass+fail) + " passed");
