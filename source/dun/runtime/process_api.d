module dun.runtime.process_api;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.runtime.globals : DunState;

void installProcess(JSContext* ctx) @trusted
{
    import dun.security.permissions : Permission;

    auto global = JS_GetGlobalObject(ctx);
    auto process = JS_NewObject(ctx);

    JS_SetPropertyStr(ctx, process, "nextTick",
        JS_NewCFunction(ctx, &jsNextTick, "nextTick", 1));

    // process.env — populated only when --allow-env is granted
    auto envObj = JS_NewObject(ctx);
    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    bool envAllowed = state !is null && state.permissions !is null &&
        state.permissions.check(Permission.env);
    if (envAllowed)
    {
        import std.process : environment;
        try
        {
            foreach (key, val; environment.toAA())
            {
                import std.string : toStringz;
                auto jsVal = JS_NewStringLen(ctx, val.ptr, val.length);
                JS_SetPropertyStr(ctx, envObj, key.toStringz, jsVal);
            }
        }
        catch (Exception) {}
    }
    JS_SetPropertyStr(ctx, process, "env", envObj);

    JS_SetPropertyStr(ctx, global, "process", process);
    JS_FreeValue(ctx, global);
}

private extern (C) JSValue jsNextTick(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1 || !JS_IsFunction(ctx, argv[0]))
        return JS_ThrowTypeError(ctx, "process.nextTick requires a function");
    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    state.eventLoop.nextTicks.enqueue(ctx, cast(JSValue) argv[0]);
    return JS_UNDEFINED();
}
