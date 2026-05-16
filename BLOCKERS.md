# Production-readiness status

What still keeps DunJS from being a drop-in replacement for an
arbitrary Node / Deno / Bun project.

**Production blockers: none.** Every gap that would prevent shipping a
real workload has a working fix or a documented opt-out. The items
below split into quality-of-life work and items that are intentionally
not addressed because matching Bun/Deno/Node behavior is the
benchmark.

## Closed

- **N-API** — 91 functions plus real `napi_wrap` /
  `napi_create_external` with a side-table for the `(data, hint,
  finalize_cb)` triple. `napiFireFinalizers` runs at process exit so
  addons that rely on destructor side effects (sharp, etc.) clean up.
  Caught a use-after-free in `napiDispatch` along the way: the
  trampoline was freeing `napiArgs[i]` and then returning `rv.handle`
  even when `rv` aliased one of the args. Fixed with `dupValue` before
  the free. ASan-clean. 5/5 + 3/3 on `napi_wrap.js` / `napi_async.js`.

- **WebAssembly + WASI** — Native `WebAssembly` on JSC/V8 with a
  microtask polyfill for `compile` / `instantiate` /
  `compileStreaming` / `instantiateStreaming`. `dun:wasi` covers
  preview1; `dun run hello.wasm` bootstraps `_start`. QuickJS prints a
  clear "use --backend=jsc/v8" error.

- **V8 regex `\p{Name}`** — Two-layer workaround: source rewriter
  before V8 parses + runtime polyfill for engine-thrown property
  escapes. Pre-baked Unicode tables cover the common General_Category
  groups + identifier props. Express 5's `/[$_\p{ID_Start}]$/u` loads
  fine.

- **TS strip — real-world coverage**:
  - Class fields, derived-class constructor parameter properties
    (injection after `super()`), multi-line parameter properties.
  - Type aliases with embedded `;` and multi-line `|` / `&`.
  - Intra-enum member references (IIFE builder pattern).
  - `function NAME<T>` declaration generics.
  - Generic call sites `tryParse<number>(...)`.
  - `satisfies` operator.
  - Inline `type` modifier in `import { a, type B, c }` /
    `export { a, type B }`.
  - `import X = require('m')` → `const X = require('m')`.
  - `import X = Y.Z` TS namespace aliases are erased.
  - `const enum` falls through to the rewriter.
  - Nested `export namespace Inner` attaches to parent `__ns`.

- **Vendor isolation** — brotli and lsquic now vendored. No more
  system `libbrotli-dev` dep. lsquic ImportC bridge cross-checks the
  manual extern(C) bindings.

- **CLI sharp edges** — `dun test -ignored-any-flag` rejects unknown
  flags. `--max-memory=64` = 64 MiB. `--eval-file` accepts both
  `=` and space forms. `dun bundle` is the new CLI for `Bun.build`.

- **dun fmt** — Now ships with `--quotes=single|double` quote
  normalization (skips strings containing the target quote) and
  `--check` (exits non-zero when any file isn't already formatted,
  for CI gating). Combined with the existing token-level operator
  spacing and brace-depth indenter, this covers the formatter use
  cases most projects care about. Full Prettier-grade reflow still
  needs a real JS AST parser — out of scope for now.

- **DevTools / Inspector** — ~50 CDP methods including
  `Debugger.evaluateOnCallFrame`, the full `step{Over,Into,Out}` /
  `resume` / `pause` family, `Runtime.globalLexicalScopeNames`,
  `Network.setUserAgentOverride`, `Page.reload`. Read-only Chrome
  DevTools inspection works end-to-end. Live breakpoints + variable
  inspection at a paused frame need real engine debug hooks (per
  backend) — out of scope for the same reason as full Prettier.

## Documented gaps (parity with Bun/Deno/Node strip modes)

These are not bugs; they're the line where scanner-based type
erasure stops and a real TS compiler begins. All three competitors
hit the same wall.

- **Decorator runtime semantics** — `@expr` is erased rather than
  dispatched. Bun and Deno's strip modes do the same.

- **`using` / `await using` declarations** — Engine-support gated, not
  a strip-mode issue. QJS, JSC, and V8 versions we link don't all
  expose Symbol.dispose yet.

- **`accessor` keyword on class fields** — Tied to stage-3 decorator
  semantics; mismatched runtime expectations make this safer to leave
  alone for now.

## Won't-fix

- **Native `.node` addons that bypass N-API** — Things that
  `dlopen('node')` and call into V8 / libuv internals can't be
  supported by any non-Node runtime. Addons that stay within the
  N-API surface work.
