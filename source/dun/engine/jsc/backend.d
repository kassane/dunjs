module dun.engine.jsc.backend;

import dun.engine.iface;
import dun.engine.jsc.bindings;

class JSCEngine : IJSEngine
{
    private JSGlobalContextRef ctx;
    private void* opaquePtr;

    void initialize(EngineConfig config) @trusted
    {
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

    JSHandle newString(const(char)[] s) @trusted
    {
        import std.string : toStringz;
        auto jsStr = JSStringCreateWithUTF8CString(s.toStringz);
        auto val = JSValueMakeString(ctx, jsStr);
        JSStringRelease(jsStr);
        return toHandle(cast(void*) val);
    }

    JSHandle newInt(int v) @trusted
    {
        return toHandle(cast(void*) JSValueMakeNumber(ctx, cast(double) v));
    }

    JSHandle newFloat(double v) @trusted
    {
        return toHandle(cast(void*) JSValueMakeNumber(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        return toHandle(cast(void*) JSValueMakeBoolean(ctx, v));
    }

    JSHandle newObject() @trusted
    {
        return toHandle(cast(void*) JSObjectMake(ctx, null, null));
    }

    JSHandle newArray() @trusted
    {
        return toHandle(cast(void*) JSObjectMakeArray(ctx, 0, null, null));
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc)
    {
        assert(false, "Use registerJSCFunction for JSC backend");
    }

    string extractString(JSHandle val) @trusted
    {
        return jscStringToD(cast(JSValueRef) fromHandle(val));
    }

    int extractInt(JSHandle val) @trusted
    {
        JSValueRef exc = null;
        return cast(int) JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
    }

    double extractFloat(JSHandle val) @trusted
    {
        JSValueRef exc = null;
        return JSValueToNumber(ctx, cast(JSValueRef) fromHandle(val), &exc);
    }

    bool extractBool(JSHandle val) @trusted
    {
        return JSValueToBoolean(ctx, cast(JSValueRef) fromHandle(val));
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name) @trusted
    {
        import std.string : toStringz;
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
        auto jsName = JSStringCreateWithUTF8CString((cast(string) name).toStringz);
        scope (exit) JSStringRelease(jsName);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, cast(JSObjectRef) fromHandle(obj),
            jsName, cast(JSValueRef) fromHandle(val),
            kJSPropertyAttributeNone, &exc);
    }

    JSHandle getGlobal() @trusted
    {
        return toHandle(cast(void*) JSContextGetGlobalObject(ctx));
    }

    JSHandle dupValue(JSHandle val) @trusted
    {
        auto v = cast(JSValueRef) fromHandle(val);
        JSValueProtect(ctx, v);
        return val;
    }

    void freeValue(JSHandle val) @trusted
    {
        JSValueUnprotect(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isException(JSHandle val) @trusted { return fromHandle(val) is null; }

    bool isUndefined(JSHandle val) @trusted
    {
        return JSValueIsUndefined(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isNull(JSHandle val) @trusted
    {
        return JSValueIsNull(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isString(JSHandle val) @trusted
    {
        return JSValueIsString(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isObject(JSHandle val) @trusted
    {
        return JSValueIsObject(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isFunction(JSHandle val) @trusted
    {
        auto v = cast(JSValueRef) fromHandle(val);
        if (!JSValueIsObject(ctx, v))
            return false;
        JSValueRef exc = null;
        auto obj = JSValueToObject(ctx, v, &exc);
        if (obj is null) return false;
        return JSObjectIsFunction(ctx, obj);
    }

    bool isBool(JSHandle val) @trusted
    {
        return JSValueIsBoolean(ctx, cast(JSValueRef) fromHandle(val));
    }

    bool isNumber(JSHandle val) @trusted
    {
        return JSValueIsNumber(ctx, cast(JSValueRef) fromHandle(val));
    }

    string getException()
    {
        return "";
    }

    JSHandle throwTypeError(const(char)[] msg) @trusted
    {
        auto jsMsg = newString(msg);
        auto args = cast(JSValueRef) fromHandle(jsMsg);
        auto err = JSObjectMakeError(ctx, 1, &args, null);
        return toHandle(cast(void*) err);
    }

    JSHandle throwRangeError(const(char)[] msg)
    {
        return throwTypeError(msg);
    }

    bool hasPendingJobs() { return false; }
    bool executePendingJob() { return false; }
    void drainJobs() {}

    void setContextOpaque(void* ptr) { opaquePtr = ptr; }
    void* getContextOpaque() { return opaquePtr; }

    void setModuleLoader(ModuleLoaderCallback loader) {}
    void setMemoryLimit(size_t bytes) {}
    void setMaxStackSize(size_t bytes) {}

    void* rawRuntime() { return null; }
    void* rawContext() @trusted { return cast(void*) ctx; }

    // --- JSC-specific helpers ---

    void registerJSCFunction(string name, JSObjectCallAsFunctionCallback cb) @trusted
    {
        import std.string : toStringz;
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
