# DunJS

A secure JavaScript runtime written in **D**, inspired by [Deno](https://deno.com), [Bun](https://bun.sh), and [Node.js](https://nodejs.org).

## Features

- **Pluggable JS engine** — IJSEngine interface with QuickJS, JSC, and V8 backends (all fully functional)
- **Security-first** — Default-deny permissions (like Deno)
- **D language** — Zero-cost C FFI, `@safe`/`@trusted` memory safety, RAII resource management
- **eventcore** async I/O — Native D event loop with epoll/kqueue/IOCP support
- **Small binary** — Target <5MB standalone executable
- **Built-in modules** — `dun:fs`, `dun:path`, `dun:net`, `dun:http`, `dun:crypto`

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
dub test -c unittest          # 49 BDD-style engine contract + fuzz tests
```

### Run

```sh
# Run a JavaScript file
./dun run script.js

# Run with permissions
./dun run --allow-read=./data --allow-net script.js

# Interactive REPL
./dun repl

# Evaluate inline
./dun eval "console.log('Hello from DunJS!')"
```

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

DunJS is organized in 7 layers:

| Layer | Purpose | Directory |
|-------|---------|-----------|
| 7 | CLI & REPL | `source/dun/cli/` |
| 6 | Runtime API (console, timers, process) | `source/dun/runtime/` |
| 5 | Module System (ES modules, resolver) | `source/dun/modules/` |
| 4 | Built-in Modules (fs, path, net, http) | `source/dun/builtins/` |
| 3 | Event Loop (eventcore, timers, microtasks) | `source/dun/loop/` |
| 2 | JS Engine Abstraction (IJSEngine + backends) | `source/dun/engine/` |
| 1 | Platform Abstraction (memory, threading) | `source/dun/platform/` |

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed design documentation.

## Engine Backends

| Backend | API | FFI | Status | Use Case |
|---------|-----|-----|--------|----------|
| QuickJS-NG | C (quickjs.h) | `extern(C)` direct | **12/12 tests pass** | Default, ES2023 fallback |
| JavaScriptCore | C (JSObjectRef) | `extern(C)` direct | **12/12 tests pass** | JIT, production (like Bun) |
| V8 | C++ via C shim | `extern(C)` → v8shim | **12/12 tests pass** | JIT, Node.js compatibility |

All backends support: `console.log/info/debug/warn/error/assert`, Promises, async/await,
ES2020+ features (optional chaining, nullish coalescing, Array.at, Object.hasOwn).

### V8 C++ Shim

V8 has no stable C API. DunJS uses a thin C++ wrapper (`vendor/v8shim/`) that exposes
V8 operations as `extern "C"` functions callable from D:

```
D (backend.d) ──extern(C)──> v8shim.cpp ──C++──> V8 API
                                │
                    FunctionTemplate trampoline
                    Context::Scope on every op
                    Ref-counted value wrappers
```

V8 headers are vendored from Node.js — no `libv8-dev` needed for compilation.

## Built-in Modules

| Module | Description |
|--------|-------------|
| `dun:fs` | File system operations (read, write, stat, mkdir) |
| `dun:path` | Path manipulation (join, resolve, basename, dirname) |
| `dun:net` | TCP/UDP sockets |
| `dun:http` | HTTP client and server |
| `dun:crypto` | Hashing, random bytes |
| `dun:os` | Platform information |
| `dun:url` | URL parsing |

```js
import { readFileSync } from "dun:fs";
import { join } from "dun:path";

const content = readFileSync(join(".", "data", "config.json"));
console.log(content);
```

## Testing

### Unit Tests (49 tests)

BDD-style engine contract tests + fuzz/stress tests:

```sh
dub test -c unittest
```

### Integration Tests (12 tests × 3 backends)

Standalone JS scripts compared against expected stdout (inspired by Node.js test patterns):

| Test | Coverage |
|------|----------|
| `hello` | Basic console.log |
| `types` | typeof for all JS types |
| `console_methods` | log/info/debug, multiple args, type coercion |
| `promises` | Promise + async/await |
| `promises_advanced` | Promise.all/race/any, async error handling |
| `es2023` | findLast, optional chaining, nullish coalescing, Array.at |
| `error_handling` | try/catch, Error subtypes, Error.cause, finally, custom errors |
| `closures` | Closures, IIFE, block scoping, generators, destructuring |
| `iterators` | Map, Set, WeakRef, for...of, Array.from, method chains |
| `json_parsing` | JSON parse/stringify, replacer/reviver, error handling |
| `classes` | Inheritance, static methods, private fields, computed properties |
| `regex` | Named groups, matchAll, replace, split, flags |

## Comparison

| | Node.js | Deno | Bun | **DunJS** |
|--|---------|------|-----|-----------|
| Language | C++ | Rust | Zig→Rust | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable (3 backends)** |
| Engine FFI | Native C++ | rusty_v8 | Zig extern(C++) | **extern(C) + C shim** |
| Event Loop | libuv | Tokio | io_uring | **eventcore** |
| Permissions | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |

## Development Status

DunJS is in early development. See the [phased roadmap](CLAUDE.md#phased-roadmap) for progress.

| Phase | Status |
|-------|--------|
| Phase 1: MVP (`dun run hello.js`) | **Done** |
| Phase 1b: Multi-engine (JSC + V8) | **Done** |
| Phase 2: Event loop + timers | In progress |
| Phase 3: Module system + builtins | Planned |
| Phase 4: Permission enforcement | Planned |

## License

[MIT](LICENSE)
