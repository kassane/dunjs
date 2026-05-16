// Type error: missing case in a discriminated union exhaustive check.
type Shape =
  | { kind: "circle"; radius: number }
  | { kind: "rect"; w: number; h: number };

function area(s: Shape): number {
  switch (s.kind) {
    case "circle": return Math.PI * s.radius ** 2;
    // BUG: rect case missing -- tsc with --strict catches via exhaustiveness
  }
  return 0;  // unreachable per the contract, but JS doesn't know
}
console.log(area({ kind: "rect", w: 2, h: 3 }));
