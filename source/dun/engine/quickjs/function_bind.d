/// Helpers for bridging D functions to JavaScript.
///
/// Provides utilities for argument conversion between D and JS types.
module dun.engine.quickjs.function_bind;

import dun.engine.quickjs.bindings;

/// Convert a D string to a JS string value.
JSValue toJSValue(JSContext* ctx, string s) @trusted nothrow
{
    if (s is null || s.length == 0)
        return JS_NewStringLen(ctx, "".ptr, 0);
    return JS_NewStringLen(ctx, s.ptr, s.length);
}

/// Convert a JS value argument to a D string.
/// Returns empty string on failure.
string jsArgToString(JSContext* ctx, JSValueConst val) @trusted
{
    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, val, 0);
    if (cstr is null)
        return "";
    scope (exit)
        JS_FreeCString(ctx, cstr);
    return cstr[0 .. len].idup;
}

/// Convert a JS value argument to int32.
int jsArgToInt32(JSContext* ctx, JSValueConst val) @trusted nothrow
{
    int result;
    JS_ToInt32(ctx, &result, val);
    return result;
}

/// Convert a JS value argument to float64.
double jsArgToFloat64(JSContext* ctx, JSValueConst val) @trusted nothrow
{
    double result;
    JS_ToFloat64(ctx, &result, val);
    return result;
}

/// Create a JS number from an int.
JSValue toJSInt(JSContext* ctx, int v) @trusted nothrow
{
    return JS_NewInt32(ctx, v);
}

/// Create a JS number from a double.
JSValue toJSFloat(JSContext* ctx, double v) @trusted nothrow
{
    return JS_NewFloat64(ctx, v);
}

/// Create a JS boolean.
JSValue toJSBool(JSContext* ctx, bool v) @trusted nothrow
{
    return JS_NewBool(ctx, v ? 1 : 0);
}
