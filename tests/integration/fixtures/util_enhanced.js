// Test enhanced util module
var util = require('util');

// 1. util.types
console.log('1: types exists: ' + (typeof util.types === 'object'));
console.log('2: isPromise: ' + util.types.isPromise(Promise.resolve()));
console.log('3: isDate: ' + util.types.isDate(new Date()));
console.log('4: isRegExp: ' + util.types.isRegExp(/test/));
console.log('5: isMap: ' + util.types.isMap(new Map()));
console.log('6: isSet: ' + util.types.isSet(new Set()));
console.log('7: isWeakMap: ' + util.types.isWeakMap(new WeakMap()));
console.log('8: isWeakSet: ' + util.types.isWeakSet(new WeakSet()));
console.log('9: isTypedArray: ' + util.types.isTypedArray(new Uint8Array(1)));
console.log('10: isArrayBuffer: ' + util.types.isArrayBuffer(new ArrayBuffer(1)));
console.log('11: isDataView: ' + util.types.isDataView(new DataView(new ArrayBuffer(1))));
console.log('12: isNativeError: ' + util.types.isNativeError(new TypeError()));
console.log('13: isAsyncFunction: ' + util.types.isAsyncFunction(async function() {}));
console.log('14: isGeneratorFunction: ' + util.types.isGeneratorFunction(function*() {}));

// 2. util.debuglog
console.log('15: debuglog exists: ' + (typeof util.debuglog === 'function'));
var log = util.debuglog('test');
console.log('16: debuglog returns fn: ' + (typeof log === 'function'));

// 3. util._extend
var target = { a: 1 };
util._extend(target, { b: 2, c: 3 });
console.log('17: _extend works: ' + (target.b === 2 && target.c === 3));

// 4. util.format
console.log('18: format %s: ' + util.format('hello %s', 'world'));
console.log('19: format %d: ' + util.format('count: %d', 42));

// 5. util.inherits
function Base() { this.x = 1; }
Base.prototype.getX = function() { return this.x; };
function Child() { Base.call(this); this.y = 2; }
util.inherits(Child, Base);
var c = new Child();
console.log('20: inherits works: ' + (c.getX() === 1 && c.y === 2));

// 6. util.promisify
function asyncOp(val, cb) { cb(null, val * 2); }
var promisified = util.promisify(asyncOp);
promisified(5).then(function(r) { console.log('21: promisify result: ' + r); });

// 7. util.callbackify
async function asyncFn(x) { return x + 10; }
var cbFn = util.callbackify(asyncFn);
cbFn(5, function(err, result) { console.log('22: callbackify result: ' + result); });

// 8. util.toUSVString
console.log('23: toUSVString: ' + util.toUSVString('hello'));

// 9. util.deprecate
var deprecated = util.deprecate(function() { return 42; }, 'old func');
console.log('24: deprecate works: ' + (deprecated() === 42));

// 10. Additional type checks
console.log('25: isUint8Array: ' + util.types.isUint8Array(new Uint8Array(1)));
console.log('26: isFloat64Array: ' + util.types.isFloat64Array(new Float64Array(1)));
console.log('27: not isDate string: ' + util.types.isDate('2024'));
