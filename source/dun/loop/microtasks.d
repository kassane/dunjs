module dun.loop.microtasks;

import dun.engine.iface : IJSEngine, JSHandle;

struct NextTickQueue
{
    private Entry[] queue;
    private size_t head;

    private struct Entry
    {
        IJSEngine engine;
        JSHandle func;
    }

    void enqueue(IJSEngine engine, JSHandle func) nothrow @trusted
    {
        assert(engine !is null, "Null engine in NextTickQueue.enqueue");
        try { queue ~= Entry(engine, engine.dupValue(func)); }
        catch (Exception) {}
    }

    void drain() @trusted
    {
        while (head < queue.length)
        {
            auto entry = queue[head];
            head++;
            auto undef = entry.engine.newUndefined();
            auto ret = entry.engine.callFunction(entry.func, undef, null);
            entry.engine.freeValue(ret);
            entry.engine.freeValue(undef);
            entry.engine.freeValue(entry.func);
        }
        queue.length = 0;
        queue.assumeSafeAppend();
        head = 0;
    }

    bool empty() const @safe { return head >= queue.length; }
}

struct MicrotaskQueue
{
    private Entry[] queue;
    private size_t head;

    private struct Entry
    {
        IJSEngine engine;
        JSHandle func;
    }

    void enqueue(IJSEngine engine, JSHandle func) nothrow @trusted
    {
        assert(engine !is null, "Null engine in MicrotaskQueue.enqueue");
        try { queue ~= Entry(engine, engine.dupValue(func)); }
        catch (Exception) {}
    }

    void drain() @trusted
    {
        while (head < queue.length)
        {
            auto entry = queue[head];
            head++;
            auto undef = entry.engine.newUndefined();
            auto ret = entry.engine.callFunction(entry.func, undef, null);
            entry.engine.freeValue(ret);
            entry.engine.freeValue(undef);
            entry.engine.freeValue(entry.func);
        }
        queue.length = 0;
        queue.assumeSafeAppend();
        head = 0;
    }

    bool empty() const @safe
    {
        return head >= queue.length;
    }
}
