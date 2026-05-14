// v8shim.h — extern "C" wrapper for V8's C++ API.
#ifndef DUN_V8SHIM_H
#define DUN_V8SHIM_H

#include <stddef.h>

#ifdef __cplusplus
#include <type_traits>
extern "C" {
#endif

typedef struct DunV8Isolate DunV8Isolate;
typedef struct DunV8Context DunV8Context;
typedef struct DunV8Value DunV8Value;

typedef DunV8Value* (*DunV8NativeCallback)(
    DunV8Context* ctx, DunV8Value* this_val,
    int argc, DunV8Value** argv, void* data);

#ifdef __cplusplus
static_assert(sizeof(DunV8NativeCallback) == sizeof(void*),
    "callback must be pointer-sized for FFI");
static_assert(sizeof(size_t) >= 4,
    "size_t too small for V8 memory limits");
#endif

/* Isolate */
DunV8Isolate* dun_v8_isolate_new(void);
void dun_v8_isolate_dispose(DunV8Isolate* isolate);

/* Context */
DunV8Context* dun_v8_context_new(DunV8Isolate* isolate);
void dun_v8_context_free(DunV8Context* ctx);

/* Evaluation */
DunV8Value* dun_v8_eval(DunV8Context* ctx, const char* source,
    size_t source_len, const char* filename, int* is_error);

/* Value creation */
DunV8Value* dun_v8_new_undefined(DunV8Context* ctx);
DunV8Value* dun_v8_new_null(DunV8Context* ctx);
DunV8Value* dun_v8_new_bool(DunV8Context* ctx, int val);
DunV8Value* dun_v8_new_int(DunV8Context* ctx, int val);
DunV8Value* dun_v8_new_number(DunV8Context* ctx, double val);
DunV8Value* dun_v8_new_string(DunV8Context* ctx, const char* str, size_t len);
DunV8Value* dun_v8_new_object(DunV8Context* ctx);
DunV8Value* dun_v8_new_array(DunV8Context* ctx, int length);
DunV8Value* dun_v8_new_function(DunV8Context* ctx, DunV8NativeCallback cb,
    const char* name, void* data);

/* Value extraction */
const char* dun_v8_value_to_string(DunV8Context* ctx, DunV8Value* val, size_t* len);
void dun_v8_free_string(const char* str);
int dun_v8_value_to_int(DunV8Context* ctx, DunV8Value* val);
double dun_v8_value_to_number(DunV8Context* ctx, DunV8Value* val);
int dun_v8_value_to_bool(DunV8Context* ctx, DunV8Value* val);

/* Type checks */
int dun_v8_value_is_undefined(DunV8Value* val);
int dun_v8_value_is_null(DunV8Value* val);
int dun_v8_value_is_bool(DunV8Value* val);
int dun_v8_value_is_int(DunV8Value* val);
int dun_v8_value_is_number(DunV8Value* val);
int dun_v8_value_is_string(DunV8Value* val);
int dun_v8_value_is_object(DunV8Value* val);
int dun_v8_value_is_function(DunV8Value* val);
int dun_v8_value_is_array(DunV8Value* val);

/* Properties */
DunV8Value* dun_v8_get_property(DunV8Context* ctx, DunV8Value* obj, const char* name);
void dun_v8_set_property(DunV8Context* ctx, DunV8Value* obj, const char* name, DunV8Value* val);
DunV8Value* dun_v8_get_property_index(DunV8Context* ctx, DunV8Value* obj, unsigned int idx);
void dun_v8_set_property_index(DunV8Context* ctx, DunV8Value* obj, unsigned int idx, DunV8Value* val);
DunV8Value* dun_v8_global(DunV8Context* ctx);

/* Typed arrays */
DunV8Value* dun_v8_new_uint8array(DunV8Context* ctx,
    const unsigned char* data, size_t len);
unsigned char* dun_v8_typed_array_data(DunV8Context* ctx,
    DunV8Value* val, size_t* out_len);

/* Reference management */
void dun_v8_value_ref(DunV8Value* val);
void dun_v8_value_unref(DunV8Value* val);

/* Exceptions */
const char* dun_v8_get_exception(DunV8Context* ctx, size_t* len);
DunV8Value* dun_v8_throw_error(DunV8Context* ctx, const char* msg);
DunV8Value* dun_v8_throw_type_error(DunV8Context* ctx, const char* msg);
DunV8Value* dun_v8_throw_range_error(DunV8Context* ctx, const char* msg);

/* Function call */
DunV8Value* dun_v8_call(DunV8Context* ctx, DunV8Value* func,
    DunV8Value* this_obj, int argc, DunV8Value** argv, int* is_error);

/* Promises */
DunV8Value* dun_v8_new_promise(DunV8Context* ctx,
    DunV8Value** resolve_out, DunV8Value** reject_out);

/* Microtasks */
int dun_v8_has_pending_microtasks(DunV8Isolate* isolate);
void dun_v8_drain_microtasks(DunV8Isolate* isolate);

/* Context data */
void dun_v8_set_context_data(DunV8Context* ctx, void* data);
void* dun_v8_get_context_data(DunV8Context* ctx);

/* Limits */
void dun_v8_set_memory_limit(DunV8Isolate* isolate, size_t bytes);
void dun_v8_set_stack_limit(DunV8Isolate* isolate, size_t bytes);

/* Garbage collection */
void dun_v8_collect_garbage(DunV8Isolate* isolate);

/* Version */
const char* dun_v8_version(void);

#ifdef __cplusplus
}
#endif

#endif /* DUN_V8SHIM_H */
