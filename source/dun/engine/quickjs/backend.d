module dun.engine.quickjs.backend;

import dun.engine.iface;
import dun.engine.quickjs.bindings;

class QuickJSEngine : IJSEngine
{
    private JSRuntime* rt;
    private JSContext* ctx;

    void initialize(EngineConfig config) @trusted
    {
        rt = JS_NewRuntime();
        assert(rt !is null, "Failed to create JSRuntime");

        if (config.memoryLimit > 0)
            JS_SetMemoryLimit(rt, config.memoryLimit);
        if (config.maxStackSize > 0)
            JS_SetMaxStackSize(rt, config.maxStackSize);

        ctx = JS_NewContext(rt);
        assert(ctx !is null, "Failed to create JSContext");
    }

    void shutdown() @trusted
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

    JSResult eval(const(char)[] source, string filename) @trusted
    {
        import std.string : toStringz;

        auto srcz = source.toStringz;
        auto val = JS_Eval(ctx, srcz, source.length,
            filename.toStringz, JS_EVAL_TYPE_GLOBAL);
        JSResult result;
        result.value = toHandle(val);
        result.isError = JS_IsException(val) != 0;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    JSHandle newUndefined() @trusted
    {
        return toHandle(JS_UNDEFINED());
    }

    JSHandle newNull() @trusted
    {
        return toHandle(JS_NULL());
    }

    JSHandle newString(const(char)[] s) @trusted
    {
        return toHandle(JS_NewStringLen(ctx, s.ptr, s.length));
    }

    JSHandle newInt(int v) @trusted
    {
        return toHandle(JS_NewInt32(ctx, v));
    }

    JSHandle newFloat(double v) @trusted
    {
        return toHandle(JS_NewFloat64(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        return toHandle(JS_NewBool(ctx, v ? 1 : 0));
    }

    JSHandle newObject() @trusted
    {
        return toHandle(JS_NewObject(ctx));
    }

    JSHandle newArray() @trusted
    {
        return toHandle(JS_NewArray(ctx));
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        import std.string : toStringz;
        import dun.engine.callbacks : register;
        int slot = register(cb);
        auto fn = JS_NewCFunction2(ctx,
            cast(JSCFunction) &qjsNativeTrampoline,
            name.toStringz, argc, JS_CFUNC_generic_magic, slot);
        return toHandle(fn);
    }

    string extractString(JSHandle val) @trusted
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

    int extractInt(JSHandle val) @trusted
    {
        auto jsv = fromHandle(val);
        int result;
        JS_ToInt32(ctx, &result, jsv);
        return result;
    }

    double extractFloat(JSHandle val) @trusted
    {
        auto jsv = fromHandle(val);
        double result;
        JS_ToFloat64(ctx, &result, jsv);
        return result;
    }

    bool extractBool(JSHandle val) @trusted
    {
        return JS_ToBool(ctx, fromHandle(val)) != 0;
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name) @trusted
    {
        import std.string : toStringz;
        return toHandle(JS_GetPropertyStr(ctx, fromHandle(obj),
            (cast(string) name).toStringz));
    }

    void setProperty(JSHandle obj, const(char)[] name, JSHandle val) @trusted
    {
        import std.string : toStringz;
        JS_SetPropertyStr(ctx, fromHandle(obj),
            (cast(string) name).toStringz, fromHandle(val));
    }

    JSHandle getGlobal() @trusted
    {
        return toHandle(JS_GetGlobalObject(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args) @trusted
    {
        JSValue[16] argv = void;
        auto argc = cast(int) args.length;
        JSValue* argp = null;
        if (argc > 0)
        {
            if (argc <= 16)
            {
                foreach (i; 0 .. argc)
                    argv[i] = fromHandle(args[i]);
                argp = argv.ptr;
            }
            else
            {
                auto buf = new JSValue[argc];
                foreach (i; 0 .. argc)
                    buf[i] = fromHandle(args[i]);
                argp = buf.ptr;
            }
        }
        auto ret = JS_Call(ctx, fromHandle(func), fromHandle(thisVal), argc, argp);
        return toHandle(ret);
    }

    JSHandle dupValue(JSHandle val) @trusted
    {
        return toHandle(JS_DupValue(ctx, fromHandle(val)));
    }

    void freeValue(JSHandle val) @trusted
    {
        JS_FreeValue(ctx, fromHandle(val));
    }

    bool isException(JSHandle val) @trusted { return JS_IsException(fromHandle(val)) != 0; }
    bool isUndefined(JSHandle val) @trusted { return JS_IsUndefined(fromHandle(val)) != 0; }
    bool isNull(JSHandle val) @trusted { return JS_IsNull(fromHandle(val)) != 0; }
    bool isString(JSHandle val) @trusted { return JS_IsString(fromHandle(val)) != 0; }
    bool isObject(JSHandle val) @trusted { return JS_IsObject(fromHandle(val)) != 0; }
    bool isFunction(JSHandle val) @trusted { return JS_IsFunction(ctx, fromHandle(val)); }
    bool isBool(JSHandle val) @trusted { return JS_IsBool(fromHandle(val)) != 0; }
    bool isNumber(JSHandle val) @trusted { return JS_IsNumber(fromHandle(val)) != 0; }

    string getException() @trusted
    {
        import dun.engine.quickjs.exceptions : extractExceptionWithStack;
        return extractExceptionWithStack(ctx);
    }

    JSHandle throwTypeError(const(char)[] msg) @trusted
    {
        import std.string : toStringz;
        return toHandle(JS_ThrowTypeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    JSHandle throwRangeError(const(char)[] msg) @trusted
    {
        import std.string : toStringz;
        return toHandle(JS_ThrowRangeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    bool hasPendingJobs() @trusted
    {
        return JS_IsJobPending(rt);
    }

    bool executePendingJob() @trusted
    {
        JSContext* pctx;
        return JS_ExecutePendingJob(rt, &pctx) > 0;
    }

    void drainJobs()
    {
        while (hasPendingJobs())
            executePendingJob();
    }

    void setContextOpaque(void* ptr) @trusted
    {
        JS_SetContextOpaque(ctx, ptr);
    }

    void* getContextOpaque() @trusted
    {
        return JS_GetContextOpaque(ctx);
    }

    void setModuleLoader(ModuleLoaderCallback loader) {}

    JSResult evalModule(const(char)[] source, string filename) @trusted
    {
        import std.string : toStringz;
        auto compiled = JS_Eval(ctx, source.toStringz, source.length,
            filename.toStringz, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        JSResult result;
        if (JS_IsException(compiled) != 0)
        {
            result.isError = true;
            result.errorMessage = getException();
            return result;
        }
        auto val = JS_EvalFunction(ctx, compiled);
        result.value = toHandle(val);
        result.isError = JS_IsException(val) != 0;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    void registerNativeModule(string name, void* initFunc) @trusted
    {
        import std.string : toStringz;
        JS_NewCModule(ctx, name.toStringz,
            cast(JSModuleInitFunc) initFunc);
    }

    void setMemoryLimit(size_t bytes) @trusted
    {
        if (bytes > 0)
            JS_SetMemoryLimit(rt, bytes);
    }

    void setMaxStackSize(size_t bytes) @trusted
    {
        if (bytes > 0)
            JS_SetMaxStackSize(rt, bytes);
    }

    void* rawRuntime() @trusted { return cast(void*) rt; }
    void* rawContext() @trusted { return cast(void*) ctx; }

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

private extern (C) JSValue qjsNativeTrampoline(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv,
    int magic) nothrow @trusted
{
    import dun.engine.callbacks : get;
    auto cb = get(magic);
    if (cb is null)
        return JS_UNDEFINED();

    auto opaque = JS_GetContextOpaque(ctx);
    JSHandle thisH;
    *cast(JSValue*)&thisH = cast(JSValue) this_val;
    JSHandle[] args;
    try
    {
        if (argc > 0)
        {
            args = new JSHandle[argc];
            foreach (i; 0 .. argc)
                *cast(JSValue*)&args[i] = cast(JSValue) argv[i];
        }
    }
    catch (Exception)
    {
        return JS_UNDEFINED();
    }
    try
    {
        auto result = cb(opaque, thisH, args);
        return *cast(JSValue*)&result;
    }
    catch (Exception)
    {
        return JS_UNDEFINED();
    }
}
