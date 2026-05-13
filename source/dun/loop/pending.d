module dun.loop.pending;

// Thread-local queue for I/O callbacks that need to call into JS.
// I/O event callbacks (eventcore delegates) push here; the event loop
// drains after each processEvents call so JS is never invoked from
// inside a @safe nothrow eventcore callback.

version (EngineQuickJS):

import dun.engine.quickjs.bindings;

struct PendingCall
{
    JSContext* ctx;
    JSValue func;      // duped — freed after call
    JSValue[4] args;   // duped — freed after call
    int argc;
}

private PendingCall[] queue;

void pushPending(JSContext* ctx, JSValue func, JSValue[] args) nothrow @trusted
{
    if (args.length > 4) args = args[0 .. 4];
    PendingCall c;
    c.ctx  = ctx;
    c.func = JS_DupValue(ctx, func);
    c.argc = cast(int) args.length;
    foreach (i, a; args)
        c.args[i] = JS_DupValue(ctx, a);
    try { queue ~= c; }
    catch (Throwable) {}
}

bool hasPending() @safe nothrow { return queue.length > 0; }

void drainPending() @trusted
{
    while (queue.length > 0)
    {
        auto c = queue[0];
        queue = queue[1 .. $];
        auto ret = JS_Call(c.ctx, c.func, JS_UNDEFINED(), c.argc, c.args.ptr);
        JS_FreeValue(c.ctx, ret);
        JS_FreeValue(c.ctx, c.func);
        foreach (i; 0 .. c.argc)
            JS_FreeValue(c.ctx, c.args[i]);
    }
}
