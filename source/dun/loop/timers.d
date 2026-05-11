module dun.loop.timers;

import core.time;

alias TimerID = uint;

struct TimerWheel
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings;

        private TimerEntry[] entries;
        private TimerID nextId = 1;

        private struct TimerEntry
        {
            TimerID id;
            MonoTime deadline;
            Duration interval;
            JSContext* ctx;
            JSValue callback;
            bool cancelled;
        }

        TimerID addTimer(JSContext* ctx, JSValue callback, Duration delay,
            Duration interval = Duration.zero) nothrow @trusted
        {
            auto id = nextId++;
            auto deadline = MonoTime.currTime + delay;

            entries ~= TimerEntry(
                id, deadline, interval, ctx,
                JS_DupValue(ctx, callback),
                false,
            );

            sortEntries();
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
    else
    {
        void processExpired() @trusted {}

        Duration nextDeadline() @trusted
        {
            return dur!"msecs"(100);
        }

        bool empty() const @safe
        {
            return true;
        }
    }
}
