module dun.runtime.worker_self;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;
import dun.workers.worker : WorkerState;

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
    assert(ctx !is null, "Null ctx in self.postMessage");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in self.postMessage");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newUndefined();

    auto wst = _getWst(engine);
    if (!wst)
        return engine.newUndefined();

    import dun.workers.worker : jsonStringify;
    auto jsonStr = jsonStringify(engine, args[0]);
    if (jsonStr is null)
        return engine.newUndefined();

    try { wst.fromWorker.send(jsonStr); }
    catch (Throwable) {}

    return engine.newUndefined();
}

private JSHandle _selfClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in self.close");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in self.close");

    auto wst = _getWst(state.engine);
    if (wst)
    {
        try { wst.toWorker.close(); wst.fromWorker.close(); }
        catch (Throwable) {}
    }

    return state.engine.newUndefined();
}
