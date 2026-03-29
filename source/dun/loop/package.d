/// Layer 3: Event loop and async runtime.
///
/// Integrates eventcore I/O polling with QuickJS Promise job queue,
/// timer wheel, and microtask queue.
module dun.loop;

public import dun.loop.eventloop;
public import dun.loop.timers;
public import dun.loop.microtasks;
