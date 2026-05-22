/// D-to-JS function bridging and argument conversion.
module dun.engine.quickjs.function_bind;

import dun.engine.quickjs.bindings;

/// Convert a D string to a JS string value.
JSValue toJSValue(JSContext* ctx, string s) @trusted nothrow
{
    assert(ctx !is null, "Null ctx in toJSValue");
    if (s is null || s.length == 0)
        return JS_NewStringLen(ctx, "".ptr, 0);
    return JS_NewStringLen(ctx, s.ptr, s.length);
}

/++
 + Convert a JS value argument to a D string.
 + Returns empty string on failure.
 +/
string jsArgToString(JSContext* ctx, JSValueConst val) nothrow @trusted
{
    assert(ctx !is null, "Null ctx in jsArgToString");
    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, val, 0);
    if (cstr is null)
        return "";
    auto result = cstr[0 .. len].idup;
    JS_FreeCString(ctx, cstr);
    return result;
}

/// Convert a JS value argument to int32.
int jsArgToInt32(JSContext* ctx, JSValueConst val) @trusted nothrow
{
    assert(ctx !is null, "Null ctx in jsArgToInt32");
    int result;
    JS_ToInt32(ctx, &result, val);
    return result;
}

/// Convert a JS value argument to float64.
double jsArgToFloat64(JSContext* ctx, JSValueConst val) @trusted nothrow
{
    assert(ctx !is null, "Null ctx in jsArgToFloat64");
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
