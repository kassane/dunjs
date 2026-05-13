// assert module integration test
const assert = require('assert');

// Basic assertions
assert(true);
assert.ok(1);
console.log('ok: pass');

// Equality
assert.equal(1, 1);
assert.equal('hello', 'hello');
assert.notEqual(1, 2);
console.log('equal: pass');

// Strict equality
assert.strictEqual(1, 1);
assert.notStrictEqual(1, '1');
console.log('strict: pass');

// Deep equality
assert.deepEqual({a: 1, b: [2, 3]}, {a: 1, b: [2, 3]});
assert.deepStrictEqual([1, 2, 3], [1, 2, 3]);
console.log('deep: pass');

// Throws
assert.throws(function() { throw new Error('test'); });
assert.throws(function() { throw new TypeError('bad'); }, TypeError);
assert.doesNotThrow(function() { return 42; });
console.log('throws: pass');

// Match
assert.match('hello world', /world/);
console.log('match: pass');

// Fail
try {
    assert.fail('custom message');
} catch (e) {
    console.log('fail:', e.code === 'ERR_ASSERTION');
}

// AssertionError
try {
    assert.strictEqual(1, 2);
} catch (e) {
    console.log('error:', e.name === 'AssertionError');
    console.log('operator:', e.operator);
}

console.log('All assert tests passed');
