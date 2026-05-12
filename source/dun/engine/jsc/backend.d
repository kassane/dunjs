module dun.engine.jsc.backend;

import dun.engine.iface;
import dun.engine.jsc.bindings;
import dun.engine.jsc.cppbindings : JSCTypeTag, JSCTypeChecks;

static assert(JSHandle.sizeof >= (void*).sizeof, "JSHandle too small for JSC pointer");

class JSCEngine : IJSEngine
{
    private JSGlobalContextRef ctx;
    private void* opaquePtr;

    void initialize(EngineConfig config) @trusted
    {
        assert(ctx is null, "Double initialization of JSCEngine");
        ctx = JSGlobalContextCreate(null);
        assert(ctx !is null, "Failed to create JSGlobalContext");
    }

    void shutdown() @trusted
    {
        if (ctx !is null)
        {
            JSGlobalContextRelease(ctx);
            ctx = null;
        }
    }

    JSResult eval(const(char)[] source, string filename) @trusted
    {
        import std.string : toStringz;

        assert(ctx !is null, "JSC context not initialized");
        auto jsSource = JSStringCreateWithUTF8CString(source.toStringz);
        scope (exit) JSStringRelease(jsSource);

        JSStringRef jsFilename = null;
        if (filename.length > 0)
        {
            jsFilename = JSStringCreateWithUTF8CString(filename.toStringz);
        }
        scope (exit) if (jsFilename !is null) JSStringRelease(jsFilename);

        JSValueRef exception = null;
        auto val = JSEvaluateScript(ctx, jsSource, null, jsFilename, 1, &exception);

        JSResult result;
        if (exception !is null)
        {
            result.isError = true;
            result.errorMessage = jscStringToD(exception);
            result.value = toHandle(cast(void*) JSValueMakeUndefined(ctx));
        }
        else
        {
            result.value = toHandle(cast(void*) val);
        }
        return result;
    }

    JSHandle newUndefined() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSValueMakeUndefined(ctx));
    }

    JSHandle newNull() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSValueMakeNull(ctx));
    }

    JSHandle newString(const(char)[] s) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "JSC context not initialized");
        auto jsStr = JSStringCreateWithUTF8CString(s.toStringz);
        assert(jsStr !is null, "JSStringCreateWithUTF8CString returned null");
        auto val = JSValueMakeString(ctx, jsStr);
        JSStringRelease(jsStr);
        return toHandle(cast(void*) val);
    }

    JSHandle newInt(int v) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSValueMakeNumber(ctx, cast(double) v));
    }

    JSHandle newFloat(double v) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSValueMakeNumber(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSValueMakeBoolean(ctx, v));
    }

    JSHandle newObject() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSObjectMake(ctx, null, null));
    }

    JSHandle newArray() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSObjectMakeArray(ctx, 0, null, null));
    }

    JSHandle newUint8Array(const(ubyte)[] data) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        import std.string : toStringz;
        try
        {
            auto buf = new char[](22 + data.length * 4);
            size_t pos = 0;
            void put(const(char)[] s)
            {
                buf[pos .. pos + s.length] = s[];
                pos += s.length;
            }
            put("new Uint8Array([");
            foreach (i, b; data)
            {
                if (i > 0) { buf[pos++] = ','; }
                if (b >= 100) { buf[pos++] = cast(char)('0' + b / 100); buf[pos++] = cast(char)('0' + (b / 10) % 10); buf[pos++] = cast(char)('0' + b % 10); }
                else if (b >= 10) { buf[pos++] = cast(char)('0' + b / 10); buf[pos++] = cast(char)('0' + b % 10); }
                else { buf[pos++] = cast(char)('0' + b); }
            }
            put("])");
            buf[pos] = '\0';
            auto jsStr = JSStringCreateWithUTF8CString(buf.ptr);
            scope (exit) JSStringRelease(jsStr);
            JSValueRef exc = null;
            auto val = JSEvaluateScript(ctx, jsStr, null, null, 1, &exc);
            if (exc !is null || val is null)
                return toHandle(cast(void*) JSValueMakeUndefined(ctx));
            return toHandle(cast(void*) val);
        }
        catch (Exception)
        {
            return toHandle(cast(void*) JSValueMakeUndefined(ctx));
        }
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        import std.string : toStringz;
        import dun.engine.callbacks : register;
        assert(ctx !is null, "JSC context not initialized");
        assert(cb !is null, "Null callback in newFunction");
        int slot = register(cb);
        auto jsName = JSStringCreateWithUTF8CString(name.toStringz);
        auto fn = JSObjectMakeFunctionWithCallback(ctx, jsName, &jscNativeTrampoline);
        JSStringRelease(jsName);
        auto slotName = JSStringCreateWithUTF8CString("__cbSlot__");
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, fn, slotName,
            JSValueMakeNumber(ctx, cast(double) slot),
            kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontEnum, &exc);
        JSStringRelease(slotName);
        return toHandle(cast(void*) fn);
    }

    string extractString(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return jscStringToD(cast(JSValueRef) fromHandle(val));
    }

    int extractInt(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        return cast(int) JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
    }

    double extractFloat(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        return JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
    }

    bool extractBool(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return JSValueToBoolean(ctx, cast(JSValueRef) fromHandle(val));
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "JSC context not initialized");
        auto jsName = JSStringCreateWithUTF8CString((cast(string) name).toStringz);
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        auto val = JSObjectGetProperty(ctx, cast(JSObjectRef) fromHandle(obj),
            jsName, &exc);
        return toHandle(cast(void*) val);
    }

    void setProperty(JSHandle obj, const(char)[] name, JSHandle val) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "JSC context not initialized");
        auto jsName = JSStringCreateWithUTF8CString((cast(string) name).toStringz);
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, cast(JSObjectRef) fromHandle(obj),
            jsName, cast(JSValueRef) fromHandle(val),
            kJSPropertyAttributeNone, &exc);
    }

    void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        JSObjectSetPropertyAtIndex(ctx, cast(JSObjectRef) fromHandle(obj),
            idx, cast(JSValueRef) fromHandle(val), &exc);
    }

    JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        auto val = JSObjectGetPropertyAtIndex(ctx,
            cast(JSObjectRef) fromHandle(obj), idx, &exc);
        return toHandle(cast(void*) val);
    }

    bool isArray(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return JSValueIsArray(ctx, cast(JSValueRef) fromHandle(val));
    }

    int getArrayLength(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        import std.string : toStringz;
        auto jsName = JSStringCreateWithUTF8CString("length".toStringz);
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        auto lenVal = JSObjectGetProperty(ctx,
            cast(JSObjectRef) fromHandle(val), jsName, &exc);
        return cast(int) JSValueToNumber(ctx, lenVal, &exc);
    }

    JSHandle getGlobal() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSContextGetGlobalObject(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto jsFunc = cast(JSObjectRef) fromHandle(func);
        auto jsThis = cast(JSObjectRef) fromHandle(thisVal);
        JSValueRef exc = null;
        if (args.length == 0)
        {
            auto ret = JSObjectCallAsFunction(ctx, jsFunc, jsThis, 0, null, &exc);
            if (exc !is null) return toHandle(cast(void*) exc);
            return toHandle(cast(void*) ret);
        }
        auto argv = new JSValueRef[args.length];
        foreach (i; 0 .. args.length)
            argv[i] = cast(JSValueRef) fromHandle(args[i]);
        auto ret = JSObjectCallAsFunction(ctx, jsFunc, jsThis,
            argv.length, cast(const(JSValueRef)*) argv.ptr, &exc);
        if (exc !is null) return toHandle(cast(void*) exc);
        return toHandle(cast(void*) ret);
    }

    JSHandle dupValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto v = cast(JSValueRef) fromHandle(val);
        JSValueProtect(ctx, v);
        return val;
    }

    void freeValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueUnprotect(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isException(JSHandle val) @trusted { return fromHandle(val) is null; }

    // Type checks via TMP dispatch table (mirrors JSType enum from JSC C API)
    private static __gshared JSCTypeChecks _typeChecks;
    private static __gshared bool _typeChecksReady;

    private bool checkType(JSCTypeTag tag, JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        if (!_typeChecksReady)
        {
            _typeChecks = JSCTypeChecks.create();
            _typeChecksReady = true;
        }
        return _typeChecks.check(tag, ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isUndefined(JSHandle val) @trusted { return checkType(JSCTypeTag.Undefined, val); }
    bool isNull(JSHandle val) @trusted { return checkType(JSCTypeTag.Null, val); }
    bool isString(JSHandle val) @trusted { return checkType(JSCTypeTag.String, val); }
    bool isObject(JSHandle val) @trusted { return checkType(JSCTypeTag.Object, val); }
    bool isFunction(JSHandle val) @trusted { return checkType(JSCTypeTag.Function, val); }
    bool isBool(JSHandle val) @trusted { return checkType(JSCTypeTag.Boolean, val); }
    bool isNumber(JSHandle val) @trusted { return checkType(JSCTypeTag.Number, val); }

    string getException()
    {
        return "";
    }

    JSHandle throwTypeError(const(char)[] msg) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto jsMsg = newString(msg);
        auto args = cast(JSValueRef) fromHandle(jsMsg);
        JSValueRef exc = null;
        auto err = JSObjectMakeError(ctx, 1, &args, &exc);
        _jscPendingThrow = err;
        return toHandle(cast(void*) err);
    }

    JSHandle throwRangeError(const(char)[] msg)
    {
        return throwTypeError(msg);
    }

    PromiseHandles newPromise() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        PromiseHandles ph;
        JSObjectRef resolveFunc, rejectFunc;
        JSValueRef exc = null;
        auto promise = JSObjectMakeDeferredPromise(ctx, &resolveFunc, &rejectFunc, &exc);
        ph.promise = toHandle(cast(void*) promise);
        ph.resolve = toHandle(cast(void*) resolveFunc);
        ph.reject = toHandle(cast(void*) rejectFunc);
        return ph;
    }

    bool hasPendingJobs() { return false; }
    bool executePendingJob() { return false; }
    void drainJobs() {}

    void setContextOpaque(void* ptr) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        opaquePtr = ptr;
        jscSetContextOpaque(ctx, ptr);
    }

    void* getContextOpaque() @trusted
    {
        return opaquePtr;
    }

    void setModuleLoader(ModuleLoaderCallback loader) {}

    JSResult evalModule(const(char)[] source, string filename) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
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
            result.value = toHandle(cast(void*) null);
            return result;
        }
    }

    void registerNativeModule(string name, void* initFunc) @trusted {}

    void setMemoryLimit(size_t bytes) {}
    void setMaxStackSize(size_t bytes) {}

    void collectGarbage() @trusted
    {
        assert(ctx !is null, "Engine not initialized");
        JSGarbageCollect(ctx);
    }

    void* rawRuntime() { return null; }
    void* rawContext() @trusted { return cast(void*) ctx; }

    // --- JSC-specific helpers ---

    void registerJSCFunction(string name, JSObjectCallAsFunctionCallback cb) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "JSC context not initialized");
        auto jsName = JSStringCreateWithUTF8CString(name.toStringz);
        scope (exit) JSStringRelease(jsName);
        auto fn = JSObjectMakeFunctionWithCallback(ctx, jsName, cb);
        auto global = JSContextGetGlobalObject(ctx);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, global, jsName, cast(JSValueRef) fn,
            kJSPropertyAttributeNone, &exc);
    }

    private string jscStringToD(JSValueRef val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        auto jsStr = JSValueToStringCopy(ctx, val, &exc);
        if (jsStr is null)
            return "";
        scope (exit) JSStringRelease(jsStr);

        auto maxSize = JSStringGetMaximumUTF8CStringSize(jsStr);
        if (maxSize == 0)
            return "";
        auto buf = new char[maxSize];
        auto written = JSStringGetUTF8CString(jsStr, buf.ptr, maxSize);
        assert(written <= maxSize, "JSC UTF8 overrun");
        if (written <= 1)
            return "";
        return (cast(immutable(char)[]) buf[0 .. written - 1]).idup;
    }

    static JSHandle toHandle(void* ptr) pure nothrow @nogc @trusted
    {
        JSHandle h;
        h.opaque[0] = ptr;
        return h;
    }

    static void* fromHandle(JSHandle h) pure nothrow @nogc @trusted
    {
        return h.opaque[0];
    }
}

private extern (C) JSValueRef jscNativeTrampoline(JSContextRef ctx,
    JSObjectRef func, JSObjectRef thisObject,
    size_t argumentCount, const(JSValueRef)* arguments,
    JSValueRef* exception) nothrow @trusted
{
    import dun.engine.callbacks : get;
    import dun.engine.jsc.backend : JSCEngine;

    assert(ctx !is null, "Null JSContextRef in jscNativeTrampoline");
    auto slotName = JSStringCreateWithUTF8CString("__cbSlot__");
    JSValueRef exc = null;
    auto slotVal = JSObjectGetProperty(ctx, func, slotName, &exc);
    JSStringRelease(slotName);
    int slot = cast(int) JSValueToNumber(ctx, slotVal, &exc);

    auto cb = get(slot);
    if (cb is null)
        return JSValueMakeUndefined(ctx);

    void* ctxOpaque = jscGetContextOpaque(JSContextGetGlobalContext(ctx));

    JSHandle thisH;
    thisH.opaque[0] = cast(void*) thisObject;
    JSHandle[] args;
    try
    {
        if (argumentCount > 0)
        {
            args = new JSHandle[argumentCount];
            foreach (i; 0 .. argumentCount)
                args[i].opaque[0] = cast(void*) arguments[i];
        }
    }
    catch (Exception)
    {
        return JSValueMakeUndefined(ctx);
    }
    try
    {
        auto result = cb(ctxOpaque, thisH, args);
        if (_jscPendingThrow !is null)
        {
            *exception = _jscPendingThrow;
            _jscPendingThrow = null;
            return null;
        }
        return cast(JSValueRef) result.opaque[0];
    }
    catch (Exception)
    {
        return JSValueMakeUndefined(ctx);
    }
}

private extern (C) void jscTypedArrayDeallocator(void* bytes, void* deallocCtx) nothrow @nogc
{
    import core.stdc.stdlib : free;
    if (bytes !is null)
        free(bytes);
}

private JSValueRef _jscPendingThrow;

// JSC doesn't have a context opaque API, so we maintain our own map.
private __gshared void*[size_t] jscContextOpaqueMap;

package void jscSetContextOpaque(JSGlobalContextRef ctx, void* ptr) nothrow @trusted
{
    try { jscContextOpaqueMap[cast(size_t) cast(void*) ctx] = ptr; }
    catch (Exception) {}
}

package void* jscGetContextOpaque(JSGlobalContextRef ctx) nothrow @trusted
{
    if (auto p = cast(size_t) cast(void*) ctx in jscContextOpaqueMap)
        return *p;
    return null;
}
