// Generic call sites, generic arrows, conditional + mapped types
function identity<T>(x: T): T { return x; }
const wrap = <T,>(x: T): T[] => [x];

// Generic class with constraint
class Box<T extends { length: number }> {
  constructor(public item: T) {}
  size(): number { return this.item.length; }
}

// Conditional + mapped type at type level (erased)
type Nullable<T> = { [K in keyof T]: T[K] | null };
type IsString<T> = T extends string ? "yes" : "no";

const a = identity<number>(42);
const b = identity("hello");  // inferred
const c = wrap<boolean>(true);
const box = new Box<string>("hello world");
const box2 = new Box([1, 2, 3, 4]);

// Generic call with complex type args
const arr: ReadonlyArray<number> = [3, 1, 4, 1, 5];
const sorted = [...arr].sort((a, b) => a - b);

console.log(a, b, c.length, c[0]);
console.log(box.item, box.size());
console.log(box2.item.length);
console.log(sorted.join(","));
