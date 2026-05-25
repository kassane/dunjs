# Advanced D / LLVM features for DunJS — evaluation

**Status**: Research / evaluation. Commissioned to assess (1) advanced
D compile-time features (reflection / CTFE / templates) for perf +
redundancy reduction, (2) uWebSockets FFI, (3) Google Highway SIMD,
(4) LDC-exclusive LLVM features. Verdicts are grounded in codebase
survey + compile-verified probes on LDC 1.42.0 / LLVM 21.

**Audience**: maintainers deciding where to spend the next perf /
cleanup budget. Every "implement" item is scoped as its own PR.

## TL;DR

| Area | Verdict | Why |
|---|---|---|
| **Table-driven callback registration** (`static foreach` + CTFE) | **DO (HIGH value / MED risk)** | ~140-150 LOC removed across builtins; promotes the existing `osExportNames` idiom |
| **`V8TypeChecks.init` `static foreach`** | **DO (small / LOW risk)** | 9 hand-written ptr assignments → 3 lines via existing `V8TypeName!t` |
| **Full-backend method mixins** | **DON'T** | `IJSEngine` bodies are irreducibly backend-specific; a generator needs so many hooks it grows longer + unreadable |
| **Auto-derive JS names from D symbols** | **DON'T** | mapping is lossy (`jsReadFileAsync→"readFile"`, `jsOsHostname→"hostname"`) → silent wrong-name bugs |
| **uWebSockets FFI** | **REJECT** | uWS owns its event loop; irreconcilable with DunJS's cooperative single-threaded `tick()`; ~600-1000 LOC C++ shim + large unsafe surface for uncertain gain over the already-tuned epoll path |
| **Google Highway SIMD** | **REJECT (redundant)** | LDC already lowers `core.simd`/`ldc.simd` to LLVM vector IR + auto-vectorizes; Highway's only differentiator (runtime CPU dispatch) is matched natively by LDC `@target` (verified below) — without an FFI-per-call boundary that defeats inlining |
| **In-tree base64 SIMD** | **DO (HIGH value / MED risk)** | base64 is the hottest byte path still on scalar `std.base64`; vectorize with the existing `ldc.simd` toolkit, no new dep |
| **LDC `@target` multiversioning** | **EVALUATE (the Highway alternative)** | per-function AVX2 codegen + `core.cpuid` runtime dispatch, zero C++ |
| **LDC `@restrict` / `@fastmath` / `@optStrategy`** | **SELECTIVE** | `@restrict` only helps fixed-stride loops (not the branchy codecs); `@fastmath` is correctness-risky; `@optStrategy("optsize")` useful on cold paths |

---

## 1. Advanced D reflection / CTFE

### 1a. Native-callback registration (HIGH value)

Every `registerXxxModule` repeats the triple
`engine.setProperty(obj, "name", engine.newFunction(&jsName, "name", argc))`
— **~220 inline call sites** across the builtins (`fs.d`, `os.d`,
`crypto.d`, `process_api.d`, …). A CTFE table + `static foreach`
registrar collapses each block ~3:1:

```d
struct FnDef { string name; NativeCallback fn; int argc; }
static immutable osFns = [
    FnDef("platform", &jsOsPlatform, 0),
    FnDef("arch",     &jsOsArch,     0),
    /* … */
];
static foreach (f; osFns)
    engine.setProperty(obj, f.name, engine.newFunction(f.fn, f.name, f.argc));
```

Realistic reduction **~140-150 LOC**. This *generalizes the
`osExportNames` list* that already exists in `os.d:92` (currently
QuickJS-only, for module exports) into the registration path too.

**Risk (MEDIUM), scoped honestly:**
- JS names are **not** mechanically derivable from the D symbol
  (`jsReadFileAsync→"readFile"`, `jsOsHostname→"hostname"`), so the
  `__traits(identifier)` "stringify the symbol" variant is rejected —
  keep the name string explicit in the table.
- Keep tables **data-only** (`static immutable[]`) with a trivial
  loop body, so `git blame` points at the table row, not a mixin, and
  compile-time cost stays flat.
- QuickJS int16 slot limit (CLAUDE.md §5) is unchanged — table
  registration doesn't alter slot count.

### 1b. `V8TypeChecks.init` `static foreach` (small, clean)

`v8/cppbindings.d` hand-writes 9 `table[Tag.X] = &dun_v8_value_is_x`
assignments; the unittest already proves the `static foreach` +
`V8TypeName!t` pattern. Promote it into `init()` — 9 lines → 3, zero
runtime cost, mirrors a pattern already validated in the same file.

### 1c. Reflection already used well (extend these)

Enum-drift guards are the established idiom and should be the model:
`iface.d:242` (`EngineBackend`==3), `permissions.d:27`
(`Permission`==9), `args.d:25` (`Command`==14), plus
`fs.d:557` `__traits(hasMember, …, "st_atim")` platform-field probing.
The research recommendation is "extend the existing static-assert /
list-table idioms," not introduce new metaprogramming styles.

### 1d. What reflection would HURT
- Don't mixin full `IJSEngine` method bodies (handle marshalling,
  `newUint8Array`, exception extraction are 280-630 LOC/backend of
  irreducibly backend-specific code).
- Don't auto-derive names (§1a).
- Don't rework the CTFE tables — `simd.d`/`buffer.d` hex LUTs +
  `declarations.d` enums are already CTFE; no runtime-built constant
  table of significance remains.

---

## 2. uWebSockets FFI — REJECT

**Current HTTP architecture** (`builtins/http.d` + `loop/iopoller.d`):
`IOPoller` abstracts epoll/kqueue/`poll()`/io_uring; `pollHttpIO`
(`http.d:1840`) calls `poll(0)` — **non-blocking** — each `tick()`;
`dispatchHttpCallbacks` runs inline on the JS thread; req/res built in
JIT-optimized JS via `Object.create(reqProto)`. The event loop
(`eventloop.d:54-139`) is strictly cooperative: microtasks → timers →
microtasks → HTTP I/O → workers/signals → microtasks, never blocking
inside the poller.

**The fatal conflict:** uWS *owns* its loop (`us_loop`, blocking
`us_loop_run()`) and is header-only **C++ templates** (needs a
v8shim-style `extern "C"` shim, ~600-1000 LOC). You cannot run uWS's
blocking loop without starving DunJS's microtasks / timers / workers /
N-API drains. The two options are both bad: (a) replace IOPoller with
uWS's loop and re-plumb all of Layer 3 (timers, microtasks, workers,
TLS, http2, ws, cluster, N-API) as uWS deferred callbacks — a Layer-3
rewrite; or (b) pump uWS non-blocking per tick — which discards uWS's
entire throughput advantage (its tuned loop + zero-copy backpressure),
leaving a heavy C++ dep that barely beats the current tuned path
(TCP_NODELAY, buffered single-`send`, CTFE status lines, proto-based
JS dispatch). Either way it inflates the unsafe surface the project
deliberately minimizes. **Cost 2-4 weeks, high risk, uncertain gain →
not worth it.**

---

## 3. Google Highway SIMD — REJECT (redundant)

**Current SIMD** (`platform/simd.d`): `core.simd` (`ubyte16`) +
`ldc.simd` (`loadUnaligned`/`storeUnaligned`/`shufflevector`) +
`ldc.intrinsics` (`llvm_cttz`/`llvm_prefetch`/`llvm_bswap`). Primitives:
`hexEncodeBuf` (16B/cycle via `shufflevector`), `asciiToLowerBuf`,
`findByte` (movemask + `llvm_cttz`), `bswap*`. **Scalar (no SIMD):**
`latin1ToUtf8Buf`/`utf8ToLatin1Buf` and **base64** (scalar
`std.base64` in `buffer.d` + `crypto.d`).

**Why Highway is redundant:** LDC already lowers `core.simd`/`ldc.simd`
to LLVM vector IR and, with release `--mcpu=native` + `--flto=thin`,
auto-vectorizes + selects AVX/AVX2/NEON. Highway's headline value
(portable intrinsics) is what LLVM's backend already provides. Its one
genuine differentiator — **runtime CPU dispatch** (single binary picks
AVX-512 vs SSE at runtime) — is matched natively by LDC `@target`
(§4) with no FFI boundary. Binding Highway means a large C++ template
lib + a C shim (the vtable problem again) + an FFI call per op that
**defeats inlining** — whereas `simd.d`'s intrinsics inline to a few
instructions.

**The real SIMD opportunity is in-tree:** vectorize **base64**
(currently scalar `std.base64`, a real Buffer/crypto hot path) and the
latin1 converters using the existing `ldc.simd` primitives — same
pattern as `hexEncodeBuf`, no new dependency, a few days of work. Note
latin1's data-dependent output length (1 vs 2 bytes per input) limits
naive vectorization; base64's fixed 3→4 / 4→3 stride is the cleaner
SIMD target.

---

## 4. LDC-exclusive LLVM features

All attributes below are LDC-only (not in DMD), from `ldc.attributes`.
**Compile-verified on LDC 1.42.0** with a standalone probe (`@target`,
`@restrict`, `@fastmath`, `@optStrategy`, `@llvmAttr` all compiled +
ran).

### 4a. `@target` — the native Highway alternative (EVALUATE)

`@target("arch=skylake")` / `@llvmAttr("target-features", "+avx2")`
compiles a *single function* with a different CPU/feature set than the
command line. **Verified codegen effect:** a plain reduction loop
emits 0 AVX `ymm` registers under generic `x86-64`, but **8 `ymm`
registers** when annotated `@target("arch=skylake")` — i.e. real AVX2
vectorization of one function without global `--mcpu=native`.

Combined with D's `core.cpuid` (`avx2` / `avx512f` runtime flags),
this gives **runtime CPU multiversioning** — ship one binary, dispatch
to the AVX-512 / AVX2 / baseline variant at runtime — which is exactly
Highway's selling point, achieved with zero C++ and full inlining
within each variant. Sketch:

```d
@target("arch=x86-64")          size_t hexBaseline(const(ubyte)[] s, char[] d) { … }
@target("arch=skylake")         size_t hexAvx2(const(ubyte)[] s, char[] d) { … }
// one-time dispatch:
import core.cpuid : avx2;
__gshared hexFn = avx2 ? &hexAvx2 : &hexBaseline;
```

**Caveat:** today DunJS release builds use `--mcpu=native` (tuned for
a known target), so multiversioning only matters if we ship *portable*
release binaries (Docker images already pin `x86-64-v3`/`NEON`). EVALUATE
only if portable-binary distribution becomes a goal; otherwise
`--mcpu=native` already gets the AVX codegen for free.

### 4b. `@restrict` — `noalias` params (SELECTIVE)

Adds LLVM `noalias` (C99 `restrict`) to a pointer param so LLVM may
assume no aliasing and vectorize/reorder more aggressively. **Only
helps fixed-stride loops where aliasing is the blocker.** The current
codecs (`latin1ToUtf8Buf`) have data-dependent output and a per-byte
branch, so `@restrict` won't vectorize them. Candidates: a future
base64 SIMD core, `Buffer.copy`/`concat` memcpy fast paths if not
already `memcpy`. LOW risk where the slices provably don't overlap.

### 4c. `@fastmath` / `@llvmFastMathFlag` — AVOID broadly

Aggressive FP reassociation. DunJS's FP surface (`performance.now`,
`hrtime`, `Math.*` delegated to the engine) is correctness-sensitive
and NaN/Inf-relevant for spec compliance — `@fastmath` can change
observable results. Not worth it.

### 4d. `@optStrategy("optsize"|"minsize")` (NICHE)

Per-function opt level. Useful to shrink cold init/error paths
(error-message formatters, one-time `registerXxxModule` bodies) when
binary size matters; negligible perf relevance. LOW priority.

### 4e. Already in use
`--flto=thin`, `--fno-plt` (≈ `@noplt` globally), `--frame-pointer=none`,
`--linkonce-templates`, `--inline-threshold=350`, `--hot-cold-split`,
`pragma(inline, true)`, PGO build types (`release-pgo-gen`/`-pgo`),
ASan/TSan/fuzzer build types. The LDC LLVM surface is already
well-exploited; the unexploited levers are `@target` (4a) and
`@restrict` (4b) on specific hot loops.

---

## Prioritized roadmap

1. **`V8TypeChecks.init` static-foreach** — small, clean, LOW risk. Quick win.
2. **Table-driven callback registration** — HIGH LOC reduction; do per-file in small PRs to keep `git blame` legible. Start with `os.d` (already has `osExportNames`).
3. **In-tree base64 SIMD** (`ldc.simd`) — HIGH perf value on a real hot path; MEDIUM risk (decode correctness across the 256-byte + padding edges — gate behind the existing `audit_roundtrip` fixture).
4. **`@target` multiversioning** — EVALUATE only if portable release binaries become a distribution goal; otherwise `--mcpu=native` already covers it.
5. **Reject**: uWebSockets (event-loop conflict), Google Highway (LLVM-redundant + FFI-per-call).
