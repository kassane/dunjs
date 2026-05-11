# CLAUDE.md - DunJS Development Guide

## Project Overview

DunJS (`dun`) is a secure JavaScript runtime written in D, inspired by Deno, Bun, and Node.js.
It uses a **pluggable engine architecture** (IJSEngine interface) with backends for
QuickJS-NG (default), JavaScriptCore (Tier 2), or V8 (Tier 2), and **eventcore** for async I/O.

**Reference**: Architecture inspired by [Bun's Zig→Rust port](https://github.com/oven-sh/bun/pull/30412)
— modular crate structure, engine abstraction layer, RAII wrappers, safety auditing.

## Build Commands

```sh
# Prerequisites: D compiler (LDC >= 1.42.0 / DMD >= 2.112.1 / GDC >= 15), C compiler, CMake
ldc2 -run build.d --backend=quickjs   # Download + build vendor deps

dub build                            # Debug build (default: QuickJS backend)
dub build -c quickjs                 # Explicit QuickJS backend
dub build -c jsc                     # JavaScriptCore backend
dub build -c v8                      # V8 backend (via C++ shim)
dub test -c unittest                 # Run BDD-style engine contract tests (49 tests)
dub build -b release                 # Release build (optimized)
./dun run script.js                  # Run a JavaScript file
./dun repl                           # Interactive REPL
./dun eval "1+1"                     # Evaluate inline JS
```

### Minimum Compiler Versions

| Compiler | Minimum Version | Frontend | LLVM/GCC |
|----------|----------------|----------|----------|
| LDC      | 1.42.0         | 2.112.1  | LLVM 21  |
| DMD      | 2.112.1        | —        | —        |
| GDC      | GCC 15         | 2.108    | GCC 15   |

## Architecture (7 Layers)

```
Layer 7: CLI & REPL           source/dun/cli/
Layer 6: Runtime API           source/dun/runtime/     (console, timers, process)
Layer 5: Module System         source/dun/modules/     (ES modules, resolver, loader)
Layer 4: Built-in Modules      source/dun/builtins/    (dun:fs, dun:path, dun:net, ...)
Layer 3: Event Loop            source/dun/loop/        (eventcore, timer wheel, microtasks)
Layer 2: JS Engine Abstraction source/dun/engine/      (IJSEngine interface + backends)
Layer 1: Platform Abstraction  source/dun/platform/    (memory, threading, OS I/O)
Cross:   Security              source/dun/security/    (permissions, sandbox)
```

### Engine Abstraction (Layer 2)

```
source/dun/engine/
├── iface.d          # IJSEngine interface, JSHandle, JSResult, EngineConfig
├── package.d        # Re-exports iface + factory
├── test.d           # BDD-style engine contract tests (46 cases)
├── fuzz.d           # Fuzz/stress tests (49 total with test.d)
├── quickjs/         # QuickJS-NG backend
│   ├── backend.d    # QuickJSEngine : IJSEngine
│   ├── bindings.d   # extern(C) declarations for quickjs.h
│   ├── runtime.d    # RAII wrapper for JSRuntime*
│   ├── context.d    # RAII wrapper for JSContext*
│   ├── value.d      # RAII wrapper for JSValue
│   ├── function_bind.d
│   ├── exceptions.d
│   └── package.d
├── jsc/             # JavaScriptCore backend (fully functional)
│   ├── backend.d    # JSCEngine : IJSEngine
│   ├── bindings.d   # extern(C) declarations for JSC C API (~240 lines)
│   ├── cppbindings.d # experimental extern(C++, "JSC") bindings
│   └── package.d
└── v8/              # V8 backend (fully functional, via C shim)
    ├── backend.d    # V8Engine : IJSEngine
    ├── bindings.d   # extern(C) declarations for v8shim (~90 lines)
    ├── cppbindings.d # extern(C++, "v8") static-method bindings
    └── package.d

vendor/v8shim/       # V8 C++ shim (~540 lines)
├── v8shim.h         # extern "C" header
└── v8shim.cpp       # C++ implementation (FunctionTemplate trampoline, Context::Scope)
```

Upper layers use `IJSEngine` — only code inside `engine/<backend>/` touches raw engine APIs.

### Runtime Globals (Layer 6)

Console is implemented per-backend in `source/dun/runtime/globals.d`:

| Method | QuickJS | JSC | V8 | Output |
|--------|---------|-----|-----|--------|
| `console.log` | extern(C) → core.stdc.stdio | JSObjectMakeFunctionWithCallback → std.stdio | v8shim trampoline → std.stdio | stdout |
| `console.info` | alias → log | alias → log | alias → log | stdout |
| `console.debug` | alias → log | alias → log | alias → log | stdout |
| `console.warn` | extern(C) → stderr | callback → std.stdio stderr | trampoline → std.stdio stderr | stderr |
| `console.error` | extern(C) → stderr | callback → std.stdio stderr | trampoline → std.stdio stderr | stderr |
| `console.assert` | extern(C) → stderr | callback → std.stdio stderr | trampoline → std.stdio stderr | stderr |

## Key Development Patterns

### 1. Engine-Agnostic Code Uses IJSEngine

```d
import dun.engine.iface : IJSEngine, createEngine, EngineConfig;

auto engine = createEngine();  // Default backend
engine.initialize(EngineConfig(memoryLimit, stackSize));

auto result = engine.eval("1 + 1", "<eval>");
if (!result.isError)
    writeln(engine.extractString(result.value));
```

### 2. Backend-Specific Code (extern(C) callbacks)

Each backend registers native functions using its own callback signature:

**QuickJS** — `extern(C) JSValue(JSContext*, JSValueConst, int, JSValueConst*)`:
```d
extern(C) JSValue myFunc(JSContext* ctx, JSValueConst this_val,
                          int argc, JSValueConst* argv) nothrow {
    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    // ...
}
```

**JSC** — `extern(C) JSValueRef(JSContextRef, JSObjectRef, JSObjectRef, size_t, const(JSValueRef)*, JSValueRef*)`:
```d
extern(C) JSValueRef myFunc(JSContextRef ctx, JSObjectRef func,
    JSObjectRef thisObject, size_t argc, const(JSValueRef)* args,
    JSValueRef* exception) nothrow {
    // ...
}
```

**V8** — `extern(C) DunV8Value*(DunV8Context*, DunV8Value*, int, DunV8Value**, void*)`:
```d
extern(C) DunV8Value* myFunc(DunV8Context* ctx, DunV8Value* thisVal,
    int argc, DunV8Value** argv, void* data) nothrow {
    // ...
}
```

### 3. RAII Wrappers for Engine Resources

- `QuickJSEngine` wraps `JSRuntime*` + `JSContext*` — freed in `shutdown()`
- `JSVal` wraps `JSValue` — calls `JS_FreeValue` in destructor
- V8 values use `dun_v8_value_ref` / `dun_v8_value_unref` (ref-counted via C++ shim)
- JSC values use `JSValueProtect` / `JSValueUnprotect` (prevent GC collection)
- All RAII types are `@disable this(this)` (non-copyable) or implement postblit

### 4. Permission Checks Before Every I/O Operation

```d
auto state = cast(DunState*) engine.getContextOpaque();
if (!state.permissions.check(Permission.read, path))
    return engine.throwTypeError("Requires --allow-read");
```

### 5. Memory Safety Annotations

- `@safe`: Default for pure computation
- `@trusted`: Boundary between D safe code and C FFI (narrowest scope)
- `@system`: Only in platform/ layer for raw OS calls
- `@nogc`: Hot-path allocations, extern(C) callbacks where possible
- `nothrow`: ALL extern(C) callbacks

### 6. Event Loop Phases (per tick)

1. Drain microtask queue (Promise jobs + queueMicrotask)
2. Process expired timers (setTimeout/setInterval)
3. Drain microtasks generated by timers
4. Poll I/O via eventcore (blocks until I/O or next timer deadline)
5. Drain microtasks generated by I/O callbacks

## C/C++ FFI Reference

### ImportC vs dpp vs dstep

| Criteria | ImportC | dpp | dstep |
|----------|---------|-----|-------|
| **Use case** | Compile C sources directly | `#include` C/C++ in `.dpp` | Batch header→D binding |
| **Macro support** | Partial (function-like) | Full (via C preprocessor) | `#define` only |
| **C++ support** | No | Limited | No |
| **Compile-time impact** | High (compiles C) | Medium (preprocess) | None (pre-generated) |
| **DUB integration** | Native (`cImportPaths`) | Via `dub run dpp` | Generated modules |
| **libclang required** | No | Yes (v6+) | Yes |
| **Best for** | Small/medium C libs | Complex C headers + macros | One-shot C binding gen |

**Real-world examples**: sokol-d uses gen_d.py + ImportC, bdwgc-d uses ImportC via DUB.

### C++ FFI with D

```d
// Direct C++ interop via extern(C++) — only safe for static methods
extern(C++, "v8") {
    extern class V8 {
    static:
        const(char)* GetVersion();
        bool Initialize();
        bool Dispose();
        void InitializePlatform(void* platform);
        void DisposePlatform();
    }
}

// Instance methods generate vtable entries → linker errors without C++ objects
// Use C shim (vendor/v8shim/) for all value operations instead

// dlang/stdcpp provides: string, string_view, memory (unique_ptr), allocator
import stdcpp.allocator;
```

### Engine FFI Strategies

| Engine | API | FFI Approach | Lines |
|--------|-----|-------------|-------|
| QuickJS | C API (quickjs.h) | extern(C) — manual D bindings, audited via ImportC `-H` | ~400 |
| JSC | C API (JSObjectRef) | extern(C) — straightforward, ~80 functions | ~240 |
| JSC | C++ internals | extern(C++, "JSC") — experimental cppbindings.d | ~30 |
| V8 | C++ only | extern(C) via C shim (vendor/v8shim/) | ~540 C++ + ~90 D |
| V8 | C++ internals | extern(C++, "v8") — static methods only (V8 class) | ~50 |

### V8 C++ Shim Architecture

```
D code (backend.d / globals.d)
  │ extern(C) calls
  ▼
vendor/v8shim/v8shim.cpp
  │ FunctionTemplate + trampoline for native callbacks
  │ Context::Scope on every operation (V8 10.x requirement)
  │ DunV8Value* ref-counted wrappers around v8::Global<Value>
  ▼
V8 C++ API (v8.h, from Node.js headers)
```

Key shim patterns:
- **FunctionTemplate trampoline**: D callback → `DunV8FunctionData*` in `v8::External` → `v8FunctionTrampoline` → D function pointer
- **Context::Scope everywhere**: V8 10.x (Node 18) requires `v8::Context::Scope` for nearly all operations
- **Headers vendored from Node.js**: `node-v22.15.0-headers.tar.gz` → `vendor/v8/include/`

## Testing

### Unit Tests (49 tests)

```sh
dub test -c unittest    # BDD-style engine contract + fuzz tests
```

- `source/dun/engine/test.d` — 46 engine contract tests (eval, types, properties, exceptions, promises)
- `source/dun/engine/fuzz.d` — stress tests (rapid create/destroy, string stress, exception recovery)

### Integration Tests (12 tests × 3 backends)

```sh
# Run against a specific backend
dub build -c quickjs && ./tests/integration/run.sh
```

| Test | Description | Engines |
|------|-------------|---------|
| `hello` | Basic console.log | All 3 |
| `types` | typeof checks for all JS types | All 3 |
| `console_methods` | log/info/debug, multiple args, types | All 3 |
| `promises` | Promise + async/await | All 3 |
| `promises_advanced` | Promise.all/race/any, async error handling | All 3 |
| `es2023` | findLast, optional chaining, nullish coalescing, Array.at, Object.hasOwn | All 3 |
| `error_handling` | try/catch, Error subtypes, Error.cause, finally, custom errors | All 3 |
| `closures` | Closures, IIFE, block scoping, generators, destructuring, symbols | All 3 |
| `iterators` | Map, Set, WeakRef, for...of, Array.from, method chains | All 3 |
| `json_parsing` | JSON parse/stringify, replacer, reviver | All 3 |
| `classes` | Inheritance, static, private fields, computed props, valueOf | All 3 |
| `regex` | Match, named groups, replace, split, matchAll | All 3 |
| `timers` | setTimeout/setInterval (requires event loop) | Skipped |

Test pattern: fixtures in `tests/integration/fixtures/*.js`, expected stdout in `tests/integration/expected/*.txt`.

## Security Model

- **Default deny**: All I/O operations require explicit permission flags
- **CLI flags**: `--allow-read`, `--allow-write`, `--allow-net`, `--allow-env`, `--allow-run`, `--allow-all`
- **Scoped**: `--allow-read=./data,/tmp` grants read only to those paths
- **Deny overrides allow**: `--deny-write=/etc` always wins
- **Path canonicalization**: Resolve symlinks before permission checks
- **Memory limits**: Engine-level heap cap (default 256MB)
- **Execution timeout**: Engine interrupt handler for infinite loop protection

## Code Style

- Module naming: `dun.layer.module` (e.g., `dun.engine.quickjs.bindings`)
- 4-space indentation
- D naming conventions: `camelCase` for functions/variables, `PascalCase` for types
- No `auto` for public API return types — always explicit
- Prefer `@safe` by default, mark `@trusted` at narrowest scope
- Every `extern(C)` callback must be `nothrow`

## FFI Bridge: D ↔ Engine Memory Rules

1. **Engine owns JS values.** Every value returned by the engine is either owned (must be freed) or borrowed. RAII wrappers handle this.
2. **D GC must not collect objects referenced by the engine.** Pin with `GC.addRoot` / `GC.removeRoot`.
3. **Hot paths use `@nogc`.** `extern(C)` callbacks must be `nothrow`. Mark `@nogc` where possible.
4. **Custom allocator.** Use engine-specific allocator hooks to track heap size and enforce `--max-memory`.

## Phased Roadmap

| Phase | Goal | Key Deliverable | Status |
|-------|------|-----------------|--------|
| 1 (MVP) | `dun run hello.js` | Engine abstraction + console + CLI | **Done** |
| 1b | Multi-engine | JSC + V8 backends fully functional | **Done** |
| 2 | Async works | Event loop + timers + Promises | In progress |
| 3 | Real scripts | Module system + fs/path/net/crypto | Planned |
| 4 | Secure by default | Permission system (deny-all) | Planned |
| 5 | DX polish | REPL + colored errors + stack traces | Planned |
| 6 | Performance | io_uring, workers, HTTP server, npm compat | Planned |
