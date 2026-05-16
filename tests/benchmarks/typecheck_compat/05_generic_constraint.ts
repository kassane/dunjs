// Type error: generic constraint violation.
function id<T extends string>(x: T): T { return x; }
const r = id(42);  // 42 doesn't extend string
console.log(r);
