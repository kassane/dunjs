// util module integration test
const util = require('util');

// util.format
console.log(util.format('%s world', 'hello'));
console.log(util.format('%d + %d = %d', 1, 2, 3));
console.log(util.format('%j', {a: 1}));
console.log(util.format('%%'));

// util.inspect
console.log(typeof util.inspect({a: 1}));

// util.types
console.log('isDate:', util.types.isDate(new Date()));
console.log('isRegExp:', util.types.isRegExp(/test/));
console.log('isNativeError:', util.types.isNativeError(new Error()));
console.log('isPromise:', util.types.isPromise(Promise.resolve()));
console.log('isMap:', util.types.isMap(new Map()));
console.log('isSet:', util.types.isSet(new Set()));

// util.inherits
function Base() { this.x = 1; }
Base.prototype.hello = function() { return 'hello'; };
function Child() { Base.call(this); }
util.inherits(Child, Base);
const c = new Child();
console.log('inherits:', c.hello(), c.x);

// util.promisify
function asyncOp(val, cb) { cb(null, val * 2); }
const promisified = util.promisify(asyncOp);
promisified(21).then(r => console.log('promisify:', r));

// util.isDeepStrictEqual
console.log('deepEqual:', util.isDeepStrictEqual({a: [1, 2]}, {a: [1, 2]}));
console.log('deepNotEqual:', util.isDeepStrictEqual({a: 1}, {a: 2}));
