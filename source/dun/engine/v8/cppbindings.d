module dun.engine.v8.cppbindings;

// D → V8 C++ bindings using extern(C++, "v8").
//
// Generated/verified via:
//   clang -Xclang -ast-dump=json -fsyntax-only -std=c++17 \
//         -I vendor/v8/include vendor/v8shim/v8shim.cpp | c++filt
//
// Only static-method classes are bound here — instance methods on extern
// C++ classes generate vtable entries that require linking against V8's
// C++ objects, which defeats the purpose of the C shim.
//
// Bindable (static methods, no vtable):
//   v8::V8 — engine lifecycle
//
// NOT bindable without V8 C++ objects:
//   v8::Isolate, v8::HandleScope, v8::HeapStatistics, etc.
//   (all have instance methods → vtable references → linker errors)
//
// Template return types (Local<T>, MaybeLocal<T>) can never be received
// in D — use the C shim (vendor/v8shim/) for all value operations.

version (EngineV8):

extern (C++, "v8")
{
    // v8::V8 — engine lifecycle (all statics, no vtable)
    extern class V8
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

// C shim handles everything else (Local<T>, Global<T>, value ops)
extern (C) nothrow @nogc
{
    const(char)* dun_v8_version();
}

// ---------------------------------------------------------------------------
// D TMP ↔ C++ TMP bridge pattern
//
// The C++ side (vendor/v8shim/v8shim_tmpl.hpp) uses template metaprogramming
// to eliminate boilerplate — withContext<F> wraps the Isolate::Scope /
// HandleScope / Context::Scope RAII pattern; V8TypeMap<Tag> maps tags to
// v8::Types at compile time; isV8Type<Tag> dispatches type checks via
// if constexpr.
//
// The D side mirrors this with compile-time features:
//   - enum V8TypeTag: matches C++ V8Tag enum for shared semantics
//   - V8TypeName template: maps tag → C shim function suffix (like V8TypeMap)
//   - static foreach: generates extern(C) declarations in bulk
//   - mixin template: creates type-safe wrapper structs from tag sequences
//
// Both sides resolve at compile time → zero runtime overhead.
// Adding a new V8 type requires:
//   1. C++: add enum value + template specialization + if constexpr case
//   2. D:   add enum value + V8TypeName entry → wrappers auto-generated
// ---------------------------------------------------------------------------

/// V8 value type tag — mirrors dun::V8Tag in v8shim_tmpl.hpp
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

/// Compile-time map: V8TypeTag → C shim function name suffix.
/// Mirrors C++ V8TypeMap<Tag> — both are compile-time dispatch tables.
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

/// Type-check function pointer table, generated via static foreach.
/// Each entry points to the corresponding dun_v8_value_is_xxx function.
/// This mirrors C++ isV8Type<Tag> — both are compile-time dispatch.
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
        tc.table[V8TypeTag.Number] = &dun_v8_value_is_number;
        tc.table[V8TypeTag.String] = &dun_v8_value_is_string;
        tc.table[V8TypeTag.Object] = &dun_v8_value_is_object;
        tc.table[V8TypeTag.Array] = &dun_v8_value_is_array;
        tc.table[V8TypeTag.Function] = &dun_v8_value_is_function;
        return tc;
    }

    bool check(V8TypeTag tag, DunV8Value* val) @trusted nothrow @nogc
    {
        return table[tag](val) != 0;
    }
}

unittest
{
    version (DunTest)
    {
        static assert(is(typeof(&V8.GetVersion)));
        static assert(is(typeof(&V8.Initialize)));
        static assert(is(typeof(&V8.Dispose)));

        // Verify TMP name mapping covers all tags
        static foreach (tag; __traits(allMembers, V8TypeTag))
        {{
            enum t = __traits(getMember, V8TypeTag, tag);
            static assert(V8TypeName!t.length > 0,
                "Missing V8TypeName for " ~ tag);
        }}

        // Verify function table can be initialized
        auto tc = V8TypeChecks.init();
        static assert(V8TypeChecks.table.length == V8TypeTag.max + 1);
    }
}
