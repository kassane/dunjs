// Test: --extern-std= flag controls C++ name mangling compatibility
// ldc2 -c --extern-std=c++17 test_extern_std.d
// ldc2 -c --extern-std=c++20 test_extern_std.d
// Compare symbols: different C++ standards may mangle differently

module tools.bindgen_tests.test_extern_std;

// C++17 features: nested namespaces, structured bindings semantics
extern(C++, "v8") nothrow @nogc
{
    struct Isolate;
    struct Context;
    struct Value;

    // Template function (mangling depends on --extern-std)
    extern(C++, class) struct HandleScope {
        @disable this();
        this(Isolate* isolate) @nogc nothrow {}
        ~this() @nogc nothrow {}
    }

    // Nested namespace (C++17 inline namespace support)
    extern(C++, "internal") {
        void* allocate_page(size_t size);
        void free_page(void* ptr);
    }

    // Static methods via extern(C++, class) — declared as struct
    // (value type) to match C++ class semantics. D `class` would
    // be a reference type with vtable, which mismatches the C++
    // class layout for static-method-only types. See research doc
    // §11.4 for the full type-system mapping.
    extern(C++, class) struct V8 {
    static:
        const(char)* GetVersion() @nogc nothrow;
        bool Initialize() @nogc nothrow;
        bool Dispose() @nogc nothrow;
    }
}

// D TMP that mirrors C++ TMP (cross-language template metaprogramming)
enum V8TypeTag : ubyte {
    Undefined = 0,
    Null,
    Boolean,
    Number,
    String,
    Object,
    Array,
    Function,
    Date,
}

// Compile-time tag -> name mapping (mirrors C++ V8TypeMap)
template V8TypeName(V8TypeTag tag) {
    static if (tag == V8TypeTag.Undefined) enum V8TypeName = "undefined";
    else static if (tag == V8TypeTag.Null) enum V8TypeName = "null";
    else static if (tag == V8TypeTag.Boolean) enum V8TypeName = "boolean";
    else static if (tag == V8TypeTag.Number) enum V8TypeName = "number";
    else static if (tag == V8TypeTag.String) enum V8TypeName = "string";
    else static if (tag == V8TypeTag.Object) enum V8TypeName = "object";
    else static if (tag == V8TypeTag.Array) enum V8TypeName = "array";
    else static if (tag == V8TypeTag.Function) enum V8TypeName = "function";
    else static if (tag == V8TypeTag.Date) enum V8TypeName = "date";
    else static assert(0, "Unknown V8TypeTag");
}

// Compile-time coverage test
static assert(V8TypeName!(V8TypeTag.Undefined) == "undefined");
static assert(V8TypeName!(V8TypeTag.Null) == "null");
static assert(V8TypeName!(V8TypeTag.Boolean) == "boolean");
static assert(V8TypeName!(V8TypeTag.Number) == "number");
static assert(V8TypeName!(V8TypeTag.String) == "string");
static assert(V8TypeName!(V8TypeTag.Object) == "object");
static assert(V8TypeName!(V8TypeTag.Array) == "array");
static assert(V8TypeName!(V8TypeTag.Function) == "function");
static assert(V8TypeName!(V8TypeTag.Date) == "date");

// Ensure enum covers all tags
static assert(__traits(allMembers, V8TypeTag).length == 9,
    "V8TypeTag must have exactly 9 members");
