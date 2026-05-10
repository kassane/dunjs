module dun.loop.eventloop;

import dun.engine.iface : IJSEngine;
import dun.loop.timers : TimerWheel;
import dun.loop.microtasks : MicrotaskQueue;

struct EventLoop
{
    TimerWheel timers;
    MicrotaskQueue microtasks;
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
        // Phase 1: Drain JS microtasks
        engine.drainJobs();
        microtasks.drain();

        // Phase 2: Fire expired timers
        timers.processExpired();

        // Phase 3: Drain microtasks from timers
        engine.drainJobs();
        microtasks.drain();

        // Phase 4: Poll I/O (eventcore integration — future)

        // Phase 5: Drain post-I/O microtasks
        engine.drainJobs();
        microtasks.drain();
    }

    bool hasWork() @trusted
    {
        return engine.hasPendingJobs() ||
            !timers.empty() ||
            !microtasks.empty() ||
            outstandingRefs > 0;
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
}
