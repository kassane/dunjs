module dun.engine.v8.cppbindings;

/// V8 value type tag — ordinals must match dun::V8Tag in v8shim_tmpl.hpp.
enum V8TypeTag
{
    Undefined,
    Null,
    Bool,
    Int,
    Number,
    String,
    Object,
    Array,
    Function,
}

// Must match C++ V8TagCount (9) in v8shim_tmpl.hpp
static assert(__traits(allMembers, V8TypeTag).length == 9,
    "V8TypeTag member count changed -- update V8TypeChecks table and V8TypeName template");

// Must match C++ V8Tag enum ordinals
static assert(V8TypeTag.Undefined == 0 && V8TypeTag.Function == 8,
    "V8TypeTag ordinals drift -- must match C++ dun::V8Tag");

// FFI pointer size guarantee (must match C++ static_assert in v8shim.h)
static assert((void*).sizeof == size_t.sizeof,
    "pointer/size_t size mismatch for C FFI");

/// V8TypeTag → C shim function name suffix.
template V8TypeName(V8TypeTag tag)
{
    static if (tag == V8TypeTag.Undefined) enum V8TypeName = "undefined";
    else static if (tag == V8TypeTag.Null) enum V8TypeName = "null";
    else static if (tag == V8TypeTag.Bool) enum V8TypeName = "bool";
    else static if (tag == V8TypeTag.Int) enum V8TypeName = "int";
    else static if (tag == V8TypeTag.Number) enum V8TypeName = "number";
    else static if (tag == V8TypeTag.String) enum V8TypeName = "string";
    else static if (tag == V8TypeTag.Object) enum V8TypeName = "object";
    else static if (tag == V8TypeTag.Array) enum V8TypeName = "array";
    else static if (tag == V8TypeTag.Function) enum V8TypeName = "function";
}

/// Type-check dispatch table (dun_v8_value_is_xxx function pointers).
struct V8TypeChecks
{
    import dun.engine.v8.bindings;

    alias CheckFn = extern (C) int function(DunV8Value*) nothrow @nogc;
    CheckFn[V8TypeTag.max + 1] table;

    static V8TypeChecks init() @trusted nothrow @nogc
    {
        V8TypeChecks tc;
        tc.table[V8TypeTag.Undefined] = &dun_v8_value_is_undefined;
        tc.table[V8TypeTag.Null] = &dun_v8_value_is_null;
        tc.table[V8TypeTag.Bool] = &dun_v8_value_is_bool;
        tc.table[V8TypeTag.Int] = &dun_v8_value_is_int;
        tc.table[V8TypeTag.Number] = &dun_v8_value_is_number;
        tc.table[V8TypeTag.String] = &dun_v8_value_is_string;
        tc.table[V8TypeTag.Object] = &dun_v8_value_is_object;
        tc.table[V8TypeTag.Array] = &dun_v8_value_is_array;
        tc.table[V8TypeTag.Function] = &dun_v8_value_is_function;
        return tc;
    }

    bool check(V8TypeTag tag, DunV8Value* val) @trusted nothrow @nogc
    {
        assert(cast(size_t) tag <= V8TypeTag.max, "V8TypeTag out of range");
        assert(val !is null, "Null DunV8Value in V8TypeChecks.check");
        return table[tag](val) != 0;
    }
}

unittest
{
    // Verify TMP name mapping covers all tags
    static foreach (tag; __traits(allMembers, V8TypeTag))
    {{
        enum t = __traits(getMember, V8TypeTag, tag);
        static assert(V8TypeName!t.length > 0,
            "Missing V8TypeName for " ~ tag);
    }}
}

// Static-method-only C++ bindings (instance methods need V8 linkage).
version (EngineV8)
{
    // C++ `class V8` is a static-method-only namespace-like type
    // (no instance state, no vtable). The right D binding is
    // `extern(C++, class) struct` — value type, no Object overhead.
    // Using `extern class` would make it a D reference type that
    // we never instantiate — wastes a vtable slot + class init data.
    extern (C++, "v8")
    {
        extern (C++, class) struct V8
        {
        static:
            void SetFlagsFromString(const(char)* str, size_t length);
            void SetFlagsFromCommandLine(int* argc, char** argv, bool remove_flags);
            const(char)* GetVersion();
            bool Initialize();
            bool Dispose();
            bool InitializeICU(const(char)* icu_data_file = null);
            void InitializeICUDefaultLocation(const(char)* exec_path);
            void InitializeExternalStartupData(const(char)* directory_path);
            void InitializePlatform(void* platform);
            void DisposePlatform();
        }
    }

    extern (C++, "v8", "platform")
    {
        void* NewDefaultPlatform(int thread_pool_size = 0);
    }

    extern (C) nothrow @nogc
    {
        const(char)* dun_v8_version();
    }

    unittest
    {
        version (DunTest)
        {
            static assert(is(typeof(&V8.GetVersion)));
            static assert(is(typeof(&V8.Initialize)));
            static assert(is(typeof(&V8.Dispose)));
        }
    }
}
