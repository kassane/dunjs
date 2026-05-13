// test_stubs.cpp — Stub v8shim functions for link-only ABI tests.

#include "v8shim.h"
#include <cstdlib>
#include <cstring>

extern "C" {

DunV8Isolate* dun_v8_isolate_new(void) { return nullptr; }
void dun_v8_isolate_dispose(DunV8Isolate* isolate) { (void)isolate; }

DunV8Context* dun_v8_context_new(DunV8Isolate* isolate) { (void)isolate; return nullptr; }
void dun_v8_context_free(DunV8Context* ctx) { (void)ctx; }

DunV8Value* dun_v8_eval(DunV8Context* ctx, const char* source,
    size_t source_len, const char* filename, int* is_error) {
    (void)ctx; (void)source; (void)source_len; (void)filename;
    if (is_error) *is_error = 1;
    return nullptr;
}

DunV8Value* dun_v8_new_undefined(DunV8Context* ctx) { (void)ctx; return nullptr; }
DunV8Value* dun_v8_new_null(DunV8Context* ctx) { (void)ctx; return nullptr; }
DunV8Value* dun_v8_new_bool(DunV8Context* ctx, int val) { (void)ctx; (void)val; return nullptr; }
DunV8Value* dun_v8_new_int(DunV8Context* ctx, int val) { (void)ctx; (void)val; return nullptr; }
DunV8Value* dun_v8_new_number(DunV8Context* ctx, double val) { (void)ctx; (void)val; return nullptr; }
DunV8Value* dun_v8_new_string(DunV8Context* ctx, const char* str, size_t len) {
    (void)ctx; (void)str; (void)len; return nullptr;
}
DunV8Value* dun_v8_new_object(DunV8Context* ctx) { (void)ctx; return nullptr; }
DunV8Value* dun_v8_new_array(DunV8Context* ctx, int length) { (void)ctx; (void)length; return nullptr; }
DunV8Value* dun_v8_new_function(DunV8Context* ctx, DunV8NativeCallback cb,
    const char* name, void* data) {
    (void)ctx; (void)cb; (void)name; (void)data; return nullptr;
}

const char* dun_v8_value_to_string(DunV8Context* ctx, DunV8Value* val, size_t* len) {
    (void)ctx; (void)val; if (len) *len = 0; return nullptr;
}
void dun_v8_free_string(const char* str) { (void)str; }
int dun_v8_value_to_int(DunV8Context* ctx, DunV8Value* val) { (void)ctx; (void)val; return 0; }
double dun_v8_value_to_number(DunV8Context* ctx, DunV8Value* val) { (void)ctx; (void)val; return 0.0; }
int dun_v8_value_to_bool(DunV8Context* ctx, DunV8Value* val) { (void)ctx; (void)val; return 0; }

int dun_v8_value_is_undefined(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_null(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_bool(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_int(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_number(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_string(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_object(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_function(DunV8Value* val) { (void)val; return 0; }
int dun_v8_value_is_array(DunV8Value* val) { (void)val; return 0; }

DunV8Value* dun_v8_get_property(DunV8Context* ctx, DunV8Value* obj, const char* name) {
    (void)ctx; (void)obj; (void)name; return nullptr;
}
void dun_v8_set_property(DunV8Context* ctx, DunV8Value* obj, const char* name, DunV8Value* val) {
    (void)ctx; (void)obj; (void)name; (void)val;
}
DunV8Value* dun_v8_get_property_index(DunV8Context* ctx, DunV8Value* obj, unsigned int idx) {
    (void)ctx; (void)obj; (void)idx; return nullptr;
}
void dun_v8_set_property_index(DunV8Context* ctx, DunV8Value* obj, unsigned int idx, DunV8Value* val) {
    (void)ctx; (void)obj; (void)idx; (void)val;
}
DunV8Value* dun_v8_global(DunV8Context* ctx) { (void)ctx; return nullptr; }

DunV8Value* dun_v8_new_uint8array(DunV8Context* ctx, const unsigned char* data, size_t len) {
    (void)ctx; (void)data; (void)len; return nullptr;
}

void dun_v8_value_ref(DunV8Value* val) { (void)val; }
void dun_v8_value_unref(DunV8Value* val) { (void)val; }

const char* dun_v8_get_exception(DunV8Context* ctx, size_t* len) {
    (void)ctx; if (len) *len = 0; return nullptr;
}
DunV8Value* dun_v8_throw_error(DunV8Context* ctx, const char* msg) { (void)ctx; (void)msg; return nullptr; }
DunV8Value* dun_v8_throw_type_error(DunV8Context* ctx, const char* msg) { (void)ctx; (void)msg; return nullptr; }
DunV8Value* dun_v8_throw_range_error(DunV8Context* ctx, const char* msg) { (void)ctx; (void)msg; return nullptr; }

DunV8Value* dun_v8_call(DunV8Context* ctx, DunV8Value* func,
    DunV8Value* this_obj, int argc, DunV8Value** argv, int* is_error) {
    (void)ctx; (void)func; (void)this_obj; (void)argc; (void)argv;
    if (is_error) *is_error = 1;
    return nullptr;
}

DunV8Value* dun_v8_new_promise(DunV8Context* ctx,
    DunV8Value** resolve_out, DunV8Value** reject_out) {
    (void)ctx;
    if (resolve_out) *resolve_out = nullptr;
    if (reject_out) *reject_out = nullptr;
    return nullptr;
}

int dun_v8_has_pending_microtasks(DunV8Isolate* isolate) { (void)isolate; return 0; }
void dun_v8_drain_microtasks(DunV8Isolate* isolate) { (void)isolate; }

void dun_v8_set_context_data(DunV8Context* ctx, void* data) { (void)ctx; (void)data; }
void* dun_v8_get_context_data(DunV8Context* ctx) { (void)ctx; return nullptr; }

void dun_v8_set_memory_limit(DunV8Isolate* isolate, size_t bytes) { (void)isolate; (void)bytes; }
void dun_v8_set_stack_limit(DunV8Isolate* isolate, size_t bytes) { (void)isolate; (void)bytes; }

void dun_v8_collect_garbage(DunV8Isolate* isolate) { (void)isolate; }

const char* dun_v8_version(void) { return "stub-0.0.0"; }

} /* extern "C" */
