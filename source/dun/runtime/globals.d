module dun.runtime.globals;

import dun.engine.iface : IJSEngine;
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
    import dun.builtins.buffer : registerBufferModule;
    import dun.builtins.events : registerEventsModule;
    import dun.builtins.url : registerUrlModule;
    import dun.builtins.os : registerOsModule;
    import dun.builtins.fetch : registerFetchGlobal;
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
    registerBufferModule(engine);
    registerEventsModule(engine);
    registerUrlModule(engine);
    registerOsModule(engine);

    version (Posix)
        registerFetchGlobal(engine);

    import dun.runtime.deno_compat : installDenoCompat;
    installDenoCompat(engine);

    installRequire(engine);

    import dun.runtime.rejection_tracker : installRejectionTracker;
    installRejectionTracker(engine, state);

    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings : JSContext;
        import dun.runtime.worker_api : installWorkerAPI;
        auto ctx = cast(JSContext*) engine.rawContext();
        installWorkerAPI(ctx, state);
    }
}
