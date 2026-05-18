// Numeric + string enums, intra-enum refs, namespace runtime
enum Status { Pending, Active, Done }
enum Mode { ReadOnly = "ro", ReadWrite = "rw" }

// const enum (erased at compile time)
const enum Priority { Low = 1, Medium = 2, High = 3 }

// Enum with intra-member reference (IIFE builder pattern)
enum Tier {
  Bronze = 100,
  Silver = Bronze * 2,
  Gold   = Silver + 50,
}

namespace MyNs {
  export const VERSION = "1.2.3";
  export function greet(n: string) { return `Hi ${n}`; }
  export namespace Inner {
    export const NESTED = true;
  }
}

console.log(Status.Active, Status[1]);
console.log(Mode.ReadOnly, Mode.ReadWrite);
console.log(Priority.High);
console.log(Tier.Bronze, Tier.Silver, Tier.Gold);
console.log(MyNs.VERSION, MyNs.greet("X"));
console.log(MyNs.Inner.NESTED);
