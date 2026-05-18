// Class fields + private fields + accessor + static initializer order
class Counter {
  #value = 0;
  static instances = 0;
  readonly id: number;
  protected name: string;

  constructor(name: string) {
    this.id = ++Counter.instances;
    this.name = name;
  }

  accessor count = 0;

  inc(): number { return ++this.#value; }
  get value(): number { return this.#value; }
}

const c1 = new Counter("alpha");
const c2 = new Counter("beta");
c1.inc(); c1.inc(); c1.inc();
c2.inc();
c1.count = 42;

console.log(`${c1.id} ${(c1 as any).name} ${c1.value} ${c1.count}`);
console.log(`${c2.id} ${(c2 as any).name} ${c2.value}`);
console.log(`instances=${Counter.instances}`);
