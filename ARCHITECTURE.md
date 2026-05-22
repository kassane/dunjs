# DunJS Architecture

## Overview

DunJS is a 7-layer JavaScript/TypeScript runtime with a **pluggable engine architecture**
(IJSEngine interface), a cross-platform I/O poller (epoll/kqueue/poll), and a Deno-inspired permission system.

Three backends are fully functional: QuickJS-NG (default), JavaScriptCore, and V8.
158/158 integration tests pass on QuickJS / V8; 157/158 + 1 SKIP on JSC (the SKIP is `bun_v7_additions`, a known JSC handle-pressure constraint with `deno_deploy_compat`).
All built-in modules (see CLAUDE.md for the canonical list — 30+ including fs, path,
crypto, net, http, http2, http3, buffer, events, url, os, fetch, child_process, stream,
zlib, dns, ws, sqlite, util, assert, querystring, string_decoder, timers/promises, vm,
cluster, async_hooks, worker_threads, https, fs/promises, readline, tls, dgram,
perf_hooks, wasi) are engine-agnostic.
Workers, SharedArrayBuffer, and Atomics work on all backends.
HTTPS via OpenSSL, npm package install, 30+ Deno APIs, web standard globals, POSIX signal handling.
fetch() returns proper Response objects. import.meta works on all backends. process.stdin available.
core.simd + LDC intrinsics (shufflevector, llvm_bswap, llvm_cttz, llvm_prefetch) for hex encoding, HTTP header parsing, byte search, and Buffer endian operations.

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
|  +---------+ +------------+ +---------+ +------------+        |
|  | console | | timers_api | | process | | deno_compat|        |
|  | (all 3) | | workers    | | (argv,  | | (30+ APIs) |        |
|  |         | | SAB/Atomics| | cwd,pid)| | web_compat |        |
|  +---------+ +------------+ +---------+ +------------+        |
+--------------------------------------------------------------+
|  Layer 5: Module System                                       |
|  +----------+ +--------+ +-----+ +----------+ +-----+         |
|  | resolver | | loader | | esm | | builtins | | npm |         |
|  +----------+ +--------+ +-----+ +----------+ +-----+         |
+--------------------------------------------------------------+
|  Layer 4: Built-in Modules (24 modules, all engine-agnostic)  |
|  +----+ +------+ +-----+ +------+ +--------+ +-----+         |
|  | fs | | path | | net | | http | | crypto | | os  |         |
|  +----+ +------+ +-----+ +------+ +--------+ +-----+         |
|  +--------+ +--------+ +-----+ +-------+ +-------+           |
|  | buffer | | events | | url | | fetch | | http2 |           |
|  +--------+ +--------+ +-----+ +-------+ +-------+           |
|  +--------+ +--------+ +------+ +-----+ +----+               |
|  |child_p | | stream | |  zlib | | dns | | ws |               |
|  +--------+ +--------+ +------+ +-----+ +----+               |
|  +--------+ +------+ +--------+ +---------+ +-----+          |
|  | sqlite | | util | | assert | |querystr | | tls |          |
|  +--------+ +------+ +--------+ +---------+ +-----+          |
+--------------------------------------------------------------+
|  Cross-Cutting Concerns                                       |
|  +----------------+ +------------------+ +----------------+   |
|  | Security       | | TypeScript       | | TMP Bridge     |   |
|  | permissions.d  | | strip.d          | | cppbindings.d  |   |
|  | cve_db.d (22+) | | (type stripping) | | (V8 + JSC)     |   |
|  | test.d (27)    | |                  | |                |   |
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
|  +--------+ +-----------+ +----+ +-------+ +---------+        |
|  | memory | | threading | | io | | paths | | openssl |        |
|  +--------+ +-----------+ +----+ +-------+ +---------+        |
+--------------------------------------------------------------+
|  Vendor: Engine (C/C++) | OS syscalls | OpenSSL (TLS 1.2+)  |
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
6. **TIGER_STYLE assertions**: Every `@trusted` block and FFI callback gets precondition asserts (null ctx/engine/state checks, double-init guards, `static assert` for type layout and enum member counts). ~290 assertions across 25 files -- fail fast at point of corruption, not downstream
7. **DIP1038 `@mustuse`**: `JSResult` (`engine.eval`/`evalModule`) and `AsyncResult` (`asyncSubmitSafe` worker results) must never be silently discarded. Use `mustEval(engine, source, filename, what)` for closed-world inline JS where a parse failure is a build-time bug
8. **DIP1000 `return scope`**: Slices into engine-owned memory (`getTypedArrayBytes`, `extractBytes`) carry `return scope` on both the virtual declaration and every backend override (DIP1000 doesn't infer `scope` for virtuals) -- callers needing the bytes past the JSHandle's lifetime must `.dup`

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
    JSHandle newUint8Array(size_t length);      // Typed array support
    void setProperty(JSHandle obj, const(char)[] name, JSHandle val);
    void setPropertyIndex(JSHandle obj, uint index, JSHandle val);  // Indexed access
    JSHandle getProperty(JSHandle obj, const(char)[] name);
    JSHandle getPropertyIndex(JSHandle obj, uint index);            // Indexed access
    JSHandle getGlobal();
    string extractString(JSHandle val);
    bool isUndefined(JSHandle val);  // dispatches via TMP type checks
    string getException();
    void drainJobs();
    void* rawContext();   // Escape hatch for backend-specific code
}
```

**Typed array support**: `newUint8Array`, `setPropertyIndex`, and `getPropertyIndex` enable
native Uint8Array creation from the engine layer. This is used by `TextEncoder` to construct
results directly as typed arrays instead of building them in JS, yielding a **21x speedup**
on the QuickJS backend. `TextDecoder` uses a pure-JS UTF-8 decode path to allow JIT
optimization on JSC and V8 backends.

## Engine FFI Strategies

| Engine | API Style | D FFI | Shim | Callback Registration |
|--------|-----------|-------|------|----------------------|
| QuickJS | C API | extern(C) direct (498 LOC bindings) | None | `JS_NewCFunction(ctx, &fn, name, argc)` |
| JSC | C API + TMP bridge | extern(C) direct (289 LOC bindings) + 180 LOC `cppbindings.d` | None | `JSObjectMakeFunctionWithCallback(ctx, name, &fn)` |
| V8 | C++ only | extern(C) via shim (112 LOC bindings) | `vendor/v8shim/` (~1118 LOC total: 868 cpp + 129 header + 121 templates) | `dun_v8_new_function(ctx, &fn, name, data)` → FunctionTemplate trampoline |

### V8 C++ Shim Details

V8 has no stable C API. The shim (`vendor/v8shim/`, 868 LOC C++
+ 121 LOC templates + 129 LOC header) exposes **54** `dun_v8_*`
functions, refactored via `withContext<F>` to eliminate scope
guard boilerplate:

| Category | Functions | TMP Pattern |
|----------|-----------|-------------|
| Lifecycle | `isolate_new/dispose`, `context_new/free`, `version` | -- |
| Eval | `eval` (Script::Compile + Run) | `withContext<F>` |
| Values | `new_undefined/null/bool/int/uint/number/string/object/array/function/promise` | `withContext<F>` |
| Extract | `value_to_string/int/number/bool`, `free_string` | `withContext<F>` |
| Types | `value_is_undefined/null/bool/int/number/string/object/function/array` + batched `value_get_type` (single FFI call returns the tag) | `valueIsType<Tag>` → `isV8Type<Tag>` |
| Props | `get/set_property`, `get/set_property_index` (O(1) numeric keys), `set_prototype`, `global` | `withContext<F>` |
| Refs | `value_ref`, `value_unref` (ref-counted `v8::Global<Value>`) | -- |
| Errors | `get_exception`, `throw_error/type_error/range_error/value` | `withContext<F>` |
| Calls | `call` (invoke JS function from native) | `withContext<F>` |
| Microtasks | `has_pending_microtasks`, `drain_microtasks` | -- |
| GC | `collect_garbage` | -- |
| Buffers | `buffer_from_utf` (fused Buffer.from-utf8 hot path), `typed_array_data` | `withContext<F>` |
| Data | `set/get_context_data` | -- |
| Limits | `set_memory_limit`, `set_stack_limit` | -- |

### V8 14.x External::New Compatibility

V8 14.x changed `v8::External::New` to require an `ExternalPointerTypeTag` parameter,
breaking the 2-argument signature used in V8 12.x and earlier. The shim uses compat
macros to abstract across V8 versions:

```cpp
// vendor/v8shim/v8shim.h (or v8shim.cpp)
#if V8_MAJOR_VERSION >= 14
  #define DUN_EXTERNAL_NEW(isolate, ptr) \
      v8::External::New(isolate, ptr, v8::ExternalPointerTag::kExternalPointerNullTag)
  #define DUN_EXTERNAL_VALUE(ext) \
      ext->Value(v8::ExternalPointerTag::kExternalPointerNullTag)
#else
  #define DUN_EXTERNAL_NEW(isolate, ptr) v8::External::New(isolate, ptr)
  #define DUN_EXTERNAL_VALUE(ext)        ext->Value()
#endif
```

All uses of `v8::External` in the trampoline and native callback registration go
through `DUN_EXTERNAL_NEW` / `DUN_EXTERNAL_VALUE` so that the shim compiles against
both V8 12.x (Node.js 22 headers) and V8 14.9 (kassane/libv8).

### D extern(C++, "v8") Direct Bindings

For V8's all-static `V8` class (no vtable, safe to bind directly).
**Use `extern(C++, class) struct`** — C++ class without virtual
methods is a value type; D struct matches. Using D `class` (reference
type) silently mismatches the ABI by reserving a vtable slot the C++
side never participates in. See [`docs/research/custom-gc-v8-jsc.md`
§3.1](docs/research/custom-gc-v8-jsc.md) for the full type-system
mapping (value vs reference, vtable risk, template instantiations).

```d
extern(C++, "v8") {
    extern(C++, class) struct V8 {
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

| Aspect | Node.js 22 | Deno 2.7 | Bun 1.3 | **DunJS** |
|--------|------------|----------|---------|-----------|
| Language | C++ | Rust | Zig | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable: QuickJS-NG / JSC / V8** |
| TypeScript | `--experimental-strip-types` (erasable subset) | Built-in check+strip | Built-in transpile | **Stripping + persistent cache + `--typecheck`** |
| Engine FFI | Native C++ | rusty_v8 (Rust bindings) | C/C++ wrappers + Zig `extern fn ... callconv(.c)` | **extern(C) for all; C shim for V8 only** |
| Type-level safety | Manual | Borrow checker | Manual | **@safe / @trusted / DIP1000 `return scope` / DIP1038 `@mustuse`** |
| TMP Bridge | N/A | N/A | N/A | **C++ TMP ↔ D TMP (V8 + JSC)** |
| Event Loop | libuv | Tokio | io_uring | **epoll / kqueue / poll / io_uring** |
| Workers | Yes (V8) | Yes (V8) | Yes (JSC) | **Yes (all 3 backends)** |
| Permission | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:` (+ `node:` compat)** |
| Build System | gyp → cmake | cargo | zig build | **DUB + `build.d`** |
| ES2025 spec | 98/98 | 98/98 | 98/98 | **98/98 / 98/98 / 98/98** (QJS / JSC / V8) |
| Cold start | 27 ms | 42 ms | 11 ms | **27 / 27 / 22 ms** |
| Binary | 119 MB | 119 MB | 89 MB | **9.8 / 60 / 56 MB** |

Cold start: `time runtime -e ';'`, best of 15. Binary: stripped
release executables — DunJS QJS statically links QuickJS-NG
(small interpreter); JSC and V8 backends embed the full WebKit /
V8 engine libraries. Triple values are always QJS / JSC / V8.

### Performance Benchmarks

Feature benchmarks (`tests/benchmarks/feature_bench.js`, 25 tests,
release builds, ops/sec — median of 3 runs):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| **DunJS JSC** | **500M** | **1.00x** (par with Bun) |
| Bun 1.3.14 | 533M | 1.00x |
| Node.js 22.22.2 | 162M | 0.30x |
| DunJS V8 | 151M | 0.28x |
| DunJS QuickJS | 20M | 0.04x (interpreter-only) |

Framework benchmarks (`tests/benchmarks/framework_bench.js`, 39
tests, release builds, ops/sec — median of 3 runs):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| **DunJS JSC** | **266M** | **0.89x** |
| Bun 1.3.14 | 250M | 1.00x |
| Node.js 22.22.2 | 169M | 0.68x |
| DunJS V8 | 163M | 0.65x |
| DunJS QuickJS | 16M | 0.06x |

npm compat: **145/145** pass across all 6 runtimes (Bun, Node, Deno, dun-v8, dun-jsc, dun-qjs; full parity).

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
| V8 source | kassane/libv8 (V8 15.0.91) | Pre-built monolith, LDC --link-internally for CREL relocations |
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
|   +-- fixtures/       # 63 test scripts (JS, MJS, TS)
|   |   +-- hello.js, types.js, console_methods.js    # Core JS
|   |   +-- promises.js, promises_advanced.js          # Async
|   |   +-- es2023.js, closures.js, iterators.js       # ES2023+
|   |   +-- classes.js, regex.js, json_parsing.js      # Language features
|   |   +-- error_handling.js                          # Error handling
|   |   +-- typescript.ts, realworld_ts_library.ts     # TypeScript
|   |   +-- timers.js, phase2.js, phase2_rejection.js  # Event loop
|   |   +-- async_io.mjs                               # Async I/O
|   |   +-- module_esm.mjs, module_cjs.js, module_chain.js  # Modules
|   |   +-- json_pipeline.js, npm_compat.js, npm_real.js     # npm
|   |   +-- fs_ops.mjs, fs_expanded.js, path_ops.mjs  # Filesystem
|   |   +-- crypto_ops.mjs, stat_file.js, env_access.js     # Platform
|   |   +-- buffer_api.js, event_emitter.js            # Node APIs
|   |   +-- url_api.js, os_api.js, process_api.js      # Node APIs
|   |   +-- http2_api.js, child_process_api.js         # Node APIs
|   |   +-- stream_api.js, zlib_api.js, dns_api.js     # Node APIs
|   |   +-- ws_api.js, sqlite_api.js                   # Node APIs
|   |   +-- util_api.js, assert_api.js                 # Node APIs
|   |   +-- querystring_api.js                         # Node APIs
|   |   +-- workers.js, workers_worker.js              # Workers (all backends)
|   |   +-- deno_compat.js                             # Deno compat
|   |   +-- perm_deny_read.js, perm_deny_write.js      # Security
|   |   +-- sample.test.js, sample.bench.js            # Test/bench runners
|   |   +-- web_apis.js                                 # 91 Web API checks
|   |   +-- fetch_response.js                          # fetch() Response object (19 checks)
|   |   +-- import_meta.mjs                            # import.meta (all backends, 6 checks)
|   |   +-- realworld_*.js/.mjs/.ts (7 scenarios)      # End-to-end
|   +-- expected/       # 62 expected stdout files
|   +-- fixtures/lib/   # Shared modules for require tests
+-- benchmarks/         # Cross-runtime benchmarks (13 files)
|   +-- feature_bench.js      # 25 cross-runtime perf tests
|   +-- framework_bench.js    # 39 framework pattern tests
|   +-- react_compat.js       # 81 React/framework compat checks
|   +-- react_bench.js        # React pattern perf benchmark
|   +-- npm_compat_test.js    # 145 simulated npm package tests
|   +-- stress.js             # 240 comprehensive JS tests
|   +-- npm_stress.js         # 189 real npm package tests
|   +-- sqlite_bench.js       # SQLite perf benchmark
|   +-- realworld.js          # 16 real-world benchmarks

source/dun/engine/
+-- test.d              # ~50 BDD-style engine contract tests
+-- fuzz.d              # ~71 fuzz/stress tests

source/dun/ts/
+-- strip.d             # 20 TypeScript stripper tests (inline)

source/dun/security/
+-- test.d              # 27 permission registry tests (inline)
+-- cve_db.d            # 8 CVE audit tests (semver, vulnerability checks)
```

Test pattern inspired by Node.js standalone scripts: run fixture, compare stdout to expected file.

### HTTP Stress Benchmarks

```
tests/benchmarks/http_bench/
+-- stress.sh                # Cross-runtime wrk benchmark runner (9 endpoints)
+-- server_stress.js         # DunJS server (plaintext, json, users API, compute, transaction, middleware, echo)
+-- server_stress_node.js    # Node.js server (identical endpoints)
+-- server_stress_bun.js     # Bun server (Bun.serve API)
+-- server_stress_deno.ts    # Deno server (Deno.serve API)
```

HTTP server optimizations: TCP_NODELAY, buffered single-write response, CTFE pre-computed
status lines, connection slot pooling, fd→connId hashmap (O(1) lookup), JS-level dispatch
for reduced FFI overhead, lazy header loading, MSG_NOSIGNAL, EOF detection with RAII cleanup.
**QuickJS 158/158, V8 158/158, JSC 157/158 + 1 SKIP** (`bun_v7_additions` — JSC handle-pressure conflict with `deno_deploy_compat`; cumulative v1.1.5 → v1.1.20 JSC handle-leak fix campaign reduced but didn't eliminate the per-request listener-chain leak that tips the threshold).
