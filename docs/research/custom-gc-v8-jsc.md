# Custom D GC backed by V8 cppgc / JSC Heap — case study

**Status**: Research + experimental prototype (`gc_arena.d`, behind
`version (DunCustomGC)`). Not on the v1.x roadmap.

**Audience**: maintainers considering whether to prototype a custom
D GC that delegates allocation to the embedded JS engine's heap.

## TL;DR

| Question | Answer |
|----------|--------|
| Can D bind to V8 cppgc / JSC heap C++ APIs directly (no extern(C) shim)? | **Yes** — validated end-to-end via `v8shim::Diagnostics` + `TypedCounter<Slot>`. Patterns are documented in §3 and tested in `tools/bindgen_tests/test_ffi_linkage.d`. |
| Should we route D allocations through cppgc / JSC heap? | **No** — see §4. Thread-affinity (cppgc heap is per-isolate; D GC is process-global) and the typed-Trace contract (cppgc requires `Trace(Visitor*)` per object; D allocates type-erased `void*`) are inherent to those designs, not FFI limitations. |
| Is D-side GC even the bottleneck in DunJS today? | **No** — GC is < 1% of CPU on `feature_bench.js` (§5). The actual V8 backend bottleneck is FFI scope overhead, addressed by `v8::FastApiCallback` — orthogonal to GC routing. |
| What about a faster D-side allocator (no engine involvement)? | **Yes, ship-worthy**. `std.experimental.allocator` Region/BorrowedRegion + `--DRT-gcopt=gc:precise` are practical. Expected +3-8% on URL/HTTP-heavy benches. See §7. |
| If perf isn't the win, why land the prototype? | The factory-recursion bug class (§6.2) is gdb-trace gold — the inline comment in `gc_arena.d` lets the next maintainer skip the same hour-long debug session. Reproduced **twice** in this branch's history. |

## 1. The two-heap problem

DunJS has two collectors in every process:

```
┌─────────────────────────────────────────┐
│  D runtime                              │
│  ┌──────────────────────────────────┐   │  ~16 MB initial pool
│  │ druntime conservative GC (CMS)   │   │  < 1% CPU under bench
│  │ - Appender buffers / Strings     │   │
│  │ - IJSEngine instances, DunState  │   │
│  │ - Closures, Workers, EventLoop   │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│  V8 / JSC / QuickJS-NG                  │
│  ┌──────────────────────────────────┐   │  ~few hundred MB live
│  │ V8 GC (Orinoco) / JSC GC (Riptide)│  │  5-10% CPU
│  │ - All JS objects, strings, arrays │  │  Already optimized
│  │ - DunV8Value wrappers (pooled)    │  │  (per-thread pool)
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

If we routed D allocations through the JS engine's GC — via [V8 cppgc](https://v8.github.io/api/head/namespacecppgc.html)
or the JSC heap — we'd have **one mark cycle covering both heaps**.
Same architectural payoff Blink gets from cppgc → DOM nodes ↔ JS
wrappers. That's the question this case study answers.

## 2. Background

### 2.1 D's `core.gc.gcinterface.GC` (verified against LDC 1.42)

The `GC` interface is **32 methods** at `/opt/ldc/import/core/gc/gcinterface.d`:

| Category | Methods | Notes |
|----------|---------|-------|
| Lifecycle | `enable`, `disable`, `collect`, `minimize` | Map to `cppgc::Heap::ForceGarbageCollectionSlow` / `JSC::Heap::collectAllGarbage` |
| Allocation | `malloc`, `qalloc`, `calloc`, `realloc`, `extend`, `reserve`, `free` | Hot path; returns raw `void*` + `BlkAttr` bits — **D's contract is type-erased** |
| Block metadata | `getAttr` / `setAttr` / `clrAttr`, `addrOf`, `sizeOf`, `query` | Recover info from a pointer mid-collection |
| Stats | `stats`, `profileStats`, `allocatedInCurrentThread` | The contract for `allocatedInCurrentThread` is **bytes, not count** — easy to get wrong |
| Roots | `addRoot` / `removeRoot` / `rootIter`, `addRange` / `removeRange` / `rangeIter` | The hardest bridge — D roots aren't cppgc/JSC roots and vice versa |
| Finalization | `runFinalizers`, `inFinalizer` | Class destructors |
| Threading | `initThread`, `cleanupThread` | Per-thread state |
| Arrays | `getArrayUsed`, `expandArrayUsed`, `reserveArrayCapacity`, `shrinkArrayUsed` | `~=` on slices hits these |

Registration pattern (the original prompt):

```d
import core.gc.gcinterface, core.gc.registry;

extern (C) pragma(crt_constructor) void registerMyGC() {
    registerGCFactory("mygc", &createMyGC);
}

GC createMyGC() {
    /* MUST NOT use D's `new` here — see §6.2 */
    return /* malloc + emplace */;
}
```

`crt_constructor` runs before `rt_init` (before druntime initializes
the GC). The user opts in with `dun "--DRT-gcopt=gc:mygc" run script.js`.

### 2.2 V8 cppgc (Oilpan)

V8 ships [`cppgc`](https://v8.dev/blog/oilpan-library) as a standalone
embedder library that Blink uses for DOM nodes. The relevant API:

```cpp
namespace cppgc {
    void InitializeProcess(PageAllocator* = nullptr);

    class Heap {
        static std::unique_ptr<Heap> Create(
            std::shared_ptr<Platform>, HeapOptions = HeapOptions::Default());
        AllocationHandle& GetAllocationHandle();
    };

    template <typename T, typename... Args>
    T* MakeGarbageCollected(AllocationHandle& h, Args&&... args);

    template <typename T> class Persistent { ... };  // cross-heap root
    template <typename T> class Member { ... };       // intra-heap field
}
```

Two design constraints that show up later as blockers:

1. **`MakeGarbageCollected<T>` requires `T : GarbageCollected<T>`**.
   Every allocated object has a header + a `Trace(Visitor*) const`
   method that walks outgoing pointers. **Cannot bind to arbitrary
   `void*` bytes** the way D's `GC.malloc` requires.

2. **Pointer hygiene**. Cross-object pointers inside managed objects
   must be `Member<T>`; off-heap → on-heap pointers must be
   `Persistent<T>`. Bare `T*` won't be scanned. D's GC contract gives
   you a raw `void*` you can put anywhere.

`v8::CppHeap` is the integration glue:

```cpp
auto cpp_heap = v8::CppHeap::Create(platform, CppHeapCreateParams{});
isolate->AttachCppHeap(cpp_heap.get());
// Now major V8 GCs walk the C++ heap; one mark phase covers both.
```

This is the synergy that would in principle pay off for DunJS — IF
we could route D allocations through it. §4 covers why we can't.

### 2.3 JavaScriptCore's heap

JSC's heap is generational, non-compacting, mostly-concurrent. The
**public C API is intentionally minimal** ([WebKit blog](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/)):

| C API | Purpose |
|-------|---------|
| `JSValueProtect(ctx, val)` | Keep alive across GC |
| `JSValueUnprotect(ctx, val)` | Allow collection |
| `JSGarbageCollect(ctx)` | GC hint |

`JSC::Heap::allocate` is internal WebKit C++ — not exposed via the C
API. Bridging would mean linking against unstable WebKit headers, on
a per-point-release treadmill. **Reject up front**.

### 2.4 Where DunJS actually allocates D memory today

Surveyed via the hot paths plus `--DRT-gcopt=profile:1`:

| Site | Frequency | Cost | GC pressure |
|------|-----------|------|-------------|
| `extractString` (JS → D string) | per-FFI | small | medium (per-call alloc) |
| `Appender!(char[])` for HTTP / JSON / TS strip | per-request | small | small (reused) |
| `new ubyte[N]` for `Buffer.from(arrayBuffer)` | per-Buffer | medium | medium |
| Worker thread state | per-Worker | one-shot | none |
| TypeScript transpile cache | per-file (cached) | one-shot | one-shot |

Measured on `feature_bench.js` (25 tests, dun-v8, cascadelake):

```
GC summary:  105 MB,   12 GC    4 ms, Pauses    3 ms <    0 ms
```

**4 ms total GC over a 14 s run = ~0.03 % of wall time**. D GC is
not on the critical path.

## 3. D ↔ C++ FFI patterns (validated end-to-end)

Single capability table — supersedes earlier drafts that had this
in §2.4½ + §10.4 + §11.5.

| Pattern | D mechanism | DunJS evidence |
|---------|-------------|----------------|
| `extern(C)` free function | `extern(C) int f()` | 1000+ symbols across the v8shim, OpenSSL bindings, libc bindings |
| `extern(C++)` free function | `extern(C++) int f()` | `cpp_add`, `cpp_mul` in `test_ffi_linkage.d` case 2 |
| Namespaced free function | `extern(C++, "ns")` | `v8::platform::NewDefaultPlatform` |
| Static method on class | `extern(C++, "ns") extern(C++, class) struct T { static: ... }` | `v8::V8::Initialize`; **`v8shim::Diagnostics::*` validated end-to-end this branch** |
| **C++ template instantiation** | **`extern(C++, "ns") { extern(C++, class) struct T(int Slot) { static: ... } alias T0 = T!0; }`** — D auto-mangles to `_ZN<ns><T>IL<arg>EE<method>Ev` | **`v8shim::TypedCounter<Slot>` (this branch, §3.2)** |
| C++ template (fallback) | `pragma(mangle, "<full itanium>")` — when D's TMP can't express the signature | `test_ffi_linkage.d` case 7b |
| C++ instance method (non-virtual) | `extern(C++, class) struct T { void f(); }` | Theoretical; ABI works for value types |
| C++ instance method (virtual) | `extern(C++) class T { void f(); }` | High risk — vtable layout must match exactly across upstream versions |
| Template function caller picks T | **Not possible directly** — write a C++ wrapper that does the instantiation, then bind via extern(C++) | Blocks `cppgc::MakeGarbageCollected<T>` direct bind |

### 3.1 The D ↔ C++ type-system mapping (critical for getting this right)

| C++ side | D-side binding | Rationale |
|----------|---------------|-----------|
| `class T { ... };` (no virtual methods) | `extern(C++, class) struct T { ... }` | **C++ class is value-type by default; D struct is value-type → match.** Using D class (reference type) silently mismatches the ABI |
| `struct T { ... };` | `extern(C++, class) struct T { ... }` | Same |
| `class T { virtual void f(); };` | `extern(C++) class T { void f(); }` | Reference type WITH vtable; D class matches — but vtable layout must be exact across C++ point releases |
| Template `T<X>` (explicitly instantiated on C++ side) | `extern(C++, class) struct T(typename X) { ... }` | D template instantiation produces matching Itanium symbol |
| Private/protected C++ members | All visible to D | D has no per-member access; module-level access only |
| C++ defaulted constructor | **Not expressible** in D struct | D structs can't have a default ctor — workaround: factory function |
| Multiple inheritance | **Hard** | Bind to a flattened C++ wrapper instead |

Pattern enforced across DunJS this branch: `extern(C++, "v8") extern(C++, class) struct V8`, `extern(C++, "v8shim") extern(C++, class) struct Diagnostics`, `JSC::SourceOrigin` — all converted from the older `extern class` (D reference type, wrong shape for static-method-only types).

### 3.2 Runtime validation (this branch)

`vendor/v8shim/v8shim.cpp` ships `v8shim::Diagnostics` + `v8shim::TypedCounter<Slot>` (with explicit instantiations for `<0>` and `<1>`). `source/dun/engine/v8/cppbindings.d` binds them via the patterns above. `source/dun/runtime/v8shim_diag.d` wires them to `globalThis.__dun_v8shim_diag__()` (V8 backend only).

End-to-end test:

```sh
$ ./dun-rel-v8 eval "
const a = __dun_v8shim_diag__();
const b = __dun_v8shim_diag__();
console.log('shimVer:', a.shimVersion);
console.log('probe:',   a.probe,        '->', b.probe);
console.log('alloc:',   a.totalAllocs,  '->', b.totalAllocs);
console.log('tmp0:',    a.tmpCounter0,  '->', b.tmpCounter0);
console.log('tmp1:',    a.tmpCounter1,  '->', b.tmpCounter1);
"
shimVer: v8shim-1.1.25         # ← C++ string constant via D extern
probe: 1 -> 2                   # ← Diagnostics::probeBumpCounter (each call hits C++)
alloc: 663 -> 670               # ← per-thread CounterCell sum across worker threads
tmp0: 1 -> 2                    # ← TypedCounter<0>::increment (independent counter)
tmp1: 1 -> 2                    # ← TypedCounter<1>::increment (independent counter)
```

Permanent regression fixture: `tests/integration/fixtures/v8shim_extern_cpp.js` (7 checks, V8-only).

Symbol-level verification (`nm`):

```
$ nm vendor/v8shim/libv8shim.a | grep TypedCounter
W _ZN6v8shim12TypedCounterILi0EE9incrementEv     # explicit instantiation <0>
W _ZN6v8shim12TypedCounterILi0EE4readEv
W _ZN6v8shim12TypedCounterILi1EE9incrementEv     # explicit instantiation <1>
W _ZN6v8shim12TypedCounterILi1EE4readEv
```

D's `TypedCounter!0.increment()` → `_ZN6v8shim12TypedCounterILi0EE9incrementEv` (matches). Verified at `-O0`, `-O3` (without `pragma(inline, false)` they're still emitted; the test file adds the pragma defensively against future LDC versions).

### 3.3 Critical gotcha — namespace scope on template instantiations

The template MUST live inside the `extern(C++, "v8shim")` block:

```d
extern(C++, "v8shim") {
    extern(C++, class) struct TypedCounter(int Slot) { ... }   // ✓ correct
}

// vs.

extern(C++, "v8shim") {
    extern class Diagnostics { ... }
}
extern(C++, class) struct TypedCounter(int Slot) { ... }       // ✗ wrong: no namespace
```

In the second form, D mangles `TypedCounter!0` as `_ZN12TypedCounter…` (no `6v8shim` namespace segment) → link error: `undefined symbol: TypedCounter<1>::increment()`. Caught during this branch's review pass; documented inline in `cppbindings.d`.

## 4. The architectural blockers (why we don't ship the bridge)

The FFI mechanism works. These don't:

### 4.1 Type-erasure vs typed-Trace mismatch

D's `GC.malloc(size, bits, ti)` is type-erased — caller gets `void*` and uses it for whatever. cppgc requires `MakeGarbageCollected<T>` where `T : GarbageCollected<T>` with a `Trace(Visitor*)` method that walks outgoing pointers. **You cannot put arbitrary D-allocated bytes inside cppgc**; you'd need a synthetic `class DOpaque : GarbageCollected<DOpaque>` wrapper with a `Trace` that calls into druntime's internal scanner. That's invasive and fragile (druntime internals aren't a public ABI).

### 4.2 Thread-affinity mismatch (the V8 showstopper)

- **cppgc heap is per-isolate** — each V8 `Isolate` gets a separate `v8::CppHeap`.
- **D's GC is process-global** — one `MyGC` instance for the entire process.

DunJS spawns one isolate per Worker. With `N` workers we'd need `N` heaps. D's `MyGC.malloc` would have to route to the right per-thread cppgc heap, with thread-locking on thread migration. This is structurally impossible without redesigning the D GC interface itself.

### 4.3 Finalization order

D class destructors run during `runFinalizers`. cppgc finalizers run during sweep on the cppgc thread. A D object whose destructor references a JSHandle owned by a cppgc-managed wrapper finalizes after the wrapper is gone → use-after-free.

### 4.4 LDC ABI churn

`interface GC` in druntime gains methods periodically (`getArrayUsed` / `expandArrayUsed` / `reserveArrayCapacity` / `shrinkArrayUsed` arrived ~druntime 2.107). A custom GC pinned to LDC 1.42's interface breaks the moment a newer LDC adds a method. Mitigation: pin LDC version + `version (DunCustomGC)` gate (which `gc_arena.d` already does).

## 5. Where DunJS actually spends time

From the per-test bench delta on v1.1.25 (dun-v8 vs Node, cascadelake):

| Test | dun-v8 ns/op | Node ns/op | Limiter |
|------|-------------:|-----------:|---------|
| Promise.resolve | 11 | 13 | engine (V8 microtask queue) |
| Object.keys/values/entries | 74 | 86 | engine |
| string replace (regex) | 125 | 166 | engine (V8 regex JIT) |
| Buffer.from string | 885 | 64 | **FFI scope overhead** |
| Buffer.concat (after v1.1.25 fused shim) | 1500-3500 | 215-300 | **FFI scope overhead** (improved 2×) |
| crypto.createHash SHA-256 | 5051 | 1183 | OpenSSL + per-call D allocation |

**The V8 backend's real bottleneck is FFI scope-entry overhead** (each `dun_v8_*` call enters `withContext<F>` — Isolate::Scope + HandleScope + Context::Scope). The fix is `v8::FastApiCallback`, **not** GC routing. Closing it via FastApi closes 5-30% per bench item.

GC-routed D allocations would not be on this list. Even a *perfect* cppgc bridge that turned D allocation free would save < 1 % of bench time.

## 6. Experimental prototype — what actually happened

`source/dun/platform/gc_arena.d` (~300 LOC, gated behind `version (DunCustomGC)`). Strategy: every D allocation goes to `core.stdc.stdlib.malloc`; `collect()` is a no-op. Leaks everything (deliberately — measurement vehicle, not production).

### 6.1 Bench data

QuickJS backend, LDC 1.42, cascadelake:

| Bench | Default conservative GC | Arena GC |
|-------|------------------------:|---------:|
| feature_bench (25 tests) | 16.6–17.0 M ops/sec | 16.6–17.1 M ops/sec |
| framework_bench (39 tests) | 13.9–13.9 M ops/sec | 13.6–13.8 M ops/sec |

GC implementation choice is **within noise**. Matches the §5 finding that GC < 1 % of bench time.

### 6.2 Bug class caught: factory-recursion (gdb-traced, TWICE in this branch's history)

First time: my initial factory used `new ArenaGC` (D's GC):

```d
GC createArenaGC() {
    __gshared instance = new ArenaGC;   // ← triggers D GC
    ...
}
```

→ ProtoGC.malloc → gc_init → createArenaGC → `new` → ProtoGC.malloc → SpinLock hang.

Fix per `core.gc.registry` docs: factory MUST C-heap-allocate.

```d
GC createArenaGC() @trusted {
    import core.stdc.stdlib : malloc;
    import core.lifetime : emplace;
    enum size = __traits(classInstanceSize, ArenaGC);
    auto raw = malloc(size);
    if (raw is null) return null;
    return emplace!ArenaGC(raw[0 .. size]);
}
```

**Second time** (caught during this branch's review audit): a thread-safety fix added `new Mutex()` to `ArenaGC.initialize()` — same recursion, same SpinLock hang. The hot loop ran 11 minutes at 99 % CPU before the audit caught it.

Stack from gdb (both occurrences look identical):

```
Thread 1:
  #0  __GI_sched_yield ()
  #1  core.internal.spinlock.SpinLock.lock() shared
  #2  gc_init ()                                    ← INNER
  #3  ProtoGC.malloc ()
  #4  createArenaGC ()                              ← OUR CODE
  #5  createGCInstance (immutable(char)[]) ()
  #6  gc_init ()                                    ← OUTER
  #7  ProtoGC.malloc ()
  #8  _sharedStaticCtor (dun.workers.shared_memory)
  #9  rt_init ()
```

**The lesson**: anything D-allocated inside the factory recurses. Including `new Mutex()`, `new Object`, `new class { ... }`, lambda captures that allocate, format strings, etc. The fix is "no D heap allocation in the factory or in any function called by the factory before the GC is established."

`gc_arena.d` documents this inline at the class body so the next implementer doesn't re-introduce it for a third time.

### 6.3 ManualGC already exists in druntime

`/opt/ldc/import/core/internal/gc/impl/manual/gc.d` ships a malloc-passthrough GC registered as `gc:manual`. Same semantics as my `gc_arena`. **For pure A/B perf measurement just use that** — no custom code required:

```sh
dun "--DRT-gcopt=gc:manual" run script.js
```

`gc_arena.d` is retained anyway because it carries the gdb-captured factory-recursion fix in its inline comment. The value is the lesson, not the GC.

### 6.4 Other bugs the prototype surfaced

- **`console.log` AssertError**: arena returns `false`/`0` from `expandArrayUsed`/`reserveArrayCapacity`. D's array invariant check fails. Production custom GC needs ~50 LOC of side-table capacity tracking to satisfy this. Skipped for the experiment.
- **`allocatedInCurrentThread` returns bytes not count**: caught by the §3-style review. Fixed.
- **Dead state**: `_roots[]` / `_ranges[]` arrays declared but never written. Deleted.

## 7. Recommendation

**Don't ship the cppgc / JSC heap bridge.** The FFI mechanism is fully expressible (§3), but §4's architectural mismatches are inherent.

**Don't ship a custom D GC as default either.** GC is < 1 % of bench time (§5). The C3-lite arena (`gc_arena.d`) is retained as a documented sketch + bug-fix archive, gated behind `version (DunCustomGC)`.

### What to ship instead, prioritized

| Option | Effort | Expected win | Why |
|--------|-------:|-------------:|-----|
| `v8::FastApiCallback` adoption in `v8shim` | Large | **5-30 % per bench item** | The actual V8 bottleneck (§5). Closes per-call FFI overhead vs Node native built-ins |
| Roll `std.experimental.allocator` (Region / BorrowedRegion / InSituRegion) into URL parser, URLSearchParams, TextEnc/Dec, HTTP request scope | Small-medium | **+3-8 % on URL/HTTP-heavy benches** | `dun.platform.arena` already re-exports the building blocks; adoption is uneven |
| `Segregator` + `FreeList` for trampoline arg-array slots | Small | ~1-2 % on FFI-heavy benches | libpas-style sized free-list for `JSHandle[]` packs |
| `--DRT-gcopt=gc:precise` ship as default | Tiny | -3 % throughput / less false retention | Trade-off, not a clear win |
| Custom region-bumper GC via `registerGCFactory` (mir-style) | Medium-large | ~2-3× on D-side allocation | Only after `std.experimental.allocator` rollout is exhausted |
| Continued JSC handle-leak fix campaign | Medium | Closes `bun_v7_additions` SKIP | Already on v1.2.x roadmap |

### How to falsify this recommendation

```sh
dun "--DRT-gcopt=profile:1" run tests/benchmarks/feature_bench.js 2>&1 | tail -10
# Look for: Grand total GC time > 100 ms on a 14 s run
# If yes → re-evaluate. Currently 4 ms (0.03 % of wall).
```

If `mark + sweep + pause` ever exceeds 10 % of wall time on a representative workload, the GC discussion reopens. Until then, the FFI / allocator paths are 10-100× higher leverage.

## 8. References

### V8 / cppgc

- [cppgc namespace reference (head)](https://v8.github.io/api/head/namespacecppgc.html)
- [`cppgc::Heap` class reference](https://v8.github.io/api/head/classcppgc_1_1Heap.html)
- [`v8::CppHeap` class reference](https://v8.github.io/api/head/classv8_1_1CppHeap.html)
- [Oilpan library blog post (V8 9.4+)](https://v8.dev/blog/oilpan-library)
- [High-performance C++ GC](https://v8.dev/blog/high-performance-cpp-gc)
- [`include/cppgc/` source](https://chromium.googlesource.com/v8/v8.git/+/HEAD/include/cppgc/)
- [Cloudflare workerd cppgc migration PR](https://github.com/cloudflare/workerd/pull/199) — real-world embedder switch

### JavaScriptCore

- [Understanding GC in JSC from scratch — WebKit blog](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/)
- [`JSValueProtect` Apple docs](https://developer.apple.com/documentation/javascriptcore/1395978-jsvalueprotect)

### D garbage collection

- [`core.gc.gcinterface` reference](https://dlang.org/library/core/gc/gcinterface.html)
- [`core.gc.registry`](https://dlang.org/phobos/core_gc_registry.html)
- [Configuring the GC (D spec)](https://dlang.org/spec/garbage.html#gc_config)
- [druntime swappable-GC PR #1581](https://github.com/dlang/druntime/pull/1581/files)

### Phobos `std.experimental.allocator`

- [Package overview](https://dlang.org/phobos/std_experimental_allocator.html)
- [`building_blocks` index](https://dlang.org/phobos/std_experimental_allocator_building_blocks.html)
- [`Region` / `BorrowedRegion` / `InSituRegion`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html)
- [`Segregator`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_segregator.html)
- [`AllocatorList`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html)

### DunJS internals (in-tree)

- `source/dun/engine/v8/cppbindings.d` — `extern(C++, "v8")` + `extern(C++, "v8shim")` patterns
- `source/dun/runtime/v8shim_diag.d` — `globalThis.__dun_v8shim_diag__()` wiring
- `source/dun/platform/gc_arena.d` — experimental arena GC + factory-recursion comment
- `vendor/v8shim/v8shim.cpp` — `v8shim::Diagnostics` + `v8shim::TypedCounter<Slot>` C++ side
- `tools/bindgen_tests/test_ffi_linkage.d` — extern(C) / extern(C++) / extern(C++, ns) / `pragma(mangle)` symbol-mangling reference (cases 1-7)
- `tests/integration/fixtures/v8shim_extern_cpp.js` — end-to-end FFI smoke test
- `.claude/commands/debug-native-callback.md` — the gdb workflow that caught the factory recursion (both times)
- `CLAUDE.md` "D Runtime GC Tuning" — current profile data
