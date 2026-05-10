module dun.engine.quickjs.backend;

import dun.engine.iface;
import dun.engine.quickjs.bindings;

class QuickJSEngine : IJSEngine
{
    private JSRuntime* rt;
    private JSContext* ctx;

    void initialize(EngineConfig config)
    {
        rt = JS_NewRuntime();
        assert(rt !is null, "Failed to create JSRuntime");
        ctx = JS_NewContext(rt);
        assert(ctx !is null, "Failed to create JSContext");

        if (config.memoryLimit > 0)
            JS_SetMemoryLimit(rt, config.memoryLimit);
        if (config.maxStackSize > 0)
            JS_SetMaxStackSize(rt, config.maxStackSize);
    }

    void shutdown()
    {
        if (ctx !is null)
        {
            JS_FreeContext(ctx);
            ctx = null;
        }
        if (rt !is null)
        {
            JS_FreeRuntime(rt);
            rt = null;
        }
    }

    JSResult eval(const(char)[] source, string filename)
    {
        import std.string : toStringz;

        auto val = JS_Eval(ctx, source.ptr, source.length,
            filename.toStringz, JS_EVAL_TYPE_GLOBAL);
        JSResult result;
        result.value = toHandle(val);
        result.isError = JS_IsException(val) != 0;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    JSHandle newString(const(char)[] s)
    {
        return toHandle(JS_NewStringLen(ctx, s.ptr, s.length));
    }

    JSHandle newInt(int v)
    {
        return toHandle(JS_NewInt32(ctx, v));
    }

    JSHandle newFloat(double v)
    {
        return toHandle(JS_NewFloat64(ctx, v));
    }

    JSHandle newBool(bool v)
    {
        return toHandle(JS_NewBool(ctx, v ? 1 : 0));
    }

    JSHandle newObject()
    {
        return toHandle(JS_NewObject(ctx));
    }

    JSHandle newArray()
    {
        return toHandle(JS_NewArray(ctx));
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc)
    {
        // NativeCallback cannot directly bridge to QuickJS extern(C) ABI.
        // For now, use the raw C function registration via rawContext().
        assert(false, "Use registerCFunction for QuickJS backend");
    }

    string extractString(JSHandle val)
    {
        auto jsv = fromHandle(val);
        size_t len;
        const(char)* cstr = JS_ToCStringLen2(ctx, &len, jsv, 0);
        if (cstr is null)
            return "";
        auto result = cstr[0 .. len].idup;
        JS_FreeCString(ctx, cstr);
        return result;
    }

    int extractInt(JSHandle val)
    {
        auto jsv = fromHandle(val);
        int result;
        JS_ToInt32(ctx, &result, jsv);
        return result;
    }

    double extractFloat(JSHandle val)
    {
        auto jsv = fromHandle(val);
        double result;
        JS_ToFloat64(ctx, &result, jsv);
        return result;
    }

    bool extractBool(JSHandle val)
    {
        return JS_ToBool(ctx, fromHandle(val)) != 0;
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name)
    {
        import std.string : toStringz;
        return toHandle(JS_GetPropertyStr(ctx, fromHandle(obj),
            (cast(string) name).toStringz));
    }

    void setProperty(JSHandle obj, const(char)[] name, JSHandle val)
    {
        import std.string : toStringz;
        JS_SetPropertyStr(ctx, fromHandle(obj),
            (cast(string) name).toStringz, fromHandle(val));
    }

    JSHandle getGlobal()
    {
        return toHandle(JS_GetGlobalObject(ctx));
    }

    JSHandle dupValue(JSHandle val)
    {
        return toHandle(JS_DupValue(ctx, fromHandle(val)));
    }

    void freeValue(JSHandle val)
    {
        JS_FreeValue(ctx, fromHandle(val));
    }

    bool isException(JSHandle val) { return JS_IsException(fromHandle(val)) != 0; }
    bool isUndefined(JSHandle val) { return JS_IsUndefined(fromHandle(val)) != 0; }
    bool isNull(JSHandle val) { return JS_IsNull(fromHandle(val)) != 0; }
    bool isString(JSHandle val) { return JS_IsString(fromHandle(val)) != 0; }
    bool isObject(JSHandle val) { return JS_IsObject(fromHandle(val)) != 0; }
    bool isFunction(JSHandle val) { return JS_IsFunction(ctx, fromHandle(val)) != 0; }
    bool isBool(JSHandle val) { return JS_IsBool(fromHandle(val)) != 0; }
    bool isNumber(JSHandle val) { return JS_IsNumber(fromHandle(val)) != 0; }

    string getException()
    {
        import dun.engine.quickjs.exceptions : extractException;
        return extractException(ctx);
    }

    JSHandle throwTypeError(const(char)[] msg)
    {
        import std.string : toStringz;
        return toHandle(JS_ThrowTypeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    JSHandle throwRangeError(const(char)[] msg)
    {
        import std.string : toStringz;
        return toHandle(JS_ThrowRangeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    bool hasPendingJobs()
    {
        return JS_IsJobPending(rt) != 0;
    }

    bool executePendingJob()
    {
        JSContext* pctx;
        return JS_ExecutePendingJob(rt, &pctx) > 0;
    }

    void drainJobs()
    {
        while (hasPendingJobs())
            executePendingJob();
    }

    void setContextOpaque(void* ptr)
    {
        JS_SetContextOpaque(ctx, ptr);
    }

    void* getContextOpaque()
    {
        return JS_GetContextOpaque(ctx);
    }

    void setModuleLoader(ModuleLoaderCallback loader)
    {
        // TODO: bridge ModuleLoaderCallback to JS_SetModuleLoaderFunc
    }

    void setMemoryLimit(size_t bytes)
    {
        if (bytes > 0)
            JS_SetMemoryLimit(rt, bytes);
    }

    void setMaxStackSize(size_t bytes)
    {
        if (bytes > 0)
            JS_SetMaxStackSize(rt, bytes);
    }

    void* rawRuntime() { return cast(void*) rt; }
    void* rawContext() { return cast(void*) ctx; }

    // --- QuickJS-specific helpers (not in IJSEngine) ---

    void registerCFunction(string name, JSCFunction func, int argc) @trusted
    {
        import std.string : toStringz;
        auto global = JS_GetGlobalObject(ctx);
        auto fnVal = JS_NewCFunction(ctx, func, name.toStringz, argc);
        JS_SetPropertyStr(ctx, global, name.toStringz, fnVal);
        JS_FreeValue(ctx, global);
    }

    static JSHandle toHandle(JSValue v) pure nothrow @nogc @trusted
    {
        JSHandle h;
        *cast(JSValue*)&h = v;
        return h;
    }

    static JSValue fromHandle(JSHandle h) pure nothrow @nogc @trusted
    {
        return *cast(JSValue*)&h;
    }
}
