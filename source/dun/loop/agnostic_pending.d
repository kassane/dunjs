module dun.loop.agnostic_pending;


/// `@trusted policy`: engine-agnostic pending-call queue (used by
/// HTTP/WS/net to schedule JS callbacks from D worker threads).
/// Every `@trusted` is `engine.dupValue` / `engine.callFunction` /
/// `engine.freeValue` — engine-FFI surface.
import dun.engine.iface : IJSEngine, JSHandle;

private enum MAX_PENDING_ARGS = 4;

struct AgnosticPendingCall
{
    IJSEngine engine;
    JSHandle func;
    JSHandle[MAX_PENDING_ARGS] args;
    int argc;
}

private AgnosticPendingCall[] agQueue;

void pushAgnosticPending(IJSEngine engine, JSHandle func, JSHandle[] args) nothrow @trusted
{
    if (args.length > MAX_PENDING_ARGS) args = args[0 .. MAX_PENDING_ARGS];
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
            // Use stack buffer to avoid GC allocation from .dup
            JSHandle[MAX_PENDING_ARGS] argBuf = c.args;
            auto ret = engine.callFunction(c.func, engine.newUndefined(), argBuf[0 .. c.argc]);
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
