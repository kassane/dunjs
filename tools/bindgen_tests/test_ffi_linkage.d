// Test: FFI linkage audit — verify symbol mangling across ABI boundaries
// Tests extern(C), extern(C++), extern(C++, ns), and extern(D) linkages
// Compile with: ldc2 -c -vcolumns test_ffi_linkage.d
// Check symbols: nm test_ffi_linkage.o | grep -E "T |U "

module tools.bindgen_tests.test_ffi_linkage;

// `pragma(inline, false)` on the bodies below: this file's purpose is
// to LET `nm` inspect the mangled symbols. Without the pragma, LDC at
// -O3 + ThinLTO may inline trivial bodies (e.g. `return a + b`) and
// elide the symbol entirely — defeating the test. Verified at LDC
// 1.42 the symbols ARE emitted even without the pragma, but it's a
// defensive measure against future LDC versions where the optimizer
// gets more aggressive about leaf-function elision.

// 1. extern(C) — flat C symbol names
extern(C) nothrow @nogc
{
    pragma(inline, false) int c_add(int a, int b) { return a + b; }
    pragma(inline, false) void c_noop() {}
}

// 2. extern(C++) — C++ mangled symbols (no namespace)
extern(C++) nothrow @nogc
{
    pragma(inline, false) int cpp_add(int a, int b) { return a + b; }
    pragma(inline, false) double cpp_mul(double x, double y) { return x * y; }
}

// 3. extern(C++, namespace) — C++ mangled in namespace
extern(C++, "dun") nothrow @nogc
{
    pragma(inline, false) int ns_func(int x) { return x * 2; }
}

// 4. extern(C++, nested namespace)
extern(C++, "dun", "engine") nothrow @nogc
{
    pragma(inline, false) int nested_func(int x) { return x + 1; }
}

// 5. extern(C++, class) struct — C++ class ABI
extern(C++, "dun") extern(C++, class) struct TestWidget {
    int x;
    int y;
    @disable this();
    pragma(inline, false) this(int x, int y) @nogc nothrow { this.x = x; this.y = y; }
    pragma(inline, false) int area() @nogc nothrow { return x * y; }
}

// 6. extern(D) — default D mangling
pragma(inline, false) int d_add(int a, int b) { return a + b; }

// 7a. D ↔ C++ TMP FFI via NATIVE D TEMPLATE SYNTAX — the preferred form.
// D's `extern(C++, class) struct Name(int Slot)` auto-mangles to the
// Itanium template-instantiation symbol (e.g.
// `_ZN6v8shim12TypedCounterILi0EE9incrementEv`). The C++ side must
// explicitly instantiate (`template class TypedCounter<0>;`) so the
// symbol exists at link time. Verified end-to-end: counters at
// vendor/v8shim/v8shim.cpp, D bindings at engine/v8/cppbindings.d.
//
// IMPORTANT type-system mapping:
//   - C++ class/struct are VALUE types
//   - D struct is a VALUE type — use this for extern(C++, class) struct
//   - D class is a REFERENCE type — would mismatch the C++ ABI
//   - D has no private members, only module-level access
extern(C++, "v8shim")
{
    extern(C++, class) struct TmpCounter(int Slot)
    {
        static int increment() nothrow @nogc;
        static int read() nothrow @nogc;
    }
    alias TmpCounter0 = TmpCounter!0;
    alias TmpCounter1 = TmpCounter!1;
}

// 7b. D ↔ C++ TMP FFI via pragma(mangle) — fallback when D's TMP can't
// express the C++ template signature (overloads, defaulted args,
// SFINAE constraints, partial specializations). Spell the full Itanium
// mangled symbol literally. Useful for one-off bindings like
// cppgc::MakeGarbageCollected<T> wrappers where only one T is needed.
extern(C++) nothrow @nogc
{
    pragma(mangle, "_ZN6v8shim12TypedCounterILi0EE4readEv")
    int tmp_counter0_read_via_pragma();
}

// Static assertions for size/alignment across ABI
static assert(TestWidget.sizeof == 8, "TestWidget should be 8 bytes (2 x int)");
static assert(TestWidget.alignof == 4, "TestWidget should be 4-byte aligned");
