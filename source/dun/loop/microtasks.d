module dun.loop.microtasks;

import dun.engine.quickjs.bindings;

struct MicrotaskQueue
{
    private Entry[] queue;

    private struct Entry
    {
        JSContext* ctx;
        JSValue func;
    }

    void enqueue(JSContext* ctx, JSValue func) @trusted
    {
        queue ~= Entry(ctx, JS_DupValue(ctx, func));
    }

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

    bool empty() const @safe
    {
        return queue.length == 0;
    }
}
