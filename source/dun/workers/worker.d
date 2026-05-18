module dun.workers.worker;

import core.thread : Thread;
import core.sync.mutex : Mutex;
import dun.workers.channel : MessageChannel;
import dun.engine.iface : IJSEngine, JSHandle, EngineConfig, createEngine,
    TEST_MEMORY_LIMIT, mustEval;
import dun.runtime.globals : DunState;
import dun.security.permissions : PermissionRegistry, Permission;

enum WorkerStatus { pending, running, done }

private enum : size_t {
    WORKER_MEMORY_LIMIT = TEST_MEMORY_LIMIT,
    WORKER_STACK_SIZE   = 512 * 1024,
}

final class WorkerState
{
    MessageChannel toWorker;
    MessageChannel fromWorker;
    WorkerStatus status_;
    string scriptPath;
    JSHandle jsWorkerVal;
    bool jsWorkerValSet;
    IJSEngine mainEngine;

    this(string path, IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in WorkerState constructor");
        toWorker = new MessageChannel();
        fromWorker = new MessageChannel();
        status_ = WorkerStatus.pending;
        scriptPath = path;
        mainEngine = engine;
    }
}

bool gIsWorkerThread = false;

private __gshared WorkerState[] gWorkers;
private __gshared Mutex gWorkersMutex;

shared static this() @system
{
    gWorkersMutex = new Mutex();
}

void registerWorker(WorkerState wst) @trusted
{
    synchronized (gWorkersMutex)
        gWorkers ~= wst;
}

bool hasActiveWorkers() @trusted
{
    if (gIsWorkerThread)
        return false;
    synchronized (gWorkersMutex)
    {
        foreach (w; gWorkers)
        {
            if (w.status_ != WorkerStatus.done || !w.fromWorker.empty())
                return true;
        }
        return false;
    }
}

void pollWorkerMessages(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in pollWorkerMessages");
    if (gIsWorkerThread)
        return;
    WorkerState[] snapshot;
    try { synchronized (gWorkersMutex) snapshot = gWorkers.dup; }
    catch (Throwable) { return; }

    foreach (wst; snapshot)
    {
        if (!wst.jsWorkerValSet)
            continue;

        string msg;
        while (wst.fromWorker.tryRecv(msg))
        {
            auto handler = engine.getProperty(wst.jsWorkerVal, "onmessage");
            if (!engine.isFunction(handler))
            {
                engine.freeValue(handler);
                continue;
            }

            auto evObj = makeMessageEvent(engine, msg);
            JSHandle[1] argv = [evObj];
            auto ret = engine.callFunction(handler, engine.newUndefined(), argv[]);
            engine.freeValue(ret);
            engine.freeValue(evObj);
            engine.freeValue(handler);
        }
    }
}

void spawnWorker(WorkerState wst) @trusted
{
    auto t = new Thread(delegate void()
    {
        gIsWorkerThread = true;
        wst.status_ = WorkerStatus.running;
        try { _runWorker(wst); }
        catch (Throwable) {}
        wst.status_ = WorkerStatus.done;
    });
    t.isDaemon = true;
    t.start();
}

private void _runWorker(WorkerState wst) @trusted
{
    import dun.runtime.worker_self : installWorkerSelf;
    import std.file : readText;
    import std.path : absolutePath, dirName;
    import std.string : replace;

    auto engine = createEngine();
    engine.initialize(EngineConfig(WORKER_MEMORY_LIMIT, WORKER_STACK_SIZE));

    auto perms = new PermissionRegistry();
    perms.grant(Permission.all);

    DunState state;
    state.engine = engine;
    state.permissions = perms;
    state.eventLoop.initialize(engine);

    _installGlobals(engine, &state);

    installWorkerSelf(engine, &state, wst);

    version (EngineQuickJS)
    {
        import dun.modules.loader : ModuleLoader;
        import dun.engine.quickjs.bindings : JSRuntime;
        ModuleLoader loader;
        loader.install(cast(JSRuntime*) engine.rawRuntime());
    }

    string source;
    try { source = readText(wst.scriptPath); }
    catch (Exception) { return; }

    if (_isTS(wst.scriptPath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
    }

    auto abs  = absolutePath(wst.scriptPath);
    auto dir  = dirName(abs);
    auto eabs = abs.replace(`\`, `\\`).replace(`"`, `\"`);
    auto edir = dir.replace(`\`, `\\`).replace(`"`, `\"`);
    // Set __filename / __dirname before the user script runs. Closed-
    // world string concat — a failure here is a build-time bug, not
    // a user-data issue. `mustEval` is the canonical drop-only
    // consumer for `@mustuse JSResult` (DIP 1038).
    mustEval(engine,
        `var __filename="` ~ eabs ~ `";var __dirname="` ~ edir ~ `";`,
        "<worker-init>", "Worker __filename/__dirname init");

    auto res = engine.eval(source, wst.scriptPath);
    if (res.isError)
        return;

    while (state.eventLoop.hasWork() || !wst.toWorker.empty())
    {
        _drainIncoming(engine, &state, wst);
        state.eventLoop.tick();
        _drainIncoming(engine, &state, wst);
    }
}

private void _drainIncoming(IJSEngine engine, DunState* state, WorkerState wst) @trusted
{
    assert(engine !is null, "Null engine in _drainIncoming");
    string msg;
    while (wst.toWorker.tryRecv(msg))
    {
        auto global = engine.getGlobal();
        auto selfObj = engine.getProperty(global, "self");
        engine.freeValue(global);

        auto handler = engine.getProperty(selfObj, "onmessage");
        engine.freeValue(selfObj);

        if (!engine.isFunction(handler))
        {
            engine.freeValue(handler);
            continue;
        }

        auto evObj = makeMessageEvent(engine, msg);
        JSHandle[1] argv = [evObj];
        auto ret = engine.callFunction(handler, engine.newUndefined(), argv[]);
        engine.freeValue(ret);
        engine.freeValue(evObj);
        engine.freeValue(handler);

        state.eventLoop.drainMicrotasks();
    }
}

JSHandle makeMessageEvent(IJSEngine engine, string jsonMsg) @trusted
{
    assert(engine !is null, "Null engine in makeMessageEvent");
    try
    {
        auto global = engine.getGlobal();
        auto json = engine.getProperty(global, "JSON");
        auto parseFn = engine.getProperty(json, "parse");
        engine.freeValue(json);
        engine.freeValue(global);

        auto jsonStr = engine.newString(jsonMsg);
        JSHandle[1] parseArgv = [jsonStr];
        auto parsed = engine.callFunction(parseFn, engine.newUndefined(), parseArgv[]);
        engine.freeValue(parseFn);
        engine.freeValue(jsonStr);

        auto evObj = engine.newObject();
        engine.setProperty(evObj, "data", parsed);
        return evObj;
    }
    catch (Throwable)
    {
        return engine.newUndefined();
    }
}

string jsonStringify(IJSEngine engine, JSHandle val) @trusted
{
    assert(engine !is null, "Null engine in jsonStringify");
    try
    {
        auto global = engine.getGlobal();
        auto json = engine.getProperty(global, "JSON");
        auto stringifyFn = engine.getProperty(json, "stringify");
        engine.freeValue(json);
        engine.freeValue(global);

        JSHandle[1] argv = [val];
        auto result = engine.callFunction(stringifyFn, engine.newUndefined(), argv[]);
        engine.freeValue(stringifyFn);

        if (engine.isException(result) || engine.isUndefined(result))
        {
            engine.freeValue(result);
            return null;
        }

        auto str = engine.extractString(result);
        engine.freeValue(result);
        return str;
    }
    catch (Throwable) { return null; }
}

private bool _isTS(string path) @safe pure nothrow @nogc
{
    if (path.length >= 3 && path[$ - 3 .. $] == ".ts")  return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".mts") return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".cts") return true;
    return false;
}

private void _installGlobals(IJSEngine engine, DunState* state) @trusted
{
    import dun.runtime.globals : installGlobals;
    installGlobals(engine, state);
}
