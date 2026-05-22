module dun.loop.microtasks;


/// `@trusted policy`: microtask queue drain. Every `@trusted` is
/// engine method calls (callFunction, freeValue) — engine-FFI
/// surface; see `engine/iface.d` policy header.
import dun.engine.iface : IJSEngine, JSHandle;

/// FIFO queue of pinned JS callbacks invoked with `undefined` receiver
/// and no args. Both `NextTickQueue` (process.nextTick) and
/// `MicrotaskQueue` (Promise jobs / queueMicrotask) share the exact
/// same enqueue+drain semantics — the difference is purely in WHO
/// drains them and WHEN, not in the queue mechanics. The dual-struct
/// pattern (two identical copies) was a jscpd-flagged ~30-line clone
/// before the dedup; both names are kept as distinct types so a misuse
/// like `nextTickQueue.drain()` inside a microtask-drain context still
/// type-checks at the call site.
private struct JsCallbackQueueImpl(string Tag)
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
        assert(engine !is null, "Null engine in " ~ Tag ~ ".enqueue");
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

alias NextTickQueue   = JsCallbackQueueImpl!"NextTickQueue";
alias MicrotaskQueue  = JsCallbackQueueImpl!"MicrotaskQueue";
