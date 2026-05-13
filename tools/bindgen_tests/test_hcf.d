// Test: ldc2 -HCf=test_hcf.hpp -c test_hcf.d
// Verifies D -> C++ header generation with extern(C++) annotations

extern (C++, "Foo", "TestNamespace") {
    extern(C++, class) struct Test1 {
        @disable this();
        this(int t) {}
        ~this() {}
    }

    extern(C++, class) class Test2 {
        this() {}
        ~this() {}
        float foo() { return 0.0; }
    }

    extern(C++) struct Test3(T, U) {
        this(float t) {}
        ~this() {}
    }

    extern(C++, class) class Test4 : Test2 {
        this() {}
        ~this() {}
        override float foo() { return 4.2; }
    }
}

extern(C++) alias MyType = Test3!(uint, double);

extern(C++) T square(T)(T num) {
    return num * num;
}
extern(C++) alias sqrt = square;

extern(C) int c_square(uint num) {
    return cast(int)(num * num);
}

extern(C) int Cmain() { return 0; }
extern(D) void main() { Cmain(); }
