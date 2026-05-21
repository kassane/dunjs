# Custom D GC backed by V8 cppgc / JSC Heap — feasibility case study

**Status**: Research only. Not on the v1.x roadmap.
**Branch**: `claude/custom-gc-research` (this commit).
**Audience**: maintainers considering whether to prototype a custom
D GC inside DunJS that delegates allocation to the embedded JS
engine's GC.

This document answers four questions:

1. **What would it look like?** — The shape of a `MyGC : GC` class
   that delegates to V8's `cppgc::Heap` or JSC's `JSC::Heap`.
2. **Where would it help?** — Realistic perf model: which D
   allocations actually become free, which stay the same, which
   regress.
3. **What are the hard problems?** — Roots, finalization, threading,
   ABI compat, dual-runtime coordination.
4. **Should we ship it?** — Recommendation + suggested next step.

TL;DR up front: **don't do it for V8, possibly do it for JSC** —
but only after measuring that D-side allocation is actually on the
critical path (current data says it isn't).

---

## 1. The 30-second pitch

DunJS has two heaps in every process:

```
┌─────────────────────────────────────────┐
│  D runtime                              │
│  ┌──────────────────────────────────┐   │
│  │ druntime conservative GC (CMS)   │   │  ~16 MB initial pool
│  │ - Appender buffers               │   │  ~2-5% CPU under feature_bench
│  │ - String / array allocations     │   │
│  │ - Closures, IJSEngine instances  │   │
│  │ - DunState, EventLoop, Workers   │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
┌─────────────────────────────────────────┐
│  V8 / JSC / QuickJS-NG                  │
│  ┌──────────────────────────────────┐   │
│  │ V8 GC (Orinoco) / JSC GC (Riptide)│  │  ~few hundred MB live
│  │ - All JS objects, strings, arrays │  │  ~5-10% CPU
│  │ - DunV8Value* wrappers (via       │  │  Already optimized
│  │   thread-local value pool)        │  │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

The user's `pragma(crt_constructor)` skeleton would let us register
a `mygc` factory that, when selected via `--DRT-gcopt=gc:mygc`, makes
D's `new`/`malloc`/array-append allocate inside the JS engine's
heap. The idea: **collapse the two heaps into one**, so any
intrinsic synergy (single GC pass, shared marking, shared
write-barrier infrastructure) becomes a real perf win.

---

## 2. Background

### 2.1 D's `core.gc.gcinterface.GC`

Verified against LDC 1.42.0 (`/opt/ldc/import/core/gc/gcinterface.d`,
[upstream docs](https://dlang.org/library/core/gc/gcinterface.html)):

The `GC` interface is **32 methods**, partitioned roughly as:

| Category | Methods | Notes |
|----------|---------|-------|
| Lifecycle | `enable`, `disable`, `collect`, `minimize` | Map to `cppgc::Heap::ForceGarbageCollectionSlow` / `JSC::Heap::collectAllGarbage` |
| Allocation | `malloc`, `qalloc`, `calloc`, `realloc`, `extend`, `reserve`, `free` | Hot path. Returns raw pointer + `BlkAttr` bits |
| Block metadata | `getAttr`/`setAttr`/`clrAttr`, `addrOf`, `sizeOf`, `query` | Lets D's runtime recover type info from a pointer mid-collection |
| Stats | `stats`, `profileStats` | Reported by `--DRT-gcopt=profile:1` |
| Root tracking | `addRoot`/`removeRoot`/`rootIter`, `addRange`/`removeRange`/`rangeIter` | The bit that's hardest to bridge — D's roots are NOT V8/JSC roots and vice versa |
| Finalization | `runFinalizers`, `inFinalizer` | Class destructors run here |
| Thread hooks | `initThread`, `cleanupThread`, plus the registry-level `GCThreadInitFunction` | Per-thread state setup |
| Arrays | `getArrayUsed`, `expandArrayUsed`, `reserveArrayCapacity`, `shrinkArrayUsed` | Druntime's `~=` operator hits these; expensive paths use `expandArrayUsed` |
| Self-stats | `allocatedInCurrentThread` | Per-thread allocation counter |

druntime ships two stock implementations:
- **Conservative** (default) — mark-sweep, scans entire reachable memory looking for pointer-shaped values. Type info ignored.
- **Precise** — uses `TypeInfo` bitmaps to scan only pointer-typed fields. Slower allocation, less false retention.

The user's `MyGC` skeleton:

```d
import core.gc.gcinterface, core.gc.registry;

extern (C) pragma(crt_constructor) void registerMyGC() {
    registerGCFactory("mygc", &createMyGC);
}

GC createMyGC() {
    __gshared instance = new MyGC;
    instance.initialize();
    return instance;
}

class MyGC : GC { /* 32 method overrides */ }
```

`pragma(crt_constructor)` ensures `registerMyGC` runs **before**
druntime initialization, so by the time `rt_init` looks at
`--DRT-gcopt=gc:mygc` the factory is in the registry. User opts in
with `dun "--DRT-gcopt=gc:mygc" run script.js`.

### 2.2 V8's cppgc (Oilpan)

V8 ships [cppgc](https://v8.github.io/api/head/namespacecppgc.html)
as a standalone embedder library that the JavaScript engine uses
internally for Blink/DOM nodes ([Oilpan library blog post](https://v8.dev/blog/oilpan-library)).
The API surface:

```cpp
namespace cppgc {
    void InitializeProcess(PageAllocator* page_allocator = nullptr);
    void ShutdownProcess();

    class Heap {
        static std::unique_ptr<Heap> Create(
            std::shared_ptr<Platform> platform,
            HeapOptions options = HeapOptions::Default());
        AllocationHandle& GetAllocationHandle();
        void ForceGarbageCollectionSlow(...);
    };

    template <typename T, typename... Args>
    T* MakeGarbageCollected(AllocationHandle& h, Args&&... args);

    template <typename T> class Persistent { ... };  // strong cross-heap ref
    template <typename T> class WeakPersistent { ... };
    template <typename T> class Member { ... };       // intra-heap field
    template <typename T> class WeakMember { ... };
}
```

Two critical constraints:

1. **`MakeGarbageCollected<T>` requires `T : GarbageCollected<T>`** —
   the object must have a vtable header that cppgc recognizes,
   and a `Trace(Visitor*) const` method that walks outgoing
   pointers. **You cannot point cppgc at arbitrary `void*` blobs.**
2. **Pointer hygiene** — every cross-object pointer inside a
   managed object must be a `Member<T>`. Bare `T*` won't be
   scanned and will dangle. Off-heap → on-heap pointers must be
   `Persistent<T>`.

For DunJS this means we can't just say "give me 64 bytes" and use
the result as a `string[]`. We'd need to wrap every D allocation
in a synthetic `GarbageCollected<T>` shell with a `Trace` that
makes cppgc aware of the D-side internal pointers. **D's GC
interface is type-erased** (you get a `void*`, you cast it to
whatever); cppgc's API is **type-driven** (you get a `T*` of a
specific traced type).

That mismatch is the fundamental friction. Workarounds exist (a
single `class DOpaque : GarbageCollected<DOpaque>` with a raw
byte buffer plus a `Trace` that calls into druntime's
`rt.lifetime` machinery) but the layering inversion makes the GC
contract hard to honor.

### 2.3 V8's `v8::CppHeap` — the integration point

`CppHeap` is the bridge that makes a `cppgc::Heap` collaborate
with the V8 JS heap ([`v8::CppHeap`](https://v8.github.io/api/head/classv8_1_1CppHeap.html)):

```cpp
auto cpp_heap = v8::CppHeap::Create(platform, CppHeapCreateParams{});
isolate->AttachCppHeap(cpp_heap.get());
// Now major V8 GCs walk the C++ heap too; one mark phase covers both.
```

This is what Blink uses — Blink DOM nodes are `cppgc`-managed,
JS wrappers point at them via embedder slots, and a single
mark cycle walks both heaps. **This is the synergy that could
actually help DunJS** if we managed to route D allocations
through cppgc.

### 2.4 JavaScriptCore's heap

JSC's heap ([WebKit blog](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/))
is a generational, non-compacting, mostly-concurrent mark-sweep
collector. The **public C API exposed to embedders is
intentionally minimal**:

| C API | Purpose |
|-------|---------|
| `JSValueProtect(ctx, val)` | Keep a JSValueRef alive across GC |
| `JSValueUnprotect(ctx, val)` | Allow collection |
| `JSGarbageCollect(ctx)` | Hint a GC cycle |

That's it. JSC's `Heap` class (the actual allocator interface) is
**not part of the C API** — `Heap::allocate`, `WeakSet`, `Strong<T>`
are all internal to WebKit's C++ source. Using them requires either:

- linking against the C++ library + an unstable header set, or
- writing a custom shim that exposes them via `extern "C"` (like
  DunJS does for V8 in `vendor/v8shim/`).

So for the JSC route, we'd need a `vendor/jscshim/` library
analogous to v8shim.

### 2.5 Where DunJS allocates D memory today

Surveyed via `grep -rn "new " source/dun/ | wc -l` and pattern-spotted
the hot paths:

| Allocation site | Frequency | Cost | GC pressure |
|-----------------|-----------|------|-------------|
| `engine.eval(...)` source string `idup` | per-eval | small | small (already cached for fetch) |
| `extractString(...)` (JS→D string) | per-FFI | small-medium | medium (per-call alloc) |
| `Appender!(char[])` for HTTP / JSON / TS strip | per-request | small | small (Appender reuses) |
| `new ubyte[N]` for `Buffer.from(arrayBuffer)` | per-Buffer-from | medium | medium |
| `JSHandle[]` arrays for trampoline arg packs | per-callback | small (stack-allocated in v8shim) | none |
| Worker thread state | per-Worker creation | one-shot | none |
| Permission scope arrays | one-shot at startup | one-shot | none |
| TypeScript transpile cache | per-file (cached) | one-shot per file | one-shot |
| EventLoop microtask queue | per-tick burst | small | small |

The aggregate D-side allocation rate on `feature_bench.js` is
**~2-5% of CPU** per `--DRT-gcopt=profile:1` runs. Most allocation
is short-lived and the conservative GC's bump allocator handles
it cheaply. **D-side allocation is NOT on the critical path for
DunJS's current bottlenecks** (which are FFI scope overhead and
V8 inline-cache misses on indirect calls).

---

## 3. Three possible designs

### Design A — Naive: delegate every D `malloc` to `cppgc`

```d
class MyGC : GC {
    void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow {
        // Calls into v8shim
        return dun_v8_cppgc_alloc(_cpp_heap, size, ti);
    }
    void free(void* p) nothrow @nogc { /* no-op — GC reclaims */ }
    void collect() nothrow { dun_v8_cppgc_force_gc(_cpp_heap); }
    // ... 29 more methods
}
```

```cpp
// vendor/v8shim/v8shim.cpp additions
class DOpaqueBlock : public cppgc::GarbageCollected<DOpaqueBlock> {
public:
    DOpaqueBlock(size_t size) : size_(size), data_(new uint8_t[size]) {}
    void Trace(cppgc::Visitor* v) const {
        // Conservative: scan data_ for pointer-shaped words
        // and report each as a possible Member<DOpaqueBlock>.
        // This is what druntime's conservative GC already does.
    }
    uint8_t* data() { return data_.get(); }
private:
    size_t size_;
    std::unique_ptr<uint8_t[]> data_;
};

void* dun_v8_cppgc_alloc(v8::CppHeap* h, size_t size, ...) {
    auto& ah = h->GetHeapHandle();
    auto* block = cppgc::MakeGarbageCollected<DOpaqueBlock>(ah, size);
    return block->data();
}
```

**Problems**:
- **Stat invariants broken**: druntime tracks `BlkInfo` per allocation (base address, size, attrs). cppgc returns an opaque managed object, not a `BlkInfo`. We'd need a side-table `void* → BlkInfo`.
- **Conservative scan inside Trace**: cppgc expects you to walk outgoing pointers explicitly via `visitor->Trace(member)`. A "scan this byte range conservatively" mode exists (`v8::EmbedderRootsHandler::ResetRoot`) but isn't an `AllocationHandle` operation. Conservative scanning inside a `Trace` method is **not supported** — cppgc will treat your `DOpaqueBlock` as opaque and miss pointers into other GC blocks.
- **Allocation rate**: cppgc's `MakeGarbageCollected` includes a header (16-32 bytes) per object. D allocates **lots** of small objects (Appender chunks, closure environments, etc.). Per-allocation overhead would dominate.
- **Thread model mismatch**: cppgc heaps are **isolate-affinity** — calls must come from the thread that owns the isolate. D code allocates from many threads (Worker threads, async pool). Crossing isolates requires `Locker` + scope entry.

**Verdict**: Doesn't work. The mismatch between D's "give me bytes,
I'll handle types" model and cppgc's "I track typed objects with
Trace methods" model is fundamental.

### Design B — Hybrid: cppgc for D objects that point at JS values

```d
class MyGC : GC {
    void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow {
        // Default path: druntime conservative
        if (!(bits & BlkAttr.HAS_JS_REFS))
            return _fallback.malloc(size, bits, ti);
        // Special path: cppgc-allocated, traced for JS refs
        return dun_v8_cppgc_alloc(_cpp_heap, size, ti);
    }
}
```

The premise: only D objects that **hold JSHandles** need cppgc.
Everything else stays in druntime's conservative GC.

**Problems**:
- **`BlkAttr.HAS_JS_REFS` doesn't exist** — we'd need to add a new
  attribute and teach every allocation site to set it. Could be a
  type-info trait (`__traits(hasJSHandle, T)`) at the call site.
- **Cross-heap roots still needed**: a D-heap object pointing at a
  cppgc object still needs `Persistent<T>`. Same problem, smaller
  scope.
- **Marginal benefit**: the objects that hold JSHandles are
  basically `DunState`, builtin module state, and Workers — a
  handful of per-process / per-Worker singletons. Moving these to
  cppgc saves ~0 µs.

**Verdict**: Engineering cost is high for ~no measurable win.

### Design C — Replace druntime CMS with a faster D-side allocator (no engine involvement)

Instead of bridging to the JS engine, write a faster D-side
allocator that targets DunJS's specific allocation patterns. This
is the **only** of the three designs with a clear path to
measurable wins. Three sub-options, in increasing order of
engineering cost:

#### C1 — `std.experimental.allocator` building-blocks (already in DunJS)

DunJS already has `source/dun/platform/arena.d`:

```d
public import std.experimental.allocator.building_blocks.region :
    Region, BorrowedRegion, InSituRegion;
public import std.experimental.allocator.mallocator : Mallocator;
public import std.array : Appender;

alias BumpRegion = Region!Mallocator;
```

Phobos's `std.experimental.allocator` ([reference](https://dlang.org/phobos/std_experimental_allocator.html))
is a composable allocator framework — pick the building blocks
that match your lifetime pattern:

| Block | Use case |
|-------|----------|
| `Mallocator` ([docs](https://dlang.org/phobos/std_experimental_allocator_mallocator.html)) | Wraps `core.stdc.stdlib.malloc/free`. No GC, no scanning. Use for raw byte buffers that outlive the request scope |
| `Region!Mallocator` (== `BumpRegion`) ([docs](https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html)) | Bump-pointer arena. Pre-allocate `N` MB; alloc returns next slot; **dispose all at once** at request end. The fastest allocator that exists for short-lived data |
| `BorrowedRegion` (no owning) | Bump arena that points at memory you own elsewhere (e.g. stack `ubyte[16384]`). Doesn't free on destruction |
| `InSituRegion!(N)` | Region whose backing storage is a struct field of size N — entirely stack-allocated for `N` ≤ a few KiB |
| `FallbackAllocator!(Primary, Secondary)` ([docs](https://dlang.org/phobos/std_experimental_allocator_building_blocks_fallback_allocator.html)) | Try fast primary, fall back to secondary on OOM. Pattern: `FallbackAllocator!(InSituRegion!8192, Mallocator)` |
| `Segregator!(threshold, Small, Large)` ([docs](https://dlang.org/phobos/std_experimental_allocator_building_blocks_segregator.html)) | Route small allocs to one allocator, large to another. Pattern: small → bump region, large → Mallocator |
| `AllocatorList!(factory)` ([docs](https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html)) | Scalable list of regions; each gets `≥ 1 MB` at a time |
| `FreeList!(parent, sizeOrRange)` | Returns objects of a specific size to a free list on `deallocate`. Combine with `AllocatorList` for libpas-style sized buckets |

`dun.platform.arena` re-exports the building blocks DunJS uses
today (`Region`, `BorrowedRegion`, `InSituRegion`, `Mallocator`).
The current adoption is **uneven**: some hot paths in
`source/dun/builtins/{fetch,http,ts/strip}.d` already use
`makeAppender(reserve)` + `Region`, but most builtins still hit
the GC.

**Where to apply for measurable wins** (looking at the bench
delta data from §5.1):

- **HTTP request parsing** — `req.headers`, `req.body`, the per-request URL/query parse: route through a per-request `Region` that resets at response close. Same pattern Bun uses.
- **URL parser** (`new URL()` is 1282ns dun-v8 vs 429ns node, 853ns lag) — the host/path/query split currently `idup`s into the GC. Move to `BorrowedRegion` over the original input bytes.
- **URLSearchParams** — same.
- **TextEncoder/Decoder** — currently goes through `engine.newString`; the intermediate UTF-8 buffer can be `InSituRegion` for messages ≤ 8 KB.
- **TS-stripper tokenization** — `dun.ts.parser.lexer` already takes a slice over the input; the type-erasure output buffer would benefit from a `Region` sized to `input.length`.

Expected aggregate impact: **+3-8% on URL-heavy benches**, ~0%
on benches that don't allocate D-side (Promise, Object.keys).

#### C2 — LDC's precise GC (`--DRT-gcopt=gc:precise`)

druntime ships a precise GC that uses TypeInfo pointer bitmaps
instead of conservative scanning ([PR #2418](https://github.com/dlang/druntime/pull/2418)).
**Zero engineering cost** — just set the runtime flag. Per the
CLAUDE.md GC tuning table:

| Config | dun-jsc M ops/sec | GCs |
|--------|------------------:|----:|
| Default | 513 | 6-25 |
| `gc:precise` | 497 | 6-23 |

So today: ~3% regression on bench throughput, comparable GC count.
The win is **reduced false retention** (no spurious pointer
matches in stack-allocated integers) — relevant for memory
footprint and long-running servers, NOT throughput.

#### C3 — Custom region-bumper GC behind `registerGCFactory`

The user's `crt_constructor` skeleton, but pointing at a D-side
implementation rather than cppgc. Implement the 32-method `GC`
interface on top of a `Region`-of-`Region`s (AllocatorList style).
This is what mir's runtime allocator does. Engineering cost is
~1-2 weeks but the resulting allocator can be ~2-3× faster than
druntime's conservative GC on bench-style allocation patterns
(many small short-lived blocks).

**Verdict on Design C**: **C1 is the highest-leverage**, lowest-risk
direction. C2 is one flag away — just measure and decide. C3 is
the "next step" if C1 + C2 aren't enough. **None of these
involves V8 or JSC**, which is exactly what makes them
practical.

---

## 4. Hard problems

### 4.1 Cross-heap roots

D's GC roots:
- `__gshared` and TLS variables
- C stack of every D thread (conservative)
- Pinned via `GC.addRoot(p)` / `GC.addRange(p, len)`

cppgc's roots:
- `Persistent<T>` objects (live anywhere off-heap)
- `EmbedderRootsHandler` callback

If a D object holds a `Persistent<cppgc::Heap object>`, cppgc keeps
the target alive. Fine. But if a cppgc object holds a raw `void*`
that points back into the D heap, **cppgc won't scan that pointer
during its mark phase** unless the cppgc object's `Trace` calls
into druntime's machinery via a custom `EmbedderRootsHandler`.

The handler shape:

```cpp
class DRuntimeRootsHandler : public v8::EmbedderRootsHandler {
public:
    void ResetRoot(const v8::TracedReference<v8::Value>& handle) override {
        // Called when V8 wants to drop a wrapper.
        // We'd need to ask druntime: is this still rooted in D?
    }
    bool TryResetRoot(...) override { ... }
};
```

This is solvable but requires writing the D-side `is this rooted?`
query, which is **not part of the public `core.gc.gcinterface.GC`
contract**. We'd need to escape into `core.memory.GC.addrOf` and
the conservative scanner's internal state — fragile across LDC
versions.

### 4.2 Finalization order

D class destructors run during `runFinalizers`. cppgc finalizers
run during its sweep phase, on the cppgc thread. **The orderings
don't compose.** A D object whose destructor references a
JSHandle owned by a cppgc'd wrapper can finalize after the
wrapper is gone → use-after-free.

Workaround: register cppgc PreFinalizer callbacks that move D
references out before cppgc reclaims. Complex.

### 4.3 Threading

DunJS spawns one V8 `Isolate` per main process (single isolate),
but each Worker has its own engine instance and its own isolate.
cppgc heaps are 1:1 with isolates (`v8::CppHeap` attaches to a
specific isolate). So we'd need **N heaps for N workers**.

D's GC is process-global. There's one `MyGC` instance for the
entire process. The implementation would need to route every
`malloc` to the right per-thread cppgc heap — which means
`thread_local` state and locking when threads migrate.

**This is the showstopper for V8.** D's process-global GC model
fundamentally mismatches V8's per-isolate cppgc model. Workers
make it intractable.

### 4.4 LDC ABI compat

The `interface GC` definition lives in druntime, which LDC pins
to a specific commit per release. The interface gained
`getArrayUsed` / `expandArrayUsed` / `reserveArrayCapacity` /
`shrinkArrayUsed` somewhere around druntime 2.107+. If we ship
a custom GC that implements the LDC 1.42 interface, then a future
LDC version adds a method, our class no longer satisfies the
interface and the build breaks.

Mitigation: pin LDC version, mark in `dub.json`, and gate the
custom GC behind a `version (DunCustomGC)` block so the default
build still works on any LDC.

### 4.5 The `--DRT-gcopt=gc:mygc` selection happens after dlopen

`pragma(crt_constructor)` runs **before** `main`, but it runs
**after** the binary's dynamic libraries have been loaded.
V8 (statically linked into DunJS, but with its own static C++
initializers) initializes its global allocator state before
our `crt_constructor` runs. By the time `registerMyGC` is called,
the cppgc process state is **already set up** with the default
PageAllocator. We can still create heaps after this point, but
the initial `cppgc::InitializeProcess(custom_allocator)` window
has closed.

For DunJS this is fine (we don't need a custom PageAllocator), but
it constrains designs that wanted to share an allocator between
D and cppgc.

---

## 5. Perf model

What would actually get faster?

### 5.1 Hot paths today

From the v1.1.25 bench grid on cascadelake (LDC 1.42 / V8 15.0.112):

| Bench | dun-v8 ns/op | Node ns/op | Limiter |
|-------|-------------:|-----------:|---------|
| Promise.resolve | 11 | 13 | engine-bound (V8 microtask queue) |
| Object.keys/values/entries | 74 | 86 | engine-bound |
| string replace (regex) | 125 | 166 | engine-bound (V8 regex JIT) |
| Buffer.from string | 885 | 64 | **FFI scope overhead** |
| Buffer.concat | 1500-3500 | 215-300 | **FFI scope overhead** (improved 2× in v1.1.25 via fused shim) |
| crypto.createHash SHA-256 | 5051 | 1183 | OpenSSL via D, but native digest cost similar to Node — **D-side allocation per call** in update/digest paths |
| URLSearchParams | 587 | 179 | **D-side parser allocation** |
| new URL() | 1282 | 429 | **D-side parser + setProperty calls** |

The places where D-side allocation IS on the critical path are
URL parsing, crypto.createHash, TextEncoder/Decoder, and HTTP
request parsing. Those allocations are small (`Appender!(char[])`
typically), in the **10-100 byte range per allocation**, and
**already cheap** via druntime's bump allocator.

### 5.2 Where a cppgc-backed GC would help

If routed through cppgc:

| Allocation pattern | cppgc cost | Druntime cost | Win? |
|--------------------|-----------:|--------------:|------|
| Small short-lived (`Appender` chunks) | High (header overhead, GarbageCollected base class) | Low (free bump) | **Regression** |
| Long-lived (DunState, builtin module state) | Medium (one-shot) | Low | Negligible |
| Holding JSHandles, needing root tracking | Medium with `Persistent<T>` | High (GC.addRoot per slot) | **Win, maybe ~5%** in worker-heavy workloads |
| Mass deallocation (cache invalidation) | High (full GC cycle to free) | Low (free explicitly) | **Regression** |
| Cross-thread allocations | Locking | Locking | Even |

**Expected aggregate impact**: -5% to +5% on feature_bench. **Not
worth the engineering cost.**

### 5.3 Where a cppgc-backed GC would NOT help

Looking at the actual bottlenecks measured above:

- **FFI scope overhead** (per-call `withContext<F>` setup at ~300ns) — fixed by `v8::FastApiCallback` adoption, NOT GC routing.
- **V8 inline-cache misses on object allocation/property set** — fixed by JS-side patterns, NOT D-side allocation.
- **Buffer.concat per-element loop** — fixed by `dun_v8_buffer_concat` in v1.1.25 (PR #62).
- **HTTP per-request handle protect-count growth on JSC** — needs the v1.2.x worker-lifecycle pass, NOT a custom GC.

None of DunJS's actual perf bottlenecks are GC-bound on the D
side. **The premise that custom GC routing is the next perf win
is incorrect** — it's about ~10-20× lower priority than fixing
the FastApi gap.

---

## 6. Implementation sketch (if we were to do it anyway)

Just enough to make the scope concrete. **Do not implement this
without first running `--DRT-gcopt=profile:1` and confirming GC is
≥ 10% of CPU**, which it currently isn't.

### 6.1 D side

```d
// source/dun/platform/gc_cppgc.d
module dun.platform.gc_cppgc;

import core.gc.gcinterface;
import core.gc.registry;
import core.memory : GC = core.memory.GC;  // disambiguate
import core.thread.threadbase : ThreadBase;
import core.stdc.string : memset;

// extern(C) into vendor/v8shim/cppgc_bridge.cpp
extern (C) {
    void* dun_cppgc_init();             // returns opaque heap handle
    void  dun_cppgc_shutdown(void*);
    void* dun_cppgc_alloc(void* heap, size_t size, uint bits);
    void  dun_cppgc_free(void* heap, void* p);   // hint only
    void  dun_cppgc_collect(void* heap);
    size_t dun_cppgc_size_of(void* heap, void* p);
}

extern (C) pragma(crt_constructor) void registerMyGC() {
    registerGCFactory("cppgc", &createCppGC);
}

GC createCppGC() nothrow {
    import core.stdc.stdio : fprintf, stderr;
    try {
        __gshared instance = new CppGCBackend;
        instance.initialize();
        return instance;
    } catch (Exception e) {
        fprintf(stderr, "cppgc backend init failed: %.*s\n",
            cast(int) e.msg.length, e.msg.ptr);
        return null;
    }
}

class CppGCBackend : GC {
    private void* _heap;
    private GC _fallback;  // druntime conservative for unsupported paths

    void initialize() {
        _heap = dun_cppgc_init();
        // We can't easily get a reference to druntime's conservative GC
        // from here — `core.gc.registry` doesn't expose it. Practical
        // mitigation: implement everything ourselves OR build druntime
        // with the conservative GC as a separate exported symbol.
    }

    void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow {
        return dun_cppgc_alloc(_heap, size, bits);
    }

    void free(void* p) nothrow @nogc {
        // cppgc doesn't have a manual free — this is a no-op hint.
    }

    void collect() nothrow {
        dun_cppgc_collect(_heap);
    }

    // ... 29 more methods stubbing out the rest
}
```

### 6.2 C++ side

```cpp
// vendor/v8shim/cppgc_bridge.cpp
#include <cppgc/heap.h>
#include <cppgc/garbage-collected.h>
#include <cppgc/allocation.h>

namespace {
class DAllocBlock : public cppgc::GarbageCollected<DAllocBlock> {
public:
    DAllocBlock(size_t size) : data_(::operator new(size)), size_(size) {
        memset(data_, 0, size);
    }
    ~DAllocBlock() { ::operator delete(data_); }
    void Trace(cppgc::Visitor*) const {
        // CONSERVATIVE SCAN NOT SUPPORTED — would need druntime hook
    }
    void* data() { return data_; }
private:
    void* data_;
    size_t size_;
};
}  // namespace

extern "C" {
    void* dun_cppgc_init() {
        // Caller must have called cppgc::InitializeProcess() — V8 does it
        // for us when the isolate is created.
        // ... return new heap
    }
    void* dun_cppgc_alloc(void* heap_opaque, size_t size, uint32_t bits) {
        auto* heap = static_cast<cppgc::Heap*>(heap_opaque);
        auto& ah = heap->GetAllocationHandle();
        auto* block = cppgc::MakeGarbageCollected<DAllocBlock>(ah, size);
        return block->data();
    }
}
```

### 6.3 Wire-up

`dub.json`:

```json
"sourceFiles-cppgc": [
    "vendor/v8shim/cppgc_bridge.cpp"
],
"versions": ["DunCustomGC"]
```

Compile-only by default. User opts in via:

```sh
dun "--DRT-gcopt=gc:cppgc" run script.js
```

If they don't pass that flag, druntime falls back to its built-in
conservative GC and the `cppgc_bridge` is just dead code in the
binary.

### 6.4 Debug & profile

How you'd verify (or falsify) this is worth shipping:

```sh
# Baseline: druntime conservative GC
dun "--DRT-gcopt=profile:1" run tests/benchmarks/feature_bench.js 2>&1 | tail -20

# Custom: cppgc-backed
dun "--DRT-gcopt=gc:cppgc profile:1" run tests/benchmarks/feature_bench.js 2>&1 | tail -20
```

Both runs print:

```
Number of collections:  N
Total GC prep time:     X ms
Total mark time:        Y ms
Total sweep time:       Z ms
Total page release:     W ms
Max Pause Time:         P ms
Total Pause Time:       Q ms
```

Acceptance criteria for landing: **mark + sweep + pause time
drops by ≥ 20% AND total throughput in feature_bench /
framework_bench improves by ≥ 5%** (the latter being the
externally-visible metric).

Use the new `-b fuzzer` + ASan (v1.1.25) to verify
no use-after-free across the D ↔ cppgc boundary. The CVE-class
risk is HIGH here — finalization order bugs in the bridge are
exactly the kind of memory corruption ASan catches at runtime.

---

## 7. Recommendation

**Don't ship this. Specifically:**

1. **V8 / cppgc route** — Reject. The thread-affinity (one
   cppgc heap per isolate, but D's GC is process-global) and the
   conservative-scan-vs-typed-Trace mismatch make this an
   intractable bridge. Even if we built it, the perf win is
   in the noise (D-side allocation is ~2-5% of CPU on the
   current bench, and most of that is unavoidable string FFI).

2. **JSC route** — Reject for the same architectural reasons
   plus an additional one: JSC's heap C API is `JSValueProtect`/
   `Unprotect` only. The actual allocator (`JSC::Heap::allocate`)
   isn't exposed and would require an unstable WebKit
   internal-header build. We'd be on a private API treadmill.

3. **The user's `crt_constructor` skeleton itself** — Confirmed
   working. We can ship a CHANGELOG note that
   `registerGCFactory` is available and lay out the **interface
   shape** (the 32-method `GC` contract documented above) so a
   future maintainer with a concrete need can implement it.

**What we WOULD ship if perf was the real ask**:

| Option | Effort | Expected win | Why |
|--------|-------:|-------------:|-----|
| `v8::FastApiCallback` adoption in v8shim | Large | **5-30% per bench item** | The actual bottleneck. Closes the per-call FFI overhead gap to Node. |
| Roll `std.experimental.allocator` (Region/BorrowedRegion/InSituRegion) into the URL parser, URLSearchParams, TextEnc/Dec, HTTP request | Small-medium | **+3-8% on URL/HTTP-heavy benches** | `dun.platform.arena` already re-exports the building blocks; current adoption is uneven. See Design C1 in §3 |
| `Segregator` + `FreeList` for trampoline arg-array slots | Small | ~1-2% on FFI-heavy benches | `JSHandle[]` packs in trampolines could use a sized free-list (libpas-style) |
| `--DRT-gcopt=gc:precise` ship as default | Tiny | -3% throughput / +less false retention | One-flag; trade-off, not a clear win. Worth measuring on long-running servers |
| Custom region-bumper GC via `registerGCFactory` (mir-style) | Medium-large | **~2-3× faster on D-side allocation** | Design C3. Only after C1 is exhausted |
| GC.disable() during hot benches | Tiny | ~1-2% noise reduction | Already documented in CLAUDE.md "GC tuning" |
| Continued JSC handle-leak fix campaign | Medium | Closes `bun_v7_additions` SKIP | Already on roadmap for v1.2.x |

### Suggested next step

If a concrete perf problem motivates revisiting this:

1. Confirm via `--DRT-gcopt=profile:1` that **mark + sweep**
   actually consume ≥ 10% of wall time. Today they're <5%.
2. If yes — try the [precise GC](https://github.com/dlang/druntime/pull/2418)
   first (already in druntime, just needs `--DRT-gcopt=gc:precise`).
3. If precise GC isn't enough — write a region-bumper backed by
   `mmap` (NOT cppgc) tuned for DunJS's allocation lifetimes.
4. Only after exhausting #1-3 should the cppgc bridge be
   re-evaluated.

---

## 8. References

### V8 cppgc / Oilpan

- [V8 cppgc namespace reference (head)](https://v8.github.io/api/head/namespacecppgc.html)
- [cppgc::Heap class reference](https://v8.github.io/api/head/classcppgc_1_1Heap.html)
- [v8::CppHeap class reference](https://v8.github.io/api/head/classv8_1_1CppHeap.html)
- [Oilpan library blog post (V8 9.4+)](https://v8.dev/blog/oilpan-library)
- [High-performance C++ GC](https://v8.dev/blog/high-performance-cpp-gc)
- [`include/cppgc/` source](https://chromium.googlesource.com/v8/v8.git/+/HEAD/include/cppgc/)
- [Cloudflare workerd cppgc migration PR](https://github.com/cloudflare/workerd/pull/199) — real-world embedder switch

### JavaScriptCore

- [Understanding GC in JSC from scratch (WebKit blog)](https://webkit.org/blog/12967/understanding-gc-in-jsc-from-scratch/)
- [JSC `Heap.cpp` source](https://github.com/WebKit/WebKit/blob/main/Source/JavaScriptCore/heap/Heap.cpp)
- [`JSValueProtect` Apple docs](https://developer.apple.com/documentation/javascriptcore/1395978-jsvalueprotect)
- [Notes on JavaScriptCore — Gianluca Pacchiella](https://ktln2.org/2020/08/25/javascriptcore/)

### D garbage collection

- [`core.gc.gcinterface` reference](https://dlang.org/library/core/gc/gcinterface.html)
- [`core.gc.registry`](https://dlang.org/phobos/core_gc_registry.html)
- [Configuring the GC (D spec)](https://dlang.org/spec/garbage.html#gc_config)
- [druntime swappable-GC PR #1581](https://github.com/dlang/druntime/pull/1581/files) — the original swappable-GC plumbing
- [LDC druntime GC source layout](https://github.com/ldc-developers/druntime/tree/ldc/src/core/gc) — for the verbatim interface

### Phobos `std.experimental.allocator`

- [`std.experimental.allocator` package](https://dlang.org/phobos/std_experimental_allocator.html) — overview + theallocator
- [`building_blocks`](https://dlang.org/phobos/std_experimental_allocator_building_blocks.html) — composition primitives index
- [`Region` / `BorrowedRegion` / `InSituRegion`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_region.html) — bump arenas
- [`Mallocator`](https://dlang.org/phobos/std_experimental_allocator_mallocator.html) — `core.stdc.stdlib` wrapper
- [`AllocatorList`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_allocator_list.html) — scalable arena list
- [`Segregator`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_segregator.html) — size-class routing
- [`FallbackAllocator`](https://dlang.org/phobos/std_experimental_allocator_building_blocks_fallback_allocator.html) — primary/secondary failover

### DunJS internals (for context)

- `source/dun/engine/v8/backend.d` — current `DunV8Value*` lifecycle
- `vendor/v8shim/v8shim.cpp` — thread-local value pool (lines 100-180) — the pattern a cppgc bridge would integrate with
- `.claude/commands/debug-native-callback.md` — `--DRT-gcopt=profile:1` workflow
- `CLAUDE.md` "D Runtime GC Tuning" — current GC profile-based numbers
