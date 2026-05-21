# Custom D GC backed by V8 cppgc / JSC Heap — case study

**Status**: Research only. No prototype landed in-tree.

**Audience**: maintainers considering whether to prototype a custom
D GC that delegates allocation to the embedded JS engine's heap.

## TL;DR

| Question | Answer |
|----------|--------|
| Can D bind to V8 cppgc / JSC heap C++ APIs directly (no extern(C) shim)? | **Yes** — patterns documented in §3 and tested in `tools/bindgen_tests/test_ffi_linkage.d` |
| Should we route D allocations through cppgc / JSC heap? | **No** — see §4. Thread-affinity (cppgc heap is per-isolate; D GC is process-global) and the typed-Trace contract (cppgc requires `Trace(Visitor*)` per object; D allocates type-erased `void*`) are inherent to those designs, not FFI limitations |
| Is D-side GC even the bottleneck in DunJS today? | **No** — GC is < 1 % of CPU on `feature_bench.js` (§5). The V8 backend bottleneck is FFI scope overhead, addressed by `v8::FastApiCallback` — orthogonal to GC routing |
| What about a faster D-side allocator (no engine involvement)? | **Yes, ship-worthy**. `std.experimental.allocator` Region/BorrowedRegion + `--DRT-gcopt=gc:precise` are practical. Expected +3–8 % on URL/HTTP-heavy benches. See §6 |

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

Registration pattern:

```d
import core.gc.gcinterface, core.gc.registry;

extern (C) pragma(crt_constructor) void registerMyGC() {
    registerGCFactory("mygc", &createMyGC);
}

GC createMyGC() {
    /* MUST NOT use D's `new` here — see §6 */
    return /* malloc + emplace */;
}
```

`crt_constructor` runs before `rt_init` (before druntime initializes
the GC). The user opts in with `dun "--DRT-gcopt=gc:mygc" run script.js`.
The full passthrough-GC body is left as an exercise — druntime
already ships an equivalent at
`core.internal.gc.impl.manual.gc.ManualGC` (registered as
`gc:manual`), so the simplest experiment is just:

```sh
dun "--DRT-gcopt=gc:manual" run script.js
```

…and compare profile output. No custom-GC implementation needed for
the A/B perf measurement.

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

## 3. D ↔ C++ FFI patterns (would-be cppgc bridge)

Single capability table for binding C++ types from D. None of these
patterns are blocked by language design — the cppgc bridge is killed
by §4's architectural mismatches, not the FFI mechanism.

| Pattern | D mechanism | DunJS evidence in-tree |
|---------|-------------|----------------|
| `extern(C)` free function | `extern(C) int f()` | 1000+ symbols across v8shim, OpenSSL bindings |
| `extern(C++)` free function | `extern(C++) int f()` | `cpp_add`, `cpp_mul` in `test_ffi_linkage.d` case 2 |
| Namespaced free function | `extern(C++, "ns")` | `v8::platform::NewDefaultPlatform` |
| Static method on class | `extern(C++, "ns") extern(C++, class) struct T { static: ... }` | `v8::V8::Initialize` |
| **C++ template instantiation** | **`extern(C++, "ns") { extern(C++, class) struct T(int Slot) { static: ... } alias T0 = T!0; }`** — D auto-mangles to `_ZN<ns><T>IL<arg>EE<method>Ev` | `test_ffi_linkage.d` case 7a (compile-only mangling test) |
| C++ template (fallback) | `pragma(mangle, "<full itanium>")` — when D's TMP can't express the signature | `test_ffi_linkage.d` case 7b |
| C++ instance method (non-virtual) | `extern(C++, class) struct T { void f(); }` | Theoretical |
| C++ instance method (virtual) | `extern(C++) class T { void f(); }` | High risk — vtable layout must match exactly |
| Template function caller picks T | **Not possible directly** — write a C++ wrapper that does the instantiation, then bind via extern(C++) | Blocks `cppgc::MakeGarbageCollected<T>` direct bind |

### 3.1 D ↔ C++ type-system mapping (critical for getting this right)

| C++ side | D-side binding | Rationale |
|----------|---------------|-----------|
| `class T { ... };` (no virtual methods) | `extern(C++, class) struct T { ... }` | **C++ class is value-type by default; D struct is value-type → match.** Using D class (reference type) silently mismatches the ABI |
| `struct T { ... };` | `extern(C++, class) struct T { ... }` | Same |
| `class T { virtual void f(); };` | `extern(C++) class T { void f(); }` | Reference type WITH vtable; D class matches — but vtable layout must be exact across C++ point releases |
| Template `T<X>` (explicitly instantiated on C++ side) | `extern(C++, class) struct T(typename X) { ... }` | D template instantiation produces matching Itanium symbol |
| Private/protected C++ members | All visible to D | D has no per-member access; module-level access only |
| C++ defaulted constructor | **Not expressible** in D struct | D structs can't have a default ctor — workaround: factory function |
| Multiple inheritance | **Hard** | Bind to a flattened C++ wrapper instead |

Pattern enforced across DunJS this branch: `extern(C++, "v8") extern(C++, class) struct V8`, `extern(C++, "JSC") extern(C++, class) struct SourceOrigin` — both converted from the older `extern class` form (D reference type, wrong shape for static-method-only C++ types).

### 3.2 Namespace-scope gotcha for template instantiations

The template MUST live inside the `extern(C++, "ns")` block:

```d
extern(C++, "myns") {
    extern(C++, class) struct TypedCounter(int Slot) { ... }   // ✓ correct
}

// vs.

extern(C++, "myns") {
    extern(C++, class) struct OtherType { ... }
}
extern(C++, class) struct TypedCounter(int Slot) { ... }       // ✗ wrong: no namespace
```

In the second form, D mangles `TypedCounter!0` as `_ZN12TypedCounter…`
(no namespace segment) → link error: `undefined symbol:
TypedCounter<1>::increment()`. Easy mistake to make — caught during
this branch's review pass.

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

`interface GC` in druntime gains methods periodically (`getArrayUsed` / `expandArrayUsed` / `reserveArrayCapacity` / `shrinkArrayUsed` arrived ~druntime 2.107). A custom GC pinned to LDC 1.42's interface breaks the moment a newer LDC adds a method. Mitigation: pin LDC version + `version (DunCustomGC)` gate.

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

## 6. The factory-recursion gotcha (do this before you write any custom GC)

If you do attempt a custom GC despite §4 + §5, this is the bug class
that will eat your first day. It hit twice during this branch's
research even after the first fix landed.

**The pattern**:

```d
GC createMyGC() {
    __gshared instance = new MyGC;   // ← D's `new` triggers the GC
    ...
}
```

→ ProtoGC.malloc → gc_init → createMyGC → `new` → ProtoGC.malloc → SpinLock hang. The first allocation D's runtime needs (during `rt_init` shared-static-ctor processing) triggers `gc_init`, which calls our factory, which calls `new`, which calls back into `ProtoGC.malloc`, which calls `gc_init` again. The SpinLock detects recursion and spins forever.

Stack trace from gdb (verbatim — both occurrences look identical):

```
Thread 1:
  #0  __GI_sched_yield ()
  #1  core.internal.spinlock.SpinLock.lock() shared
  #2  gc_init ()                                    ← INNER
  #3  ProtoGC.malloc ()
  #4  createMyGC ()                                 ← YOUR CODE
  #5  createGCInstance (immutable(char)[]) ()
  #6  gc_init ()                                    ← OUTER
  #7  ProtoGC.malloc ()
  #8  _sharedStaticCtor (any module that has one)
  #9  rt_init ()
```

**The fix** per [`core.gc.registry`](https://dlang.org/phobos/core_gc_registry.html)
docs (which say "the instance was allocated on the C heap, it is
supposed to free itself upon calling its destructor"):

```d
GC createMyGC() @trusted {
    import core.stdc.stdlib : malloc;
    import core.lifetime : emplace;
    enum size = __traits(classInstanceSize, MyGC);
    auto raw = malloc(size);
    if (raw is null) return null;
    return emplace!MyGC(raw[0 .. size]);
}
```

**The lesson** — anything D-allocated inside the factory recurses.
This includes:
- `new ClassName`
- `new Mutex()` (the second occurrence in this branch — added during
  a "thread-safety" review fix; same recursion)
- Lambda captures that allocate
- Format strings (`format!"%s"`, `text(...)`)
- D arrays (`[1, 2, 3]`)

If your custom GC needs synchronization, use a pthread mutex value
(no D heap) or `core.atomic.cas` for lock-free linked-list ops.

## 7. Recommendation

**Don't ship a cppgc / JSC heap bridge.** The FFI mechanism is fully expressible (§3), but §4's architectural mismatches are inherent.

**Don't ship a custom D GC as default either.** GC is < 1 % of bench time (§5). If you want to measure the upper bound of "no GC overhead", use `--DRT-gcopt=gc:manual` (ships in druntime) instead of writing your own.

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
- [Cloudflare workerd cppgc migration PR](https://github.com/cloudflare/workerd/pull/199) — real-world embedder switch

### JavaScriptCore

- [Understanding GC in JSC from scratch — WebKit blog](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/)
- [`JSValueProtect` Apple docs](https://developer.apple.com/documentation/javascriptcore/1395978-jsvalueprotect)

### D garbage collection

- [`core.gc.gcinterface` reference](https://dlang.org/library/core/gc/gcinterface.html)
- [`core.gc.registry`](https://dlang.org/phobos/core_gc_registry.html)
- [Configuring the GC (D spec)](https://dlang.org/spec/garbage.html#gc_config)
- [druntime swappable-GC PR #1581](https://github.com/dlang/druntime/pull/1581/files)
- [`core.internal.gc.impl.manual.gc`](https://github.com/dlang/druntime/blob/master/src/core/internal/gc/impl/manual/gc.d) — already-shipped `gc:manual` reference

### Phobos `std.experimental.allocator`

- [Package overview](https://dlang.org/phobos/std_experimental_allocator.html)
- [`building_blocks` index](https://dlang.org/phobos/std_experimental_allocator_building_blocks.html)
- [`Region` / `BorrowedRegion` / `InSituRegion`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html)
- [`Segregator`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_segregator.html)
- [`AllocatorList`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html)

### DunJS internals (in-tree)

- `source/dun/engine/v8/cppbindings.d` — `extern(C++, "v8")` static-method bindings (V8 + platform)
- `source/dun/engine/jsc/cppbindings.d` — `extern(C++, "JSC")` SourceOrigin binding
- `tools/bindgen_tests/test_ffi_linkage.d` — extern(C) / extern(C++) / extern(C++, ns) / template-instantiation / `pragma(mangle)` symbol-mangling reference (cases 1-7)
- `.claude/commands/debug-native-callback.md` — gdb workflow used to capture the factory-recursion trace (§6)
- `CLAUDE.md` "D Runtime GC Tuning" — current profile data
