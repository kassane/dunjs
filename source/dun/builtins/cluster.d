module dun.builtins.cluster;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

/// Maximum number of tracked worker processes.
private enum MAX_WORKERS = 1024;
/// Maximum number of registered exit callbacks.
private enum MAX_EXIT_CALLBACKS = 64;
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

    if (!isWorker)
    {
        engine.setProperty(obj, "fork", engine.newFunction(&jsClusterFork, "fork", 0));
        engine.setProperty(obj, "on", engine.newFunction(&jsClusterOn, "on", 2));
        engine.setProperty(obj, "workers", engine.newObject());
        gClusterEngine = engine;
    }

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_cluster__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

/// Returns true if there are active cluster worker processes being tracked.
public bool hasActiveClusterWorkers() nothrow @trusted
{
    return gWorkerCount > 0;
}

/// Poll for exited worker processes (called from event loop tick).
/// Uses waitpid(WNOHANG) to reap children without blocking.
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
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:cluster", &clusterModuleInit);
        if (m is null) return;
        foreach (name; ["isPrimary", "isWorker", "isMaster", "fork", "on", "workers"])
            JS_AddModuleExport(ctx, m, name.ptr);
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
        JS_FreeValue(ctx, clObj);
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

JSHandle jsClusterFork(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsClusterFork");
    auto state = cast(DunState*) ctx;
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

            import std.conv : to;
            engine.setProperty(workersObj, pid.to!string, workerObj);

            // Return worker info with pid
            auto retObj = engine.newObject();
            engine.setProperty(retObj, "pid", engine.newInt(pid));
            return retObj;
        }
    }
    else
    {
        return engine.throwTypeError("cluster.fork() is not supported on this platform");
    }
}

JSHandle jsClusterOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsClusterOn");
    auto state = cast(DunState*) ctx;
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
    return engine.getProperty(global, "__dun_cjs_cluster__");
}
