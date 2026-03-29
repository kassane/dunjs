/// RAII wrapper for JSValue.
///
/// Automatically calls JS_FreeValue on scope exit.
/// Copy constructor calls JS_DupValue to maintain reference count.
module dun.engine.value;

import dun.engine.bindings;

/// Ref-counted RAII wrapper for JSValue.
struct JSVal
{
    private JSContext* ctx;
    private JSValue val;
    private bool owned = true;

    this(JSContext* ctx, JSValue val) @trusted
    {
        this.ctx = ctx;
        this.val = val;
    }

    this(ref return scope JSVal other) @trusted
    {
        this.ctx = other.ctx;
        this.val = JS_DupValue(other.ctx, other.val);
        this.owned = true;
    }

    ~this() @trusted
    {
        if (owned && ctx !is null)
            JS_FreeValue(ctx, val);
    }

    // --- Type checks ---

    bool isException() const @trusted
    {
        return JS_IsException(val) != 0;
    }

    bool isUndefined() const @trusted
    {
        return JS_IsUndefined(val) != 0;
    }

    bool isNull() const @trusted
    {
        return JS_IsNull(val) != 0;
    }

    bool isString() const @trusted
    {
        return JS_IsString(val) != 0;
    }

    bool isNumber() const @trusted
    {
        return JS_IsNumber(val) != 0;
    }

    bool isObject() const @trusted
    {
        return JS_IsObject(val) != 0;
    }

    bool isBool() const @trusted
    {
        return JS_IsBool(val) != 0;
    }

    // --- Value extraction ---

    /// Convert to D string. The returned string is GC-allocated.
    string toString() @trusted
    {
        size_t len;
        const(char)* cstr = JS_ToCStringLen2(ctx, &len, val, 0);
        if (cstr is null)
            return "<exception>";
        scope (exit)
            JS_FreeCString(ctx, cstr);
        return cstr[0 .. len].idup;
    }

    int toInt32() @trusted
    {
        int result;
        JS_ToInt32(ctx, &result, val);
        return result;
    }

    double toFloat64() @trusted
    {
        double result;
        JS_ToFloat64(ctx, &result, val);
        return result;
    }

    bool toBool() @trusted
    {
        return JS_ToBool(ctx, val) != 0;
    }

    // --- Property access ---

    /// Get a property by name.
    JSVal getProperty(string name) @trusted
    {
        import std.string : toStringz;

        return JSVal(ctx, JS_GetPropertyStr(ctx, val, name.toStringz));
    }

    /// Set a property by name. Transfers ownership of the value to the JS engine.
    void setProperty(string name, JSVal value) @trusted
    {
        import std.string : toStringz;

        value.owned = false; // Transfer ownership
        JS_SetPropertyStr(ctx, val, name.toStringz, value.val);
    }

    /// Set a property with a raw JSValue.
    void setPropertyRaw(string name, JSValue value) @trusted
    {
        import std.string : toStringz;

        JS_SetPropertyStr(ctx, val, name.toStringz, value);
    }

    // --- Raw access ---

    /// Access the raw JSValue (for passing to C API).
    JSValue raw() @trusted
    {
        return val;
    }

    /// Access the context this value belongs to.
    JSContext* context() @trusted
    {
        return ctx;
    }

    /// Release ownership without freeing (for transferring to C API).
    JSValue release() @trusted
    {
        owned = false;
        return val;
    }
}
