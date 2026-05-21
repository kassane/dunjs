module dun.runtime.worker_self;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;
import dun.workers.worker : WorkerState, jsonStringify;

void installWorkerSelf(IJSEngine engine, DunState* state, WorkerState wst) @trusted
{
    assert(engine !is null, "Null engine in installWorkerSelf");
    assert(state !is null, "Null state in installWorkerSelf");
    assert(wst !is null, "Null WorkerState in installWorkerSelf");

    import std.format : format;

    auto selfObj = engine.newObject();

    auto ptrStr = format!"%x"(cast(size_t) cast(void*) wst);
    engine.setProperty(selfObj, "__wsp__", engine.newString(ptrStr));
    engine.setProperty(selfObj, "postMessage",
        engine.newFunction(&_selfPostMessage, "postMessage", 1));
    engine.setProperty(selfObj, "close",
        engine.newFunction(&_selfClose, "close", 0));

    auto global = engine.getGlobal();
    engine.setProperty(global, "self", selfObj);
    engine.freeValue(global);

    // Wire Node-style `require('worker_threads').parentPort` so worker
    // code that does `parentPort.postMessage(...)` works. parentPort is
    // an EventEmitter that delegates to `self.postMessage` underneath.
    auto wireRes = engine.eval(
        `(function(){`
        ~ `  const wt = globalThis.__dun_cjs_worker_threads__;`
        ~ `  if (!wt) return;`
        ~ `  wt.isMainThread = false;`
        ~ `  const listeners = { message: [], messageerror: [], close: [] };`
        ~ `  const port = {`
        ~ `    postMessage: function(msg) { self.postMessage(msg); },`
        ~ `    on: function(ev, cb) {`
        ~ `      if (listeners[ev]) listeners[ev].push(cb);`
        ~ `      return port;`
        ~ `    },`
        ~ `    once: function(ev, cb) {`
        ~ `      const wrap = function() { port.off(ev, wrap); cb.apply(null, arguments); };`
        ~ `      return port.on(ev, wrap);`
        ~ `    },`
        ~ `    off: function(ev, cb) {`
        ~ `      const a = listeners[ev]; if (!a) return port;`
        ~ `      const i = a.indexOf(cb); if (i >= 0) a.splice(i, 1);`
        ~ `      return port;`
        ~ `    },`
        ~ `    removeListener: function(ev, cb) { return port.off(ev, cb); },`
        ~ `    close: function() { self.close(); }`
        ~ `  };`
        ~ `  wt.parentPort = port;`
        ~ `  self.onmessage = function(ev) {`
        ~ `    for (const fn of listeners.message) fn(ev && ev.data !== undefined ? ev.data : ev);`
        ~ `  };`
        ~ `})();`,
        "<worker-parent-port>");
    if (!wireRes.isError) engine.freeValue(wireRes.value);
}

private WorkerState _getWst(IJSEngine engine) nothrow @trusted
{
    try
    {
        auto global = engine.getGlobal();
        auto selfObj = engine.getProperty(global, "self");
        engine.freeValue(global);
        auto wspVal = engine.getProperty(selfObj, "__wsp__");
        engine.freeValue(selfObj);

        auto hexStr = engine.extractString(wspVal);
        engine.freeValue(wspVal);

        if (hexStr.length == 0)
            return null;

        import core.stdc.stdlib : strtoul;
        import std.string : toStringz;
        size_t ptrVal = cast(size_t) strtoul(hexStr.toStringz, null, 16);
        return cast(WorkerState) cast(void*) ptrVal;
    }
    catch (Throwable) { return null; }
}

private JSHandle _selfPostMessage(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null, "Invalid DunState in self.postMessage");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newUndefined();

    auto wst = _getWst(engine);
    if (!wst)
        return engine.newUndefined();

    auto jsonStr = jsonStringify(engine, args[0]);
    if (jsonStr is null)
        return engine.newUndefined();

    try { wst.fromWorker.send(jsonStr); }
    catch (Throwable) {}

    return engine.newUndefined();
}

private JSHandle _selfClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null, "Invalid DunState in self.close");

    auto wst = _getWst(state.engine);
    if (wst)
    {
        try { wst.toWorker.close(); wst.fromWorker.close(); }
        catch (Throwable) {}
    }

    return state.engine.newUndefined();
}
