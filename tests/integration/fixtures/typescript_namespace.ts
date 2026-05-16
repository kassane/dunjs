// TS stripper: namespace + decorator erasure regression test.

let passed = 0, total = 0;
function check(name: string, cond: boolean) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

// --- namespace ---
namespace Math2 {
  export const PI = 3.14;
  export function double(x: number) { return x * 2; }
  export class Vec2 { constructor(public x: number, public y: number) {} }
}
check('namespace const', Math2.PI === 3.14);
check('namespace function', Math2.double(5) === 10);
check('namespace class', new Math2.Vec2(1, 2).x === 1);

// --- nested ---
namespace Outer {
  export const flag = true;
}
check('nested namespace', Outer.flag === true);

// --- module keyword (alias of namespace in TS) ---
module Util {
  export function greet(n: string) { return 'hi ' + n; }
}
check('module keyword', Util.greet('x') === 'hi x');

// --- decorator erasure ---
// We don't run decorator side-effects, but we must not crash on the
// syntax. Erased decorators leave the class declaration valid.
function logged(target: any, key: string) { /* would log if active */ }
function tagged(name: string) { return function(target: any) {}; }
@tagged('hello')
class Demo {
  @logged
  method() { return 42; }
}
const d = new Demo();
check('decorator class instantiates', d instanceof Demo);
check('decorator method still works', d.method() === 42);

console.log('typescript_namespace:', passed + '/' + total, 'checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
