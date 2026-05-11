module dun.runtime.rejection_tracker;

import dun.engine.iface : IJSEngine;
import dun.loop.eventloop : RejectedPromise;
import dun.runtime.globals : DunState;

void installRejectionTracker(IJSEngine engine, DunState* state) @trusted
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings : JSRuntime, JS_GetRuntime;
        alias CB = extern (C) void function(
            dun.engine.quickjs.bindings.JSContext*,
            dun.engine.quickjs.bindings.JSValueConst,
            dun.engine.quickjs.bindings.JSValueConst,
            bool, void*) nothrow @nogc;
        auto ctx = cast(dun.engine.quickjs.bindings.JSContext*) engine.rawContext();
        JS_SetHostPromiseRejectionTracker(
            JS_GetRuntime(ctx),
            cast(CB) &qjsOnPromiseRejection,
            cast(void*) state);
    }
    else
    {
        // JSC/V8: install JS-based rejection tracking
        installJSRejectionTracker(engine, state);
    }
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;
    import dun.engine.iface : JSHandle;

    private extern (C) void qjsOnPromiseRejection(JSContext* ctx,
        JSValueConst promise, JSValueConst reason,
        bool is_handled, void* opaque) nothrow @trusted
    {
        import dun.engine.quickjs.backend : QuickJSEngine;
        auto state = cast(DunState*) opaque;

        if (is_handled)
        {
            size_t found = size_t.max;
            foreach (i, ref entry; state.eventLoop.unhandledRejections)
            {
                auto entryPromise = QuickJSEngine.fromHandle(entry.promise);
                if (JS_IsSameValue(ctx, entryPromise, promise))
                {
                    try
                    {
                        state.engine.freeValue(entry.promise);
                        state.engine.freeValue(entry.reason);
                    }
                    catch (Throwable) {}
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

        string reasonStr;
        try
        {
            size_t cstr_len;
            const(char)* cstr = JS_ToCStringLen2(ctx, &cstr_len, reason, false);
            if (JS_HasException(ctx))
            {
                auto exc = JS_GetException(ctx);
                JS_FreeValue(ctx, exc);
            }
            reasonStr = cstr ? cstr[0 .. cstr_len].idup : "";
            if (cstr) JS_FreeCString(ctx, cstr);
        }
        catch (Throwable) {}

        auto entry = RejectedPromise(
            state.engine,
            QuickJSEngine.toHandle(JS_DupValue(ctx, cast(JSValue) promise)),
            QuickJSEngine.toHandle(JS_DupValue(ctx, cast(JSValue) reason)),
            reasonStr);

        try { state.eventLoop.unhandledRejections ~= entry; }
        catch (Throwable)
        {
            try
            {
                state.engine.freeValue(entry.promise);
                state.engine.freeValue(entry.reason);
            }
            catch (Throwable) {}
        }
    }
}

private void installJSRejectionTracker(IJSEngine engine, DunState* state) @trusted
{
    import dun.engine.iface : NativeCallback, JSHandle;

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dunRejections__", engine.newArray());
    engine.setProperty(global, "__dunRejectionIdx__", engine.newInt(0));

    engine.setProperty(global, "__dunReportRejection__",
        engine.newFunction(&jsReportRejection, "__dunReportRejection__", 1));

    auto setupResult = engine.eval(
        `(function() {
            if (typeof globalThis.addEventListener === 'function') {
                globalThis.addEventListener('unhandledrejection', function(e) {
                    __dunReportRejection__(e.reason);
                });
            }
        })()`, "<rejection-setup>");
    if (!setupResult.isError)
        engine.freeValue(setupResult.value);
}

private JSHandle jsReportRejection(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.engine.iface : JSHandle;
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    string reasonStr;
    if (args.length > 0)
    {
        try { reasonStr = engine.extractString(args[0]); }
        catch (Exception) {}
    }

    auto entry = RejectedPromise(
        engine,
        engine.newUndefined(),
        args.length > 0 ? engine.dupValue(args[0]) : engine.newUndefined(),
        reasonStr);

    try { state.eventLoop.unhandledRejections ~= entry; }
    catch (Throwable)
    {
        engine.freeValue(entry.promise);
        engine.freeValue(entry.reason);
    }

    return engine.newUndefined();
}
