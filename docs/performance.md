# Performance

How DunJS performs against Node, Deno, and Bun — and how to get the
best out of it.

## Cross-runtime benchmarks (v1.1.27)

Numbers from `/bench-compare` on 2026-05-23 against `tests/benchmarks/*.js`,
release builds + the `dun-rel-*` binaries the `/all-backends release`
skill stages. Runtimes downloaded fresh from upstream tarballs:
**Bun 1.3.14**, **Node 22.22.2**, **Deno 2.8.0**.

### feature_bench.js — JS compute throughput

| Runtime | ops/sec | vs Node |
|---------|--------:|--------:|
| Bun 1.3.14    | 413M | 3.74× |
| **dun-rel-jsc** | **411M** | **3.73×** (within noise of Bun) |
| dun-rel-v8    | 118M | 1.07× |
| Deno 2.8.0    | 112M | 1.01× |
| Node 22.22.2  | 110M | 1.00× |
| dun-rel-qjs   | 17M  | 0.16× (interpreter) |

DunJS JSC reaches **99.6%** of Bun on `feature_bench.js` — same V8
heritage (JSC), with the v1.1.7 cached Response builder + v1.1.9
handle pin + v1.1.16-20 stream/dgram/Buffer-alloc method-cache
campaign closing the FFI-overhead gap. v1.1.27 added a shared
`statProto` with lazy Date getters that cuts `statSync` 45-51%
on JIT backends and 29% on QJS (see [TESTING.md](../TESTING.md)
fs_bench breakdown).

### framework_bench.js — real-world framework patterns

| Runtime | ops/sec | vs Node |
|---------|--------:|--------:|
| Bun 1.3.14    | 283M | 2.11× |
| **dun-rel-jsc** | **165M** | 1.24× |
| Node 22.22.2  | 134M | 1.00× |
| dun-rel-v8    | 130M | 0.97× |
| Deno 2.8.0    | 125M | 0.93× |
| dun-rel-qjs   | 13M  | 0.10× |

### fs_bench.js — POSIX FS ops

| Runtime | ops/sec | vs Node |
|---------|--------:|--------:|
| Bun 1.3.14    | 8.0M | 1.13× |
| Node 22.22.2  | 7.1M | 1.00× |
| Deno 2.8.0    | 4.1M | 0.58× |
| dun-rel-qjs   | 3.9M | 0.55× |
| dun-rel-v8    | 3.3M | 0.46× |
| dun-rel-jsc   | 2.4M | 0.34× |

DunJS lags on fs_bench — the path-canonicalization step in the
permission check (CVE-2023-32004 fix) is unavoidable for hot writes
but adds ~5-10μs per `writeFileSync`. The v1.1.27 `statProto`
fix is the per-call win; further gains would need a path-canon
cache, `sendfile()` on Linux for `copyFileSync`, and/or a fused
`(open, write, close)` builtin for `writeFileSync`.

### npm_compat — correctness

All 6 runtimes pass **145/145** checks (Bun 1.3.14, Node 22, Deno 2.8.0,
dun-jsc, dun-v8, dun-qjs). Full cross-runtime correctness parity.

### react_compat — correctness

All 6 runtimes pass **81/81** checks. Full cross-runtime parity.

### HTTP benchmarks (wrk, v1.1.29 measurement, 64 conns, 5s/endpoint)

| Endpoint | Bun 1.3.14 | Deno 2.8.0 | Node 22 | dun-v8 | dun-jsc | dun-qjs |
|----------|--------:|---------:|--------:|-------:|--------:|--------:|
| /plaintext | 50,368 | 45,112 | 31,807 | 36,722 | **40,470** | 31,953 |
| /json     | 57,261 | 43,173 | 31,750 | 38,218 | 37,283 | 29,270 |
| /echo     | 45,599 | 31,789 | 26,507 | **33,907** | 24,602 | 21,020 |
| /compute  | 46,987 | 47,361 | 31,024 | 36,355 | 30,050 | 23,684 |

**DunJS beats Node 22 on every endpoint and every backend** (104-122%
on plaintext, 92-120% on json, 79-128% on echo, 76-117% on compute).

DunJS JSC tops the DunJS backends on plaintext (**40,470 req/s**, +10%
vs dun-v8 36,722 and +27% vs Node 22), confirming the cumulative
v1.1.5-v1.1.20 JSC handle-leak campaign + v1.1.26 `_writeHeadFlattener`
cache + v1.1.27-29 thread-local factory caches paid off. JSC HTTP
perf is variable run-to-run — under sweep heap-load + concurrent-GC
pressure it drops 30% (HANDOFF Known issue #1 documents the
`deno_deploy_compat` flake mechanism). Fresh JSC processes hit the
ceiling reported here.

DunJS V8 is the most consistent backend (37k ±0.5k across runs) and
the only backend that beats Bun on `echo` (33,907 vs 25,413 — but
behind Bun 45,599; Deno 31,789).

Remaining ~25-30% gap to Bun on plaintext/json is dominated by
per-request FFI overhead — `req.headers` lazy-loader (40% of the
echo gap on QJS), `Content-Length` string interpolation, response
builder factory. **v1.1.30 partial fix (PR #99 + #100)**: HTTP
dispatcher now uses `sockProto` / `reqProto` / `resProto` installed
once + `Object.create(proto)` per request, cutting per-request
object setup from ~30 property assignments to ~8 (varying fields
only — method, url, __cid, connection, socket). Methods + defaults
inherit from the proto so JIT engines (V8 / JSC) share one inline-
cache call site across all dispatched requests. PR #100 also dropped
the unused `_events: {}` / `_headerValues: {}` per-request initializations.
Re-run `/bench-compare` to verify the wrk numbers update.

## Picking a backend

| Workload | Recommended | Why |
|----------|-------------|-----|
| CLI tools | dun-qjs | Smallest binary, fastest startup |
| HTTP servers | dun-v8 or dun-jsc | JIT |
| Compute-heavy (hashing, crypto, parsing) | dun-jsc | Fastest CPU benchmarks |
| Maximum Node parity | dun-v8 | Same engine as Node |

See [Backends](./backends.md) for the full comparison.

## GC tuning

DunJS sets `gcopt=minPoolSize:16` by default in `app.d` — a 16 MiB
minimum GC pool that reduces collections ~11× over the D default.

For long-running servers, you can bump this:

```sh
dun "--DRT-gcopt=minPoolSize:32 maxPoolSize:512" run server.js
```

Profile GC behavior:

```sh
dun "--DRT-gcopt=profile:1" run script.js
# Prints at exit:
#   Number of collections:  6
#   Total GC prep time:     0 milliseconds
#   Total mark time:        2 milliseconds
#   Total sweep time:       1 milliseconds
#   ...
```

See [GC Tuning](./gc-tuning.md) for the full options.

## Hot-path patterns

If you're writing a built-in module or addon and want top-tier perf:

1. **Cache JS functions, don't `engine.eval()` per call.** Compile
   the function once at first use, reuse with value arguments. See
   `_fetchResponseBuilder` in `source/dun/builtins/fetch.d`.

2. **Use SIMD helpers.** Hex encoding (`hexEncode`), Latin-1 ↔ UTF-8
   (`latin1ToUtf8Buf`), byte search (`findByte`), ASCII lowercase
   (`asciiToLowerBuf`) — all in `source/dun/platform/simd.d`. 16
   bytes/cycle on LDC builds via `shufflevector` + `llvm_cttz`.

3. **Use the StackFallback allocator.** `dun.platform.arena.StackFallback!N`
   gives you stack-first, GC-overflow allocation for per-call
   scratch buffers. Avoids GC pressure for the common case.

4. **CTFE lookup tables.** Use `enum` + immediately-invoked CTFE
   functions for encoding tables. See the hex LUT in
   `source/dun/builtins/buffer.d`.

5. **Avoid per-call `setProperty(obj, k, dupValue(X))` on JSC.** JSC
   doesn't consume the value — the dup leaks one `JSValueProtect`
   per call. Use `engine.bindMethod` for cached __gshared function
   handles.

6. **Use `setPropertyIndex` for array elements.** O(1) vs O(n)
   string-keyed access.

7. **Watch the JSC handle-protect counter.** When caching a
   `__gshared JSHandle`, the canonical pattern is:

   ```d
   engine.dupValue(result.value);              // counter: 0 → 1
   _cachedHandle = engine.dupValue(result.value); // counter: 1 → 2
   engine.freeValue(result.value);             // counter: 2 → 1
   ```

   Without the double-dup, `freeValue` drops the counter to 0 and
   JSC's GC will eventually collect your cached handle under
   stress. See v1.1.9 changelog.

See [CLAUDE.md](../CLAUDE.md) for the full hot-path pattern catalog.

## Workers + parallelism

DunJS Workers are real OS threads with their own engine instances.
Shared state goes through `SharedArrayBuffer` + `Atomics` (lockfree
refcount, TSan-clean).

For embarrassingly-parallel workloads:

```js
import { Worker } from "node:worker_threads";

const workers = Array.from({ length: 8 }, () =>
  new Worker("./worker.js"));

await Promise.all(workers.map((w, i) =>
  new Promise(r => {
    w.postMessage(chunk(i));
    w.on("message", result => { record(result); r(); });
  })));
```

See `dun:worker_threads` in the [built-ins index](./builtins/index.md).

## Profiling

DunJS has `console.time` / `console.timeEnd` / `performance.now()` /
`Bun.nanoseconds()`. For deeper profiling on V8, `--inspect` opens
a Chrome DevTools-compatible port.

For native-side perf:

```sh
perf record -g ./build/dun run --allow-all script.js
perf report

# Or with flame graphs:
perf script | flamegraph.pl > flame.svg
```

## What's not yet optimized

- **HTTP server per-request hot path** — Bun's native HTTP server
  outperforms DunJS by 2-3×. Path to close: zero-copy response
  paths, native header parser, connection pool reuse.
- **JSON.parse / JSON.stringify of large objects** — currently
  routed through engine native; could use simdjson-style SIMD.
- **WebStreams** — implemented but the byte stream path could be
  zero-copy on JSC.

If you hit a perf wall, file an issue with a reproducer and we'll
investigate via the `/debug-native-callback` workflow.
