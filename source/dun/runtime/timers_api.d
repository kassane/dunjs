module dun.runtime.timers_api;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.loop.timers : TimerID;
import core.time : dur;

void installTimers(JSContext* ctx, void* stateOpaque) @trusted
{
    auto global = JS_GetGlobalObject(ctx);

    JS_SetPropertyStr(ctx, global, "setTimeout",
        JS_NewCFunction(ctx, &jsSetTimeout, "setTimeout", 2));
    JS_SetPropertyStr(ctx, global, "setInterval",
        JS_NewCFunction(ctx, &jsSetInterval, "setInterval", 2));
    JS_SetPropertyStr(ctx, global, "clearTimeout",
        JS_NewCFunction(ctx, &jsClearTimer, "clearTimeout", 1));
    JS_SetPropertyStr(ctx, global, "clearInterval",
        JS_NewCFunction(ctx, &jsClearTimer, "clearInterval", 1));

    JS_FreeValue(ctx, global);
}

private:

import dun.runtime.globals : DunState;

extern (C) JSValue jsSetTimeout(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1 || !JS_IsFunction(ctx, argv[0]))
        return JS_UNDEFINED();

    auto state = cast(DunState*) JS_GetContextOpaque(ctx);

    double delayMs = 0;
    if (argc >= 2)
        JS_ToFloat64(ctx, &delayMs, argv[1]);
    if (delayMs < 0)
        delayMs = 0;

    auto id = state.eventLoop.timers.addTimer(
        ctx, cast(JSValue) argv[0],
        dur!"msecs"(cast(long) delayMs),
        dur!"msecs"(0),
    );

    return JS_NewInt32(ctx, cast(int) id);
}

extern (C) JSValue jsSetInterval(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1 || !JS_IsFunction(ctx, argv[0]))
        return JS_UNDEFINED();

    auto state = cast(DunState*) JS_GetContextOpaque(ctx);

    double intervalMs = 0;
    if (argc >= 2)
        JS_ToFloat64(ctx, &intervalMs, argv[1]);
    if (intervalMs < 0)
        intervalMs = 0;

    immutable ms = cast(long) intervalMs;
    auto id = state.eventLoop.timers.addTimer(
        ctx, cast(JSValue) argv[0],
        dur!"msecs"(ms),
        dur!"msecs"(ms),
    );

    return JS_NewInt32(ctx, cast(int) id);
}

extern (C) JSValue jsClearTimer(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_UNDEFINED();

    auto state = cast(DunState*) JS_GetContextOpaque(ctx);

    int id;
    JS_ToInt32(ctx, &id, argv[0]);
    if (id > 0)
        state.eventLoop.timers.cancelTimer(cast(TimerID) id);

    return JS_UNDEFINED();
}
