# Performance

How DunJS performs against Node, Deno, and Bun — and how to get the
best out of it.

## Cross-runtime benchmarks (v1.1.24)

### feature_bench.js — JS compute throughput

| Runtime | ops/sec | vs Node |
|---------|--------:|--------:|
| Bun 1.3 | 501M | 3.09× |
| **dun-jsc** | **500M** | **3.09×** (par with Bun) |
| Node 22 | 162M | 1.00× |
| dun-v8 | 161M | 0.99× |
| Deno 2.7 | 160M | 0.99× |
| dun-qjs | 23M | 0.14× |

DunJS JSC backend is at parity with Bun on `feature_bench.js` since
the v1.1.7 cached Response builder + v1.1.9 handle pin landed.
v1.1.16 → v1.1.20 added fs stream-method caching,
`newUint8ArrayZeroedWithProto` fused Buffer.alloc primitive, v8shim
hot-path opts (Persistent::Reset elimination + Int32/Number fast
paths), dgram + cluster method caching, and jscpd-driven dedup.

### framework_bench.js — real-world framework patterns

| Runtime | ops/sec | vs Node |
|---------|--------:|--------:|
| Bun 1.3 | 300M | 1.69× |
| **dun-jsc** | **266M** | 1.49× |
| Node 22 | 178M | 1.00× |
| dun-v8 | 164M | 0.92× |
| Deno 2.7 | 159M | 0.89× |
| dun-qjs | 17M | 0.10× |

### npm_compat — correctness

All 6 runtimes pass **145/145** checks (Bun, Node, Deno, dun-jsc,
dun-v8, dun-qjs). Full cross-runtime correctness parity.

### HTTP benchmarks (wrk, 64 conns, 10s)

| Endpoint | Bun 1.3 | Deno 2.7 | Node 22 | dun-v8 | dun-jsc | dun-qjs |
|----------|--------:|---------:|--------:|-------:|--------:|--------:|
| /plaintext | 80,354 | 68,079 | 50,838 | 34,635 | 18,381 | 16,299 |
| /json | 79,724 | 68,021 | 59,071 | 37,325 | 18,206 | 16,564 |
| /echo | 70,868 | 58,193 | 57,521 | 28,994 | 17,314 | 15,046 |
| /compute | 83,964 | 68,631 | 57,738 | 34,274 | 17,921 | 15,455 |

The HTTP server is currently DunJS's weakest area relative to Bun.
The CPU-bound benches are where JSC's JIT pays for itself; the HTTP
hot path needs more native-side optimization (per-request handle
recycling, zero-copy response paths).

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

## LDC compiler features

DunJS ships with three pre-built [LDC](https://github.com/ldc-developers/ldc)
configurations on top of plain `release` for the perf-critical paths.

### Release flag breakdown (`dub build -b release`)

`dub.json` passes these to LDC:

| Flag | What it does |
|------|--------------|
| `-O3` | LLVM aggressive optimization |
| `--release` | Disable contracts / invariants / asserts |
| `--boundscheck=off` | No `RangeError` instrumentation |
| `--mcpu=native` | Tune for the host CPU (replace before shipping a portable binary) |
| `--flto=thin` | ThinLTO — cross-module inlining at link time, faster than full LTO and uses far less memory ([Johan Engelen on ThinLTO](https://dconf.org/2018/talks/engelen.html)) |
| `--fno-plt` | Skip PLT indirection for shared-library calls |
| `--frame-pointer=none` | Free a register on AMD64 |
| `--linkonce-templates` | Merge identical template instantiations across TUs |
| `--inline-threshold=350` | Larger inline budget (default 225) |
| `--hot-cold-split` | Split rarely-executed code (LLVM `hot-cold-split` pass) into a separate section to keep the icache hot |

`-b release` strips the binary on POSIX (`lflags-posix: ["-s"]`).

### Profile-Guided Optimization (PGO)

PGO instruments your binary, lets you run a representative workload,
then recompiles with the collected profile. Real-world gain on the LDC
front-end itself was ~7% per [Johan Engelen's writeup](https://johanengelen.github.io/posts/2016-07-15-profile-guided-optimization-with-ldc/).
DunJS exposes the workflow as two build types:

```sh
# 1. Instrumented build (writes build/dun-<pid>.profraw at runtime)
dub build -c quickjs -b release-pgo-gen

# 2. Run representative workloads to collect profile data
./build/dun run tests/benchmarks/feature_bench.js
./build/dun run tests/benchmarks/framework_bench.js
bash tests/benchmarks/http_bench/stress.sh

# 3. Merge the .profraw files into build/dun.profdata
ldc-profdata merge -o build/dun.profdata build/dun-*.profraw

# 4. Final optimized build using the profile
dub build -c quickjs -b release-pgo
```

The PGO-instrumented build is slower than `-b release` (instrumentation
overhead) — only use it for the profile-collection phase. Make sure
the workload you run covers the code paths you actually care about;
PGO only optimizes what it observes.

### `ldc.attributes`, `ldc.intrinsics`, `ldc.simd`

When writing a new built-in or hot path, `version (LDC)` opens up
LLVM-backed primitives that DMD/GDC lack. The pattern DunJS uses
across the codebase:

```d
version (LDC)
{
    import ldc.simd : loadUnaligned, storeUnaligned, shufflevector;
    import ldc.intrinsics : llvm_cttz, llvm_prefetch, llvm_bswap;
    import ldc.attributes : fastmath, target;
}

@fastmath
double dotProduct(const(double)[] a, const(double)[] b) pure @nogc nothrow
{
    // -ffast-math: associative + reciprocal + no-NaN/Inf assumptions.
    // Lets LDC vectorize the loop. Don't use on code that depends on
    // strict IEEE 754 semantics (e.g. fp-bit-pattern parsing).
    double s = 0;
    foreach (i; 0 .. a.length) s += a[i] * b[i];
    return s;
}

@target("avx2")
ubyte16 hexEncodeAvx2(ubyte16 src) pure @nogc nothrow @trusted { ... }
```

Already used in DunJS:
- `source/dun/platform/simd.d` — `loadUnaligned`/`storeUnaligned`/`shufflevector` for 16-byte/cycle hex/toLower/byte-search; `llvm_cttz` for O(1) first-match; `llvm_prefetch` for cache warming; `llvm_bswap` for Buffer BE ops.

For the full attribute list (`@cold`, `@naked`, `@noplt`, `@optStrategy`,
`@section`, `@target`, `@weak`, `@fastmath`, `@llvmAttr`, …) see
[`ldc/attributes.d` on GitHub](https://github.com/ldc-developers/ldc/blob/master/runtime/druntime/src/ldc/attributes.d).

### Object-file cache for incremental builds

For CI or scratch-rebuild workflows, LDC can skip codegen for unchanged
modules ([writeup](https://johanengelen.github.io/ldc/2016/09/17/LDC-object-file-caching.html)):

```sh
DFLAGS="--ir2obj-cache=$HOME/.cache/dun-ldc-cache" dub build -c quickjs
```

Engelen's measurement on the LDC front-end itself: 5m50 → 2m30 for a
full `-O3` rebuild with 100% cache hit (optimization + codegen are
skipped, only linking runs). Prune with:

```sh
# Cap to 2 GiB (default is 75% of available disk via --max-percentage-of-avail)
ldc-prune-cache --max-bytes=2147483648 $HOME/.cache/dun-ldc-cache
```

The cache lives outside the DUB build tree and survives `dub clean`.

### Sanitizers

LDC ships `-fsanitize=address` and `-fsanitize=thread` runtimes
([Engelen's ASan walkthrough](https://johanengelen.github.io/posts/2017-12-25-ldc-and-addresssanitizer/),
[fuzzing writeup](https://johanengelen.github.io/posts/2018-01-14-fuzzing-with-ldc/)).
DunJS pre-wires both as DUB build types:

```sh
dub build -c quickjs -b asan
ASAN_OPTIONS=detect_leaks=0 bash tests/integration/run.sh   # 155/155 clean

dub build -c quickjs -b tsan
bash tests/integration/run.sh                                # daemon worker threads excluded
```

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
