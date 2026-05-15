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

## Reference numbers (May 2026, this branch)

| Benchmark         | Bun 1.3 | Node 22 | DunJS V8 | DunJS QJS |
|-------------------|---------|---------|----------|-----------|
| feature_bench     | 416M    | 111M    | 109M     | 14M       |
| framework_bench   | 249M    | 133M    | 125M     | 12M       |
| npm_compat        | 145/145 | 145/145 | 145/145  | 145/145   |

DunJS V8 is ~98% of Node on feature, ~94% on framework. QuickJS is interpreter-only.
