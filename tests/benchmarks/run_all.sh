#!/bin/bash
# Cross-runtime benchmark comparison
# Usage: bash tests/benchmarks/run_all.sh
#
# Requires: node, bun, deno in PATH
# DunJS backends: set DUN_QJS, DUN_JSC, DUN_V8 env vars or auto-detect from /tmp

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../.."
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

BENCH="$SCRIPT_DIR/feature_bench.js"
FRAMEWORK="$SCRIPT_DIR/framework_bench.js"
STRESS="$SCRIPT_DIR/stress.js"
COMPAT="$SCRIPT_DIR/npm_compat_test.js"

echo "========================================="
echo "  DunJS Cross-Runtime Benchmark Suite"
echo "========================================="
echo ""

# Detect runtimes
declare -A RT_CMD
declare -A RT_VER

if command -v node >/dev/null 2>&1; then
    RT_CMD[node]="node"
    RT_VER[node]="Node.js $(node --version)"
fi
if command -v bun >/dev/null 2>&1; then
    RT_CMD[bun]="bun run"
    RT_VER[bun]="Bun $(bun --version)"
fi
if command -v deno >/dev/null 2>&1; then
    RT_CMD[deno]="deno run --allow-all --unstable-detect-cjs"
    RT_VER[deno]="Deno $(deno --version | head -1 | awk '{print $2}')"
fi

# DunJS backends
DUN_QJS="${DUN_QJS:-}"
DUN_JSC="${DUN_JSC:-}"
DUN_V8="${DUN_V8:-}"

[ -z "$DUN_QJS" ] && [ -f /tmp/dun-quickjs ] && DUN_QJS="/tmp/dun-quickjs"
[ -z "$DUN_JSC" ] && [ -f /tmp/dun-jsc ] && DUN_JSC="/tmp/dun-jsc"
[ -z "$DUN_V8" ] && [ -f /tmp/dun-v8 ] && DUN_V8="/tmp/dun-v8"

[ -n "$DUN_QJS" ] && RT_CMD[dun-quickjs]="$DUN_QJS run --allow-all" && RT_VER[dun-quickjs]="DunJS QuickJS"
[ -n "$DUN_JSC" ] && RT_CMD[dun-jsc]="$DUN_JSC run --allow-all" && RT_VER[dun-jsc]="DunJS JSC"
[ -n "$DUN_V8" ] && RT_CMD[dun-v8]="$DUN_V8 run --allow-all" && RT_VER[dun-v8]="DunJS V8"

echo "Detected runtimes:"
for rt in "${!RT_VER[@]}"; do
    echo "  $rt: ${RT_VER[$rt]}"
done
echo ""

run_bench() {
    local rt_name="$1"
    local bench_file="$2"
    local out_file="$3"
    local cmd="${RT_CMD[$rt_name]}"

    echo "  Running $rt_name..."
    if timeout 300 bash -c "$cmd '$bench_file'" > "$out_file" 2>&1; then
        return 0
    else
        echo "  $rt_name: FAILED (exit $?)" >> "$out_file"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# 1. Feature Benchmarks (25 tests)
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════"
echo "  1. Feature Benchmarks (25 tests)"
echo "═══════════════════════════════════════"
echo ""

for rt in node bun deno dun-quickjs dun-jsc dun-v8; do
    [ -z "${RT_CMD[$rt]:-}" ] && continue
    run_bench "$rt" "$BENCH" "$RESULTS_DIR/feature_${rt}.txt"
    # Extract summary line
    grep -E "Summary|benchmarks|throughput" "$RESULTS_DIR/feature_${rt}.txt" 2>/dev/null | head -3
    echo ""
done

# ═══════════════════════════════════════════════════════════════
# 2. Framework Benchmarks (39 tests)
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════"
echo "  2. Framework Benchmarks (39 tests)"
echo "═══════════════════════════════════════"
echo ""

for rt in node bun deno dun-quickjs dun-jsc dun-v8; do
    [ -z "${RT_CMD[$rt]:-}" ] && continue
    run_bench "$rt" "$FRAMEWORK" "$RESULTS_DIR/framework_${rt}.txt"
    grep -E "Summary|benchmarks|throughput" "$RESULTS_DIR/framework_${rt}.txt" 2>/dev/null | head -3
    echo ""
done

# ═══════════════════════════════════════════════════════════════
# 3. npm Compat Test (145 assertions)
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════"
echo "  3. npm Compat Test (145 assertions)"
echo "═══════════════════════════════════════"
echo ""

for rt in node bun deno dun-quickjs dun-jsc dun-v8; do
    [ -z "${RT_CMD[$rt]:-}" ] && continue
    run_bench "$rt" "$COMPAT" "$RESULTS_DIR/compat_${rt}.txt"
    grep -E "PASS|FAIL|pass|fail|assertions" "$RESULTS_DIR/compat_${rt}.txt" 2>/dev/null | tail -3
    echo ""
done

# ═══════════════════════════════════════════════════════════════
# 4. Stress Test (240 tests)
# ═══════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════"
echo "  4. Stress Test (240 tests)"
echo "═══════════════════════════════════════"
echo ""

for rt in node bun deno dun-quickjs dun-jsc dun-v8; do
    [ -z "${RT_CMD[$rt]:-}" ] && continue
    echo "  Running $rt... (may take ~2min)"
    timeout 300 bash -c "${RT_CMD[$rt]} '$STRESS'" > "$RESULTS_DIR/stress_${rt}.txt" 2>&1 || true
    PASS=$(grep -c "^PASS:" "$RESULTS_DIR/stress_${rt}.txt" 2>/dev/null || echo 0)
    FAIL=$(grep -c "^FAIL:" "$RESULTS_DIR/stress_${rt}.txt" 2>/dev/null || echo 0)
    echo "  $rt: $PASS pass / $FAIL fail"
    echo ""
done

# ═══════════════════════════════════════════════════════════════
# Summary Table
# ═══════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════"
echo ""

printf "%-15s %12s %12s %12s %12s\n" "Runtime" "Feature" "Framework" "Compat" "Stress"
printf "%-15s %12s %12s %12s %12s\n" "───────────" "──────────" "──────────" "──────────" "──────────"

for rt in node bun deno dun-quickjs dun-jsc dun-v8; do
    [ -z "${RT_CMD[$rt]:-}" ] && continue

    feat_ops=$(grep -oP '\d+(?=\.\d+[MK] ops)' "$RESULTS_DIR/feature_${rt}.txt" 2>/dev/null | tail -1 || echo "?")
    feat_summary=$(grep "throughput" "$RESULTS_DIR/feature_${rt}.txt" 2>/dev/null | grep -oP '[\d.]+[MK]? ops/sec' || echo "?")

    fw_summary=$(grep "throughput" "$RESULTS_DIR/framework_${rt}.txt" 2>/dev/null | grep -oP '[\d.]+[MK]? ops/sec' || echo "?")

    compat=$(grep -oP '\d+/\d+' "$RESULTS_DIR/compat_${rt}.txt" 2>/dev/null | tail -1 || echo "?")

    stress_pass=$(grep -c "^PASS:" "$RESULTS_DIR/stress_${rt}.txt" 2>/dev/null || echo "?")
    stress_total="240"

    printf "%-15s %12s %12s %12s %12s\n" "$rt" "$feat_summary" "$fw_summary" "$compat" "$stress_pass/$stress_total"
done

echo ""
echo "Results saved to: $RESULTS_DIR/"
echo "Done."
