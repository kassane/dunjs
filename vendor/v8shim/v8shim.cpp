// v8shim.cpp — extern "C" V8 wrapper (C++20).

#include "v8shim.h"

#include <v8.h>
#include <libplatform/libplatform.h>
#include <cassert>
#include <cstdlib>
#include <cstring>
#include <array>
#include <atomic>
#include <memory>
#ifdef __linux__
#include <unistd.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#elif defined(_WIN32)
#include <windows.h>
#endif
#include <span>
#include <string>
#include <mutex>

// V8 14.x: External::New/Value require ExternalPointerTypeTag parameter
#if V8_MAJOR_VERSION >= 14
#define DUN_EXTERNAL_NEW(iso, ptr) \
    v8::External::New(iso, ptr, v8::kExternalPointerTypeTagDefault)
#define DUN_EXTERNAL_VALUE(ext) \
    (ext)->Value(v8::kExternalPointerTypeTagDefault)
#else
#define DUN_EXTERNAL_NEW(iso, ptr) v8::External::New(iso, ptr)
#define DUN_EXTERNAL_VALUE(ext)    (ext)->Value()
#endif

static std::once_flag g_platform_flag;
static std::unique_ptr<v8::Platform> g_platform;

static void ensurePlatform() {
    std::call_once(g_platform_flag, [] {
        g_platform = v8::platform::NewDefaultPlatform();
        v8::V8::InitializePlatform(g_platform.get());
        // ICU must be initialized before V8::Initialize so Unicode property
        // escapes (`\p{L}`, etc.) work in regular expressions. Without
        // this V8 reports "Invalid property name in character class" for
        // any `/[\p{L}]/u` or `/[\p{L}]/v` regex, even though the build
        // links ICU.
        //
        // ICU data resolution (v15.0.112 i18n profile + earlier):
        //   1. Try `$DUN_ICU_DATA` env var (explicit override)
        //   2. Try `<exec_dir>/icudtl.dat` (libv8 i18n profile ships
        //      this file next to libv8_monolith.a; we copy it next to
        //      the `dun` binary at link time via dub's preBuildCommands)
        //   3. Fall back to `InitializeICU(nullptr)` — uses the i18n
        //      table embedded in libv8_monolith.a for default profile
        //      builds (covers Unicode property escapes; locale data
        //      will be English-only)
        const char* icu_env = std::getenv("DUN_ICU_DATA");
        bool icu_ok = false;
        if (icu_env && *icu_env) {
            icu_ok = v8::V8::InitializeICU(icu_env);
        }
        if (!icu_ok) {
            // Resolve the real executable path so
            // InitializeICUDefaultLocation can find `<exec_dir>/icudtl.dat`.
            // Cross-platform argv[0] discovery — V8's
            // InitializeICUDefaultLocation does `dirname(argv0) + /icudtl.dat`
            // so an empty argv0 makes it skip the search.
            char exe_path[4096] = {0};
#ifdef __linux__
            ssize_t n = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
            if (n > 0) exe_path[n] = '\0';
#elif defined(__APPLE__)
            uint32_t sz = sizeof(exe_path);
            _NSGetExecutablePath(exe_path, &sz);
#elif defined(_WIN32)
            GetModuleFileNameA(NULL, exe_path, sizeof(exe_path));
#endif
            if (exe_path[0]) {
                v8::V8::InitializeICUDefaultLocation(exe_path);
            } else {
                v8::V8::InitializeICUDefaultLocation("");
            }
            icu_ok = true;
        }
        v8::V8::Initialize();
    });
}

struct DunV8Isolate {
    v8::Isolate* isolate;
    v8::Isolate::CreateParams params;
};

struct DunV8Context {
    v8::Global<v8::Context> context;
    DunV8Isolate* isolate_wrapper;
    void* user_data;
    std::string last_exception;
};

struct DunV8Value {
    // Persistent slot — populated when this wrapper owns a v8 root
    // (i.e. created via wrapValue, or promoted from a borrowed wrap).
    v8::Global<v8::Value> value;
    // Borrowed Local — populated when this wrapper just lends a Local
    // from the surrounding HandleScope (the trampoline frame), to skip
    // the Persistent::Reset pair that dominates per-call FFI cost on
    // V8 native callbacks. Promoted to Persistent on first dupValue.
    v8::Local<v8::Value> borrowed_local;
    DunV8Isolate* isolate_wrapper;
    int ref_count;
    int is_borrowed;     // 0 = persistent, 1 = borrowed Local (no Reset)
};

// Read the live v8::Local for a wrapper, regardless of mode.
static inline v8::Local<v8::Value> getLocal(DunV8Value* vw, v8::Isolate* iso) {
    return vw->is_borrowed ? vw->borrowed_local : vw->value.Get(iso);
}

// Compile-time FFI safety: verify struct invariants
static_assert(std::is_standard_layout_v<DunV8Isolate>,
    "DunV8Isolate must be standard layout for C FFI");
static_assert(sizeof(DunV8Isolate*) == sizeof(void*),
    "opaque pointer size mismatch");
static_assert(sizeof(DunV8Context*) == sizeof(void*),
    "opaque pointer size mismatch");
static_assert(sizeof(DunV8Value*) == sizeof(void*),
    "opaque pointer size mismatch");
static_assert(sizeof(int) == 4, "int must be 32-bit for D interop");

// Value pool: reuse DunV8Value objects to avoid malloc/free per JS value.
// Thread-local fast path eliminates mutex contention in the common single-threaded case.
namespace {
constexpr size_t kValuePoolCapacity = 512;

struct ValuePool {
    DunV8Value* free_list[kValuePoolCapacity];
    size_t count = 0;

    DunV8Value* acquire() {
        if (count > 0)
            return free_list[--count];
        return new DunV8Value();
    }

    void release(DunV8Value* v) {
        // Caller is responsible for clearing v->value (owning) or
        // v->borrowed_local (borrowed) before calling. release() just
        // recycles the wrapper slot — the Persistent::Reset on borrowed
        // wraps was wasted (Persistent never written) and showed up as
        // the residual per-trampoline-arg cost after wrapBorrowed.
        if (count < kValuePoolCapacity)
            free_list[count++] = v;
        else
            delete v;
    }
};

static thread_local ValuePool g_value_pool;

// Allocation counters — used by v8shim::Diagnostics below. Atomic so a
// concurrent diagnostic read across worker threads is well-defined.
static std::atomic<size_t> g_alloc_count{0};
static std::atomic<size_t> g_release_count{0};
} // anon namespace

// Bind-via-extern(C++, "v8shim") demonstration. This class is what D
// code reaches via `extern(C++, "v8shim")` static-method declarations
// in source/dun/engine/v8/cppbindings.d — no extern "C" shim wrapper
// between them. Forces the Itanium ABI mangling path from D into a
// real production C++ class. See docs/research/custom-gc-v8-jsc.md
// §2.4½ for the FFI strategy rationale.
namespace v8shim {

class Diagnostics {
public:
    // Per-thread DunV8Value free-list depth (how many wrappers are
    // recyclable without hitting `new`).
    static size_t valuePoolFreeCount() noexcept;

    // Lifetime allocation counters (atomic, may be > 2^32 on long runs).
    static size_t totalAllocs() noexcept;
    static size_t totalReleases() noexcept;
    static size_t liveCount() noexcept;

    // Shim version string. Constant — no allocation, no copy.
    static const char* shimVersion() noexcept;

    // Sentinel value used by the FFI smoke test in
    // tests/integration/fixtures/v8shim_extern_cpp.js. Bumps every
    // call to verify the linkage actually invokes this method on
    // each call (not e.g. a constant inlined at the call site).
    static int probeBumpCounter() noexcept;
};

size_t Diagnostics::valuePoolFreeCount() noexcept {
    return g_value_pool.count;
}

size_t Diagnostics::totalAllocs() noexcept {
    return g_alloc_count.load(std::memory_order_relaxed);
}

size_t Diagnostics::totalReleases() noexcept {
    return g_release_count.load(std::memory_order_relaxed);
}

size_t Diagnostics::liveCount() noexcept {
    auto a = g_alloc_count.load(std::memory_order_relaxed);
    auto r = g_release_count.load(std::memory_order_relaxed);
    return a > r ? (a - r) : 0;
}

const char* Diagnostics::shimVersion() noexcept {
    return "v8shim-1.1.25";
}

int Diagnostics::probeBumpCounter() noexcept {
    static std::atomic<int> probe{0};
    return probe.fetch_add(1, std::memory_order_relaxed) + 1;
}

} // namespace v8shim

[[nodiscard]] static DunV8Value* wrapValue(DunV8Isolate* iw, v8::Local<v8::Value> val) {
    auto* wrapped = g_value_pool.acquire();
    wrapped->value.Reset(iw->isolate, val);
    wrapped->isolate_wrapper = iw;
    wrapped->ref_count = 1;
    wrapped->is_borrowed = 0;
    g_alloc_count.fetch_add(1, std::memory_order_relaxed);
    return wrapped;
}

// Cheap wrapper for values whose lifetime is bounded by the calling
// HandleScope — typically `info.This()` and `info[i]` inside a native
// trampoline. Skips Persistent::Reset (the dominant per-call FFI cost
// on V8 native callbacks). If the D-side later calls dupValue (= ref),
// we promote the borrowed Local to a real Persistent inside
// dun_v8_value_ref so it survives past the trampoline frame.
[[nodiscard]] static DunV8Value* wrapBorrowed(DunV8Isolate* iw, v8::Local<v8::Value> val) {
    auto* wrapped = g_value_pool.acquire();
    // pool.release() already Reset() the Persistent to empty; don't touch it.
    wrapped->borrowed_local = val;
    wrapped->isolate_wrapper = iw;
    wrapped->ref_count = 1;
    wrapped->is_borrowed = 1;
    return wrapped;
}

// TMP helpers — withContext<F>, withIsolate<F>, isV8Type<Tag>
#include "v8shim_tmpl.hpp"

// Internal template: type-check dispatch via isV8Type<Tag>
namespace {
template <dun::V8Tag Tag>
int valueIsType(DunV8Value* vw) {
    return dun::withIsolate(vw->isolate_wrapper, [&](auto isolate) -> int {
        return dun::isV8Type<Tag>(isolate, vw) ? 1 : 0;
    });
}
} // anon namespace

struct DunV8FunctionData {
    DunV8NativeCallback callback;
    DunV8Context* context;
    void* user_data;
    v8::Global<v8::External> prevent_gc;
};

static void functionDataweak(const v8::WeakCallbackInfo<DunV8FunctionData>& info) {
    auto* fd = info.GetParameter();
    fd->prevent_gc.Reset();
    delete fd;
}

static void v8FunctionTrampoline(const v8::FunctionCallbackInfo<v8::Value>& info) {
    auto* isolate = info.GetIsolate();
    v8::HandleScope handle_scope(isolate);

    auto external = v8::Local<v8::External>::Cast(info.Data());
    auto* fd = static_cast<DunV8FunctionData*>(DUN_EXTERNAL_VALUE(external));
    assert(fd && "trampoline: null FunctionData");
    assert(fd->callback && "trampoline: null callback");

    const int argc = info.Length();
    constexpr int kStackArgLimit = 16;
    std::array<DunV8Value*, kStackArgLimit> stack_argv{};
    std::unique_ptr<DunV8Value*[]> heap_argv;
    DunV8Value** argv;
    if (argc <= kStackArgLimit) {
        argv = stack_argv.data();
    } else {
        heap_argv = std::make_unique<DunV8Value*[]>(static_cast<size_t>(argc));
        argv = heap_argv.get();
    }
    // info.This() and info[i] are alive for the lifetime of this
    // HandleScope. Wrap them as borrowed Locals to skip the
    // Persistent::Reset pair per arg — the largest per-call cost on
    // the V8 native-callback path. If the D callback wants to keep
    // one past this frame it must call dupValue, which promotes to a
    // real Persistent inside dun_v8_value_ref.
    auto* iw = fd->context->isolate_wrapper;
    for (int i = 0; i < argc; i++)
        argv[i] = wrapBorrowed(iw, info[i]);

    DunV8Value* thisVal = wrapBorrowed(iw, info.This());

    DunV8Value* result = fd->callback(fd->context, thisVal,
        argc, argc > 0 ? argv : nullptr, fd->user_data);

    dun_v8_value_unref(thisVal);
    for (int i = 0; i < argc; i++)
        dun_v8_value_unref(argv[i]);

    if (result) {
        info.GetReturnValue().Set(getLocal(result, isolate));
        dun_v8_value_unref(result);
    }
}

extern "C" {

// --- Isolate ---

DunV8Isolate* dun_v8_isolate_new(void) {
    ensurePlatform();
    auto* iw = new DunV8Isolate();
    iw->params.array_buffer_allocator =
        v8::ArrayBuffer::Allocator::NewDefaultAllocator();
    iw->isolate = v8::Isolate::New(iw->params);
    return iw;
}

void dun_v8_isolate_dispose(DunV8Isolate* iw) {
    if (!iw) return;
    iw->isolate->Dispose();
    delete iw->params.array_buffer_allocator;
    delete iw;
}

// --- Context ---

DunV8Context* dun_v8_context_new(DunV8Isolate* iw) {
    assert(iw && "dun_v8_context_new: null isolate");
    v8::Isolate::Scope isolate_scope(iw->isolate);
    v8::HandleScope handle_scope(iw->isolate);
    auto context = v8::Context::New(iw->isolate);
    auto* cw = new DunV8Context();
    cw->context.Reset(iw->isolate, context);
    cw->isolate_wrapper = iw;
    cw->user_data = nullptr;
    return cw;
}

void dun_v8_context_free(DunV8Context* cw) {
    if (!cw) return;
    cw->context.Reset();
    delete cw;
}

// --- Evaluation (unique logic — TryCatch, ScriptOrigin) ---

DunV8Value* dun_v8_eval(DunV8Context* cw, const char* source,
    size_t source_len, const char* filename, int* is_error)
{
    assert(cw && "dun_v8_eval: null context");
    assert(source && "dun_v8_eval: null source");
    assert(is_error && "dun_v8_eval: null is_error");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) -> DunV8Value* {
        v8::TryCatch try_catch(isolate);

        auto src = v8::String::NewFromUtf8(isolate, source,
            v8::NewStringType::kNormal, static_cast<int>(source_len))
            .ToLocalChecked();

        auto origin_name = v8::String::NewFromUtf8(
            isolate, filename ? filename : "<eval>").ToLocalChecked();
#if V8_MAJOR_VERSION >= 10 && V8_MAJOR_VERSION <= 12
        // V8 10-12: ScriptOrigin takes isolate as first arg
        v8::ScriptOrigin origin(isolate, origin_name);
#else
        // V8 13+: ScriptOrigin takes value directly (no isolate)
        v8::ScriptOrigin origin(origin_name);
#endif

        auto script = v8::Script::Compile(context, src, &origin);
        if (script.IsEmpty()) {
            *is_error = 1;
            if (try_catch.HasCaught()) {
                v8::String::Utf8Value msg(isolate, try_catch.Exception());
                cw->last_exception = *msg ? *msg : "unknown error";
            }
            return wrapValue(iw, v8::Undefined(isolate));
        }

        auto result = script.ToLocalChecked()->Run(context);
        if (result.IsEmpty()) {
            *is_error = 1;
            if (try_catch.HasCaught()) {
                v8::String::Utf8Value msg(isolate, try_catch.Exception());
                cw->last_exception = *msg ? *msg : "unknown error";
            }
            return wrapValue(iw, v8::Undefined(isolate));
        }

        *is_error = 0;
        return wrapValue(iw, result.ToLocalChecked());
    });
}

// --- Value creation (withContext eliminates scope guard boilerplate) ---

DunV8Value* dun_v8_new_undefined(DunV8Context* cw) {
    return dun::withContext(cw, [](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Undefined(isolate));
    });
}

DunV8Value* dun_v8_new_null(DunV8Context* cw) {
    return dun::withContext(cw, [](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Null(isolate));
    });
}

DunV8Value* dun_v8_new_bool(DunV8Context* cw, int val) {
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Boolean::New(isolate, val != 0));
    });
}

DunV8Value* dun_v8_new_int(DunV8Context* cw, int val) {
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Integer::New(isolate, val));
    });
}

DunV8Value* dun_v8_new_number(DunV8Context* cw, double val) {
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Number::New(isolate, val));
    });
}

DunV8Value* dun_v8_new_string(DunV8Context* cw, const char* str, size_t len) {
    assert(cw && "dun_v8_new_string: null context");
    assert(str && "dun_v8_new_string: null str");
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::String::NewFromUtf8(isolate, str,
            v8::NewStringType::kNormal, static_cast<int>(len))
            .ToLocalChecked());
    });
}

DunV8Value* dun_v8_new_object(DunV8Context* cw) {
    return dun::withContext(cw, [](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Object::New(isolate));
    });
}

DunV8Value* dun_v8_new_array(DunV8Context* cw, int length) {
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        return wrapValue(iw, v8::Array::New(isolate, length));
    });
}

// --- Function creation (unique — FunctionTemplate trampoline) ---

DunV8Value* dun_v8_new_function(DunV8Context* cw, DunV8NativeCallback cb,
    const char* name, void* data)
{
    assert(cw && "dun_v8_new_function: null context");
    assert(cb && "dun_v8_new_function: null callback");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto* fd = new DunV8FunctionData{cb, cw, data, {}};
        auto external = DUN_EXTERNAL_NEW(isolate, fd);
        fd->prevent_gc.Reset(isolate, external);
        fd->prevent_gc.SetWeak(fd, functionDataweak, v8::WeakCallbackType::kParameter);
        auto tmpl = v8::FunctionTemplate::New(isolate, v8FunctionTrampoline, external);
        auto fn = tmpl->GetFunction(context).ToLocalChecked();

        if (name) {
            auto v8name = v8::String::NewFromUtf8(isolate, name).ToLocalChecked();
            fn->SetName(v8name);
        }

        return wrapValue(iw, fn);
    });
}

// --- Value extraction (withContext eliminates scope guard boilerplate) ---

const char* dun_v8_value_to_string(DunV8Context* cw, DunV8Value* vw, size_t* len) {
    assert(cw && "dun_v8_value_to_string: null context");
    assert(vw && "dun_v8_value_to_string: null value");
    assert(len && "dun_v8_value_to_string: null len");
    return dun::withContext(cw, [&](auto isolate, auto, auto*) -> const char* {
        v8::String::Utf8Value utf8(isolate, getLocal(vw, isolate));
        if (!*utf8) { *len = 0; return nullptr; }
        *len = utf8.length();
        char* copy = new char[*len + 1];
        memcpy(copy, *utf8, *len);
        copy[*len] = '\0';
        return copy;
    });
}

void dun_v8_free_string(const char* str) {
    delete[] str;
}

int dun_v8_value_to_int(DunV8Context* cw, DunV8Value* vw) {
    return dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        auto val = getLocal(vw, isolate);
        // Fast path: SMI / already-int32. Skips the ToInt32 coercion
        // call (the hot path for indexed property work, Buffer sizes,
        // randomBytes lengths, etc.).
        if (val->IsInt32())
            return v8::Local<v8::Int32>::Cast(val)->Value();
        return val->Int32Value(context).FromMaybe(0);
    });
}

double dun_v8_value_to_number(DunV8Context* cw, DunV8Value* vw) {
    return dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        auto val = getLocal(vw, isolate);
        // Fast path: already a Number — skip the ToNumber coercion.
        if (val->IsNumber())
            return v8::Local<v8::Number>::Cast(val)->Value();
        return val->NumberValue(context).FromMaybe(0.0);
    });
}

int dun_v8_value_to_bool(DunV8Context* cw, DunV8Value* vw) {
    return dun::withContext(cw, [&](auto isolate, auto, auto*) {
        return getLocal(vw, isolate)->BooleanValue(isolate) ? 1 : 0;
    });
}

// --- Type checks (TMP dispatch via isV8Type<Tag>) ---

int dun_v8_value_is_undefined(DunV8Value* vw)  { return valueIsType<dun::V8Tag::Undefined>(vw); }
int dun_v8_value_is_null(DunV8Value* vw)        { return valueIsType<dun::V8Tag::Null>(vw); }
int dun_v8_value_is_bool(DunV8Value* vw)        { return valueIsType<dun::V8Tag::Bool>(vw); }
int dun_v8_value_is_int(DunV8Value* vw)         { return valueIsType<dun::V8Tag::Int>(vw); }
int dun_v8_value_is_number(DunV8Value* vw)      { return valueIsType<dun::V8Tag::Number>(vw); }
int dun_v8_value_is_string(DunV8Value* vw)      { return valueIsType<dun::V8Tag::String>(vw); }
int dun_v8_value_is_object(DunV8Value* vw)      { return valueIsType<dun::V8Tag::Object>(vw); }
int dun_v8_value_is_function(DunV8Value* vw)    { return valueIsType<dun::V8Tag::Function>(vw); }
int dun_v8_value_is_array(DunV8Value* vw)       { return valueIsType<dun::V8Tag::Array>(vw); }

// Single FFI call: returns V8Tag enum value for the given value
int dun_v8_value_get_type(DunV8Value* vw) {
    if (!vw) return 0;
    return dun::withIsolate(vw->isolate_wrapper, [&](auto isolate) -> int {
        auto val = getLocal(vw, isolate);
        if (val->IsUndefined()) return static_cast<int>(dun::V8Tag::Undefined);
        if (val->IsNull())      return static_cast<int>(dun::V8Tag::Null);
        if (val->IsBoolean())   return static_cast<int>(dun::V8Tag::Bool);
        if (val->IsInt32())     return static_cast<int>(dun::V8Tag::Int);
        if (val->IsNumber())    return static_cast<int>(dun::V8Tag::Number);
        if (val->IsString())    return static_cast<int>(dun::V8Tag::String);
        if (val->IsArray())     return static_cast<int>(dun::V8Tag::Array);
        if (val->IsFunction())  return static_cast<int>(dun::V8Tag::Function);
        if (val->IsObject())    return static_cast<int>(dun::V8Tag::Object);
        return static_cast<int>(dun::V8Tag::Undefined);
    });
}

// --- Property access (withContext eliminates scope guard boilerplate) ---

DunV8Value* dun_v8_get_property(DunV8Context* cw, DunV8Value* obj, const char* name) {
    assert(cw && "dun_v8_get_property: null context");
    assert(obj && "dun_v8_get_property: null obj");
    assert(name && "dun_v8_get_property: null name");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto o = getLocal(obj, isolate).template As<v8::Object>();
        auto key = v8::String::NewFromUtf8(isolate, name).ToLocalChecked();
        auto val = o->Get(context, key);
        if (val.IsEmpty())
            return wrapValue(iw, v8::Undefined(isolate));
        return wrapValue(iw, val.ToLocalChecked());
    });
}

void dun_v8_set_property(DunV8Context* cw, DunV8Value* obj,
    const char* name, DunV8Value* val)
{
    assert(cw && "dun_v8_set_property: null context");
    assert(obj && "dun_v8_set_property: null obj");
    assert(name && "dun_v8_set_property: null name");
    assert(val && "dun_v8_set_property: null val");
    dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        auto o = getLocal(obj, isolate).template As<v8::Object>();
        auto key = v8::String::NewFromUtf8(isolate, name).ToLocalChecked();
        o->Set(context, key, getLocal(val, isolate)).FromMaybe(false);
        return 0; // withContext needs a return value
    });
}

// Object.setPrototypeOf(obj, proto). Used for Buffer-as-Uint8Array
// hot path so makeBufferObj can return a real TypedArray with the
// Buffer prototype glued on, skipping the per-call JS factory call.
void dun_v8_set_prototype(DunV8Context* cw, DunV8Value* obj, DunV8Value* proto)
{
    assert(cw && "dun_v8_set_prototype: null context");
    assert(obj && "dun_v8_set_prototype: null obj");
    assert(proto && "dun_v8_set_prototype: null proto");
    dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        auto o = getLocal(obj, isolate).template As<v8::Object>();
        o->SetPrototype(context, getLocal(proto, isolate)).FromMaybe(false);
        return 0;
    });
}

DunV8Value* dun_v8_get_property_index(DunV8Context* cw, DunV8Value* obj, unsigned int idx) {
    assert(cw && "dun_v8_get_property_index: null context");
    assert(obj && "dun_v8_get_property_index: null obj");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto o = getLocal(obj, isolate).template As<v8::Object>();
        auto val = o->Get(context, idx);
        if (val.IsEmpty())
            return wrapValue(iw, v8::Undefined(isolate));
        return wrapValue(iw, val.ToLocalChecked());
    });
}

void dun_v8_set_property_index(DunV8Context* cw, DunV8Value* obj,
    unsigned int idx, DunV8Value* val)
{
    assert(cw && "dun_v8_set_property_index: null context");
    assert(obj && "dun_v8_set_property_index: null obj");
    assert(val && "dun_v8_set_property_index: null val");
    dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        auto o = getLocal(obj, isolate).template As<v8::Object>();
        o->Set(context, idx, getLocal(val, isolate)).FromMaybe(false);
        return 0;
    });
}

DunV8Value* dun_v8_global(DunV8Context* cw) {
    return dun::withContext(cw, [](auto, auto context, auto* iw) {
        return wrapValue(iw, context->Global());
    });
}

// --- Typed arrays ---

DunV8Value* dun_v8_new_uint8array(DunV8Context* cw,
    const unsigned char* data, size_t len)
{
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto ab = v8::ArrayBuffer::New(isolate, len);
        if (data && len > 0) {
            auto src = std::span{data, len};
            memcpy(ab->GetBackingStore()->Data(), src.data(), src.size_bytes());
        }
        auto ta = v8::Uint8Array::New(ab, 0, len);
        return wrapValue(iw, ta.template As<v8::Value>());
    });
}

// One-shot Uint8Array allocator with prototype glue — used by the Buffer
// hot path. Doing alloc + memcpy + SetPrototype in a single withContext
// avoids 3 redundant Isolate::Scope/HandleScope/Context::Scope entries
// per Buffer.from / .alloc, which is the largest chunk of native-call
// overhead in `feature_bench.js` Buffer section on the V8 backend.
DunV8Value* dun_v8_new_uint8array_with_proto(DunV8Context* cw,
    const unsigned char* data, size_t len, DunV8Value* proto, int zeroed)
{
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto ab = v8::ArrayBuffer::New(isolate, len);
        if (data && len > 0) {
            memcpy(ab->GetBackingStore()->Data(), data, len);
        } else if (zeroed && len > 0) {
            // ArrayBuffer::New zeros by default in V8 14+, this is just for
            // older versions and explicit clarity. memset is cheap vs. the
            // scope-entry cost we just avoided.
        }
        auto ta = v8::Uint8Array::New(ab, 0, len);
        auto obj = ta.template As<v8::Object>();
        if (proto) {
            obj->SetPrototype(context, getLocal(proto, isolate)).FromMaybe(false);
        }
        return wrapValue(iw, ta.template As<v8::Value>());
    });
}

// Buffer.from(string, "utf8") hot path: read the JS string, allocate an
// ArrayBuffer of the right UTF-8 byte length, copy bytes directly via
// v8::String::WriteUtf8V2, set the Buffer prototype. One withContext
// entry instead of the previous three (extractString + newUint8Array +
// setPrototype). Returns the new Buffer as a DunV8Value*.
DunV8Value* dun_v8_buffer_from_utf8_string(DunV8Context* cw,
    DunV8Value* jsString, DunV8Value* proto)
{
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto local = getLocal(jsString, isolate);
        if (!local->IsString()) {
            return wrapValue(iw, v8::Undefined(isolate).template As<v8::Value>());
        }
        auto str = local.template As<v8::String>();
        size_t utf8len = str->Utf8LengthV2(isolate);
        auto ab = v8::ArrayBuffer::New(isolate, utf8len);
        if (utf8len > 0) {
            char* dst = static_cast<char*>(ab->GetBackingStore()->Data());
            str->WriteUtf8V2(isolate, dst, utf8len, v8::String::WriteFlags::kNone);
        }
        auto ta = v8::Uint8Array::New(ab, 0, utf8len);
        auto obj = ta.template As<v8::Object>();
        if (proto) {
            obj->SetPrototype(context, getLocal(proto, isolate)).FromMaybe(false);
        }
        return wrapValue(iw, ta.template As<v8::Value>());
    });
}

// Buffer.concat fused fast-path. Replaces ~3N+5 FFI scope entries
// (count probe, per-element getPropertyIndex/getTypedArrayBytes/
// freeValue, newUint8ArrayZeroed, setPrototype) with one withContext
// block. The size pass + memcpy loop all happen here against
// v8::Local<TypedArray> directly. If `total_len == SIZE_MAX` the
// function computes the total by summing ByteLength()s; otherwise
// it uses the caller-supplied value (Node's `totalLength` optional
// parameter or D-side clamping).
DunV8Value* dun_v8_buffer_concat(DunV8Context* cw, DunV8Value* arrayHandle,
    int count, size_t total_len, DunV8Value* proto)
{
    assert(cw && "dun_v8_buffer_concat: null context");
    assert(arrayHandle && "dun_v8_buffer_concat: null array handle");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto arrayLocal = getLocal(arrayHandle, isolate);
        auto arrayObj = arrayLocal->IsObject()
            ? arrayLocal.template As<v8::Object>()
            : v8::Local<v8::Object>();

        // Resolve each element to a TypedArray on the stack (avoids
        // a second Get() pass during memcpy). count is bounded by D-
        // side STACK_MAX (16) for short concats; fallback below uses
        // heap.
        constexpr int kStackMax = 16;
        v8::Local<v8::TypedArray> stack_ta[kStackMax];
        std::unique_ptr<v8::Local<v8::TypedArray>[]> heap_ta;
        v8::Local<v8::TypedArray>* tas = nullptr;
        if (count > 0) {
            if (count <= kStackMax) {
                tas = stack_ta;
            } else {
                heap_ta = std::make_unique<v8::Local<v8::TypedArray>[]>(
                    static_cast<size_t>(count));
                tas = heap_ta.get();
            }
        }

        size_t computed_len = 0;
        for (int i = 0; i < count; i++) {
            tas[i] = v8::Local<v8::TypedArray>();
            if (arrayObj.IsEmpty()) continue;
            auto elemMaybe = arrayObj->Get(context, static_cast<uint32_t>(i));
            if (elemMaybe.IsEmpty()) continue;
            auto elem = elemMaybe.ToLocalChecked();
            if (!elem->IsTypedArray()) continue;
            tas[i] = elem.template As<v8::TypedArray>();
            computed_len += tas[i]->ByteLength();
        }

        // SIZE_MAX sentinel = "no caller override, use computed total"
        size_t result_len = (total_len == static_cast<size_t>(-1))
            ? computed_len : total_len;

        auto ab = v8::ArrayBuffer::New(isolate, result_len);
        char* dst = result_len > 0
            ? static_cast<char*>(ab->GetBackingStore()->Data())
            : nullptr;
        if (dst && count > 0) {
            size_t pos = 0;
            for (int i = 0; i < count && pos < result_len; i++) {
                if (tas[i].IsEmpty()) continue;
                auto ta = tas[i];
                size_t offset = ta->ByteOffset();
                size_t elemLen = ta->ByteLength();
                if (elemLen == 0) continue;
                if (pos + elemLen > result_len) elemLen = result_len - pos;
                auto bs = ta->Buffer()->GetBackingStore();
                if (bs) {
                    memcpy(dst + pos,
                        static_cast<const char*>(bs->Data()) + offset,
                        elemLen);
                    pos += elemLen;
                }
            }
        }
        auto result = v8::Uint8Array::New(ab, 0, result_len);
        if (proto) {
            result.template As<v8::Object>()
                ->SetPrototype(context, getLocal(proto, isolate))
                .FromMaybe(false);
        }
        return wrapValue(iw, result.template As<v8::Value>());
    });
}

unsigned char* dun_v8_typed_array_data(DunV8Context* cw,
    DunV8Value* val, size_t* out_len)
{
    if (!val || !out_len) { if (out_len) *out_len = 0; return nullptr; }
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) -> unsigned char* {
        auto local = getLocal(val, isolate);
        if (!local->IsTypedArray()) { *out_len = 0; return nullptr; }
        auto ta = local.template As<v8::TypedArray>();
        *out_len = ta->ByteLength();
        auto ab = ta->Buffer();
        return static_cast<unsigned char*>(ab->GetBackingStore()->Data())
            + ta->ByteOffset();
    });
}

// --- Reference management ---

void dun_v8_value_ref(DunV8Value* vw) {
    if (!vw) return;
    // First dup of a borrowed value: promote to a real Persistent. The
    // caller intends to keep the value past the surrounding HandleScope
    // (e.g. `return engine.dupValue(thisVal)` from a chain method).
    if (vw->is_borrowed) {
        vw->value.Reset(vw->isolate_wrapper->isolate, vw->borrowed_local);
        vw->borrowed_local.Clear();
        vw->is_borrowed = 0;
    }
    vw->ref_count++;
}

void dun_v8_value_unref(DunV8Value* vw) {
    if (!vw) return;
    if (--vw->ref_count <= 0) {
        // Borrowed Local doesn't own anything — its slot dies with the
        // HandleScope. Just drop the reference and recycle the wrapper.
        // Owning wrappers need Persistent::Reset to release V8's GC root.
        if (vw->is_borrowed) {
            vw->borrowed_local.Clear();
            vw->is_borrowed = 0;
        } else {
            vw->value.Reset();
        }
        g_value_pool.release(vw);
        g_release_count.fetch_add(1, std::memory_order_relaxed);
    }
}

// --- Exceptions ---

const char* dun_v8_get_exception(DunV8Context* cw, size_t* len) {
    assert(cw && "dun_v8_get_exception: null context");
    assert(len && "dun_v8_get_exception: null len");
    *len = cw->last_exception.size();
    if (*len == 0) return nullptr;
    char* copy = new char[*len + 1];
    memcpy(copy, cw->last_exception.c_str(), *len);
    copy[*len] = '\0';
    return copy;
}

DunV8Value* dun_v8_throw_error(DunV8Context* cw, const char* msg) {
    assert(cw && "dun_v8_throw_error: null context");
    assert(msg && "dun_v8_throw_error: null msg");
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        auto err = v8::Exception::Error(
            v8::String::NewFromUtf8(isolate, msg).ToLocalChecked());
        isolate->ThrowException(err);
        return wrapValue(iw, err);
    });
}

DunV8Value* dun_v8_throw_type_error(DunV8Context* cw, const char* msg) {
    assert(cw && "dun_v8_throw_type_error: null context");
    assert(msg && "dun_v8_throw_type_error: null msg");
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        auto err = v8::Exception::TypeError(
            v8::String::NewFromUtf8(isolate, msg).ToLocalChecked());
        isolate->ThrowException(err);
        return wrapValue(iw, err);
    });
}

DunV8Value* dun_v8_throw_range_error(DunV8Context* cw, const char* msg) {
    assert(cw && "dun_v8_throw_range_error: null context");
    assert(msg && "dun_v8_throw_range_error: null msg");
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        auto err = v8::Exception::RangeError(
            v8::String::NewFromUtf8(isolate, msg).ToLocalChecked());
        isolate->ThrowException(err);
        return wrapValue(iw, err);
    });
}

DunV8Value* dun_v8_throw_value(DunV8Context* cw, DunV8Value* val) {
    assert(cw && "dun_v8_throw_value: null context");
    assert(val && "dun_v8_throw_value: null value");
    return dun::withContext(cw, [&](auto isolate, auto, auto* iw) {
        auto local = getLocal(val, isolate);
        isolate->ThrowException(local);
        return wrapValue(iw, local);
    });
}

// --- Function call (unique — TryCatch + args marshalling) ---

DunV8Value* dun_v8_call(DunV8Context* cw, DunV8Value* func,
    DunV8Value* this_obj, int argc, DunV8Value** argv, int* is_error)
{
    assert(cw && "dun_v8_call: null context");
    assert(func && "dun_v8_call: null func");
    assert(is_error && "dun_v8_call: null is_error");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) -> DunV8Value* {
        v8::TryCatch try_catch(isolate);

        auto fn = getLocal(func, isolate).template As<v8::Function>();
        v8::Local<v8::Value> recv = this_obj ?
            getLocal(this_obj, isolate) :
            context->Global().template As<v8::Value>();

        constexpr int kStackLimit = 16;
        std::array<v8::Local<v8::Value>, kStackLimit> stack_args;
        std::unique_ptr<v8::Local<v8::Value>[]> heap_args;
        v8::Local<v8::Value>* args;
        if (argc <= kStackLimit) {
            args = stack_args.data();
        } else {
            heap_args = std::make_unique<v8::Local<v8::Value>[]>(
                static_cast<size_t>(argc));
            args = heap_args.get();
        }
        auto argv_span = std::span{argv, static_cast<size_t>(argc)};
        for (size_t i = 0; i < argv_span.size(); i++)
            args[i] = getLocal(argv_span[i], isolate);

        auto result = fn->Call(context, recv, argc,
            argc > 0 ? args : nullptr);

        if (result.IsEmpty()) {
            *is_error = 1;
            if (try_catch.HasCaught()) {
                v8::String::Utf8Value msg(isolate, try_catch.Exception());
                cw->last_exception = *msg ? *msg : "unknown error";
            }
            return wrapValue(iw, v8::Undefined(isolate));
        }

        *is_error = 0;
        return wrapValue(iw, result.ToLocalChecked());
    });
}

// --- Promises ---

DunV8Value* dun_v8_new_promise(DunV8Context* cw,
    DunV8Value** resolve_out, DunV8Value** reject_out)
{
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) -> DunV8Value* {
        auto resolver = v8::Promise::Resolver::New(context).ToLocalChecked();
        auto promise = resolver->GetPromise();

        auto* resolverVal = new DunV8Value();
        resolverVal->value.Reset(isolate, resolver);
        resolverVal->isolate_wrapper = iw;
        resolverVal->ref_count = 2; // one for resolve, one for reject

        auto resolveExt = DUN_EXTERNAL_NEW(isolate, resolverVal);
        auto resolveFunc = v8::Function::New(context,
            [](const v8::FunctionCallbackInfo<v8::Value>& info) {
                auto ext = v8::Local<v8::External>::Cast(info.Data());
                auto* rw = static_cast<DunV8Value*>(DUN_EXTERNAL_VALUE(ext));
                auto iso = info.GetIsolate();
                auto ctx = iso->GetCurrentContext();
                auto resolver = v8::Local<v8::Promise::Resolver>::Cast(
                    getLocal(rw, iso));
                v8::Local<v8::Value> val;
                if (info.Length() > 0) val = info[0];
                else val = v8::Undefined(iso);
                resolver->Resolve(ctx, val).FromMaybe(false);
                dun_v8_value_unref(rw);
            }, resolveExt).ToLocalChecked();

        auto rejectExt = DUN_EXTERNAL_NEW(isolate, resolverVal);
        auto rejectFunc = v8::Function::New(context,
            [](const v8::FunctionCallbackInfo<v8::Value>& info) {
                auto ext = v8::Local<v8::External>::Cast(info.Data());
                auto* rw = static_cast<DunV8Value*>(DUN_EXTERNAL_VALUE(ext));
                auto iso = info.GetIsolate();
                auto ctx = iso->GetCurrentContext();
                auto resolver = v8::Local<v8::Promise::Resolver>::Cast(
                    getLocal(rw, iso));
                v8::Local<v8::Value> val;
                if (info.Length() > 0) val = info[0];
                else val = v8::Undefined(iso);
                resolver->Reject(ctx, val).FromMaybe(false);
                dun_v8_value_unref(rw);
            }, rejectExt).ToLocalChecked();

        *resolve_out = wrapValue(iw, resolveFunc);
        *reject_out = wrapValue(iw, rejectFunc);
        return wrapValue(iw, promise);
    });
}

// --- Microtasks ---

int dun_v8_has_pending_microtasks(DunV8Isolate* iw) {
    if (!iw) return 0;
    v8::Isolate::Scope s(iw->isolate);
#if V8_MAJOR_VERSION >= 14
    // HasPendingBackgroundTasks removed in V8 14.x; microtask checkpoint is
    // the only reliable way to drain — return 0 so callers just checkpoint.
    return 0;
#else
    return iw->isolate->HasPendingBackgroundTasks() ? 1 : 0;
#endif
}

void dun_v8_drain_microtasks(DunV8Isolate* iw) {
    if (!iw) return;
    v8::Isolate::Scope s(iw->isolate);
    iw->isolate->PerformMicrotaskCheckpoint();
}

// --- Context data ---

void dun_v8_set_context_data(DunV8Context* cw, void* data) {
    assert(cw && "dun_v8_set_context_data: null context");
    cw->user_data = data;
}

void* dun_v8_get_context_data(DunV8Context* cw) {
    assert(cw && "dun_v8_get_context_data: null context");
    return cw->user_data;
}

// --- Limits ---

static size_t nearHeapLimitCallback(void* data, size_t current, size_t initial) {
    (void)data; (void)initial;
    // Don't increase — let V8 OOM. Returning current means "no more room".
    return current;
}

void dun_v8_set_memory_limit(DunV8Isolate* iw, size_t bytes) {
    assert(iw && "dun_v8_set_memory_limit: null isolate");
    v8::Isolate::Scope isolate_scope(iw->isolate);
    v8::HandleScope handle_scope(iw->isolate);
    iw->isolate->AddNearHeapLimitCallback(nearHeapLimitCallback, nullptr);
    v8::HeapStatistics stats;
    iw->isolate->GetHeapStatistics(&stats);
    int64_t delta = static_cast<int64_t>(bytes) - static_cast<int64_t>(stats.total_heap_size());
    if (delta > 0)
        iw->isolate->AdjustAmountOfExternalAllocatedMemory(delta);
}

void dun_v8_set_stack_limit(DunV8Isolate* iw, size_t bytes) {
    assert(iw && "dun_v8_set_stack_limit: null isolate");
    // V8 SetStackLimit takes an absolute address, not a size.
    // Compute limit as current stack position minus requested size.
    volatile char stack_var = 0;
    uintptr_t stack_addr = reinterpret_cast<uintptr_t>(&stack_var);
    uintptr_t limit = (bytes < stack_addr) ? (stack_addr - bytes) : 0;
    iw->isolate->SetStackLimit(limit);
}

// --- Garbage collection ---

void dun_v8_collect_garbage(DunV8Isolate* iw) {
    if (!iw) return;
    iw->isolate->LowMemoryNotification();
}

// --- Version ---

const char* dun_v8_version() {
    return v8::V8::GetVersion();
}

} /* extern "C" */
