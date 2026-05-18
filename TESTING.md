# DunJS Testing Guide

How to run, what's covered, and how the benchmarks are structured.
See [CLAUDE.md](CLAUDE.md) for top-level build commands.


### Unit Tests

```sh
dub test -c unittest    # All unit tests
```

| Suite | File | Tests | Coverage |
|-------|------|-------|----------|
| Engine contract | `source/dun/engine/test.d` | ~50 | eval, types, properties, exceptions, promises |
| Fuzz/stress | `source/dun/engine/fuzz.d` | ~71 | rapid create/destroy, string stress, exception recovery, ES2023+, typed arrays, JSON, classes, closures, regex, proxy, symbols, destructuring |
| TypeScript strip | `source/dun/ts/strip.d` | 20 | annotations, interfaces, as, declare, arrow types |
| Security perms | `source/dun/security/test.d` | 27 | default deny, scoped grants, deny overrides, parseFlag |
| CVE audit | `source/dun/security/cve_db.d` | 8 | semver, CVSS parsing, severity mapping, JSON escaping, cache round-trip |
| SQLite | `source/dun/builtins/sqlite.d` | 4 | ImportC bindings, open/close, exec/query, bind parameters |
| HTTP/2 | `source/dun/builtins/http2.d` | 15 | frame encoding, HPACK encode/decode, static table, settings |
| HTTP/3 | `source/dun/builtins/http3.d` | 12 | QUIC varint encode/decode, H3 frame header, SETTINGS payload |
| V8 TMP bridge | `source/dun/engine/v8/cppbindings.d` | compile-time | V8TypeName coverage, tag->name mapping |
| JSC TMP bridge | `source/dun/engine/jsc/cppbindings.d` | compile-time | JSCTypeName coverage, kJSType* alignment |

### Integration Tests (137 tests, 145 npm-compat checks)

```sh
# Run against a specific backend
dub build -c quickjs && ./tests/integration/run.sh
dub build -c jsc && BACKEND=jsc ./tests/integration/run.sh
dub build -c v8  && BACKEND=v8  ./tests/integration/run.sh
```

| Category | Tests | Coverage |
|----------|-------|----------|
| Core JS | `hello`, `types`, `console_methods`, `console_inspect` | Basic output, typeof, multi-arg logging, Node-style object inspect |
| Async | `promises`, `promises_advanced`, `timers`, `phase2`, `phase2_rejection`, `async_io` | Promise.all/race/any, async/await, setTimeout, unhandledRejection |
| ES2023+ | `es2023`, `closures`, `iterators`, `classes`, `regex`, `json_parsing` | findLast, generators, Map/Set, private fields, matchAll |
| Errors | `error_handling` | try/catch, Error subtypes, Error.cause, finally |
| Modules | `module_esm`, `module_cjs`, `module_chain`, `json_pipeline`, `npm_compat` | ESM import/export, CJS require, chained deps, JSON import |
| Builtins | `fs_ops`, `path_ops`, `crypto_ops`, `stat_file`, `env_access` | readFile, join/resolve, hash/randomBytes, stat, process.env |
| Node APIs | `buffer_api`, `event_emitter`, `url_api`, `os_api`, `http2_api`, `http3_api` | Buffer.from/alloc/concat, EventEmitter on/emit/once, URL/URLSearchParams, os.platform/cpus/totalmem, HTTP/2 API (20 checks), HTTP/3 API (22 checks) |
| New Modules | `child_process_api`, `stream_api`, `zlib_api`, `dns_api`, `ws_api` | execSync/spawnSync, Readable/Writable/Transform/pipeline, deflate/gzip round-trip, DNS lookup/resolve, WebSocket API |
| Database | `sqlite_api` | open, exec, run, get, all, close, NULL handling, types (20 checks) |
| Web APIs | `web_apis` | 101 checks: performance, EventTarget/Event, AbortController, Blob, FormData, Headers, Request/Response, MessageChannel, BroadcastChannel, ReadableStream, WritableStream, TransformStream, CompressionStream, DecompressionStream, crypto.getRandomValues, navigator, Promise.withResolvers, require.resolve |
| Deno compat | `deno_compat` | 22 checks: env, fs, stat, copy, rename, remove, web globals |
| Security | `perm_deny_read`, `perm_deny_write`, `realworld_security_boundary` | Permission denial enforcement |
| TypeScript | `typescript`, `realworld_ts_library` | Type annotations, interfaces, as, arrow types |
| Fetch/Response | `fetch_response` | 19 checks: Response constructor, status/statusText/ok/url, headers, text/json/clone, process.stdin |
| import.meta | `import_meta` | 6 checks: url, filename, dirname, main (all 3 backends) |
| New Modules | `vm_api`, `async_hooks_api`, `signal_handling` | vm.runInThisContext/runInNewContext/createContext/Script, AsyncLocalStorage run/getStore/enterWith/disable, process.on('SIGTERM'/'SIGINT') |
| fs errors | `fs_errors` | Node-compatible Error objects (code/errno/syscall/path), ENOENT, permission errors |
| fs promises | `fs_promises` | 20 checks: readFile, writeFile, appendFile, copyFile, rename, unlink, mkdir, readdir, stat, access, realpath |
| HTTPS | `https_api` | https.createServer, options validation, cert/key loading, request/get/Agent |
| HTTP client | `http_client_api` | 42 checks: STATUS_CODES, METHODS, Agent, request/get, ClientRequest API |
| Crypto async | `crypto_async` | 12 checks: async pbkdf2/scrypt, randomFill, createSign/createVerify, constants |
| Real-world | 7 end-to-end scenarios | Config loading, task runner, file processing, events, promise pool, nested require, ESM pipeline |
| Process | `process_enhanced` | 18 checks: nextTick args, emitWarning, kill, umask, hrtime, memoryUsage, cpuUsage |
| Crypto | `crypto_cipher` | 12 checks: AES-256-CBC/AES-128-CBC round-trip, getCiphers, getHashes, timingSafeEqual, HMAC |
| Util | `util_enhanced` | 27 checks: types (20+), debuglog, _extend, format, inherits, promisify, callbackify |
| Readline | `readline_api` | 18 checks: createInterface, events, write/line, punycode, domain, diagnostics_channel |
| Env Proxy | `process_env_proxy` | 8 checks: set/delete/in/keys, NODE_ENV pattern |
| Env Native | `process_env_native` | 11 checks: setenv/unsetenv, child process inheritance, numeric coercion |
| npm compat | `npm_compat_modules` | 452 checks: 35 modules, key API surface, globals, crypto (25+ APIs), stream, events, util, http/https, tls/dns/dgram, os, perf_hooks, ES2023+, Symbol well-known |
| UDP/dgram | `dgram_api` | 25 checks: createSocket, bind, address, setBroadcast, setTTL, on/close, Socket alias |
| spawn/execFile | `spawn_api` | 19 checks: spawn pid/stdout/stderr/stdin/on/kill, execFile with callback |
| TLS module | `tls_api` | 24 checks: connect, getCiphers, TLSSocket constructor/methods, constants |
| DNS enhanced | `dns_enhanced` | 18 checks: resolve, getServers, dns.promises, lookupSync, resolve with rrtype |

| Crypto | `crypto_sign` | 19 checks: createSign/createVerify with OpenSSL, RSA/ECDSA, hex/base64 encoding |
| Zlib | `zlib_enhanced` | 33 checks: async deflate/inflate/gzip/gunzip, createDeflate/createGzip streams, constants |

| Express compat | `express_compat` | 102 checks: EventEmitter, streams, Buffer, URL, path, crypto, querystring, http, assert, os, util |
| Bundler compat | `bundler_compat` | 91 checks: fs ops, path resolution, crypto hashing, Map/Set, RegExp, string ops, Promise, modules |
| Crypto keygen | `crypto_keygen` | 12 checks: generateKeyPairSync RSA/EC, PEM output, sign+verify round-trip, DiffieHellman |
| WebCrypto | `webcrypto_api` | 55 checks: subtle.digest (SHA-1/256/384/512), importKey, sign/verify (HMAC), encrypt/decrypt (AES-GCM/CBC), generateKey (AES/HMAC), exportKey, deriveBits (PBKDF2/HKDF) |
| .env loading | `dotenv_loading` | 3 checks: parse KEY=VALUE/quoted, no-override existing env, missing .env OK |
| Production gaps 3 | `production_gaps3` | 15 checks: console.group, TypedArray.from/of, zlib Buffer, sqlite bind |
| Production gaps 4 | `production_gaps4` | 144 checks: process, Buffer, stream, EventEmitter, path, crypto, fs, Error, util, npm patterns |
| Production readiness | `production_readiness` | 122 checks: all critical Node.js APIs for production server workloads |

Backend test scores: **QuickJS 137/137**, **JSC 137/137**, **V8 137/137** — **0 failures** across all 3 backends.

Test pattern: fixtures in `tests/integration/fixtures/*.{js,mjs,ts}`, expected stdout in `tests/integration/expected/*.txt`.

### Sanitizer Testing

```sh
dub build -c quickjs -b asan                          # ASan build via DUB
ASAN_OPTIONS=detect_leaks=0 bash tests/integration/run.sh  # Run with ASan
```

All 137 integration tests pass under AddressSanitizer with zero memory errors.

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
| **DunJS JSC** | **658M** | **1.15x** ⭐ |
| Bun 1.3.14 | 570M | 1.00x |
| Node.js v22 | 199M | 0.35x |
| DunJS V8 | 180M | 0.32x |
| DunJS QuickJS | 26M | 0.05x (interpreter-only) |

After the Buffer-as-Uint8Array refactor (factory call + Proxy wrapper
removed in favor of `Object.setPrototypeOf` on a real `new Uint8Array`),
DunJS JSC overtook Bun on `feature_bench.js` total throughput. The same
refactor unblocked the Buffer.concat segfault that was killing JSC under
hot iteration in earlier sessions (heap stays under 90M instead of
growing to 187M+ before crash).

Framework benchmarks (framework_bench.js, 39 tests, release builds, ops/sec):

| Runtime | Total Throughput | vs Bun |
|---------|-----------------|--------|
| **DunJS JSC** | **289M** | **1.03x** ⭐ |
| Bun 1.3.14 | 280M | 1.00x |
| Node.js v22 | 194M | 0.69x |
| DunJS V8 | 189M | 0.68x |
| DunJS QuickJS | 20M | 0.07x |

npm compat test (npm_compat_test.js, 145 assertions): **All 6 runtimes: 145/145 pass**

HTTP benchmarks (wrk, 2 threads, 128 connections, 5s per endpoint, release builds):

| Endpoint | Node v22 | Deno 2.7 | DunJS JSC | DunJS V8 | Bun 1.3 |
|----------|----------|----------|-----------|----------|---------|
| /plaintext | 44,704 | 58,882 | 46,634 | **62,907** | **80,322** |
| /json | 47,976 | 59,627 | 48,038 | **59,600** | **76,653** |

DunJS V8 HTTP: beats Node by 41% on /plaintext, competitive with Deno.
All endpoints include TCP_NODELAY, buffered single-write response, CTFE status lines.

Stress test (stress.js, 240 tests, release builds):

| Runtime | Wall Time | Status |
|---------|-----------|--------|
| **DunJS JSC** | **62s** | **240/240** ⭐ (faster than Bun) |
| Bun 1.3.14 | 66s | 240/240 |
| Node.js v22 | 133s | 240/240 |
| DunJS V8 | 133s | 240/240 |
| Deno 2.7.14 | 182s | 240/240 |

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
DunJS uses `core.simd` + LDC-exclusive intrinsics in hot paths (`dun.platform.simd`):
- **`hexEncodeBuf`**: SIMD hex encoding (16 bytes → 32 hex chars/cycle) + LDC `shufflevector` for zero-copy interleave
- **`asciiToLowerBuf`**: SIMD ASCII toLower (16 bytes/cycle) with `ldc.simd.loadUnaligned`/`storeUnaligned`
- **`findByte`**: SIMD byte search (16 bytes/cycle) + LDC `llvm_cttz` for O(1) first-match extraction
- **`bswap16`/`bswap32`/`bswap64`**: LDC `llvm_bswap` for Buffer BE read/write (single instruction vs 4 shifts+ORs)
- **`prefetchRead`**: LDC `llvm_prefetch` for data cache warming
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

### Cross-Runtime Compliance Suites

DunJS ships parity tests that probe major-runtime surfaces and compare output
against the gold reference (tsc / Deno / Bun) byte-for-byte. Run via:

```sh
bash tests/benchmarks/ts_parity/run.sh             # TS strip vs tsc + node
bash tests/benchmarks/spec_compliance/compare.sh   # ES + TS spec grid
./dun run tests/benchmarks/deno_deploy_compat.js   # Deno.serve / Deno Deploy
./dun run tests/benchmarks/bun_bundler_compat.js   # Bun.build
```

| Suite | Probes | DunJS (×3 backends) | Gold |
|-------|--------|---------------------|------|
| `spec_compliance/ecmascript.js` (98 checks) | ES2015..ES2025 — TDZ, arrow, destructuring, classes, Symbol, Map/Set, Promise, async/await, optional chaining, BigInt, top-level await, weak refs, Array.findLast, Object.groupBy, `RegExp /v` set ops | **98/98** | Bun / Node / Deno 98/98 |
| `spec_compliance/typescript.ts` (35 checks) | erasable + permissive TS strip (param-prop, enum, namespace) | **35/35** | Bun / Deno 35/35; Node FAIL (erasable subset rejects param-prop / enum / namespace) |
| `ts_parity` (12 fixtures) | class fields, enums, namespaces, decorators, JSX, `using`, generics, regex in TS, template literal types, type-only imports | **12/12** | `tsc + node` 12/12 |
| `deno_deploy_compat` (12 checks) | `Deno.serve` signature, `onListen`, ephemeral port, Response with string/Uint8Array/ReadableStream body, `shutdown()`, `finished`, request + response header round-trip, method/URL routing | **12/12** | Deno 2.7 12/12 |
| `bun_bundler_compat` (13 checks) | `Bun.build` relative-import inlining, bare-spec external, `define` constants, `minify`, `naming.entry`, `target=node/browser`, `outputs[i].arrayBuffer()`, unresolved-import signalling | **13/13** | Bun 1.3 13/13 |

DunJS matches Bun more thoroughly than Bun matches itself on the bundler suite
(both score 13/13). Node `--experimental-strip-types` scores 3/12 on `ts_parity`
because its erasable-only mode rejects enums, decorators, namespaces, `using`,
and generic arrow functions.

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

