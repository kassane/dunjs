# DunJS Changelog

Historical record of phased deliveries. Newest at the bottom.
See [BLOCKERS.md](BLOCKERS.md) for the current open / closed gap status.

## Phased Roadmap

| Phase | Goal | Key Deliverable | Status |
|-------|------|-----------------|--------|
| 1 (MVP) | `dun run hello.js` | Engine abstraction + console + CLI | **Done** |
| 1b | Multi-engine | JSC + V8 backends fully functional | **Done** |
| 1c | TypeScript | `dun run file.ts` with type stripping | **Done** |
| 1d | Security tests | PermissionRegistry unit tests (27 tests) | **Done** |
| 1e | TMP bridge | C++ TMP <-> D TMP wired for V8 + JSC | **Done** |
| 2 | Async works | Event loop + timers + Promises | **Done** |
| 2f | Phase 2 close | queueMicrotask + process.nextTick + unhandledRejection | **Done** |
| 3 | Real scripts | Module system + fs/path/net/crypto | **Done** |
| 4 | Secure by default | Permission enforcement wired to builtins | **Done** |
| 5 | DX polish | REPL + colored errors + stack traces | **Done** |
| 6a | Networking | net.d TCP + npm compat (node_modules) + I/O polling | **Done** |
| 6b | HTTP server | http.d HTTP/1.1 createServer/listen/close, req/res, epoll | **Done** |
| 6c | Workers | Web Workers + SharedArrayBuffer + Atomics (all backends) | **Done** |
| 6d | io_uring | Linux io_uring backend for IOPoller (IORING_OP_POLL_ADD) | **Done** |
| 7a | Node APIs | Buffer, EventEmitter, URL/URLSearchParams, os module | **Done** |
| 7b | Engine parity | net/http ported engine-agnostic (JSC/V8 fully usable) | **Done** |
| 7c | Safety | `-preview=safer` enabled for all code | **Done** |
| 8a | TLS/HTTPS | OpenSSL bindings + TlsSocket + fetch() with HTTPS | **Done** |
| 8b | npm install | `dun install <pkg>` with transitive deps from registry | **Done** |
| 8c | Deno compat | Deno.env, readTextFileSync, writeTextFileSync, cwd, exit, build | **Done** |
| 8d | Full Deno compat | 30+ Deno APIs (stat, mkdir, remove, rename, copy, readDir, permissions, errors) | **Done** |
| 8e | Web globals | atob, btoa, TextEncoder, TextDecoder, structuredClone | **Done** |
| 8f | Node process | process.argv, cwd(), exit(), platform, arch, version, pid | **Done** |
| 9a | HTTP/2 | http2.d RFC 9113 binary framing, HPACK, stream multiplexing, ALPN/TLS | **Done** |
| 9b | child_process | execSync, spawnSync, exec with permissions | **Done** |
| 9c | stream | Readable, Writable, Duplex, Transform, PassThrough, pipeline | **Done** |
| 9d | zlib | deflateSync, inflateSync, gzipSync, gunzipSync, raw deflate/inflate | **Done** |
| 9e | dns | lookup, lookupSync, resolve4, resolve6, reverse (POSIX getaddrinfo) | **Done** |
| 9f | WebSocket | RFC 6455 framing, client connect, server create, send/close (ws module) | **Done** |
| 9g | CVE audit | `dun audit` + `--audit=block/warn/off`, OSV API + local cache (24h TTL) | **Done** |
| 10a | SQLite | `dun:sqlite` built-in module, ImportC bindings from sqlite3.h, open/exec/run/get/all/close | **Done** |
| 10b | Test runner | `dun test` with Deno.test() API, file discovery, --filter, async tests | **Done** |
| 10c | Bench runner | `dun bench` with Deno.bench() API, auto-calibrating iterations, ops/sec reporting | **Done** |
| 10d | CLI tools | `dun init`, `dun fmt`, `dun clean` (project scaffold, formatter, cache cleanup) | **Done** |
| 10e | Perf: callback slots | Fix NativeCallback slot exhaustion (cache function handles, TIGER_STYLE assert) | **Done** |
| 10f | Perf: allocations | CTFE hex LUT (Buffer 59x faster), WS frame pre-alloc, ESM Appender | **Done** |
| 10g | GC tuning | collectGarbage() API, gc() global, rt_options minPoolSize:16, --DRT-gcopt docs | **Done** |
| 10h | Benchmarks | feature_bench.js (25 cross-runtime benchmarks), GC profiling integration | **Done** |
| 11a | Web APIs | performance, EventTarget/Event, AbortController/AbortSignal, DOMException | **Done** |
| 11b | Web APIs | Blob/File, FormData, Headers, Request/Response, navigator | **Done** |
| 11c | Web APIs | MessageChannel/MessagePort, BroadcastChannel, ReadableStream/WritableStream/TransformStream | **Done** |
| 11d | Web Crypto | crypto.getRandomValues(), crypto.randomUUID() as globals | **Done** |
| 11e | Console ext | console.time/timeEnd/timeLog/count/countReset/table/dir/trace | **Done** |
| 11f | Module compat | require.resolve(), require.cache, import.meta.url (QuickJS ESM) | **Done** |
| 11g | ES2024 | Promise.withResolvers(), setImmediate/clearImmediate | **Done** |
| 11h | Safety | `-preview=dip1000` enabled (scope safety for slices) | **Done** |
| 12a | fetch Response | fetch() returns proper Response objects (constructor, prototype, text/json/clone) | **Done** |
| 12b | process.stdin | process.stdin with non-blocking read, fd, isTTY, setEncoding | **Done** |
| 12c | import.meta all backends | import.meta.url/filename/dirname/main on QuickJS (native) + JSC/V8 (ESM shim polyfill) | **Done** |
| 12d | D FFI bindgen tests | 27 tests: -HCf, -H, ImportC, @nogc alloc, clang AST, FFI linkage, --extern-std | **Done** |
| 13a | HTTP/3 | dun:http3 module, RFC 9114 constants, QUIC varint encoding, lsquic bindings, API stubs | **Done** |
| 14a | vm module | dun:vm — runInThisContext, runInNewContext, createContext, Script class | **Done** |
| 14b | cluster module | dun:cluster — fork(), isPrimary/isWorker, worker tracking, exit callbacks | **Done** |
| 14c | async_hooks | dun:async_hooks — AsyncLocalStorage constructor, run/getStore/enterWith/disable | **Done** |
| 14d | worker_threads | dun:worker_threads — isMainThread, threadId, Worker (delegates to existing Worker API) | **Done** |
| 14e | Signal handling | POSIX SIGTERM/SIGINT handlers, process.on('SIGTERM'/'SIGINT', cb), event loop drain | **Done** |
| 14f | core.simd | SIMD hex encoding (16B/cycle), ASCII toLower (16B/cycle), byte search; SSE2/NEON | **Done** |
| 14g | LDC intrinsics | loadUnaligned/storeUnaligned, shufflevector interleave, llvm_bswap, llvm_cttz, llvm_prefetch | **Done** |
| 14h | V8 value pool | DunV8Value free-list allocator (256-entry pool), eliminates malloc/free per JS value | **Done** |
| 14i | Fuzz coverage | 21 new fuzz tests: ES2023+, typed arrays, JSON, classes, closures, regex, proxy, symbols, destructuring | **Done** |
| 15a | Node errors | Node-compatible Error objects with code/errno/syscall/path via IJSEngine.throwValue() | **Done** |
| 15b | fs/promises | Full fs.promises module (17 async operations) using asyncSubmitSafe nothrow pattern | **Done** |
| 15c | HTTPS server | https.createServer with OpenSSL TLS, cert/key loading, TLS-aware read/write/accept | **Done** |
| 15d | Stream finished | stream.finished() utility, util.callbackify, process.stdout/stderr stream compat | **Done** |
| 15e | Stub modules | tls, dgram, perf_hooks registered as JS stubs on globalThis for npm compat | **Done** |
| 15f | Process enhanced | process.nextTick args, emitWarning, kill, abort, umask, ppid, exitCode | **Done** |
| 15g | HTTP response | getHeader, getHeaders, hasHeader, removeHeader, headersSent | **Done** |
| 15h | util.types | 20+ type checkers (isAsyncFunction, isGeneratorFunction, isWeakMap, isDataView, etc.) | **Done** |
| 15i | Crypto ciphers | createCipheriv/createDecipheriv, AES-CBC/GCM with OpenSSL EVP API | **Done** |
| 15j | readline | readline module with createInterface, on/once/question/close, Symbol.asyncIterator | **Done** |
| 15k | process.env Proxy | Live Proxy with set/delete/in/ownKeys for runtime env manipulation | **Done** |
| 15l | Module stubs | punycode, domain, diagnostics_channel stubs for npm ecosystem | **Done** |
| 15m | net.isIP | net.isIP/isIPv4/isIPv6 with pure D validators | **Done** |
| 15n | stream.Readable | Readable.from(iterable), Readable[Symbol.asyncIterator] | **Done** |
| 15o | npm compat test | 97-check test covering 29 modules + key API surface (75/75 integration) | **Done** |
| 15p | HTTP client API | http.request/get, STATUS_CODES (50), METHODS (34), Agent, ClientRequest with fetch backend | **Done** |
| 15q | tty + pseudo-modules | tty.isatty/ReadStream/WriteStream, require('constants'/'module'/'timers'/'process'/'console') | **Done** |
| 15r | Async crypto | pbkdf2/scrypt async wrappers, randomFill/randomFillSync, createSign/createVerify stubs, constants | **Done** |
| 15s | Socket addresses | remoteAddress/remotePort/localAddress/localPort on net.Socket via accept()/getsockname() | **Done** |
| 15t | process.stdout | cork/uncork/cursorTo/clearLine/moveCursor/getWindowSize, process.argv0/execArgv/mainModule | **Done** |
| 15u | aarch64 + Docker | stat_t __traits(hasMember) for aarch64, Docker buildx multiplatform (amd64+arm64), non-root user | **Done** |
| 16a | child_process.spawn | spawn() with ChildProcess object (pid/stdout/stderr/stdin/on/kill), async event delivery | **Done** |
| 16b | child_process.execFile | execFile() direct process spawn without shell, callback and Promise modes | **Done** |
| 16c | dgram (UDP) | dgram.createSocket with bind/send/close/address/setBroadcast/setTTL, IPv4/IPv6, event callbacks | **Done** |
| 16d | TLS module | tls.connect with OpenSSL, TLSSocket class, getCiphers, event loop integration, SNI/hostname verify | **Done** |
| 16e | DNS enhanced | dns.resolve with rrtype, dns.getServers (/etc/resolv.conf), dns.promises (lookup/resolve4/resolve6) | **Done** |
| 16f | perf_hooks | performance.mark/measure/getEntries/clearMarks, PerformanceObserver, timerify, monitorEventLoopDelay, constants | **Done** |
| 16g | stream enhanced | Stream base class, addAbortSignal, promises.pipeline/finished, Readable.toWeb, Writable.toWeb | **Done** |
| 16h | fs.watchFile | fs.watchFile/unwatchFile (stat-polling), fs.watch enhanced (options, FSWatcher events) | **Done** |
| 16i | Async zlib | deflate/inflate/gzip/gunzip async, createDeflate/createGzip streams, zlib.constants (35), brotli stubs | **Done** |
| 16j | Crypto sign/verify | createSign/createVerify with OpenSSL EVP_DigestSign, RSA/ECDSA, hex/base64/buffer encoding | **Done** |
| 16k | os enhancements | os.networkInterfaces (getifaddrs), os.userInfo (getpwuid), os.loadavg, os.version, os.machine | **Done** |
| 16l | crypto.generateKeyPairSync | RSA/EC key pair generation with OpenSSL, PEM encoding, DiffieHellman stubs | **Done** |
| 16m | Compat tests | express_compat (102 checks), bundler_compat (91 checks) — npm ecosystem validation | **Done** |
| 17a | Crypto complete | createECDH, KeyObject, X509Certificate, webcrypto/subtle, generateKeySync, hkdfSync, hash, getCurves, FIPS stubs | **Done** |
| 17b | Stream complete | compose, isErrored, isReadable, isDisturbed, consumers (text/json/arrayBuffer), Readable.fromWeb | **Done** |
| 17c | Events complete | captureRejectionSymbol, captureRejections, errorMonitor, getEventListeners, addAbortListener | **Done** |
| 17d | Util complete | getSystemErrorName, parseArgs, styleText, MIMEType, aborted, transferableAbortController, getCallSites | **Done** |
| 17e | Process complete | debugPort, connected, report, resourceUsage (getrusage), binding, config, features, release, allowedNodeEnvironmentFlags | **Done** |
| 17f | HTTP/URL complete | maxHeaderSize, validateHeaderName/Value, Server.setTimeout, URL.canParse | **Done** |
| 17g | Module stubs | os.availableParallelism/setPriority/getPriority, net.BlockList/SocketAddress, path.matchesGlob | **Done** |
| 17h | Zlib complete | brotliCompressSync/DecompressSync, unzipSync, createBrotliCompress/Decompress | **Done** |
| 17i | Misc complete | readline.promises, assert.strict, fs/promises.cp/constants, Readable statics | **Done** |
| 17j | npm compat 452 | 452-check npm_compat_modules test covering all Node.js core APIs | **Done** |
| 18a | .env auto-loading | Bun-compatible .env parsing at startup (KEY=VALUE, quotes, no-override) | **Done** |
| 18b | --watch mode | `--watch` / `-w` flag: poll mtime, restart script on file changes | **Done** |
| 18c | CompressionStream | Web Compression API: CompressionStream/DecompressionStream (gzip/deflate/deflate-raw) | **Done** |
| 18d | WebCrypto subtle | Native crypto.subtle via OpenSSL: digest, importKey, sign/verify (HMAC), encrypt/decrypt (AES-GCM/CBC), generateKey, exportKey, deriveBits (PBKDF2/HKDF), deriveKey | **Done** |
| 18e | TIGER_STYLE audit | Precondition assertions in 45+ @trusted functions across all builtins and engine backends | **Done** |
| 18f | DIP1000 scope | `scope` annotations on 8 IJSEngine interface methods + all backend implementations | **Done** |
| 19a | ESM imports | Bare module imports (`fs`, `path`, `crypto`), `node:` prefix, `.mjs` files, JSON import attributes | **Done** |
| 19b | Error stacks | Full stack traces for uncaught exceptions, Error.captureStackTrace polyfill | **Done** |
| 19c | Binary crypto | D-side buffer registry for binary-safe Hash/HMAC, Buffer key support, multi-encoding digest | **Done** |
| 19d | Hash algorithms | sha3-256/384/512, ripemd160, blake2s256, blake2b512 via OpenSSL EVP | **Done** |
| 19e | Buffer encoding | base64url encode/decode, latin1/binary encoding with UTF-8 codepoint mapping | **Done** |
| 19f | createReadStream | Event emission (data/end/close), Buffer default, encoding option, chained .on() | **Done** |
| 19g | HTTP headers | Multi-value header support (Set-Cookie), array in setHeader/writeHead, per-value emission | **Done** |
| 19h | JSHandle safety | Fixed 38 dupValue/freeValue bugs across 9 builtin modules (use-after-free on QuickJS) | **Done** |
| 19i | timingSafeEqual | Buffer and Uint8Array input support via extractArgBytes helper | **Done** |
| 20a | Native setenv | process.env set/delete calls POSIX setenv/unsetenv, child processes inherit | **Done** |
| 20b | WebCrypto keygen | subtle.generateKey (AES/HMAC), exportKey (raw), deriveBits (PBKDF2/HKDF), deriveKey | **Done** |
| 20c | Expanded ciphers | 22 cipher algorithms: AES-CTR/ECB/OFB/CFB, AES-192-GCM, DES-EDE3, ChaCha20-Poly1305 | **Done** |
| 20d | stream.compose | Pipe-based stream composition (was throwing "not yet implemented") | **Done** |
| 20e | GC safety fix | Fix double-free in process.env (QuickJS setProperty consumes refcount) | **Done** |
| 20f | console.log inspect | Node-style object formatting: `{ key: value }`, Map/Set/TypedArray, circular detection, depth limit | **Done** |
| 20g | Format strings | console.log `%s`/`%d`/`%i`/`%f`/`%o`/`%O`/`%j`/`%%` substitution | **Done** |
| 20h | Buffer extended | swap16/32/64, lastIndexOf, readIntBE/LE, readUIntBE/LE, writeIntBE/LE, writeUIntBE/LE | **Done** |
| 20i | fs.createWriteStream | Deferred finish/close events to nextTick (matches Node.js event ordering) | **Done** |
| 20j | Inspect unification | Deno.inspect, console.dir, util.inspect, REPL all delegate to __dun_inspect__ | **Done** |
| 21a | CLI arg validation | Reject unexpected positional args after eval/version/help/audit/clean/repl | **Done** |
| 21b | zlib/sqlite fixes | zlib returns Buffer, sqlite bind arrays, console.group indentation, TypedArray.from/of | **Done** |
| 21c | Buffer improvements | BigInt read/write, WebSocket global, http.Server alias, Buffer as function type | **Done** |
| 21d | Buffer advanced | alloc fill string/Buffer/hex, from ArrayBuffer/Uint8Array, isEncoding case-insensitive, concat totalLength | **Done** |
| 21e | Stream flowing | Readable auto-flows on 'data' listener (Node.js compat), EventEmitter.rawListeners | **Done** |
| 21f | Crypto scryptSync | Returns Buffer instead of hex string (Node.js compat) | **Done** |
| 21g | OS tmpdir | Strip trailing slash from os.tmpdir() | **Done** |
| 21h | Production readiness | 122-check comprehensive validation test across all core Node.js APIs | **Done** |
| 22a | Intl polyfills | toLocaleString for Number/Date/String/Array, localeCompare, toLocaleLowerCase/UpperCase | **Done** |
| 22b | hrtime.bigint | process.hrtime.bigint() returns proper BigInt instead of float | **Done** |
| 22c | crypto.getRandomValues | Available on require('crypto') module (Node 19+ compat) | **Done** |
| 22d | Buffer.from ArrayBuffer | 3-arg form: Buffer.from(ArrayBuffer, byteOffset, length) | **Done** |
| 22e | child_process Buffer | execSync/spawnSync return Buffer by default, encoding option for string | **Done** |
| 22f | path.join empty | path.join("") returns "." (Node.js compat) | **Done** |
| 23a | Error.stack format | QuickJS-only "ErrorName: message\n" prefix for Node-compatible stack traces | **Done** |
| 23b | writeHead arrays | ServerResponse.writeHead supports array headers and optional statusMessage | **Done** |
| 23c | console %c | Handle CSS %c format specifier (consume+skip style argument) | **Done** |
| 23d | process.versions.v8 | Present on all backends for npm package compatibility | **Done** |
| 23e | util.inspect props | .custom Symbol, .colors, .styles, .defaultOptions properties | **Done** |
| 23f | JSC typed array offset | getTypedArrayBytes accounts for byteOffset in views | **Done** |
| 23g | Buffer.fill cycling | Multi-byte fill strings cycle correctly (was using first char only) | **Done** |
| 23h | Buffer instanceof U8 | Uint8Array[Symbol.hasInstance] returns true for Buffer objects | **Done** |
| 23i | path.relative empty | Identical paths return "" instead of "." (Node.js compat) | **Done** |
| 23j | fs.readFileSync empty | Fix ENOENT on empty/device files (/dev/null) | **Done** |
| 23k | Test runner timeout | 30s per-test timeout prevents JSC hangs | **Done** |
| 24a | WebAssembly | Microtask polyfill for compile/instantiate/streaming (JSC + V8); QuickJS reports friendly error | **Done** |
| 24b | dun:wasi | WASI preview1 module (args, env, clock, random, fd_*, path_*) wired through dun:fs / process | **Done** |
| 24c | dun run *.wasm | `.wasm` extension dispatch synthesizes WASI bootstrap that instantiates and calls `_start` | **Done** |
| 24d | Binary stdout | process.stdout/stderr.write accepts Uint8Array/Buffer (binary-safe fd_write from WASI) | **Done** |
| 25a | Persistent transpile cache | `$DUN_HOME/cache/tsc/<sha256>.js` keyed on source+filename+tsc-version; ~30x speedup on cache hit | **Done** |
| 25b | User-global package store | `dunGlobalRoot()` in `dun.platform.paths` (Posix $HOME/.dun, Windows %LOCALAPPDATA%\dun); `DUN_HOME` override; installPackage gained installRoot | **Done** |
| 25c | Resolver $DUN_HOME fallback | `require()` falls back to `$DUN_HOME/node_modules` after project tree walk fails | **Done** |
| 25d | Auto-install typescript | `DUN_AUTO_INSTALL_TSC=1` for default tsc path (--typecheck always auto-installs); both target $DUN_HOME | **Done** |
| 25e | RegExp /v set ops | `expandVSetOps()` source rewriter resolves `[A--B]` / `[A&&B]` to /u-equivalent range class; ECMAScript spec now 98/98 on QJS+V8 (was 97/98) | **Done** |
