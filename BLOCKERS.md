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

- **RegExp `/v` set operations** — QuickJS-NG 0.14 rejects
  `[A--B]/v` / `[A&&B]/v` literals at parse time; V8 14.9 has /v
  but returns wrong matches for `[\p{X}--\p{Y}]/v`. JSC handles both
  natively. `dun.runtime.unicode_props.expandVSetOps()` runs on every
  loaded source (and on `eval("/.../v")` string args) and rewrites
  set-difference / intersection / nested-class operands into a
  pre-computed `/u` range class. ECMAScript spec audit now reads
  98/98 across all 3 backends; was 97/98 on QJS + V8 before this.

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
  - **Decorators (`@DecoratorName(args)`)** — handled correctly when
    the user has `typescript` installed (DunJS auto-routes through
    `ts.transpileModule()` and emits `__decorate` calls). Falls back
    to the scanner stripper (which erases decorators) when typescript
    isn't installed. Matches Bun and Deno's strip / `--erasable` mode
    in the fallback path.

- **TS-to-JS pipeline (tsc by default)** — when `typescript` is
  installed in node_modules (anywhere upward from the script, or in
  `$DUN_HOME/node_modules`), `.ts` / `.tsx` files go through
  `ts.transpileModule()` for full TS-spec correctness: decorators,
  namespace runtime, const enum member references, generic call
  sites, the entire TS surface. Falls back to the byte-level
  stripper when typescript isn't present. Opt-out:
  `DUN_DISABLE_TSC=1`. Works uniformly on QuickJS / JSC / V8.
  (The earlier V8-specific opt-in flag is gone: the underlying
  segfault was a stale __gshared cache from runTranspile's transient
  engine; minimal-init fix in runTranspile means the main engine no
  longer reuses V8 handles from a freed isolate.)

  Three production-grade refinements on top of that:

  1. **Persistent transpile cache** at
     `$DUN_HOME/cache/tsc/<first-2-chars>/<sha256>.js`. Key hashes
     (source, filename, tsc version, compiler-options fingerprint),
     so any input change invalidates exactly its own entries. Drops
     a cache hit's wall time from ~900 ms (cold tsc startup) to
     ~30 ms (~30× speedup). LRU eviction triggers at most every 5
     min via a `.last_trim` mtime marker (in-process counters would
     never advance across `dun` invocations). Bounds:
     `DUN_TSC_CACHE_MAX_ENTRIES` (default 2000),
     `DUN_TSC_CACHE_MAX_MB` (default 64),
     `DUN_TSC_CACHE_TRIM_INTERVAL_SECS` (default 300).

  2. **Auto-install consistency**. Both `--typecheck` and the
     default tsc path now auto-install typescript when missing
     (was: only `--typecheck`). Default path needs explicit
     opt-in via `DUN_AUTO_INSTALL_TSC=1` so first-run latency is
     opt-in; `--typecheck` still auto-installs unconditionally.
     Both install into `$DUN_HOME/node_modules` so every
     invocation on the machine shares one copy.

  3. **User-global store at `$DUN_HOME`** (default
     `$HOME/.dun` on Posix, `%LOCALAPPDATA%\dun` on Windows).
     Hosts both the transpile cache and the auto-installed
     packages. Overridable via `DUN_HOME=/path` for CI caches,
     multi-user sandboxes, etc. `installPackage` takes an
     `installRoot` parameter; `require()`'s resolver falls back
     to `$DUN_HOME/node_modules` after the project tree walk
     fails. Cross-platform — uses `std.path.buildPath` everywhere,
     no embedded posix separators.

- **Bun.hash sub-methods + Deno async FS** —
  `Bun.hash.{crc32, adler32, xxh32, xxh64}` and `Deno.{stat, lstat,
  mkdir, remove, rename, copyFile, readDir, readTextFile,
  writeTextFile, realPath, truncate}` async variants all match
  their respective vendor's surface. `Deno.errors.*` are real
  Error subclasses now (instanceof works), classified from OS
  failure messages.

- **child_process + Web streams** — `child.stdout.on('data', ...)`
  fires reliably (closure-captured emitter, not `this._events`).
  `Bun.spawn(...).stdout` is a Web ReadableStream;
  `new Response(p.stdout).text()` consumes it correctly.
  `Readable.prototype[Symbol.asyncIterator]` no longer hangs when
  `_read` synchronously emits `end` before subscription.

- **Dynamic `import()`** — `await import("fs")` works on all three
  backends. JSC and V8 don't wire
  `HostImportModuleDynamicallyCallback`, so the source pipeline
  rewrites the call site to `__dunImport__(...)` (a tiny shim that
  wraps `require(...)` in a Promise). QJS uses its native module
  loader. Source rewriter respects string / template / comment /
  regex contexts; static `import x from "y"` and `import.meta`
  pass through unchanged.

- **V8 D exception unwinding** — V8 backend now properly unwinds D
  exceptions through native callbacks. The `.eh_frame_hdr` section
  is required by glibc's `_Unwind_RaiseException` to look up
  LSDA tables. LDC's `--link-internally` mode (needed for V8's
  CREL relocations in libv8_monolith.a) doesn't emit it by
  default; passing `-L=--eh-frame-hdr` to lld fixes it. Without
  this, any D `try { ... } catch` inside a native callback was
  silently bypassed and the process aborted on the first throw
  (e.g. `Deno.readTextFileSync("/nonexistent")` previously
  crashed V8 with `rt/dwarfeh.d:370: uncaught exception`).

- **Stream pipe + pipeline + Readable.from** —
  `Readable.from([...]).pipe(dst)` now actually flows (was sitting
  idle waiting for a consumer to call `read()`). `pipeline(a, b, c,
  cb)` actually invokes the callback (the `'finish'` listener
  attached AFTER the pipe loop synchronously drained the chain).
  `pipe()` attaches the `'end'` listener before the auto-resuming
  `'data'` listener so `dest.end()` runs.

- **`performance.now()` high-resolution across all 3 backends** —
  JSC and V8 ship a native one that rounds to integer milliseconds,
  so benchmarks measuring sub-ms loops got always-zero diffs. We
  override with a MonoTime-backed implementation that returns
  sub-millisecond doubles uniformly.

- **`URL.parse(url, base?)`** — Node 20+ / WHATWG static method
  (returns URL or null instead of throwing). Sibling to the
  pre-existing `URL.canParse`.

- **worker_threads message shape** — `.on('message', cb)` now
  receives the raw posted value (Node semantics) instead of a
  `{data: payload}` wrapper (Web Worker semantics). Workers
  authored against Node's `worker_threads` see the right value.

- **`new WebSocketServer(opts)` / `new WebSocket(url)`** — JS-side
  class wrappers around the native factories so the canonical
  `new`-form usage works (extern(C) callbacks themselves can't
  be invoked as constructors on any of the three backends).
  Supports both `new` and bare-call forms; added `ws.Server`
  alias.

- **MessagePort auto-start on `onmessage` setter** — Per WHATWG
  spec, assigning to `port.onmessage` implicitly starts the port
  so queued messages flush. Now done via a getter/setter pair on
  the prototype (was a plain data property).

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
