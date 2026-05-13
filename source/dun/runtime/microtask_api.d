module dun.runtime.microtask_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installMicrotask(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto global = engine.getGlobal();
    engine.setProperty(global, "queueMicrotask",
        engine.newFunction(&jsQueueMicrotask, "queueMicrotask", 1));
}

private:

JSHandle jsQueueMicrotask(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in queueMicrotask");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    assert(engine !is null, "Null engine in queueMicrotask");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.throwTypeError("queueMicrotask requires a function");

    state.eventLoop.microtasks.enqueue(engine, args[0]);
    return engine.newUndefined();
}
