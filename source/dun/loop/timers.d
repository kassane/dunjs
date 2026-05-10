module dun.loop.timers;

import core.time;
import dun.engine.quickjs.bindings;

alias TimerID = uint;

struct TimerEntry
{
    TimerID id;
    MonoTime deadline;
    Duration interval;
    JSContext* ctx;
    JSValue callback;
    bool cancelled;
}

struct TimerWheel
{
    private TimerEntry[] entries;
    private TimerID nextId = 1;

    TimerID addTimer(JSContext* ctx, JSValue callback, Duration delay,
        Duration interval = Duration.zero) @trusted
    {
        auto id = nextId++;
        auto deadline = MonoTime.currTime + delay;

        entries ~= TimerEntry(
            id, deadline, interval, ctx,
            JS_DupValue(ctx, callback),
            false,
        );

        import std.algorithm : sort;
        entries.sort!((a, b) => a.deadline < b.deadline);

        return id;
    }

    void cancelTimer(TimerID id) @trusted
    {
        foreach (ref entry; entries)
        {
            if (entry.id == id)
            {
                entry.cancelled = true;
                break;
            }
        }
    }

    void processExpired() @trusted
    {
        auto now = MonoTime.currTime;
        size_t processed = 0;

        while (processed < entries.length && entries[processed].deadline <= now)
        {
            auto entry = entries[processed];
            processed++;

            if (entry.cancelled)
            {
                JS_FreeValue(entry.ctx, entry.callback);
                continue;
            }

            auto ret = JS_Call(entry.ctx, entry.callback,
                JS_UNDEFINED(), 0, null);
            JS_FreeValue(entry.ctx, ret);

            if (entry.interval != Duration.zero)
            {
                entry.deadline = now + entry.interval;
                entry.cancelled = false;
                entries ~= entry;
            }
            else
            {
                JS_FreeValue(entry.ctx, entry.callback);
            }
        }

        if (processed > 0)
        {
            entries = entries[processed .. $];
            import std.algorithm : sort;
            entries.sort!((a, b) => a.deadline < b.deadline);
        }
    }

    Duration nextDeadline() @trusted
    {
        if (entries.length == 0)
            return dur!"msecs"(100);

        auto now = MonoTime.currTime;
        auto diff = entries[0].deadline - now;
        if (diff < Duration.zero)
            return Duration.zero;
        return diff;
    }

    bool empty() const @safe
    {
        return entries.length == 0;
    }
}
