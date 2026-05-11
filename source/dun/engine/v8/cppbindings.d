module dun.engine.v8.cppbindings;

// D → V8 C++ bindings using extern(C++, "v8") + core.stdcpp.
//
// V8's public API uses C++ classes in namespace v8. D's extern(C++) can
// bind to non-template classes and static methods.
//
// For template-heavy types (Local<T>, Global<T>, Maybe<T>, MaybeLocal<T>),
// D cannot instantiate C++ templates — the C shim (vendor/v8shim/) handles
// those via extern "C" wrapper functions.
//
// core.stdcpp availability (LDC 1.42+):
//   ✅ core.stdcpp.string       — std::string (GNU + LLVM runtimes)
//   ✅ core.stdcpp.string_view  — std::string_view
//   ✅ core.stdcpp.memory       — std::unique_ptr<T>
//   ✅ core.stdcpp.allocator    — std::allocator<T>
//   ❌ core.stdcpp.vector       — MSVC only, not usable on Linux/macOS
//
// Strategy: extern(C++) for static/class-level operations (V8::Initialize,
// V8::GetVersion, platform creation). C shim for value manipulation that
// touches templates (Local<T>, Global<T>, FunctionCallbackInfo<T>).
//
// To regenerate/verify these bindings against a specific V8 version:
//   clang -Xclang -ast-dump -fsyntax-only -std=c++17 \
//         -I vendor/v8/include vendor/v8shim/v8shim.cpp 2>/dev/null | \
//         c++filt | grep -E '(CXXRecordDecl|CXXMethodDecl).*v8::'

version (EngineV8):

// --- v8 namespace: static initialization ---
extern (C++, "v8")
{
    extern class V8
    {
    static:
        int GetCurrentPlatform();
        void InitializePlatform(void* platform);
        bool Initialize();
        void InitializeICUDefaultLocation(const(char)* exec_path);
        bool InitializeICU(const(char)* icu_data_file = null);
        void InitializeExternalStartupData(const(char)* directory_path);
        bool Dispose();
        void SetFlagsFromString(const(char)* str, size_t length);
        void SetFlagsFromCommandLine(int* argc, char** argv, bool remove_flags);
        const(char)* GetVersion();
    }
}

// --- v8::platform namespace ---
extern (C++, "v8", "platform")
{
    void* NewDefaultPlatform(
        int thread_pool_size = 0,
    );
}

// --- v8::Isolate ---
extern (C++, "v8")
{
    extern class Isolate
    {
        struct CreateParams
        {
            void* array_buffer_allocator;
        }

    static:
        Isolate New(ref CreateParams params);
    }
}

// --- C shim functions (for template-heavy V8 APIs) ---
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
    }
}
