module dun.runtime.timers_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.loop.timers : TimerID;
import dun.runtime.globals : DunState;
import core.time : dur;

void installTimers(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto global = engine.getGlobal();

    engine.setProperty(global, "setTimeout",
        engine.newFunction(&jsSetTimeout, "setTimeout", 2));
    engine.setProperty(global, "setInterval",
        engine.newFunction(&jsSetInterval, "setInterval", 2));
    engine.setProperty(global, "clearTimeout",
        engine.newFunction(&jsClearTimer, "clearTimeout", 1));
    engine.setProperty(global, "clearInterval",
        engine.newFunction(&jsClearTimer, "clearInterval", 1));
    engine.freeValue(global);
}

private:

JSHandle jsSetTimeout(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in setTimeout");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in setTimeout");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in setTimeout");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.newUndefined();

    double delayMs = 0;
    if (args.length >= 2)
        delayMs = engine.extractFloat(args[1]);
    if (delayMs < 0)
        delayMs = 0;

    auto id = state.eventLoop.timers.addTimer(
        engine, args[0],
        dur!"msecs"(cast(long) delayMs),
        dur!"msecs"(0),
    );

    return engine.newInt(cast(int) id);
}

JSHandle jsSetInterval(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in setInterval");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in setInterval");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in setInterval");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.newUndefined();

    double intervalMs = 0;
    if (args.length >= 2)
        intervalMs = engine.extractFloat(args[1]);
    if (intervalMs < 0)
        intervalMs = 0;

    immutable ms = cast(long) intervalMs;
    auto id = state.eventLoop.timers.addTimer(
        engine, args[0],
        dur!"msecs"(ms),
        dur!"msecs"(ms),
    );

    return engine.newInt(cast(int) id);
}

JSHandle jsClearTimer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in clearTimer");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in clearTimer");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in clearTimer");

    if (args.length < 1)
        return engine.newUndefined();

    int id = engine.extractInt(args[0]);
    if (id > 0)
        state.eventLoop.timers.cancelTimer(cast(TimerID) id);

    return engine.newUndefined();
}
