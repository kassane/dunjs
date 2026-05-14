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
        assert(engine !is null, "Null engine");
        this.engine = engine;
    }

    void run() @trusted
    {
        assert(engine !is null, "Event loop not initialized");
        running = true;
        while (running && hasWork())
            tick();
    }

    void tick() @trusted
    {
        assert(engine !is null, "Event loop not initialized");
        drainNextTicksAndMicrotasks();
        flushUnhandledRejections();

        timers.processExpired();

        drainNextTicksAndMicrotasks();

        {
            import dun.builtins.net : pollNetIO;
            import dun.builtins.http : pollHttpIO, dispatchHttpCallbacks;
            import dun.builtins.http2 : pollHttp2IO;
            import dun.builtins.ws : pollWsIO;
            import dun.loop.async : asyncDrain, asyncHasWork;
            pollNetIO();
            pollHttpIO();
            dispatchHttpCallbacks();
            pollHttp2IO();
            pollWsIO();

            if (asyncDrain() > 0)
                drainNextTicksAndMicrotasks();

            {
                import dun.workers.worker : pollWorkerMessages;
                pollWorkerMessages(engine);
            }

            {
                import dun.builtins.cluster : pollClusterWorkers;
                pollClusterWorkers();
            }

            // Drain pending POSIX signals (SIGTERM/SIGINT) and dispatch JS callbacks
            {
                import dun.runtime.signals : checkSignals, drainSignals;
                if (checkSignals())
                    drainSignals();
            }

            if (!engine.hasPendingJobs()
                && microtasks.empty()
                && nextTicks.empty()
                && !asyncHasWork()
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
        import dun.builtins.http2 : hasActiveHttp2IO;
        import dun.builtins.ws : hasActiveWsIO;
        import dun.builtins.cluster : hasActiveClusterWorkers;
        import dun.loop.agnostic_pending : hasAgnosticPending;
        import dun.loop.async : asyncHasWork;

        bool base = engine.hasPendingJobs()
            || !timers.empty()
            || !microtasks.empty()
            || !nextTicks.empty()
            || outstandingRefs > 0
            || hasActiveNetIO()
            || hasActiveHttpIO()
            || hasActiveHttp2IO()
            || hasActiveWsIO()
            || hasActiveClusterWorkers()
            || hasAgnosticPending()
            || asyncHasWork();

        version (EngineQuickJS)
        {
            import dun.loop.pending : hasPending;
            import dun.workers.worker : hasActiveWorkers;
            return base || hasPending() || hasActiveWorkers();
        }
        else
        {
            import dun.workers.worker : hasActiveWorkers;
            return base || hasActiveWorkers();
        }
    }

    void stop()
    {
        running = false;
    }

    void ref_()
    {
        assert(outstandingRefs >= 0, "Negative outstanding refs before increment");
        outstandingRefs++;
    }

    void unref()
    {
        assert(outstandingRefs > 0, "unref() called with no outstanding refs");
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

        import dun.runtime.process_api : hasUnhandledRejectionHandler,
            invokeUnhandledRejectionHandler;
        import dun.cli.errors : isColorEnabled, formatRejection;
        bool hasHandler = hasUnhandledRejectionHandler();
        bool color = isColorEnabled();
        foreach (ref entry; pending)
        {
            try
            {
                if (hasHandler)
                {
                    invokeUnhandledRejectionHandler(entry.engine,
                        entry.reason, entry.promise);
                }
                else
                {
                    string reason = entry.reasonStr.length > 0
                        ? entry.reasonStr : "<unknown>";
                    stderr.write(formatRejection(reason, color));
                    stderr.flush();
                }
            }
            catch (Exception) {}
            entry.engine.freeValue(entry.promise);
            entry.engine.freeValue(entry.reason);
        }
        exitCode = 1;
    }
}
