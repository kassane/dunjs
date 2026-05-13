// Test: ldc2 -H -Hf=test_h.di -c test_h.d
// Verifies D interface (.di) generation

module tools.bindgen_tests.test_h;

extern(C) nothrow @nogc:

struct JSValue {
    long tag;
    void* ptr;
}

alias JSContext = void;
alias JSRuntime = void;

JSValue JS_NewInt32(JSContext* ctx, int val);
JSValue JS_NewFloat64(JSContext* ctx, double val);
JSValue JS_NewString(JSContext* ctx, const(char)* str);
void JS_FreeValue(JSContext* ctx, JSValue val);
int JS_IsException(JSValue val);
const(char)* JS_ToCString(JSContext* ctx, JSValue val);
void JS_FreeCString(JSContext* ctx, const(char)* str);
