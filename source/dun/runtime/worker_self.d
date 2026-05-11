module dun.runtime.worker_self;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.runtime.globals : DunState;
import dun.workers.worker : WorkerState;

void installWorkerSelf(JSContext* ctx, DunState* state, WorkerState wst) @trusted
{
    import std.format : format;

    auto selfObj = JS_NewObject(ctx);

    // Store wst pointer as a hex string property so callbacks can retrieve it
    auto ptrStr = format!"%x"(cast(size_t) cast(void*) wst);
    JS_SetPropertyStr(ctx, selfObj, "__wsp__",
        JS_NewStringLen(ctx, ptrStr.ptr, ptrStr.length));

    auto postMsg = JS_NewCFunction(ctx, &_selfPostMessage, "postMessage", 1);
    JS_SetPropertyStr(ctx, selfObj, "postMessage", postMsg);

    auto closeFn = JS_NewCFunction(ctx, &_selfClose, "close", 0);
    JS_SetPropertyStr(ctx, selfObj, "close", closeFn);

    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "self", selfObj);
    JS_FreeValue(ctx, global);
}

private WorkerState _getWst(JSContext* ctx) nothrow @system
{
    auto global = JS_GetGlobalObject(ctx);
    auto selfObj = JS_GetPropertyStr(ctx, global, "self");
    JS_FreeValue(ctx, global);
    auto wspVal = JS_GetPropertyStr(ctx, selfObj, "__wsp__");
    JS_FreeValue(ctx, selfObj);

    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, wspVal, false);
    JS_FreeValue(ctx, wspVal);
    if (!cstr)
        return null;

    import core.stdc.stdlib : strtoul;
    size_t ptrVal = cast(size_t) strtoul(cstr, null, 16);
    JS_FreeCString(ctx, cstr);
    return cast(WorkerState) cast(void*) ptrVal;
}

private extern (C) JSValue _selfPostMessage(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow @system
{
    if (argc < 1)
        return JS_UNDEFINED();

    auto wst = _getWst(ctx);
    if (!wst)
        return JS_UNDEFINED();

    auto jsonStr = JS_JSONStringify(ctx, argv[0], JS_UNDEFINED(), JS_UNDEFINED());
    if (JS_IsException(jsonStr))
        return JS_UNDEFINED();
    scope (exit) JS_FreeValue(ctx, jsonStr);

    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, jsonStr, false);
    if (!cstr)
        return JS_UNDEFINED();
    scope (exit) JS_FreeCString(ctx, cstr);

    try { wst.fromWorker.send(cstr[0 .. len].idup); }
    catch (Throwable) {}

    return JS_UNDEFINED();
}

private extern (C) JSValue _selfClose(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow @system
{
    auto wst = _getWst(ctx);
    if (wst)
        try { wst.toWorker.close(); wst.fromWorker.close(); }
        catch (Throwable) {}
    return JS_UNDEFINED();
}
