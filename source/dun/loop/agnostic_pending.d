module dun.loop.agnostic_pending;

import dun.engine.iface : IJSEngine, JSHandle;

struct AgnosticPendingCall
{
    IJSEngine engine;
    JSHandle func;
    JSHandle[4] args;
    int argc;
}

private AgnosticPendingCall[] agQueue;

void pushAgnosticPending(IJSEngine engine, JSHandle func, JSHandle[] args) nothrow @trusted
{
    if (args.length > 4) args = args[0 .. 4];
    AgnosticPendingCall c;
    c.engine = engine;
    try { c.func = engine.dupValue(func); } catch (Throwable) { return; }
    c.argc = cast(int) args.length;
    foreach (i, a; args)
    {
        try { c.args[i] = engine.dupValue(a); } catch (Throwable) {}
    }
    try { agQueue ~= c; }
    catch (Throwable) {}
}

bool hasAgnosticPending() @safe nothrow { return agQueue.length > 0; }

void drainAgnosticPending() @trusted
{
    while (agQueue.length > 0)
    {
        auto c = agQueue[0];
        agQueue = agQueue[1 .. $];
        auto engine = c.engine;
        try
        {
            auto argSlice = c.args[0 .. c.argc];
            auto ret = engine.callFunction(c.func, engine.newUndefined(), argSlice.dup);
            engine.freeValue(ret);
        }
        catch (Exception) {}
        try { engine.freeValue(c.func); } catch (Throwable) {}
        foreach (i; 0 .. c.argc)
        {
            try { engine.freeValue(c.args[i]); } catch (Throwable) {}
        }
    }
}
