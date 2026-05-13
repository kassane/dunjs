// Test: ldc2 -H -Hf=test_importc.di test_importc.c
// ImportC: D compiler processes C source directly, generates .di interface

#include <stddef.h>
#include <stdint.h>

typedef struct DunV8Isolate DunV8Isolate;
typedef struct DunV8Context DunV8Context;
typedef struct DunV8Value DunV8Value;

typedef DunV8Value* (*DunV8NativeCallback)(
    DunV8Context* ctx, DunV8Value* this_val,
    int argc, DunV8Value** argv, void* data);

DunV8Isolate* dun_v8_isolate_new(void);
void dun_v8_isolate_dispose(DunV8Isolate* isolate);
DunV8Context* dun_v8_context_new(DunV8Isolate* isolate);
void dun_v8_context_free(DunV8Context* ctx);

DunV8Value* dun_v8_eval(DunV8Context* ctx, const char* source,
    size_t len, const char* filename, int* is_error);

DunV8Value* dun_v8_new_string(DunV8Context* ctx, const char* str, size_t len);
DunV8Value* dun_v8_new_number(DunV8Context* ctx, double num);
DunV8Value* dun_v8_new_bool(DunV8Context* ctx, int val);

int dun_v8_value_is_string(DunV8Value* val);
int dun_v8_value_is_number(DunV8Value* val);

void dun_v8_set_property(DunV8Context* ctx, DunV8Value* obj,
    const char* name, DunV8Value* val);
DunV8Value* dun_v8_get_property(DunV8Context* ctx, DunV8Value* obj,
    const char* name);
