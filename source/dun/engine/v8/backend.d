module dun.engine.v8.backend;

/// `@trusted policy`: this file is the V8 binding layer. Every method
/// wraps an `extern(C)` call into the V8 C shim (`vendor/v8shim/`)
/// declared in `dun.engine.v8.bindings`; the `@trusted` is the FFI
/// escape required to call them from D's `@safe` boundary.
///
/// The shim translates the D-side `DunV8*` opaque handles into V8's
/// `Isolate / HandleScope / Context::Scope` setup (see
/// `vendor/v8shim/v8shim_tmpl.hpp::withContext`). The invariants the
/// wrappers rely on:
///
///   - `isolate` is non-null after `initialize()` and stays valid
///     until `shutdown()`;
///   - `DunV8Value*` handles are ref-counted via
///     `dun_v8_value_ref` / `dun_v8_value_unref`; `dupValue` =
///     `dun_v8_value_ref`, `freeValue` = `dun_v8_value_unref`;
///   - the shim asserts the `withContext` invariants on the C++
///     side, so handle-table corruption surfaces as a CHECK abort
///     rather than UB.

import dun.engine.iface;
import dun.engine.v8.bindings;
import dun.engine.v8.cppbindings : V8TypeTag, V8TypeChecks;
import std.string : toStringz;

static assert(JSHandle.sizeof >= (void*).sizeof, "JSHandle too small for V8 pointer");

class V8Engine : IJSEngine
{
    private DunV8Isolate* isolate;
    private DunV8Context* ctx;
    private bool lastCallWasException;

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

        // Eagerly populate the type-check dispatch table so every
        // hot-path isXxx() call skips the lazy-init branch.
        if (!_typeChecksReady)
        {
            _typeChecks = V8TypeChecks.init();
            _typeChecksReady = true;
        }
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

    JSResult eval(scope const(char)[] source, string filename) @trusted
    {

        assert(ctx !is null, "V8 context not initialized");
        int isError;
        auto val = dun_v8_eval(ctx, source.ptr, source.length,
            filename.toStringz, &isError);

        JSResult result;
        result.value = toHandle(val);
        result.isError = isError != 0;
        lastCallWasException = result.isError;
        if (result.isError)
            result.errorMessage = getException();
        return result;
    }

    JSHandle newUndefined() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_undefined(ctx));
    }

    JSHandle newNull() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_null(ctx));
    }

    JSHandle newString(scope const(char)[] s) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        if (s.length == 0)
            return toHandle(dun_v8_new_string(ctx, "".ptr, 0));
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

    JSHandle newUint8Array(scope const(ubyte)[] data) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_uint8array(ctx, data.ptr, data.length));
    }

    JSHandle newUint8ArrayZeroed(size_t length) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_new_uint8array(ctx, null, length));
    }

    ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = fromHandle(val);
        if (v is null) return null;
        size_t len;
        auto ptr = dun_v8_typed_array_data(ctx, v, &len);
        if (ptr is null || len == 0) return null;
        return ptr[0 .. len];
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted
    {
        import dun.engine.callbacks : register;
        assert(ctx !is null, "V8 context not initialized");
        assert(cb !is null, "Null callback in V8 newFunction");
        int slot = register(cb);
        auto fn = dun_v8_new_function(ctx, &v8NativeTrampoline,
            name.toStringz, cast(void*) cast(size_t) slot);
        return toHandle(fn);
    }

    private enum V8_STACK_STRING_SIZE = 512;

    string extractString(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        size_t len;
        auto cstr = dun_v8_value_to_string(ctx, fromHandle(val), &len);
        if (cstr is null)
            return "";
        // Single copy: directly from C string to immutable D string
        // Stack buffer avoids GC allocation for short strings (~99% of cases)
        if (len <= V8_STACK_STRING_SIZE)
        {
            char[V8_STACK_STRING_SIZE] stackBuf = void;
            stackBuf[0 .. len] = cstr[0 .. len];
            dun_v8_free_string(cstr);
            return stackBuf[0 .. len].idup;
        }
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

    JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        char[V8_STACK_STRING_SIZE] buf = void;
        return toHandle(dun_v8_get_property(ctx, fromHandle(obj),
            stackTerminate(name, buf)));
    }

    void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        char[V8_STACK_STRING_SIZE] buf = void;
        dun_v8_set_property(ctx, fromHandle(obj),
            stackTerminate(name, buf), fromHandle(val));
    }

    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted
    {
        // V8 wraps every value in a ref-counted DunV8Value; setProperty
        // does not consume. Same shape as setProperty — caller's `fn`
        // handle is unchanged because dun_v8_set_property internally
        // creates its own v8::Local from the persistent handle.
        setProperty(obj, name, fn);
    }

    void setPrototype(JSHandle obj, JSHandle proto) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        dun_v8_set_prototype(ctx, fromHandle(obj), fromHandle(proto));
    }

    JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool zeroed) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = dun_v8_new_uint8array_with_proto(ctx,
            data.length ? data.ptr : null,
            data.length, fromHandle(proto), zeroed ? 1 : 0);
        return toHandle(v);
    }

    JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        // 1 FFI call: ArrayBuffer::New(size) + Uint8Array::New + SetPrototype
        // inside a single withContext entry. Eliminates the per-call
        // scope/handle-scope overhead of the previous 2-step pattern.
        auto v = dun_v8_new_uint8array_with_proto(ctx, null, size,
            fromHandle(proto), 1);
        return toHandle(v);
    }

    JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = dun_v8_buffer_from_utf8_string(ctx,
            fromHandle(jsStr), fromHandle(proto));
        return toHandle(v);
    }

    JSHandle bufferConcatFused(JSHandle arrayHandle, int count,
        size_t totalLen, JSHandle proto) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto v = dun_v8_buffer_concat(ctx, fromHandle(arrayHandle), count,
            totalLen, fromHandle(proto));
        return toHandle(v);
    }

    void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        dun_v8_set_property_index(ctx, fromHandle(obj), idx, fromHandle(val));
    }

    JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_get_property_index(ctx, fromHandle(obj), idx));
    }

    bool isArray(JSHandle val) @trusted
    {
        return dun_v8_value_is_array(fromHandle(val)) != 0;
    }

    int getArrayLength(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto lenVal = dun_v8_get_property(ctx, fromHandle(val), "length");
        if (lenVal is null) return 0;
        auto result = dun_v8_value_to_int(ctx, lenVal);
        dun_v8_value_unref(lenVal);
        return result;
    }

    JSHandle getGlobal() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return toHandle(dun_v8_global(ctx));
    }

    JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto jsFunc = fromHandle(func);
        auto jsThis = fromHandle(thisVal);
        int isError;
        if (args.length == 0)
        {
            auto ret = dun_v8_call(ctx, jsFunc, jsThis, 0, null, &isError);
            lastCallWasException = isError != 0;
            return toHandle(ret);
        }
        DunV8Value*[NATIVE_CALL_STACK_ARGS] stackArgv = void;
        auto argc = cast(int) args.length;
        DunV8Value** argp;
        if (argc <= NATIVE_CALL_STACK_ARGS)
        {
            foreach (i; 0 .. argc)
                stackArgv[i] = fromHandle(args[i]);
            argp = stackArgv.ptr;
        }
        else
        {
            auto buf = new DunV8Value*[argc];
            foreach (i; 0 .. argc)
                buf[i] = fromHandle(args[i]);
            argp = buf.ptr;
        }
        auto ret = dun_v8_call(ctx, jsFunc, jsThis, argc, argp, &isError);
        lastCallWasException = isError != 0;
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

    bool isException(JSHandle) @safe { return lastCallWasException; }

    // Type checks via TMP dispatch table (mirrors C++ isV8Type<Tag>)
    private static __gshared V8TypeChecks _typeChecks;
    private static __gshared bool _typeChecksReady;

    private bool checkType(V8TypeTag tag, JSHandle val) @trusted
    {
        // Table is eagerly populated in initialize() — see comment there.
        assert(_typeChecksReady, "V8 type checks not initialized (initialize() not called?)");
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

    /* Throw helpers: V8 14+ requires the throw path to be
       (1) `isolate->ThrowException(err)` then (2) the native
       function returns WITHOUT calling `info.GetReturnValue().Set`.
       The shim's throw helpers return nullptr + set
       `cw->has_thrown = true`; the trampoline checks the flag and
       skips Set. The D-side surfaces this by setting
       `lastCallWasException = true` so `engine.isException(h)`
       returns the expected `true` for callers that gate further
       work on it (e.g. `loadNativeAddon` failure → require.d). */

    JSHandle throwTypeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        char[V8_STACK_STRING_SIZE] buf = void;
        auto h = toHandle(dun_v8_throw_type_error(ctx, stackTerminate(msg, buf)));
        lastCallWasException = true;
        return h;
    }

    JSHandle throwRangeError(scope const(char)[] msg) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        char[V8_STACK_STRING_SIZE] buf = void;
        auto h = toHandle(dun_v8_throw_range_error(ctx, stackTerminate(msg, buf)));
        lastCallWasException = true;
        return h;
    }

    JSHandle throwValue(JSHandle val) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        auto h = toHandle(dun_v8_throw_value(ctx, fromHandle(val)));
        lastCallWasException = true;
        return h;
    }

    PromiseHandles newPromise() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        PromiseHandles ph;
        DunV8Value* resolveOut, rejectOut;
        auto promise = dun_v8_new_promise(ctx, &resolveOut, &rejectOut);
        if (promise is null)
        {
            lastCallWasException = true;
            auto undef = dun_v8_new_undefined(ctx);
            ph.promise = toHandle(undef);
            ph.resolve = toHandle(undef);
            ph.reject = toHandle(undef);
            return ph;
        }
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
        assert(isolate !is null, "V8 isolate not initialized");
        dun_v8_drain_microtasks(isolate);
        return false;
    }

    void drainJobs() @trusted
    {
        assert(isolate !is null, "V8 isolate not initialized");
        dun_v8_drain_microtasks(isolate);
    }

    void setContextOpaque(void* ptr) @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        dun_v8_set_context_data(ctx, ptr);
    }

    void* getContextOpaque() @trusted
    {
        assert(ctx !is null, "V8 context not initialized");
        return dun_v8_get_context_data(ctx);
    }

    void setModuleLoader(ModuleLoaderCallback loader) {}

    JSResult evalModule(scope const(char)[] source, string filename) @trusted
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
            lastCallWasException = true;
            result.errorMessage = "ESM transpile error: " ~ e.msg;
            result.value = toHandle(dun_v8_new_undefined(ctx));
            return result;
        }
    }

    void registerNativeModule(string name, void* initFunc) @trusted {}

    void setMemoryLimit(size_t bytes) @trusted
    {
        assert(isolate !is null, "V8 isolate not initialized");
        if (bytes > 0)
            dun_v8_set_memory_limit(isolate, bytes);
    }

    void setMaxStackSize(size_t bytes) @trusted
    {
        assert(isolate !is null, "V8 isolate not initialized");
        if (bytes > 0)
            dun_v8_set_stack_limit(isolate, bytes);
    }

    void collectGarbage() @trusted
    {
        assert(isolate !is null, "V8 isolate not initialized");
        dun_v8_collect_garbage(isolate);
    }

    void* rawRuntime() @trusted { return cast(void*) isolate; }
    void* rawContext() @trusted { return cast(void*) ctx; }

    // --- V8-specific helpers ---

    void registerV8Function(string name, DunV8NativeCallback cb, void* data = null) @trusted
    {
        assert(cb !is null, "Null callback in registerV8Function");
        auto fn = dun_v8_new_function(ctx, cb, name.toStringz, data);
        auto global = dun_v8_global(ctx);
        dun_v8_set_property(ctx, global, name.toStringz, fn);
        dun_v8_value_unref(global);
    }

    pragma(inline, true)
    private static const(char)* stackTerminate(
        const(char)[] name, return ref char[V8_STACK_STRING_SIZE] buf) @trusted
    {
        if (name.length < V8_STACK_STRING_SIZE)
        {
            buf[0 .. name.length] = name[];
            buf[name.length] = '\0';
            return buf.ptr;
        }
        return (cast(string) name).toStringz;
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

    assert(ctx !is null, "Null DunV8Context in v8NativeTrampoline");
    int slot = cast(int) cast(size_t) data;
    auto cb = get(slot);
    if (cb is null)
        return dun_v8_new_undefined(ctx);

    auto ctxOpaque = dun_v8_get_context_data(ctx);

    JSHandle thisH;
    thisH.opaque[0] = cast(void*) thisVal;
    JSHandle[NATIVE_CALL_STACK_ARGS] stackArgs = void;
    JSHandle[] args;
    // Throwable, not Exception: OOM on the heap-allocated args[]
    // path could otherwise escape into C land.
    try
    {
        if (argc > 0)
        {
            if (argc <= NATIVE_CALL_STACK_ARGS)
            {
                foreach (i; 0 .. argc)
                    stackArgs[i].opaque[0] = cast(void*) argv[i];
                args = stackArgs[0 .. argc];
            }
            else
            {
                args = new JSHandle[argc];
                foreach (i; 0 .. argc)
                    args[i].opaque[0] = cast(void*) argv[i];
            }
        }
    }
    catch (Throwable)
    {
        return dun_v8_new_undefined(ctx);
    }
    try
    {
        auto result = cb(ctxOpaque, thisH, args);
        return cast(DunV8Value*) result.opaque[0];
    }
    catch (Throwable)
    {
        return dun_v8_new_undefined(ctx);
    }
}
