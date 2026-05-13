#!/usr/bin/env bash
# Comprehensive bindgen test suite
# Tests all D compiler FFI features: -H, -HCf, ImportC, @nogc alloc,
# clang -ast-dump, and FFI linkage mangling
set -euo pipefail

export PATH="/opt/ldc2-1.42.0-linux-x86_64/bin:$PATH"
cd "$(dirname "$0")"

pass=0
fail=0
check() {
    if [ $? -eq 0 ]; then
        echo "PASS: $1"
        pass=$((pass+1))
    else
        echo "FAIL: $1"
        fail=$((fail+1))
    fi
}

echo "=== D Compiler Bindgen Test Suite ==="
echo ""

# Test 1: -HCf (D → C++ header)
echo "--- Test 1: -HCf (D → C++ header) ---"
rm -f test_hcf.hpp test_hcf.o
ldc2 -HCf=test_hcf.hpp -c test_hcf.d 2>/dev/null
[ -f test_hcf.hpp ] && grep -q "namespace Foo" test_hcf.hpp
check "-HCf generates C++ header with namespaces"
grep -q "class Test1 final" test_hcf.hpp 2>/dev/null
check "-HCf generates C++ class with @disable->delete"
grep -q "virtual float foo();" test_hcf.hpp 2>/dev/null
check "-HCf generates virtual methods"
grep -q "class Test4 : public Test2" test_hcf.hpp 2>/dev/null
check "-HCf generates inheritance"
grep -q 'extern "C"' test_hcf.hpp 2>/dev/null
check "-HCf generates extern C functions"

# Test 2: -H with D source (.di generation)
echo ""
echo "--- Test 2: -H (D → .di interface) ---"
rm -f test_h.di test_h.o
ldc2 -H -Hf=test_h.di -c test_h.d 2>/dev/null
[ -f test_h.di ] && grep -q "extern (C)" test_h.di
check "-H generates .di interface"
grep -q "JSValue" test_h.di 2>/dev/null
check "-H preserves struct definitions"
grep -q "JS_NewInt32" test_h.di 2>/dev/null
check "-H preserves function declarations"

# Test 3: ImportC (.c → .di)
echo ""
echo "--- Test 3: ImportC (C source → .di) ---"
rm -f test_importc.di test_importc.o
ldc2 -H -Hf=test_importc.di -c test_importc.c 2>/dev/null
[ -f test_importc.di ] && grep -q "dun_v8_isolate_new" test_importc.di
check "ImportC generates D bindings from C source"
grep -q "DunV8NativeCallback" test_importc.di 2>/dev/null
check "ImportC handles function pointer typedefs"
grep -q 'const(char)\*' test_importc.di 2>/dev/null
check "ImportC maps const char* correctly"

# Test 4: @nogc class allocation
echo ""
echo "--- Test 4: @nogc class allocation ---"
rm -f test_nogc_alloc test_nogc_alloc.o
output=$(ldc2 -run test_nogc_alloc.d 2>&1)
echo "$output" | grep -q "Test 1 PASS"
check "@nogc alloc: manual malloc + classInstanceSize"
echo "$output" | grep -q "Test 2 PASS"
check "@nogc alloc: classInstanceSize > 0"
echo "$output" | grep -q "Test 3 PASS"
check "@nogc alloc: initSymbol valid"
echo "$output" | grep -q "Test 4 PASS"
check "@nogc alloc: Scoped RAII wrapper"

# Test 5: clang -ast-dump bindgen
echo ""
echo "--- Test 5: clang -ast-dump → D bindings ---"
if command -v clang >/dev/null 2>&1; then
    output=$(clang -Xclang -ast-dump=json -fsyntax-only test_ast_dump.hpp 2>/dev/null | python3 ast_to_d.py test_ast_dump.hpp 2>&1)
    echo "$output" | grep -q "struct DunV8Isolate;"
    check "clang AST: opaque struct detection"
    echo "$output" | grep -q "dun_v8_isolate_new"
    check "clang AST: function extraction"
    echo "$output" | grep -q "dun_v8_set_property"
    check "clang AST: property functions"
    echo "$output" | grep -q 'const(char)\*'
    check "clang AST: const char* mapping"

    # Test against real v8shim.h
    real_output=$(clang -Xclang -ast-dump=json -fsyntax-only ../../vendor/v8shim/v8shim.h 2>/dev/null | python3 ast_to_d.py v8shim.h 2>&1)
    func_count=$(echo "$real_output" | grep -c "^[a-zA-Z].*(" || true)
    [ "$func_count" -ge 40 ]
    check "clang AST: real v8shim.h extracts 40+ functions (got $func_count)"
else
    echo "SKIP: clang not available"
fi

# Test 6: FFI linkage audit
echo ""
echo "--- Test 6: FFI linkage / symbol mangling ---"
rm -f test_ffi_linkage.o
ldc2 -c test_ffi_linkage.d 2>/dev/null
[ -f test_ffi_linkage.o ]
check "FFI linkage: compiles"
nm test_ffi_linkage.o | grep -q "T c_add$"
check "FFI linkage: extern(C) flat symbol"
nm test_ffi_linkage.o | grep -q "T _Z7cpp_addii"
check "FFI linkage: extern(C++) mangled"
nm test_ffi_linkage.o | grep -q "T _ZN3dun7ns_funcEi"
check "FFI linkage: extern(C++, 'dun') namespace"
nm test_ffi_linkage.o | grep -q "T _ZN3dun6engine11nested_funcEi"
check "FFI linkage: extern(C++, 'dun', 'engine') nested ns"
nm test_ffi_linkage.o | grep -q "T _ZN3dun10TestWidget4areaEv"
check "FFI linkage: extern(C++, class) method"
nm test_ffi_linkage.o | grep -q "T _ZN3dun10TestWidgetC1Eii"
check "FFI linkage: extern(C++, class) constructor"

# Cleanup
rm -f test_hcf.hpp test_h.di test_importc.di test_ffi_linkage.o test_hcf.o test_h.o test_importc.o test_nogc_alloc.o

echo ""
echo "=== Bindgen Tests: $pass/$((pass+fail)) passed ==="
[ $fail -eq 0 ] && echo "All tests passed!" || echo "$fail FAILED"
exit $fail
