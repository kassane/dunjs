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
| `--mcpu=native` | Tune for the host CPU (makes the binary non-portable; strip for shipping) |
| `--flto=thin` | ThinLTO — cross-module inlining at link time. Faster than full LTO, far less memory; nearly the same optimization quality |
| `--fno-plt` | Skip PLT indirection on shared-lib calls |
| `--frame-pointer=none` | Free a register on AMD64 |
| `--linkonce-templates` | Merge identical template instantiations across TUs |
| `--inline-threshold=350` | Larger inline budget (default 225) |
| `--hot-cold-split` | Move rarely-executed code to `.text.unlikely` to keep the icache hot |

Strip `--mcpu=native` before shipping a release binary:

```sh
DFLAGS="--mcpu=x86-64-v3" dub build -c quickjs -b release  # AVX2 baseline
```

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
- `release-pgo-gen`: `-O3 --release --boundscheck=off --mcpu=native --fprofile-instr-generate=build/dun-%m.profraw` + `-lldc_rt.profile`
- `release-pgo`: same release flags + ThinLTO + `--fprofile-instr-use=build/dun.profdata`

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

Backend test scores: **QuickJS 146/146, JSC 145/145 + 1 SKIP (`bun_v7_additions`), V8 146/146** (full parity, Workers on all backends).

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
3. **Integration tests**: Run 131 fixtures against expected output on Linux/macOS/Windows

## DUB Configurations

| Config | Version Flag | Vendor Deps | Link Flags |
|--------|-------------|-------------|------------|
| `quickjs` | `EngineQuickJS` | CMake-built libqjs.a | `-lqjs`, `-lm`, `-ldl` |
| `jsc` | `EngineJSC` | Prebuilt from oven-sh/WebKit | `-L vendor/jsc/lib`, JSC libs |
| `v8` | `EngineV8` | V8 14.9.207.4 from kassane/libv8 + v8shim | `-lv8`, `-lv8_libplatform`, `-lv8shim` (LDC: `--link-internally`) |
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
