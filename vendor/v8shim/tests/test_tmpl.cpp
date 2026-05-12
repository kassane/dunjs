// test_tmpl.cpp — TMP bridge tests (needs V8 headers, not runtime).

#include <gtest/gtest.h>
#include <type_traits>
#include <concepts>

#include "v8shim_tmpl.hpp"

using namespace dun;


static_assert(isValidTag(V8Tag::Undefined));
static_assert(isValidTag(V8Tag::Function));
static_assert(!isValidTag(static_cast<V8Tag>(-1)));
static_assert(!isValidTag(static_cast<V8Tag>(V8TagCount)));
static_assert(!isValidTag(static_cast<V8Tag>(99)));

// Every tag maps to a non-null name
static_assert(tagName(V8Tag::Undefined) != nullptr);
static_assert(tagName(V8Tag::Null) != nullptr);
static_assert(tagName(V8Tag::Bool) != nullptr);
static_assert(tagName(V8Tag::Int) != nullptr);
static_assert(tagName(V8Tag::Number) != nullptr);
static_assert(tagName(V8Tag::String) != nullptr);
static_assert(tagName(V8Tag::Object) != nullptr);
static_assert(tagName(V8Tag::Array) != nullptr);
static_assert(tagName(V8Tag::Function) != nullptr);

static_assert(static_cast<int>(V8Tag::Undefined) == 0);
static_assert(static_cast<int>(V8Tag::Null) == 1);
static_assert(static_cast<int>(V8Tag::Bool) == 2);
static_assert(static_cast<int>(V8Tag::Int) == 3);
static_assert(static_cast<int>(V8Tag::Number) == 4);
static_assert(static_cast<int>(V8Tag::String) == 5);
static_assert(static_cast<int>(V8Tag::Object) == 6);
static_assert(static_cast<int>(V8Tag::Array) == 7);
static_assert(static_cast<int>(V8Tag::Function) == 8);
static_assert(V8TagCount == 9);


static_assert(std::is_same_v<V8TypeMap<V8Tag::Bool>::type, v8::Boolean>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::Int>::type, v8::Integer>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::Number>::type, v8::Number>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::String>::type, v8::String>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::Object>::type, v8::Object>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::Array>::type, v8::Array>);
static_assert(std::is_same_v<V8TypeMap<V8Tag::Function>::type, v8::Function>);

static_assert(ContextCallable<decltype([](v8::Isolate*, v8::Local<v8::Context>, DunV8Isolate*) {})>);
static_assert(!ContextCallable<decltype([](int) {})>);
static_assert(!ContextCallable<decltype([]() {})>);

static_assert(IsolateCallable<decltype([](v8::Isolate*) {})>);
static_assert(!IsolateCallable<decltype([](int) {})>);
static_assert(!IsolateCallable<decltype([]() {})>);


TEST(V8ShimTMP, TagNameStrings) {
    EXPECT_STREQ(tagName(V8Tag::Undefined), "undefined");
    EXPECT_STREQ(tagName(V8Tag::Null), "null");
    EXPECT_STREQ(tagName(V8Tag::Bool), "boolean");
    EXPECT_STREQ(tagName(V8Tag::Int), "int32");
    EXPECT_STREQ(tagName(V8Tag::Number), "number");
    EXPECT_STREQ(tagName(V8Tag::String), "string");
    EXPECT_STREQ(tagName(V8Tag::Object), "object");
    EXPECT_STREQ(tagName(V8Tag::Array), "array");
    EXPECT_STREQ(tagName(V8Tag::Function), "function");
}

TEST(V8ShimTMP, TagValidation) {
    // consteval — verified at compile time, runtime just confirms constants
    static_assert(isValidTag(V8Tag::Undefined));
    static_assert(isValidTag(V8Tag::Function));
    static_assert(!isValidTag(static_cast<V8Tag>(-1)));
    static_assert(!isValidTag(static_cast<V8Tag>(V8TagCount)));
    EXPECT_EQ(static_cast<int>(V8Tag::Undefined), 0);
    EXPECT_EQ(static_cast<int>(V8Tag::Function), 8);
}

TEST(V8ShimTMP, V8TagCountMatchesEnum) {
    EXPECT_EQ(V8TagCount, 9);
    EXPECT_EQ(static_cast<int>(V8Tag::Function), V8TagCount - 1);
}

TEST(V8ShimTMP, FFIAlignmentGuarantees) {
    EXPECT_EQ(alignof(DunV8Isolate*), alignof(void*));
    EXPECT_EQ(alignof(DunV8Context*), alignof(void*));
    EXPECT_EQ(alignof(DunV8Value*), alignof(void*));
    EXPECT_EQ(alignof(DunV8NativeCallback), alignof(void*));
}
