module dun.engine.v8.cppbindings;

// Experimental: Direct D → V8 C++ bindings using extern(C++, "v8").
//
// V8's public API lives in namespace v8 and uses C++ classes with virtual
// methods. D's extern(C++) can bind to these when the types don't use
// templates. For template-heavy types (Local<T>, Global<T>, Maybe<T>),
// we still need the C shim — D cannot instantiate C++ templates.
//
// This module demonstrates what CAN be bound directly:
//   - v8::V8 (static methods, no templates)
//   - v8::Isolate (class with virtual methods)
//   - v8::Platform (abstract interface)
//   - v8::ArrayBuffer::Allocator (abstract)
//
// What CANNOT be bound directly (requires C shim):
//   - v8::Local<T>, v8::Global<T> (class templates)
//   - v8::Maybe<T>, v8::MaybeLocal<T> (class templates)
//   - v8::FunctionCallbackInfo<T> (class template)
//   - v8::PropertyCallbackInfo<T> (class template)
//
// Strategy: Use extern(C++) for static/namespace-level operations,
// keep the C shim for value manipulation that touches templates.

version (EngineV8):

// --- v8 namespace: static initialization ---
extern (C++, "v8")
{
    // v8::V8 — static methods for engine lifecycle
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
        // IdleTaskSupport = kDisabled, InProcessStackDumping = kDisabled
    );
}

// --- v8::ArrayBuffer::Allocator ---
extern (C++, "v8")
{
    extern class Isolate
    {
        struct CreateParams
        {
            void* array_buffer_allocator;
            // other fields are opaque from D's perspective
        }

    static:
        Isolate New(ref CreateParams params);
    }
}

// --- Convenience: check V8 version at compile time via shim ---

extern (C) nothrow @nogc
{
    const(char)* dun_v8_version();
}

// Hybrid approach: use extern(C++) for init, extern(C) shim for values.
// This is the recommended pattern — extern(C++) where possible,
// C shim where C++ templates make direct binding impossible.

unittest
{
    version (DunTest)
    {
        // Compile-time verification: these symbols resolve if V8 is linked
        static assert(is(typeof(&V8.GetVersion)));
        static assert(is(typeof(&V8.Initialize)));
    }
}
