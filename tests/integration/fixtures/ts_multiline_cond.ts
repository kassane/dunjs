// Regression: multi-line conditional type aliases where `?` and `:`
// lead the next line (`T extends X\n  ? A\n  : B`). DunJS's scanner
// stripper's findSemiOrEOL used to only continue past `\n` when:
//   * next line starts with `|` or `&`         (union/intersection)
//   * prev line ENDS in `?`, `:`, `=`, or `,`  (trailing operator)
// But the leading-operator style is the common TypeScript layout for
// distributive conditional types. Surfaced by yt-dlp/ejs's
// `src/types.ts` which uses `DeepPartial<T> = T extends ...\n  ? ...\n  : ...`.
// Fixed by also accepting `?` or `:` at the START of next line.

// 1. Simple leading-operator conditional
type Cond<T> = T extends string
  ? "str"
  : "other";

// 2. Distributive conditional with infer
type DeepPartial<T> = T extends (infer U)[]
  ? DeepPartial<U>[]
  : T extends object
    ? { [K in keyof T]?: DeepPartial<T[K]> }
    : T;

// 3. Trailing-operator (already worked; regression-protect)
type Long<T> = T extends string ?
  number :
  T extends number ?
  string :
  boolean;

// 4. Multi-line union (already worked; regression-protect)
type Union<T> =
  | { kind: "a"; value: T }
  | { kind: "b"; value: number };

const a: Cond<string> = "str";
const b: Cond<number> = "other";
const c: DeepPartial<{ a: number; b: string[] }> = { a: 1 };
const d: Long<string> = 1;
const e: Union<number> = { kind: "a", value: 42 };

console.log("cond:", a, b);
console.log("deep:", JSON.stringify(c));
console.log("long:", d);
console.log("union:", e.kind, e.value);
