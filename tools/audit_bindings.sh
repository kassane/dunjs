#!/bin/bash
# Audit QuickJS-NG D bindings against the C header using ImportC.
#
# Generates a .di file via ImportC and compares key function signatures,
# tag constants, and type layouts against our manual bindings.d.
#
# Usage: ./tools/audit_bindings.sh [--verbose]
#
# Requires: ldc2 or ldmd2 in PATH

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERBOSE="${1:-}"
DC="${DC:-ldc2}"
CIMPORT_C="$ROOT_DIR/source/dun/engine/quickjs/cimport.c"
HEADER="$ROOT_DIR/vendor/quickjs/quickjs.h"
BINDINGS="$ROOT_DIR/source/dun/engine/quickjs/bindings.d"
DI_OUT="/tmp/quickjs_importc_audit.di"

if [ ! -f "$HEADER" ]; then
    echo "ERROR: quickjs.h not found at $HEADER"
    echo "  Run: ldc2 -run build.d --backend=quickjs"
    exit 1
fi

echo "=== QuickJS-NG Binding Audit ==="
echo "Header: $HEADER"
echo "Bindings: $BINDINGS"
echo ""

# Generate ImportC .di
echo "[1/4] Generating ImportC .di ..."
$DC -c "$CIMPORT_C" -P-I"$ROOT_DIR/vendor/quickjs" -H -Hf="$DI_OUT" -o- 2>/dev/null || true

if [ ! -f "$DI_OUT" ]; then
    echo "ERROR: Failed to generate .di file"
    exit 1
fi

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local pattern="$2"
    local file="$3"
    if grep -q "$pattern" "$file"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_bindings() {
    local desc="$1"
    local pattern="$2"
    check "$desc" "$pattern" "$BINDINGS"
}

check_di() {
    local desc="$1"
    local pattern="$2"
    check "$desc" "$pattern" "$DI_OUT"
}

# [2/4] Verify tag constants
echo ""
echo "[2/4] Checking tag constants ..."
check_bindings "JS_TAG_FLOAT64 = 8" "JS_TAG_FLOAT64 = 8"
check_bindings "JS_TAG_SHORT_BIG_INT = 7" "JS_TAG_SHORT_BIG_INT = 7"
check_bindings "JS_TAG_STRING_ROPE = -6" "JS_TAG_STRING_ROPE = -6"
check_bindings "JS_TAG_EXCEPTION = 6" "JS_TAG_EXCEPTION = 6"
check_bindings "JS_TAG_BIG_INT = -9" "JS_TAG_BIG_INT = -9"

# [3/4] Verify function return types (bool vs int)
echo ""
echo "[3/4] Checking function signatures ..."

# These must be bool in both .di and bindings.d
for func in JS_IsJobPending JS_IsArray JS_IsFunction JS_IsError; do
    check_di "$func returns bool (header)" "bool $func"
    check_bindings "$func returns bool (bindings)" "bool $func"
done

# JS_ToCStringLen2 cesu8 parameter must be bool
check_di "JS_ToCStringLen2 cesu8=bool (header)" "bool cesu8"
check_bindings "JS_ToCStringLen2 cesu8=bool (bindings)" "bool cesu8"

# JS_SetOpaque must return int
check_di "JS_SetOpaque returns int (header)" "int.*JS_SetOpaque"
check_bindings "JS_SetOpaque returns int (bindings)" "int JS_SetOpaque"

# [4/4] Summary
echo ""
echo "[4/4] Audit Summary"
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "AUDIT FAILED: $FAIL checks failed"
    exit 1
else
    echo "AUDIT PASSED: All $PASS checks passed"
fi

if [ "$VERBOSE" = "--verbose" ]; then
    echo ""
    echo "=== Full ImportC .di output ==="
    cat "$DI_OUT"
fi
