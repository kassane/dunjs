module dun.engine.v8.cppbindings;

// D → V8 C++ bindings using extern(C++, "v8").
//
// Generated/verified via:
//   clang -Xclang -ast-dump=json -fsyntax-only -std=c++17 \
//         -I vendor/v8/include vendor/v8shim/v8shim.cpp | c++filt
//
// V8 (Node 22.15.0, V8 12.x) exposes ~80 public classes in namespace v8.
// D's extern(C++) can bind static methods and non-template classes.
// Template types (Local<T>, Global<T>, Maybe<T>, MaybeLocal<T>) require
// the C shim (vendor/v8shim/).
//
// core.stdcpp (LDC 1.42+):
//   ✅ string, string_view, memory (unique_ptr), allocator — GNU/LLVM
//   ❌ vector — MSVC only
//
// Bindable from D (static methods, no template params):
//   v8::V8, v8::Isolate, v8::HandleScope, v8::Boolean, v8::Exception,
//   v8::JSON, v8::Locker, v8::MicrotasksScope, v8::Platform, v8::Unwinder,
//   v8::ScriptCompiler, v8::StackTrace, v8::TryCatch
//
// NOT bindable (template return types like Local<T>, MaybeLocal<T>):
//   Most New()/Cast() statics return Local<T> — can't be received in D.
//   Only static methods returning void, bool, int, const char* are usable.

version (EngineV8):

extern (C++, "v8")
{
    // v8::V8 — engine lifecycle (all statics, no templates in signatures)
    extern class V8
    {
    static:
        void SetSnapshotDataBlob(void* startup_data);
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
        bool EnableWebAssemblyTrapHandler(bool use_v8_signal_handler);
    }

    // v8::Isolate — partial binding (statics only)
    extern class Isolate
    {
        struct CreateParams
        {
            void* array_buffer_allocator;
        }

    static:
        Isolate New(ref CreateParams params);
        Isolate GetCurrent();
        Isolate TryGetCurrent();
        uint GetNumberOfDataSlots();
    }

    // v8::HandleScope — static helpers
    extern class HandleScope
    {
    static:
        int NumberOfHandles(Isolate isolate);
    }

    // v8::Locker
    extern class Locker
    {
    static:
        bool IsLocked(Isolate isolate);
    }

    // v8::MicrotasksScope
    extern class MicrotasksScope
    {
    static:
        int GetCurrentDepth(Isolate isolate);
        bool IsRunningMicrotasks(Isolate isolate);
    }

    // v8::Platform — base class, one usable static
    extern class Platform
    {
    static:
        double SystemClockTimeMillis();
    }

    // v8::Unwinder — stack unwinding
    extern class Unwinder
    {
    static:
        bool PCIsInV8(size_t code_pages_length, void* code_pages, void* pc);
    }

    // v8::ResourceConstraints — isolate memory/stack configuration
    extern class ResourceConstraints
    {
    extern (D):
        void set_max_old_generation_size_in_bytes(size_t limit);
        void set_max_young_generation_size_in_bytes(size_t limit);
        void set_initial_old_generation_size_in_bytes(size_t initial_size);
        void set_initial_young_generation_size_in_bytes(size_t initial_size);
        void set_stack_limit(uint* value);
        size_t max_old_generation_size_in_bytes() const;
        size_t max_young_generation_size_in_bytes() const;
        size_t initial_old_generation_size_in_bytes() const;
        size_t initial_young_generation_size_in_bytes() const;
    }

    // v8::ScriptOriginOptions — flags for script origin
    extern class ScriptOriginOptions
    {
    extern (D):
        bool IsSharedCrossOrigin() const;
        bool IsOpaque() const;
        bool IsWasm() const;
        bool IsModule() const;
        int Flags() const;
    }

    // v8::HeapStatistics — heap memory info (all instance getters)
    extern class HeapStatistics
    {
    extern (D):
        size_t total_heap_size();
        size_t total_heap_size_executable();
        size_t total_physical_size();
        size_t total_available_size();
        size_t total_global_handles_size();
        size_t used_global_handles_size();
        size_t used_heap_size();
        size_t heap_size_limit();
        size_t malloced_memory();
        size_t external_memory();
        size_t peak_malloced_memory();
        size_t number_of_native_contexts();
        size_t number_of_detached_contexts();
    }
}

// v8::platform — factory functions
extern (C++, "v8", "platform")
{
    void* NewDefaultPlatform(int thread_pool_size = 0);
}

// C shim (for everything that touches Local<T>/Global<T>/Maybe<T>)
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
        static assert(is(typeof(&V8.SetFlagsFromString)));
        static assert(is(typeof(&V8.InitializePlatform)));
        static assert(is(typeof(&V8.DisposePlatform)));
    }
}
