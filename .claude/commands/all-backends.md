---
description: Build all three DunJS backends (QuickJS, JSC, V8) and stage side-by-side `./dun-<backend>` binaries for parity testing. Use when verifying a change holds across backends, or after touching `source/dun/engine/`, `source/dun/builtins/`, or `dub.json`.
---

# Build All Backends

Builds QuickJS / JSC / V8 in sequence, copies each to `./dun-<backend>`, smoke-tests
`./dun-X eval "1+1"`, and prints a summary table. Mirrors the manual loop I ran ~15
times during the runtime-parity session.

## Usage

```sh
# Default: debug build of all three
/all-backends

# Release build (for benchmarks)
/all-backends release

# Skip vendor deps (assume already built — saves 30s)
/all-backends skip-vendor
```

## Steps

1. **Ensure toolchain:** `export PATH=/opt/ldc/bin:$PATH` (LDC 1.42 must already be installed; see `/build` if missing).

2. **Vendor deps:** unless `skip-vendor`, run for each backend:
   ```sh
   ldc2 -run build.d --backend=quickjs   # QuickJS-NG via CMake FetchContent
   ldc2 -run build.d --backend=jsc       # prebuilt JSC from oven-sh/WebKit
   ldc2 -run build.d --backend=v8        # libv8 14.9 + v8shim
   ```

3. **Compile + stage:** for `B` in `quickjs jsc v8`:
   ```sh
   dub build -c $B ${RELEASE:+-b release}
   cp build/dun ./dun-${B/quickjs/qjs}${RELEASE:+-rel}
   ```
   Output binaries:
   - debug: `./dun` (qjs), `./dun-jsc`, `./dun-v8`
   - release: `./dun-rel-qjs`, `./dun-rel-jsc`, `./dun-rel-v8`

4. **Smoke test:** verify each runs `eval "1+1"` returns `2`.

5. **Report:** print a one-line summary per backend with binary size and smoke status.

## Known gotchas (encountered this session)

- **JSC linker order:** adding libs to top-level `libs-linux` in `dub.json` reorders the JSC config's libs, breaking ICU resolution. Use `lflags-linux: ["-l<name>"]` instead.
- **V8 needs `--link-internally`:** V8 14.9 monolith uses CREL relocations; only LDC's internal LLVM21 linker handles them.
- **ICU mismatch on Ubuntu noble:** system has libicu74 but JSC needs symbols `_75`. The static `libicu*.a` in `vendor/jsc/lib/` provide them — they must be linked before libWTF (JSC config's `libs-linux` order matters).
- **Avoid `--mcpu=native` for anything you'll ship.** The default `release` buildType in `dub.json` uses `--mcpu=native` so the side-by-side `./dun-rel-{qjs,jsc,v8}` binaries are tuned to the build host — fine for local benches, wrong for distribution. `native` can also silently produce under-specified feature sets on cross or embedded targets (see [ldc-developers/ldc#4919](https://github.com/ldc-developers/ldc/issues/4919)). Always inspect what LDC will actually emit, then pin an explicit CPU:
  ```sh
  # Inspect first — shows resolved Target + Features list, no codegen
  ldc2 --mtriple=x86_64-linux-gnu -mcpu=x86-64-v3 -vv | grep -E '^(Target|Features:)'

  # Then pin the explicit CPU
  DFLAGS="--mcpu=x86-64-v3" dub build -c quickjs -b release   # AVX2 baseline (2013+)
  DFLAGS="--mcpu=x86-64-v2" dub build -c quickjs -b release   # SSE4.2 baseline (2009+)
  DFLAGS="--mcpu=x86-64"    dub build -c quickjs -b release   # generic AMD64
  ```
  See `/build` for the full release-flag breakdown.
- **PGO binaries are even less portable** — `release-pgo` binaries are tuned for the workload that produced `build/dun.profdata`. Don't rebuild PGO with a stale `.profdata` from a different DunJS commit, or `ldc-profdata merge` will silently produce a profile that misses your new code paths. See `/build` for the full PGO recipe.
