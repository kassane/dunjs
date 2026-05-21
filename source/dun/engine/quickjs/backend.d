module dun.engine.quickjs.backend;

import dun.engine.iface;
import dun.engine.quickjs.bindings;
import std.string : toStringz;

class QuickJSEngine : IJSEngine

{
    private JSRuntime* rt;
    private JSContext* ctx;

    void initialize(EngineConfig config) @trusted
    {
        assert(rt is null, "Double initialization: runtime already exists");
        assert(ctx is null, "Double initialization: context already exists");
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

    JSResult eval(scope const(char)[] source, string filename) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        assert(source.ptr !is null, "Null source pointer");

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
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_UNDEFINED());
    }

    JSHandle newNull() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NULL());
    }

    JSHandle newString(scope const(char)[] s) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewStringLen(ctx, s.ptr, s.length));
    }

    JSHandle newInt(int v) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewInt32(ctx, v));
    }

    JSHandle newFloat(double v) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewFloat64(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewBool(ctx, v ? 1 : 0));
    }

    JSHandle newObject() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewObject(ctx));
    }

    JSHandle newArray() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_NewArray(ctx));
    }

    JSHandle newUint8Array(scope const(ubyte)[] data) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        auto ab = JS_NewArrayBufferCopy(ctx, data.ptr, data.length);
        if (JS_IsException(ab) != 0)
            return toHandle(ab);
        auto global = JS_GetGlobalObject(ctx);
        auto ctor = JS_GetPropertyStr(ctx, global, "Uint8Array");
        auto result = JS_CallConstructor(ctx, ctor, 1, &ab);
        JS_FreeValue(ctx, ctor);
        JS_FreeValue(ctx, global);
        JS_FreeValue(ctx, ab);
        return toHandle(result);
    }

    JSHandle newUint8ArrayZeroed(size_t length) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        auto global = JS_GetGlobalObject(ctx);
        auto ctor = JS_GetPropertyStr(ctx, global, "Uint8Array");
        auto lenArg = JS_NewInt32(ctx, cast(int) length);
        auto result = JS_CallConstructor(ctx, ctor, 1, &lenArg);
        JS_FreeValue(ctx, lenArg);
        JS_FreeValue(ctx, ctor);
        JS_FreeValue(ctx, global);
        return toHandle(result);
    }

    ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        auto v = fromHandle(val);
        size_t offset, byteLen, bpe;
        auto ab = JS_GetTypedArrayBuffer(ctx, v, &offset, &byteLen, &bpe);
        if (JS_IsException(ab) != 0) return null;
        scope(exit) JS_FreeValue(ctx, ab);
        size_t abSize;
        auto ptr = JS_GetArrayBuffer(ctx, &abSize, ab);
        if (ptr is null) return null;
        if (offset + byteLen > abSize) return null;
        return ptr[offset .. offset + byteLen];
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        import dun.engine.callbacks : register;
        int slot = register(cb);
        auto fn = JS_NewCFunction2(ctx,
            cast(JSCFunction) &qjsNativeTrampoline,
            name.toStringz, argc, JS_CFUNC_generic_magic, slot);
        return toHandle(fn);
    }

    string extractString(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
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
        assert(ctx !is null, "Engine not initialized");
        auto jsv = fromHandle(val);
        int result;
        JS_ToInt32(ctx, &result, jsv);
        return result;
    }

    double extractFloat(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        auto jsv = fromHandle(val);
        double result;
        JS_ToFloat64(ctx, &result, jsv);
        return result;
    }

    bool extractBool(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return JS_ToBool(ctx, fromHandle(val)) != 0;
    }

    JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        char[QJS_STACK_STRING_SIZE] buf = void;
        return toHandle(JS_GetPropertyStr(ctx, fromHandle(obj),
            stackTerminate(name, buf)));
    }

    void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        char[QJS_STACK_STRING_SIZE] buf = void;
        JS_SetPropertyStr(ctx, fromHandle(obj),
            stackTerminate(name, buf), fromHandle(val));
    }

    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted
    {
        // QuickJS JS_SetPropertyStr consumes the value, so we must dup `fn`
        // first; otherwise the cached function's refcount drops to zero and
        // the next call uses freed memory. The dup'd ref becomes the
        // property's owned reference; caller's `fn` handle is unchanged.
        assert(ctx !is null, "Engine not initialized");
        char[QJS_STACK_STRING_SIZE] buf = void;
        JS_SetPropertyStr(ctx, fromHandle(obj),
            stackTerminate(name, buf), JS_DupValue(ctx, fromHandle(fn)));
    }

    void setPrototype(JSHandle obj, JSHandle proto) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        JS_SetPrototype(ctx, fromHandle(obj), fromHandle(proto));
    }

    JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool zeroed) @trusted
    {
        // QuickJS already creates fresh zeroed ArrayBuffers — no benefit to
        // a fused primitive here. Defer to the existing two-step path.
        auto u8 = zeroed && data.length == 0
            ? newUint8ArrayZeroed(0)
            : (data.length > 0 ? newUint8Array(data) : newUint8ArrayZeroed(0));
        if (zeroed && data.length > 0)
            u8 = newUint8ArrayZeroed(data.length);
        setPrototype(u8, proto);
        return u8;
    }

    JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted
    {
        auto u8 = newUint8ArrayZeroed(size);
        setPrototype(u8, proto);
        return u8;
    }

    JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted
    {
        // No native one-shot — fall back to extract + alloc + setProto.
        auto s = extractString(jsStr);
        return newBufferWithProto(cast(const(ubyte)[]) s, proto, false);
    }

    JSHandle bufferConcatFused(JSHandle arrayHandle, int count,
        size_t totalLen, JSHandle proto) @trusted
    {
        // QuickJS doesn't have an FFI-overhead asymmetry the V8 fused
        // path is built to compensate for. Return empty so the caller
        // falls back to the generic engine-agnostic loop in buffer.d.
        return JSHandle.init;
    }

    void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        JS_SetPropertyUint32(ctx, fromHandle(obj), idx, fromHandle(val));
    }

    JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_GetPropertyUint32(ctx, fromHandle(obj), idx));
    }

    bool isArray(JSHandle val) @trusted
    {
        return JS_IsArray(fromHandle(val));
    }

    int getArrayLength(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        long len;
        JS_GetLength(ctx, fromHandle(val), &len);
        return cast(int) len;
    }

    JSHandle getGlobal() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_GetGlobalObject(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        JSValue[NATIVE_CALL_STACK_ARGS] argv = void;
        auto argc = cast(int) args.length;
        JSValue* argp = null;
        if (argc > 0)
        {
            if (argc <= NATIVE_CALL_STACK_ARGS)
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
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_DupValue(ctx, fromHandle(val)));
    }

    void freeValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
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

    JSHandle throwTypeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_ThrowTypeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    JSHandle throwRangeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_ThrowRangeError(ctx, "%s", (cast(string) msg).toStringz));
    }

    JSHandle throwValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return toHandle(JS_Throw(ctx, JS_DupValue(ctx, fromHandle(val))));
    }

    PromiseHandles newPromise() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        PromiseHandles ph;
        JSValue[2] resolvingFuncs = [JS_UNDEFINED(), JS_UNDEFINED()];
        auto promise = JS_NewPromiseCapability(ctx, resolvingFuncs.ptr);
        if (JS_IsException(promise) != 0)
        {
            ph.promise = toHandle(JS_UNDEFINED());
            ph.resolve = toHandle(JS_UNDEFINED());
            ph.reject = toHandle(JS_UNDEFINED());
            return ph;
        }
        ph.promise = toHandle(promise);
        ph.resolve = toHandle(resolvingFuncs[0]);
        ph.reject = toHandle(resolvingFuncs[1]);
        return ph;
    }

    bool hasPendingJobs() @trusted
    {
        assert(rt !is null, "Engine not initialized");
        return JS_IsJobPending(rt);
    }

    bool executePendingJob() @trusted
    {
        assert(rt !is null, "Engine not initialized");
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
        assert(ctx !is null, "Engine not initialized");
        JS_SetContextOpaque(ctx, ptr);
    }

    void* getContextOpaque() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        return JS_GetContextOpaque(ctx);
    }

    void setModuleLoader(ModuleLoaderCallback loader) {}

    JSResult evalModule(scope const(char)[] source, string filename) @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        assert(source.ptr !is null, "Null source pointer");
        auto compiled = JS_Eval(ctx, source.toStringz, source.length,
            filename.toStringz, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
        JSResult result;
        if (JS_IsException(compiled) != 0)
        {
            result.isError = true;
            result.errorMessage = getException();
            return result;
        }

        // Set import.meta properties on the entry point module
        try
        {
            import std.path : absolutePath, dirName;
            auto mod = cast(JSModuleDef*) compiled.ptr;
            auto meta = JS_GetImportMeta(ctx, mod);
            if (JS_IsException(meta) == 0)
            {
                auto absPath = absolutePath(filename);
                auto urlStr = "file://" ~ absPath;
                JS_SetPropertyStr(ctx, meta, "url",
                    JS_NewStringLen(ctx, urlStr.ptr, urlStr.length));
                JS_SetPropertyStr(ctx, meta, "filename",
                    JS_NewStringLen(ctx, absPath.ptr, absPath.length));
                auto dirStr = dirName(absPath);
                JS_SetPropertyStr(ctx, meta, "dirname",
                    JS_NewStringLen(ctx, dirStr.ptr, dirStr.length));
                JS_SetPropertyStr(ctx, meta, "main",
                    JS_NewBool(ctx, true));

                // `import.meta.resolve(spec)` — Node ESM spec.
                import std.string : replace;
                auto safeDir = dirStr.replace(`\`, `\\`).replace(`'`, `\'`);
                auto resolveSrc =
                    `(function(){var __d='` ~ safeDir ~ `';` ~
                    `return function resolve(spec){` ~
                    `if(typeof spec!=='string')throw new TypeError('import.meta.resolve: spec must be a string');` ~
                    `if(spec.indexOf('://')!==-1)return spec;` ~
                    `if(spec[0]==='/')return 'file://'+spec;` ~
                    `if(spec[0]==='.'){` ~
                    `var parts=(__d+'/'+spec).split('/'),out=[];` ~
                    `for(var i=0;i<parts.length;i++){if(parts[i]==='..')out.pop();` ~
                    `else if(parts[i]&&parts[i]!=='.')out.push(parts[i]);}` ~
                    `return 'file:///'+out.join('/');}` ~
                    `try{if(typeof require!=='undefined'&&require.resolve)` ~
                    `return 'file://'+require.resolve(spec);}catch(e){}` ~
                    `return spec;};})()` ~ '\0';
                auto resolveFn = JS_Eval(ctx, resolveSrc.ptr, resolveSrc.length - 1,
                    "<import-meta-resolve>".ptr, JS_EVAL_TYPE_GLOBAL);
                if (JS_IsException(resolveFn) == 0)
                    JS_SetPropertyStr(ctx, meta, "resolve", resolveFn);
                else
                    JS_FreeValue(ctx, resolveFn);

                JS_FreeValue(ctx, meta);
            }
        }
        catch (Throwable) {}

        auto val = JS_EvalFunction(ctx, compiled);
        result.value = toHandle(val);
        result.isError = JS_IsException(val) != 0;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    void registerNativeModule(string name, void* initFunc) @trusted
    {
        assert(ctx !is null, "Engine not initialized in registerNativeModule");
        JS_NewCModule(ctx, name.toStringz,
            cast(JSModuleInitFunc) initFunc);
    }

    void setMemoryLimit(size_t bytes) @trusted
    {
        assert(rt !is null, "Engine not initialized");
        if (bytes > 0)
            JS_SetMemoryLimit(rt, bytes);
    }

    void setMaxStackSize(size_t bytes) @trusted
    {
        assert(rt !is null, "Engine not initialized");
        if (bytes > 0)
            JS_SetMaxStackSize(rt, bytes);
    }

    void collectGarbage() @trusted
    {
        assert(rt !is null, "Engine not initialized");
        JS_RunGC(rt);
    }

    void* rawRuntime() @trusted { return cast(void*) rt; }
    void* rawContext() @trusted { return cast(void*) ctx; }

    // --- QuickJS-specific helpers (not in IJSEngine) ---

    void registerCFunction(string name, JSCFunction func, int argc) @trusted
    {
        assert(func !is null, "Null function pointer");
        auto global = JS_GetGlobalObject(ctx);
        auto fnVal = JS_NewCFunction(ctx, func, name.toStringz, argc);
        JS_SetPropertyStr(ctx, global, name.toStringz, fnVal);
        JS_FreeValue(ctx, global);
    }

    private enum QJS_STACK_STRING_SIZE = 512;

    private static const(char)* stackTerminate(
        const(char)[] name, return ref char[QJS_STACK_STRING_SIZE] buf) @trusted
    {
        if (name.length < QJS_STACK_STRING_SIZE)
        {
            buf[0 .. name.length] = name[];
            buf[name.length] = '\0';
            return buf.ptr;
        }
        return (cast(string) name).toStringz;
    }

    static JSHandle toHandle(JSValue v) pure nothrow @nogc @trusted
    {
        static assert(JSHandle.sizeof >= JSValue.sizeof, "JSHandle too small to hold a JSValue");
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
    assert(ctx !is null, "Null JSContext in trampoline");
    import dun.engine.callbacks : get;
    auto cb = get(magic);
    if (cb is null)
        return JS_UNDEFINED();

    auto opaque = JS_GetContextOpaque(ctx);
    JSHandle thisH;
    *cast(JSValue*)&thisH = cast(JSValue) this_val;
    JSHandle[NATIVE_CALL_STACK_ARGS] stackArgs = void;
    JSHandle[] args;
    // catch Throwable, not Exception: `new JSHandle[argc]` can throw
    // OutOfMemoryError (a Throwable, not Exception). An OOM
    // propagating out of an extern(C) trampoline into C land is UB.
    try
    {
        if (argc > 0)
        {
            if (argc <= NATIVE_CALL_STACK_ARGS)
            {
                foreach (i; 0 .. argc)
                    *cast(JSValue*)&stackArgs[i] = cast(JSValue) argv[i];
                args = stackArgs[0 .. argc];
            }
            else
            {
                args = new JSHandle[argc];
                foreach (i; 0 .. argc)
                    *cast(JSValue*)&args[i] = cast(JSValue) argv[i];
            }
        }
    }
    catch (Throwable)
    {
        return JS_UNDEFINED();
    }
    try
    {
        auto result = cb(opaque, thisH, args);
        return *cast(JSValue*)&result;
    }
    catch (Throwable)
    {
        return JS_UNDEFINED();
    }
}
