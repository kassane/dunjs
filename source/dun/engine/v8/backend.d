module dun.engine.v8.backend;

import dun.engine.iface;
import dun.engine.v8.bindings;

class V8Engine : IJSEngine
{
    private DunV8Isolate* isolate;
    private DunV8Context* ctx;

    void initialize(EngineConfig config) @trusted
    {
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

    JSHandle newString(const(char)[] s) @trusted
    {
        return toHandle(dun_v8_new_string(ctx, s.ptr, s.length));
    }

    JSHandle newInt(int v) @trusted
    {
        return toHandle(dun_v8_new_int(ctx, v));
    }

    JSHandle newFloat(double v) @trusted
    {
        return toHandle(dun_v8_new_number(ctx, v));
    }

    JSHandle newBool(bool v) @trusted
    {
        return toHandle(dun_v8_new_bool(ctx, v ? 1 : 0));
    }

    JSHandle newObject() @trusted
    {
        return toHandle(dun_v8_new_object(ctx));
    }

    JSHandle newArray() @trusted
    {
        return toHandle(dun_v8_new_array(ctx, 0));
    }

    JSHandle newFunction(NativeCallback cb, string name, int argc)
    {
        assert(false, "Use registerV8Function for V8 backend");
    }

    string extractString(JSHandle val) @trusted
    {
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
        return dun_v8_value_to_int(ctx, fromHandle(val));
    }

    double extractFloat(JSHandle val) @trusted
    {
        return dun_v8_value_to_number(ctx, fromHandle(val));
    }

    bool extractBool(JSHandle val) @trusted
    {
        return dun_v8_value_to_bool(ctx, fromHandle(val)) != 0;
    }

    JSHandle getProperty(JSHandle obj, const(char)[] name) @trusted
    {
        return toHandle(dun_v8_get_property(ctx, fromHandle(obj), name.ptr));
    }

    void setProperty(JSHandle obj, const(char)[] name, JSHandle val) @trusted
    {
        dun_v8_set_property(ctx, fromHandle(obj), name.ptr, fromHandle(val));
    }

    JSHandle getGlobal() @trusted
    {
        return toHandle(dun_v8_global(ctx));
    }

    JSHandle dupValue(JSHandle val) @trusted
    {
        auto v = fromHandle(val);
        if (v !is null)
            dun_v8_value_ref(v);
        return val;
    }

    void freeValue(JSHandle val) @trusted
    {
        auto v = fromHandle(val);
        if (v !is null)
            dun_v8_value_unref(v);
    }

    bool isException(JSHandle val) @trusted { return fromHandle(val) is null; }
    bool isUndefined(JSHandle val) @trusted { return dun_v8_value_is_undefined(fromHandle(val)) != 0; }
    bool isNull(JSHandle val) @trusted { return dun_v8_value_is_null(fromHandle(val)) != 0; }
    bool isString(JSHandle val) @trusted { return dun_v8_value_is_string(fromHandle(val)) != 0; }
    bool isObject(JSHandle val) @trusted { return dun_v8_value_is_object(fromHandle(val)) != 0; }
    bool isFunction(JSHandle val) @trusted { return dun_v8_value_is_function(fromHandle(val)) != 0; }
    bool isBool(JSHandle val) @trusted { return dun_v8_value_is_bool(fromHandle(val)) != 0; }
    bool isNumber(JSHandle val) @trusted { return dun_v8_value_is_number(fromHandle(val)) != 0; }

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
        return toHandle(dun_v8_throw_type_error(ctx, msg.ptr));
    }

    JSHandle throwRangeError(const(char)[] msg) @trusted
    {
        return toHandle(dun_v8_throw_range_error(ctx, msg.ptr));
    }

    bool hasPendingJobs() @trusted
    {
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
