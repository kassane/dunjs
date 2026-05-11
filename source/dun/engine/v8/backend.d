module dun.engine.v8.backend;

import dun.engine.iface;
import dun.engine.v8.bindings;
import dun.engine.v8.cppbindings : V8TypeTag, V8TypeChecks;

static assert(JSHandle.sizeof >= (void*).sizeof, "JSHandle too small for V8 pointer");

class V8Engine : IJSEngine
{
    private DunV8Isolate* isolate;
    private DunV8Context* ctx;

    void initialize(EngineConfig config) @trusted
    {
        assert(isolate is null && ctx is null, "Double initialization of V8Engine");
        isolate = dun_v8_isolate_new();
        assert(isolate !is null, "Failed to create V8 Isolate");
        ctx = dun_v8_context_new(isolate);
        assert(ctx !is null, "Failed to create V8 Context");

        if (config.memoryLimit > 0)
            dun_v8_set_memory_limit(isolate, config.memoryLimit);
        if (config.maxStackSize > 0)
            dun_v8_set_stack_limit(isolate, config.maxStackSize);
    }

    void shutdown() @trusted
    {
        if (ctx !is null)
        {
            dun_v8_context_free(ctx);
            ctx = null;
        }
        if (isolate !is null)
        {
            dun_v8_isolate_dispose(isolate);
            isolate = null;
        }
    }

    JSResult eval(const(char)[] source, string filename) @trusted
    {
        import std.string : toStringz;

        assert(ctx !is null, "V8 context not initialized");
        int isError;
        auto val = dun_v8_eval(ctx, source.ptr, source.length,
            filename.toStringz, &isError);

        JSResult result;
        result.value = toHandle(val);
        result.isError = isError != 0;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    JSHandle newUndefined() @trusted
    {
        return toHandle(dun_v8_new_undefined(ctx));
    }

    JSHandle newNull() @trusted
    {
        return toHandle(dun_v8_new_null(ctx));
    }

    JSHandle newString(const(char)[] s) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_string(ctx, s.ptr, s.length));
    }

    JSHandle newInt(int v) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_int(ctx, v));
    }

    JSHandle newFloat(double v) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_number(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_bool(ctx, v ? 1 : 0));
    }

    JSHandle newObject() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_object(ctx));
    }

    JSHandle newArray() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_array(ctx, 0));
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        import std.string : toStringz;
        import dun.engine.callbacks : register;
        assert(ctx !is null, "V8 context not initialized");
        assert(cb !is null, "Null callback in V8 newFunction");
        int slot = register(cb);
        auto fn = dun_v8_new_function(ctx, &v8NativeTrampoline,
            name.toStringz, cast(void*) cast(size_t) slot);
        return toHandle(fn);
    }

    string extractString(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        size_t len;
        auto cstr = dun_v8_value_to_string(ctx, fromHandle(val), &len);
        if (cstr is null)
            return "";
        auto result = cstr[0 .. len].idup;
        dun_v8_free_string(cstr);
        return result;
    }

    int extractInt(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return dun_v8_value_to_int(ctx, fromHandle(val));
    }

    double extractFloat(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return dun_v8_value_to_number(ctx, fromHandle(val));
    }

    bool extractBool(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return dun_v8_value_to_bool(ctx, fromHandle(val)) != 0;
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_get_property(ctx, fromHandle(obj),
            (cast(string) name).toStringz));
    }

    void setProperty(JSHandle obj, const(char)[] name, JSHandle val) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "V8 context not initialized");
        dun_v8_set_property(ctx, fromHandle(obj),
            (cast(string) name).toStringz, fromHandle(val));
    }

    JSHandle getGlobal() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_global(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto jsFunc = fromHandle(func);
        auto jsThis = fromHandle(thisVal);
        int isError;
        if (args.length == 0)
        {
            auto ret = dun_v8_call(ctx, jsFunc, jsThis, 0, null, &isError);
            return toHandle(ret);
        }
        auto argv = new DunV8Value*[args.length];
        foreach (i; 0 .. args.length)
            argv[i] = fromHandle(args[i]);
        auto ret = dun_v8_call(ctx, jsFunc, jsThis,
            cast(int) args.length, argv.ptr, &isError);
        return toHandle(ret);
    }

    JSHandle dupValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = fromHandle(val);
        if (v !is null)
            dun_v8_value_ref(v);
        return val;
    }

    void freeValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = fromHandle(val);
        if (v !is null)
            dun_v8_value_unref(v);
    }

    bool isException(JSHandle val) @trusted { return fromHandle(val) is null; }

    // Type checks via TMP dispatch table (mirrors C++ isV8Type<Tag>)
    private static __gshared V8TypeChecks _typeChecks;
    private static __gshared bool _typeChecksReady;

    private bool checkType(V8TypeTag tag, JSHandle val) @trusted
    {
        if (!_typeChecksReady)
        {
            _typeChecks = V8TypeChecks.init();
            _typeChecksReady = true;
        }
        return _typeChecks.check(tag, fromHandle(val));
    }

    bool isUndefined(JSHandle val) @trusted { return checkType(V8TypeTag.Undefined, val); }
    bool isNull(JSHandle val) @trusted { return checkType(V8TypeTag.Null, val); }
    bool isString(JSHandle val) @trusted { return checkType(V8TypeTag.String, val); }
    bool isObject(JSHandle val) @trusted { return checkType(V8TypeTag.Object, val); }
    bool isFunction(JSHandle val) @trusted { return checkType(V8TypeTag.Function, val); }
    bool isBool(JSHandle val) @trusted { return checkType(V8TypeTag.Bool, val); }
    bool isNumber(JSHandle val) @trusted { return checkType(V8TypeTag.Number, val); }

    string getException() @trusted
    {
        size_t len;
        auto cstr = dun_v8_get_exception(ctx, &len);
        if (cstr is null)
            return "";
        auto result = cstr[0 .. len].idup;
        dun_v8_free_string(cstr);
        return result;
    }

    JSHandle throwTypeError(const(char)[] msg) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_throw_type_error(ctx, (cast(string) msg).toStringz));
    }

    JSHandle throwRangeError(const(char)[] msg) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_throw_range_error(ctx, (cast(string) msg).toStringz));
    }

    PromiseHandles newPromise() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        PromiseHandles ph;
        DunV8Value* resolveOut, rejectOut;
        auto promise = dun_v8_new_promise(ctx, &resolveOut, &rejectOut);
        ph.promise = toHandle(promise);
        ph.resolve = toHandle(resolveOut);
        ph.reject = toHandle(rejectOut);
        return ph;
    }

    bool hasPendingJobs() @trusted
    {
        assert(isolate !is null, "V8 isolate not initialized");
        return dun_v8_has_pending_microtasks(isolate) != 0;
    }

    bool executePendingJob() @trusted
    {
        dun_v8_drain_microtasks(isolate);
        return false;
    }

    void drainJobs() @trusted
    {
        dun_v8_drain_microtasks(isolate);
    }

    void setContextOpaque(void* ptr) @trusted
    {
        dun_v8_set_context_data(ctx, ptr);
    }

    void* getContextOpaque() @trusted
    {
        return dun_v8_get_context_data(ctx);
    }

    void setModuleLoader(ModuleLoaderCallback loader) {}

    JSResult evalModule(const(char)[] source, string filename) @trusted
    {
        import dun.modules.esm_shim : transpileESM;
        try
        {
            auto transpiled = transpileESM(cast(string) source, filename);
            return eval(transpiled, filename);
        }
        catch (Exception e)
        {
            JSResult result;
            result.isError = true;
            result.errorMessage = "ESM transpile error: " ~ e.msg;
            result.value = toHandle(cast(DunV8Value*) null);
            return result;
        }
    }

    void registerNativeModule(string name, void* initFunc) @trusted {}

    void setMemoryLimit(size_t bytes) @trusted
    {
        if (bytes > 0)
            dun_v8_set_memory_limit(isolate, bytes);
    }

    void setMaxStackSize(size_t bytes) @trusted
    {
        if (bytes > 0)
            dun_v8_set_stack_limit(isolate, bytes);
    }

    void* rawRuntime() @trusted { return cast(void*) isolate; }
    void* rawContext() @trusted { return cast(void*) ctx; }

    // --- V8-specific helpers ---

    void registerV8Function(string name, DunV8NativeCallback cb, void* data = null) @trusted
    {
        import std.string : toStringz;
        auto fn = dun_v8_new_function(ctx, cb, name.toStringz, data);
        auto global = dun_v8_global(ctx);
        dun_v8_set_property(ctx, global, name.toStringz, fn);
    }

    static JSHandle toHandle(DunV8Value* ptr) pure nothrow @nogc @trusted
    {
        JSHandle h;
        h.opaque[0] = cast(void*) ptr;
        return h;
    }

    static DunV8Value* fromHandle(JSHandle h) pure nothrow @nogc @trusted
    {
        return cast(DunV8Value*) h.opaque[0];
    }
}

private extern (C) DunV8Value* v8NativeTrampoline(DunV8Context* ctx,
    DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow @trusted
{
    import dun.engine.callbacks : get;

    int slot = cast(int) cast(size_t) data;
    auto cb = get(slot);
    if (cb is null)
        return dun_v8_new_undefined(ctx);

    auto ctxOpaque = dun_v8_get_context_data(ctx);

    JSHandle thisH;
    thisH.opaque[0] = cast(void*) thisVal;
    JSHandle[] args;
    try
    {
        if (argc > 0)
        {
            args = new JSHandle[argc];
            foreach (i; 0 .. argc)
                args[i].opaque[0] = cast(void*) argv[i];
        }
    }
    catch (Exception)
    {
        return dun_v8_new_undefined(ctx);
    }
    try
    {
        auto result = cb(ctxOpaque, thisH, args);
        return cast(DunV8Value*) result.opaque[0];
    }
    catch (Exception)
    {
        return dun_v8_new_undefined(ctx);
    }
}
