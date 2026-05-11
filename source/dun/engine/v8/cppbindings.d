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

unittest
{
    version (DunTest)
    {
        static assert(is(typeof(&V8.GetVersion)));
        static assert(is(typeof(&V8.Initialize)));
        static assert(is(typeof(&V8.Dispose)));
    }
}
