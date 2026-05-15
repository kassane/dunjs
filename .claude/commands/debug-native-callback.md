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
