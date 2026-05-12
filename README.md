# DunJS

A secure, multi-engine JavaScript/TypeScript runtime written in D.

```sh
dun run server.ts --allow-net --allow-read
```

## Why DunJS?

- **Three JS engines, one API.** Switch between QuickJS-NG, JavaScriptCore, and V8 at build time. Same code runs on all three.
- **Secure by default.** No file, network, or environment access unless explicitly granted. Modeled after Deno's permission system.
- **TypeScript without a build step.** Run `.ts` files directly via type stripping.
- **npm packages work.** `dun install express` fetches from the npm registry. `require()` resolves `node_modules/` the Node.js way.
- **HTTPS out of the box.** `fetch()` supports TLS 1.2+ via OpenSSL.
- **Deno compatibility.** 30+ Deno APIs: env, fs (stat, mkdir, remove, rename, copy, readDir), permissions.query, errors, hostname, inspect.
- **Web standard globals.** `atob`, `btoa`, `TextEncoder`, `TextDecoder`, `structuredClone`.

## Install

Requires [LDC](https://github.com/ldc-developers/ldc/releases) >= 1.42.0 and a C compiler.

```sh
git clone https://github.com/kassane/dunjs.git && cd dunjs
ldc2 -run build.d --backend=quickjs
dub build
```

Other backends:

```sh
dub build -c jsc    # JavaScriptCore (Linux: libjavascriptcoregtk, macOS: framework)
dub build -c v8     # V8 (via C++ shim)
```

## Usage

```sh
dun run app.js                          # Run JavaScript
dun run app.ts                          # Run TypeScript (type stripping)
dun run --allow-read=./data app.js      # Scoped file access
dun run --allow-net=api.example.com app.js  # Scoped network access
dun run --allow-all app.js              # Unrestricted
dun install lodash                      # Install npm package
dun install lodash --audit=block        # Block vulnerable packages
dun audit                               # Scan node_modules for CVEs
dun repl                                # Interactive REPL
dun eval "1 + 1"                        # Evaluate expression
```

## Built-in Modules

```js
import { readFileSync } from "dun:fs";
import { join } from "dun:path";
import { createHash } from "dun:crypto";

// Also available via require()
const http = require("http");
const { Buffer } = require("buffer");
const { EventEmitter } = require("events");
```

| Module | API |
|--------|-----|
| `dun:fs` | readFileSync, writeFileSync, existsSync, statSync, mkdirSync |
| `dun:path` | join, resolve, basename, dirname, extname, normalize |
| `dun:net` | createServer, createConnection (TCP) |
| `dun:http` | createServer, listen, close (HTTP/1.1) |
| `dun:crypto` | createHash, randomBytes |
| `dun:os` | platform, arch, hostname, cpus, totalmem, freemem, uptime |
| `dun:buffer` | Buffer.from, Buffer.alloc, concat, slice, toString |
| `dun:events` | EventEmitter (on, once, off, emit, listeners) |
| `dun:url` | URL, URLSearchParams |

Global: `fetch()`, `setTimeout`/`setInterval`, `console`, `process`, `Deno.*`, `atob`/`btoa`, `TextEncoder`/`TextDecoder`, `structuredClone`

## npm Support

```sh
dun install is-odd
```

```js
const isOdd = require("is-odd");
console.log(isOdd(3)); // true
```

Dependencies are resolved transitively. Packages are downloaded from `registry.npmjs.org` over HTTPS and extracted into `node_modules/`.

### Security Auditing

```sh
dun audit                           # Scan node_modules for known CVEs
dun install lodash --audit=block    # Block critical/high severity
dun install lodash --audit=off      # Skip CVE checks
```

DunJS queries [Google's OSV database](https://osv.dev) for real-time vulnerability data, cached locally
for 24 hours. `dun install` checks packages before download. See [SECURITY.md](SECURITY.md) for details.

## Permissions

| Flag | Grants |
|------|--------|
| `--allow-read[=paths]` | File system read |
| `--allow-write[=paths]` | File system write |
| `--allow-net[=hosts]` | Network access |
| `--allow-env[=vars]` | Environment variables |
| `--allow-run[=cmds]` | Child processes |
| `--allow-all` / `-A` | Everything |
| `--deny-*` | Overrides allow (always wins) |

## Engine Backends

| Backend | Tests | Notes |
|---------|-------|-------|
| QuickJS-NG | 46/46 | Default. Interpreter, ES2023, smallest binary (4.6MB) |
| JavaScriptCore | 45/45 | JIT. Same engine as Safari/Bun |
| V8 | 45/45 | JIT. Same engine as Chrome/Node.js. Via C++ shim |

All 9 built-in modules, fetch, Deno compat, and web globals work on every backend.

## Architecture

Seven layers, zero coupling between engine backends and runtime APIs:

```
CLI/REPL  ->  Runtime (console, timers, process, Deno.*)
          ->  Modules (ESM, CJS, npm resolver)
          ->  Builtins (fs, path, net, http, crypto, os, buffer, events, url, fetch)
          ->  Event Loop (epoll/kqueue/poll/io_uring, timer wheel, microtasks)
          ->  Engine Abstraction (IJSEngine interface)
          ->  Platform (OpenSSL TLS, memory, threading)
```

Upper layers use `IJSEngine` -- only `engine/<backend>/` touches raw engine APIs.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.

## Testing

```sh
dub test -c unittest                    # ~150 unit tests
./tests/integration/run.sh              # 44 integration tests
```

| Suite | Tests |
|-------|-------|
| Engine contract | ~50 BDD-style (eval, types, properties, exceptions, promises) |
| Fuzz/stress | ~50 (rapid create/destroy, string stress, exception recovery) |
| TypeScript strip | 20 (annotations, interfaces, as, declare, arrow types) |
| Security | 27 (default deny, scoped grants, deny overrides, parseFlag) |
| Integration | 46 fixtures (core JS, async, ES2023+, modules, builtins, Deno compat, TypeScript, real-world) |

## Comparison

| | Node.js | Deno | Bun | DunJS |
|--|---------|------|-----|-------|
| Language | C++ | Rust | Zig | D |
| Engine | V8 | V8 | JSC | Pluggable (3) |
| TypeScript | Via tsc | Built-in | Built-in | Type stripping |
| Permissions | None | Default-deny | None | Default-deny |
| npm | Native | `npm:` specifier | Native | `dun install` |
| TLS | OpenSSL | rustls | BoringSSL | OpenSSL |
| Deno compat | No | -- | None | 30+ APIs |
| Startup | ~30ms | ~30ms | ~8ms | **~3.5ms** |
| Binary | ~90MB | ~120MB | ~100MB | **4.6MB** |

### Performance

Total wall time across 16 real-world benchmarks (lower is better):

| Runtime | Total Time | vs Deno |
|---------|-----------|---------|
| Deno | 3.4s | 1.00x |
| DunJS V8 | 3.6s | 1.05x |
| Bun | 4.0s | 1.18x |
| DunJS JSC | 4.4s | 1.29x |
| DunJS QuickJS | 18.7s | 5.50x |

DunJS V8 is competitive with Deno and Bun on JIT-optimized workloads.
QuickJS is an interpreter (no JIT) -- it trades raw speed for smallest binary size (4.6MB).

Selected benchmark (TextEncoder/TextDecoder, 100k iterations):

| Runtime | Time |
|---------|------|
| Bun | 15ms |
| DunJS QuickJS | 50ms |
| Deno | 62ms |

Feature compatibility: **39/39 checks** pass across all runtimes.

## License

[MIT](LICENSE)
