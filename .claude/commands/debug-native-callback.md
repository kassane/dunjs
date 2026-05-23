---
description: gdb workflow + reproducer template for native-callback bugs (JSC trampoline deadlocks, QuickJS slot overflows, Buffer.concat segfaults). Use when seeing `Uncaught null`, `Hash slot overflow`, `Aborted`, `Segmentation fault`, or JSC hangs at `JSC::Heap::acquireAccessSlow` under heavy iteration.
---

# Debug Native Callback

For deadlocks/segfaults that only manifest under iteration pressure — the bugs
this session uncovered (Hash slot overflow, JSC Buffer.concat segfault,
JSC trampoline JSLock churn).

## When to reach for this

- `Uncaught null` printed by the runtime (not by JS code)
- `Hash slot overflow` / `HMAC slot overflow` assertions
- `Segmentation fault` after thousands of iterations
- Process hangs forever — gdb shows `__futex_abstimed_wait_cancelable64`
  → `JSC::Heap::acquireAccessSlow` or `WTF::ParkingLot::parkConditionally`
- Test passes in isolation but fails inside the benchmark loop (
  feature_bench.js Buffer section is the canonical example)

## Reproducer template

```js
// /tmp/repro.js
function bench(name, fn, iters = 100_000) {
  for (let i = 0; i < 50; i++) fn();          // warmup, JIT compile
  const start = Date.now();
  try {
    for (let i = 0; i < iters; i++) fn();
  } catch (e) {
    console.log("FAIL @", i, e === null ? "NULL" : String(e));
    return;
  }
  const mem = process.memoryUsage();
  console.log("OK", name,
    Date.now() - start, "ms",
    "heap=" + Math.round(mem.heapUsed / 1024 / 1024) + "M");
}

// Replace with the failing pattern + any prerequisites
bench("repro", () => {
  /* hot loop here */
});
```

Run with progressively larger `iters` until it crashes. Note the
heap=XXX number at the last successful step — that bracket is the
allocation pressure threshold.

## Step 1: Always reproduce in debug

Release builds strip assertions (`-boundscheck=off`). The debug build
hits `assert(... < MAX_..._SLOTS, "... slot overflow")` and points at
the file:line, which is much more actionable than a release-build
segfault.

```sh
dub build -c <backend>           # debug
./dun run --allow-all /tmp/repro.js
```

If the debug build aborts with a D assertion or printed stack trace,
that's the bug — skip the rest of this guide and look at the offending
file.

## Step 2: gdb when no D-side assertion fires

```sh
cat > /tmp/gdb.cmd <<'EOF'
set pagination off
handle SIGSEGV nostop noprint pass
run --allow-all /tmp/repro.js
bt 25
info registers
quit
EOF
timeout 120 gdb -batch -x /tmp/gdb.cmd ./dun 2>&1 \
  | grep -E "Program received|^#[0-9]+ " \
  | head -30
```

Patterns to look for in the backtrace:

| Top frames | Likely cause | Fix pattern |
|---|---|---|
| `JSC::Heap::acquireAccessSlow` → `WTF::ParkingLot::parkConditionally` → `__futex_abstimed_wait_cancelable64` | JSC concurrent-GC vs. our trampoline lock contention | Cache the per-function private data (avoid `JSValueToNumber` per call). See `JSObjectSetPrivate` fix in `source/dun/engine/jsc/backend.d` newFunction |
| `JSValueProtect` / `JSValueUnprotect` | Reference-counting underflow or leaked protection | Audit `dupValue` / `freeValue` pairing for the type. JSC `dupValue` adds a protection; `freeValue` removes it. Symmetric or you crash. |
| `JS_Eval` → `JS_FreeValue` (QuickJS) | Refcount underflow | Look for missing `dupValue` before `setProperty` (which consumes) |
| `__GI___assert_fail` with `... slot overflow` | Monotonic slot ID counter | Add an `int[]` free-list, push on `digest()`/destroy, pop on `create()`. See `_freeHashIds` in `source/dun/builtins/crypto.d` |
| Main thread in `epoll_wait(timeout=0)`, worker in `read(fd=N)` | Per-cycle JS bytecode compile leak (uncacheable eval source) | Cache the function at first use with `engine.dupValue(eval result)`, call with value args instead of inlining them in source. See `_fetchResponseBuilder` / `_fetchHeadersFlattener` in `source/dun/builtins/fetch.d` (v1.1.7 fix — JSC fetch_only stress moved from 27 → 30+ on all backends) |
| `Uncaught SyntaxError: Unexpected EOF` on JSC, source contains literal `\0` | `JSStringCreateWithUTF8CString` terminates at first NUL | Route through the NUL-safe `createJSStringFromD` helper in `source/dun/engine/jsc/backend.d` (v1.1.3 / v1.1.4) |
| `Buffer.toString('latin1')` or `Buffer.from(str, 'latin1')` returns empty or garbled bytes ≥ 0x80 | UTF-8 / Latin-1 conversion bug | Use `dun.platform.simd.latin1ToUtf8Buf` (encode) / `utf8ToLatin1Buf` (decode) — Latin-1 constants live in `source/dun/declarations.d` |

## Step 3: Bisect by stripping

If the bug only triggers in a multi-benchmark sequence:

1. Take the reproducer down to the smallest combination that still fails.
2. Use the heap=XXX printout to find when memory growth diverges.
3. The bench BEFORE the failing one is often the leak source — look for
   `dupValue()` returns into JS, or `setProperty(obj, k, dupValue(X))`
   patterns (JSC leaks one protection each).

## Step 4: Common fixes

- **Slot exhaustion** → add free-list recycling (see `_freeHashIds` /
  `_freeHmacIds` in `source/dun/builtins/crypto.d`).
- **`engine.freeValue` before final use** → re-order so all reads happen
  before frees.
- **GC-sensitive transient handle** → `auto pinned = engine.dupValue(h);
  scope(exit) engine.freeValue(pinned);` around the GC-triggering call
  (e.g., Buffer.concat result pinned across the memcpy + factory call).
- **Hot-path callback identification** → switch from `__cbSlot__`
  property to `JSObjectSetPrivate` so the slot lookup is a pointer load,
  not a `JSValueToNumber`.

## Anti-patterns to avoid

- **Don't** assume "segfault" means a memory bug — JSC's hung
  acquireAccess often looks like a segfault when killed.
- **Don't** try to disable JIT with `JSC_useJIT=false` — these env vars
  are honored only by WebKit's `jsc` shell, not by embedders using the
  C API (`vendor/jsc/lib`).
- **Don't** add `JSValueProtect` to every `newX` in JSC unless you also
  make every `setProperty` consume — partial changes break the
  refcount accounting on ~360 call sites.
- **Don't** trust the test's own crash message — `"CRASH @<error-compat>:1:3877"`
  in `deno_deploy_compat` output is the test's own `Promise.race`
  timeout caught by its `.catch`, formatted via the `<error-compat>`
  wrapper at the top of the stack. The actual bug is a fetch-hang,
  not a JSC crash. Investigate where the fetch is blocked, not where
  the JS exception was formatted.
- **Don't** build per-fetch JS source strings with response body
  embedded — JSC compiles bytecode per unique source and never
  evicts it. This was the v1.1.7 root-cause fix; see `_fetchResponseBuilder`
  pattern. Same warning for headers flattener, JSON parse paths,
  and any other "eval per call" code.

## LDC sanitizers — when gdb isn't enough

LDC ships AddressSanitizer + ThreadSanitizer + libFuzzer (LLVM-backed,
same flags as Clang). DunJS pre-wires ASan/TSan as DUB build types.

### AddressSanitizer (`-b asan`)

Use when gdb shows a segfault but no useful stack — ASan turns
buffer overflows / use-after-free / double-free into a precise
"READ/WRITE of size N at address X, allocated here / freed here"
report with stack traces on both sides. Same flag as Clang/GCC:
`-fsanitize=address`. Reference: Johan Engelen's writeup at
https://johanengelen.github.io/posts/2017-12-25-ldc-and-addresssanitizer/
(found a real bug in `core/atomic.d`, fixed in LDC 1.4.0).

```sh
dub build -c quickjs -b asan
# LSan often false-positives on D's GC roots — disable on integration sweeps
ASAN_OPTIONS=detect_leaks=0 ./build/dun run --allow-all /tmp/repro.js
ASAN_OPTIONS=detect_leaks=0 bash tests/integration/run.sh   # full 167/167 sweep
```

ASan symbolicates D mangled names automatically. The runtime-overhead
is ~2-3× — usable for repros, too slow for benchmarks.

### ThreadSanitizer (`-b tsan`)

Use when a Worker / SAB / Atomics test crashes intermittently or
the test passes solo but fails under sweep heap-load. TSan reports
data races between threads with both stack traces.

```sh
dub build -c quickjs -b tsan
./build/dun run --allow-all /tmp/repro_workers.js
```

DunJS's worker pool is TSan-clean modulo intentional daemon worker
threads (the daemon threads use lockfree primitives audited by hand).
A new TSan failure means a real race in your change.

### libFuzzer (`-b fuzzer` build type, LDC 1.4.0+)

For finding parser / type-stripper / JSON / URL / regex inputs that
crash. `dub.json` exposes a `fuzzer` build type:

```json
"fuzzer": {
  "dflags": ["-O1", "-g", "--fsanitize=fuzzer,address"],
  "lflags-posix": ["-lpthread"]
}
```

`-b fuzzer` is for binaries you wire by hand — the standard `app.d`
entry point isn't a fuzz target. The pattern: write a small `.d`
file with `LLVMFuzzerTestOneInput`, compile it via `ldc2` directly
against the modules it exercises:

```d
// /tmp/fuzz_strip.d
import dun.ts.strip : stripTypes;

extern(C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow {
    if (size == 0 || size > 65536) return 0;
    try {
        auto src = cast(const(char)[]) data[0 .. size];
        auto out_ = stripTypes(src);
        if (out_.length > 0 && out_[0] == 0xff && out_[$-1] == 0xff)
            return 1;  // unreachable, prevents DCE
    } catch (Exception) {
        // Scanner is @safe; catching keeps the fuzzer alive
    }
    return 0;
}
```

```sh
ldc2 -fsanitize=fuzzer -O1 -g \
     -I=source -Jsource \
     -of=/tmp/fuzz_strip \
     /tmp/fuzz_strip.d \
     source/dun/ts/strip.d source/dun/ts/parser/lexer.d

# Seed corpus with realistic inputs, then let the fuzzer mutate
mkdir -p /tmp/ts-corpus
echo 'const x: number = 1;'                    > /tmp/ts-corpus/01
echo 'interface I<T> { a: T; b(): void; }'    > /tmp/ts-corpus/02
echo 'enum E { A = 1, B = "x" as const }'     > /tmp/ts-corpus/03
echo 'class C<T> { constructor(public x: T) {} }' > /tmp/ts-corpus/04
timeout 60 /tmp/fuzz_strip -max_len=4096 /tmp/ts-corpus/
```

Verified on LDC 1.42.0: the stripper fuzzer ran 10s and grew a
5-entry seed corpus to 4276 interesting inputs without crashing.
Saved inputs that hit new edges accumulate in the corpus dir;
reruns pick up where the previous one stopped. Any crash writes
the offending bytes to `crash-<sha1>` in the cwd.

Reference: https://johanengelen.github.io/posts/2018-01-14-fuzzing-with-ldc/

## CVE-class fixes (regression-tested)

Whenever you fix a CVE-class bug or correctness root cause:

1. **Cite the upstream advisory in the inline comment** — e.g.,
   "Mirrors Node CVE-2023-32004 (path traversal in fs)".
2. **Add a permanent fixture** in `tests/integration/fixtures/`
   (see `cve_path_traversal.js`, `audit_simd.js`,
   `audit_roundtrip.js` for the canonical patterns) so the
   regression check runs on every sweep.
3. **Update `SECURITY.md`** with the version, class, symptom,
   and fix description — future investigators trying to remove the
   fix should see exactly why it's there.
