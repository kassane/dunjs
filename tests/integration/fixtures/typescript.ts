// Basic type annotations
const x: number = 42;
const s: string = "hello";
console.log(x, s);

// Interface (stripped entirely)
interface Point {
  x: number;
  y: number;
}

// Type alias (stripped entirely)
type ID = string | number;

// Function with typed params and return type
function add(a: number, b: number): number {
  return a + b;
}
console.log(add(1, 2));

// Arrow function with types
const double = (n: number): number => n * 2;
console.log(double(21));

// as assertion
const val = (100 as number);
console.log(val);

// Optional parameter
function greet(name: string, greeting?: string): string {
  return (greeting || "Hello") + ", " + name + "!";
}
console.log(greet("world"));
console.log(greet("TypeScript", "Hi"));

// Generics (type params on function)
function identity(x) {
  return x;
}
console.log(identity("generic"));
