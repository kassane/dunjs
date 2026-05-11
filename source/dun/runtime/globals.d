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
    engine.setContextOpaque(cast(void*) state);

    import dun.runtime.console : installConsole;
    import dun.runtime.timers_api : installTimers;
    import dun.runtime.microtask_api : installMicrotask;
    import dun.runtime.process_api : installProcess;
    import dun.builtins.fs : registerFsModule;
    import dun.builtins.path : registerPathModule;
    import dun.builtins.crypto : registerCryptoModule;
    import dun.modules.require : installRequire;

    installConsole(engine);
    installTimers(engine);
    installMicrotask(engine);
    installProcess(engine);
    registerFsModule(engine);
    registerPathModule(engine);
    registerCryptoModule(engine);
    installRequire(engine);

    import dun.runtime.rejection_tracker : installRejectionTracker;
    installRejectionTracker(engine, state);

    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings : JSContext;
        import dun.builtins.net : registerNetModule;
        import dun.builtins.http : registerHttpModule;
        auto ctx = cast(JSContext*) engine.rawContext();
        registerNetModule(ctx);
        registerHttpModule(ctx);
        import dun.runtime.worker_api : installWorkerAPI;
        installWorkerAPI(ctx, state);
    }
}
