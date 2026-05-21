// Test: FFI linkage audit — verify symbol mangling across ABI boundaries
// Tests extern(C), extern(C++), extern(C++, ns), and extern(D) linkages
// Compile with: ldc2 -c -vcolumns test_ffi_linkage.d
// Check symbols: nm test_ffi_linkage.o | grep -E "T |U "

module tools.bindgen_tests.test_ffi_linkage;

// 1. extern(C) — flat C symbol names
extern(C) nothrow @nogc
{
    int c_add(int a, int b) { return a + b; }
    void c_noop() {}
}

// 2. extern(C++) — C++ mangled symbols (no namespace)
extern(C++) nothrow @nogc
{
    int cpp_add(int a, int b) { return a + b; }
    double cpp_mul(double x, double y) { return x * y; }
}

// 3. extern(C++, namespace) — C++ mangled in namespace
extern(C++, "dun") nothrow @nogc
{
    int ns_func(int x) { return x * 2; }
}

// 4. extern(C++, nested namespace)
extern(C++, "dun", "engine") nothrow @nogc
{
    int nested_func(int x) { return x + 1; }
}

// 5. extern(C++, class) struct — C++ class ABI
extern(C++, "dun") extern(C++, class) struct TestWidget {
    int x;
    int y;
    @disable this();
    this(int x, int y) @nogc nothrow { this.x = x; this.y = y; }
    int area() @nogc nothrow { return x * y; }
}

// 6. extern(D) — default D mangling
int d_add(int a, int b) { return a + b; }

// 7. D ↔ C++ TMP FFI via pragma(mangle) — bind D to explicit C++ template
// instantiations like `v8shim::TypedCounter<0>::increment()`.
// extern(C++, "ns") alone can't express template arguments, so we spell
// the full Itanium-mangled symbol via pragma(mangle). The C++ side must
// explicitly instantiate the template (`template class TypedCounter<0>;`)
// so the symbol exists at link time. This is the canonical pattern for
// any C++ TMP API — cppgc::MakeGarbageCollected<T>, JSC::Heap::allocate<T>,
// std::vector<T>::push_back, etc.
extern(C++) nothrow @nogc
{
    pragma(mangle, "_ZN6v8shim12TypedCounterILi0EE9incrementEv")
    int tmp_counter0_increment();
    pragma(mangle, "_ZN6v8shim12TypedCounterILi1EE9incrementEv")
    int tmp_counter1_increment();
}

// Static assertions for size/alignment across ABI
static assert(TestWidget.sizeof == 8, "TestWidget should be 8 bytes (2 x int)");
static assert(TestWidget.alignof == 4, "TestWidget should be 4-byte aligned");
