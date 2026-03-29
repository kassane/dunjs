/// Timer management for setTimeout/setInterval.
///
/// Uses a simple sorted array ordered by deadline.
/// Will be upgraded to a binary heap for production use.
module dun.loop.timers;

import core.time;
import dun.engine.bindings;

alias TimerID = uint;

/// A pending timer entry.
struct TimerEntry
{
    TimerID id;
    MonoTime deadline;
    Duration interval; // Duration.zero for one-shot (setTimeout)
    JSContext* ctx;
    JSValue callback; // Must be JS_DupValue'd
    bool cancelled;
}

/// Manages setTimeout/setInterval timers.
struct TimerWheel
{
    private TimerEntry[] entries;
    private TimerID nextId = 1;

    /// Add a new timer. Returns the timer ID.
    TimerID addTimer(JSContext* ctx, JSValue callback, Duration delay,
        Duration interval = Duration.zero) @trusted
    {
        auto id = nextId++;
        auto deadline = MonoTime.currTime + delay;

        entries ~= TimerEntry(
            id, deadline, interval, ctx,
            JS_DupValue(ctx, callback), // Take ownership
            false,
        );

        // Sort by deadline (simple approach; upgrade to heap later)
        import std.algorithm : sort;

        entries.sort!((a, b) => a.deadline < b.deadline);

        return id;
    }

    /// Cancel a timer by ID.
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

    /// Process and fire all expired timers.
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

            // Fire the callback
            auto ret = JS_Call(entry.ctx, entry.callback,
                JS_UNDEFINED(), 0, null);
            JS_FreeValue(entry.ctx, ret);

            // Re-insert if interval (setInterval)
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

        // Remove processed entries
        if (processed > 0)
        {
            entries = entries[processed .. $];
            import std.algorithm : sort;

            entries.sort!((a, b) => a.deadline < b.deadline);
        }
    }

    /// Get time until next timer fires.
    Duration nextDeadline() @trusted
    {
        if (entries.length == 0)
            return dur!"msecs"(100); // Default poll timeout

        auto now = MonoTime.currTime;
        auto diff = entries[0].deadline - now;
        if (diff < Duration.zero)
            return Duration.zero;
        return diff;
    }

    /// Check if there are any pending timers.
    bool empty() const @safe
    {
        return entries.length == 0;
    }
}
