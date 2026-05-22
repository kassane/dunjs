module dun.loop.pending;


/// `@trusted policy`: QuickJS-specific pending-call queue. Every
/// `@trusted` is `engine.callFunction` / `engine.freeValue` /
/// `engine.dupValue` on cached function handles (engine-FFI surface).
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

// Head-indexed FIFO: `queue` only grows; `head` advances per pop. A
// previous version used `queue = queue[1 .. $]` which copies the tail
// each iteration -- O(N^2) drain on a burst of I/O callbacks.
// Matches the pattern used by NextTickQueue / MicrotaskQueue.
private PendingCall[] queue;
private size_t head;

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

bool hasPending() @safe nothrow { return head < queue.length; }

void drainPending() @trusted
{
    while (head < queue.length)
    {
        auto c = queue[head];
        head++;
        auto ret = JS_Call(c.ctx, c.func, JS_UNDEFINED(), c.argc, c.args.ptr);
        JS_FreeValue(c.ctx, ret);
        JS_FreeValue(c.ctx, c.func);
        foreach (i; 0 .. c.argc)
            JS_FreeValue(c.ctx, c.args[i]);
    }
    // Compact: once the queue has been fully drained, reset both
    // indices so the GC can collect the prior backing array.
    queue.length = 0;
    head = 0;
}
