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
dun test                                # Run test files (Deno.test API)
dun test mytest.ts --filter=name        # Filter tests by name
dun bench                               # Run benchmarks (Deno.bench API)
dun init my-project                     # Scaffold a new project
dun fmt                                 # Format JS/TS files
dun clean                               # Remove cache and node_modules
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
| `dun:http2` | HTTP/2 with ALPN/TLS, HPACK, stream multiplexing |
| `dun:crypto` | createHash, randomBytes, randomUUID |
| `dun:os` | platform, arch, hostname, cpus, totalmem, freemem, uptime |
| `dun:buffer` | Buffer.from, Buffer.alloc, concat, slice, toString |
| `dun:events` | EventEmitter (on, once, off, emit, listeners) |
| `dun:url` | URL, URLSearchParams |
| `dun:sqlite` | open, exec, run, get, all, close (in-memory + file DBs) |
| `dun:child_process` | execSync, spawnSync, exec |
| `dun:stream` | Readable, Writable, Duplex, Transform, pipeline |
| `dun:zlib` | deflateSync, inflateSync, gzipSync, gunzipSync |
| `dun:dns` | lookup, lookupSync, resolve4, resolve6, reverse |
| `dun:ws` | WebSocket client/server (RFC 6455) |
| `dun:util` | inspect, format, types, promisify |
| `dun:assert` | ok, equal, deepEqual, throws, rejects |
| `dun:vm` | runInThisContext, runInNewContext, createContext, Script |
| `dun:cluster` | fork, isPrimary, isWorker, on('exit') |
| `dun:async_hooks` | AsyncLocalStorage (run, getStore, enterWith, disable) |
| `dun:worker_threads` | isMainThread, threadId, Worker, parentPort |

Global: `fetch()`, `Worker`, `SharedArrayBuffer`, `Atomics`, `setTimeout`/`setInterval`, `console`, `process`, `Deno.*`, `atob`/`btoa`, `TextEncoder`/`TextDecoder`, `structuredClone`

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
| QuickJS-NG | 66/66 | Default. Interpreter, ES2023, smallest binary (4.6MB) |
| JavaScriptCore | 66/66 | JIT. Same engine as Safari/Bun |
| V8 | 66/66 | JIT. Same engine as Chrome/Node.js (V8 14.9). Via C++ shim |

All 24 built-in modules, Workers, SharedArrayBuffer, Atomics, fetch, Deno compat, and web globals work identically on every backend.

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
dub test -c unittest                    # ~175 unit tests
./tests/integration/run.sh              # 66 integration tests (all 3 backends)
```

| Suite | Tests |
|-------|-------|
| Engine contract | ~50 BDD-style (eval, types, properties, exceptions, promises) |
| Fuzz/stress | ~50 (rapid create/destroy, string stress, exception recovery) |
| TypeScript strip | 20 (annotations, interfaces, as, declare, arrow types) |
| Security | 38 (permissions 27 + CVE audit 8 + security tests 3) |
| HTTP/2 | 15 (frame encoding, HPACK, static table, settings) |
| HTTP/3 | 12 (QUIC varint encode/decode, H3 frame header, SETTINGS payload) |
| Integration | 66 tests (core JS, async, ES2023+, modules, 28 builtins, Workers, Deno compat, TypeScript, fetch Response, import.meta, vm, async_hooks, signals, REPL, CLI, real-world) |

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

Feature benchmarks (25 tests, ops/sec — higher is better):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.11 | 399M | 1.00x |
| DunJS JSC | 373M | 0.94x |
| Node.js v22 | 118M | 0.30x |
| DunJS V8 | 103M | 0.26x |

Framework benchmarks (39 tests, ops/sec):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.11 | 275M | 1.00x |
| DunJS JSC | 260M | 0.95x |
| DunJS V8 | 138M | 0.50x |
| Node.js v22 | 125M | 0.45x |

HTTP stress (wrk, 128 connections, req/sec — higher is better):

| Endpoint | Bun | Deno | DunJS V8 | DunJS QJS | Node.js |
|----------|-----|------|----------|-----------|---------|
| /plaintext | 55,487 | 52,086 | 37,298 | 48,084 | 28,238 |
| /json | 53,093 | 49,783 | 38,924 | **55,888** | 29,398 |
| /compute | 55,132 | 42,544 | 39,778 | 40,334 | 27,372 |
| /transaction | 42,694 | 41,792 | 34,138 | 26,501 | 19,046 |

DunJS JSC is 94-95% of Bun on JS compute. DunJS V8 beats Node.js on all HTTP endpoints.
npm compat: **145/145** pass across all 6 runtimes.

## License

[MIT](LICENSE)
