module dun.loop.eventloop;

import core.time : Duration, dur;
import dun.engine.iface : IJSEngine;
import dun.loop.timers : TimerWheel;
import dun.loop.microtasks : MicrotaskQueue, NextTickQueue;

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings :
        JSContext, JSValue, JS_ToCStringLen2, JS_HasException,
        JS_GetException, JS_FreeValue, JS_FreeCString, JS_IsSameValue;

    struct RejectedPromise
    {
        JSContext* ctx;
        JSValue promise;
        JSValue reason;
    }
}

struct EventLoop
{
    TimerWheel timers;
    MicrotaskQueue microtasks;
    NextTickQueue nextTicks;
    int exitCode;

    version (EngineQuickJS)
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
            version (EngineQuickJS)
            {
                import dun.builtins.net : pollNetIO;
                import dun.builtins.http : pollHttpIO;
                import dun.workers.worker : pollWorkerMessages;
                pollNetIO();
                pollHttpIO();
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
        drainNextTicksAndMicrotasks();
    }

    bool hasWork() @trusted
    {
        version (EngineQuickJS)
        {
            import dun.builtins.net : hasActiveNetIO;
            import dun.builtins.http : hasActiveHttpIO;
            import dun.loop.pending : hasPending;
            import dun.workers.worker : hasActiveWorkers;
            return engine.hasPendingJobs()
                || !timers.empty()
                || !microtasks.empty()
                || !nextTicks.empty()
                || outstandingRefs > 0
                || hasActiveNetIO()
                || hasActiveHttpIO()
                || hasPending()
                || hasActiveWorkers();
        }
        else
        {
            return engine.hasPendingJobs()
                || !timers.empty()
                || !microtasks.empty()
                || !nextTicks.empty()
                || outstandingRefs > 0;
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
        version (EngineQuickJS)
        {
            if (unhandledRejections.length == 0) return;
            import std.stdio : stderr;

            auto pending = unhandledRejections;
            unhandledRejections = null;

            import dun.cli.errors : isColorEnabled, formatRejection;
            bool color = isColorEnabled();
            foreach (ref entry; pending)
            {
                size_t cstr_len;
                const(char)* cstr =
                    JS_ToCStringLen2(entry.ctx, &cstr_len, entry.reason, false);
                if (JS_HasException(entry.ctx))
                {
                    auto exc = JS_GetException(entry.ctx);
                    JS_FreeValue(entry.ctx, exc);
                }
                try
                {
                    string reason = cstr ? cstr[0 .. cstr_len].idup : "<unknown>";
                    stderr.write(formatRejection(reason, color));
                    stderr.flush();
                }
                catch (Exception) {}
                if (cstr) JS_FreeCString(entry.ctx, cstr);
                JS_FreeValue(entry.ctx, entry.promise);
                JS_FreeValue(entry.ctx, entry.reason);
            }
            exitCode = 1;
        }
    }
}
