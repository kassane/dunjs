// Destructuring with type annotations, parameter properties,
// `this:` param, return-type arrow shapes.
interface User { id: number; name: string; meta?: { tag: string } }

function greet({ name, meta = { tag: "default" } }: User): string {
  return `${name}/${meta.tag}`;
}

// Array destructure with type
function firstPair([a, b]: [number, number]): number { return a + b; }

// `this:` parameter
function describe(this: { kind: string }, suffix: string): string {
  return `${this.kind}-${suffix}`;
}

// Function returning object-type-literal shape
function makeFn(): (x: number) => { v: number } {
  return (x) => ({ v: x * 2 });
}

// Constructor parameter properties + super injection
class Animal {
  constructor(public name: string, protected sound: string) {}
}
class Dog extends Animal {
  constructor(name: string, public breed: string) {
    super(name, "woof");
  }
  introduce(): string {
    return `${this.name} (${this.breed}): ${this.sound}`;
  }
}

console.log(greet({ id: 1, name: "Alice" }));
console.log(greet({ id: 2, name: "Bob", meta: { tag: "admin" } }));
console.log(firstPair([3, 4]));
console.log(describe.call({ kind: "rocket" }, "X"));
console.log(makeFn()(21).v);
console.log(new Dog("Rex", "Lab").introduce());
