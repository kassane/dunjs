/// Microtask queue for queueMicrotask() support.
///
/// FIFO queue of JS callbacks that run before the next I/O poll,
/// complementing QuickJS's built-in Promise job queue.
module dun.loop.microtasks;

import dun.engine.bindings;

/// FIFO queue of microtasks.
struct MicrotaskQueue
{
    private Entry[] queue;

    private struct Entry
    {
        JSContext* ctx;
        JSValue func;
    }

    /// Enqueue a microtask. DupValue is called to own the callback.
    void enqueue(JSContext* ctx, JSValue func) @trusted
    {
        queue ~= Entry(ctx, JS_DupValue(ctx, func));
    }

    /// Drain all microtasks, executing each callback.
    void drain() @trusted
    {
        while (queue.length > 0)
        {
            auto entry = queue[0];
            queue = queue[1 .. $];

            auto ret = JS_Call(entry.ctx, entry.func,
                JS_UNDEFINED(), 0, null);
            JS_FreeValue(entry.ctx, ret);
            JS_FreeValue(entry.ctx, entry.func);
        }
    }

    /// Check if the queue is empty.
    bool empty() const @safe
    {
        return queue.length == 0;
    }
}
