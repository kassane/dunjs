# DunJS Development Workflow

## Quick Reference

```sh
# Build (pick one backend)
ldc2 -run build.d --backend=quickjs   # vendor deps first
dub build -c quickjs                   # QuickJS (default)
dub build -c jsc                       # JavaScriptCore
dub build -c v8                        # V8

# Test
dub test -c unittest                   # all unit tests (118 QJS/V8, 47 JSC)
./build/dun run tests/integration/fixtures/hello.js  # smoke test

# Run
./build/dun run script.js              # JavaScript
./build/dun run script.ts              # TypeScript (type stripping)
./build/dun eval "1+1"                 # inline eval
./build/dun repl                       # interactive REPL
./build/dun install <pkg>              # npm package installer
```

## Project Structure

```
source/dun/
  app.d              # Entry point (main, runScript, eval, repl)
  engine/
    iface.d          # IJSEngine interface (40+ methods)
    callbacks.d      # Global NativeCallback registry
    test.d + fuzz.d  # ~100 BDD engine tests
    quickjs/         # QuickJS-NG backend (extern(C) -> quickjs.h)
    jsc/             # JSC backend (extern(C) -> JSC C API + TMP bridge)
    v8/              # V8 backend (extern(C) -> v8shim C++ wrapper + TMP bridge)
  runtime/
    globals.d        # Console, timers, queueMicrotask, process (argv/cwd/exit/platform)
    process_api.d    # process.stdin (non-blocking read), process.env, process globals
    worker_api.d     # Workers, SharedArrayBuffer, Atomics (all 3 backends)
    worker_self.d    # Worker self.postMessage/close
    deno_compat.d    # 30+ Deno APIs (env, fs, stat, mkdir, remove, permissions, errors)
    web_compat.d     # atob, btoa, TextEncoder, TextDecoder, structuredClone
    web_apis.d       # Response, Headers, Blob, FormData, EventTarget, AbortController, etc.
    rejection_tracker.d  # Unhandled promise rejection tracking
  ts/strip.d         # TypeScript type stripping (20 tests)
  ts/transpile_cache.d # Persistent transpile cache ($DUN_HOME/cache/tsc/)
  security/          # Permission model (27 perms + 8 CVE tests)
  platform/paths.d   # dunGlobalRoot() — cross-platform user-global store
  workers/           # Worker threads, SharedArrayBuffer, Atomics
  cli/args.d         # CLI argument parser
  loop/
    eventloop.d      # Event loop (epoll/kqueue/poll + io_uring)
    async.d          # Async work queue (background threads + promises)
  builtins/          # 29 modules: fs (30 functions), path, net, http, http2, crypto,
                     #   fetch, buffer, events, url, os, child_process, stream, zlib,
                     #   dns, ws, sqlite, util, assert, querystring, string_decoder,
                     #   vm, cluster, async_hooks, worker_threads, tls
  modules/           # ES modules, CJS require, npm resolver
  platform/          # OpenSSL bindings, memory, threading, SIMD (core.simd + LDC intrinsics)

vendor/v8shim/       # V8 C++ shim (~300 LOC, uses TMP templates)
```

## Architecture Rules

1. **Upper layers use IJSEngine only** -- never import backend-specific bindings
2. **Each backend lives in engine/<name>/** -- only place that touches raw C/C++ APIs
3. **All extern(C) callbacks must be nothrow** -- D exceptions can't cross FFI
4. **RAII for engine resources** -- JSVal (QJS), DunV8Value ref-counting (V8), JSValueProtect/Unprotect (JSC). RAII wrappers ensure deterministic cleanup at scope exit; manual freeValue only when handing the value to JS land
5. **Permission checks before I/O** -- `state.permissions.check(Permission.read, path)`. The resource path is canonicalized inside `check()` (CVE-2023-32004 class)
6. **Named constants for limits** -- `DEFAULT_MEMORY_LIMIT`, not `256 * 1024 * 1024`. Cross-module shared constants live in `source/dun/declarations.d` (UTF-8, Unicode, NAPI, RTLD)
7. **Engine-agnostic builtins** -- all 30+ modules + Workers work identically across QuickJS, JSC, V8
8. **TIGER_STYLE assertions** -- every @trusted block and extern(C)/NativeCallback gets precondition asserts (null ctx, null engine, double-init guards, static asserts for layout/enum counts). `static assert(N > 0)` on size-parameterized templates
9. **Use `setPropertyIndex`/`getPropertyIndex` for array element access** -- O(1) vs O(n) string-based
10. **Use `engine.newUint8Array(data)` for creating Uint8Array from byte data**
11. **Never use `i.to!string` + `setProperty` for array indices** -- use `setPropertyIndex(obj, i, val)` instead
12. **`callFunction` cross-backend contract** -- returns an owned protected value; every caller MUST `engine.freeValue(ret)`. Don't discard the return (was a per-call JSValueProtect leak on JSC fixed in v1.1.6/v1.1.7)
13. **`setPropertyIndex` semantics differ** -- QJS consumes `val`, JSC/V8 don't. Branch by backend (`version (EngineQuickJS)`) when the value needs cleanup after. See `fetch.d` `makeResponse` header pair construction for the canonical pattern
14. **Don't `engine.eval()` per call with a unique source string** -- JSC caches bytecode per unique source forever, leaking ~9 MB per call when bodies are inlined. Cache the function at first use, call with value args. See `_fetchResponseBuilder` / `_fetchHeadersFlattener` in `fetch.d` (v1.1.7)
15. **Doc-comments are human-concise** -- default one line; multi-line only when the WHY is non-obvious (a hidden constraint, a CVE-class workaround, a backend-specific quirk that would surprise the next reader)

## Adding a New Engine Feature

1. Add method to `IJSEngine` in `iface.d`
2. Implement in all 3 backends: `quickjs/backend.d`, `jsc/backend.d`, `v8/backend.d`
3. For V8: may need new function in `vendor/v8shim/v8shim.cpp` + `v8shim.h` + D `bindings.d`
4. Add test in `engine/test.d` using `@Test` UDA
5. Add integration test fixture in `tests/integration/fixtures/` + expected output

## Adding a New V8/JSC Type

Uses the C++ TMP <-> D TMP bridge pattern:

**V8**:
1. C++: add to `V8Tag` enum in `v8shim_tmpl.hpp`, add `if constexpr` case in `isV8Type<Tag>`
2. C++: add `dun_v8_value_is_xxx` one-liner in `v8shim.cpp`, declare in `v8shim.h`
3. D: add to `V8TypeTag` enum, `V8TypeName` template, `V8TypeChecks.init()` table in `cppbindings.d`
4. D: add to `bindings.d` extern declarations

**JSC**:
1. D: add to `JSCTypeTag` enum, `JSCTypeName` template in `cppbindings.d`
2. D: add to `JSCTypeChecks.init()` table (or handle specially like Function)
3. D: add binding declaration in `bindings.d` if needed

## Adding a New Builtin Module

1. Create `source/dun/builtins/<name>.d`
2. Use `IJSEngine` + `NativeCallback` -- never backend-specific code
3. Register in `runtime/globals.d` via `registerXxxModule(engine)`
4. Add to CJS require map in `modules/require.d`
5. Add ESM resolution in `modules/resolver.d`
6. Add integration test in `tests/integration/fixtures/`

## Key Files to Read First

- `source/dun/engine/iface.d` -- the core abstraction everything depends on
- `source/dun/declarations.d` -- shared named constants (UTF-8, Unicode,
  NAPI, RTLD) — add here when a value lives in two+ modules
- `source/dun/app.d` -- entry point, shows how layers connect
- `source/dun/runtime/globals.d` -- per-backend console wiring + module registration
- `source/dun/loop/eventloop.d` -- event loop phases and microtask draining
- `source/dun/security/permissions.d` -- default-deny + CVE-2023-32004-class path canonicalization
- `ARCHITECTURE.md` -- system diagrams and design decisions
- `CLAUDE.md` -- development guide (build commands, code style,
  DIP1000 `return scope` / DIP1038 `@mustuse` rules, GC tuning,
  CVE-class fix patterns)
- `SECURITY.md` -- threat model, permission flags, fixed CVE
  classes (path-traversal v1.1.0, latin1 high-byte v1.1.3,
  JSC NUL truncation v1.1.3/1.1.4), `/security-review` skill
- `TESTING.md` -- test inventory, integration sweep recipe,
  cross-runtime comparison grids, audit fixtures (`audit_simd`,
  `audit_roundtrip`, `cve_path_traversal`)
- `CHANGELOG.md` -- phased delivery history
- `CLAUDE.md ## Won't-fix design constraints` -- documented
  no-go items (native .node addons, full Bun parser port)

## Skills (Claude Code commands)

- `/build` — full build + smoke test of one backend
- `/all-backends` — build all three backends, side-by-side staging
- `/integration-sweep` — run integration sweep across all backends
  with 3× retry on the known concurrency-flake fixtures
- `/debug-native-callback` — gdb workflow for native-callback bugs
  (slot overflow, JSC GC contention, NUL truncation, per-fetch
  bytecode leaks)
- `/bench-compare` — wrk + feature_bench across runtimes
- `/security-review` — OWASP-top-10 audit of pending changes;
  run before opening a PR that touches `security/`, `builtins/fs.d`,
  `net.d`, `http*.d`, `child_process.d`, or any new IJSEngine
  callback that takes user input
