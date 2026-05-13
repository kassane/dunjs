// Test header for clang -ast-dump bindgen
// Simulates a minimal V8-like C API

#pragma once
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DunV8Isolate DunV8Isolate;
typedef struct DunV8Context DunV8Context;
typedef struct DunV8Value DunV8Value;

typedef DunV8Value* (*DunV8FunctionCallback)(
    DunV8Context* ctx, DunV8Value* this_val,
    int argc, DunV8Value** argv, void* data);

// Lifecycle
DunV8Isolate* dun_v8_isolate_new(void);
void dun_v8_isolate_dispose(DunV8Isolate* isolate);
DunV8Context* dun_v8_context_new(DunV8Isolate* isolate);
void dun_v8_context_free(DunV8Context* ctx);

// Eval
DunV8Value* dun_v8_eval(DunV8Context* ctx, const char* source,
    size_t len, const char* filename, int* is_error);

// Values
DunV8Value* dun_v8_new_string(DunV8Context* ctx, const char* str, size_t len);
DunV8Value* dun_v8_new_number(DunV8Context* ctx, double num);
DunV8Value* dun_v8_new_bool(DunV8Context* ctx, bool val);
DunV8Value* dun_v8_new_null(DunV8Context* ctx);
DunV8Value* dun_v8_new_undefined(DunV8Context* ctx);

// Type checks
bool dun_v8_is_string(DunV8Context* ctx, DunV8Value* val);
bool dun_v8_is_number(DunV8Context* ctx, DunV8Value* val);
bool dun_v8_is_bool(DunV8Context* ctx, DunV8Value* val);
bool dun_v8_is_object(DunV8Context* ctx, DunV8Value* val);
bool dun_v8_is_array(DunV8Context* ctx, DunV8Value* val);
bool dun_v8_is_function(DunV8Context* ctx, DunV8Value* val);

// Properties
void dun_v8_set_property(DunV8Context* ctx, DunV8Value* obj,
    const char* name, DunV8Value* val);
DunV8Value* dun_v8_get_property(DunV8Context* ctx, DunV8Value* obj,
    const char* name);

// Ref counting
void dun_v8_value_ref(DunV8Context* ctx, DunV8Value* val);
void dun_v8_value_unref(DunV8Context* ctx, DunV8Value* val);

#ifdef __cplusplus
}
#endif
