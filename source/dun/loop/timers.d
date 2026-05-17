module dun.loop.timers;

import core.time;
import dun.engine.iface : IJSEngine, JSHandle;

alias TimerID = uint;

struct TimerWheel
{
    private TimerEntry[] entries;
    private TimerID nextId = 1;

    private struct TimerEntry
    {
        TimerID id;
        MonoTime deadline;
        Duration interval;
        IJSEngine engine;
        JSHandle callback;
        bool cancelled;
    }

    TimerID addTimer(IJSEngine engine, JSHandle callback, Duration delay,
        Duration interval = Duration.zero) nothrow @trusted
    {
        assert(engine !is null, "Null engine in addTimer");
        assert(nextId > 0, "TimerID overflow");
        auto id = nextId++;
        auto deadline = MonoTime.currTime + delay;

        try
        {
            entries ~= TimerEntry(
                id, deadline, interval, engine,
                engine.dupValue(callback),
                false,
            );
            sortEntries();
        }
        catch (Exception) {}

        return id;
    }

    void cancelTimer(TimerID id) nothrow @trusted
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
                entry.engine.freeValue(entry.callback);
                continue;
            }

            auto undef = entry.engine.newUndefined();
            auto ret = entry.engine.callFunction(entry.callback, undef, null);
            entry.engine.freeValue(ret);
            // On V8, `newUndefined` allocates a ref-counted DunV8Value;
            // QJS/JSC sentinel undefined values are no-ops in freeValue.
            // Either way, free it so we don't accumulate per timer tick.
            entry.engine.freeValue(undef);

            if (entry.interval != Duration.zero)
            {
                entry.deadline = now + entry.interval;
                entry.cancelled = false;
                try { entries ~= entry; }
                catch (Exception) {}
            }
            else
            {
                entry.engine.freeValue(entry.callback);
            }
        }

        if (processed > 0)
        {
            entries = entries[processed .. $];
            sortEntries();
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

    private void sortEntries() nothrow @trusted
    {
        for (size_t i = 1; i < entries.length; i++)
        {
            auto key = entries[i];
            long j = cast(long) i - 1;
            while (j >= 0 && entries[cast(size_t) j].deadline > key.deadline)
            {
                entries[cast(size_t)(j + 1)] = entries[cast(size_t) j];
                j--;
            }
            entries[cast(size_t)(j + 1)] = key;
        }
    }
}
