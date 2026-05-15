// Test process.env proxy behavior

// 1. env is object
console.log('1: env is object: ' + (typeof process.env === 'object'));

// 2. Set new env var
process.env.MY_TEST_VAR = 'hello123';
console.log('2: set works: ' + (process.env.MY_TEST_VAR === 'hello123'));

// 3. Delete env var
delete process.env.MY_TEST_VAR;
console.log('3: delete works: ' + (process.env.MY_TEST_VAR === undefined));

// 4. 'in' operator
process.env.CHECK_VAR = 'yes';
console.log('4: in operator: ' + ('CHECK_VAR' in process.env));

// 5. Object.keys includes set vars
var keys = Object.keys(process.env);
console.log('5: keys includes CHECK_VAR: ' + keys.includes('CHECK_VAR'));

// 6. process.env.NODE_ENV pattern (common in npm)
process.env.NODE_ENV = 'production';
console.log('6: NODE_ENV set: ' + (process.env.NODE_ENV === 'production'));

// 7. Clean up
delete process.env.CHECK_VAR;
delete process.env.NODE_ENV;
console.log('7: cleanup done: ' + (process.env.NODE_ENV === undefined));

// 8. Set multiple vars
process.env.A = '1';
process.env.B = '2';
process.env.C = '3';
var envKeys = Object.keys(process.env).filter(function(k) { return k === 'A' || k === 'B' || k === 'C'; });
console.log('8: multiple vars: ' + (envKeys.length === 3));
delete process.env.A;
delete process.env.B;
delete process.env.C;
