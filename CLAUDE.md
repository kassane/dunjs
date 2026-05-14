# CLAUDE.md - DunJS Development Guide

## Project Overview

DunJS (`dun`) is a secure JavaScript/TypeScript runtime written in D, inspired by Deno, Bun, and Node.js.
It uses a **pluggable engine architecture** (IJSEngine interface) with backends for
QuickJS-NG (default), JavaScriptCore (Tier 2), or V8 (Tier 2), with a cross-platform I/O poller (epoll/kqueue/poll).

**Reference**: Architecture inspired by [Bun's Zig->Rust port](https://github.com/oven-sh/bun/pull/30412)
-- modular crate structure, engine abstraction layer, RAII wrappers, safety auditing.

## Build Commands

```sh
# Prerequisites: D compiler (LDC >= 1.42.0 / DMD >= 2.112.1 / GDC >= 15), C compiler, CMake
ldc2 -run build.d --backend=quickjs   # Download + build vendor deps

dub build                            # Debug build (default: QuickJS backend)
dub build -c quickjs                 # Explicit QuickJS backend
dub build -c jsc                     # JavaScriptCore backend
dub build -c v8                      # V8 backend (via C++ shim)
dub test -c unittest                 # Run all unit tests (engine + TS + security)
dub build -b release                 # Release build (optimized)
dub build -c quickjs -b asan         # AddressSanitizer build (memory safety audit)
DFLAGS="--fsanitize=address" dub build -c quickjs  # Alternative ASan via DFLAGS
./dun run script.js                  # Run a JavaScript file
./dun run script.ts                  # Run a TypeScript file (type stripping)
./dun repl                           # Interactive REPL
./dun eval "1+1"                     # Evaluate inline JS
./dun audit                          # Scan node_modules for CVEs
./dun install pkg --audit=block      # Block critical/high CVE packages
./dun test                           # Run test files (*.test.{js,ts}, *_test.{js,ts})
./dun test mytest.ts --filter=name   # Run specific test with filter
./dun bench                          # Run benchmarks (*.bench.{js,ts})
./dun init my-project                # Initialize a new project
./dun fmt                            # Format JavaScript/TypeScript files
./dun clean                          # Remove .dun/ cache and node_modules/
```

### Minimum Compiler Versions

| Compiler | Minimum Version | Frontend | LLVM/GCC |
|----------|----------------|----------|----------|
| LDC      | 1.42.0         | 2.112.1  | LLVM 21  |
| DMD      | 2.112.1        | --       | --       |
| GDC      | GCC 15         | 2.108    | GCC 15   |

## Architecture (7 Layers + Cross-Cutting)

```
Layer 7: CLI & REPL           source/dun/cli/
Layer 6: Runtime API           source/dun/runtime/     (console, timers, process, Deno.*)
Layer 5: Module System         source/dun/modules/     (ES modules, resolver, loader, npm installer)
Layer 4: Built-in Modules      source/dun/builtins/    (dun:fs, dun:path, dun:net, dun:http, dun:http2, dun:http3, dun:os, dun:buffer, dun:events, dun:url, dun:zlib, dun:dns, dun:ws, dun:child_process, dun:stream, dun:sqlite, fetch)
Layer 3: Event Loop            source/dun/loop/        (epoll/kqueue/poll, timer wheel, microtasks)
Layer 2: JS Engine Abstraction source/dun/engine/      (IJSEngine interface + backends)
Layer 1: Platform Abstraction  source/dun/platform/    (memory, threading, OS I/O, arena allocator)
Cross:   TypeScript            source/dun/ts/          (type stripping for .ts/.mts/.cts)
Cross:   Security              source/dun/security/    (permissions, CVE audit, sandbox, 38 tests)
```

### Engine Abstraction (Layer 2)

```
source/dun/engine/
+-- iface.d          # IJSEngine interface, JSHandle, JSResult, EngineConfig
                     #   newUint8Array, setPropertyIndex, getPropertyIndex, isArray, getArrayLength
+-- callbacks.d      # Global NativeCallback registry (register/get by slot ID)
+-- package.d        # Re-exports iface + factory
+-- test.d           # BDD-style engine contract tests (~50 cases)
+-- fuzz.d           # Fuzz/stress tests (~50 cases)
+-- quickjs/         # QuickJS-NG backend
|   +-- backend.d    # QuickJSEngine : IJSEngine
|   +-- bindings.d   # extern(C) declarations for quickjs.h
|   +-- runtime.d    # RAII wrapper for JSRuntime*
|   +-- context.d    # RAII wrapper for JSContext*
|   +-- value.d      # RAII wrapper for JSValue
|   +-- function_bind.d
|   +-- exceptions.d
|   +-- package.d
+-- jsc/             # JavaScriptCore backend (fully functional)
|   +-- backend.d    # JSCEngine : IJSEngine (uses JSCTypeChecks dispatch)
|   +-- bindings.d   # extern(C) declarations for JSC C API (~290 lines)
|   +-- cppbindings.d # D TMP bridge (JSCTypeTag, JSCTypeChecks, getType)
|   +-- package.d     #   + experimental extern(C++, "JSC") bindings
+-- v8/              # V8 backend (fully functional, via C shim)
    +-- backend.d    # V8Engine : IJSEngine (uses V8TypeChecks dispatch)
    +-- bindings.d   # extern(C) declarations for v8shim (~90 lines)
    +-- cppbindings.d # D TMP bridge (V8TypeTag, V8TypeChecks)
    +-- package.d     #   + extern(C++, "v8") static-method bindings

vendor/v8shim/           # V8 C++ shim (refactored with TMP)
+-- v8shim.h             # extern "C" header (~38 functions)
+-- v8shim.cpp           # C++ impl (withContext<F> eliminates boilerplate)
+-- v8shim_tmpl.hpp      # C++ TMP (withContext, withIsolate, V8TypeMap, isV8Type)

source/dun/ts/           # TypeScript type stripping
+-- strip.d              # Scanner-based type eraser (~600 lines, 20 unit tests)
+-- package.d            # Re-exports strip

source/dun/platform/
+-- arena.d              # Arena/bump allocator (std.experimental.allocator Region, BorrowedRegion, InSituRegion, Mallocator)
+-- simd.d               # core.simd SIMD primitives (toLower16, hexEncode, findByte; SSE2/NEON)
+-- openssl.d            # extern(C) OpenSSL bindings (libssl, libcrypto, ALPN, SSL_accept, cert/key loading)
+-- lsquic.d             # extern(C) lsquic bindings (QUIC/HTTP3, litespeedtech/lsquic)

source/dun/security/
+-- permissions.d        # PermissionRegistry (default-deny model)
+-- cve_db.d             # OSV API client + local cache (24h TTL) + semver comparison + audit scanner (8 tests)
+-- test.d               # Security unit tests (27 tests)
```

Upper layers use `IJSEngine` -- only code inside `engine/<backend>/` touches raw engine APIs.

### Runtime Globals (Layer 6)

All runtime globals are **engine-agnostic** (use `IJSEngine` + `NativeCallback`):

| Module | Registration | Available via |
|--------|-------------|---------------|
| `console` | `installConsole(engine)` | Global `console` object |
| `Buffer` | `registerBufferModule(engine)` | Global `Buffer`, `require('buffer')` |
| `EventEmitter` | `registerEventsModule(engine)` | Global `EventEmitter`, `require('events')` |
| `URL` / `URLSearchParams` | `registerUrlModule(engine)` | Global `URL`/`URLSearchParams`, `require('url')` |
| `os` | `registerOsModule(engine)` | `require('os')` |
| `fs` | `registerFsModule(engine)` | `require('fs')`, ESM `import from 'dun:fs'` |
| `path` | `registerPathModule(engine)` | `require('path')`, ESM `import from 'dun:path'` |
| `crypto` | `registerCryptoModule(engine)` | `require('crypto')`, ESM `import from 'dun:crypto'` |
| `net` | `registerNetModule(engine)` | `require('net')`, ESM `import from 'dun:net'` |
| `http` | `registerHttpModule(engine)` | `require('http')`, ESM `import from 'dun:http'` |
| `http2` | `registerHttp2Module(engine)` | `require('http2')`, ESM `import from 'dun:http2'` |
| `http3` | `registerHttp3Module(engine)` | `require('http3')`, ESM `import from 'dun:http3'` |
| `child_process` | `registerChildProcessModule(engine)` | `require('child_process')`, ESM `import from 'dun:child_process'` |
| `stream` | `registerStreamModule(engine)` | `require('stream')`, ESM `import from 'dun:stream'` |
| `zlib` | `registerZlibModule(engine)` | `require('zlib')`, ESM `import from 'dun:zlib'` |
| `dns` | `registerDnsModule(engine)` | `require('dns')`, ESM `import from 'dun:dns'` |
| `ws` | `registerWsModule(engine)` | `require('ws')`, ESM `import from 'dun:ws'` |
| `sqlite` | `registerSqliteModule(engine)` | `require('sqlite')`, ESM `import from 'dun:sqlite'` |
| `util` | `registerUtilModule(engine)` | `require('util')`, ESM `import from 'dun:util'` |
| `assert` | `registerAssertModule(engine)` | `require('assert')`, ESM `import from 'dun:assert'` |
| `querystring` | `registerQuerystringModule(engine)` | `require('querystring')`, ESM `import from 'dun:querystring'` |
| `string_decoder` | `registerStringDecoderModule(engine)` | `require('string_decoder')`, ESM `import from 'dun:string_decoder'` |
| `timers/promises` | `registerTimersPromisesModule(engine)` | `require('timers/promises')`, ESM `import from 'dun:timers/promises'` |
| `vm` | `registerVmModule(engine)` | `require('vm')`, ESM `import from 'dun:vm'` |
| `cluster` | `registerClusterModule(engine)` | `require('cluster')`, ESM `import from 'dun:cluster'` |
| `async_hooks` | `registerAsyncHooksModule(engine)` | `require('async_hooks')`, ESM `import from 'dun:async_hooks'` |
| `worker_threads` | `registerWorkerThreadsModule(engine)` | `require('worker_threads')`, ESM `import from 'dun:worker_threads'` |
| `fetch` | `registerFetchGlobal(engine)` | Global `fetch()` (Posix, HTTPS via OpenSSL) |
| Web globals | `installWebCompat(engine)` | `atob`, `btoa`, `structuredClone`, `TextEncoder`, `TextDecoder`, native Uint8Array creation |
| Web APIs | `installWebAPIs(engine)` | `performance`, `EventTarget`, `Event`, `CustomEvent`, `AbortController`, `AbortSignal`, `DOMException`, `navigator`, `Blob`, `File`, `FormData`, `Headers`, `Request`, `Response`, `MessageChannel`, `MessagePort`, `BroadcastChannel`, `ReadableStream`, `WritableStream`, `TransformStream`, `setImmediate`, `clearImmediate`, `Promise.withResolvers`, `crypto.getRandomValues`, `crypto.randomUUID`, `console.time/timeEnd/timeLog/count/countReset/table/dir/trace` |
| `Deno.*` | `installDenoCompat(engine)` | Full Deno compat (30+ APIs: env, fs, permissions, errors) |

All modules work identically across QuickJS, JSC, and V8 backends.
Workers work identically across QuickJS, JSC, and V8 backends.
Web APIs (91 checks) pass identically across all 3 backends.

### Module Resolution (package.json)

DunJS supports Node.js-compatible module resolution:
- **`exports` field**: Conditional exports (dun > import > require > node > types > default), subpath exports, wildcard patterns
- **`imports` field**: Package-internal `#` imports with condition matching
- **`main`/`module` fields**: Fallback when `exports` is not present
- Resolution order: `exports` → `main` → `module` → `index.js`

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

**QuickJS** -- `extern(C) JSValue(JSContext*, JSValueConst, int, JSValueConst*)`:
```d
extern(C) JSValue myFunc(JSContext* ctx, JSValueConst this_val,
                          int argc, JSValueConst* argv) nothrow {
    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    // ...
}
```

**JSC** -- `extern(C) JSValueRef(JSContextRef, JSObjectRef, JSObjectRef, size_t, const(JSValueRef)*, JSValueRef*)`:
```d
extern(C) JSValueRef myFunc(JSContextRef ctx, JSObjectRef func,
    JSObjectRef thisObject, size_t argc, const(JSValueRef)* args,
    JSValueRef* exception) nothrow {
    // ...
}
```

**V8** -- `extern(C) DunV8Value*(DunV8Context*, DunV8Value*, int, DunV8Value**, void*)`:
```d
extern(C) DunV8Value* myFunc(DunV8Context* ctx, DunV8Value* thisVal,
    int argc, DunV8Value** argv, void* data) nothrow {
    // ...
}
```

### 3. RAII Wrappers for Engine Resources

- `QuickJSEngine` wraps `JSRuntime*` + `JSContext*` -- freed in `shutdown()`
- `JSVal` wraps `JSValue` -- calls `JS_FreeValue` in destructor
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

### 6. TIGER_STYLE Assertions (TigerBeetle-inspired)

Fail fast at the point of corruption rather than propagating invalid state through FFI.
Applied across all 7 layers (~290 assertions in 25 files).

**Patterns**:
- Every `@trusted` block: `assert(ctx !is null)`, `assert(engine !is null)`
- Every `extern(C)` callback: `assert(ctx !is null)`, `assert(state.engine !is null)`
- Every `NativeCallback`: `assert(ctx !is null)` (ctx is `DunState*`), then `assert(state.engine !is null)`
- Double-init guards: `assert(ctx is null, "Double initialization of XxxEngine")`
- `static assert` for layout: `JSHandle.sizeof >= 2 * (void*).sizeof`
- `static assert` for enum drift: `__traits(allMembers, EngineBackend).length == 3`
- Bounds checks: refcount overflow, buffer write limits, type tag ranges

### 7. Performance Optimizations

- **Trampoline stack allocation**: All 3 backends use `JSHandle[16]` stack buffer in native callback trampolines instead of GC `new JSHandle[argc]`
- **Native typed arrays**: QuickJS uses `JS_CallConstructor(Uint8Array, ArrayBuffer)`, JSC uses `JSObjectMakeTypedArray` + `memcpy`, V8 uses `ArrayBuffer::New` + `memcpy` — no eval
- **Buffer prototype**: Shared prototype object with 35 methods, `Object.create(proto)` per instance (3 property sets vs 38)
- **V8 indexed properties**: Native `dun_v8_get/set_property_index` via `Object::Get(context, idx)` — no int-to-string conversion
- **Crypto cached fd**: `/dev/urandom` opened once, reused for all `randomBytes`/`randomUUID` calls
- **UUID fast format**: CTFE hex LUT instead of `std.format` for UUID formatting
- **SIMD hex encoding**: `dun.platform.simd.hexEncodeBuf` uses `core.simd` ubyte16 to encode 16 bytes → 32 hex chars per cycle (used by `buffer.d` `bytesToHex`)
- **SIMD HTTP toLower**: `asciiToLowerBuf` lowercases HTTP header names 16 bytes/cycle via SIMD masks (used by `http.d` `parseRequestHeaders`)
- **SIMD byte search**: `findByte` scans buffers for delimiters 16 bytes/cycle via SIMD equality check
- **CTFE hex LUT**: Fallback 512-byte lookup table for non-SIMD paths and tail bytes
- **Pre-allocated buffers**: WebSocket frames, ESM shim use `Appender` with `reserve()`
- **ESM shim O(n) strings**: `escapeJsString`, `splitLines`, `parseImportLine` use `Appender` instead of `~=`/`~` concatenation
- **Arena allocator**: `dun.platform.arena` re-exports `std.experimental.allocator` (`Region!Mallocator`, `BorrowedRegion`, `InSituRegion`) for `@nogc pure` bump allocation
- **GC tuning**: `rt_options = ["gcopt=minPoolSize:16"]` reduces GC collections ~11x
- **HTTP TCP_NODELAY**: Disables Nagle's algorithm on accepted sockets, eliminating 40ms delayed-ACK latency
- **HTTP buffered response**: Headers + body combined in `char[MAX_BUF]` stack buffer, flushed in single `send()` call
- **HTTP CTFE status lines**: `statusLine()` returns pre-computed `"HTTP/1.1 200 OK\r\n"` strings — `pure nothrow @safe @nogc`, zero allocation
- **HTTP connection pool**: fd→connId hashmap (O(1) lookup) + free slot list for connection reuse
- **HTTP JS-level dispatch**: Pre-compiled JS function creates req/res objects in JIT-optimized JS, reducing per-request FFI calls from ~25 to ~8
- **HTTP lazy headers**: `get headers()` getter loads headers on demand via native callback, avoiding allocation when headers unused

### 8. Event Loop Phases (per tick)

1. Drain microtask queue (Promise jobs + queueMicrotask)
2. Process expired timers (setTimeout/setInterval)
3. Drain microtasks generated by timers
4. Poll I/O via IOPoller (epoll/kqueue/poll, blocks until I/O or next timer deadline)
5. Drain microtasks generated by I/O callbacks

## C/C++ FFI Reference

### ImportC vs dpp vs dstep

| Criteria | ImportC | dpp | dstep |
|----------|---------|-----|-------|
| **Use case** | Compile C sources directly | `#include` C/C++ in `.dpp` | Batch header->D binding |
| **Macro support** | Partial (function-like) | Full (via C preprocessor) | `#define` only |
| **C++ support** | No | Limited | No |
| **Compile-time impact** | High (compiles C) | Medium (preprocess) | None (pre-generated) |
| **DUB integration** | Native (`cImportPaths`) | Via `dub run dpp` | Generated modules |
| **libclang required** | No | Yes (v6+) | Yes |
| **Best for** | Small/medium C libs | Complex C headers + macros | One-shot C binding gen |

**Real-world examples**: sokol-d uses gen_d.py + ImportC, bdwgc-d uses ImportC via DUB.

### C++ FFI with D

```d
// Direct C++ interop via extern(C++) -- only safe for static methods
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

// Instance methods generate vtable entries -> linker errors without C++ objects
// Use C shim (vendor/v8shim/) for all value operations instead

// dlang/stdcpp provides: string, string_view, memory (unique_ptr), allocator
import stdcpp.allocator;
```

### Engine FFI Strategies

| Engine | API | FFI Approach | Lines |
|--------|-----|-------------|-------|
| QuickJS | C API (quickjs.h) | extern(C) -- manual D bindings, audited via ImportC `-H` | ~400 |
| JSC | C API (JSObjectRef) | extern(C) -- straightforward, ~90 functions | ~290 |
| JSC | C++ internals | extern(C++, "JSC") -- experimental cppbindings.d | ~30 |
| JSC | D TMP bridge | JSCTypeTag + JSCTypeChecks + getType() fast path | ~140 |
| V8 | C++ only | extern(C) via C shim (vendor/v8shim/) | ~300 C++ + ~90 D |
| V8 | C++ internals | extern(C++, "v8") -- static methods only (V8 class) | ~50 |
| V8 | C++ TMP bridge | D TMP (V8TypeChecks) <-> C++ TMP (isV8Type, withContext) | ~120 |
| SQLite | C API (sqlite3.h) | ImportC -- real header processed by D compiler | ~10 D + header |

### C++ TMP <-> D TMP Bridge Pattern

The V8 and JSC backends use cross-language template metaprogramming where C++ templates
and D compile-time features mirror each other across the FFI boundary.

**V8 C++ side** (`vendor/v8shim/v8shim_tmpl.hpp` -- wired into `v8shim.cpp`):
- `withContext<F>`: RAII scope guard eliminating 4-line boilerplate in ~20 functions
- `withIsolate<F>`: isolate-only variant for type checks
- `V8TypeMap<Tag>`: compile-time tag -> v8::Type dispatch (9 specializations)
- `isV8Type<Tag>`: `if constexpr` for type-check method selection (9 types)
- `valueIsType<Tag>`: internal template combining withIsolate + isV8Type

**V8 D side** (`source/dun/engine/v8/cppbindings.d` -- used by `backend.d`):
- `V8TypeTag` enum: mirrors C++ `V8Tag` (Undefined..Function)
- `V8TypeName` template: compile-time tag -> function suffix map
- `V8TypeChecks`: function pointer table (9 entries), `check(tag, val)` dispatch
- `backend.d` `checkType()`: lazy-initialized table, 7 `isXxx()` one-liners

**JSC D side** (`source/dun/engine/jsc/cppbindings.d` -- used by `backend.d`):
- `JSCTypeTag` enum: values 0-6 match `kJSType*` constants, extended with Array/Function/Date
- `JSCTypeName` template: compile-time tag -> display name
- `JSCTypeChecks`: function pointer table + special Function handling
  - `getType()`: single `JSValueGetType()` call for basic types (O(1) dispatch)
  - `check(tag)`: function pointer table for all types including extended
  - `typeofString()`: JS `typeof` semantics via single-dispatch
- `backend.d` `checkType()`: lazy-initialized table, 7 `isXxx()` one-liners

Adding a new type requires adding an enum value on each side -- templates
auto-generate the rest at compile time, both in C++ and D.

### V8 C++ Shim Architecture

```
D code (backend.d / globals.d)
  | extern(C) calls
  v
vendor/v8shim/v8shim.cpp
  | withContext<F> scope guard (eliminates boilerplate)
  | valueIsType<Tag> -> isV8Type<Tag> (compile-time type dispatch)
  | FunctionTemplate + trampoline for native callbacks
  | DunV8Value* ref-counted wrappers around v8::Global<Value>
  v
V8 C++ API (v8.h, from Node.js headers)
```

Key shim patterns:
- **withContext<F>**: RAII scope guard (Isolate::Scope + HandleScope + Context::Scope) with perfect forwarding
- **isV8Type<Tag>**: `if constexpr` dispatch to V8 `IsXxx()` methods (9 types)
- **FunctionTemplate trampoline**: D callback -> `DunV8FunctionData*` in `v8::External` -> `v8FunctionTrampoline` -> D function pointer
- **V8 14.x compat**: `DUN_EXTERNAL_NEW(iso, ptr)` / `DUN_EXTERNAL_VALUE(ext)` macros for `ExternalPointerTypeTag` parameter (V8 14+ requires 3-arg `External::New`)
- **Headers from kassane/libv8**: V8 14.9.207.4 headers + monolith from `github.com/kassane/libv8/releases`
- **CREL relocations**: V8 14.9 monolith uses LLVM 19+ CREL format; requires LDC's internal linker (`--link-internally`, LLVM 21 based) on Linux — GNU ld 2.42 and lld-18 cannot process CREL

## Testing

### Unit Tests

```sh
dub test -c unittest    # All unit tests
```

| Suite | File | Tests | Coverage |
|-------|------|-------|----------|
| Engine contract | `source/dun/engine/test.d` | ~50 | eval, types, properties, exceptions, promises |
| Fuzz/stress | `source/dun/engine/fuzz.d` | ~50 | rapid create/destroy, string stress, exception recovery |
| TypeScript strip | `source/dun/ts/strip.d` | 20 | annotations, interfaces, as, declare, arrow types |
| Security perms | `source/dun/security/test.d` | 27 | default deny, scoped grants, deny overrides, parseFlag |
| CVE audit | `source/dun/security/cve_db.d` | 8 | semver, CVSS parsing, severity mapping, JSON escaping, cache round-trip |
| SQLite | `source/dun/builtins/sqlite.d` | 4 | ImportC bindings, open/close, exec/query, bind parameters |
| HTTP/2 | `source/dun/builtins/http2.d` | 15 | frame encoding, HPACK encode/decode, static table, settings |
| HTTP/3 | `source/dun/builtins/http3.d` | 12 | QUIC varint encode/decode, H3 frame header, SETTINGS payload |
| V8 TMP bridge | `source/dun/engine/v8/cppbindings.d` | compile-time | V8TypeName coverage, tag->name mapping |
| JSC TMP bridge | `source/dun/engine/jsc/cppbindings.d` | compile-time | JSCTypeName coverage, kJSType* alignment |

### Integration Tests (66 tests)

```sh
# Run against a specific backend
dub build -c quickjs && ./tests/integration/run.sh
dub build -c jsc && BACKEND=jsc ./tests/integration/run.sh
dub build -c v8  && BACKEND=v8  ./tests/integration/run.sh
```

| Category | Tests | Coverage |
|----------|-------|----------|
| Core JS | `hello`, `types`, `console_methods` | Basic output, typeof, multi-arg logging |
| Async | `promises`, `promises_advanced`, `timers`, `phase2`, `phase2_rejection`, `async_io` | Promise.all/race/any, async/await, setTimeout, unhandledRejection |
| ES2023+ | `es2023`, `closures`, `iterators`, `classes`, `regex`, `json_parsing` | findLast, generators, Map/Set, private fields, matchAll |
| Errors | `error_handling` | try/catch, Error subtypes, Error.cause, finally |
| Modules | `module_esm`, `module_cjs`, `module_chain`, `json_pipeline`, `npm_compat` | ESM import/export, CJS require, chained deps, JSON import |
| Builtins | `fs_ops`, `path_ops`, `crypto_ops`, `stat_file`, `env_access` | readFile, join/resolve, hash/randomBytes, stat, process.env |
| Node APIs | `buffer_api`, `event_emitter`, `url_api`, `os_api`, `http2_api`, `http3_api` | Buffer.from/alloc/concat, EventEmitter on/emit/once, URL/URLSearchParams, os.platform/cpus/totalmem, HTTP/2 API (20 checks), HTTP/3 API (22 checks) |
| New Modules | `child_process_api`, `stream_api`, `zlib_api`, `dns_api`, `ws_api` | execSync/spawnSync, Readable/Writable/Transform/pipeline, deflate/gzip round-trip, DNS lookup/resolve, WebSocket API |
| Database | `sqlite_api` | open, exec, run, get, all, close, NULL handling, types (20 checks) |
| Web APIs | `web_apis` | 91 checks: performance, EventTarget/Event, AbortController, Blob, FormData, Headers, Request/Response, MessageChannel, BroadcastChannel, ReadableStream, WritableStream, TransformStream, crypto.getRandomValues, navigator, Promise.withResolvers, require.resolve |
| Deno compat | `deno_compat` | 22 checks: env, fs, stat, copy, rename, remove, web globals |
| Security | `perm_deny_read`, `perm_deny_write`, `realworld_security_boundary` | Permission denial enforcement |
| TypeScript | `typescript`, `realworld_ts_library` | Type annotations, interfaces, as, arrow types |
| Fetch/Response | `fetch_response` | 19 checks: Response constructor, status/statusText/ok/url, headers, text/json/clone, process.stdin |
| import.meta | `import_meta` | 6 checks: url, filename, dirname, main (all 3 backends) |
| New Modules | `vm_api`, `async_hooks_api`, `signal_handling` | vm.runInThisContext/runInNewContext/createContext/Script, AsyncLocalStorage run/getStore/enterWith/disable, process.on('SIGTERM'/'SIGINT') |
| Real-world | 7 end-to-end scenarios | Config loading, task runner, file processing, events, promise pool, nested require, ESM pipeline |

Backend test scores: **QuickJS 66/66**, **JSC 66/66**, **V8 66/66** (full parity across all 3 backends).

Test pattern: fixtures in `tests/integration/fixtures/*.{js,mjs,ts}`, expected stdout in `tests/integration/expected/*.txt`.

### Sanitizer Testing

```sh
dub build -c quickjs -b asan                          # ASan build via DUB
ASAN_OPTIONS=detect_leaks=0 bash tests/integration/run.sh  # Run with ASan
```

All 51 integration tests pass under AddressSanitizer with zero memory errors.

### Stress Benchmarks

| File | Tests | Description |
|------|-------|-------------|
| `tests/benchmarks/realworld.js` | 16 | Core JS performance (JSON, regex, arrays, maps, text encoding) |
| `tests/benchmarks/stress.js` | 240 | Comprehensive pure-JS (strings, arrays, objects, classes, generators, promises) |
| `tests/benchmarks/npm_stress.js` | 189 | Real npm packages (lodash, moment, validator, pako, diff, etc.) |
| `tests/benchmarks/features.js` | 53 | Feature compatibility (ES2023+, modules, web APIs) |
| `tests/benchmarks/feature_bench.js` | 25 | Cross-runtime perf (crypto, Buffer, URL, JSON, strings, arrays, Map/Set, Promise) |
| `tests/benchmarks/framework_bench.js` | 39 | Framework patterns (routing, middleware, JSON API, templates, SQL, validation, concurrency) |
| `tests/benchmarks/npm_compat_test.js` | 145 | Simulated npm packages (lodash, express, moment, uuid, chalk, dotenv, minimist, semver, etc.) |
| `tests/benchmarks/sqlite_bench.js` | 5 | SQLite performance (bulk insert/read, aggregation, update) |
| `tests/benchmarks/http_bench/stress.sh` | 9 endpoints | HTTP wrk stress (plaintext, json, users API, compute, transaction, middleware, echo) |

Cross-runtime comparison (feature_bench.js, 25 tests, release builds, ops/sec):

| Runtime | Total Throughput | vs Bun |
|---------|-----------------|--------|
| Bun 1.3.11 | 399M | 1.00x |
| DunJS JSC | 373M | **0.94x** |
| Node.js v22 | 118M | 0.30x |
| Deno 2.7.14 | 108M | 0.27x |
| DunJS V8 | 103M | 0.26x |

Framework benchmarks (framework_bench.js, 39 tests, release builds, ops/sec):

| Runtime | Total Throughput | vs Bun |
|---------|-----------------|--------|
| Bun 1.3.11 | 275M | 1.00x |
| DunJS JSC | 260M | **0.95x** |
| Deno 2.7.14 | 143M | 0.52x |
| DunJS V8 | 138M | 0.50x |
| Node.js v22 | 125M | 0.45x |

npm compat test (npm_compat_test.js, 145 assertions): **All 6 runtimes: 145/145 pass**

HTTP stress benchmarks (wrk, 2 threads, 128 connections, 10s per endpoint, release builds):

| Endpoint | Node v22 | Deno 2.7 | Bun 1.3 | DunJS V8 | DunJS JSC | DunJS QJS |
|----------|----------|----------|---------|----------|-----------|-----------|
| /plaintext | 28,238 | 52,086 | 55,487 | 37,298 | 30,515 | 48,084 |
| /json | 29,398 | 49,783 | 53,093 | 38,924 | 28,850 | 55,888 |
| /api/users | 13,951 | 21,930 | 22,147 | 16,191 | 11,813 | 5,172 |
| /compute | 27,372 | 42,544 | 55,132 | 39,778 | 34,040 | 40,334 |
| /transaction | 19,046 | 41,792 | 42,694 | 34,138 | 25,407 | 26,501 |
| /middleware | 20,474 | 43,507 | 49,675 | 32,517 | 25,467 | 34,185 |

DunJS V8 beats Node.js on all endpoints. DunJS QuickJS excels at /json (55K vs Bun's 53K).
All endpoints include TCP_NODELAY, buffered single-write response, CTFE status lines.

Stress test (stress.js, 240 tests, release builds):

| Runtime | Wall Time | Status |
|---------|-----------|--------|
| Bun 1.3.11 | 90s | 240/240 |
| DunJS JSC | 99s | 240/240 |
| DunJS V8 | 211s | 240/240 |
| Node.js v22 | 220s | 240/240 |
| Deno 2.7.14 | 222s | 240/240 |

### Concurrency & SIMD Comparison

| Feature | DunJS | Bun | Deno | Node.js |
|---------|-------|-----|------|---------|
| Workers | All backends | Yes (JSC) | Yes (V8) | Yes (V8) |
| SharedArrayBuffer | Yes | Yes | Yes | Yes |
| Atomics | Yes (futex on Linux) | Yes | Yes | Yes |
| io_uring | Yes (IORING_OP_POLL_ADD) | Yes (internal) | No | No (libuv) |
| Async thread pool | Yes (D threads) | Yes (Zig) | Yes (Tokio) | Yes (libuv) |
| core.simd / WASM SIMD | `core.simd` active (hex, toLower, findByte) | WASM SIMD | V8 SIMD | V8 SIMD |
| Epoll/kqueue | Yes | Yes | Yes | Via libuv |
| HTTP/2 multiplexing | Yes | Yes | Yes | Yes |
| WebSocket | Yes (RFC 6455) | Yes | Yes | Via ws pkg |

D's `core.simd` maps to SSE2/AVX (x86) and NEON (ARM) at compile time, similar to
Zig's `@Vector`. V8/JSC use their own internal SIMD for JIT-compiled code.
DunJS uses `core.simd` in hot paths (`dun.platform.simd`):
- **`hexEncodeBuf`**: SIMD hex encoding (16 bytes → 32 hex chars/cycle) used by `buffer.d`
- **`asciiToLowerBuf`**: SIMD ASCII toLower (16 bytes/cycle) used by HTTP header parsing
- **`findByte`**: SIMD byte search (16 bytes/cycle) for delimiter scanning
- Scalar fallback via `version(D_SIMD)` for platforms without SIMD

### Docker Support

```sh
# Single-backend (smallest image)
docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
docker build --build-arg BACKEND=jsc -t dunjs:jsc .
docker build --build-arg BACKEND=v8 -t dunjs:v8 .

# Multi-backend (all 3, switchable via DUN_BACKEND env)
docker build -f Dockerfile.multibackend -t dunjs:multi .
docker run --rm dunjs:multi run script.js                    # quickjs default
docker run --rm -e DUN_BACKEND=jsc dunjs:multi run script.js # jsc
docker run --rm -e DUN_BACKEND=v8 dunjs:multi run script.js  # v8
```

Base image: `debian:bookworm-slim` (glibc, compatible with JSC/V8 prebuilt libs).

### TypeScript Support

DunJS supports running `.ts`, `.mts`, and `.cts` files directly via type stripping
(same approach as Node.js `--experimental-strip-types`). Types are replaced with
whitespace to preserve source positions for error messages.

Supported erasable TypeScript:
- Type annotations (`: T` on variables, parameters, return types)
- `interface` and `type` alias declarations
- `import type` / `export type` statements
- `as T` type assertions
- `declare` blocks, `abstract` keyword
- Optional parameters (`x?: T`)
- Generic type parameters (`<T>`)

Not supported (have runtime semantics):
- `enum` (use `const obj = { ... } as const` instead)
- `namespace` blocks
- Constructor parameter properties (`constructor(public x: number)`)

## Security Model

- **Default deny**: All I/O operations require explicit permission flags
- **CLI flags**: `--allow-read`, `--allow-write`, `--allow-net`, `--allow-env`, `--allow-run`, `--allow-all`
- **Scoped**: `--allow-read=./data,/tmp` grants read only to those paths
- **Deny overrides allow**: `--deny-write=/etc` always wins
- **Path canonicalization**: Resolve symlinks before permission checks
- **Memory limits**: Engine-level heap cap (default 256MB)
- **Execution timeout**: Engine interrupt handler for infinite loop protection
- **38 unit tests**: Default deny, global grant, --allow-all, scoped grants, deny-overrides-allow, parseFlag, CVE semver, vulnerability checks
- **CVE audit**: OSV API (osv.dev) with local cache (24h TTL), `dun audit` scans node_modules, `--audit=block` blocks critical/high

## Code Style

- Module naming: `dun.layer.module` (e.g., `dun.engine.quickjs.bindings`)
- 4-space indentation
- D naming conventions: `camelCase` for functions/variables, `PascalCase` for types
- No `auto` for public API return types -- always explicit
- **`@safe` first, `@system` when needed, `@trusted` only as last resort**: `@trusted` bypasses compiler safety checks entirely -- it is *more dangerous* than `@system` because it silently trusts the programmer. Use `@safe` for all pure logic. Use `@system` for raw OS/FFI calls (compiler still flags unsafe operations). Only use `@trusted` at the *narrowest possible scope* when bridging `@safe` code to a verified-safe `@system` operation -- never on entire functions unless unavoidable (e.g., `extern(C)` callbacks that call `@system` internally). Audit every `@trusted` annotation: if the function can be made `@safe` or split into `@safe` + `@system` parts, do that instead
- Every `extern(C)` callback must be `nothrow`
- Named constants for limits: `DEFAULT_MEMORY_LIMIT`, `DEFAULT_MAX_STACK`, `TEST_MEMORY_LIMIT`, `TEST_MAX_STACK`
- **Avoid magic numbers**: Use named `enum` constants for buffer sizes, protocol constants, reserve capacities, and bit patterns. Use `dun.platform.arena` for all allocation utilities (`Appender`, `BumpRegion`, `makeAppender`)
- **Avoid redundancies**: Use `dun.platform.arena` instead of `import std.array : Appender` directly. Prefer `*To(ref Appender)` helper patterns to eliminate intermediate allocations. Remove duplicate local imports when already imported at module level
- **MUST add `assert`/`static assert` in all new features** -- TIGER_STYLE: assert preconditions at every `@trusted` boundary, every `extern(C)` callback, every FFI entry point
- **MUST always build and test ALL backends (quickjs, jsc, v8) before committing any changes**:
  ```sh
  dub build -c quickjs && dub build -c jsc && dub build -c v8
  dub test -c unittest
  bash tests/integration/run.sh                          # QuickJS
  BACKEND=jsc bash tests/integration/run.sh              # JSC
  BACKEND=v8  bash tests/integration/run.sh              # V8
  ```
- Never ship code that only compiles or passes on one backend

## FFI Bridge: D <-> Engine Memory Rules

1. **Engine owns JS values.** Every value returned by the engine is either owned (must be freed) or borrowed. RAII wrappers handle this.
2. **D GC must not collect objects referenced by the engine.** Pin with `GC.addRoot` / `GC.removeRoot`.
3. **Hot paths use `@nogc`.** `extern(C)` callbacks must be `nothrow`. Mark `@nogc` where possible.
4. **Custom allocator.** Use engine-specific allocator hooks to track heap size and enforce `--max-memory`.
5. **NativeCallback slot limit.** QuickJS uses `int16_t` magic values → max 32,767 callback slots. Cache function handles with `engine.dupValue()` instead of `engine.newFunction()` per object. TIGER_STYLE assertion in `callbacks.d` catches overflow.
6. **CTFE lookup tables.** Use compile-time function evaluation for encoding tables (e.g., `bytesToHex` in `buffer.d`). Avoids `std.format` in hot paths.
7. **std.array.Appender.** Use `Appender!(char[])` with `reserve()` for string building instead of `~=` (ESM shim, transpiler output).
8. **Pre-allocated buffers.** Build WebSocket frames, HTTP responses, etc. with exact-size `new ubyte[totalLen]` instead of incremental `~=`.

## D Runtime GC Tuning

Default: `rt_options = ["gcopt=minPoolSize:16"]` in `app.d` — 16 MiB minimum pool reduces GC collections ~11x.

```sh
# Profile GC behavior
dun "--DRT-gcopt=profile:1" run script.js

# Tune pool sizes for server workloads
dun "--DRT-gcopt=minPoolSize:32 maxPoolSize:512" run server.js

# Precise GC (fewer false retentions, slightly slower)
dun "--DRT-gcopt=gc:precise" run script.js

# Parallel GC marking (default: uses all cores)
dun "--DRT-gcopt=parallel:4" run script.js

# Show all GC options
dun "--DRT-gcopt=help"
```

Benchmark impact (25 benchmarks, feature_bench.js):
| Config | GC Collections | GC Time | Throughput |
|--------|---------------|---------|------------|
| Default (1MB pool) | 260 | 27ms | 5.67M ops/sec |
| minPoolSize:16 | 23 | 6ms | 5.92M ops/sec |
| precise + 16MB | 20 | 7ms | ~5.9M ops/sec |

## Phased Roadmap

| Phase | Goal | Key Deliverable | Status |
|-------|------|-----------------|--------|
| 1 (MVP) | `dun run hello.js` | Engine abstraction + console + CLI | **Done** |
| 1b | Multi-engine | JSC + V8 backends fully functional | **Done** |
| 1c | TypeScript | `dun run file.ts` with type stripping | **Done** |
| 1d | Security tests | PermissionRegistry unit tests (27 tests) | **Done** |
| 1e | TMP bridge | C++ TMP <-> D TMP wired for V8 + JSC | **Done** |
| 2 | Async works | Event loop + timers + Promises | **Done** |
| 2f | Phase 2 close | queueMicrotask + process.nextTick + unhandledRejection | **Done** |
| 3 | Real scripts | Module system + fs/path/net/crypto | **Done** |
| 4 | Secure by default | Permission enforcement wired to builtins | **Done** |
| 5 | DX polish | REPL + colored errors + stack traces | **Done** |
| 6a | Networking | net.d TCP + npm compat (node_modules) + I/O polling | **Done** |
| 6b | HTTP server | http.d HTTP/1.1 createServer/listen/close, req/res, epoll | **Done** |
| 6c | Workers | Web Workers + SharedArrayBuffer + Atomics (all backends) | **Done** |
| 6d | io_uring | Linux io_uring backend for IOPoller (IORING_OP_POLL_ADD) | **Done** |
| 7a | Node APIs | Buffer, EventEmitter, URL/URLSearchParams, os module | **Done** |
| 7b | Engine parity | net/http ported engine-agnostic (JSC/V8 fully usable) | **Done** |
| 7c | Safety | `-preview=safer` enabled for all code | **Done** |
| 8a | TLS/HTTPS | OpenSSL bindings + TlsSocket + fetch() with HTTPS | **Done** |
| 8b | npm install | `dun install <pkg>` with transitive deps from registry | **Done** |
| 8c | Deno compat | Deno.env, readTextFileSync, writeTextFileSync, cwd, exit, build | **Done** |
| 8d | Full Deno compat | 30+ Deno APIs (stat, mkdir, remove, rename, copy, readDir, permissions, errors) | **Done** |
| 8e | Web globals | atob, btoa, TextEncoder, TextDecoder, structuredClone | **Done** |
| 8f | Node process | process.argv, cwd(), exit(), platform, arch, version, pid | **Done** |
| 9a | HTTP/2 | http2.d RFC 9113 binary framing, HPACK, stream multiplexing, ALPN/TLS | **Done** |
| 9b | child_process | execSync, spawnSync, exec with permissions | **Done** |
| 9c | stream | Readable, Writable, Duplex, Transform, PassThrough, pipeline | **Done** |
| 9d | zlib | deflateSync, inflateSync, gzipSync, gunzipSync, raw deflate/inflate | **Done** |
| 9e | dns | lookup, lookupSync, resolve4, resolve6, reverse (POSIX getaddrinfo) | **Done** |
| 9f | WebSocket | RFC 6455 framing, client connect, server create, send/close (ws module) | **Done** |
| 9g | CVE audit | `dun audit` + `--audit=block/warn/off`, OSV API + local cache (24h TTL) | **Done** |
| 10a | SQLite | `dun:sqlite` built-in module, ImportC bindings from sqlite3.h, open/exec/run/get/all/close | **Done** |
| 10b | Test runner | `dun test` with Deno.test() API, file discovery, --filter, async tests | **Done** |
| 10c | Bench runner | `dun bench` with Deno.bench() API, auto-calibrating iterations, ops/sec reporting | **Done** |
| 10d | CLI tools | `dun init`, `dun fmt`, `dun clean` (project scaffold, formatter, cache cleanup) | **Done** |
| 10e | Perf: callback slots | Fix NativeCallback slot exhaustion (cache function handles, TIGER_STYLE assert) | **Done** |
| 10f | Perf: allocations | CTFE hex LUT (Buffer 59x faster), WS frame pre-alloc, ESM Appender | **Done** |
| 10g | GC tuning | collectGarbage() API, gc() global, rt_options minPoolSize:16, --DRT-gcopt docs | **Done** |
| 10h | Benchmarks | feature_bench.js (25 cross-runtime benchmarks), GC profiling integration | **Done** |
| 11a | Web APIs | performance, EventTarget/Event, AbortController/AbortSignal, DOMException | **Done** |
| 11b | Web APIs | Blob/File, FormData, Headers, Request/Response, navigator | **Done** |
| 11c | Web APIs | MessageChannel/MessagePort, BroadcastChannel, ReadableStream/WritableStream/TransformStream | **Done** |
| 11d | Web Crypto | crypto.getRandomValues(), crypto.randomUUID() as globals | **Done** |
| 11e | Console ext | console.time/timeEnd/timeLog/count/countReset/table/dir/trace | **Done** |
| 11f | Module compat | require.resolve(), require.cache, import.meta.url (QuickJS ESM) | **Done** |
| 11g | ES2024 | Promise.withResolvers(), setImmediate/clearImmediate | **Done** |
| 11h | Safety | `-preview=dip1000` enabled (scope safety for slices) | **Done** |
| 12a | fetch Response | fetch() returns proper Response objects (constructor, prototype, text/json/clone) | **Done** |
| 12b | process.stdin | process.stdin with non-blocking read, fd, isTTY, setEncoding | **Done** |
| 12c | import.meta all backends | import.meta.url/filename/dirname/main on QuickJS (native) + JSC/V8 (ESM shim polyfill) | **Done** |
| 12d | D FFI bindgen tests | 27 tests: -HCf, -H, ImportC, @nogc alloc, clang AST, FFI linkage, --extern-std | **Done** |
| 13a | HTTP/3 | dun:http3 module, RFC 9114 constants, QUIC varint encoding, lsquic bindings, API stubs | **Done** |
| 14a | vm module | dun:vm — runInThisContext, runInNewContext, createContext, Script class | **Done** |
| 14b | cluster module | dun:cluster — fork(), isPrimary/isWorker, worker tracking, exit callbacks | **Done** |
| 14c | async_hooks | dun:async_hooks — AsyncLocalStorage constructor, run/getStore/enterWith/disable | **Done** |
| 14d | worker_threads | dun:worker_threads — isMainThread, threadId, Worker (delegates to existing Worker API) | **Done** |
| 14e | Signal handling | POSIX SIGTERM/SIGINT handlers, process.on('SIGTERM'/'SIGINT', cb), event loop drain | **Done** |
| 14f | core.simd | SIMD hex encoding (16B/cycle), ASCII toLower (16B/cycle), byte search; SSE2/NEON | **Done** |
