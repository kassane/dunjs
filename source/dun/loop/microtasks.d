module dun.loop.microtasks;

import dun.engine.iface : IJSEngine, JSHandle;

struct NextTickQueue
{
    private Entry[] queue;

    private struct Entry
    {
        IJSEngine engine;
        JSHandle func;
    }

    void enqueue(IJSEngine engine, JSHandle func) nothrow @trusted
    {
        try { queue ~= Entry(engine, engine.dupValue(func)); }
        catch (Exception) {}
    }

    void drain() @trusted
    {
        while (queue.length > 0)
        {
            auto entry = queue[0];
            queue = queue[1 .. $];
            auto undef = entry.engine.newUndefined();
            auto ret = entry.engine.callFunction(entry.func, undef, null);
            entry.engine.freeValue(ret);
            entry.engine.freeValue(entry.func);
        }
    }

    bool empty() const @safe { return queue.length == 0; }
}

struct MicrotaskQueue
{
    private Entry[] queue;

    private struct Entry
    {
        IJSEngine engine;
        JSHandle func;
    }

    void enqueue(IJSEngine engine, JSHandle func) nothrow @trusted
    {
        try { queue ~= Entry(engine, engine.dupValue(func)); }
        catch (Exception) {}
    }

    void drain() @trusted
    {
        while (queue.length > 0)
        {
            auto entry = queue[0];
            queue = queue[1 .. $];
            auto undef = entry.engine.newUndefined();
            auto ret = entry.engine.callFunction(entry.func, undef, null);
            entry.engine.freeValue(ret);
            entry.engine.freeValue(entry.func);
        }
    }

    bool empty() const @safe
    {
        return queue.length == 0;
    }
}
