# Node.js Compatibility

DunJS targets drop-in compatibility for the Node.js APIs that real
applications use. Below is a status table — what works, what's a
stub, what's a hard won't-fix.

## Compatibility summary

- **30+ built-in modules**: `fs`, `fs/promises`, `path`, `crypto`,
  `net`, `http`, `https`, `http2`, `dgram`, `tls`, `stream`, `zlib`,
  `events`, `child_process`, `dns`, `ws`, `sqlite`, `url`, `querystring`,
  `string_decoder`, `util`, `assert`, `os`, `vm`, `cluster`,
  `async_hooks`, `worker_threads`, `timers`, `timers/promises`,
  `perf_hooks`, `tty`, `wasi`, `buffer`, `console`, `process`,
  `readline`
- **N-API 140 functions** — sharp + similar real native addons work
- **`node:buffer.{isUtf8, isAscii, kStringMaxLength}`** (Node v19.5+)
  for jest@30 / pino bench probes
- **`util.{MIMEParams, getSystemErrorMap, getSystemErrorMessage,
  formatWithOptions}`** (Node v10/v16/v22+)
- **`assert.partialDeepStrictEqual`** (Node v22+)
- **`npm install`** with CVE audit (OSV API)
- **145/145 npm_compat** checks pass on all 5 runtimes (Node, Deno, Bun,
  DunJS QJS, DunJS V8/JSC)
- **`process.*`** — argv, env, cwd, chdir, exit, platform, arch, version,
  versions, pid, ppid, stdin/stdout/stderr, emit, on, nextTick,
  memoryUsage, hrtime, uptime
- **Streams, pipelines, async iterators**
- **EventEmitter** including `errorMonitor`, `captureRejections`,
  `getMaxListeners`, `setMaxListeners`
- **`Buffer`** — full API, SIMD hex encode, all encodings
  (utf8/utf16le/latin1/binary/base64/base64url/hex/ascii)

## What works (by module)

### Fully implemented

```js
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const http = require("http");
const net = require("net");
const url = require("url");
const querystring = require("querystring");
const buffer = require("buffer");
const events = require("events");
const os = require("os");
const util = require("util");
const assert = require("assert");
const stream = require("stream");
const zlib = require("zlib");
const dns = require("dns");
const child_process = require("child_process");
const string_decoder = require("string_decoder");
const readline = require("readline");
const perf_hooks = require("perf_hooks");
```

### Implemented with caveats

| Module | Status |
|--------|--------|
| `http2` | Server + client; SETTINGS, GOAWAY, PING; CONTINUATION partial |
| `http3` (DunJS-specific) | QUIC via lsquic; HTTP/3 server + client |
| `https` | Full via OpenSSL |
| `tls` | `connect`, `createServer`, `TLSSocket`, `getCiphers`, constants |
| `dgram` | `createSocket`, `bind`, `send`, `close` (UDPv4 + v6) |
| `ws` | Real WebSocket per RFC 6455 |
| `sqlite` | Full via ImportC from sqlite3.h — `open`, `exec`, `run`, `get`, `all`, `close` |
| `worker_threads` | Real OS threads with own engine, SharedArrayBuffer + Atomics |
| `cluster` | Round-robin + worker pool |
| `vm` | `runInThisContext`, `runInNewContext`, `Script.runInContext` |
| `wasi` | Preview1 — `args_get`, `clock_*`, `fd_*`, `path_*`, `random_get` |
| `async_hooks` | `createHook`, `executionAsyncId`, `triggerAsyncId`, `AsyncLocalStorage` |
| `diagnostics_channel` | Real publish/subscribe (lazy on JSC) |
| `tty` | `isatty`, `WriteStream`, `ReadStream` |

### Stubs (return empty values, no exceptions)

| Module | Why |
|--------|-----|
| `punycode` | Deprecated upstream; basic encode/decode shim |
| `domain` | Deprecated upstream; empty `.create()`, `.run()` |
| `inspector` | Debug protocol not implemented (use `--inspect` on V8) |

## Web APIs (in addition to Node)

DunJS also provides the WHATWG / WICG surface Node ships:

- **fetch**, `Request`, `Response`, `Headers`, `Blob`, `File`,
  `FormData`, `URL`, `URLSearchParams`
- **TextEncoder / TextDecoder**, `atob`, `btoa`, `structuredClone`
- **AbortController / AbortSignal**, `EventTarget`, `Event`,
  `CustomEvent`, `DOMException`
- **performance** (`now`, `mark`, `measure`, `getEntries`),
  `PerformanceObserver`
- **MessageChannel / MessagePort / BroadcastChannel**
- **ReadableStream / WritableStream / TransformStream**,
  `CompressionStream`, `DecompressionStream`
- **crypto.getRandomValues**, **crypto.randomUUID**,
  **crypto.subtle** (digest, importKey, sign/verify HMAC, encrypt/decrypt
  AES-GCM/CBC, generateKey, deriveBits PBKDF2/HKDF)
- **localStorage / sessionStorage**, `caches` (CacheStorage),
  `FileReader`, `ImageData`, `DOMRect`, `Matrix`, `Quad`,
  `CryptoKey`, `MessageEvent`, `ErrorEvent`, `CloseEvent`,
  `PromiseRejectionEvent`

Plus lazy globals (loaded on first access via
`Object.defineProperty` getter): `IntersectionObserver`,
`MutationObserver`, `ResizeObserver`, `WebTransport`,
`RTCPeerConnection`, `indexedDB`, `Notification`, `CookieStore`,
`FileReaderSync`, `ImageBitmap` / `createImageBitmap`.

## process

```js
process.argv       // ["dun", "/path/to/script.js", ...userArgs]
process.argv0      // "dun"
process.execPath   // "/path/to/dun"
process.cwd()      // current working dir
process.chdir("/tmp")
process.env.NODE_ENV
process.exit(0)
process.platform   // "linux" | "darwin" | "win32"
process.arch       // "x64" | "arm64" | ...
process.version    // "v22.0.0" (set for Node parity)
process.versions   // { node: "22.0.0", v8: "15.0.112", dun: "1.1.29", ... }
process.pid
process.ppid
process.uptime()
process.memoryUsage()
process.hrtime() / process.hrtime.bigint()
process.nextTick(fn)
process.emit("uncaughtException", err)
process.on("exit", fn)
process.on("SIGINT", fn)
```

## Won't-fix

These are documented in [CLAUDE.md](../CLAUDE.md#wont-fix-design-constraints):

### Native `.node` addons that bypass N-API

Things that `dlopen('node')` and directly call V8 / libuv internals
can't be supported by any non-Node runtime. Addons that stay within
the N-API surface work — DunJS ships 140+ N-API functions plus real
`napi_wrap` / `napi_create_external` with a side-table for the
`(data, hint, finalize_cb)` triple. **Sharp + similar real addons
have been tested.**

### Internal V8 APIs

- `--inspect` works on the V8 backend only (uses V8's built-in
  inspector). QJS / JSC don't have a compatible protocol.
- `vm.compileFunction` with V8 cache hints — supported but caching
  is limited to V8.

### Process model differences

- **`process.dlopen`** — works (via FFI) but requires `--allow-ffi`
- **`process.binding`** — internal Node API, not stable; not
  implemented
- **`process.report`** — heap dump format Node-specific; not
  implemented

## Drop-in testing

The fastest way to know if your Node code works on DunJS:

```sh
dun run -A your-existing-app.js
```

If it crashes, file an issue with the stack trace. The integration
test suite includes cross-runtime grids for n8n, gaia, opencode —
real Node.js apps that work on DunJS today.

## Quirks worth knowing

1. **Worker thread startup is ~3× faster** than Node — useful for
   short-lived worker fanout
2. **`Buffer.alloc(n).fill(byte).toString('hex')`** uses SIMD — 16
   bytes/cycle on LDC builds
3. **`fs.readFile(path)`** is synchronous under the hood (small
   files), async I/O is via worker pool — Node uses libuv threadpool
4. **`http.createServer` peak rps** is ~17k-37k depending on
   backend, vs Bun's 80k+. The CPU benches outperform Bun; the
   HTTP server doesn't yet (see [performance.md](./performance.md)).
5. **`require('fs').promises`** and `require('fs/promises')` both
   work — same object
6. **`os.networkInterfaces()`** requires `--allow-sys` (Deno parity)

## See also

- [Deno compat](./deno-compat.md) — `Deno.*` APIs
- [Bun compat](./bun-compat.md) — `Bun.*` APIs
- [Built-ins index](./builtins/index.md) — full WHATWG surface
  (`fetch`, `URL`, Web Streams, `crypto.subtle`, etc.) and Node-style
  modules
- [tests/benchmarks/npm_compat_test.js](../tests/benchmarks/npm_compat_test.js)
  — 145-check parity suite
