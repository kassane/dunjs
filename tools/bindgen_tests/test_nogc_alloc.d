// Test: @nogc class allocation via manual malloc
// Pattern from numem/clib: allocate D classes without GC

module tools.bindgen_tests.test_nogc_alloc;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memcpy;

extern(C++, class) class Widget {
    int x;
    int y;
    this(int x, int y) @nogc nothrow { this.x = x; this.y = y; }
    float area() @nogc nothrow { return cast(float)(x * y); }
}

// @nogc class allocation: malloc + classInstanceSize + initSymbol + manual ctor
T nogcNew(T, Args...)(auto ref Args args) @trusted @nogc nothrow
{
    enum isize = __traits(classInstanceSize, T);
    auto chunk = malloc(isize);
    if (chunk is null) return null;

    // Copy init bytes (vtable + default field values)
    auto initSym = __traits(initSymbol, T);
    memcpy(chunk, initSym.ptr, isize);

    auto obj = cast(T) chunk;
    // Call constructor if it exists
    static if (__traits(hasMember, T, "__ctor"))
        obj.__ctor(args);

    return obj;
}

void nogcDelete(T)(T obj) @trusted @nogc nothrow
{
    if (obj is null) return;
    // Call destructor if it exists
    static if (__traits(hasMember, T, "__dtor"))
        obj.__dtor();
    free(cast(void*) obj);
}

// RAII wrapper with scope(exit)
struct Scoped(T)
{
    T obj;
    alias this = obj;

    static Scoped opCall(Args...)(auto ref Args args) @trusted @nogc nothrow
    {
        Scoped s;
        s.obj = nogcNew!T(args);
        return s;
    }

    ~this() @trusted @nogc nothrow
    {
        nogcDelete(obj);
        obj = null;
    }

    @disable this(this);
}

void main()
{
    import core.stdc.stdio : printf;

    // Test 1: Manual @nogc allocation
    auto w = nogcNew!Widget(10, 20);
    assert(w !is null, "nogcNew returned null");
    assert(w.x == 10);
    assert(w.y == 20);
    assert(w.area() == 200.0f);
    printf("Test 1 PASS: @nogc alloc Widget(%d, %d) area=%.0f\n", w.x, w.y, w.area());
    nogcDelete(w);

    // Test 2: classInstanceSize
    enum wSize = __traits(classInstanceSize, Widget);
    static assert(wSize > 0, "classInstanceSize must be positive");
    printf("Test 2 PASS: classInstanceSize(Widget) = %zu\n", wSize);

    // Test 3: initSymbol
    auto initSym = __traits(initSymbol, Widget);
    assert(initSym.ptr !is null, "initSymbol must not be null");
    printf("Test 3 PASS: initSymbol(Widget) ptr=%p len=%zu\n", initSym.ptr, initSym.length);

    // Test 4: Scoped RAII
    {
        auto s = Scoped!Widget(5, 7);
        assert(s.obj !is null);
        assert(s.obj.x == 5);
        assert(s.obj.y == 7);
        printf("Test 4 PASS: Scoped!Widget(%d, %d) area=%.0f\n", s.obj.x, s.obj.y, s.obj.area());
    } // auto-freed here

    printf("All @nogc allocation tests passed!\n");
}
