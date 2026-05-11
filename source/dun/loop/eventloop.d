module dun.loop.eventloop;

import core.time : Duration, dur;
import dun.engine.iface : IJSEngine, JSHandle;
import dun.loop.timers : TimerWheel;
import dun.loop.microtasks : MicrotaskQueue, NextTickQueue;

struct RejectedPromise
{
    IJSEngine engine;
    JSHandle promise;
    JSHandle reason;
    string reasonStr;
}

struct EventLoop
{
    TimerWheel timers;
    MicrotaskQueue microtasks;
    NextTickQueue nextTicks;
    int exitCode;

    RejectedPromise[] unhandledRejections;

    private IJSEngine engine;
    private bool running;
    private int outstandingRefs;

    void initialize(IJSEngine engine) @trusted
    {
        this.engine = engine;
    }

    void run() @trusted
    {
        running = true;
        while (running && hasWork())
            tick();
    }

    void tick() @trusted
    {
        drainNextTicksAndMicrotasks();
        flushUnhandledRejections();

        timers.processExpired();

        drainNextTicksAndMicrotasks();

        {
            import dun.builtins.net : pollNetIO;
            import dun.builtins.http : pollHttpIO;
            pollNetIO();
            pollHttpIO();

            version (EngineQuickJS)
            {
                import dun.workers.worker : pollWorkerMessages;
                import dun.engine.quickjs.bindings : JSContext;
                pollWorkerMessages(cast(JSContext*) engine.rawContext());
            }

            if (!engine.hasPendingJobs()
                && microtasks.empty()
                && nextTicks.empty()
                && !timers.empty())
            {
                auto wait = timers.nextDeadline();
                if (wait > dur!"msecs"(0))
                {
                    import core.thread : Thread;
                    if (wait > dur!"msecs"(10))
                        wait = dur!"msecs"(10);
                    Thread.sleep(wait);
                }
            }
        }

        version (EngineQuickJS)
        {
            import dun.loop.pending : drainPending;
            drainPending();
        }

        import dun.loop.agnostic_pending : drainAgnosticPending;
        drainAgnosticPending();

        drainNextTicksAndMicrotasks();
    }

    bool hasWork() @trusted
    {
        import dun.builtins.net : hasActiveNetIO;
        import dun.builtins.http : hasActiveHttpIO;
        import dun.loop.agnostic_pending : hasAgnosticPending;

        bool base = engine.hasPendingJobs()
            || !timers.empty()
            || !microtasks.empty()
            || !nextTicks.empty()
            || outstandingRefs > 0
            || hasActiveNetIO()
            || hasActiveHttpIO()
            || hasAgnosticPending();

        version (EngineQuickJS)
        {
            import dun.loop.pending : hasPending;
            import dun.workers.worker : hasActiveWorkers;
            return base || hasPending() || hasActiveWorkers();
        }
        else
        {
            return base;
        }
    }

    void stop()
    {
        running = false;
    }

    void ref_()
    {
        outstandingRefs++;
    }

    void unref()
    {
        if (outstandingRefs > 0)
            outstandingRefs--;
    }

    void drainMicrotasks() @trusted { drainNextTicksAndMicrotasks(); }

    private void drainNextTicksAndMicrotasks() @trusted
    {
        do {
            nextTicks.drain();
            engine.drainJobs();
            microtasks.drain();
        } while (!nextTicks.empty() || engine.hasPendingJobs() || !microtasks.empty());
    }

    public void flushUnhandledRejections() @trusted
    {
        if (unhandledRejections.length == 0) return;
        import std.stdio : stderr;

        auto pending = unhandledRejections;
        unhandledRejections = null;

        import dun.cli.errors : isColorEnabled, formatRejection;
        bool color = isColorEnabled();
        foreach (ref entry; pending)
        {
            try
            {
                string reason = entry.reasonStr.length > 0
                    ? entry.reasonStr : "<unknown>";
                stderr.write(formatRejection(reason, color));
                stderr.flush();
            }
            catch (Exception) {}
            entry.engine.freeValue(entry.promise);
            entry.engine.freeValue(entry.reason);
        }
        exitCode = 1;
    }
}
