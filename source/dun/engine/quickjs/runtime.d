/// RAII wrapper for JSRuntime.
module dun.engine.quickjs.runtime;


/++
 + `@trusted policy`: RAII wrapper for JSRuntime*. Constructor calls
 + `JS_NewRuntime2`; destructor calls `JS_FreeRuntime`. `@trusted` is
 + the engine FFI escape — same surface as `engine/quickjs/backend.d`.
 +/
import dun.engine.quickjs.bindings;

/// RAII wrapper for JSRuntime*. Non-copyable.
struct Runtime
{
    private JSRuntime* rt;

    @disable this(this);

    /// Create a new QuickJS runtime with default allocator.
    static Runtime create() @trusted
    {
        auto rt = JS_NewRuntime();
        assert(rt !is null, "Failed to create JSRuntime");
        return Runtime(rt);
    }

    /// Create a new QuickJS runtime with custom malloc functions.
    static Runtime create(const(JSMallocFunctions)* mf) @trusted
    {
        auto rt = JS_NewRuntime2(mf, null);
        assert(rt !is null, "Failed to create JSRuntime with custom allocator");
        return Runtime(rt);
    }

    ~this() @trusted
    {
        if (rt !is null)
            JS_FreeRuntime(rt);
    }

    /// Set the maximum JS heap memory in bytes.
    void setMemoryLimit(size_t limit) @trusted
    {
        if (limit > 0)
            JS_SetMemoryLimit(rt, limit);
    }

    /// Set the maximum C stack size in bytes.
    void setMaxStackSize(size_t stackSize) @trusted
    {
        if (stackSize > 0)
            JS_SetMaxStackSize(rt, stackSize);
    }

    /// Set an interrupt handler for execution timeout.
    void setInterruptHandler(JSInterruptHandler cb, void* opaque = null) @trusted
    {
        JS_SetInterruptHandler(rt, cb, opaque);
    }

    /// Check if there are pending Promise jobs.
    bool hasPendingJob() @trusted
    {
        return JS_IsJobPending(rt);
    }

    /// Execute one pending job. Returns true if a job ran.
    bool executePendingJob() @trusted
    {
        JSContext* pctx;
        int ret = JS_ExecutePendingJob(rt, &pctx);
        return ret > 0;
    }

    /// Drain all pending jobs (microtask queue).
    void drainJobs() @trusted
    {
        while (hasPendingJob())
        {
            executePendingJob();
        }
    }

    /// Store opaque data on the runtime.
    void setOpaque(void* opaque) @trusted
    {
        JS_SetRuntimeOpaque(rt, opaque);
    }

    /// Retrieve opaque data from the runtime.
    void* getOpaque() @trusted
    {
        return JS_GetRuntimeOpaque(rt);
    }

    /// Access the raw JSRuntime pointer (for C API calls).
    JSRuntime* handle() @trusted
    {
        return rt;
    }
}
