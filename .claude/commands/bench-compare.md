---
description: Run `feature_bench.js` / `framework_bench.js` / `npm_compat_test.js` against DunJS (all 3 backends), Node, and Bun in one go and print a comparison table. Use after a change that could affect performance, or to verify cross-runtime parity.
---

# Cross-Runtime Benchmark Compare

Reproduces the comparison table from the runtime-parity session. Each benchmark
prints `Total throughput: N ops/sec` (or `passed/failed` for npm_compat); the
skill extracts those numbers and tabulates.

## Prereqs

Built release binaries in place (`./dun-rel-qjs`, `./dun-rel-jsc`, `./dun-rel-v8`).
If missing, run `/all-backends release` first.

`node`, `bun`, and `deno` should be on `$PATH`. Deno needs
`--unstable-detect-cjs -A` to run the CJS-format bench files (the
benchmarks use `require('crypto')` etc.). Missing runtimes get skipped.

## Usage

```sh
/bench-compare                  # all three benchmarks
/bench-compare feature          # only feature_bench.js
/bench-compare framework        # only framework_bench.js
/bench-compare npm              # only npm_compat_test.js
```

## Run sequence

```sh
for bench in feature_bench framework_bench npm_compat_test; do
  echo "=== $bench ==="
  bun  run                       tests/benchmarks/$bench.js 2>&1 | grep -E 'Total throughput|passed'
  node                           tests/benchmarks/$bench.js 2>&1 | grep -E 'Total throughput|passed'
  ./dun-rel-v8  run --allow-all  tests/benchmarks/$bench.js 2>&1 | grep -E 'Total throughput|passed'
  ./dun-rel-qjs run --allow-all  tests/benchmarks/$bench.js 2>&1 | grep -E 'Total throughput|passed'
  ./dun-rel-jsc run --allow-all  tests/benchmarks/$bench.js 2>&1 | grep -E 'Total throughput|passed'
done
```

## Caveats

- **JSC release** segfaults partway through `feature_bench` (dupValue+setProperty
  leak pattern under heavy iteration); the table will show `-` for the JSC column
  on that bench. Reproduces deterministically after `crypto.createHash` →
  `Buffer.alloc` → `Buffer.concat` sequence.
- **`feature_bench`** auto-calibrates iters; total wall time ~30s per runtime.
- **`npm_compat_test`** loads 15 simulated npm packages; ~5s per runtime.

## Tighter numbers via PGO

For headline numbers (e.g. updating a CHANGELOG release table or
README perf section), rebuild the DunJS binaries with PGO before
running the comparison. PGO gives the LDC front-end itself ~7%
on D-heavy code per Johan Engelen's measurement; expect a similar
or better lift on `dun`'s native trampolines.

```sh
# Per backend:
for B in quickjs jsc v8; do
  dub build -c $B -b release-pgo-gen
  ./build/dun run --allow-all tests/benchmarks/feature_bench.js   > /dev/null
  ./build/dun run --allow-all tests/benchmarks/framework_bench.js > /dev/null
  ldc-profdata merge -o build/dun.profdata build/dun-*.profraw
  dub build -c $B -b release-pgo
  cp build/dun ./dun-pgo-${B/quickjs/qjs}
  rm -f build/dun-*.profraw
done
```

Then run `/bench-compare` using `./dun-pgo-{qjs,jsc,v8}` in place of
the plain `./dun-rel-*` binaries. Note PGO-built binaries are tuned
for the specific workload you trained them on — use the same bench
suite for training as for measurement, or you'll measure noise from
mispredicted code paths.

## Reference numbers

See [TESTING.md](../../TESTING.md) for the canonical perf tables — numbers
are updated each release and can drift across snapshots.

Cross-runtime correctness is `145/145` on `npm_compat` for every supported
runtime; the per-benchmark throughput delta between DunJS V8 and Node is
within a few percent, and QuickJS is interpreter-only (10-100× slower on
CPU-bound code, comparable on I/O-bound).
