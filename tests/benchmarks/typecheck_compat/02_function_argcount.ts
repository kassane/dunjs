// Type error: too many arguments to a typed function.
function add(a: number, b: number): number { return a + b; }
const r = (add as any)(1, 2, 3);  // strict mode caught only by tsc
const r2 = add(1, 2, 3);  // catches at type-check time
console.log(r, r2);
