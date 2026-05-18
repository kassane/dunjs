module dun.engine.jsc.backend;

import dun.engine.iface;
import dun.engine.jsc.bindings;
import dun.engine.jsc.cppbindings : JSCTypeTag, JSCTypeChecks;
import std.string : toStringz;

static assert(JSHandle.sizeof >= (void*).sizeof, "JSHandle too small for JSC pointer");

class JSCEngine : IJSEngine
{
    private JSGlobalContextRef ctx;
    private JSContextGroupRef group;
    private void* opaquePtr;
    private bool lastCallWasException;
    private JSObjectRef uint8ArrayCtor;

    void initialize(EngineConfig config) @trusted
    {
        assert(ctx is null, "Double initialization of JSCEngine");
        group = JSContextGroupCreate();
        assert(group !is null, "Failed to create JSContextGroup");
        ctx = JSGlobalContextCreateInGroup(group, null);
        assert(ctx !is null, "Failed to create JSGlobalContext");
    }

    void shutdown() @trusted
    {
        if (ctx !is null)
        {
            JSGarbageCollect(ctx);
            JSGlobalContextRelease(ctx);
            ctx = null;
        }
        if (group !is null)
        {
            JSContextGroupRelease(group);
            group = null;
        }
    }

    JSResult eval(scope const(char)[] source, string filename) @trusted
    {

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
            lastCallWasException = true;
            result.isError = true;
            result.errorMessage = jscStringToD(exception);
            result.value = toHandle(cast(void*) JSValueMakeUndefined(ctx));
        }
        else
        {
            lastCallWasException = false;
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

    private enum STACK_TERM_SIZE = 512;

    JSHandle newString(scope const(char)[] s) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        // Stack-terminate for short strings to avoid GC allocation from toStringz
        const(char)* cstr;
        char[STACK_TERM_SIZE] stackBuf = void;
        if (s.length < STACK_TERM_SIZE)
        {
            stackBuf[0 .. s.length] = s[];
            stackBuf[s.length] = '\0';
            cstr = stackBuf.ptr;
        }
        else
        {
            cstr = s.toStringz;
        }
        auto jsStr = JSStringCreateWithUTF8CString(cstr);
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

    JSHandle newUint8Array(scope const(ubyte)[] data) @trusted
    {
        import core.stdc.string : memcpy;

        assert(ctx !is null, "JSC context not initialized");
        ensureUint8ArrayCtor();
        JSValueRef exc = null;
        JSValueRef[1] ctorArgs = [JSValueMakeNumber(ctx, cast(double) data.length)];
        auto ta = JSObjectCallAsConstructor(ctx, uint8ArrayCtor, 1, ctorArgs.ptr, &exc);
        if (exc !is null || ta is null)
            return toHandle(cast(void*) JSValueMakeUndefined(ctx));
        if (data.length > 0)
        {
            auto ptr = cast(ubyte*) JSObjectGetTypedArrayBytesPtr(ctx, ta, &exc);
            if (ptr !is null)
                memcpy(ptr, data.ptr, data.length);
        }
        return toHandle(cast(void*) cast(JSValueRef) ta);
    }

    JSHandle newUint8ArrayZeroed(size_t length) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        ensureUint8ArrayCtor();
        JSValueRef exc = null;
        JSValueRef[1] ctorArgs = [JSValueMakeNumber(ctx, cast(double) length)];
        auto ta = JSObjectCallAsConstructor(ctx, uint8ArrayCtor, 1, ctorArgs.ptr, &exc);
        if (exc !is null || ta is null)
            return toHandle(cast(void*) JSValueMakeUndefined(ctx));
        return toHandle(cast(void*) cast(JSValueRef) ta);
    }

    private void ensureUint8ArrayCtor() @trusted
    {
        if (uint8ArrayCtor !is null) return;
        auto global = JSContextGetGlobalObject(ctx);
        auto name = JSStringCreateWithUTF8CString("Uint8Array");
        scope(exit) JSStringRelease(name);
        JSValueRef exc = null;
        auto ctorVal = JSObjectGetProperty(ctx, global, name, &exc);
        uint8ArrayCtor = cast(JSObjectRef) ctorVal;
        assert(uint8ArrayCtor !is null, "Uint8Array constructor not found");
        JSValueProtect(ctx, cast(JSValueRef) uint8ArrayCtor);
    }

    ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto obj = cast(JSObjectRef) fromHandle(val);
        if (obj is null) return null;
        JSValueRef exc = null;
        auto len = JSObjectGetTypedArrayByteLength(ctx, obj, &exc);
        if (exc !is null || len == 0) return null;
        auto ptr = cast(ubyte*) JSObjectGetTypedArrayBytesPtr(ctx, obj, &exc);
        if (exc !is null || ptr is null) return null;
        auto offset = JSObjectGetTypedArrayByteOffset(ctx, obj, &exc);
        if (exc !is null) return null;
        return (ptr + offset)[0 .. len];
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        import dun.engine.callbacks : register;
        assert(ctx !is null, "JSC context not initialized");
        assert(cb !is null, "Null callback in newFunction");
        int slot = register(cb);
        auto jsName = JSStringCreateWithUTF8CString(name.toStringz);
        auto fn = JSObjectMakeFunctionWithCallback(ctx, jsName, &jscNativeTrampoline);
        JSStringRelease(jsName);
        // Fast path: store slot ID in object's private data slot.
        // No JSValueToNumber on every call → avoids JSLock contention under
        // heavy iteration. Falls back to __cbSlot__ property if SetPrivate
        // is rejected by this build of JSC.
        bool storedAsPrivate = JSObjectSetPrivate(fn,
            cast(void*) cast(size_t)(slot + 1));  // +1 to distinguish from null
        if (!storedAsPrivate)
        {
            JSValueRef exc = null;
            JSObjectSetProperty(ctx, fn, getCbSlotStr(),
                JSValueMakeNumber(ctx, cast(double) slot),
                kJSPropertyAttributeReadOnly | kJSPropertyAttributeDontEnum, &exc);
        }
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
        auto result = cast(int) JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
        if (exc !is null) return 0;
        return result;
    }

    double extractFloat(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        auto result = JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
        if (exc !is null) return 0.0;
        return result;
    }

    bool extractBool(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return JSValueToBoolean(ctx, cast(JSValueRef) fromHandle(val));
    }

    pragma(inline, true)
    private static const(char)* stackTerminate(
        const(char)[] name, return ref char[STACK_TERM_SIZE] buf) nothrow @trusted
    {
        if (name.length < STACK_TERM_SIZE)
        {
            buf[0 .. name.length] = name[];
            buf[name.length] = '\0';
            return buf.ptr;
        }
        return (cast(string) name).toStringz;
    }

    JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        char[STACK_TERM_SIZE] termBuf = void;
        auto jsName = JSStringCreateWithUTF8CString(stackTerminate(name, termBuf));
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        auto val = JSObjectGetProperty(ctx, cast(JSObjectRef) fromHandle(obj),
            jsName, &exc);
        if (exc !is null) return toHandle(cast(void*) JSValueMakeUndefined(ctx));
        return toHandle(cast(void*) val);
    }

    void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        char[STACK_TERM_SIZE] termBuf = void;
        auto jsName = JSStringCreateWithUTF8CString(stackTerminate(name, termBuf));
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, cast(JSObjectRef) fromHandle(obj),
            jsName, cast(JSValueRef) fromHandle(val),
            kJSPropertyAttributeNone, &exc);
    }

    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted
    {
        // JSObjectSetProperty does not consume the value and JSC's GC roots
        // the function via the property table — no extra dupValue /
        // JSValueProtect needed. Critical for hot constructors (e.g.
        // crypto.createHash) that previously leaked one protect entry per
        // call via `setProperty(obj, k, dupValue(_cachedFn))`.
        setProperty(obj, name, fn);
    }

    void setPrototype(JSHandle obj, JSHandle proto) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSObjectSetPrototype(ctx, cast(JSObjectRef) fromHandle(obj),
            cast(JSValueRef) fromHandle(proto));
    }

    JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool zeroed) @trusted
    {
        // JSC's typed-array constructor is one JS-API call already; the
        // additional SetPrototype call is cheap by comparison. Use the
        // two-step path with a tweak: avoid the extra JS_DupValue/Protect
        // dance that `newUint8Array` would do.
        auto u8 = zeroed
            ? newUint8ArrayZeroed(data.length)
            : newUint8Array(data);
        setPrototype(u8, proto);
        return u8;
    }

    JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted
    {
        auto s = extractString(jsStr);
        return newBufferWithProto(cast(const(ubyte)[]) s, proto, false);
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

    private static __gshared JSStringRef _cachedLengthStr;

    private static JSStringRef getLengthStr() nothrow @trusted
    {
        if (_cachedLengthStr is null)
            _cachedLengthStr = JSStringCreateWithUTF8CString("length");
        return _cachedLengthStr;
    }

    int getArrayLength(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        JSValueRef exc = null;
        auto lenVal = JSObjectGetProperty(ctx,
            cast(JSObjectRef) fromHandle(val), getLengthStr(), &exc);
        if (exc !is null) return 0;
        exc = null;
        auto result = cast(int) JSValueToNumber(ctx, lenVal, &exc);
        if (exc !is null) return 0;
        return result;
    }

    JSHandle getGlobal() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        return toHandle(cast(void*) JSContextGetGlobalObject(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto jsFunc = cast(JSObjectRef) fromHandle(func);
        auto jsThis = cast(JSObjectRef) fromHandle(thisVal);
        JSValueRef exc = null;
        if (args.length == 0)
        {
            auto ret = JSObjectCallAsFunction(ctx, jsFunc, jsThis, 0, null, &exc);
            if (exc !is null)
            {
                lastCallWasException = true;
                JSValueProtect(ctx, exc);
                return toHandle(cast(void*) exc);
            }
            lastCallWasException = false;
            return toHandle(cast(void*) ret);
        }
        JSValueRef[NATIVE_CALL_STACK_ARGS] stackArgv = void;
        auto argc = args.length;
        const(JSValueRef)* argp;
        if (argc <= NATIVE_CALL_STACK_ARGS)
        {
            foreach (i; 0 .. argc)
                stackArgv[i] = cast(JSValueRef) fromHandle(args[i]);
            argp = cast(const(JSValueRef)*) stackArgv.ptr;
        }
        else
        {
            auto buf = new JSValueRef[argc];
            foreach (i; 0 .. argc)
                buf[i] = cast(JSValueRef) fromHandle(args[i]);
            argp = cast(const(JSValueRef)*) buf.ptr;
        }
        auto ret = JSObjectCallAsFunction(ctx, jsFunc, jsThis, argc, argp, &exc);
        if (exc !is null)
        {
            lastCallWasException = true;
            JSValueProtect(ctx, exc);
            return toHandle(cast(void*) exc);
        }
        lastCallWasException = false;
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

    bool isException(JSHandle) @safe { return lastCallWasException; }

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

    JSHandle throwTypeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto jsMsg = newString(msg);
        auto args = cast(JSValueRef) fromHandle(jsMsg);
        JSValueRef exc = null;
        auto err = JSObjectMakeError(ctx, 1, &args, &exc);
        _jscPendingThrow = err;
        return toHandle(cast(void*) err);
    }

    JSHandle throwRangeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        auto jsMsg = newString(msg);
        auto args = cast(JSValueRef) fromHandle(jsMsg);
        JSValueRef exc = null;
        auto err = JSObjectMakeError(ctx, 1, &args, &exc);
        // Set name to "RangeError" to distinguish from TypeError
        auto nameProp = JSStringCreateWithUTF8CString("name");
        auto rangeStr = JSStringCreateWithUTF8CString("RangeError");
        auto rangeVal = JSValueMakeString(ctx, rangeStr);
        JSObjectSetProperty(ctx, err, nameProp, rangeVal,
            kJSPropertyAttributeNone, &exc);
        JSStringRelease(nameProp);
        JSStringRelease(rangeStr);
        _jscPendingThrow = err;
        return toHandle(cast(void*) err);
    }

    JSHandle throwValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        _jscPendingThrow = cast(JSValueRef) fromHandle(val);
        return val;
    }

    PromiseHandles newPromise() @trusted
    {
        assert(ctx !is null, "JSC context not initialized");
        PromiseHandles ph;
        JSObjectRef resolveFunc, rejectFunc;
        JSValueRef exc = null;
        auto promise = JSObjectMakeDeferredPromise(ctx, &resolveFunc, &rejectFunc, &exc);
        if (exc !is null || promise is null)
        {
            lastCallWasException = true;
            auto undef = cast(void*) JSValueMakeUndefined(ctx);
            ph.promise = toHandle(undef);
            ph.resolve = toHandle(undef);
            ph.reject = toHandle(undef);
            return ph;
        }
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

    JSResult evalModule(scope const(char)[] source, string filename) @trusted
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
            lastCallWasException = true;
            result.errorMessage = "ESM transpile error: " ~ e.msg;
            result.value = toHandle(cast(void*) JSValueMakeUndefined(ctx));
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
        assert(ctx !is null, "JSC context not initialized");
        auto jsName = JSStringCreateWithUTF8CString(name.toStringz);
        scope (exit) JSStringRelease(jsName);
        auto fn = JSObjectMakeFunctionWithCallback(ctx, jsName, cb);
        auto global = JSContextGetGlobalObject(ctx);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, global, jsName, cast(JSValueRef) fn,
            kJSPropertyAttributeNone, &exc);
    }

    private enum JSC_STACK_STRING_SIZE = 512;

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

        // Stack buffer for short strings (covers ~99% of cases)
        if (maxSize <= JSC_STACK_STRING_SIZE)
        {
            char[JSC_STACK_STRING_SIZE] stackBuf = void;
            auto written = JSStringGetUTF8CString(jsStr, stackBuf.ptr, maxSize);
            assert(written <= maxSize, "JSC UTF8 overrun");
            if (written <= 1) return "";
            return stackBuf[0 .. written - 1].idup;
        }

        // Heap fallback for large strings
        auto buf = new char[maxSize];
        auto written = JSStringGetUTF8CString(jsStr, buf.ptr, maxSize);
        assert(written <= maxSize, "JSC UTF8 overrun");
        if (written <= 1)
            return "";
        return cast(string) buf[0 .. written - 1];
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

// Cached JSStringRef for __cbSlot__ — created once, reused on every native call
private __gshared JSStringRef _cachedCbSlotStr;

private JSStringRef getCbSlotStr() nothrow @trusted
{
    if (_cachedCbSlotStr is null)
        _cachedCbSlotStr = JSStringCreateWithUTF8CString("__cbSlot__");
    return _cachedCbSlotStr;
}

private extern (C) JSValueRef jscNativeTrampoline(JSContextRef ctx,
    JSObjectRef func, JSObjectRef thisObject,
    size_t argumentCount, const(JSValueRef)* arguments,
    JSValueRef* exception) nothrow @trusted
{
    import dun.engine.callbacks : get;
    import dun.engine.jsc.backend : JSCEngine;

    assert(ctx !is null, "Null JSContextRef in jscNativeTrampoline");
    // Fast slot lookup via private data (no JSValueToNumber → no JSLock churn).
    int slot;
    auto priv = JSObjectGetPrivate(func);
    if (priv !is null)
    {
        slot = cast(int)(cast(size_t) priv - 1);
    }
    else
    {
        JSValueRef exc = null;
        auto slotVal = JSObjectGetProperty(ctx, func, getCbSlotStr(), &exc);
        slot = cast(int) JSValueToNumber(ctx, slotVal, &exc);
    }

    auto cb = get(slot);
    if (cb is null)
        return JSValueMakeUndefined(ctx);

    void* ctxOpaque = jscGetContextOpaque(JSContextGetGlobalContext(ctx));

    JSHandle thisH;
    thisH.opaque[0] = cast(void*) thisObject;
    JSHandle[NATIVE_CALL_STACK_ARGS] stackArgs = void;
    JSHandle[] args;
    // Throwable, not Exception: OOM on the heap-allocated args[]
    // path could otherwise escape into C land.
    try
    {
        if (argumentCount > 0)
        {
            if (argumentCount <= NATIVE_CALL_STACK_ARGS)
            {
                foreach (i; 0 .. argumentCount)
                    stackArgs[i].opaque[0] = cast(void*) arguments[i];
                args = stackArgs[0 .. argumentCount];
            }
            else
            {
                args = new JSHandle[argumentCount];
                foreach (i; 0 .. argumentCount)
                    args[i].opaque[0] = cast(void*) arguments[i];
            }
        }
    }
    catch (Throwable)
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
    catch (Throwable)
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
// The map is `__gshared` (one per process) because callbacks from
// foreign threads need to find the opaque, but the (ctx, opaque)
// fast-path cache is `__thread` (thread-local) so worker threads
// don't tear each other's lookups: if thread A wrote (A_ctx, A_op)
// and thread B wrote (B_ctx, B_op), without TLS thread A's next
// `get(A_ctx)` could observe `_cachedCtx == A_ctx` but read
// `_cachedOpaque == B_op` for an unrelated context.
private __gshared void*[size_t] jscContextOpaqueMap;
private static JSGlobalContextRef _cachedCtx;     // TLS
private static void*              _cachedOpaque;  // TLS

package void jscSetContextOpaque(JSGlobalContextRef ctx, void* ptr) nothrow @trusted
{
    _cachedCtx = ctx;
    _cachedOpaque = ptr;
    try { jscContextOpaqueMap[cast(size_t) cast(void*) ctx] = ptr; }
    catch (Exception) {}
}

package void* jscGetContextOpaque(JSGlobalContextRef ctx) nothrow @trusted
{
    if (ctx is _cachedCtx) return _cachedOpaque;
    if (auto p = cast(size_t) cast(void*) ctx in jscContextOpaqueMap)
    {
        _cachedCtx = ctx;     // warm TLS cache for next call on this thread
        _cachedOpaque = *p;
        return *p;
    }
    return null;
}
