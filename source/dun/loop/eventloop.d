module dun.loop.eventloop;


/++
 + `@trusted policy`: main event loop tick (microtasks → timers →
 + I/O poll → async drain → microtasks). Every `@trusted` is one
 + of:
 +   1. `core.thread.Thread.sleep` for the idle wait when there's
 +      pending work but no expired timer.
 +   2. Engine method calls (`drainJobs`, `executePendingJob`) —
 +      `@trusted`-by-interface (see engine/iface.d policy).
 +   3. `cast(void*) state` for handing the DunState to engine ctx.
 +/
import core.time : dur;
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
            import dun.builtins.net : pollNetIO, hasActiveNetIO;
            import dun.builtins.http : pollHttpIO, dispatchHttpCallbacks, hasActiveHttpIO;
            import dun.builtins.http2 : pollHttp2IO, hasActiveHttp2IO;
            import dun.builtins.ws : pollWsIO, hasActiveWsIO;
            import dun.loop.async : asyncDrain, asyncHasWork;
            import dun.napi.napi : napiDrainAsyncWork, napiHasAsyncWork,
                                    napiDrainThreadsafeCalls, napiHasThreadsafeCalls;

            // Only poll subsystems that have active I/O — skip idle ones
            bool anyIO = false;
            if (hasActiveNetIO()) { pollNetIO(); anyIO = true; }
            if (hasActiveHttpIO()) { pollHttpIO(); dispatchHttpCallbacks(); anyIO = true; }
            else { dispatchHttpCallbacks(); } // still dispatch any queued callbacks
            if (hasActiveHttp2IO()) { pollHttp2IO(); anyIO = true; }
            if (hasActiveWsIO()) { pollWsIO(); anyIO = true; }

            version (Posix)
            {
                import dun.builtins.tls : pollTlsIO, hasActiveTlsIO;
                if (hasActiveTlsIO()) { pollTlsIO(); anyIO = true; }
            }

            if (asyncDrain() > 0)
                drainNextTicksAndMicrotasks();
            if (napiDrainAsyncWork() > 0)
                drainNextTicksAndMicrotasks();
            if (napiDrainThreadsafeCalls() > 0)
                drainNextTicksAndMicrotasks();

            {
                import dun.workers.worker : pollWorkerMessages;
                pollWorkerMessages(engine);
            }

            {
                import dun.builtins.cluster : pollClusterWorkers;
                pollClusterWorkers();
            }

            {
                import dun.runtime.signals : checkSignals, drainSignals;
                if (checkSignals())
                    drainSignals();
            }

            if (!engine.hasPendingJobs()
                && microtasks.empty()
                && nextTicks.empty()
                && !asyncHasWork()
                && !napiHasAsyncWork()
                && !napiHasThreadsafeCalls()
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
        import dun.napi.napi : napiHasAsyncWork, napiHasThreadsafeCalls;

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
            || asyncHasWork()
            || napiHasAsyncWork()
            || napiHasThreadsafeCalls();

        version (Posix)
        {
            import dun.builtins.tls : hasActiveTlsIO;
            base = base || hasActiveTlsIO();
        }

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
