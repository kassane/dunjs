// v8shim.cpp — extern "C" V8 wrapper (C++20).

#include "v8shim.h"

#include <v8.h>
#include <libplatform/libplatform.h>
#include <cassert>
#include <cstring>
#include <array>
#include <memory>
#include <span>
#include <string>
#include <mutex>

static std::once_flag g_platform_flag;
static std::unique_ptr<v8::Platform> g_platform;

static void ensurePlatform() {
    std::call_once(g_platform_flag, [] {
        g_platform = v8::platform::NewDefaultPlatform();
        v8::V8::InitializePlatform(g_platform.get());
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
    v8::Global<v8::Value> value;
    DunV8Isolate* isolate_wrapper;
    int ref_count;
};

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

[[nodiscard]] static DunV8Value* wrapValue(DunV8Isolate* iw, v8::Local<v8::Value> val) {
    auto* wrapped = new DunV8Value();
    wrapped->value.Reset(iw->isolate, val);
    wrapped->isolate_wrapper = iw;
    wrapped->ref_count = 1;
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
    auto* fd = static_cast<DunV8FunctionData*>(external->Value());
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
    for (int i = 0; i < argc; i++)
        argv[i] = wrapValue(fd->context->isolate_wrapper, info[i]);

    DunV8Value* thisVal = wrapValue(fd->context->isolate_wrapper, info.This());

    DunV8Value* result = fd->callback(fd->context, thisVal,
        argc, argc > 0 ? argv : nullptr, fd->user_data);

    dun_v8_value_unref(thisVal);
    for (int i = 0; i < argc; i++)
        dun_v8_value_unref(argv[i]);

    if (result) {
        info.GetReturnValue().Set(result->value.Get(isolate));
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

        v8::ScriptOrigin origin(
            isolate,
            v8::String::NewFromUtf8(isolate, filename ? filename : "<eval>")
                .ToLocalChecked());

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
        auto external = v8::External::New(isolate, fd);
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
        v8::String::Utf8Value utf8(isolate, vw->value.Get(isolate));
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
        return vw->value.Get(isolate)->Int32Value(context).FromMaybe(0);
    });
}

double dun_v8_value_to_number(DunV8Context* cw, DunV8Value* vw) {
    return dun::withContext(cw, [&](auto isolate, auto context, auto*) {
        return vw->value.Get(isolate)->NumberValue(context).FromMaybe(0.0);
    });
}

int dun_v8_value_to_bool(DunV8Context* cw, DunV8Value* vw) {
    return dun::withContext(cw, [&](auto isolate, auto, auto*) {
        return vw->value.Get(isolate)->BooleanValue(isolate) ? 1 : 0;
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

// --- Property access (withContext eliminates scope guard boilerplate) ---

DunV8Value* dun_v8_get_property(DunV8Context* cw, DunV8Value* obj, const char* name) {
    assert(cw && "dun_v8_get_property: null context");
    assert(obj && "dun_v8_get_property: null obj");
    assert(name && "dun_v8_get_property: null name");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto o = obj->value.Get(isolate).template As<v8::Object>();
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
        auto o = obj->value.Get(isolate).template As<v8::Object>();
        auto key = v8::String::NewFromUtf8(isolate, name).ToLocalChecked();
        o->Set(context, key, val->value.Get(isolate)).FromMaybe(false);
        return 0; // withContext needs a return value
    });
}

DunV8Value* dun_v8_get_property_index(DunV8Context* cw, DunV8Value* obj, unsigned int idx) {
    assert(cw && "dun_v8_get_property_index: null context");
    assert(obj && "dun_v8_get_property_index: null obj");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) {
        auto o = obj->value.Get(isolate).template As<v8::Object>();
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
        auto o = obj->value.Get(isolate).template As<v8::Object>();
        o->Set(context, idx, val->value.Get(isolate)).FromMaybe(false);
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

// --- Reference management ---

void dun_v8_value_ref(DunV8Value* vw) {
    if (vw) vw->ref_count++;
}

void dun_v8_value_unref(DunV8Value* vw) {
    if (!vw) return;
    if (--vw->ref_count <= 0) {
        vw->value.Reset();
        delete vw;
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

// --- Function call (unique — TryCatch + args marshalling) ---

DunV8Value* dun_v8_call(DunV8Context* cw, DunV8Value* func,
    DunV8Value* this_obj, int argc, DunV8Value** argv, int* is_error)
{
    assert(cw && "dun_v8_call: null context");
    assert(func && "dun_v8_call: null func");
    assert(is_error && "dun_v8_call: null is_error");
    return dun::withContext(cw, [&](auto isolate, auto context, auto* iw) -> DunV8Value* {
        v8::TryCatch try_catch(isolate);

        auto fn = func->value.Get(isolate).template As<v8::Function>();
        v8::Local<v8::Value> recv = this_obj ?
            this_obj->value.Get(isolate) :
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
            args[i] = argv_span[i]->value.Get(isolate);

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

        auto resolveExt = v8::External::New(isolate, resolverVal);
        auto resolveFunc = v8::Function::New(context,
            [](const v8::FunctionCallbackInfo<v8::Value>& info) {
                auto ext = v8::Local<v8::External>::Cast(info.Data());
                auto* rw = static_cast<DunV8Value*>(ext->Value());
                auto iso = info.GetIsolate();
                auto ctx = iso->GetCurrentContext();
                auto r = rw->value.Get(iso).template As<v8::Promise::Resolver>();
                v8::Local<v8::Value> val;
                if (info.Length() > 0) val = info[0];
                else val = v8::Undefined(iso);
                r->Resolve(ctx, val).FromMaybe(false);
                dun_v8_value_unref(rw);
            }, resolveExt).ToLocalChecked();

        auto rejectExt = v8::External::New(isolate, resolverVal);
        auto rejectFunc = v8::Function::New(context,
            [](const v8::FunctionCallbackInfo<v8::Value>& info) {
                auto ext = v8::Local<v8::External>::Cast(info.Data());
                auto* rw = static_cast<DunV8Value*>(ext->Value());
                auto iso = info.GetIsolate();
                auto ctx = iso->GetCurrentContext();
                auto r = rw->value.Get(iso).template As<v8::Promise::Resolver>();
                v8::Local<v8::Value> val;
                if (info.Length() > 0) val = info[0];
                else val = v8::Undefined(iso);
                r->Reject(ctx, val).FromMaybe(false);
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
    return iw->isolate->HasPendingBackgroundTasks() ? 1 : 0;
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
    iw->isolate->AddNearHeapLimitCallback(nearHeapLimitCallback, nullptr);
    // Constrain young + old generation to requested total
    v8::HeapStatistics stats;
    iw->isolate->GetHeapStatistics(&stats);
    iw->isolate->AdjustAmountOfExternalAllocatedMemory(
        static_cast<int64_t>(bytes) - static_cast<int64_t>(stats.total_heap_size()));
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
