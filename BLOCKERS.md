# Production-readiness status

What still keeps DunJS from being a drop-in replacement for an
arbitrary Node / Deno / Bun project.

**Production blockers: none.** Every gap that would prevent shipping a
real workload has a working fix.

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
  - Type annotations after destructure / tuple patterns
    (`function f({a}: T)`, `function f([a]: T)`).
  - Return types whose body is `{...}` (object type) or `(...) => T`
    (arrow function type).
  - Type aliases with embedded `;` and multi-line `|` / `&` /
    conditional / `extends` continuations.
  - Intra-enum member references (IIFE builder pattern).
  - `function NAME<T>` / `class NAME<T>` declaration generics.
  - Generic call sites and arrow expressions
    (`tryParse<number>(...)`, `<T>(value: T): T => ...`).
  - TS-only class-member modifiers (`public` / `private` /
    `protected` / `readonly` / `abstract` / `override`); `static`
    and `#`-private kept.
  - TS `this:` parameter (`function f(this: X, a)`) — erases the
    whole `this: TYPE,` span.
  - `satisfies` operator.
  - Inline `type` modifier in `import { a, type B, c }` /
    `export { a, type B }`.
  - `import X = require('m')` → `const X = require('m')`.
  - `import X = Y.Z` TS namespace aliases are erased.
  - `const enum` falls through to the rewriter.
  - Nested `export namespace Inner` attaches to parent `__ns`.
  - `accessor` keyword on class fields — erased (treated as a
    regular field, matching Bun's strip-mode behaviour).
  - **`using x = expr;` / `await using x = expr;`** — rewritten to
    `const x = expr;` plus a synthetic `try { ... } finally { x?.[Symbol.dispose]?.() }`
    wrap around the rest of the enclosing block. `await using` awaits
    `Symbol.asyncDispose`. LIFO order across sibling declarations;
    cleanup fires on every exit path (normal return, throw, propagation).
    Works on QuickJS / JSC / V8 identically; native V8 `using`
    support is not required.
  - **Decorators (`@DecoratorName(args)`)** — the decorator
    expression is erased so the underlying engine doesn't choke
    on `@`. Runtime semantics (calling the factory, applying its
    return value to the target) are not implemented; Bun and
    Deno's strip / `--erasable` modes do the same. Code that needs
    decorator runtime behavior should compile with the TypeScript
    compiler (`experimentalDecorators` or 2022-decorators emit).

- **Top-level `await`** — Works on all three backends. `isESM()`
  detects top-level `await` anywhere at depth-0 statement scope so
  `.ts` files using top-level await without explicit `import`/`export`
  still get module-mode dispatch. JSC and V8 evaluate the transpiled
  ESM body as a script, so the shim wraps in an async IIFE with a
  catch handler that surfaces rejections as non-zero exit codes.

- **Node fs callbacks** — `fs.readFile(path, cb)` /
  `fs.readFile(path, opts, cb)` invoke the callback (previously
  always returned a promise, breaking `util.promisify(fs.readFile)`).
  `fsP.readdir(path, { withFileTypes: true })` returns Dirent
  objects with `.isFile()` / `.isDirectory()` / `.isSymlink()`.

- **`Worker` constructor + eval-source + EventEmitter** —
  `require('worker_threads').Worker` is real-class-constructible.
  `new Worker(src, { eval: true, workerData: {...} })` writes the
  inline source to a temp file with the workerData baked in; the
  returned worker exposes `on`/`once`/`off`/`removeListener`/`terminate`
  that dispatch through the existing `onmessage` / `onerror` /
  `onexit` hooks. Inside the worker, `require('worker_threads')
  .parentPort` is an EventEmitter delegating to `self.postMessage`.
  workerdemo.ts in the ts_compat grid passes on all three DunJS
  backends (parity with Bun; Node and Deno fail).

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

## Won't-fix

- **Native `.node` addons that bypass N-API** — Things that
  `dlopen('node')` and call into V8 / libuv internals can't be
  supported by any non-Node runtime. Addons that stay within the
  N-API surface work.

- **Host-specific API tests on the wrong host** — e.g.
  `tests/benchmarks/ts_compat/bunapis.ts` calls `Bun.hash.xxh32`,
  which doesn't exist on Bun 1.3 either. These tests are useful as
  cross-runtime delta indicators, not as conformance gates.
