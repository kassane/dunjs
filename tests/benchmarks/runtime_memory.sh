#!/usr/bin/env bash
# Cross-runtime memory + time comparison.
#
# Measures peak RSS (VmHWM via Linux rusage) + wall time of each
# runtime running identical pure-JS benchmarks. All runtimes are
# release builds; Bun's BUN_OPTIONS is cleared so --smol can't skew
# results.
#
# Usage: bash tests/benchmarks/runtime_memory.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
cd "$ROOT" || exit 1

# Clear any inherited Bun options (some shells set --smol).
unset BUN_OPTIONS

readonly PEAKRSS=/tmp/peakrss.py

# Runtime entries: label:command (file appended at runtime).
RUNTIMES=(
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8 :./dun-rel-v8  run --allow-all"
  "node-22:node"
  "deno   :deno run -A --no-config --no-lock --unstable-detect-cjs"
  "bun-13 :bun run"
)

# Benchmarks to run. Each is a pure-JS file every runtime can handle.
BENCHMARKS=(
  "tests/benchmarks/feature_bench.js"
  "tests/benchmarks/framework_bench.js"
  "tests/benchmarks/safe_features.js"
)

# Header.
printf '%-32s %-30s %12s %10s\n' "benchmark" "runtime" "peak_kb" "ms"
printf '%.0s-' {1..90}; echo

run_one() {
  local rt="$1" cmd="$2" file="$3"
  "$PEAKRSS" "$rt" $cmd "$file"
}

# 1. Startup-only cost (no file): each runtime evaluates a trivial expr.
echo "=== startup ==="
for entry in "${RUNTIMES[@]}"; do
  rt="${entry%%:*}"
  cmd="${entry#*:}"
  cmd="${cmd# }"  # strip space-padding from rt label alignment
  # The eval flag differs slightly per runtime.
  case "$rt" in
    dun-qjs|dun-jsc|"dun-v8 ") "$PEAKRSS" "$rt" ${cmd%% run*} eval "1" ;;
    node-22) "$PEAKRSS" "$rt" node -e "1" ;;
    "deno   ") "$PEAKRSS" "$rt" deno eval "1" ;;
    "bun-13 ") "$PEAKRSS" "$rt" bun -e "1" ;;
  esac
done
echo

# 2. Each benchmark file.
for f in "${BENCHMARKS[@]}"; do
  echo "=== $(basename "$f") ==="
  for entry in "${RUNTIMES[@]}"; do
    rt="${entry%%:*}"
    cmd="${entry#*:}"
    cmd="${cmd# }"
    "$PEAKRSS" "$rt" timeout 90 $cmd "$f"
  done
  echo
done
