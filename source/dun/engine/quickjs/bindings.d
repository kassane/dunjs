/// Raw extern(C) declarations for the QuickJS-NG C API.
///
/// This module is a manual translation of quickjs.h into D.
/// All functions are extern(C) nothrow @nogc.
/// Inline functions from quickjs.h are reimplemented in D.
///
/// See: https://quickjs-ng.github.io/quickjs/developer-guide/intro/
module dun.engine.quickjs.bindings;

// --- Opaque handle types ---
struct JSRuntime;
struct JSContext;
struct JSMallocState;
struct JSModuleDef;

// --- JSValue representation ---
// QuickJS-NG struct-based layout (non-NaN-boxing, 64-bit).
// Matches: struct JSValue { JSValueUnion u; int64_t tag; }
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

// --- Tag constants (must match quickjs.h enum JSValueTag) ---
enum : long
{
    JS_TAG_FIRST = -9,
    JS_TAG_BIG_INT = -9,
    JS_TAG_SYMBOL = -8,
    JS_TAG_STRING = -7,
    JS_TAG_MODULE = -3,
    JS_TAG_FUNCTION_BYTECODE = -2,
    JS_TAG_OBJECT = -1,
    JS_TAG_INT = 0,
    JS_TAG_BOOL = 1,
    JS_TAG_NULL = 2,
    JS_TAG_UNDEFINED = 3,
    JS_TAG_UNINITIALIZED = 4,
    JS_TAG_CATCH_OFFSET = 5,
    JS_TAG_EXCEPTION = 6,
    JS_TAG_FLOAT64 = 7,
}

// --- Inline value constructors (reimplemented from quickjs.h) ---

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

// Inline reimplementations of static inline C functions
JSValue JS_NewBool(JSContext* ctx, int val) pure nothrow @nogc @safe
{
    JSValue v;
    v.int32 = (val != 0) ? 1 : 0;
    v.tag = JS_TAG_BOOL;
    return v;
}

JSValue JS_NewInt32(JSContext* ctx, int val) pure nothrow @nogc @safe
{
    JSValue v;
    v.int32 = val;
    v.tag = JS_TAG_INT;
    return v;
}

JSValue JS_NewFloat64(JSContext* ctx, double val) pure nothrow @nogc @safe
{
    JSValue v;
    v.float64 = val;
    v.tag = JS_TAG_FLOAT64;
    return v;
}

JSValue JS_NewCFunction(JSContext* ctx, JSCFunction func,
    const(char)* name, int length) nothrow @nogc @trusted
{
    return JS_NewCFunction2(ctx, func, name, length, JS_CFUNC_generic, 0);
}

int JS_IsUndefined(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_UNDEFINED ? 1 : 0;
}

int JS_IsNull(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_NULL ? 1 : 0;
}

int JS_IsException(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_EXCEPTION ? 1 : 0;
}

int JS_IsBool(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_BOOL ? 1 : 0;
}

int JS_IsNumber(JSValueConst v) pure nothrow @nogc @safe
{
    return (v.tag == JS_TAG_INT || v.tag == JS_TAG_FLOAT64) ? 1 : 0;
}

int JS_IsString(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_STRING ? 1 : 0;
}

int JS_IsObject(JSValueConst v) pure nothrow @nogc @safe
{
    return v.tag == JS_TAG_OBJECT ? 1 : 0;
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

// --- CFunction enum ---
enum
{
    JS_CFUNC_generic = 0,
    JS_CFUNC_generic_magic = 1,
    JS_CFUNC_constructor = 2,
    JS_CFUNC_constructor_magic = 3,
    JS_CFUNC_constructor_or_func = 4,
    JS_CFUNC_constructor_or_func_magic = 5,
    JS_CFUNC_f_f = 6,
    JS_CFUNC_f_f_f = 7,
    JS_CFUNC_getter = 8,
    JS_CFUNC_setter = 9,
    JS_CFUNC_getter_magic = 10,
    JS_CFUNC_setter_magic = 11,
    JS_CFUNC_iterator_next = 12,
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

// --- CFunction list entry ---
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
    }
}

// ==========================================================================
// Core QuickJS-NG C API (exported symbols only)
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
bool JS_IsJobPending(JSRuntime* rt);
int JS_ExecutePendingJob(JSRuntime* rt, JSContext** pctx);
JSContext* JS_GetPendingJobContext(JSRuntime* rt);

// --- Equality ---
bool JS_IsStrictEqual(JSContext* ctx, JSValueConst op1, JSValueConst op2);
bool JS_IsSameValue(JSContext* ctx, JSValueConst op1, JSValueConst op2);
bool JS_IsSameValueZero(JSContext* ctx, JSValueConst op1, JSValueConst op2);

// --- Promise rejection tracker ---
alias JSHostPromiseRejectionTracker = extern (C) void function(
    JSContext* ctx, JSValueConst promise, JSValueConst reason,
    bool is_handled, void* opaque) nothrow;

void JS_SetHostPromiseRejectionTracker(JSRuntime* rt,
    JSHostPromiseRejectionTracker cb, void* opaque);

// --- Runtime GC ---
void JS_RunGC(JSRuntime* rt);

// --- Version ---
const(char)* JS_GetVersion();

// --- Context lifecycle ---
JSContext* JS_NewContext(JSRuntime* rt);
JSContext* JS_DupContext(JSContext* ctx);
void JS_FreeContext(JSContext* ctx);
JSRuntime* JS_GetRuntime(JSContext* ctx);
void JS_SetContextOpaque(JSContext* ctx, void* opaque);
void* JS_GetContextOpaque(JSContext* ctx);
int JS_AddPerformance(JSContext* ctx);

// --- Evaluation ---
JSValue JS_Eval(JSContext* ctx, const(char)* input, size_t input_len,
    const(char)* filename, int eval_flags);
JSValue JS_EvalFunction(JSContext* ctx, JSValue fun_obj);
JSValue JS_EvalThis(JSContext* ctx, JSValueConst this_obj,
    const(char)* input, size_t input_len,
    const(char)* filename, int eval_flags);

// --- QuickJS allocator (uses runtime's allocator, default = system malloc) ---
void* js_malloc(JSContext* ctx, size_t size) nothrow;
void js_free(JSContext* ctx, void* ptr) nothrow;
char* js_strdup(JSContext* ctx, const(char)* str) nothrow;

// --- Value lifecycle (reference counting) ---
JSValue JS_DupValue(JSContext* ctx, JSValueConst v);
JSValue JS_DupValueRT(JSRuntime* rt, JSValueConst v);
void JS_FreeValue(JSContext* ctx, JSValue v);
void JS_FreeValueRT(JSRuntime* rt, JSValue v);

// --- Value extraction ---
int JS_ToBool(JSContext* ctx, JSValueConst val);
int JS_ToInt32(JSContext* ctx, int* pres, JSValueConst val);
int JS_ToInt64(JSContext* ctx, long* pres, JSValueConst val);
int JS_ToFloat64(JSContext* ctx, double* pres, JSValueConst val);
const(char)* JS_ToCStringLen2(JSContext* ctx, size_t* plen, JSValueConst val, bool cesu8);
void JS_FreeCString(JSContext* ctx, const(char)* ptr);

// --- Value constructors (exported from library) ---
JSValue JS_NewStringLen(JSContext* ctx, const(char)* str, size_t len);
JSValue JS_NewObject(JSContext* ctx);
JSValue JS_NewArray(JSContext* ctx);
JSValue JS_NewError(JSContext* ctx);
JSValue JS_NewInt64(JSContext* ctx, long val);
JSValue JS_NewNumber(JSContext* ctx, double d);
JSValue JS_NewBigInt64(JSContext* ctx, long v);
JSValue JS_NewBigUint64(JSContext* ctx, ulong v);

// --- Function constructors ---
JSValue JS_NewCFunction2(JSContext* ctx, JSCFunction func,
    const(char)* name, int length, int cproto, int magic);

// --- Object property access ---
JSValue JS_GetGlobalObject(JSContext* ctx);
int JS_GetLength(JSContext* ctx, JSValueConst obj, long* pres);
int JS_SetLength(JSContext* ctx, JSValueConst obj, long len);
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

// --- Type checks (exported) ---
bool JS_IsArray(JSValueConst val);
bool JS_IsFunction(JSContext* ctx, JSValueConst val);
bool JS_IsError(JSValueConst val);             // ctx dropped in v0.14.0
bool JS_IsPromise(JSValueConst val);
bool JS_IsArrayBuffer(JSValueConst obj);
bool JS_HasException(JSContext* ctx);

// --- Module detection ---
bool JS_DetectModule(const(char)* input, size_t input_len);

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
JSValue JS_Invoke(JSContext* ctx, JSValueConst this_val, JSAtom atom,
    int argc, JSValueConst* argv);
JSValue JS_CallConstructor(JSContext* ctx, JSValueConst func_obj,
    int argc, JSValueConst* argv);

// --- ArrayBuffer ---
JSValue JS_NewArrayBufferCopy(JSContext* ctx, const(ubyte)* buf, size_t len);
ubyte* JS_GetArrayBuffer(JSContext* ctx, size_t* psize, JSValueConst obj);

// --- Atom ---
JSAtom JS_NewAtom(JSContext* ctx, const(char)* str);
JSAtom JS_NewAtomLen(JSContext* ctx, const(char)* str, size_t len);
void JS_FreeAtom(JSContext* ctx, JSAtom v);
const(char)* JS_AtomToCString(JSContext* ctx, JSAtom atom);
JSValue JS_AtomToString(JSContext* ctx, JSAtom atom);
JSValue JS_AtomToValue(JSContext* ctx, JSAtom atom);

// --- Property by atom ---
int JS_SetProperty(JSContext* ctx, JSValueConst this_obj,
    JSAtom prop, JSValue val);
JSValue JS_GetProperty(JSContext* ctx, JSValueConst this_obj, JSAtom prop);
int JS_DefinePropertyValue(JSContext* ctx, JSValueConst this_obj,
    JSAtom prop, JSValue val, int flags);

// --- Module resolution ---
int JS_ResolveModule(JSContext* ctx, JSValueConst obj);

// --- Constructor ---
int JS_SetConstructor(JSContext* ctx, JSValueConst func_obj,
    JSValueConst proto);
bool JS_SetConstructorBit(JSContext* ctx, JSValueConst func_obj, bool val);

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
int JS_SetOpaque(JSValueConst obj, void* opaque);
void* JS_GetOpaque(JSValueConst obj, JSClassID class_id);
void* JS_GetOpaque2(JSContext* ctx, JSValueConst obj, JSClassID class_id);
void JS_SetClassProto(JSContext* ctx, JSClassID class_id, JSValue obj);

// --- Promise ---
JSValue JS_NewPromiseCapability(JSContext* ctx, JSValue* resolving_funcs);
JSValue JS_PromiseResult(JSContext* ctx, JSValueConst promise);

enum JSPromiseStateEnum
{
    JS_PROMISE_PENDING,
    JS_PROMISE_FULFILLED,
    JS_PROMISE_REJECTED,
}

JSPromiseStateEnum JS_PromiseState(JSContext* ctx, JSValueConst promise);

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
