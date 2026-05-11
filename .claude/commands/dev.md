# DunJS Development Workflow

## Quick Reference

```sh
# Build (pick one backend)
ldc2 -run build.d --backend=quickjs   # vendor deps first
dub build -c quickjs                   # QuickJS (default)
dub build -c jsc                       # JavaScriptCore
dub build -c v8                        # V8

# Test
dub test -c unittest                   # all unit tests (~150 tests)
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
    globals.d        # Console, timers, queueMicrotask, process.nextTick
    rejection_tracker.d  # Unhandled promise rejection tracking
  ts/strip.d         # TypeScript type stripping (20 tests)
  security/          # Permission model (27 tests)
  cli/args.d         # CLI argument parser
  loop/
    eventloop.d      # Event loop (epoll/kqueue/poll + io_uring)
    async.d          # Async work queue (background threads + promises)
  builtins/          # fs, path, net, http, crypto, fetch, buffer, events, url, os
  modules/           # ES modules, CJS require, npm resolver
  platform/          # OpenSSL bindings, memory, threading

vendor/v8shim/       # V8 C++ shim (~300 LOC, uses TMP templates)
```

## Architecture Rules

1. **Upper layers use IJSEngine only** -- never import backend-specific bindings
2. **Each backend lives in engine/<name>/** -- only place that touches raw C/C++ APIs
3. **All extern(C) callbacks must be nothrow** -- D exceptions can't cross FFI
4. **RAII for engine resources** -- JSVal, DunV8Value ref-counting, JSValueProtect
5. **Permission checks before I/O** -- `state.permissions.check(Permission.read, path)`
6. **Named constants for limits** -- `DEFAULT_MEMORY_LIMIT`, not `256 * 1024 * 1024`
7. **Engine-agnostic builtins** -- all modules work identically across QuickJS, JSC, V8

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
- `source/dun/app.d` -- entry point, shows how layers connect
- `source/dun/runtime/globals.d` -- per-backend console wiring + module registration
- `source/dun/loop/eventloop.d` -- event loop phases and microtask draining
- `ARCHITECTURE.md` -- system diagrams and design decisions
