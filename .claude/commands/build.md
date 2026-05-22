# Build & Test DunJS

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| LDC >= 1.42.0 | Yes | D compiler (preferred) |
| DMD >= 2.112.1 | Alt | D compiler (alternative) |
| GDC >= GCC 15 | Alt | D compiler (alternative) |
| GCC/Clang | Yes | C compiler for QuickJS |
| CMake | QuickJS | Build system for QuickJS-NG |
| g++ or clang++ | V8 | C++ compiler for v8shim |
| OpenSSL (libssl, libcrypto) | TLS/fetch | HTTPS support |

## Build Steps

### 1. Vendor Dependencies

```sh
# QuickJS-NG (downloads + CMake build)
ldc2 -run build.d --backend=quickjs --verbose

# JSC (downloads prebuilt from oven-sh/WebKit, macOS: system framework)
ldc2 -run build.d --backend=jsc --verbose

# V8 (downloads prebuilt from kassane/libv8 + compiles v8shim.cpp)
ldc2 -run build.d --backend=v8 --verbose

# All backends at once
ldc2 -run build.d --backend=all --verbose

# Force rebuild (clears cached artifacts)
ldc2 -run build.d --backend=quickjs --verbose --force
```

### 2. Build

```sh
dub build -c quickjs              # QuickJS debug
dub build -c jsc                  # JSC debug
dub build -c v8                   # V8 debug
dub build -c quickjs -b release   # QuickJS release (optimized + stripped)
```

#### Release flag breakdown (from `dub.json` `release` buildType)

LDC-specific flags applied on `-b release` (`dflags-ldc`):

| Flag | Effect |
|------|--------|
| `-O3` | LLVM aggressive optimization |
| `--release` | Strip contracts / invariants / asserts |
| `--boundscheck=off` | No `RangeError` instrumentation in array indexing |
| (no `--mcpu=`) | `dub.json` deliberately does NOT set `--mcpu` on any release buildType. `--mcpu=native` ties the binary to the build host's exact CPU (`cascadelake`, `znver4`, …) and on cross / WASM / embedded targets even named CPUs like `x86-64-v3` or `wasm32 generic` can resolve to `features ''` ([ldc-developers/ldc#4919](https://github.com/ldc-developers/ldc/issues/4919) — reproduced on 1.42.0). LLVM picks a safe baseline by default. If you need a specific instruction set, add it ad-hoc via `DFLAGS="--mcpu=… --mattr=+…"` and inspect via `-vv` first (see below) |
| `--flto=thin` | ThinLTO — cross-module inlining at link time. Faster than full LTO, far less memory; nearly the same optimization quality |
| `--fno-plt` | Skip PLT indirection on shared-lib calls |
| `--frame-pointer=none` | Free a register on AMD64 |
| `--linkonce-templates` | Merge identical template instantiations across TUs |
| `--inline-threshold=350` | Larger inline budget (default 225) |
| `--hot-cold-split` | Move rarely-executed code to `.text.unlikely` to keep the icache hot |

**Inspect what LDC will emit before adding `--mcpu` or `--mattr`** —
`-vv` prints one line per target showing the resolved CPU + every
feature it will (and won't) emit. This is how you avoid the empty-
feature trap from #4919.

```sh
# Print the line that shows what LDC will codegen — single-line format:
#   "Targeting '<triple>' (CPU '<cpu>' with features '<list>')"
echo 'void main(){}' > /tmp/empty.d
ldc2 --mcpu=native -vv /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting

ldc2 --mtriple=x86_64-linux-gnu   -mcpu=x86-64-v3   -vv /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting
ldc2 --mtriple=aarch64-linux-gnu  -mcpu=neoverse-n1 -vv /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting
ldc2 --mtriple=wasm32-unknown-emscripten -mcpu=generic -vv /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting
```

Reproduced on LDC 1.42.0:

```
Targeting 'x86_64-unknown-linux-gnu' (CPU 'cascadelake' with features '+prfchw,-cldemote,+avx,+aes,...')
Targeting 'x86_64-unknown-linux-gnu' (CPU 'x86-64-v3' with features '')   # <-- empty!
Targeting 'aarch64-unknown-linux-gnu' (CPU 'neoverse-n1' with features '') # <-- empty!
Targeting 'wasm32-unknown-emscripten' (CPU 'generic' with features '')     # <-- empty! (#4919)
```

`--mcpu=native` expands to the host's full feature list explicitly.
Named generic profiles report empty features — LLVM emits sensible
defaults but you can't tell from `-vv` what those are. If you need
specific instructions, add them with `--mattr` (they DO show up):

```sh
ldc2 --mtriple=x86_64-linux-gnu -mcpu=x86-64-v3 -mattr=+aes,+pclmul -vv /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting
# -> Targeting '...' (CPU 'x86-64-v3' with features '+aes,+pclmul')
```

#### Reference baselines (mirror Zig std.Target on LLVM 21)

When you want a deterministic, portable build with a known feature
floor, mirror Zig's `std.Target` defaults — they're explicit, audited,
and a known-good starting point that LDC's LLVM 21 accepts in full.

**x86-64-v3** (Haswell-and-later AMD64, AVX2+FMA baseline):
```sh
DFLAGS="--mcpu=x86-64-v3 -mattr=+64bit,+avx,+avx2,+bmi,+bmi2,+cmov,+crc32,+cx16,+cx8,\
+f16c,+fma,+fxsr,+lzcnt,+mmx,+movbe,+popcnt,+sahf,+sse,+sse2,+sse3,+sse4.1,+sse4.2,\
+ssse3,+x87,+xsave,+allow-light-256-bit,+false-deps-lzcnt-tzcnt,+false-deps-popcnt,\
+fast-15bytenop,+fast-scalar-fsqrt,+fast-shld-rotate,+fast-variable-crosslane-shuffle,\
+fast-variable-perlane-shuffle,+idivq-to-divl,+macrofusion,+nopl,+slow-3ops-lea,\
+vzeroupper" dub build -c quickjs -b release
```

24 ISA flags + 13 LLVM scheduling tunings. Bench impact measured on
LDC 1.42 host (`feature_bench` / `framework_bench`):

| Backend | feature_bench Δ | framework_bench Δ |
|---------|----------------:|------------------:|
| qjs | +0.2% (noise)   | -6.5%             |
| jsc | +1.6% (noise)   | **+8.7%**         |
| v8  | -1.5% (noise)   | +3.9%             |

So a Zig-v3 build is mostly a wash for DunJS — JIT-heavy backends
(jsc/v8) see at most ~5-9% on framework workloads. QJS gains nothing
because the interpreter dispatch loop dominates over auto-vectorizable
code. Worth using when you're shipping to a known-v3 host; not worth
making the `dub.json` default.

**aarch64-generic** (Zig's default for ARM64, minimum NEON):
```sh
DFLAGS="--mcpu=generic -mattr=+enable-select-opt,+ete,+fp-armv8,+fuse-adrp-add,\
+fuse-aes,+neon,+trbe,+use-postra-scheduler" dub build -c quickjs -b release
```

8 features (NEON + scheduler tunings). Cross-verified with
`ldc2 --mtriple=aarch64-linux-gnu -c -O3 ...` — produces a valid
`ELF 64-bit LSB relocatable, ARM aarch64` object. Bench numbers
require an actual aarch64 host (the project's Dockerfile builds
`linux/arm64` via buildx and is the right place to measure this).

**Inspection workflow before adding any `-mattr` set:**

```sh
echo 'void main(){}' > /tmp/empty.d
ldc2 --mtriple=<your-triple> -mcpu=<your-cpu> -mattr=<your-flags> -vv \
     /tmp/empty.d -of=/tmp/o 2>&1 | grep -i Targeting
```

Pin only what shows up in `features '...'`. If a flag is missing,
LDC silently dropped it (different LLVM version, wrong dash-case,
arch mismatch) — fix the flag, don't assume LLVM picked it up.

Recommended workflow: leave `dub.json` `--mcpu` unset (current state),
add `DFLAGS="--mcpu=… --mattr=+…"` per-build when you have a specific
target in mind, and always verify via `-vv` first.

Reference: https://github.com/ldc-developers/ldc/issues/4919

### 2b. PGO release (`-b release-pgo-gen` → `-b release-pgo`)

Profile-Guided Optimization recipe. Real-world gain on the LDC
front-end itself was ~7% per the LDC-author writeup; expect similar
or better on a JIT-heavy embedder like `dun`.

```sh
# 1. Instrumented build (writes build/dun-<pid>.profraw at runtime)
dub build -c quickjs -b release-pgo-gen

# 2. Run representative workloads to collect profile data
./build/dun run --allow-all tests/benchmarks/feature_bench.js
./build/dun run --allow-all tests/benchmarks/framework_bench.js
bash tests/benchmarks/http_bench/stress.sh

# 3. Merge .profraw files into build/dun.profdata
ldc-profdata merge -o build/dun.profdata build/dun-*.profraw

# 4. Final optimized build using the profile
dub build -c quickjs -b release-pgo
```

PGO build types are defined in `dub.json`:
- `release-pgo-gen`: `-O3 --release --boundscheck=off --fprofile-instr-generate=build/dun-%m.profraw` + lflags `--whole-archive -lldc_rt.profile --no-whole-archive`
- `release-pgo`: same release flags + ThinLTO + `--fprofile-instr-use=build/dun.profdata`

**Critical**: the `--whole-archive` wrapping around `-lldc_rt.profile` is
required with LDC 1.42's internal linker. Without it the LLD pulls in
only `__llvm_profile_instrument_target` (the symbol referenced by
compile-time instrumentation calls) but not the 47 other symbols that
make up the runtime — `__llvm_profile_begin_data`, `__llvm_profile_filename`,
the registry, etc. The binary then runs but writes no `.profraw` file
on exit. Verify with `nm build/dun | grep -c __llvm_profile_` — should
be ≥ 48.

Only profile what you want optimized — PGO only speeds up paths it sees.

### 2c. Incremental builds with `--ir2obj-cache`

LDC can skip codegen for unchanged modules. The author measured
5m50 → 2m30 on the LDC front-end with 100% cache hit (optimization
and codegen both skip; only linking runs).

```sh
DFLAGS="--ir2obj-cache=$HOME/.cache/dun-ldc-cache" dub build -c quickjs
```

Prune (avoid the cache eating multiple GiB):

```sh
ldc-prune-cache --max-bytes=2147483648 $HOME/.cache/dun-ldc-cache  # cap to 2 GiB
# OR
ldc-prune-cache --max-percentage-of-avail=75 $HOME/.cache/dun-ldc-cache  # default
```

The cache lives outside the DUB build tree and survives `dub clean`.
Reference: https://johanengelen.github.io/ldc/2016/09/17/LDC-object-file-caching.html


### 3. Test

```sh
# Unit tests (see TESTING.md for the canonical breakdown by suite)
dub test -c unittest                 # QuickJS (118)
dub test -c unittest-jsc             # JSC (47)
dub test -c unittest-v8              # V8 (118)

# Integration tests (131 fixtures, requires built binary)
dub build -c quickjs
bash tests/integration/run.sh

# Integration tests for other backends
dub build -c jsc && BACKEND=jsc bash tests/integration/run.sh
dub build -c v8  && BACKEND=v8  bash tests/integration/run.sh

# Cross-runtime benchmarks
./build/dun run --allow-all tests/benchmarks/feature_bench.js    # 25 perf tests
./build/dun run --allow-all tests/benchmarks/framework_bench.js  # 39 framework tests
./build/dun run --allow-all tests/benchmarks/fs_bench.js         # 24 fs perf tests
./build/dun run --allow-all tests/benchmarks/fs_parity.js        # 69 fs correctness
./build/dun run --allow-all tests/benchmarks/safe_features.js    # 231 safe feature checks
./build/dun run --allow-all tests/benchmarks/npm_compat_test.js  # 145 npm compat
./build/dun run --allow-all tests/benchmarks/stress.js           # 240 stress tests

# GC tuning benchmarks
./build/dun "--DRT-gcopt=parallel:4 minPoolSize:32" run --allow-all tests/benchmarks/feature_bench.js
```

Backend test scores: **QuickJS 162/162, JSC 161/162 + 1 SKIP (`bun_v7_additions`), V8 162/162** (full parity, Workers on all backends).

### 4. Docker

```sh
# Single-backend
docker build --build-arg BACKEND=quickjs -t dunjs:quickjs .
docker build --build-arg BACKEND=jsc -t dunjs:jsc .
docker build --build-arg BACKEND=v8 -t dunjs:v8 .

# Multi-backend (all 3, switchable via DUN_BACKEND env)
docker build -f Dockerfile.multibackend -t dunjs:multi .
docker run --rm dunjs:multi run script.js                    # quickjs default
docker run --rm -e DUN_BACKEND=jsc dunjs:multi run script.js
docker run --rm -e DUN_BACKEND=v8 dunjs:multi run script.js
```

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs:
1. **Build matrix**: QuickJS (Linux/macOS/Windows), JSC (Linux/macOS), V8 (Linux compile-check)
2. **Unit tests**: `dub test -c unittest` on Linux/macOS/Windows
3. **Integration tests**: Run 162 fixtures against expected output on Linux/macOS/Windows

## DUB Configurations

| Config | Version Flag | Vendor Deps | Link Flags |
|--------|-------------|-------------|------------|
| `quickjs` | `EngineQuickJS` | CMake-built libqjs.a | `-lqjs`, `-lm`, `-ldl` |
| `jsc` | `EngineJSC` | Prebuilt from oven-sh/WebKit | `-L vendor/jsc/lib`, JSC libs |
| `v8` | `EngineV8` | V8 15.0.91 from kassane/libv8 + v8shim | `-lv8`, `-lv8_libplatform`, `-lv8shim` (LDC: `--link-internally`) |
| `unittest` | `EngineQuickJS` + `DunTest` | Same as quickjs | Same as quickjs |

## GC Tuning

```sh
# Profile GC
./build/dun "--DRT-gcopt=profile:1" run script.js

# Best perf config (parallel marking + larger pool)
./build/dun "--DRT-gcopt=parallel:4 minPoolSize:32" run script.js

# Precise GC (fewer false retentions)
./build/dun "--DRT-gcopt=gc:precise minPoolSize:32" run script.js
```

## Troubleshooting

- **"cannot find -lqjs"**: Run `ldc2 -run build.d --backend=quickjs` first
- **"cannot find -lv8" in Docker**: Ensure `.dockerignore` excludes `vendor/v8/lib/` (broken absolute symlinks)
- **JSC link errors on Linux**: Prebuilt JSC auto-downloaded by build.d
- **Windows MSVC errors**: Ensure `ilammy/msvc-dev-cmd` or VS Developer prompt is active
- **Windows __imp_fesetround**: QuickJS CRT mismatch -- build.d forces `/MT` via CMake flags
- **OpenSSL not found (macOS)**: Install via `brew install openssl`, paths auto-detected
- **V8 "unknown architecture" link error**: V8 14.9 monolith uses CREL relocations (LLVM 19+). LDC's internal linker (`--link-internally`) handles this; GNU ld 2.42 and lld-18 cannot. The `dflags-linux-ldc` in dub.json enables this automatically
- **segfault debugging**: Use `gdb ./build/dun` with `run script.js`, check backtrace
