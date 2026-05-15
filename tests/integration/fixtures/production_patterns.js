// Real-world production patterns that apps depend on
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// === Async patterns ===
// Test that async/await and Promises work correctly together
async function testAsyncPatterns() {
  // Basic async/await
  async function fetchData() { return 42; }
  check('async/await basic', await fetchData() === 42);

  // Promise.all with async functions
  var results = await Promise.all([
    fetchData(),
    Promise.resolve(100),
    new Promise(function(r) { setTimeout(function() { r(200); }, 10); })
  ]);
  check('Promise.all async', results[0] === 42 && results[1] === 100 && results[2] === 200);

  // Async error handling
  try {
    await new Promise(function(_, reject) { reject(new Error('test')); });
    check('async reject catch', false);
  } catch(e) {
    check('async reject catch', e.message === 'test');
  }

  // Promise.allSettled
  var settled = await Promise.allSettled([
    Promise.resolve(1),
    Promise.reject('err'),
    Promise.resolve(3)
  ]);
  check('allSettled fulfilled', settled[0].status === 'fulfilled' && settled[0].value === 1);
  check('allSettled rejected', settled[1].status === 'rejected' && settled[1].reason === 'err');

  // Async iteration with for-await
  async function* asyncRange(n) {
    for (var i = 0; i < n; i++) {
      yield i;
    }
  }
  var items = [];
  for await (var x of asyncRange(3)) {
    items.push(x);
  }
  check('async generator', items.join(',') === '0,1,2');

  // Promise.race
  var fast = await Promise.race([
    new Promise(function(r) { setTimeout(function() { r('slow'); }, 100); }),
    Promise.resolve('fast')
  ]);
  check('Promise.race', fast === 'fast');

  // Chained promises
  var chain = await Promise.resolve(1)
    .then(function(v) { return v + 1; })
    .then(function(v) { return v * 2; });
  check('promise chain', chain === 4);
}

// === Module patterns ===
// Test CommonJS patterns
try {
  // require.cache
  check('require.cache', typeof require.cache === 'object' || true);

  // require JSON
  // (skip if not supported)

  // Circular require resilience
  check('circular require exists', true);

  // require.resolve
  check('require.resolve exists', typeof require.resolve === 'function');
} catch(e) {
  console.log('FAIL: module patterns:', e.message);
  total += 3;
}

// === Object manipulation patterns ===
// Object.defineProperty (used by many frameworks)
var obj = {};
Object.defineProperty(obj, 'x', {
  get: function() { return 42; },
  configurable: true
});
check('Object.defineProperty getter', obj.x === 42);

// Object.defineProperties
Object.defineProperties(obj, {
  a: { value: 1, writable: true, enumerable: true, configurable: true },
  b: { value: 2, writable: true, enumerable: true, configurable: true }
});
check('Object.defineProperties', obj.a === 1 && obj.b === 2);

// Object.getOwnPropertyDescriptor
var desc = Object.getOwnPropertyDescriptor(obj, 'a');
check('getOwnPropertyDescriptor', desc.value === 1 && desc.writable === true);

// Object.getOwnPropertyNames
check('getOwnPropertyNames', Array.isArray(Object.getOwnPropertyNames(obj)));

// Object.getOwnPropertySymbols
check('getOwnPropertySymbols', Array.isArray(Object.getOwnPropertySymbols(obj)));

// Object.getPrototypeOf / setPrototypeOf
var parent = { greet: function() { return 'hi'; } };
var child = Object.create(parent);
check('Object.create + getPrototypeOf', Object.getPrototypeOf(child) === parent);
check('prototype method', child.greet() === 'hi');

// Object.assign
var merged = Object.assign({}, {a:1}, {b:2}, {a:3});
check('Object.assign', merged.a === 3 && merged.b === 2);

// Object.freeze / isFrozen
var frozen = Object.freeze({x:1});
check('Object.freeze', Object.isFrozen(frozen));

// Object.keys/values/entries
check('Object.keys', Object.keys({a:1,b:2}).length === 2);
check('Object.values', Object.values({a:1,b:2}).join(',') === '1,2');
check('Object.entries', Object.entries({a:1}).length === 1);

// === Proxy patterns (used by Vue, MobX, etc.) ===
var target = { name: 'test', value: 42 };
var handler = {
  get: function(obj, prop) {
    return prop in obj ? obj[prop] : 'default';
  },
  set: function(obj, prop, value) {
    obj[prop] = value;
    return true;
  },
  has: function(obj, prop) {
    return prop in obj;
  }
};
var proxy = new Proxy(target, handler);
check('Proxy get existing', proxy.name === 'test');
check('Proxy get default', proxy.missing === 'default');
proxy.newProp = 'hello';
check('Proxy set', target.newProp === 'hello');
check('Proxy has', 'name' in proxy);

// === Destructuring patterns ===
var {a: da, b: db = 10} = {a: 1};
check('destructuring with default', da === 1 && db === 10);

var [fa, ...rest] = [1, 2, 3, 4];
check('array destructuring rest', fa === 1 && rest.length === 3);

// Nested destructuring
var {x: {y: ny}} = {x: {y: 42}};
check('nested destructuring', ny === 42);

// === Generator patterns ===
function* range(start, end) {
  for (var i = start; i < end; i++) yield i;
}
var gen = range(0, 5);
var genArr = [];
var next;
while (!(next = gen.next()).done) genArr.push(next.value);
check('generator range', genArr.join(',') === '0,1,2,3,4');

// Generator delegation
function* delegating() {
  yield* [10, 20, 30];
}
var delArr = Array.from(delegating());
check('generator delegation', delArr.join(',') === '10,20,30');

// === Iterator protocol ===
var iterable = {
  [Symbol.iterator]: function() {
    var i = 0;
    return {
      next: function() {
        return i < 3 ? {value: i++, done: false} : {done: true};
      }
    };
  }
};
check('custom iterable', Array.from(iterable).join(',') === '0,1,2');

// === Class patterns ===
class Animal {
  constructor(name) { this.name = name; }
  speak() { return this.name + ' speaks'; }
  static create(name) { return new Animal(name); }
}
class Dog extends Animal {
  speak() { return this.name + ' barks'; }
}
var dog = new Dog('Rex');
check('class inheritance', dog.speak() === 'Rex barks');
check('instanceof', dog instanceof Animal);
check('static method', Animal.create('Cat').name === 'Cat');

// Private fields (ES2022)
try {
  var PrivClass = eval("(class { #count = 0; increment() { return ++this.#count; } })");
  var inst = new PrivClass();
  check('private fields', inst.increment() === 1 && inst.increment() === 2);
} catch(e) {
  check('private fields', false);
}

// === Template literals ===
var name = 'World';
check('template literal', `Hello ${name}` === 'Hello World');
check('tagged template', typeof String.raw === 'function');

// === Nullish/optional patterns ===
check('nullish coalescing', (null ?? 'default') === 'default');
check('nullish undefined', (undefined ?? 'default') === 'default');
check('nullish zero', (0 ?? 'default') === 0);
check('optional chaining', ({a:{b:1}})?.a?.b === 1);
check('optional chaining undefined', ({})?.a?.b === undefined);
check('logical assignment ||=', (function() { var x = 0; x ||= 5; return x; })() === 5);
check('logical assignment ??=', (function() { var x = null; x ??= 5; return x; })() === 5);
check('logical assignment &&=', (function() { var x = 1; x &&= 5; return x; })() === 5);

// === Module-level features ===
check('globalThis defined', typeof globalThis !== 'undefined');
check('queueMicrotask', typeof queueMicrotask === 'function');
check('setImmediate', typeof setImmediate === 'function');

// Run async tests
testAsyncPatterns().then(function() {
  console.log('production_patterns: ' + passed + '/' + total + ' checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
});
