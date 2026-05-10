/// RAII wrapper for JSContext.
///
/// Provides safe eval, property access, and global function registration.
/// Automatically frees the context on destruction.
module dun.engine.quickjs.context;

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.value;
import dun.engine.quickjs.runtime;

/// RAII wrapper for JSContext*. Non-copyable.
struct Context
{
    private JSContext* ctx;

    @disable this(this);

    /// Create a new context bound to the given runtime.
    static Context create(ref Runtime rt) @trusted
    {
        auto ctx = JS_NewContext(rt.handle());
        assert(ctx !is null, "Failed to create JSContext");
        return Context(ctx);
    }

    ~this() @trusted
    {
        if (ctx !is null)
            JS_FreeContext(ctx);
    }

    /// Evaluate JavaScript source code. Returns a managed JSVal.
    JSVal eval(const(char)[] source, string filename = "<eval>",
        int flags = JS_EVAL_TYPE_GLOBAL) @trusted
    {
        import std.string : toStringz;

        auto result = JS_Eval(ctx, source.ptr, source.length,
            filename.toStringz, flags);
        return JSVal(ctx, result);
    }

    /// Get the global object.
    JSVal globalObject() @trusted
    {
        return JSVal(ctx, JS_GetGlobalObject(ctx));
    }

    /// Register a D function as a global JS function.
    void setGlobalFunction(string name, JSCFunction func, int argCount = 0) @trusted
    {
        import std.string : toStringz;

        auto global = JS_GetGlobalObject(ctx);
        auto fnVal = JS_NewCFunction(ctx, func, name.toStringz, argCount);
        JS_SetPropertyStr(ctx, global, name.toStringz, fnVal);
        JS_FreeValue(ctx, global);
    }

    /// Get the last exception as a D string.
    string getException() @trusted
    {
        auto exc = JS_GetException(ctx);
        scope (exit)
            JS_FreeValue(ctx, exc);

        size_t len;
        const(char)* cstr = JS_ToCStringLen2(ctx, &len, exc, 0);
        if (cstr is null)
            return "<unknown exception>";
        scope (exit)
            JS_FreeCString(ctx, cstr);
        return cstr[0 .. len].idup;
    }

    /// Store an opaque pointer in the context.
    void setOpaque(void* ptr) @trusted
    {
        JS_SetContextOpaque(ctx, ptr);
    }

    /// Retrieve the opaque pointer from the context.
    void* getOpaque() @trusted
    {
        return JS_GetContextOpaque(ctx);
    }

    /// Access the raw JSContext pointer.
    JSContext* handle() @trusted
    {
        return ctx;
    }
}
