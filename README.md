# DunJS

A secure JavaScript runtime written in **D**, inspired by [Deno](https://deno.com), [Bun](https://bun.sh), and [Node.js](https://nodejs.org).

## Features

- **Pluggable JS engine** — IJSEngine interface with JSC, Hermes, QuickJS backends
- **Security-first** — Default-deny permissions (like Deno)
- **D language** — Zero-cost C FFI, `@safe`/`@trusted` memory safety, RAII resource management
- **eventcore** async I/O — Native D event loop with epoll/kqueue/IOCP support
- **Small binary** — Target <5MB standalone executable
- **Built-in modules** — `dun:fs`, `dun:path`, `dun:net`, `dun:http`, `dun:crypto`

## Quick Start

### Prerequisites

- **D compiler**: [DMD](https://dlang.org/download.html) or [LDC](https://github.com/ldc-developers/ldc/releases)
- **C compiler**: GCC or Clang
- **Make**: GNU Make

### Build

```sh
git clone https://github.com/kassane/dunjs.git
cd dunjs
git submodule update --init --recursive
dub build
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

## Comparison

| | Node.js | Deno | Bun | **DunJS** |
|--|---------|------|-----|-----------|
| Language | C++ | Rust | Zig→Rust | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable** |
| Event Loop | libuv | Tokio | io_uring | **eventcore** |
| Permissions | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |

## Development Status

DunJS is in early development. See the [phased roadmap](CLAUDE.md#phased-roadmap) for implementation progress.

## License

[MIT](LICENSE)
