/// Raw extern(C) declarations for the QuickJS-NG C API.
///
/// This module is a manual translation of quickjs.h into D.
/// All functions are extern(C) nothrow @nogc.
///
/// See: https://quickjs-ng.github.io/quickjs/developer-guide/intro/
module dun.engine.quickjs.bindings;

// --- Opaque handle types ---
struct JSRuntime;
struct JSContext;
struct JSMallocState;
struct JSModuleDef;

// --- JSValue representation ---
// QuickJS uses a tagged value representation.
// On 64-bit platforms with JS_NAN_BOXING=0, JSValue is 128 bits (16 bytes).
struct JSValue
{
    union
    {
        int int32;
        double float64;
        void* ptr;
    }

    long tag;
}

alias JSValueConst = const(JSValue);
alias JSClassID = uint;
alias JSAtom = uint;

// --- Tag constants ---
enum : long
{
    JS_TAG_INT = 0,
    JS_TAG_BOOL = 1,
    JS_TAG_NULL = 2,
    JS_TAG_UNDEFINED = 3,
    JS_TAG_UNINITIALIZED = 4,
    JS_TAG_CATCH_OFFSET = 5,
    JS_TAG_EXCEPTION = 6,
    JS_TAG_FLOAT64 = 7,
    JS_TAG_OBJECT = -1,
    JS_TAG_FUNCTION_BYTECODE = -2,
    JS_TAG_MODULE = -3,
    JS_TAG_STRING = -7,
    JS_TAG_SYMBOL = -8,
    JS_TAG_BIG_INT = -9,
}

// --- Sentinel value constructors ---
JSValue JS_UNDEFINED() pure nothrow @nogc @safe
{
    JSValue v;
    v.tag = JS_TAG_UNDEFINED;
    return v;
}

JSValue JS_NULL() pure nothrow @nogc @safe
{
    JSValue v;
    v.tag = JS_TAG_NULL;
    return v;
}

JSValue JS_EXCEPTION() pure nothrow @nogc @safe
{
    JSValue v;
    v.tag = JS_TAG_EXCEPTION;
    return v;
}

JSValue JS_TRUE() pure nothrow @nogc @safe
{
    JSValue v;
    v.int32 = 1;
    v.tag = JS_TAG_BOOL;
    return v;
}

JSValue JS_FALSE() pure nothrow @nogc @safe
{
    JSValue v;
    v.int32 = 0;
    v.tag = JS_TAG_BOOL;
    return v;
}

// --- Eval flags ---
enum
{
    JS_EVAL_TYPE_GLOBAL = 0 << 0,
    JS_EVAL_TYPE_MODULE = 1 << 0,
    JS_EVAL_TYPE_DIRECT = 2 << 0,
    JS_EVAL_TYPE_INDIRECT = 3 << 0,
    JS_EVAL_TYPE_MASK = 3 << 0,
    JS_EVAL_FLAG_STRICT = 1 << 3,
    JS_EVAL_FLAG_STRIP = 1 << 4,
    JS_EVAL_FLAG_COMPILE_ONLY = 1 << 5,
    JS_EVAL_FLAG_BACKTRACE_BARRIER = 1 << 6,
}

// --- C function callback types ---
alias JSCFunction = extern (C) JSValue function(
    JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow;

alias JSCFunctionMagic = extern (C) JSValue function(
    JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv,
    int magic) nothrow;

alias JSModuleInitFunc = extern (C) int function(
    JSContext* ctx, JSModuleDef* m) nothrow;

alias JSInterruptHandler = extern (C) int function(
    JSRuntime* rt, void* opaque) nothrow;

alias JSModuleNormalizeFunc = extern (C) char* function(
    JSContext* ctx, const(char)* module_base_name,
    const(char)* module_name, void* opaque) nothrow;

alias JSModuleLoaderFunc = extern (C) JSModuleDef* function(
    JSContext* ctx, const(char)* module_name,
    void* opaque) nothrow;

// --- Class definition ---
alias JSClassFinalizer = extern (C) void function(JSRuntime* rt, JSValue val) nothrow;
alias JSMarkFunc = extern (C) void function(JSRuntime* rt, JSValueConst val) nothrow;
alias JSClassGCMark = extern (C) void function(JSRuntime* rt, JSValueConst val,
    JSMarkFunc mark_func) nothrow;

struct JSClassDef
{
    const(char)* class_name;
    JSClassFinalizer finalizer;
    JSClassGCMark gc_mark;
    void* call;
    void* exotic;
}

// --- Custom malloc functions ---
struct JSMallocFunctions
{
    extern (C) void* function(JSMallocState* s, size_t size) nothrow js_malloc;
    extern (C) void function(JSMallocState* s, void* ptr) nothrow js_free;
    extern (C) void* function(JSMallocState* s, void* ptr, size_t size) nothrow js_realloc;
    extern (C) size_t function(const void* ptr) nothrow js_malloc_usable_size;
}

// --- CFunction list entry (for batch registration) ---
enum JSCFunctionEnum
{
    JS_CFUNC_generic,
    JS_CFUNC_generic_magic,
    JS_CFUNC_constructor,
    JS_CFUNC_constructor_magic,
    JS_CFUNC_constructor_or_func,
    JS_CFUNC_constructor_or_func_magic,
    JS_CFUNC_f_f,
    JS_CFUNC_f_f_f,
    JS_CFUNC_getter,
    JS_CFUNC_setter,
    JS_CFUNC_getter_magic,
    JS_CFUNC_setter_magic,
    JS_CFUNC_iterator_next,
}

struct JSCFunctionListEntry
{
    const(char)* name;
    ubyte prop_flags;
    ubyte def_type;
    short magic;

    union
    {
        struct
        {
            ubyte length;
            ubyte cproto;
            JSCFunction cfunc_generic;
        }

        // Other union members omitted for brevity;
        // extend as needed for getter/setter/etc.
    }
}

// ==========================================================================
// Core QuickJS C API functions
// ==========================================================================
extern (C) nothrow @nogc:

// --- Runtime lifecycle ---
JSRuntime* JS_NewRuntime();
JSRuntime* JS_NewRuntime2(const(JSMallocFunctions)* mf, void* opaque);
void JS_FreeRuntime(JSRuntime* rt);
void JS_SetMemoryLimit(JSRuntime* rt, size_t limit);
void JS_SetMaxStackSize(JSRuntime* rt, size_t stack_size);
void JS_SetInterruptHandler(JSRuntime* rt, JSInterruptHandler cb, void* opaque);
void* JS_GetRuntimeOpaque(JSRuntime* rt);
void JS_SetRuntimeOpaque(JSRuntime* rt, void* opaque);

// --- Job queue (Promise microtasks) ---
int JS_IsJobPending(JSRuntime* rt);
int JS_ExecutePendingJob(JSRuntime* rt, JSContext** pctx);

// --- Context lifecycle ---
JSContext* JS_NewContext(JSRuntime* rt);
void JS_FreeContext(JSContext* ctx);
JSRuntime* JS_GetRuntime(JSContext* ctx);
void JS_SetContextOpaque(JSContext* ctx, void* opaque);
void* JS_GetContextOpaque(JSContext* ctx);

// --- Evaluation ---
JSValue JS_Eval(JSContext* ctx, const(char)* input, size_t input_len,
    const(char)* filename, int eval_flags);
JSValue JS_EvalFunction(JSContext* ctx, JSValue fun_obj);

// --- Value lifecycle (reference counting) ---
JSValue JS_DupValue(JSContext* ctx, JSValueConst v);
void JS_FreeValue(JSContext* ctx, JSValue v);

// --- Value extraction ---
int JS_ToBool(JSContext* ctx, JSValueConst val);
int JS_ToInt32(JSContext* ctx, int* pres, JSValueConst val);
int JS_ToInt64(JSContext* ctx, long* pres, JSValueConst val);
int JS_ToFloat64(JSContext* ctx, double* pres, JSValueConst val);
const(char)* JS_ToCStringLen2(JSContext* ctx, size_t* plen, JSValueConst val, int cesu8);
void JS_FreeCString(JSContext* ctx, const(char)* ptr);

// --- Value constructors ---
JSValue JS_NewInt32(JSContext* ctx, int val);
JSValue JS_NewInt64(JSContext* ctx, long val);
JSValue JS_NewFloat64(JSContext* ctx, double val);
JSValue JS_NewBool(JSContext* ctx, int val);
JSValue JS_NewString(JSContext* ctx, const(char)* str);
JSValue JS_NewStringLen(JSContext* ctx, const(char)* str, size_t len);
JSValue JS_NewObject(JSContext* ctx);
JSValue JS_NewArray(JSContext* ctx);
JSValue JS_NewError(JSContext* ctx);

// --- Function constructors ---
JSValue JS_NewCFunction(JSContext* ctx, JSCFunction func,
    const(char)* name, int length);
JSValue JS_NewCFunction2(JSContext* ctx, JSCFunction func,
    const(char)* name, int length, int cproto, int magic);

// --- Object property access ---
JSValue JS_GetGlobalObject(JSContext* ctx);
int JS_SetPropertyStr(JSContext* ctx, JSValueConst this_obj,
    const(char)* prop, JSValue val);
JSValue JS_GetPropertyStr(JSContext* ctx, JSValueConst this_obj,
    const(char)* prop);
int JS_SetPropertyUint32(JSContext* ctx, JSValueConst this_obj,
    uint idx, JSValue val);
JSValue JS_GetPropertyUint32(JSContext* ctx, JSValueConst this_obj,
    uint idx);
int JS_DefinePropertyValueStr(JSContext* ctx, JSValueConst this_obj,
    const(char)* prop, JSValue val, int flags);
int JS_HasProperty(JSContext* ctx, JSValueConst this_obj, JSAtom prop);
int JS_DeleteProperty(JSContext* ctx, JSValueConst obj, JSAtom prop, int flags);

// --- Type checks ---
int JS_IsNumber(JSValueConst v);
int JS_IsString(JSValueConst v);
int JS_IsObject(JSValueConst v);
int JS_IsArray(JSContext* ctx, JSValueConst val);
int JS_IsFunction(JSContext* ctx, JSValueConst val);
int JS_IsUndefined(JSValueConst v);
int JS_IsNull(JSValueConst v);
int JS_IsException(JSValueConst v);
int JS_IsBool(JSValueConst v);
int JS_IsError(JSContext* ctx, JSValueConst val);

// --- Exceptions ---
JSValue JS_GetException(JSContext* ctx);
JSValue JS_Throw(JSContext* ctx, JSValue obj);
JSValue JS_ThrowTypeError(JSContext* ctx, const(char)* fmt, ...);
JSValue JS_ThrowRangeError(JSContext* ctx, const(char)* fmt, ...);
JSValue JS_ThrowReferenceError(JSContext* ctx, const(char)* fmt, ...);
JSValue JS_ThrowInternalError(JSContext* ctx, const(char)* fmt, ...);

// --- Function calls ---
JSValue JS_Call(JSContext* ctx, JSValueConst func_obj,
    JSValueConst this_obj, int argc, JSValueConst* argv);

// --- Modules ---
JSModuleDef* JS_NewCModule(JSContext* ctx, const(char)* name_str,
    JSModuleInitFunc func);
int JS_AddModuleExport(JSContext* ctx, JSModuleDef* m, const(char)* name_str);
int JS_SetModuleExport(JSContext* ctx, JSModuleDef* m,
    const(char)* name_str, JSValue val);
void JS_SetModuleLoaderFunc(JSRuntime* rt,
    JSModuleNormalizeFunc module_normalize,
    JSModuleLoaderFunc module_loader,
    void* opaque);

// --- Classes ---
JSClassID JS_NewClassID(JSRuntime* rt, JSClassID* pclass_id);
int JS_NewClass(JSRuntime* rt, JSClassID class_id, const(JSClassDef)* class_def);
JSValue JS_NewObjectClass(JSContext* ctx, int class_id);
void JS_SetOpaque(JSValue obj, void* opaque);
void* JS_GetOpaque(JSValueConst obj, JSClassID class_id);
void* JS_GetOpaque2(JSContext* ctx, JSValueConst obj, JSClassID class_id);
void JS_SetClassProto(JSContext* ctx, JSClassID class_id, JSValue obj);

// --- Promise ---
JSValue JS_NewPromiseCapability(JSContext* ctx, JSValue* resolving_funcs);

// --- JSON ---
JSValue JS_ParseJSON(JSContext* ctx, const(char)* buf, size_t buf_len,
    const(char)* filename);
JSValue JS_JSONStringify(JSContext* ctx, JSValueConst obj,
    JSValueConst replacer, JSValueConst space0);

// --- Property flags ---
enum
{
    JS_PROP_CONFIGURABLE = 1 << 0,
    JS_PROP_WRITABLE = 1 << 1,
    JS_PROP_ENUMERABLE = 1 << 2,
    JS_PROP_C_W_E = JS_PROP_CONFIGURABLE | JS_PROP_WRITABLE | JS_PROP_ENUMERABLE,
    JS_PROP_HAS_SHIFT = 8,
    JS_PROP_HAS_CONFIGURABLE = 1 << 8,
    JS_PROP_HAS_WRITABLE = 1 << 9,
    JS_PROP_HAS_ENUMERABLE = 1 << 10,
    JS_PROP_HAS_GET = 1 << 11,
    JS_PROP_HAS_SET = 1 << 12,
    JS_PROP_HAS_VALUE = 1 << 13,
}
