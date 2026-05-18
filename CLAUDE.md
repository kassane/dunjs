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
./dun clean                          # Remove project-local .dun/ + node_modules/ (NOT $DUN_HOME)
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
+-- fuzz.d           # Fuzz/stress tests (~71 cases)
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
|   +-- backend.d    # JSCEngine : IJSEngine (uses JSCTypeChecks dispatch, ~766 LOC)
|   +-- bindings.d   # extern(C) declarations for JSC C API (~289 lines)
|   +-- cppbindings.d # D TMP bridge (JSCTypeTag, JSCTypeChecks, getType, ~180 LOC)
|   +-- package.d     #   + experimental extern(C++, "JSC") bindings
+-- v8/              # V8 backend (fully functional, via C shim)
    +-- backend.d    # V8Engine : IJSEngine (uses V8TypeChecks dispatch, ~557 LOC)
    +-- bindings.d   # extern(C) declarations for v8shim (~112 lines)
    +-- cppbindings.d # D TMP bridge (V8TypeTag, V8TypeChecks)
    +-- package.d     #   + extern(C++, "v8") static-method bindings

vendor/v8shim/           # V8 C++ shim (refactored with TMP, ~1118 LOC total)
+-- v8shim.h             # extern "C" header (~129 LOC, ~54 functions)
+-- v8shim.cpp           # C++ impl (~868 LOC, withContext<F> eliminates boilerplate)
+-- v8shim_tmpl.hpp      # C++ TMP (~121 LOC: withContext, withIsolate, V8TypeMap, isV8Type)

source/dun/ts/           # TypeScript type stripping
+-- strip.d              # Scanner-based type eraser (~600 lines, 20 unit tests)
+-- jsx.d                # JSX to React.createElement / Bun.jsx transform
+-- dynamic_import.d     # source-rewriter: `import(x)` -> `__dunImport__(x)` for JSC/V8
+-- transpile_cache.d    # SHA-256 keyed persistent cache (~30x speedup on cache hit)
+-- package.d            # Re-exports

source/dun/platform/
+-- arena.d              # Arena/bump allocator (std.experimental.allocator Region, BorrowedRegion, InSituRegion, Mallocator)
+-- simd.d               # SIMD primitives + LDC intrinsics (loadUnaligned, shufflevector, bswap, cttz, prefetch)
+-- paths.d              # canonicalizePath + dunGlobalRoot() (cross-platform user-global store)
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
| `os` | `registerOsModule(engine)` | `require('os')` — platform, cpus, totalmem, freemem, networkInterfaces, userInfo, loadavg, version, machine |
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
| `https` | `registerHttpsModule(engine)` | `require('https')`, ESM `import from 'dun:https'` |
| `fs/promises` | `registerFsPromisesModule(engine)` | `require('fs/promises')`, ESM `import from 'dun:fs/promises'` |
| `readline` | `registerReadlineModule(engine)` | `require('readline')`, ESM `import from 'dun:readline'` |
| `tls` | `registerTlsModule(engine)` | `require('tls')`, ESM `import from 'dun:tls'` — connect, getCiphers, TLSSocket, constants |
| `dgram` | `registerDgramModule(engine)` | `require('dgram')`, ESM `import from 'dun:dgram'` — createSocket, bind, send, close |
| `perf_hooks` | `registerPerfHooksModule(engine)` | `require('perf_hooks')`, ESM `import from 'dun:perf_hooks'` — mark/measure/getEntries, PerformanceObserver, timerify |
| `wasi` | `registerWasiModule(engine)` | `require('wasi')`, ESM `import from 'dun:wasi'` — preview1 WASI (args, env, clock, random, fd_*, path_*) |
| `punycode` | stub (globalThis) | `require('punycode')`, ESM `import from 'dun:punycode'` |
| `domain` | stub (globalThis) | `require('domain')`, ESM `import from 'dun:domain'` |
| `diagnostics_channel` | stub (globalThis) | `require('diagnostics_channel')`, ESM `import from 'dun:diagnostics_channel'` |
| `tty` | `registerTtyModule(engine)` | `require('tty')`, ESM `import from 'dun:tty'` |
| `constants` | stub (globalThis) | `require('constants')` |
| `module` | stub (globalThis) | `require('module')` — builtinModules, isBuiltin, createRequire |
| `timers` | stub (globalThis) | `require('timers')` — setTimeout, setInterval, etc. |
| `process` | stub (globalThis) | `require('process')` — delegates to global `process` |
| `console` | stub (globalThis) | `require('console')` — delegates to global `console` |
| `fetch` | `registerFetchGlobal(engine)` | Global `fetch()` (Posix, HTTPS via OpenSSL) |
| Web globals | `installWebCompat(engine)` | `atob`, `btoa`, `structuredClone`, `TextEncoder`, `TextDecoder`, native Uint8Array creation |
| Web APIs | `installWebAPIs(engine)` | `performance`, `EventTarget`, `Event`, `CustomEvent`, `AbortController`, `AbortSignal`, `DOMException`, `navigator`, `Blob`, `File`, `FormData`, `Headers`, `Request`, `Response`, `MessageChannel`, `MessagePort`, `BroadcastChannel`, `ReadableStream`, `WritableStream`, `TransformStream`, `CompressionStream`, `DecompressionStream`, `setImmediate`, `clearImmediate`, `Promise.withResolvers`, `crypto.getRandomValues`, `crypto.randomUUID`, `crypto.subtle`, `console.time/timeEnd/timeLog/count/countReset/table/dir/trace` |
| `Deno.*` | `installDenoCompat(engine)` | Full Deno compat (30+ APIs: env, fs, permissions, errors) |

All modules work identically across QuickJS, JSC, and V8 backends.
Workers work identically across QuickJS, JSC, and V8 backends.
Web APIs (101 checks) pass identically across all 3 backends.

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
- **SIMD hex encoding**: `hexEncodeBuf` uses `core.simd` + LDC `shufflevector` for zero-copy interleave (16 bytes → 32 hex chars/cycle, no scalar loop)
- **SIMD HTTP toLower**: `asciiToLowerBuf` lowercases HTTP header names 16 bytes/cycle via SIMD masks (used by `http.d` `parseRequestHeaders`)
- **SIMD byte search**: `findByte` scans buffers 16 bytes/cycle; LDC path uses `llvm_cttz` for O(1) first-match extraction
- **LDC load/store**: `ldc.simd.loadUnaligned`/`storeUnaligned` for correct unaligned SIMD access (no undefined behavior)
- **LDC prefetch**: `llvm_prefetch` hints for data cache warming in large buffer operations
- **Buffer bswap**: `bswap16`/`bswap32`/`bswap64` (LDC: single `llvm_bswap` instruction) for all Buffer BE read/write ops
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
- **HTTP O(1) hasActiveIO**: Counter-based `hasActiveHttpIO()` instead of O(n) scan of servers+connections per event loop tick
- **JSC cached __cbSlot__**: JSStringRef for `__cbSlot__` created once, eliminates create+release per native function call
- **JSC cached length**: JSStringRef for `"length"` property cached for `getArrayLength` hot path
- **JSC/V8 stackTerminate**: Stack buffer for property name null-termination, avoids `toStringz` GC allocation per `getProperty`/`setProperty`
- **V8 batch type query**: `dun_v8_value_get_type()` returns type tag in single FFI call (was 9 individual `isXxx` calls)
- **V8 thread-local value pool**: 512-entry pool eliminates mutex contention in trampoline value wrapping
- **UUID random byte pool**: Pre-fills 64 UUIDs worth of random bytes per `getrandom` syscall, amortizing kernel overhead
- **getrandom syscall**: Linux fast path uses `__NR_getrandom` syscall directly (no fd management)
- **JSHandle leak fixes**: `freeValue()` added to 40+ `getProperty`/`getGlobal` call sites across all builtins
- **Console format batch**: `__dun_format_console__` formats all args in single JS call (1 FFI call vs N per console.log)
- **LTO + mcpu=native**: Release builds use `--flto=thin`, `--mcpu=native`, `--inline-threshold=350`, `--hot-cold-split`

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
| QuickJS | C API (quickjs.h) | extern(C) -- manual D bindings, audited via ImportC `-H` | ~498 |
| JSC | C API (JSObjectRef) | extern(C) -- straightforward, ~90 functions | ~289 |
| JSC | C++ internals | extern(C++, "JSC") -- experimental cppbindings.d | ~30 |
| JSC | D TMP bridge | JSCTypeTag + JSCTypeChecks + getType() fast path | ~180 |
| V8 | C++ only | extern(C) via C shim (vendor/v8shim/) | ~868 C++ + 121 templates + ~112 D |
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
- **Headers from kassane/libv8**: V8 15.0.91 headers + monolith from `github.com/kassane/libv8/releases`
- **CREL relocations**: V8 14.9 monolith uses LLVM 19+ CREL format; requires LDC's internal linker (`--link-internally`, LLVM 21 based) on Linux — GNU ld 2.42 and lld-18 cannot process CREL

## Testing

See [TESTING.md](TESTING.md) — unit tests (118 quickjs+v8 / 47 jsc),
integration sweep (134/134 across 3 backends), 145 npm-compat checks,
98/98 ECMAScript spec, 35/35 TypeScript spec, 81/81 react-compat,
231/231 safe-features, 45/45 security audit, 12/12 ts_parity vs
`tsc`, 12/12 deno_deploy_compat vs Deno 2.7, 13/13
bun_bundler_compat vs Bun 1.3, sanitizer testing, stress benchmarks,
HTTP bench, Docker matrix. The quick recipe:

```sh
dub test -c unittest                   # unit tests
bash tests/integration/run.sh          # QuickJS integration
BACKEND=jsc DUN=./dun-jsc bash tests/integration/run.sh
BACKEND=v8  DUN=./dun-v8  bash tests/integration/run.sh
```

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

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DUN_HOME` | `$HOME/.dun` (Posix) / `%LOCALAPPDATA%\dun` (Windows) | User-global package store + transpile cache root |
| `DUN_DISABLE_TSC` | unset | Force scanner stripper instead of tsc transpile |
| `DUN_AUTO_INSTALL_TSC` | unset | Default tsc path auto-installs typescript into `$DUN_HOME/node_modules` (off by default; --typecheck always auto-installs) |
| `DUN_TSC_CACHE_MAX_ENTRIES` | 2000 | Max entries in the persistent transpile cache |
| `DUN_TSC_CACHE_MAX_MB` | 64 | Max size of transpile cache in MiB |
| `DUN_TSC_CACHE_TRIM_INTERVAL_SECS` | 300 | Min seconds between trim sweeps (rate-limit via `.last_trim` marker) |
| `DUN_TSC_CACHE_DEBUG` | unset | Print cache write/trim errors to stderr |
| `DUN_TSC_QUIET` | unset | Suppress "tsc transpile failed; using scanner" warning |
| `DUN_TYPECHECK_DEBUG` | unset | Dump --typecheck driver to /tmp on engine error |
| `DUN_REPL_HISTORY` | `~/.dun_repl_history` | REPL history file path |
| `DUN_REPL_HISTORY_SIZE` | 1000 | Max REPL history entries |
| `DUN_TEST_TIMEOUT` | 30 | Per-fixture timeout (seconds) for integration runner |

The transpile cache lives at `$DUN_HOME/cache/tsc/<first-2-chars>/<full-hash>.js`.
`dun clean` removes only the project-local `.dun/` and `node_modules/` — it does NOT
touch the user-global `$DUN_HOME/` store. Wipe that manually if needed.

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

Benchmark impact (25 benchmarks, feature_bench.js, release builds):

| Config | dun-qjs ops/sec | dun-jsc ops/sec | dun-v8 ops/sec | GCs |
|--------|----------------:|----------------:|---------------:|----:|
| **Default (16 MB pool)** | 23.7M | **513M** | 165M | 6–25 |
| minPoolSize:32 | 23.5M | 497M | 169M | 3–12 |
| minPoolSize:64 | 23.3M | 463M | 163M | 2–7 |
| parallel:4 | 22.6M | 508M | 162M | 6–23 |
| gc:precise | 22.6M | 497M | 169M | 6–23 |

The 16 MB default is at the throughput knee — `minPoolSize:32` halves
GC count but throughput barely moves (within noise). `minPoolSize:64`
actually regresses JSC throughput ~10% (pool re-allocs cost more than
the saved collections). `parallel:4` is a no-op or slight loss on
single-threaded workloads (single JS thread); useful for Worker-heavy
apps. `gc:precise` is a no-op on feature_bench's working set.

GC time itself is already negligible (1–5 ms over a 14–15 s run).
Don't change the default unless you have profile data showing GC
overhead — `--DRT-gcopt=profile:1` reports it.

## D-side previews + DIPs enabled

`dub.json` `dflags` enables five DMD/LDC previews. Each maps to an
accepted DIP and tightens what the compiler will accept:

| Preview | Effect | DIP |
|---------|--------|-----|
| `fixImmutableConv` | Disallow unsafe immutable conversions | (LDC patch) |
| `fixAliasThis` | Strict `alias this` lookup order | (LDC patch) |
| `rvaluerefparam` | Allow rvalue → `ref` parameter binding | (LDC patch) |
| `safer` | `@safe` is the default for non-extern functions | (in progress) |
| `dip1000` | Scope / `return scope` lifetime tracking on slices, refs, pointers | [DIP 1000](https://github.com/dlang/DIPs/blob/master/DIPs/other/DIP1000.md) |

DIP1000 specifically: `scope` is **not** inferred for virtual / interface
methods, so engine APIs that return slices into engine-owned memory must
spell out `return scope` on both the interface declaration and every
backend override. We currently annotate:

- `IJSEngine.getTypedArrayBytes(return scope JSHandle val) → ubyte[]`
- `dun.builtins.buffer.extractBytes(IJSEngine, return scope JSHandle) → ubyte[]`

Callers that need the slice past the JSHandle's lifetime (e.g. shipping
into an `asyncSubmit` worker) must `.dup`. Compiler-checked.

DIP1038 (`@mustuse` from `core.attribute`) annotates struct returns
whose value must never be silently dropped. We currently annotate:

- `JSResult` — every `engine.eval(...)` / `engine.evalModule(...)`
  caller must either check `isError` or hand the value to a consumer.
- `AsyncResult` — every `asyncSubmitSafe` work delegate must build
  a result via `AsyncResult.ok(...)` / `AsyncResult.fail(...)` and
  return it (vs. silently discarding the constructed value).

For closed-world inline JS init code where a parse failure is a
build-time bug rather than user data, use the canonical drop-only
consumer:

```d
mustEval(engine, source, filename, what);  // asserts !isError, frees value
```

Defined in `dun.engine.iface`. Used by `worker_api.installWorkerAPI`
(Worker constructor installer) and `workers.worker._runWorker`
(`__filename`/`__dirname` setup).

## Phased Roadmap

See [CHANGELOG.md](CHANGELOG.md) — historical record of every
phased delivery (150+ phases across 26 major releases). The
production-blockers list is empty as of v0.4.0; every blocker
has either landed or has a documented design-level rationale
below.

## Won't-fix design constraints

- **Native `.node` addons that bypass N-API.** Things that
  `dlopen('node')` and call into V8 / libuv internals can't be
  supported by any non-Node runtime. Addons that stay within
  the N-API surface work — DunJS ships 91 N-API functions plus
  real `napi_wrap` / `napi_create_external` with a side-table
  for the `(data, hint, finalize_cb)` triple. Tested with sharp
  + similar real addons.

- **Host-specific API tests on the wrong host.** Some entries
  in `tests/benchmarks/ts_compat/` exercise APIs that don't
  exist on every runtime (e.g. `Bun.hash.xxh32` isn't on
  Bun 1.3 either, and Deno/Node lack `Bun.*` entirely). These
  files are useful as cross-runtime delta indicators, not as
  conformance gates.

- **Full Bun parser port** (TS AST + printer + lowering).
  Researched and rejected in v0.3.x: 3-5 person-months to
  replace a working scanner with one that produces the same
  observable output (DunJS now matches `tsc + node` on
  `tests/benchmarks/ts_parity/` 12/12 across all 3 backends).
  Re-evaluate only if DunJS gets a bundler / source maps /
  AST-based linter — none are on the roadmap. The lexer-only
  lift in `source/dun/ts/parser/lexer.d` is the right amount
  of port for the scanner pipeline.
