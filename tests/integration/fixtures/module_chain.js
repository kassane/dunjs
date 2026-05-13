// Real-world: CJS require chain — entry script requires a local utility
const math = require('./lib/math_utils');

console.log(math.factorial(5));
console.log(math.fibonacci(10));
console.log(typeof math.factorial);

// Require the same module again — must hit cache, not re-execute
const math2 = require('./lib/math_utils');
console.log(math === math2);
