# Built-in Modules

DunJS ships 30+ built-in modules. All work identically on every
backend (QuickJS-NG / JavaScriptCore / V8).

## Importing

```js
// CommonJS
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

// ES modules
import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";

// `dun:` prefix (DunJS-native shortcut, same modules)
import sqlite from "dun:sqlite";
import wasi from "dun:wasi";
```

Both `node:fs` and just `fs` work — they resolve to the same module.

## Module index

### Filesystem

- **`fs`** — synchronous + async file ops (`readFile`, `writeFile`,
  `stat`, `mkdir`, `unlink`, `rename`, `copyFile`, `readdir`, ...)
- **`fs/promises`** — promise-based variants
- **`path`** — `join`, `resolve`, `dirname`, `basename`, `extname`,
  `posix`, `win32` namespaces

### Network

- **`net`** — TCP sockets (`createServer`, `connect`, `Socket`)
- **`http`** — HTTP/1.1 server + client
- **`https`** — HTTP/1.1 over TLS (OpenSSL)
- **`http2`** — HTTP/2 binary framing, HPACK, multiplexing
- **`http3`** (DunJS-specific) — HTTP/3 via QUIC (lsquic)
- **`tls`** — TLS sockets, cipher selection, custom CA
- **`dgram`** — UDP sockets (v4 + v6)
- **`dns`** — `lookup`, `resolve4`, `resolve6`, `reverse`
- **`ws`** — WebSocket per RFC 6455
- **`fetch`** (global) — WHATWG fetch

### Crypto

- **`crypto`** — Node's full surface: `createHash`, `createHmac`,
  `createCipheriv`, `createDecipheriv`, `randomBytes`, `randomUUID`,
  `generateKeyPair`, `sign`/`verify`, DH, ECDH
- **`crypto.subtle`** (Web Crypto) — `digest`, `importKey`,
  `sign`/`verify` (HMAC), `encrypt`/`decrypt` (AES-GCM/CBC),
  `generateKey`, `exportKey`, `deriveBits` (PBKDF2, HKDF)

### Data + utilities

- **`buffer`** — full `Buffer` API, all encodings, SIMD hex encode
- **`events`** — `EventEmitter` with `errorMonitor`,
  `captureRejections`, `getMaxListeners`
- **`url`** — `URL`, `URLSearchParams`
- **`querystring`** — Node's legacy QS module
- **`string_decoder`** — `StringDecoder`
- **`util`** — `inspect`, `format`, `promisify`, `callbackify`,
  `types`, `deprecate`
- **`assert`** — `assert.*` with proper `AssertionError` shape

### Streams + compression

- **`stream`** — `Readable`, `Writable`, `Duplex`, `Transform`,
  `PassThrough`, `pipeline`
- **`zlib`** — `deflate`/`inflate`/`gzip`/`gunzip`/`brotli` sync +
  streaming
- **`readline`** — line-by-line stdin reader

### Process

- **`child_process`** — `exec`, `execSync`, `spawn`, `spawnSync`,
  `fork`
- **`cluster`** — Round-robin worker pool
- **`worker_threads`** — Real OS threads with engine isolation +
  SharedArrayBuffer + Atomics
- **`os`** — `platform`, `arch`, `cpus`, `totalmem`, `freemem`,
  `networkInterfaces`, `userInfo`, `hostname`, `loadavg`

### Runtime

- **`vm`** — `runInThisContext`, `Script`, `compileFunction`
- **`perf_hooks`** — `performance`, `PerformanceObserver`,
  `monitorEventLoopDelay`, `timerify`
- **`async_hooks`** — `createHook`, `executionAsyncId`,
  `AsyncLocalStorage`, `AsyncResource`
- **`timers`** / **`timers/promises`** — setTimeout, setInterval,
  setImmediate (+ promise variants)
- **`diagnostics_channel`** — Real publish/subscribe
- **`tty`** — `isatty`, `ReadStream`, `WriteStream`
- **`wasi`** — WASI preview1

### DunJS-specific

- **`dun:sqlite`** — `sqlite3` bindings via ImportC

## Stubs (no-op but don't throw)

- **`punycode`** — deprecated in Node; basic shim
- **`domain`** — deprecated in Node; empty methods
- **`inspector`** — debug protocol stubs
- **`constants`** — re-exports module-specific constants

## Deno + Bun globals

- **`Deno.*`** — 30+ APIs ([Deno compat](../deno-compat.md))
- **`Bun.*`** — 25+ APIs ([Bun compat](../bun-compat.md))

## Quick navigation

| If you want to… | Use |
|-----------------|-----|
| Read/write files | `fs` |
| HTTP server | `http`, `http2`, or `Deno.serve` / `Bun.serve` |
| Outbound HTTP | `fetch` (global), `http.request` |
| Hash / encrypt | `crypto` or `crypto.subtle` |
| Run a command | `child_process.exec` / `Deno.Command` |
| Spawn threads | `worker_threads` |
| Embedded DB | `dun:sqlite` |
| WebSocket | `ws` |
| Read env | `process.env` / `Deno.env` |

## See also

- [CLAUDE.md Runtime Globals](../../CLAUDE.md#runtime-globals-layer-6)
  — internal registration table
- [tests/benchmarks/npm_compat_test.js](../../tests/benchmarks/npm_compat_test.js)
  — 145 cross-runtime checks
