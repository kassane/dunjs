/// JS exception handling helpers.
module dun.engine.quickjs.exceptions;

import dun.engine.quickjs.bindings;

/// Extract the current exception from a context as a D string.
/// Clears the exception state.
string extractException(JSContext* ctx) @trusted
{
    assert(ctx !is null, "Null ctx in extractException");
    auto exc = JS_GetException(ctx);
    scope (exit)
        JS_FreeValue(ctx, exc);

    // Try to get the message property first
    auto msgVal = JS_GetPropertyStr(ctx, exc, "message");
    scope (exit)
        JS_FreeValue(ctx, msgVal);

    if (!JS_IsUndefined(msgVal))
    {
        size_t len;
        const(char)* cstr = JS_ToCStringLen2(ctx, &len, msgVal, 0);
        if (cstr !is null)
        {
            scope (exit)
                JS_FreeCString(ctx, cstr);
            return cstr[0 .. len].idup;
        }
    }

    // Fall back to string representation of the exception
    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, exc, 0);
    if (cstr is null)
        return "<unknown exception>";
    scope (exit)
        JS_FreeCString(ctx, cstr);
    return cstr[0 .. len].idup;
}

/// Extract exception with stack trace as a D string.
string extractExceptionWithStack(JSContext* ctx) @trusted
{
    assert(ctx !is null, "Null ctx in extractExceptionWithStack");
    auto exc = JS_GetException(ctx);
    scope (exit)
        JS_FreeValue(ctx, exc);

    string result;

    // Get the error string
    {
        size_t len;
        const(char)* cstr = JS_ToCStringLen2(ctx, &len, exc, 0);
        if (cstr !is null)
        {
            result = cstr[0 .. len].idup;
            JS_FreeCString(ctx, cstr);
        }
        else
        {
            result = "<unknown exception>";
        }
    }

    // Try to get the stack property
    if (JS_IsObject(exc))
    {
        auto stackVal = JS_GetPropertyStr(ctx, exc, "stack");
        scope (exit)
            JS_FreeValue(ctx, stackVal);

        if (!JS_IsUndefined(stackVal))
        {
            size_t len;
            const(char)* cstr = JS_ToCStringLen2(ctx, &len, stackVal, 0);
            if (cstr !is null)
            {
                result ~= "\n" ~ cstr[0 .. len].idup;
                JS_FreeCString(ctx, cstr);
            }
        }
    }

    return result;
}
