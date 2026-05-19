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
- **Deno compatibility.** 30+ Deno APIs: env, fs (stat, mkdir, remove, rename, copy, readDir), permissions.query, errors, hostname, inspect, `Deno.serve`, `Deno.Command`, `Deno.dlopen`.
- **Web standard globals.** `atob`, `btoa`, `TextEncoder`, `TextDecoder`, `structuredClone`, plus the full v0.6.0 surface: `localStorage`/`sessionStorage`, `caches`, `FileReader`, `DOMRect`/`Point`/`Matrix`/`Quad`, `ImageData`, `PerformanceObserver`, `MessageEvent`/`ErrorEvent`/`CloseEvent`/`PromiseRejectionEvent`, observers, `WebTransport`, `IndexedDB`, `Notification`, `CookieStore`, `ImageBitmap` (38/38 audit on every backend).

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
dun test --concurrent                   # Run tests in parallel (Bun parity)
dun test --concurrent --max-concurrency=8
dun bench                               # Run benchmarks (Deno.bench API)
dun lint                                # Lint .js/.ts files (no-eval / eqeqeq / no-debugger)
dun lint src/                           # Lint a directory tree
dun bundle entry.ts --outdir ./dist     # Bundle (Bun.build)
dun bundle entry.ts --sourcemap         # Bundle + sibling .map file (V3)
dun bundle entry.ts --sourcemap=inline  # Bundle + inline data: URI map
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
| `dun:assert` | ok, equal, deepEqual, throws, rejects (plus `node:assert/strict` alias) |
| `dun:test` | test, describe, it, before, after, beforeEach, afterEach (TAP-style runner) |
| `dun:vm` | runInThisContext, runInNewContext, createContext, Script |
| `dun:cluster` | fork, isPrimary, isWorker, on('exit') |
| `dun:async_hooks` | AsyncLocalStorage (run, getStore, enterWith, disable) |
| `dun:worker_threads` | isMainThread, threadId, Worker, parentPort |

Globals: `fetch()`, `Worker`, `SharedArrayBuffer`, `Atomics`, `setTimeout`/`setInterval`/`setImmediate`, `console`, `process`, `Bun.*`, `Deno.*`, `atob`/`btoa`, `TextEncoder`/`TextDecoder`, `structuredClone`, `crypto.subtle`/`getRandomValues`/`randomUUID`, `AbortController`, `EventTarget`/`CustomEvent`, `Blob`/`File`/`FormData`/`Headers`/`Request`/`Response`, `URL`/`URLPattern`/`URLSearchParams`, `MessageChannel`/`BroadcastChannel`, `ReadableStream`/`WritableStream`/`TransformStream` (+ `Default`/`BYOB`/`Byte` controllers), `CompressionStream`/`DecompressionStream`, `TextEncoderStream`/`TextDecoderStream`, `EventSource`, `MessageEvent`/`ErrorEvent`/`CloseEvent`/`PromiseRejectionEvent`, `localStorage`/`sessionStorage`, `caches`/`Cache`/`CacheStorage`, `FileReader`/`FileReaderSync`, `DOMRect`/`DOMPoint`/`DOMMatrix`/`DOMQuad` (+ `ReadOnly` variants), `ImageData`/`ImageBitmap`, `PerformanceObserver`, `IntersectionObserver`/`MutationObserver`/`ResizeObserver`, `WebTransport`/`RTCPeerConnection`, `indexedDB`, `Notification`, `cookieStore`.

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
| QuickJS-NG | 144/144 | Default. Interpreter, ES2025, smallest binary (9.8MB) |
| JavaScriptCore | 140/140 (1 SKIP) | JIT. Same engine as Safari/Bun. Skips `bun_v7_additions` pending io_uring fd-accumulation investigation |
| V8 | 144/144 | JIT. Same engine as Chrome/Node.js (V8 15.0). Via C++ shim |

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
dub test -c unittest                            # unit tests
bash tests/integration/run.sh                   # QuickJS integration (141 tests)
BACKEND=jsc DUN=./dun-jsc bash tests/integration/run.sh
BACKEND=v8  DUN=./dun-v8  bash tests/integration/run.sh
```

144/144 integration on QJS / V8, 143/143 + 1 SKIP on JSC, plus 145 npm-compat checks,
98/98 ECMAScript spec audit (all 3 backends — /v set-op gap on
QJS / V8 closed via source rewriter), 81/81 react-compat,
231/231 safe-features, 45/45 security audit, 35/35 TypeScript
erasable subset, **12/12 ts_parity vs `tsc`**, **12/12
deno_deploy_compat vs Deno 2.7**, **13/13 bun_bundler_compat
vs Bun 1.3**, **38/38 v0.6.0 web API audit**, **25/26 Bun.*
audit** (the 1 miss is `Bun.MD4`, not a real upstream API),
and cross-runtime grids for real-world apps (n8n, gaia, opencode).

See [TESTING.md](TESTING.md) for the full suite breakdown.

## Comparison

| | Node.js 22 | Deno 2.7 | Bun 1.3 | DunJS |
|--|------------|----------|---------|-------|
| Language | C++ | Rust | Zig | D |
| Engine | V8 | V8 | JSC | Pluggable: **QuickJS-NG / JSC / V8** |
| TypeScript | `--experimental-strip-types` (erasable subset) | Built-in | Built-in | Type stripping + persistent cache + `--typecheck` |
| Permissions | None | Default-deny | None | Default-deny |
| npm | Native | `npm:` specifier | Native | `dun install` |
| TLS | OpenSSL | rustls | BoringSSL | OpenSSL |
| Deno compat | No | -- | None | 30+ `Deno.*` APIs |
| ES2025 spec | 98/98 | 98/98 | 98/98 | **98/98 / 98/98 / 98/98** |
| TS strip parity | FAIL (rejects param-prop / enum / namespace) | 35/35 | 35/35 | **35/35 / 35/35 / 35/35** |
| Cold start | 27 ms | 42 ms | 11 ms | **27 ms / 27 ms / 22 ms** |
| Binary | 119 MB | 119 MB | 89 MB | **9.8 MB / 60 MB / 56 MB** |

DunJS triple values are always ordered **QJS / JSC / V8**. Cold
start: `time runtime -e ';'`, best of 15 on this host. Binary size:
stripped release executables — DunJS QJS statically links QuickJS-NG
(the small interpreter); DunJS JSC and DunJS V8 embed the full
WebKit / V8 engine libraries.

### Performance

Feature benchmarks (25 tests, ops/sec — higher is better, median of 3 runs):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.14 | 491M | 1.00x |
| DunJS JSC | **488M** | **0.99x** |
| Node.js 22.22.2 | 172M | 0.35x |
| Deno 2.7.14 | 169M | 0.34x |
| DunJS V8 | 160M | 0.33x |
| DunJS QuickJS | 22M | 0.05x (interpreter-only) |

Framework benchmarks (39 tests, ops/sec — median of 3 runs):

| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.14 | 339M | 1.00x |
| DunJS JSC | 277M | 0.82x |
| Node.js 22.22.2 | 180M | 0.53x |
| DunJS V8 | 172M | 0.51x |
| Deno 2.7.14 | 154M | 0.45x |
| DunJS QuickJS | 17M | 0.05x |

HTTP stress (wrk, 128 connections, req/sec — higher is better):

| Endpoint | Bun | Deno | DunJS V8 | DunJS QJS | Node.js |
|----------|-----|------|----------|-----------|---------|
| /plaintext | 55,487 | 52,086 | 37,298 | 48,084 | 28,238 |
| /json | 53,093 | 49,783 | 38,924 | **55,888** | 29,398 |
| /compute | 55,132 | 42,544 | 39,778 | 40,334 | 27,372 |
| /transaction | 42,694 | 41,792 | 34,138 | 26,501 | 19,046 |

DunJS JSC is within 1% of Bun on `feature_bench.js` JS compute.
DunJS V8 beats Node.js on all HTTP endpoints.
npm compat: **145/145** pass across all 6 runtimes.

## Can DunJS replace Node / Deno / Bun?

Partially. Honest assessment:

**Where it works today** (CLI tools, build scripts, microservices,
test harnesses, learning projects):

- 144/144 integration sweep on QJS / V8 (143/143 + 1 SKIP on JSC); 145/145 npm-compat,
  98/98 ES2025 spec, 12/12 `deno_deploy_compat` vs Deno 2.7,
  13/13 `bun_bundler_compat` vs Bun 1.3, 38/38 v0.6.0 web API
  audit.
- Real Node.js module surface: `fs`, `path`, `crypto`, `net`,
  `http`/`http2`/`http3`, `dgram`, `tls`, `stream`, `zlib`,
  `events`, `child_process`, `dns`, `ws`, `sqlite`, `perf_hooks`,
  `worker_threads`, `wasi`, `vm` — all 30+ modules.
- Real Deno surface (22/23 audit): `Deno.serve`, `Deno.Command`,
  `Deno.dlopen`, env/fs/permissions APIs.
- Real Bun surface (25/26 audit): `Bun.serve`/`build`/`file`/
  `write`/`password`/`hash`/`semver`/`glob`/`color`/`udp`/etc.
- Real native addons via N-API (91 functions, sharp + similar
  work).
- HTTP perf: DunJS V8 beats Node by 41% on `/plaintext`; JSC
  backend beats Bun on `stress.js` (62s vs 66s, 240/240).
- **Dev experience (v0.7.0)**: `dun lint` (lexer-based JS/TS
  linter, 6 core rules), `dun test --concurrent`
  (`Promise.all`-batched parallel tests + `--max-concurrency=N`
  + `test.concurrent()` / `test.serial()` — Bun parity), `dun
  bundle --sourcemap[=inline|external]` (Source Map V3 emit).

**Where it can't yet**:

- **Maturity.** v0.6.0, no production deployments tracked, no
  CVE history. Bun and Deno took years to harden under real
  traffic; DunJS hasn't been hammered at scale yet.
- **Stub-only web APIs.** `IndexedDB`, `WebTransport`,
  `RTCPeerConnection`, `Notification`, `CookieStore`,
  `FileReaderSync`, `ImageBitmap` satisfy `typeof === 'function'`
  probes but throw on actual use. Good enough for libraries
  that feature-detect; not good enough to run a real workload
  that depends on them.
- **No `bun build --compile` / `deno compile` standalone
  executable** — bundling works (`dun bundle`, Source Map V3
  via `--sourcemap`), but embedding the runtime + bundle in a
  single binary is a multi-PR project. The minimal linter
  shipped in v0.7.0 covers the dev-experience floor (6 rules);
  full ESLint parity (200+ rules) needs a real parser, which
  the project rejects (see Won't-fix in CLAUDE.md).
- **Native `.node` addons that bypass N-API** (call V8 / libuv
  internals directly) won't work — same constraint Bun and Deno
  have.
- **Inspector / Chrome DevTools wire protocol** isn't wired up
  across all backends.

**Practical rule**: drop-in for a CLI / build script / small
service / test harness. For a 50-engineer production service
shipping to millions tomorrow, run alongside Node first.

## Docs

- [ARCHITECTURE.md](ARCHITECTURE.md) — 7-layer design, engine
  abstraction, FFI strategies, RAII patterns
- [CLAUDE.md](CLAUDE.md) — development guide (build commands,
  code style, key patterns, GC tuning, won't-fix design
  constraints)
- [TESTING.md](TESTING.md) — full test inventory + how to run
- [CHANGELOG.md](CHANGELOG.md) — phased delivery history

## License

[MIT](LICENSE)
