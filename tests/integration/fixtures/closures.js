// Closures and scoping (inspired by Bun/Node scoping tests)

// Basic closure
function makeCounter() {
    let count = 0;
    return {
        inc: () => ++count,
        get: () => count,
    };
}
const c = makeCounter();
c.inc();
c.inc();
c.inc();
console.log(c.get());

// IIFE
const result = (() => {
    const x = 10;
    const y = 20;
    return x + y;
})();
console.log(result);

// let/const block scoping
{
    let x = "inner";
    console.log(x);
}

// Closure over loop variable
const funcs = [];
for (let i = 0; i < 3; i++) {
    funcs.push(() => i);
}
console.log(funcs[0](), funcs[1](), funcs[2]());

// Generator
function* range(start, end) {
    for (let i = start; i < end; i++) yield i;
}
console.log([...range(1, 4)].join(","));

// Destructuring
const { a, b, ...rest } = { a: 1, b: 2, c: 3, d: 4 };
console.log(a, b, JSON.stringify(rest));

// Template literals
const name = "world";
console.log(`hello ${name}`);

// Symbol
const sym = Symbol("test");
console.log(typeof sym);
console.log(sym.toString());
