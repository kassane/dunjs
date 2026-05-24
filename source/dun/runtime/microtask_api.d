module dun.runtime.microtask_api;


/++
 + `@trusted policy`: `queueMicrotask` JS global. `@trusted` for
 + the `cast(DunState*) ctx` via `ctxState(ctx)` + the
 + `state.eventLoop.microtasks.enqueue` call (mutates the
 + `__gshared` queue).
 +/
import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;

void installMicrotask(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto global = engine.getGlobal();
    engine.setProperty(global, "queueMicrotask",
        engine.newFunction(&jsQueueMicrotask, "queueMicrotask", 1));
    engine.freeValue(global);
}

private:

JSHandle jsQueueMicrotask(void* ctx, JSHandle thisVal, scope JSHandle[] args) @safe
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    assert(engine !is null, "Null engine in queueMicrotask");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.throwTypeError("queueMicrotask requires a function");

    state.eventLoop.microtasks.enqueue(engine, args[0]);
    return engine.newUndefined();
}
