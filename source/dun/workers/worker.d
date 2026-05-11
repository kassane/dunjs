module dun.workers.worker;

version (EngineQuickJS):

import core.thread : Thread;
import core.sync.mutex : Mutex;
import dun.workers.channel : MessageChannel;
import dun.engine.quickjs.bindings : JSContext, JSValue, JS_UNDEFINED,
    JS_NewObject, JS_NewStringLen, JS_SetPropertyStr, JS_GetPropertyStr,
    JS_IsFunction, JS_FreeValue, JS_Call, JS_DupValue,
    JS_ToCStringLen2, JS_FreeCString, JS_JSONStringify,
    JS_IsException, JS_IsNull, JS_GetGlobalObject;
import dun.engine.iface : IJSEngine;
import dun.runtime.globals : DunState;
import dun.security.permissions : PermissionRegistry, Permission;

enum WorkerStatus { pending, running, done }

final class WorkerState
{
    MessageChannel toWorker;
    MessageChannel fromWorker;
    WorkerStatus status_;
    string scriptPath;
    JSValue jsWorkerVal;   // JS Worker object on main ctx (duped ref)
    bool jsWorkerValSet;
    JSContext* mainCtx;

    this(string path, JSContext* ctx) @trusted
    {
        toWorker = new MessageChannel();
        fromWorker = new MessageChannel();
        status_ = WorkerStatus.pending;
        scriptPath = path;
        mainCtx = ctx;
    }
}

// Thread-local: true inside worker threads (Atomics.wait → "not-allowed" on main)
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
    if (gIsWorkerThread)  // worker threads don't create sub-workers
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

// Deliver any queued fromWorker messages to worker.onmessage (main event loop)
void pollWorkerMessages(JSContext* ctx) @trusted
{
    if (gIsWorkerThread)  // only the main thread delivers messages
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
            auto handler = JS_GetPropertyStr(ctx, wst.jsWorkerVal, "onmessage");
            if (!JS_IsFunction(ctx, handler))
            {
                JS_FreeValue(ctx, handler);
                continue;
            }

            auto evObj = _makeMessageEvent(ctx, msg);
            JSValue[1] argv = [evObj];
            auto ret = JS_Call(ctx, handler, JS_UNDEFINED(), 1, argv.ptr);
            JS_FreeValue(ctx, ret);
            JS_FreeValue(ctx, evObj);
            JS_FreeValue(ctx, handler);
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
    import dun.engine.iface : createEngine, EngineConfig;
    import dun.modules.loader : ModuleLoader;
    import dun.engine.quickjs.bindings : JSRuntime;
    import dun.runtime.worker_self : installWorkerSelf;
    import std.file : readText;
    import std.path : absolutePath, dirName;
    import std.string : replace;

    auto engine = createEngine();
    engine.initialize(EngineConfig(64 * 1024 * 1024, 512 * 1024));

    auto perms = new PermissionRegistry();
    perms.grant(Permission.all);

    DunState state;
    state.engine = engine;
    state.permissions = perms;
    state.eventLoop.initialize(engine);

    _installGlobals(engine, &state);

    auto ctx = cast(JSContext*) engine.rawContext();
    installWorkerSelf(ctx, &state, wst);

    ModuleLoader loader;
    loader.install(cast(JSRuntime*) engine.rawRuntime());

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
    engine.eval(`var __filename="` ~ eabs ~ `";var __dirname="` ~ edir ~ `";`, "<init>");
    auto res = engine.eval(source, wst.scriptPath);
    if (res.isError)
        return;

    while (state.eventLoop.hasWork() || !wst.toWorker.empty())
    {
        _drainIncoming(ctx, &state, wst);
        state.eventLoop.tick();
        _drainIncoming(ctx, &state, wst);
    }
}

private void _drainIncoming(JSContext* ctx, DunState* state, WorkerState wst) @trusted
{
    string msg;
    while (wst.toWorker.tryRecv(msg))
    {
        auto global = JS_GetGlobalObject(ctx);
        auto selfObj = JS_GetPropertyStr(ctx, global, "self");
        JS_FreeValue(ctx, global);

        auto handler = JS_GetPropertyStr(ctx, selfObj, "onmessage");
        JS_FreeValue(ctx, selfObj);

        if (!JS_IsFunction(ctx, handler))
        {
            JS_FreeValue(ctx, handler);
            continue;
        }

        auto evObj = _makeMessageEvent(ctx, msg);
        JSValue[1] argv = [evObj];
        auto ret = JS_Call(ctx, handler, JS_UNDEFINED(), 1, argv.ptr);
        JS_FreeValue(ctx, ret);
        JS_FreeValue(ctx, evObj);
        JS_FreeValue(ctx, handler);

        state.eventLoop.drainMicrotasks();
    }
}

private JSValue _makeMessageEvent(JSContext* ctx, string jsonMsg) nothrow @trusted
{
    auto jsonStr = JS_NewStringLen(ctx, jsonMsg.ptr, jsonMsg.length);

    auto global = JS_GetGlobalObject(ctx);
    auto json = JS_GetPropertyStr(ctx, global, "JSON");
    auto parseFn = JS_GetPropertyStr(ctx, json, "parse");
    JS_FreeValue(ctx, json);
    JS_FreeValue(ctx, global);

    JSValue[1] parseArgv = [jsonStr];
    auto parsed = JS_Call(ctx, parseFn, JS_UNDEFINED(), 1, parseArgv.ptr);
    JS_FreeValue(ctx, parseFn);
    JS_FreeValue(ctx, jsonStr);

    auto evObj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, evObj, "data", parsed);
    return evObj;
}

private bool _isTS(string path) @safe pure nothrow @nogc
{
    if (path.length >= 3 && path[$ - 3 .. $] == ".ts")  return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".mts") return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".cts") return true;
    return false;
}

// Forward to installGlobals via local import to avoid module-level cycle
private void _installGlobals(IJSEngine engine, DunState* state) @trusted
{
    import dun.runtime.globals : installGlobals;
    installGlobals(engine, state);
}
