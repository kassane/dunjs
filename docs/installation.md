# Installation

## Prebuilt binaries

Coming soon — currently DunJS is source-only. Build instructions below
take ~5 minutes once the D toolchain is in place.

## From source

### Prerequisites

| Tool | Minimum | Why |
|------|--------:|-----|
| LDC | 1.42.0 | D compiler (frontend 2.112.1, LLVM 21) |
| (or) DMD | 2.112.1 | Alternative D compiler |
| (or) GDC | GCC 15 | Alternative — GCC-based D compiler |
| C compiler | gcc/clang | sqlite, brotli, quickjs, jsc backends |
| CMake | 3.20+ | sqlite + brotli vendor builds |

LDC is recommended — it produces the fastest binaries and bundles
LLVM 21 which we need for V8's CREL relocations.

### Quick install (Linux x86_64)

```sh
git clone https://github.com/kassane/dunjs.git
cd dunjs

# Fetch + build vendor deps for your chosen backend
ldc2 -run build.d --backend=quickjs   # QuickJS-NG (default, 9.8 MB)
# OR
ldc2 -run build.d --backend=jsc       # JavaScriptCore (60 MB)
# OR
ldc2 -run build.d --backend=v8        # V8 (60 MB)

# Build the dun binary
dub build -c quickjs                  # debug
dub build -c quickjs -b release       # release (recommended)

# Smoke test
./build/dun eval "1 + 1"              # prints: 2
./build/dun run hello.js              # if hello.js exists
```

The `build/dun` binary is statically linked against the engine libraries
in `vendor/`. You can rename + move it freely.

### Picking a backend

| Backend | Best for |
|---------|----------|
| **QuickJS-NG** | Smallest binary (9.8 MB), embedded use, fastest startup. Interpreter — slower on CPU-bound workloads |
| **JavaScriptCore** | Best raw throughput (matches/beats Bun). Same engine as Safari/Bun. 60 MB binary |
| **V8** | Best Node.js parity. Same engine as Chrome/Node 22. 60 MB binary |

All 30+ built-in modules work identically on every backend. Web
APIs, Workers, fetch, Deno compat, Bun compat — full parity.

### Building all three

```sh
for B in quickjs jsc v8; do
  dub build -c $B -b release
  cp build/dun ./dun-$B
done
```

Then `./dun-quickjs`, `./dun-jsc`, `./dun-v8` side-by-side. Useful for
cross-runtime testing.

### Verify

```sh
./dun --version
# dun 1.1.29
# engine: JavaScriptCore   (or QuickJS-NG / V8)

./dun eval "console.log('hello'); 42"
# hello

./dun run --allow-net https://example.com
# prints fetched HTML
```

## Build flags

| Flag | Purpose |
|------|---------|
| `-b release` | Optimized build (recommended for any non-debug use) |
| `-b debug` | Default — full assertions, slower runtime |
| `-b asan` | AddressSanitizer instrumentation (memory bug hunting) |
| `-b tsan` | ThreadSanitizer (race condition hunting) |
| `-b fuzzer` | `-fsanitize=fuzzer,address` for libFuzzer harnesses (parser / TS-strip / JSON / URL fuzzing) |
| `--force` | Force rebuild (useful when changing branches) |

## Troubleshooting

**`dub build` says "no compiler found"** — install LDC ≥ 1.42:
```sh
curl -fsSL https://dlang.org/install.sh | bash -s ldc-1.42.0
source ~/dlang/ldc-1.42.0/activate
```

**JSC build fails on Linux non-x86_64** — JSC prebuilt tarballs are
only available for `linux-amd64`, `linux-aarch64`, and `darwin-arm64`.
On other platforms, fall back to system `javascriptcoregtk-4.1-dev`
or build via QJS / V8.

**V8 build fails with linker errors about CREL** — V8 14.9+ / 15.0+ uses
LLVM 21's CREL relocation format. GNU ld 2.42 and lld-18 can't process
it. Use LDC 1.42+ which bundles the LLVM 21 internal linker. The
`v8` config in `dub.json` passes `--link-internally` automatically.

**`unbound icu74 symbols`** on Ubuntu noble — the static libicu in
`vendor/jsc/lib/` provides `_75` symbols needed by JSC. Make sure
they appear in the link order before `libWTF.a` (handled by
`dub.json`'s `libs-linux` order).

## Next steps

- [Quick Start](./quick-start.md) — first script, REPL, eval
- [CLI Reference](./cli-reference.md) — every subcommand + flag
- [Backends](./backends.md) — deeper backend comparison
