# DunJS Architecture

## Overview

DunJS is a 7-layer JavaScript/TypeScript runtime with a **pluggable engine architecture**
(IJSEngine interface), a cross-platform I/O poller (epoll/kqueue/poll), and a Deno-inspired permission system.

Three backends are fully functional: QuickJS-NG (default), JavaScriptCore, and V8.
All 38 integration tests pass on QuickJS (including 9 real-world end-to-end scenarios).

Reference: [Bun's Zig->Rust port](https://github.com/oven-sh/bun/pull/30412) -- modular
workspace with `bun_jsc` engine layer, `*_jsc` suffix pattern for engine-specific modules,
RAII wrappers, and pointer safety auditing.

## System Architecture

```
+--------------------------------------------------------------+
|                    JavaScript / TypeScript User Code           |
|              (ES2023+ modules, async/await, .ts/.mts/.cts)    |
+--------------------------------------------------------------+
|  Layer 7: CLI & REPL                                          |
|  +---------+ +------+ +------+ +---------+                    |
|  |  args   | | repl | | run  | |   fmt   |                    |
|  +---------+ +------+ +------+ +---------+                    |
+--------------------------------------------------------------+
|  Layer 6: Runtime API (Globals)                               |
|  +---------+ +------------+ +---------+ +----------+          |
|  | console | | timers_api | | process | | encoding |          |
|  | (all 3) | |            | |         | |          |          |
|  +---------+ +------------+ +---------+ +----------+          |
+--------------------------------------------------------------+
|  Layer 5: Module System                                       |
|  +----------+ +--------+ +-----+ +----------+                 |
|  | resolver | | loader | | esm | | builtins |                 |
|  +----------+ +--------+ +-----+ +----------+                 |
+--------------------------------------------------------------+
|  Layer 4: Built-in Modules                                    |
|  +----+ +------+ +-----+ +------+ +--------+ +-----+         |
|  | fs | | path | | net | | http | | crypto | | url |         |
|  +----+ +------+ +-----+ +------+ +--------+ +-----+         |
+--------------------------------------------------------------+
|  Cross-Cutting Concerns                                       |
|  +----------------+ +------------------+ +----------------+   |
|  | Security       | | TypeScript       | | TMP Bridge     |   |
|  | permissions.d  | | strip.d          | | cppbindings.d  |   |
|  | test.d (27)    | | (type stripping) | | (V8 + JSC)     |   |
|  +----------------+ +------------------+ +----------------+   |
+--------------------------------------------------------------+
|  Layer 3: Event Loop & Async Runtime                          |
|  +-----------+ +--------+ +------------+ +-------+            |
|  | eventloop | | timers | | microtasks | | tasks |            |
|  +-----------+ +--------+ +------------+ +-------+            |
+--------------------------------------------------------------+
|  Layer 2: JS Engine Abstraction                               |
|  +-----------------------------------------------+            |
|  |  IJSEngine (iface.d)                          |            |
|  |  +--------------+--------------+----------+   |            |
|  |  | quickjs/     |  jsc/        |  v8/     |   |            |
|  |  | backend.d    | backend.d    | backend.d|   |            |
|  |  | bindings.d   | bindings.d   | bindings.d   |            |
|  |  | cimport.c    | cppbindings.d| cppbindings.d|            |
|  |  | runtime.d    | (TMP bridge) | (TMP bridge) |            |
|  |  | context.d    |              |              |            |
|  |  | value.d      |              | v8shim/      |            |
|  |  |              |              | (C++ shim)   |            |
|  |  +--------------+--------------+----------+   |            |
|  +-----------------------------------------------+            |
+--------------------------------------------------------------+
|  Layer 1: Platform Abstraction                                |
|  +--------+ +-----------+ +----+ +-------+                    |
|  | memory | | threading | | io | | paths |                    |
|  +--------+ +-----------+ +----+ +-------+                    |
+--------------------------------------------------------------+
|  Vendor: Engine (C/C++) | OS syscalls (epoll/kqueue/poll)    |
+--------------------------------------------------------------+
```

## Engine Abstraction Pattern

```
  Upper Layers (app, runtime, builtins, loop)
            |
            v
  +---------------------+
  |   IJSEngine          |  interface in iface.d
  |   - eval()           |
  |   - newString()      |
  |   - getProperty()    |
  |   - drainJobs()      |
  |   - isUndefined()    |  <-- dispatches via TMP type checks
  |   - ...              |
  +----------+-----------+
             | implements
    +--------+--------+
    v        v        v
 QuickJS    JSC      V8
 Engine   Engine   Engine
    |        |        |
    v        v        v
 extern(C)  extern(C)  extern(C)
 quickjs.h  JSC C API  v8shim.cpp
```

`createEngine()` factory returns the selected backend (compile-time via
`version(EngineQuickJS)`, `version(EngineJSC)`, `version(EngineV8)`).
Backends live in `source/dun/engine/<name>/` and only they import
engine-specific C/C++ bindings.

## Data Flow: Script Execution

```
CLI (args.d) --parse--> CliConfig
                              |
                    +---------v----------+
                    | createEngine()      |  IJSEngine factory
                    | engine.initialize() |  EngineConfig
                    | installGlobals()    |  console (per-backend)
                    +---------+----------+
                              |
                    +---------v----------+
                    | isTypeScript(path)? |  .ts/.mts/.cts detection
                    | stripTypes(source)  |  whitespace-preserving
                    +---------+----------+
                              |
                    +---------v----------+
                    | engine.eval(source) |  Evaluates JS source
                    +---------+----------+
                              |
                    +---------v----------+
                    | engine.drainJobs()  |  Promise microtasks
                    +---------+----------+
                              |
                    +---------v----------+
                    | engine.shutdown()   |  Cleanup
                    +--------------------+
```

## Console Implementation (per-backend)

Each backend uses its native callback mechanism to implement `console.*`:

```
                    installGlobals()
                          |
          +---------------+---------------+
          v               v               v
    EngineQuickJS    EngineJSC        EngineV8
          |               |               |
    console.d:        globals.d:       globals.d:
    JS_NewCFunction   JSObjectMake     dun_v8_new_function
    -> core.stdc.stdio FunctionWith     -> FunctionTemplate
                      Callback         -> v8FunctionTrampoline
                      -> std.stdio      -> std.stdio
```

## C++ TMP <-> D TMP Bridge Pattern

The V8 and JSC backends use a cross-language template metaprogramming bridge where
C++ templates and D compile-time features mirror each other across the FFI boundary.
Both sides resolve at compile time with zero runtime overhead.

### V8 Bridge

```
C++ side (vendor/v8shim/)                D side (engine/v8/)
=========================                ====================

v8shim_tmpl.hpp:                         cppbindings.d:
  enum V8Tag { Undefined,                  enum V8TypeTag { Undefined,
    Null, Bool, Int, Number,                 Null, Bool, Int, Number,
    String, Object, Array,                   String, Object, Array,
    Function }                               Function }

  V8TypeMap<Tag> (type map)                V8TypeName!tag (name map)

  isV8Type<Tag>(isolate, vw)               V8TypeChecks.check(tag, val)
    -> if constexpr dispatch                 -> function pointer table

  withContext<F>(cw, fn)                   backend.d:
    -> RAII scope guard                      checkType(tag, handle)
    -> eliminates 4-line                     -> lazy-init dispatch table
       boilerplate in ~20 fns                -> 7 isXxx() one-liners

v8shim.cpp:
  valueIsType<Tag>(vw)
    -> withIsolate + isV8Type
  9 type-check fns = 1-liners
  ~20 fns use withContext<F>
```

**Adding a new V8 type** only requires:
1. C++: add enum value + `if constexpr` case + `V8TypeMap` specialization
2. D: add enum value + `V8TypeName` entry + `V8TypeChecks` table row

### JSC Bridge

JSC has `JSValueGetType()` returning a `JSType` enum directly -- a single C call
replaces multiple type-check calls:

```
JSC C API (bindings.d)                   D side (engine/jsc/)
======================                   ====================

JSType enum:                             cppbindings.d:
  kJSTypeUndefined = 0                    enum JSCTypeTag { Undefined = 0,
  kJSTypeNull      = 1                      Null = 1, Boolean = 2,
  kJSTypeBoolean   = 2                      Number = 3, String = 4,
  kJSTypeNumber    = 3                      Object = 5, Symbol = 6,
  kJSTypeString    = 4                      Array, Function, Date }
  kJSTypeObject    = 5
  kJSTypeSymbol    = 6                   JSCTypeName!tag (name map)

JSValueGetType(ctx, val)                 JSCTypeChecks:
  -> returns JSType (single call)          .getType() -> single dispatch
                                           .check(tag) -> fn ptr table
JSValueIsXxx(ctx, val)                     .typeofString() -> JS typeof
  -> individual type checks
                                         backend.d:
                                           checkType(tag, handle)
                                           -> 7 isXxx() one-liners
```

**JSC advantage**: `getType()` returns the type in one call (O(1) dispatch),
while V8 requires testing each type individually.

## V8 Native Function Trampoline

V8 has no C API -- the C++ shim uses FunctionTemplate with an extern "C" trampoline:

```
D function pointer (DunV8NativeCallback)
          |
          | stored in DunV8FunctionData struct
          v
v8::External wraps pointer to FunctionData
          |
          | passed as data to FunctionTemplate
          v
v8FunctionTrampoline (C++ function)
          |
          | extracts DunV8FunctionData* from External
          | wraps argv in DunV8Value* array
          | calls D callback via function pointer
          v
D callback executes, returns DunV8Value*
          |
          | trampoline unwraps result
          v
V8 receives return value via FunctionCallbackInfo::GetReturnValue()
```

## Memory Management Bridge

```
+---------------------+        +-----------------------------+
|   D World (GC)      |        |  Engine World (C/C++)       |
|                     |        |                             |
|  IJSEngine    ------+-call-->|  QuickJS: extern(C) direct  |
|                     |        |  JSC: extern(C) to C API    |
|                     |        |  V8: extern(C) to C++ shim  |
|                     |        |                             |
|  JSHandle     ------+-map--->|  QJS: JSValue (tagged union) |
|                     |        |  JSC: JSValueRef (opaque ptr)|
|                     |        |  V8: DunV8Value* (ref-counted)|
|                     |        |                             |
|  DunState*    <-----+-opaque-|  QJS: JS_GetContextOpaque   |
|                     |        |  JSC: opaquePtr field        |
|                     |        |  V8: dun_v8_get_context_data |
|                     |        |                             |
|  GC.addRoot() ------+-pin--->|  Engine class opaque         |
|  @trusted block ----+-call-->|  eval, call                  |
|                     |        |                             |
+---------------------+        +-----------------------------+
```

### Value Lifetime Rules

| Engine | Own | Borrow | Release |
|--------|-----|--------|---------|
| QuickJS | `JS_Eval`, `JS_NewString`, etc. | `argv[]` in callbacks | `JS_FreeValue(ctx, val)` |
| JSC | All JSValueRef are GC-managed | Same refs | `JSValueUnprotect(ctx, val)` |
| V8 | `wrapValue` -> `DunV8Value*` (ref=1) | N/A | `dun_v8_value_unref` (ref--) |

### Rules

1. Every value returned by the engine **MUST** be freed via RAII or explicit `freeValue()`
2. D objects stored as engine opaques **MUST** be pinned with `GC.addRoot`
3. `extern(C)` callbacks **MUST** be `nothrow`
4. Custom allocator enforces memory limits
5. `dupValue()` must be called when storing a handle beyond its original scope

## Permission Enforcement Flow

```
JS code calls:  import { readFileSync } from "dun:fs";
                readFileSync("/etc/passwd")
                        |
                        v
               extern(C) jsReadFileSync(ctx, ...)
                        |
                        v
               DunState* state = getContextOpaque()
                        |
                        v
               state.permissions.check(Permission.read, "/etc/passwd")
                        |
                +-------+-------+
                |               |
              DENIED          GRANTED
                |               |
                v               v
        throwTypeError()    std.file.read("/etc/passwd")
        "Requires           return newString(content)
         --allow-read"
```

## Key Type Signatures

### DunState (Central runtime state)

```d
struct DunState {
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}
```

### IJSEngine Interface (abbreviated)

```d
interface IJSEngine {
    void initialize(EngineConfig config);
    void shutdown();
    JSResult eval(const(char)[] source, string filename);
    JSHandle newString(const(char)[] s);
    JSHandle newObject();
    JSHandle getGlobal();
    void setProperty(JSHandle obj, const(char)[] name, JSHandle val);
    JSHandle getProperty(JSHandle obj, const(char)[] name);
    string extractString(JSHandle val);
    bool isUndefined(JSHandle val);  // dispatches via TMP type checks
    string getException();
    void drainJobs();
    void* rawContext();   // Escape hatch for backend-specific code
}
```

## Engine FFI Strategies

| Engine | API Style | D FFI | Shim | Callback Registration |
|--------|-----------|-------|------|----------------------|
| QuickJS | C API | extern(C) direct | None | `JS_NewCFunction(ctx, &fn, name, argc)` |
| JSC | C API | extern(C) direct | None | `JSObjectMakeFunctionWithCallback(ctx, name, &fn)` |
| V8 | C++ only | extern(C) via shim | vendor/v8shim/ (~300 LOC) | `dun_v8_new_function(ctx, &fn, name, data)` -> FunctionTemplate |

### V8 C++ Shim Details

V8 has no stable C API. The shim (`vendor/v8shim/v8shim.cpp`) exposes ~38 functions,
refactored via `withContext<F>` to eliminate scope guard boilerplate:

| Category | Functions | TMP Pattern |
|----------|-----------|-------------|
| Lifecycle | `isolate_new`, `isolate_dispose`, `context_new`, `context_free` | -- |
| Eval | `eval` (with Script::Compile + Run) | `withContext<F>` |
| Values | `new_undefined/null/bool/int/number/string/object/array/function` | `withContext<F>` |
| Extract | `value_to_string/int/number/bool`, `free_string` | `withContext<F>` |
| Types | `value_is_undefined/null/bool/int/number/string/object/function/array` | `valueIsType<Tag>` -> `isV8Type<Tag>` |
| Props | `get_property`, `set_property`, `global` | `withContext<F>` |
| Refs | `value_ref`, `value_unref` (ref-counted `v8::Global<Value>`) | -- |
| Errors | `get_exception`, `throw_error/type_error/range_error` | `withContext<F>` |
| Calls | `call` (invoke JS function from native) | `withContext<F>` |
| Microtasks | `has_pending_microtasks`, `drain_microtasks` | -- |
| Data | `set_context_data`, `get_context_data` | -- |
| Limits | `set_memory_limit`, `set_stack_limit` | -- |

### D extern(C++, "v8") Direct Bindings

For V8's all-static `V8` class (no vtable, safe to bind directly):

```d
extern(C++, "v8") {
    extern class V8 {
    static:
        const(char)* GetVersion();
        bool Initialize();
        bool Dispose();
        void InitializePlatform(void* platform);
    }
}
```

Instance methods on V8 C++ classes (Isolate, Context, etc.) generate vtable entries
that require linking against V8's C++ objects -- these MUST go through the C shim.

## Comparison with Other Runtimes

| Aspect | Node.js | Deno | Bun | **DunJS** |
|--------|---------|------|-----|-----------|
| Language | C++ | Rust | Zig | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable (QuickJS, JSC, V8)** |
| TypeScript | Via tsc/swc | Built-in check+strip | Built-in transpile | **Type stripping** |
| Engine FFI | Native C++ | rusty_v8 (Rust bindings) | Zig extern(C++) | **extern(C) + C shim** |
| TMP Bridge | N/A | N/A | N/A | **C++ TMP <-> D TMP** |
| Event Loop | libuv | Tokio | io_uring | **epoll/kqueue/poll** |
| Permission | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |
| Build System | gyp -> cmake | cargo | zig build | **DUB + build.d** |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| JS Engine | Pluggable (IJSEngine) | Swap backends without rewriting upper layers |
| Default backend | QuickJS-NG | Pure C API, ES2023, easy extern(C), MIT license |
| Tier 2 backends | JSC + V8 | JIT performance for production use |
| TypeScript | Type stripping | Same as Node.js `--experimental-strip-types`; preserves source positions |
| C FFI | extern(C) | Auditable bindings, no external tooling |
| C++ FFI (V8) | C shim + extern(C) | V8 templates/RAII require C++ wrapper |
| C++ FFI (V8 TMP) | withContext<F> + isV8Type<Tag> | Eliminates scope guard boilerplate in ~20 functions |
| C++ FFI (JSC) | extern(C) public API | JSC has a stable C API (JSObjectRef) |
| D TMP (V8) | V8TypeChecks dispatch table | Function pointer table mirrors C++ isV8Type<Tag> |
| D TMP (JSC) | JSCTypeChecks + getType() | Single-dispatch via JSValueGetType(), mirrors kJSType* |
| C++ FFI (direct) | extern(C++, "v8") | Only for static-method classes (no vtable) |
| V8 headers | Vendored from Node.js | Eliminate libv8-dev compile dependency |
| Event loop | epoll/kqueue/poll | D stdlib syscalls, zero deps, cross-platform |
| Build system | DUB (JSON) | Standard D tooling, configurations per engine |
| Build orchestrator | build.d | CMake, curl downloads, toolchain detection |
| Async model | Callback loop + Promise jobs | Matches engine internal async handling |
| Permission | Default deny-all | Security-first, Deno's proven model |
| RAII wrappers | D structs with `~this()` | Deterministic cleanup, zero-cost |
| Engine selection | `dub build -c quickjs/jsc/v8` | DUB configurations switch backends |

## Testing Architecture

```
tests/
+-- integration/
|   +-- fixtures/       # 38 test scripts (JS, MJS, TS)
|   |   +-- hello.js                    # Basic smoke test
|   |   +-- types.js                    # typeof for all JS types
|   |   +-- console_methods.js          # log/info/debug, multiple args
|   |   +-- promises.js                 # Promise + async/await
|   |   +-- promises_advanced.js        # all/race/any, async errors
|   |   +-- es2023.js                   # findLast, optional chaining, Array.at
|   |   +-- error_handling.js           # try/catch, Error subtypes, Error.cause
|   |   +-- closures.js                 # Closures, generators, destructuring
|   |   +-- iterators.js               # Map, Set, WeakRef, Array.from
|   |   +-- json_parsing.js            # JSON parse/stringify, replacer/reviver
|   |   +-- classes.js                  # Inheritance, private fields, valueOf
|   |   +-- regex.js                    # Named groups, matchAll, flags
|   |   +-- typescript.ts              # TS type stripping
|   |   +-- timers.js                  # setTimeout/setInterval
|   |   +-- phase2.js                  # Event loop phases
|   |   +-- phase2_rejection.js        # unhandledRejection
|   |   +-- async_io.mjs               # Async I/O operations
|   |   +-- module_esm.mjs            # ES module import/export
|   |   +-- module_cjs.js             # CommonJS require
|   |   +-- module_chain.js           # Chained module dependencies
|   |   +-- json_pipeline.js          # JSON import pipeline
|   |   +-- npm_compat.js             # npm compatibility
|   |   +-- fs_ops.mjs                # File system operations
|   |   +-- path_ops.mjs              # Path manipulation
|   |   +-- crypto_ops.mjs            # Crypto operations
|   |   +-- stat_file.js              # File stat
|   |   +-- env_access.js             # Environment variables
|   |   +-- perm_deny_read.js         # Permission denial (read)
|   |   +-- perm_deny_write.js        # Permission denial (write)
|   |   +-- realworld_config_loader.js     # Config loading end-to-end
|   |   +-- realworld_task_runner.js       # Task runner simulation
|   |   +-- realworld_file_processor.mjs   # File processing pipeline
|   |   +-- realworld_event_system.js      # Event emitter pattern
|   |   +-- realworld_promise_pool.js      # Concurrent promise pool
|   |   +-- realworld_ts_library.ts        # TS library patterns
|   |   +-- realworld_nested_require.js    # Nested require chains
|   |   +-- realworld_security_boundary.js # Security boundary tests
|   |   +-- realworld_esm_pipeline.mjs     # ESM pipeline end-to-end
|   +-- expected/       # 37 expected stdout files
|   +-- fixtures/lib/   # Shared modules for require tests
+-- bench/              # Benchmarks

source/dun/engine/
+-- test.d              # ~50 BDD-style engine contract tests
+-- fuzz.d              # ~50 fuzz/stress tests

source/dun/ts/
+-- strip.d             # 20 TypeScript stripper tests (inline)

source/dun/security/
+-- test.d              # 27 permission registry tests (inline)
```

Test pattern inspired by Node.js standalone scripts: run fixture, compare stdout to expected file.
All 38 integration tests pass on QuickJS. TypeScript tests use type stripping.
