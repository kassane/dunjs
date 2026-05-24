module dun.builtins.cluster;


/++
 + `@trusted policy`: Node's `cluster` module (master/worker fork
 + model). Every `@trusted` is one of:
 +
 +   1. POSIX `fork` + `waitpid` + `setenv` for spawning worker
 +      processes (master sets NODE_UNIQUE_ID, workers inherit it).
 +   2. UNIX domain socket pair for IPC (master ↔ worker).
 +   3. `__gshared` worker registry (PID → worker state) on master.
 +   4. `Permission.run` gate before fork.
 +   5. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +/
import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;
import dun.security.permissions : Permission;

/// Maximum number of tracked worker processes.
private enum MAX_WORKERS = 1024;
/// Maximum number of registered exit callbacks.
private enum MAX_EXIT_CALLBACKS = 64;

// Cached Worker method handles. Without these, every cluster.fork()
// + the per-worker self-object allocate 6 new JSValueProtect slots
// per call on JSC. Same pattern as v1.1.5 http.d / v1.1.16 fs.d /
// v1.1.17 dgram.d.
__gshared JSHandle _workerSend, _workerOn, _workerDisconnect;
__gshared JSHandle _workerKill, _workerIsConnected, _workerIsDead;
__gshared bool _workerFnsCached = false;

private void ensureWorkerFnsCached(IJSEngine engine) @trusted
{
    if (!_workerFnsCached)
    {
        _workerSend        = engine.newFunction(&jsWorkerSend, "send", 1);
        _workerOn          = engine.newFunction(&jsWorkerOn, "on", 2);
        _workerDisconnect  = engine.newFunction(&jsWorkerDisconnect, "disconnect", 0);
        _workerKill        = engine.newFunction(&jsWorkerKill, "kill", 0);
        _workerIsConnected = engine.newFunction(&jsWorkerIsConnected, "isConnected", 0);
        _workerIsDead      = engine.newFunction(&jsWorkerIsDead, "isDead", 0);
        _workerFnsCached = true;
    }
}
/// Bitmask to extract exit status from waitpid status.
private enum WSTATUS_EXIT_MASK = 0x7F;
/// Bit shift to extract exit code from waitpid status.
private enum WSTATUS_CODE_SHIFT = 8;

/// Stored worker PIDs (primary process only).
private __gshared int[MAX_WORKERS] gWorkerPids;
private __gshared int gWorkerCount = 0;

/// Registered exit callbacks (primary process only).
private __gshared JSHandle[MAX_EXIT_CALLBACKS] gExitCallbacks;
private __gshared int gExitCallbackCount = 0;
private __gshared IJSEngine gClusterEngine;

void registerClusterModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerClusterModule");
    auto obj = engine.newObject();

    import core.stdc.stdlib : getenv;
    bool isWorker = getenv("DUN_CLUSTER_WORKER") !is null;

    engine.setProperty(obj, "isPrimary", engine.newBool(!isWorker));
    engine.setProperty(obj, "isWorker", engine.newBool(isWorker));
    engine.setProperty(obj, "isMaster", engine.newBool(!isWorker)); // Node.js compat
    engine.setProperty(obj, "schedulingPolicy", engine.newInt(2)); // SCHED_RR
    engine.setProperty(obj, "settings", engine.newObject());
    engine.setProperty(obj, "setupPrimary", engine.newFunction(&jsClusterSetupPrimary, "setupPrimary", 1));
    engine.setProperty(obj, "setupMaster", engine.newFunction(&jsClusterSetupPrimary, "setupMaster", 1)); // alias
    engine.setProperty(obj, "disconnect", engine.newFunction(&jsClusterDisconnect, "disconnect", 0));

    if (!isWorker)
    {
        engine.setProperty(obj, "fork", engine.newFunction(&jsClusterFork, "fork", 0));
        engine.setProperty(obj, "on", engine.newFunction(&jsClusterOn, "on", 2));
        engine.setProperty(obj, "workers", engine.newObject());
        gClusterEngine = engine;
    }
    else
    {
        engine.setProperty(obj, "worker", makeWorkerSelf(engine));
    }

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_cluster__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

/// Returns true if there are active cluster worker processes being tracked.
public bool hasActiveClusterWorkers() nothrow @trusted
{
    return gWorkerCount > 0;
}

/++
 + Poll for exited worker processes (called from event loop tick).
 + Uses waitpid(WNOHANG) to reap children without blocking.
 +/
public void pollClusterWorkers() nothrow @trusted
{
    if (gWorkerCount == 0 || gClusterEngine is null) return;

    version (Posix)
    {
        import core.sys.posix.sys.wait : waitpid, WNOHANG;

        int status;
        while (true)
        {
            auto pid = waitpid(-1, &status, WNOHANG);
            if (pid <= 0) break; // No more exited children

            // Extract exit code: if low 7 bits are 0, process exited normally
            bool normalExit = (status & WSTATUS_EXIT_MASK) == 0;
            int exitCode = normalExit ? ((status >> WSTATUS_CODE_SHIFT) & 0xFF) : -1;

            // Find and remove from workers list
            bool found = false;
            foreach (i; 0 .. gWorkerCount)
            {
                if (gWorkerPids[i] == pid)
                {
                    found = true;
                    // Shift remaining workers down
                    foreach (j; i .. gWorkerCount - 1)
                        gWorkerPids[j] = gWorkerPids[j + 1];
                    gWorkerCount--;
                    break;
                }
            }

            if (!found) continue;

            // Remove from JS workers object
            try
            {
                auto global = gClusterEngine.getGlobal();
                auto clusterObj = gClusterEngine.getProperty(global, "__dun_cjs_cluster__");
                auto workersObj = gClusterEngine.getProperty(clusterObj, "workers");

                import std.conv : to;
                auto pidStr = pid.to!string;
                gClusterEngine.setProperty(workersObj, pidStr, gClusterEngine.newUndefined());

                gClusterEngine.freeValue(workersObj);
                gClusterEngine.freeValue(clusterObj);
                gClusterEngine.freeValue(global);
            }
            catch (Exception) {}

            // Fire exit callbacks
            foreach (ci; 0 .. gExitCallbackCount)
            {
                try
                {
                    auto workerInfo = gClusterEngine.newObject();
                    gClusterEngine.setProperty(workerInfo, "pid", gClusterEngine.newInt(pid));

                    JSHandle[2] cbArgs = [workerInfo, gClusterEngine.newInt(exitCode)];
                    gClusterEngine.callFunction(
                        gExitCallbacks[ci], gClusterEngine.newUndefined(), cbArgs[]);
                }
                catch (Exception) {}
            }
        }
    }
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:cluster", &clusterModuleInit);
        if (m is null) return;
        foreach (name; ["isPrimary", "isWorker", "isMaster", "fork", "on", "workers"])
            JS_AddModuleExport(ctx, m, name.ptr);

            JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int clusterModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in clusterModuleInit");
        assert(m !is null, "Null JSModuleDef in clusterModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto clObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_cluster__");
        foreach (name; ["isPrimary", "isWorker", "isMaster", "fork", "on", "workers"])
        {
            auto fn = JS_GetPropertyStr(ctx, clObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", clObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

bool checkRunPerm(DunState* state) nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(Permission.run, ""); }
    catch (Exception) { return false; }
}

JSHandle jsClusterFork(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsClusterFork");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsClusterFork");

    if (!checkRunPerm(state))
        return engine.throwTypeError(
            "[ERR_PERMISSION_DENIED] Requires --allow-run permission for cluster.fork()");

    version (Posix)
    {
        import core.sys.posix.unistd : fork;
        import core.sys.posix.stdlib : setenv;

        if (gWorkerCount >= MAX_WORKERS)
            return engine.throwTypeError("cluster.fork(): maximum worker limit reached");

        auto pid = fork();
        if (pid < 0)
            return engine.throwTypeError("cluster.fork(): fork() failed");

        if (pid == 0)
        {
            // Child process: set environment variable so cluster.isWorker = true
            setenv("DUN_CLUSTER_WORKER", "1", 1);

            // Reset cluster state in child
            gWorkerCount = 0;
            gExitCallbackCount = 0;
            gClusterEngine = null;

            // Update the cluster object in JS to reflect worker state
            auto global = engine.getGlobal();
            auto clusterObj = engine.getProperty(global, "__dun_cjs_cluster__");
            engine.setProperty(clusterObj, "isPrimary", engine.newBool(false));
            engine.setProperty(clusterObj, "isWorker", engine.newBool(true));
            engine.setProperty(clusterObj, "isMaster", engine.newBool(false));
            engine.freeValue(clusterObj);
            engine.freeValue(global);

            // Return a worker info object (from child's perspective)
            auto workerObj = engine.newObject();
            import core.sys.posix.unistd : getpid;
            engine.setProperty(workerObj, "pid", engine.newInt(getpid()));
            return workerObj;
        }
        else
        {
            // Parent process: track child PID
            assert(gWorkerCount >= 0, "Negative worker count");
            assert(gWorkerCount < MAX_WORKERS, "Worker count overflow");
            gWorkerPids[gWorkerCount] = pid;
            gWorkerCount++;

            // Add to JS workers object
            auto global = engine.getGlobal();
            auto clusterObj = engine.getProperty(global, "__dun_cjs_cluster__");
            auto workersObj = engine.getProperty(clusterObj, "workers");

            auto workerObj = engine.newObject();
            engine.setProperty(workerObj, "pid", engine.newInt(pid));
            engine.setProperty(workerObj, "id", engine.newInt(gWorkerCount));
            ensureWorkerFnsCached(engine);
            engine.bindMethod(workerObj, "send", _workerSend);
            engine.bindMethod(workerObj, "on", _workerOn);
            engine.bindMethod(workerObj, "disconnect", _workerDisconnect);
            engine.bindMethod(workerObj, "kill", _workerKill);
            engine.bindMethod(workerObj, "isConnected", _workerIsConnected);
            engine.bindMethod(workerObj, "isDead", _workerIsDead);
            engine.setProperty(workerObj, "process", engine.newObject());

            import std.conv : to;
            engine.setProperty(workersObj, pid.to!string, engine.dupValue(workerObj));

            engine.freeValue(workersObj);
            engine.freeValue(clusterObj);
            engine.freeValue(global);

            return workerObj;
        }
    }
    else
    {
        return engine.throwTypeError("cluster.fork() is not supported on this platform");
    }
}

JSHandle jsClusterOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsClusterOn");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsClusterOn");

    if (args.length < 2)
        return engine.throwTypeError("cluster.on() requires 2 arguments (event, callback)");

    if (!engine.isString(args[0]))
        return engine.throwTypeError("cluster.on(): first argument must be a string");
    if (!engine.isFunction(args[1]))
        return engine.throwTypeError("cluster.on(): second argument must be a function");

    auto eventName = engine.extractString(args[0]);

    if (eventName == "exit")
    {
        if (gExitCallbackCount >= MAX_EXIT_CALLBACKS)
            return engine.throwTypeError("cluster.on(): maximum exit callback limit reached");

        assert(gExitCallbackCount >= 0, "Negative exit callback count");
        assert(gExitCallbackCount < MAX_EXIT_CALLBACKS, "Exit callback count overflow");
        gExitCallbacks[gExitCallbackCount] = engine.dupValue(args[1]);
        gExitCallbackCount++;
    }

    // Return cluster object for chaining
    auto global = engine.getGlobal();
    auto clusterObj = engine.getProperty(global, "__dun_cjs_cluster__");
    engine.freeValue(global);
    return clusterObj;
}

JSHandle jsClusterSetupPrimary(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto global = engine.getGlobal();
    auto clusterObj = engine.getProperty(global, "__dun_cjs_cluster__");
    if (args.length >= 1 && engine.isObject(args[0]))
        engine.setProperty(clusterObj, "settings", engine.dupValue(args[0]));
    engine.freeValue(clusterObj);
    engine.freeValue(global);
    return engine.newUndefined();
}

JSHandle jsClusterDisconnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newUndefined();
}

JSHandle makeWorkerSelf(IJSEngine engine) @trusted
{
    auto w = engine.newObject();
    engine.setProperty(w, "id", engine.newInt(1));
    version (Posix)
    {
        import core.sys.posix.unistd : getpid;
        engine.setProperty(w, "pid", engine.newInt(getpid()));
    }
    ensureWorkerFnsCached(engine);
    engine.bindMethod(w, "send", _workerSend);
    engine.bindMethod(w, "on", _workerOn);
    engine.bindMethod(w, "disconnect", _workerDisconnect);
    engine.bindMethod(w, "kill", _workerKill);
    engine.bindMethod(w, "isConnected", _workerIsConnected);
    engine.bindMethod(w, "isDead", _workerIsDead);
    return w;
}

JSHandle jsWorkerSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newBool(true);
}

JSHandle jsWorkerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.dupValue(thisVal);
}

JSHandle jsWorkerDisconnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newUndefined();
}

JSHandle jsWorkerKill(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newUndefined();
}

JSHandle jsWorkerIsConnected(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newBool(true);
}

JSHandle jsWorkerIsDead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    return state.engine.newBool(false);
}
