// v8shim_tmpl.hpp — C++20 TMP helpers (scope guards, type dispatch).

#ifndef DUN_V8SHIM_TMPL_HPP
#define DUN_V8SHIM_TMPL_HPP

#include <v8.h>
#include <cassert>
#include <concepts>
#include <span>
#include <type_traits>
#include "v8shim.h"

namespace dun {


enum class V8Tag : int {
    Undefined = 0, Null, Bool, Int, Number, String, Object, Array, Function
};

static constexpr int V8TagCount = 9;
static_assert(static_cast<int>(V8Tag::Function) == V8TagCount - 1,
    "V8Tag enum drift — update V8TagCount");

consteval bool isValidTag(V8Tag tag) {
    return static_cast<int>(tag) >= 0
        && static_cast<int>(tag) < V8TagCount;
}

consteval const char* tagName(V8Tag tag) {
    switch (tag) {
        case V8Tag::Undefined: return "undefined";
        case V8Tag::Null:      return "null";
        case V8Tag::Bool:      return "boolean";
        case V8Tag::Int:       return "int32";
        case V8Tag::Number:    return "number";
        case V8Tag::String:    return "string";
        case V8Tag::Object:    return "object";
        case V8Tag::Array:     return "array";
        case V8Tag::Function:  return "function";
    }
    return "unknown";
}


template <typename F>
concept ContextCallable = std::invocable<F, v8::Isolate*,
    v8::Local<v8::Context>, DunV8Isolate*>;

template <typename F>
concept IsolateCallable = std::invocable<F, v8::Isolate*>;


template <ContextCallable F>
auto withContext(DunV8Context* cw, F&& fn)
    -> std::invoke_result_t<F, v8::Isolate*, v8::Local<v8::Context>, DunV8Isolate*>
{
    assert(cw && "withContext: null DunV8Context");
    assert(cw->isolate_wrapper && "withContext: null isolate_wrapper");
    auto* isolate = cw->isolate_wrapper->isolate;
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    auto context = cw->context.Get(isolate);
    v8::Context::Scope context_scope(context);
    return fn(isolate, context, cw->isolate_wrapper);
}

template <IsolateCallable F>
auto withIsolate(DunV8Isolate* iw, F&& fn)
    -> std::invoke_result_t<F, v8::Isolate*>
{
    assert(iw && "withIsolate: null DunV8Isolate");
    v8::Isolate::Scope scope(iw->isolate);
    v8::HandleScope handle_scope(iw->isolate);
    return fn(iw->isolate);
}


template <V8Tag Tag> struct V8TypeMap;
template <> struct V8TypeMap<V8Tag::Bool>     { using type = v8::Boolean; };
template <> struct V8TypeMap<V8Tag::Int>      { using type = v8::Integer; };
template <> struct V8TypeMap<V8Tag::Number>   { using type = v8::Number; };
template <> struct V8TypeMap<V8Tag::String>   { using type = v8::String; };
template <> struct V8TypeMap<V8Tag::Object>   { using type = v8::Object; };
template <> struct V8TypeMap<V8Tag::Array>    { using type = v8::Array; };
template <> struct V8TypeMap<V8Tag::Function> { using type = v8::Function; };


template <V8Tag Tag>
    requires (isValidTag(Tag))
[[nodiscard]] bool isV8Type(v8::Isolate* isolate, DunV8Value* vw) {
    auto val = vw->value.Get(isolate);
    if constexpr (Tag == V8Tag::Undefined) return val->IsUndefined();
    else if constexpr (Tag == V8Tag::Null)     return val->IsNull();
    else if constexpr (Tag == V8Tag::Bool)     return val->IsBoolean();
    else if constexpr (Tag == V8Tag::Int)      return val->IsInt32();
    else if constexpr (Tag == V8Tag::Number)   return val->IsNumber();
    else if constexpr (Tag == V8Tag::String)   return val->IsString();
    else if constexpr (Tag == V8Tag::Object)   return val->IsObject();
    else if constexpr (Tag == V8Tag::Array)    return val->IsArray();
    else { static_assert(Tag == V8Tag::Function); return val->IsFunction(); }
}


static_assert(tagName(V8Tag::Undefined) != nullptr);
static_assert(tagName(V8Tag::Function) != nullptr);

static_assert(sizeof(DunV8NativeCallback) == sizeof(void*),
    "function pointer must be pointer-sized for FFI");
static_assert(alignof(DunV8Isolate*) == alignof(void*),
    "opaque pointer alignment mismatch");
static_assert(alignof(DunV8Context*) == alignof(void*),
    "opaque pointer alignment mismatch");
static_assert(alignof(DunV8Value*) == alignof(void*),
    "opaque pointer alignment mismatch");

} // namespace dun


#endif /* DUN_V8SHIM_TMPL_HPP */
