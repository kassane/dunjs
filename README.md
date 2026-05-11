# DunJS

A secure JavaScript/TypeScript runtime written in **D**, inspired by [Deno](https://deno.com), [Bun](https://bun.sh), and [Node.js](https://nodejs.org).

## Features

- **Pluggable JS engine** -- IJSEngine interface with QuickJS-NG, JavaScriptCore, and V8 backends
- **TypeScript support** -- Run `.ts`/`.mts`/`.cts` directly via type stripping (like Node.js `--experimental-strip-types`)
- **Security-first** -- Default-deny permissions (like Deno): `--allow-read`, `--allow-net`, etc.
- **D language** -- Zero-cost C FFI, `@safe`/`@trusted` memory safety, RAII resource management
- **C++ TMP bridge** -- Cross-language template metaprogramming between D and C++ (V8 + JSC backends)
- **Cross-platform I/O** -- Native poller (epoll on Linux, kqueue on macOS/BSD, poll(2) fallback)
- **Small binary** -- Target <5MB standalone executable
- **Built-in modules** -- `dun:fs`, `dun:path`, `dun:net`, `dun:http`, `dun:crypto`, `dun:os`, `dun:buffer`, `dun:events`, `dun:url`

## Quick Start

### Prerequisites

- **D compiler**: [LDC](https://github.com/ldc-developers/ldc/releases) >= 1.42.0 or [DMD](https://dlang.org/download.html) >= 2.112.1
- **C compiler**: GCC or Clang
- **CMake**: For building QuickJS-NG

### Build

```sh
git clone https://github.com/kassane/dunjs.git
cd dunjs

# Build vendor dependencies (downloads + compiles automatically)
ldc2 -run build.d --backend=quickjs

# Default (QuickJS-NG backend)
dub build

# Explicit backend selection
dub build -c quickjs          # QuickJS-NG (default, ES2023)
dub build -c jsc              # JavaScriptCore (Linux: GTK, macOS: framework)
dub build -c v8               # V8 (via C++ shim, headers vendored from Node.js)

# Release build
dub build -c quickjs -b release

# Run tests
dub test -c unittest          # BDD-style engine + TS + security tests
```

### Run

```sh
# Run a JavaScript file
./dun run script.js

# Run a TypeScript file (type stripping, no tsc needed)
./dun run script.ts

# Run with permissions
./dun run --allow-read=./data --allow-net script.js

# Interactive REPL
./dun repl

# Evaluate inline
./dun eval "console.log('Hello from DunJS!')"
```

## TypeScript

DunJS runs `.ts`, `.mts`, and `.cts` files directly via type stripping -- no `tsc` or build step needed.
Types are replaced with whitespace to preserve source positions for accurate error messages.

```ts
// hello.ts -- runs directly with: dun run hello.ts
interface User { name: string; age: number }

function greet(user: User): string {
    return `Hello, ${user.name}!`;
}

console.log(greet({ name: "World", age: 42 }));
```

**Supported**: type annotations, `interface`, `type` aliases, `import type`, `as T`, `declare`, `abstract`, generics, optional parameters.

**Not supported** (have runtime semantics): `enum`, `namespace`, constructor parameter properties.

## Security

DunJS uses a **default-deny** permission model. Scripts have no access to the
file system, network, or environment unless explicitly granted:

```sh
./dun run script.js                              # No I/O allowed
./dun run --allow-read=./data script.js          # Read only ./data
./dun run --allow-net=api.example.com script.js  # Network to one host
./dun run --allow-all script.js                  # Full access
```

See [SECURITY.md](SECURITY.md) for the full security policy and threat model.

## Architecture

DunJS is organized in 7 layers plus cross-cutting concerns:

| Layer | Purpose | Directory |
|-------|---------|-----------|
| 7 | CLI & REPL | `source/dun/cli/` |
| 6 | Runtime API (console, timers, process) | `source/dun/runtime/` |
| 5 | Module System (ES modules, resolver) | `source/dun/modules/` |
| 4 | Built-in Modules (fs, path, net, http, crypto, os, buffer, events, url) | `source/dun/builtins/` |
| 3 | Event Loop (epoll/kqueue/poll, timers, microtasks) | `source/dun/loop/` |
| 2 | JS Engine Abstraction (IJSEngine + backends) | `source/dun/engine/` |
| 1 | Platform Abstraction (memory, threading) | `source/dun/platform/` |
| Cross | TypeScript type stripping | `source/dun/ts/` |
| Cross | Security (permissions, sandbox) | `source/dun/security/` |

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design documentation.

## Engine Backends

| Backend | API | FFI | Status | Use Case |
|---------|-----|-----|--------|----------|
| QuickJS-NG | C (quickjs.h) | `extern(C)` direct | **44/44 tests pass** | Default, ES2023 fallback |
| JavaScriptCore | C (JSObjectRef) | `extern(C)` direct | **42/42 tests pass** | JIT, production (like Bun) |
| V8 | C++ via C shim | `extern(C)` via v8shim | **42/42 tests pass** | JIT, Node.js compatibility |

All backends support: `console.log/info/debug/warn/error/assert`, Promises, async/await,
ES2020+ features (optional chaining, nullish coalescing, Array.at, Object.hasOwn).

### C++ TMP Bridge

V8 and JSC backends use a **cross-language template metaprogramming bridge** -- C++ templates
(`withContext<F>`, `isV8Type<Tag>`) and D compile-time features (`V8TypeTag`, `V8TypeChecks`,
`static foreach`) mirror each other across the FFI boundary. Both resolve at compile time
with zero runtime overhead.

```
C++ side (v8shim_tmpl.hpp)           D side (cppbindings.d)
  V8Tag enum                    <-->   V8TypeTag enum
  V8TypeMap<Tag>                <-->   V8TypeName template
  isV8Type<Tag> (if constexpr)  <-->   V8TypeChecks (fn ptr table)
  withContext<F> (RAII scope)   <-->   backend.d checkType()
```

JSC uses the same pattern with `JSCTypeTag` mirroring `kJSType*` constants, plus a
`getType()` fast path via `JSValueGetType()` for single-call type dispatch.

### V8 C++ Shim

V8 has no stable C API. DunJS uses a thin C++ wrapper (`vendor/v8shim/`) that exposes
V8 operations as `extern "C"` functions callable from D:

```
D (backend.d) --extern(C)--> v8shim.cpp --C++--> V8 API
                                |
                    withContext<F> scope guard
                    FunctionTemplate trampoline
                    Ref-counted value wrappers
```

V8 headers are vendored from Node.js -- no `libv8-dev` needed for compilation.

## Built-in Modules

| Module | Description | Engine Support |
|--------|-------------|----------------|
| `dun:fs` | File system operations (read, write, stat, mkdir) | All |
| `dun:path` | Path manipulation (join, resolve, basename, dirname) | All |
| `dun:net` | TCP sockets (createServer, createConnection) | All |
| `dun:http` | HTTP/1.1 server (createServer, listen, close) | All |
| `dun:crypto` | Hashing (createHash), randomBytes | All |
| `dun:os` | Platform info (hostname, cpus, totalmem, freemem, uptime) | All |
| `dun:buffer` | Buffer (from, alloc, concat, slice, toString, encodings) | All |
| `dun:events` | EventEmitter (on, once, off, emit, listeners) | All |
| `dun:url` | URL + URLSearchParams (parse, format, search params) | All |

```js
import { readFileSync } from "dun:fs";
import { join } from "dun:path";

const content = readFileSync(join(".", "data", "config.json"));
console.log(content);
```

## Testing

### Unit Tests

```sh
dub test -c unittest
```

| Suite | File | Tests |
|-------|------|-------|
| Engine contract | `source/dun/engine/test.d` | ~50 BDD-style tests |
| Fuzz/stress | `source/dun/engine/fuzz.d` | ~50 edge-case tests |
| TypeScript strip | `source/dun/ts/strip.d` | 20 inline tests |
| Security perms | `source/dun/security/test.d` | 27 permission tests |

### Integration Tests (44 fixtures)

Standalone JS/TS scripts compared against expected stdout:

| Category | Tests | Coverage |
|----------|-------|----------|
| Core JS | `hello`, `types`, `console_methods` | Basic output, typeof, multi-arg logging |
| Async | `promises`, `promises_advanced`, `timers`, `phase2`, `phase2_rejection`, `async_io` | Promise.all/race/any, async/await, setTimeout, unhandledRejection |
| ES2023+ | `es2023`, `closures`, `iterators`, `classes`, `regex`, `json_parsing` | findLast, generators, Map/Set, private fields, matchAll |
| Errors | `error_handling` | try/catch, Error subtypes, Error.cause, finally |
| Modules | `module_esm`, `module_cjs`, `module_chain`, `json_pipeline`, `npm_compat` | ESM import/export, CJS require, chained deps, JSON import |
| Builtins | `fs_ops`, `path_ops`, `crypto_ops`, `stat_file`, `env_access` | readFile, join/resolve, hash/randomBytes, stat, process.env |
| Node.js APIs | `buffer_api`, `event_emitter`, `url_api`, `os_api` | Buffer, EventEmitter, URL/URLSearchParams, os module |
| Security | `perm_deny_read`, `perm_deny_write` | Permission denial enforcement |
| TypeScript | `typescript`, `realworld_ts_library` | Type annotations, interfaces, as, arrow types |
| Real-world | 8 end-to-end scenarios | Config loading, task runner, file processing, events, promise pool, nested require, security boundary, ESM pipeline |

## Comparison

| | Node.js | Deno | Bun | **DunJS** |
|--|---------|------|-----|-----------|
| Language | C++ | Rust | Zig | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable (3 backends)** |
| TypeScript | Via tsc/swc | Built-in | Built-in | **Type stripping** |
| Engine FFI | Native C++ | rusty_v8 | Zig extern(C++) | **extern(C) + C shim** |
| Event Loop | libuv | Tokio | io_uring | **epoll/kqueue/poll** |
| Permissions | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |
| TMP Bridge | N/A | N/A | N/A | **C++ TMP <-> D TMP** |

## Development Status

DunJS is in active development. See the [phased roadmap](CLAUDE.md#phased-roadmap) for progress.

| Phase | Status |
|-------|--------|
| Phase 1: MVP (`dun run hello.js`) | **Done** |
| Phase 1b: Multi-engine (JSC + V8) | **Done** |
| Phase 1c: TypeScript (`dun run file.ts`) | **Done** |
| Phase 1d: Security tests (27 PermissionRegistry tests) | **Done** |
| Phase 1e: C++ TMP <-> D TMP bridge (V8 + JSC) | **Done** |
| Phase 2: Event loop + timers + Promises | **Done** |
| Phase 2f: queueMicrotask + process.nextTick + unhandledRejection | **Done** |
| Phase 3: Module system + fs/path/net/crypto | **Done** |
| Phase 4: Permission enforcement wired to builtins | **Done** |
| Phase 5: REPL + colored errors + stack traces | **Done** |
| Phase 6a: Networking (TCP, npm compat, I/O polling) | **Done** |
| Phase 6b: HTTP server (HTTP/1.1 createServer/listen/close) | **Done** |
| Phase 6c: Workers (Web Workers, SharedArrayBuffer, Atomics) | **Done** |
| Phase 6d: io_uring (Linux io_uring backend for IOPoller) | **Done** |
| Phase 7a: Engine parity (net/http ported to engine-agnostic) | **Done** |
| Phase 7b: Node.js APIs (Buffer, EventEmitter, URL, os) | **Done** |
| Phase 7c: Safety (`-preview=safer` default) | **Done** |

## License

[MIT](LICENSE)
