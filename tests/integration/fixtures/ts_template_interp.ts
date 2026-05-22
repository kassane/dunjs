// Regression: TS-only syntax inside `${...}` template-literal
// interpolations. The DunJS scanner stripper used to call
// `skipTemplateLit` which walks the whole template (including
// interpolations) verbatim — so `as T`, `satisfies T`, generic
// arrow params, etc. inside `${...}` reached the JS engine
// unstripped and tripped `SyntaxError: Unexpected identifier 'as'`.
// Surfaced by yt-dlp/ejs's `src/yt/solver/solvers.ts:173` which
// interpolates `generate({...} as ESTree.Node)` inside a template.
// Fixed by recursively stripping TS inside each interpolation.

type Node = { type: string; value?: number };

function gen(n: Node): string {
  return JSON.stringify(n);
}

// 1. `as Type` cast inside `${...}`
const a = `prefix:${gen({
  type: "x",
  value: 1,
} as Node)}:suffix`;
console.log("a:", a);

// 2. `satisfies Type` inside `${...}`
const b = `b=${{ type: "y", value: 2 } satisfies Node}`;
console.log("b:", b);

// 3. Arrow with explicit return type inside `${...}`
const nums = [1, 2, 3];
const c = `sum=${nums.map((n: number): number => n * 2).reduce((a, b) => a + b, 0)}`;
console.log("c:", c);

// 4. Nested template — TS inside an interpolation inside another
//    template — both levels need stripping.
const d = `outer-${`inner-${42 as number}-end`}-tail`;
console.log("d:", d);

// 5. Multiple interpolations — only the right one strips.
const e = `[${1 as number}][${"x" as string}][${true as boolean}]`;
console.log("e:", e);

// 6. Generic call inside `${...}` (angle-bracket type args)
function id<T>(x: T): T { return x; }
const f = `id=${id<number>(99)}`;
console.log("f:", f);
