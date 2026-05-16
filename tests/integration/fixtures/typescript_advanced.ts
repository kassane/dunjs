// Tests for the enhanced TS stripper: enums, parameter properties,
// type-only exports, non-null assertions, nested arrow function params.

var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

// --- enums ---
// (Enums are erased + emitted as `const X = Object.freeze({...});` in
// a prologue. They run before the body, so we can reference them here.)
enum Color { Red, Green, Blue }
check('enum forward Red', Color.Red === 0);
check('enum forward Green', Color.Green === 1);
check('enum forward Blue', Color.Blue === 2);
check('enum reverse 0', Color[0] === 'Red');
check('enum reverse 2', Color[2] === 'Blue');

enum Status { OK = "ok", FAIL = "fail" }
check('string enum OK', Status.OK === 'ok');
check('string enum FAIL', Status.FAIL === 'fail');

enum Priority { Low = 1, Medium, High = 10 }
check('explicit numeric', Priority.Low === 1 && Priority.High === 10);
check('auto-increment', Priority.Medium === 2);
check('reverse high', Priority[10] === 'High');

// --- parameter properties ---
class Point {
  constructor(public x: number, public y: number, readonly z: number = 0) {}
  sum(): number { return this.x + this.y + this.z; }
}
const p = new Point(1, 2, 3);
check('param prop x', p.x === 1);
check('param prop y', p.y === 2);
check('param prop readonly z', p.z === 3);
check('method uses params', p.sum() === 6);

class Mixed {
  constructor(public name: string, private id: number, age: number) {
    // age is NOT a param prop — should NOT auto-init from constructor
    (this as any).computedAge = age * 2;
  }
}
const m = new Mixed("alice", 7, 30);
check('mixed: public field', m.name === 'alice');
check('mixed: private field', (m as any).id === 7);
check('mixed: non-prop assigned in body', (m as any).computedAge === 60);

// --- non-null assertion postfix ---
const obj = { val: 42 } as { val?: number };
check('non-null assertion', obj.val!.toString() === '42');

// --- nested arrow function params ---
function nestedTest() {
  const fn = (x: number, y: string = 'default'): string => {
    return y + ':' + x;
  };
  return fn(5);
}
check('nested arrow with default', nestedTest() === 'default:5');

console.log('typescript_advanced:', passed + '/' + total, 'checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
