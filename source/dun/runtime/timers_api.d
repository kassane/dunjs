module dun.runtime.timers_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.loop.timers : TimerID;
import dun.runtime.globals : DunState;
import core.time : dur;

void installTimers(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto global = engine.getGlobal();
    scope (exit) engine.freeValue(global);

    engine.setProperty(global, "setTimeout",
        engine.newFunction(&jsSetTimeout, "setTimeout", 2));
    engine.setProperty(global, "setInterval",
        engine.newFunction(&jsSetInterval, "setInterval", 2));
    engine.setProperty(global, "clearTimeout",
        engine.newFunction(&jsClearTimer, "clearTimeout", 1));
    engine.setProperty(global, "clearInterval",
        engine.newFunction(&jsClearTimer, "clearInterval", 1));
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

    return makeTimerObject(engine, cast(int) id);
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

    return makeTimerObject(engine, cast(int) id);
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

    int id;
    if (engine.isObject(args[0]))
    {
        auto idProp = engine.getProperty(args[0], "_id");
        id = engine.extractInt(idProp);
        engine.freeValue(idProp);
    }
    else
    {
        id = engine.extractInt(args[0]);
    }

    if (id > 0)
        state.eventLoop.timers.cancelTimer(cast(TimerID) id);

    return engine.newUndefined();
}

JSHandle makeTimerObject(IJSEngine engine, int id) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "_id", engine.newInt(id));
    engine.setProperty(obj, "ref", engine.newFunction(&jsTimerRef, "ref", 0));
    engine.setProperty(obj, "unref", engine.newFunction(&jsTimerUnref, "unref", 0));
    engine.setProperty(obj, "hasRef", engine.newFunction(&jsTimerHasRef, "hasRef", 0));
    engine.setProperty(obj, "refresh", engine.newFunction(&jsTimerRef, "refresh", 0));

    // valueOf + Symbol.toPrimitive for numeric coercion (clearTimeout(timer) compat).
    // Uses the cached setup fn registered in installTimers -- avoids an
    // engine.eval per call (this path runs on every setTimeout/setInterval).
    /* valueOf: native D callback that reads `this._id`. Replaces the
       v1.1.5-v1.1.21 cached JS setup-fn approach which reliably crashed
       QJS's `add_shape_property` when invoked from a setTimeout
       callback that creates another setTimeout AND a Worker had been
       constructed earlier (gdb-traced — the cached fn's bytecode
       referenced a `Function.prototype` shape ID that QJS's shape
       table had reorged after the Worker installer's heavy install-
       time JS eval). Native callback works on all 3 backends + doesn't
       depend on JS-side shape state. clearTimeout also accepts the raw
       timer object directly (see jsClearTimer at line 105), so most
       code doesn't even need this; valueOf is for Node compat where
       `+timer === id` is observable. Symbol.toPrimitive is skipped on
       QJS for the same QJS-specific shape-fragility reason; the rare
       caller that explicitly invokes `[Symbol.toPrimitive]('number')`
       on a timer hits the valueOf fallback through Number() coercion. */
    engine.setProperty(obj, "valueOf",
        engine.newFunction(&jsTimerValueOf, "valueOf", 0));

    return obj;
}

JSHandle jsTimerRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    return state.engine.dupValue(thisVal);
}

JSHandle jsTimerUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    return state.engine.dupValue(thisVal);
}

JSHandle jsTimerHasRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    return state.engine.newBool(true);
}

/// `+timer` → reads `this._id` via a native fast path. Replaces the
/// crash-prone cached JS setup-fn (see comment at makeTimerObject).
JSHandle jsTimerValueOf(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto idProp = engine.getProperty(thisVal, "_id");
    scope(exit) engine.freeValue(idProp);
    if (!engine.isNumber(idProp))
        return engine.newInt(0);
    return engine.newInt(engine.extractInt(idProp));
}
