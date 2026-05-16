module dun.builtins.worker_threads;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;

void registerWorkerThreadsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerWorkerThreadsModule");

    auto obj = engine.newObject();

    engine.setProperty(obj, "isMainThread", engine.newBool(true));
    engine.setProperty(obj, "threadId", engine.newInt(0));
    engine.setProperty(obj, "parentPort", engine.newNull());

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_worker_threads__", obj);

    // Worker must be `new`-able. JS_NewCFunction makes a regular
    // callable, not a constructor, so wrap in a JS class that
    // delegates to the global `Worker(path)` factory installed by
    // worker_api.d. Both `new Worker(p)` and `Worker(p)` then work.
    auto wrapRes = engine.eval(
        `globalThis.__dun_cjs_worker_threads__.Worker = `
        ~ `class Worker { `
        ~ `  constructor(p, opts) { return new globalThis.Worker(p, opts); } `
        ~ `};`,
        "<worker-threads-init>");
    if (!wrapRes.isError) engine.freeValue(wrapRes.value);

    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null ctx in worker_threads registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:worker_threads", &workerThreadsModuleInit);
        if (m is null) return;
        foreach (name; ["isMainThread", "threadId", "Worker", "parentPort"])
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int workerThreadsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in workerThreadsModuleInit");
        assert(m !is null, "Null JSModuleDef in workerThreadsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_worker_threads__");
        foreach (name; ["isMainThread", "threadId", "Worker", "parentPort"])
        {
            auto val = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, val);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

JSHandle jsWorkerThreadsWorker(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in worker_threads.Worker");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    auto global = engine.getGlobal();
    auto workerCtor = engine.getProperty(global, "__workerCreate");
    engine.freeValue(global);

    if (engine.isUndefined(workerCtor) || !engine.isFunction(workerCtor))
        return engine.throwTypeError("Worker API not available");

    return engine.callFunction(workerCtor, engine.newUndefined(), args);
}
