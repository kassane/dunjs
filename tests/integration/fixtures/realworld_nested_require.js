// Real-world: Nested CJS require chains — validator -> string_utils, plus math_utils
var validator = require('./lib/validator');
var math = require('./lib/math_utils');
var str = validator.stringUtils;

// String utils
console.log(str.capitalize('hello world'));
console.log(str.slugify('Hello World! 123'));
console.log(str.truncate('The quick brown fox jumps', 15));
console.log(str.repeat('ab', 4));

// Validator
var u1 = validator.validateUsername('alice');
console.log('alice: ' + u1.valid + ', slug: ' + u1.normalized);

var u2 = validator.validateUsername('ab');
console.log('ab: ' + u2.valid + ', reason: ' + u2.reason);

var u3 = validator.validateUsername('Hello World');
console.log('Hello World: ' + u3.valid + ', reason: ' + u3.reason);

var e1 = validator.validateEmail('user@example.com');
console.log('email valid: ' + e1.valid);

var e2 = validator.validateEmail('broken');
console.log('email invalid: ' + e2.valid + ', reason: ' + e2.reason);

// Cross-module: math
console.log('fib(12): ' + math.fibonacci(12));
console.log('fact(7): ' + math.factorial(7));

// Module caching: require same module twice
var str2 = require('./lib/string_utils');
console.log('cached: ' + (str === str2));
