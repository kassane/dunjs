module dun.builtins.worker_threads;


/// `@trusted policy`: Node-compatible `worker_threads` module —
/// thin shim over `dun.runtime.worker_api` (the Web Worker
/// implementation). Each callback `cast(DunState*) ctx` and
/// delegates to the underlying worker API.
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
    //
    // workerData / parentPort are populated by the worker bootstrap:
    //   - Main thread sees workerData === undefined.
    //   - Worker thread sees workerData = globalThis.__workerData__
    //     (set by the inline-source temp file when eval:true is used)
    //     and parentPort = a tiny EventEmitter wrapping postMessage.
    auto wrapRes = engine.eval(
        `globalThis.__dun_cjs_worker_threads__.Worker = `
        ~ `class Worker { `
        ~ `  constructor(p, opts) { return new globalThis.Worker(p, opts); } `
        ~ `};`
        ~ `Object.defineProperty(globalThis.__dun_cjs_worker_threads__, 'workerData', {`
        ~ `  get: function() { return globalThis.__workerData__; }, configurable: true });`,
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
