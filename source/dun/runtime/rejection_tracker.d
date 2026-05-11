module dun.runtime.rejection_tracker;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.loop.eventloop : RejectedPromise;
import dun.runtime.globals : DunState;

void installRejectionTracker(JSRuntime* rt, DunState* state) @trusted
{
    // Cast away @nogc: the D GC remains functional during C->D callbacks.
    // The callback allocates (RejectedPromise[]) but is wrapped in try-catch.
    alias CB = extern (C) void function(
        JSContext*, JSValueConst, JSValueConst, bool, void*) nothrow @nogc;
    JS_SetHostPromiseRejectionTracker(rt, cast(CB) &onPromiseRejection, cast(void*) state);
}

private extern (C) void onPromiseRejection(JSContext* ctx,
    JSValueConst promise, JSValueConst reason,
    bool is_handled, void* opaque) nothrow @trusted
{
    auto state = cast(DunState*) opaque;

    if (is_handled)
    {
        size_t found = size_t.max;
        foreach (i, ref entry; state.eventLoop.unhandledRejections)
        {
            if (JS_IsSameValue(ctx, entry.promise, promise))
            {
                JS_FreeValue(entry.ctx, entry.promise);
                JS_FreeValue(entry.ctx, entry.reason);
                found = i;
                break;
            }
        }
        if (found != size_t.max)
        {
            try
            {
                state.eventLoop.unhandledRejections =
                    state.eventLoop.unhandledRejections[0 .. found] ~
                    state.eventLoop.unhandledRejections[found + 1 .. $];
            }
            catch (Throwable) {}
        }
        return;
    }

    auto entry = RejectedPromise(
        ctx,
        JS_DupValue(ctx, cast(JSValue) promise),
        JS_DupValue(ctx, cast(JSValue) reason));

    // M2: ~= may throw OutOfMemoryError; absorb it — lossy under OOM,
    // acceptable for Phase 2 (tracked as follow-up S8 / ring buffer).
    try
    {
        state.eventLoop.unhandledRejections ~= entry;
    }
    catch (Throwable)
    {
        JS_FreeValue(ctx, entry.promise);
        JS_FreeValue(ctx, entry.reason);
    }
}
