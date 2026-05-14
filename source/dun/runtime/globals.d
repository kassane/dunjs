module dun.runtime.globals;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.loop.eventloop : EventLoop;
import dun.security.permissions : PermissionRegistry;

struct DunState
{
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}

void installGlobals(IJSEngine engine, DunState* state) @trusted
{
    assert(engine !is null, "Null engine");
    assert(state !is null, "Null state");
    assert(state.engine is engine, "State engine mismatch");

    engine.setContextOpaque(cast(void*) state);

    import dun.runtime.console : installConsole;
    import dun.runtime.timers_api : installTimers;
    import dun.runtime.microtask_api : installMicrotask;
    import dun.runtime.process_api : installProcess;
    import dun.builtins.fs : registerFsModule;
    import dun.builtins.path : registerPathModule;
    import dun.builtins.crypto : registerCryptoModule;
    import dun.builtins.net : registerNetModule;
    import dun.builtins.http : registerHttpModule;
    import dun.builtins.http2 : registerHttp2Module;
    import dun.builtins.buffer : registerBufferModule;
    import dun.builtins.events : registerEventsModule;
    import dun.builtins.url : registerUrlModule;
    import dun.builtins.os : registerOsModule;
    import dun.builtins.zlib : registerZlibModule;
    import dun.builtins.dns : registerDnsModule;
    import dun.builtins.fetch : registerFetchGlobal;
    import dun.builtins.child_process : registerChildProcessModule;
    import dun.builtins.stream : registerStreamModule;
    import dun.builtins.ws : registerWsModule;
    import dun.builtins.sqlite : registerSqliteModule;
    import dun.builtins.util : registerUtilModule;
    import dun.builtins.assert_ : registerAssertModule;
    import dun.builtins.querystring : registerQuerystringModule;
    import dun.builtins.string_decoder : registerStringDecoderModule;
    import dun.builtins.timers_promises : registerTimersPromisesModule;
    import dun.builtins.http3 : registerHttp3Module;
    import dun.modules.require : installRequire;

    installConsole(engine);
    installTimers(engine);
    installMicrotask(engine);
    installProcess(engine);
    registerFsModule(engine);
    registerPathModule(engine);
    registerCryptoModule(engine);
    registerNetModule(engine);
    registerHttpModule(engine);
    registerHttp2Module(engine);
    registerBufferModule(engine);
    registerEventsModule(engine);
    registerUrlModule(engine);
    registerOsModule(engine);
    registerZlibModule(engine);
    registerDnsModule(engine);
    registerChildProcessModule(engine);
    registerStreamModule(engine);
    registerWsModule(engine);
    registerSqliteModule(engine);
    registerUtilModule(engine);
    registerAssertModule(engine);
    registerQuerystringModule(engine);
    registerStringDecoderModule(engine);
    registerTimersPromisesModule(engine);
    registerHttp3Module(engine);

    version (Posix)
        registerFetchGlobal(engine);

    import dun.runtime.web_compat : installWebCompat;
    installWebCompat(engine);

    import dun.runtime.web_apis : installWebAPIs;
    installWebAPIs(engine);

    import dun.runtime.deno_compat : installDenoCompat;
    installDenoCompat(engine);

    installRequire(engine);

    import dun.runtime.rejection_tracker : installRejectionTracker;
    installRejectionTracker(engine, state);

    auto global = engine.getGlobal();
    engine.setProperty(global, "gc", engine.newFunction(&jsGlobalGC, "gc", 0));

    import dun.runtime.worker_api : installWorkerAPI;
    installWorkerAPI(engine, state);
}

private JSHandle jsGlobalGC(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGlobalGC");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in jsGlobalGC");
    state.engine.collectGarbage();
    return state.engine.newUndefined();
}
