module dun.runtime.process_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void installProcess(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto state = cast(DunState*) engine.getContextOpaque();
    auto global = engine.getGlobal();
    auto process = engine.newObject();

    engine.setProperty(process, "nextTick",
        engine.newFunction(&jsNextTick, "nextTick", 1));

    auto envObj = engine.newObject();
    bool envAllowed = state !is null && state.permissions !is null &&
        state.permissions.check(Permission.env);
    if (envAllowed)
    {
        try
        {
            import std.process : environment;
            foreach (key, val; environment.toAA())
                engine.setProperty(envObj, key, engine.newString(val));
        }
        catch (Exception) {}
    }
    engine.setProperty(process, "env", envObj);

    engine.setProperty(global, "process", process);
}

private:

JSHandle jsNextTick(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.nextTick");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    assert(engine !is null, "Null engine in process.nextTick");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.throwTypeError("process.nextTick requires a function");

    state.eventLoop.nextTicks.enqueue(engine, args[0]);
    return engine.newUndefined();
}
