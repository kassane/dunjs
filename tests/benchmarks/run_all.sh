#!/bin/bash
# Cross-runtime benchmark comparison
# Usage: bash tests/benchmarks/run_all.sh
#
# Requires: dun (quickjs+jsc built), node, bun, deno in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH="$SCRIPT_DIR/feature_bench.js"
SQLITE="$SCRIPT_DIR/sqlite_bench.js"

echo "========================================="
echo "  DunJS Cross-Runtime Benchmark Suite"
echo "========================================="
echo ""

# Detect available runtimes
RUNTIMES=""
command -v node >/dev/null 2>&1 && RUNTIMES="$RUNTIMES node" && echo "Node.js: $(node --version)"
command -v bun >/dev/null 2>&1 && RUNTIMES="$RUNTIMES bun" && echo "Bun:     $(bun --version)"
command -v deno >/dev/null 2>&1 && RUNTIMES="$RUNTIMES deno" && echo "Deno:    $(deno --version | head -1)"

DUN_QJS=""
DUN_JSC=""
if [ -f "$SCRIPT_DIR/../../build/dun" ]; then
    echo "DunJS:   $(file "$SCRIPT_DIR/../../build/dun" | grep -o 'ELF.*' | head -c 40)"
fi

echo ""
echo "=== Feature Benchmarks (25 tests) ==="
echo ""

for rt in $RUNTIMES; do
    echo "--- $rt ---"
    case $rt in
        node) node "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput" ;;
        bun)  bun run "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput" ;;
        deno) deno run --allow-all --unstable-detect-cjs "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput" ;;
    esac
    echo ""
done

if [ -f "$SCRIPT_DIR/../../build/dun" ]; then
    DUN="$SCRIPT_DIR/../../build/dun"

    echo "--- DunJS (default GC: minPoolSize:16) ---"
    "$DUN" "--DRT-gcopt=profile:1" run --allow-all "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput|GC summary"
    echo ""

    echo "--- DunJS (minPoolSize:32) ---"
    "$DUN" "--DRT-gcopt=profile:1 minPoolSize:32" run --allow-all "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput|GC summary"
    echo ""

    echo "--- DunJS (precise GC) ---"
    "$DUN" "--DRT-gcopt=profile:1 gc:precise minPoolSize:16" run --allow-all "$BENCH" 2>&1 | grep -E "Summary|benchmarks|throughput|GC summary"
    echo ""
fi

echo ""
echo "=== SQLite Benchmarks ==="
echo ""

if [ -f "$SCRIPT_DIR/../../build/dun" ]; then
    DUN="$SCRIPT_DIR/../../build/dun"
    echo "--- DunJS ---"
    "$DUN" run --allow-all "$SQLITE" 2>&1
    echo ""
fi

echo "Done."
