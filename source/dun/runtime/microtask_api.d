module dun.runtime.microtask_api;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.runtime.globals : DunState;

void installMicrotask(JSContext* ctx) @trusted
{
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "queueMicrotask",
        JS_NewCFunction(ctx, &jsQueueMicrotask, "queueMicrotask", 1));
    JS_FreeValue(ctx, global);
}

private extern (C) JSValue jsQueueMicrotask(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1 || !JS_IsFunction(ctx, argv[0]))
        return JS_ThrowTypeError(ctx, "queueMicrotask requires a function");
    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    state.eventLoop.microtasks.enqueue(ctx, cast(JSValue) argv[0]);
    return JS_UNDEFINED();
}
