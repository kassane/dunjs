# DunJS Architecture

## Overview

DunJS is a 7-layer JavaScript runtime with a **pluggable engine architecture**
(IJSEngine interface), an eventcore-based event loop, and a Deno-inspired permission system.

Three backends are fully functional: QuickJS-NG (default), JavaScriptCore, and V8.
All 12 integration tests pass identically on all 3 engines.

Reference: [Bun's Zig→Rust port](https://github.com/oven-sh/bun/pull/30412) — modular
workspace with `bun_jsc` engine layer, `*_jsc` suffix pattern for engine-specific modules,
RAII wrappers, and pointer safety auditing.

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    JavaScript User Code                       │
│              (ES2023+ modules, async/await, etc.)             │
├──────────────────────────────────────────────────────────────┤
│  Layer 7: CLI & REPL                                         │
│  ┌─────────┐ ┌──────┐ ┌──────┐ ┌─────────┐                  │
│  │  args   │ │ repl │ │ run  │ │   fmt   │                  │
│  └─────────┘ └──────┘ └──────┘ └─────────┘                  │
├──────────────────────────────────────────────────────────────┤
│  Layer 6: Runtime API (Globals)                              │
│  ┌─────────┐ ┌────────────┐ ┌─────────┐ ┌──────────┐       │
│  │ console │ │ timers_api │ │ process │ │ encoding │       │
│  │ (all 3) │ │            │ │         │ │          │       │
│  └─────────┘ └────────────┘ └─────────┘ └──────────┘       │
├──────────────────────────────────────────────────────────────┤
│  Layer 5: Module System                                      │
│  ┌──────────┐ ┌────────┐ ┌─────┐ ┌──────────┐              │
│  │ resolver │ │ loader │ │ esm │ │ builtins │              │
│  └──────────┘ └────────┘ └─────┘ └──────────┘              │
├──────────────────────────────────────────────────────────────┤
│  Layer 4: Built-in Modules                                   │
│  ┌────┐ ┌──────┐ ┌─────┐ ┌──────┐ ┌────────┐ ┌─────┐      │
│  │ fs │ │ path │ │ net │ │ http │ │ crypto │ │ url │      │
│  └────┘ └──────┘ └─────┘ └──────┘ └────────┘ └─────┘      │
├──────────────────────────────────────────────────────────────┤
│  Security: Permission System (cross-cutting)                 │
│  ┌─────────────┐ ┌─────────┐ ┌────────┐                     │
│  │ permissions │ │ sandbox │ │ policy │                     │
│  └─────────────┘ └─────────┘ └────────┘                     │
├──────────────────────────────────────────────────────────────┤
│  Layer 3: Event Loop & Async Runtime                         │
│  ┌───────────┐ ┌────────┐ ┌────────────┐ ┌───────┐         │
│  │ eventloop │ │ timers │ │ microtasks │ │ tasks │         │
│  └───────────┘ └────────┘ └────────────┘ └───────┘         │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: JS Engine Abstraction                              │
│  ┌───────────────────────────────────────────────┐           │
│  │  IJSEngine (iface.d)                          │           │
│  │  ┌──────────────┬──────────────┬──────────┐   │           │
│  │  │ quickjs/     │  jsc/        │  v8/     │   │           │
│  │  │ backend.d    │ backend.d    │ backend.d│   │           │
│  │  │ bindings.d   │ bindings.d   │ bindings.d   │           │
│  │  │ cimport.c    │ cppbindings.d│ cppbindings.d│           │
│  │  │ runtime.d    │              │          │   │           │
│  │  │ context.d    │              │ v8shim/  │   │           │
│  │  │ value.d      │              │ (C++ shim)   │           │
│  │  └──────────────┴──────────────┴──────────┘   │           │
│  └───────────────────────────────────────────────┘           │
├──────────────────────────────────────────────────────────────┤
│  Layer 1: Platform Abstraction                               │
│  ┌────────┐ ┌───────────┐ ┌────┐ ┌───────┐                  │
│  │ memory │ │ threading │ │ io │ │ paths │                  │
│  └────────┘ └───────────┘ └────┘ └───────┘                  │
├──────────────────────────────────────────────────────────────┤
│  Vendor: Engine (C/C++) │ eventcore (D) │ OS (POSIX/Win32)  │
└──────────────────────────────────────────────────────────────┘
```

## Engine Abstraction Pattern

```
  Upper Layers (app, runtime, builtins, loop)
            │
            ▼
  ┌─────────────────────┐
  │   IJSEngine          │  interface in iface.d
  │   - eval()           │
  │   - newString()      │
  │   - getProperty()    │
  │   - drainJobs()      │
  │   - ...              │
  └──────────┬──────────┘
             │ implements
    ┌────────┼────────┐
    ▼        ▼        ▼
 QuickJS    JSC      V8
 Engine   Engine   Engine
    │        │        │
    ▼        ▼        ▼
 extern(C)  extern(C)  extern(C)
 quickjs.h  JSC C API  v8shim.cpp
```

`createEngine()` factory returns the selected backend (compile-time via
`version(EngineQuickJS)`, `version(EngineJSC)`, `version(EngineV8)`).
Backends live in `source/dun/engine/<name>/` and only they import
engine-specific C/C++ bindings.

## Data Flow: Script Execution

```
CLI (args.d) ──parse──> CliConfig
                              │
                    ┌─────────▼──────────┐
                    │ createEngine()      │  IJSEngine factory
                    │ engine.initialize() │  EngineConfig
                    │ installGlobals()    │  console (per-backend)
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.eval(source) │  Evaluates JS source
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.drainJobs()  │  Promise microtasks
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.shutdown()   │  Cleanup
                    └────────────────────┘
```

## Console Implementation (per-backend)

Each backend uses its native callback mechanism to implement `console.*`:

```
                    installGlobals()
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    EngineQuickJS    EngineJSC        EngineV8
          │               │               │
    console.d:        globals.d:       globals.d:
    JS_NewCFunction   JSObjectMake     dun_v8_new_function
    → core.stdc.stdio FunctionWith     → FunctionTemplate
                      Callback         → v8FunctionTrampoline
                      → std.stdio      → std.stdio
```

## V8 Native Function Trampoline

V8 has no C API — the C++ shim uses FunctionTemplate with an extern "C" trampoline:

```
D function pointer (DunV8NativeCallback)
          │
          │ stored in DunV8FunctionData struct
          ▼
v8::External wraps pointer to FunctionData
          │
          │ passed as data to FunctionTemplate
          ▼
v8FunctionTrampoline (C++ function)
          │
          │ extracts DunV8FunctionData* from External
          │ wraps argv in DunV8Value* array
          │ calls D callback via function pointer
          ▼
D callback executes, returns DunV8Value*
          │
          │ trampoline unwraps result
          ▼
V8 receives return value via FunctionCallbackInfo::GetReturnValue()
```

## Memory Management Bridge

```
┌─────────────────────┐        ┌─────────────────────────────┐
│   D World (GC)      │        │  Engine World (C/C++)       │
│                     │        │                             │
│  IJSEngine    ──────┼─call──>│  QuickJS: extern(C) direct  │
│                     │        │  JSC: extern(C) to C API    │
│                     │        │  V8: extern(C) to C++ shim  │
│                     │        │                             │
│  JSHandle     ──────┼─map───>│  QJS: JSValue (tagged union) │
│                     │        │  JSC: JSValueRef (opaque ptr)│
│                     │        │  V8: DunV8Value* (ref-counted)│
│                     │        │                             │
│  DunState*    <─────┼─opaque─│  QJS: JS_GetContextOpaque   │
│                     │        │  JSC: opaquePtr field        │
│                     │        │  V8: dun_v8_get_context_data │
│                     │        │                             │
│  GC.addRoot() ──────┼─pin───>│  Engine class opaque         │
│  @trusted block ────┼─call──>│  eval, call                  │
│                     │        │                             │
└─────────────────────┘        └─────────────────────────────┘
```

### Value Lifetime Rules

| Engine | Own | Borrow | Release |
|--------|-----|--------|---------|
| QuickJS | `JS_Eval`, `JS_NewString`, etc. | `argv[]` in callbacks | `JS_FreeValue(ctx, val)` |
| JSC | All JSValueRef are GC-managed | Same refs | `JSValueUnprotect(ctx, val)` |
| V8 | `wrapValue` → `DunV8Value*` (ref=1) | N/A | `dun_v8_value_unref` (ref--) |

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
                        │
                        ▼
               extern(C) jsReadFileSync(ctx, ...)
                        │
                        ▼
               DunState* state = getContextOpaque()
                        │
                        ▼
               state.permissions.check(Permission.read, "/etc/passwd")
                        │
                ┌───────┴───────┐
                │               │
              DENIED          GRANTED
                │               │
                ▼               ▼
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
| V8 | C++ only | extern(C) via shim | vendor/v8shim/ (~540 LOC) | `dun_v8_new_function(ctx, &fn, name, data)` → FunctionTemplate |

### V8 C++ Shim Details

V8 has no stable C API. The shim (`vendor/v8shim/v8shim.cpp`) exposes ~37 functions:

| Category | Functions |
|----------|-----------|
| Lifecycle | `isolate_new`, `isolate_dispose`, `context_new`, `context_free` |
| Eval | `eval` (with Script::Compile + Run, Context::Scope) |
| Values | `new_undefined/null/bool/int/number/string/object/array/function` |
| Extract | `value_to_string/int/number/bool`, `free_string` |
| Types | `value_is_undefined/null/bool/number/string/object/function/array` |
| Props | `get_property`, `set_property`, `global` |
| Refs | `value_ref`, `value_unref` (ref-counted `v8::Global<Value>`) |
| Errors | `get_exception`, `throw_error/type_error/range_error` |
| Calls | `call` (invoke JS function from native) |
| Microtasks | `has_pending_microtasks`, `drain_microtasks` |
| Data | `set_context_data`, `get_context_data` |
| Limits | `set_memory_limit`, `set_stack_limit` |

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
that require linking against V8's C++ objects — these MUST go through the C shim.

## Comparison with Other Runtimes

| Aspect | Node.js | Deno | Bun | **DunJS** |
|--------|---------|------|-----|-----------|
| Language | C++ | Rust | Zig→Rust | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable (QuickJS, JSC, V8)** |
| Engine FFI | Native C++ | rusty_v8 (Rust bindings) | Zig extern(C++) | **extern(C) + C shim** |
| Event Loop | libuv | Tokio | io_uring | **eventcore** |
| Permission | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |
| Build System | gyp → cmake | cargo | zig build | **DUB + build.d** |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| JS Engine | Pluggable (IJSEngine) | Swap backends without rewriting upper layers |
| Default backend | QuickJS-NG | Pure C API, ES2023, easy extern(C), MIT license |
| Tier 2 backends | JSC + V8 | JIT performance for production use |
| C FFI | extern(C) | Auditable bindings, no external tooling |
| C++ FFI (V8) | C shim + extern(C) | V8 templates/RAII require C++ wrapper |
| C++ FFI (JSC) | extern(C) public API | JSC has a stable C API (JSObjectRef) |
| C++ FFI (direct) | extern(C++, "v8") | Only for static-method classes (no vtable) |
| V8 headers | Vendored from Node.js | Eliminate libv8-dev compile dependency |
| Event loop | eventcore | D-native, proactor pattern, cross-platform |
| Build system | DUB (JSON) | Standard D tooling, configurations per engine |
| Build orchestrator | build.d | CMake, curl downloads, toolchain detection |
| Async model | Callback loop + Promise jobs | Matches engine internal async handling |
| Permission | Default deny-all | Security-first, Deno's proven model |
| RAII wrappers | D structs with `~this()` | Deterministic cleanup, zero-cost |
| Engine selection | `dub build -c quickjs/jsc/v8` | DUB configurations switch backends |

## Testing Architecture

```
tests/
├── integration/
│   ├── fixtures/       # 13 JS test scripts
│   │   ├── hello.js           # Basic smoke test
│   │   ├── types.js           # typeof for all JS types
│   │   ├── console_methods.js # log/info/debug, multiple args
│   │   ├── promises.js        # Promise + async/await
│   │   ├── promises_advanced.js # all/race/any, async errors
│   │   ├── es2023.js          # findLast, optional chaining, Array.at
│   │   ├── error_handling.js  # try/catch, Error subtypes, Error.cause
│   │   ├── closures.js        # Closures, generators, destructuring
│   │   ├── iterators.js       # Map, Set, WeakRef, Array.from
│   │   ├── json_parsing.js    # JSON parse/stringify, replacer/reviver
│   │   ├── classes.js         # Inheritance, private fields, valueOf
│   │   ├── regex.js           # Named groups, matchAll, flags
│   │   └── timers.js          # setTimeout/setInterval (Phase 2)
│   └── expected/       # 12 expected stdout files (1 skipped: timers)
└── bench/              # Benchmarks

source/dun/engine/
├── test.d              # 46 BDD-style engine contract tests
└── fuzz.d              # Stress/fuzz tests (rapid create/destroy, exception recovery)
                        # Total: 49 unit tests
```

Test pattern inspired by Node.js standalone scripts: run fixture, compare stdout to expected file.
All 12 integration tests pass identically on QuickJS, JSC, and V8.
