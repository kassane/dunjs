# Backends

DunJS implements a pluggable engine abstraction (`IJSEngine`). Every
built-in module, the event loop, the permission system, the runtime
APIs — all are engine-agnostic. Only the code in `source/dun/engine/<name>/`
touches raw engine APIs.

You pick the backend **at build time**. The same source code runs
identically on all three.

## Comparison

| | QuickJS-NG | JavaScriptCore | V8 |
|---|---|---|---|
| **Type** | Interpreter | JIT (LLInt + Baseline + DFG + FTL) | JIT (Ignition + TurboFan + Maglev) |
| **Upstream** | bellard/QuickJS-NG | WebKit (Safari/Bun) | Chromium (Chrome/Node) |
| **Binary size** | ~9.8 MB | ~60 MB | ~60 MB |
| **Startup** | Fastest | Medium | Medium |
| **CPU-bound JS** | 10-100× slower (interpreter) | Fastest | Fast |
| **ES2025 support** | Full | Full | Full |
| **Best for** | CLI tools, embedded, small bins | Throughput, HTTP servers, compute | Node.js compat, drop-in replacement |

## Performance snapshot (v1.1.26)

Per-bench, release builds, single-threaded:

| Bench | Bun 1.3 | Node 22 | Deno 2.7 | dun-jsc | dun-v8 | dun-qjs |
|---|---:|---:|---:|---:|---:|---:|
| feature_bench (compute) | 501M ops/s | 162M | 160M | **500M** | 161M | 23M |
| framework_bench (compute) | 300M | 178M | 159M | **266M** | 164M | 17M |
| http_bench plaintext | 80,354 rps | 50,838 | — | 18,381 | 34,635 | 16,299 |
| http_bench json | 79,724 | 59,071 | — | 18,206 | 37,325 | 16,564 |
| npm_compat (correctness) | 145/145 | 145/145 | 145/145 | 145/145 | 145/145 | 145/145 |

Highlights:

- **dun-jsc at parity with Bun on `feature_bench`** (500M vs 501M)
  since v1.1.7's cached Response builder + v1.1.9's handle pin.
- **dun-jsc close to Bun on `framework_bench`** (266M vs 300M, ~89%).
- **dun-v8 within ~8% of Node** on framework_bench (164M vs 178M).
- **dun-qjs** is 10-30× slower on CPU-bound code (interpreter trade-off),
  but matches everyone on `npm_compat` correctness and has the fastest
  startup time of all five runtimes.

See [tests/benchmarks/](../tests/benchmarks/) for the bench sources.

## Build flags per backend

```sh
ldc2 -run build.d --backend=quickjs   # default
ldc2 -run build.d --backend=jsc
ldc2 -run build.d --backend=v8

dub build -c quickjs                  # debug
dub build -c quickjs -b release       # release (use this)
dub build -c jsc -b release
dub build -c v8 -b release
```

## Engine sources

| Backend | Source | API |
|---------|--------|-----|
| QuickJS-NG | [quickjs-ng/quickjs](https://github.com/quickjs-ng/quickjs) | C API (quickjs.h) |
| JavaScriptCore | [oven-sh/WebKit](https://github.com/oven-sh/WebKit) prebuilt | C API + WebKit C++ |
| V8 | [kassane/libv8](https://github.com/kassane/libv8) prebuilt 15.0.206 | C++ via vendor/v8shim/ |

DunJS doesn't compile WebKit from source — it pulls a prebuilt
tarball from the `oven-sh/WebKit` autobuild releases. The current pin
is `88b2f7a2159c913f7dd0d73c0e88d66138cd67ba` (selected for its JIT
flag profile — see `build.d` comments).

## When to pick which

### Pick QuickJS-NG when…
- Binary size matters (~10 MB vs ~60 MB)
- You want the fastest cold-start (~5 ms vs ~30 ms)
- The workload is I/O-bound, not CPU-bound
- You're embedding DunJS in a larger app
- You need the most predictable timing (no JIT warmup spikes)

### Pick JavaScriptCore when…
- CPU-bound JS is the hot path
- You want raw throughput on real-world apps
- You're comparing against Bun (same engine)
- You're on macOS / iOS (native engine)

### Pick V8 when…
- Maximum Node.js compatibility matters
- You're porting code that relies on V8-specific behavior
  (e.g., `Error.captureStackTrace`, `--inspect`)
- You're comparing against Node.js (same engine)

## Backend-specific gotchas

### QuickJS-NG
- **No JIT** — CPU-bound code is 10-100× slower than JIT'd backends
- **NativeCallback slot limit** — uses `int16_t` magic values; max
  32,767 callback slots. Cached function handles via `engine.bindMethod`
  to stay well under

### JavaScriptCore
- **NUL-byte handling** — `JSStringCreateWithUTF8CString` terminates
  at the first NUL. DunJS routes through `createJSStringFromD`
  (NUL-safe) since v1.1.3
- **Cached `__gshared` handles** — must double-dup before freeValue
  (JSC's `dupValue` increments, `freeValue` decrements; single-dup
  drops back to 0). See v1.1.9 changelog entry
- **Concurrent GC vs trampoline lock** — under heavy iteration,
  JSC's incremental GC can contend with our trampoline JSLock.
  See `/debug-native-callback` skill for the gdb workflow

### V8
- **CREL relocations** — V8 14.9+ / 15.0+ monolith uses LLVM 19+ CREL.
  Requires LDC's internal linker (`--link-internally`)
- **ICU symbols** — V8 ships its own ICU; conflicts can arise if
  the host has a different ICU version
- **`setPropertyIndex` doesn't consume** — caller must `freeValue`
  the value (unlike QJS which consumes)

## Engine abstraction (`IJSEngine`)

All backends implement [`IJSEngine`](../source/dun/engine/iface.d) —
~40 methods covering:

- Value creation: `newString`, `newInt`, `newFloat`, `newBool`,
  `newArray`, `newObject`, `newFunction`, `newUint8Array`
- Conversion: `extractString`, `extractInt`, `extractFloat`,
  `extractBool`, `getTypedArrayBytes`
- Type checks: `isString`, `isNumber`, `isArray`, `isFunction`, etc.
- Property access: `getProperty`, `setProperty`, `getPropertyIndex`,
  `setPropertyIndex`
- Function call: `callFunction`
- Lifetime: `dupValue`, `freeValue`, `bindMethod`
- Eval: `eval`, `evalModule`
- Error handling: `throwTypeError`, `throwRangeError`
- Native callbacks: `NativeCallback` registry

If you're writing a new built-in module, you only see `IJSEngine` —
you'll never `import dun.engine.jsc.bindings`. The same code works
on every backend.

See [ARCHITECTURE.md](../ARCHITECTURE.md) for the full engine
abstraction layer design.
