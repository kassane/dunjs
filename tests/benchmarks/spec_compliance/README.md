# Spec-compliance audit (ECMAScript + TypeScript)

Two fixtures plus a runner that tabulates spec-conformance per runtime.

```
ecmascript.js  — ES2015..ES2025 coverage, ~98 individual checks
typescript.ts  — erasable + permissive TS strip subset, ~35 checks
compare.sh     — run both on bun/node/deno/dun-{qjs,jsc,v8}
```

## ECMAScript (May 2026, release binaries)

Each cell shows `passed / total`. Failures are individual feature
checks, not whole-file errors.

| Spec    | Bun   | Node  | Deno  | DunJS QJS | DunJS JSC | DunJS V8 |
|---------|------:|------:|------:|----------:|----------:|---------:|
| total   | 98/98 | 98/98 | 98/98 | **98/98** | **98/98** | **98/98**|

All six runtimes are at 100%. The `RegExp /v` flag (ES2025
unicodeSets, "v" set-operation regex) is the long-standing gap on
QuickJS-NG and on the libv8 14.9 we link; `expandVSetOps` in
`dun.runtime.unicode_props` rewrites `[A--B]/v` and `[A&&B]/v` source
literals to `/u`-equivalent range classes before handing the source
to the engine. JSC handles `/v` natively. The rewriter no-ops when
neither the flag nor the set operators are present, so it's free on
the common path.

## TypeScript (May 2026)

| Category | Bun  | Node  | Deno  | DunJS QJS | DunJS JSC | DunJS V8 |
|----------|-----:|------:|------:|----------:|----------:|---------:|
| total    | 35/35| FAIL  | 35/35 | **35/35** | **35/35** | **35/35**|

Node's `--experimental-strip-types` (the canonical `--erasableSyntaxOnly`
subset) rejects:

- Constructor parameter properties (`constructor(public x: number)`)
- Enums (numeric and string)
- Namespaces

DunJS, Bun, and Deno accept the wider permissive strip — same shape
as Bun's transpiler.

## Running

```sh
# release builds
./dun-rel-qjs run --allow-all tests/benchmarks/spec_compliance/ecmascript.js
./dun-rel-qjs run --allow-all tests/benchmarks/spec_compliance/typescript.ts

# or the full cross-runtime grid
bash tests/benchmarks/spec_compliance/compare.sh
```

## When to update

- New ES proposal reaches Stage 4: add it to ecmascript.js, retest.
- TS release adds an erasable form: add to typescript.ts.
- New runtime to compare: extend `compare.sh`'s RUNTIMES list.

## Methodology notes

- Individual checks are wrapped in `try/eval` so a parser-level
  rejection on one feature doesn't kill the rest of the file.
  This way "QJS doesn't have `/v`" only costs us 1/98 instead of
  blowing up the whole audit.
- The TS file uses constructor parameter properties, enums, and
  namespaces — features outside `--erasableSyntaxOnly`. Five of
  the six runtimes accept them; Node is the strictest. This
  matches Node's documented policy.
- `Object.groupBy` / `Map.groupBy` were ES2024 stage-4 promotions;
  Node ≥21, Bun ≥1.0.20, Deno ≥1.41, DunJS via JSC/V8 are all
  current. QuickJS-NG ≥0.14 added them.
