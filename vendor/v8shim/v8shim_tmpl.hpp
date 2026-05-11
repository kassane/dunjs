/*
 * v8shim_tmpl.hpp — C++ template metaprogramming helpers for v8shim.
 *
 * Eliminates boilerplate in v8shim.cpp by abstracting V8's scope guard
 * pattern into templates. Every V8 operation requires identical setup:
 *   1. Isolate::Scope
 *   2. HandleScope
 *   3. Context::Get + Context::Scope
 *
 * This header provides:
 *   - withContext<F>: RAII scope guard + forwarding
 *   - V8TypeMap<Tag>: compile-time V8 type dispatch (int → Integer, etc.)
 *   - makeV8Value<Tag>: type-safe value creation via template specialization
 *
 * Usage in v8shim.cpp:
 *   return withContext(cw, [](auto isolate, auto context, auto* iw) {
 *       return wrapValue(iw, v8::Integer::New(isolate, 42));
 *   });
 *
 * This reduces the 15-line boilerplate per function to 3 lines.
 * The D side can mirror this with D's compile-time templates (static foreach,
 * mixin templates) to auto-generate extern(C) binding declarations.
 */

#ifndef DUN_V8SHIM_TMPL_HPP
#define DUN_V8SHIM_TMPL_HPP

#include <v8.h>
#include "v8shim.h"

namespace dun {

// RAII scope guard: sets up Isolate::Scope + HandleScope + Context::Scope,
// then invokes F with (isolate, context, isolate_wrapper).
template <typename F>
auto withContext(DunV8Context* cw, F&& fn)
    -> decltype(fn(std::declval<v8::Isolate*>(),
                   std::declval<v8::Local<v8::Context>>(),
                   std::declval<DunV8Isolate*>()))
{
    auto* isolate = cw->isolate_wrapper->isolate;
    v8::Isolate::Scope isolate_scope(isolate);
    v8::HandleScope handle_scope(isolate);
    auto context = cw->context.Get(isolate);
    v8::Context::Scope context_scope(context);
    return fn(isolate, context, cw->isolate_wrapper);
}

// Isolate-only variant (no context needed)
template <typename F>
auto withIsolate(DunV8Isolate* iw, F&& fn)
    -> decltype(fn(std::declval<v8::Isolate*>()))
{
    v8::Isolate::Scope scope(iw->isolate);
    v8::HandleScope handle_scope(iw->isolate);
    return fn(iw->isolate);
}

// Compile-time tag types for V8 value dispatch
enum class V8Tag { Undefined, Null, Bool, Int, Number, String, Object, Array, Function };

// Type-level map: V8Tag → v8::Type
template <V8Tag Tag> struct V8TypeMap;
template <> struct V8TypeMap<V8Tag::Bool>    { using type = v8::Boolean; };
template <> struct V8TypeMap<V8Tag::Int>     { using type = v8::Integer; };
template <> struct V8TypeMap<V8Tag::Number>  { using type = v8::Number; };
template <> struct V8TypeMap<V8Tag::String>  { using type = v8::String; };
template <> struct V8TypeMap<V8Tag::Object>  { using type = v8::Object; };
template <> struct V8TypeMap<V8Tag::Array>   { using type = v8::Array; };
template <> struct V8TypeMap<V8Tag::Function> { using type = v8::Function; };

// Type check dispatch: compile-time selection of IsXxx method
template <V8Tag Tag>
bool isV8Type(v8::Isolate* isolate, DunV8Value* vw) {
    auto val = vw->value.Get(isolate);
    if constexpr (Tag == V8Tag::Undefined) return val->IsUndefined();
    else if constexpr (Tag == V8Tag::Null)      return val->IsNull();
    else if constexpr (Tag == V8Tag::Bool)      return val->IsBoolean();
    else if constexpr (Tag == V8Tag::Int)       return val->IsInt32();
    else if constexpr (Tag == V8Tag::Number)    return val->IsNumber();
    else if constexpr (Tag == V8Tag::String)    return val->IsString();
    else if constexpr (Tag == V8Tag::Object)    return val->IsObject();
    else if constexpr (Tag == V8Tag::Array)     return val->IsArray();
    else if constexpr (Tag == V8Tag::Function)  return val->IsFunction();
    else return false;
}

} // namespace dun

/*
 * D-side TMP mirror (compile-time code generation):
 *
 * The D binding can use mixin templates and static foreach to generate
 * the extern(C) declarations from a type descriptor:
 *
 *   // In D:
 *   enum V8Tag { Undefined, Null, Bool, Int, Number, String, Object, Array }
 *
 *   // Generate type-check functions
 *   static foreach (tag; [EnumMembers!V8Tag]) {
 *       mixin("extern(C) int dun_v8_value_is_" ~ toLower(tag.stringof)
 *             ~ "(DunV8Value* val) nothrow @nogc;");
 *   }
 *
 *   // Generate value creation functions via mixin template
 *   mixin template V8Creator(string name, RetType, ArgTypes...) {
 *       mixin("extern(C) DunV8Value* dun_v8_new_" ~ name
 *             ~ "(" ~ joinArgs!(ArgTypes) ~ ") nothrow @nogc;");
 *   }
 *
 * This keeps the C++ templates and D templates in sync — the C++ side
 * uses if constexpr dispatch, the D side uses static foreach generation.
 * Both are resolved at compile time with zero runtime overhead.
 */

#endif /* DUN_V8SHIM_TMPL_HPP */
