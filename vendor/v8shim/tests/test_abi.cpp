// test_abi.cpp — ABI contract tests (no V8 needed, links against stubs).

#include <gtest/gtest.h>
#include <cstddef>
#include <cstdint>
#include <type_traits>

#include "v8shim.h"

// Opaque pointer types are pointer-sized
static_assert(sizeof(DunV8Isolate*) == sizeof(void*));
static_assert(sizeof(DunV8Context*) == sizeof(void*));
static_assert(sizeof(DunV8Value*) == sizeof(void*));

static_assert(sizeof(DunV8NativeCallback) == sizeof(void*),
    "callback must be pointer-sized for D FFI");

static_assert(sizeof(int) == 4, "int must be 32-bit for D interop");
static_assert(sizeof(size_t) == sizeof(void*),
    "size_t must match pointer size for D interop");
static_assert(alignof(DunV8Isolate*) == alignof(void*));
static_assert(alignof(DunV8Context*) == alignof(void*));
static_assert(alignof(DunV8Value*) == alignof(void*));
static_assert(alignof(DunV8NativeCallback) == alignof(void*));

static_assert(sizeof(unsigned int) == 4,
    "unsigned int must be 32-bit for D uint interop");
static_assert(sizeof(double) == 8, "double must be 64-bit for D interop");
static_assert(std::numeric_limits<double>::is_iec559,
    "double must be IEEE 754 for D interop");

TEST(V8ShimABI, OpaquePointerSizes) {
    EXPECT_EQ(sizeof(DunV8Isolate*), sizeof(void*));
    EXPECT_EQ(sizeof(DunV8Context*), sizeof(void*));
    EXPECT_EQ(sizeof(DunV8Value*), sizeof(void*));
}

TEST(V8ShimABI, CallbackPointerSize) {
    EXPECT_EQ(sizeof(DunV8NativeCallback), sizeof(void*));
}

TEST(V8ShimABI, IntWidth) {
    EXPECT_EQ(sizeof(int), 4u);
    EXPECT_EQ(sizeof(unsigned int), 4u);
}

TEST(V8ShimABI, SizeTMatchesPointer) {
    EXPECT_EQ(sizeof(size_t), sizeof(void*));
}

TEST(V8ShimABI, DoubleWidth) {
    EXPECT_EQ(sizeof(double), 8u);
}

TEST(V8ShimABI, NullCallbackIsNullptr) {
    DunV8NativeCallback cb = nullptr;
    EXPECT_EQ(cb, nullptr);
}

TEST(V8ShimABI, FunctionPointersCallable) {
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_isolate_new), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_isolate_dispose), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_context_new), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_context_free), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_eval), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_undefined), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_null), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_bool), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_int), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_number), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_string), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_object), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_array), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_function), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_to_string), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_free_string), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_to_int), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_to_number), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_to_bool), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_undefined), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_null), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_bool), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_int), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_number), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_string), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_object), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_function), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_is_array), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_get_property), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_set_property), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_get_property_index), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_set_property_index), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_global), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_uint8array), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_ref), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_value_unref), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_get_exception), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_throw_error), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_throw_type_error), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_throw_range_error), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_call), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_new_promise), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_has_pending_microtasks), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_drain_microtasks), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_set_context_data), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_get_context_data), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_set_memory_limit), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_set_stack_limit), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_collect_garbage), nullptr);
    EXPECT_NE(reinterpret_cast<void*>(&dun_v8_version), nullptr);
}

TEST(V8ShimABI, NullSafeDispose) {
    dun_v8_isolate_dispose(nullptr);
    dun_v8_context_free(nullptr);
    dun_v8_value_ref(nullptr);
    dun_v8_value_unref(nullptr);
    dun_v8_collect_garbage(nullptr);
}

TEST(V8ShimABI, NullSafeFreeString) {
    dun_v8_free_string(nullptr);
}
