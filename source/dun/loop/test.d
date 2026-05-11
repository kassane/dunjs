module dun.loop.test;

version (DunTest):

import dun.engine.iface;
import dun.engine.test : Test, Describe, EngineTestRunner, runModuleTests;

@Describe("event loop")
@Test("nextTick drains before queueMicrotask")
void testNextTickBeforeMicrotask(IJSEngine engine)
{
    import dun.loop.eventloop : EventLoop;

    auto orderPtr = new string[][1];

    static JSHandle tickCb(void* ctx, JSHandle thisVal, JSHandle[] args)
    {
        auto p = cast(string[]*) ctx;
        try { (*p) ~= "nextTick"; } catch (Throwable) {}
        return JSHandle.init;
    }

    static JSHandle microtaskCb(void* ctx, JSHandle thisVal, JSHandle[] args)
    {
        auto p = cast(string[]*) ctx;
        try { (*p) ~= "microtask"; } catch (Throwable) {}
        return JSHandle.init;
    }

    engine.setContextOpaque(cast(void*) &orderPtr[0]);

    EventLoop loop;
    loop.initialize(engine);

    auto tickFn = engine.newFunction(&tickCb, "t", 0);
    auto mtFn = engine.newFunction(&microtaskCb, "m", 0);

    loop.nextTicks.enqueue(engine, tickFn);
    loop.microtasks.enqueue(engine, mtFn);

    engine.freeValue(tickFn);
    engine.freeValue(mtFn);

    while (loop.hasWork())
        loop.tick();

    auto order = orderPtr[0];
    assert(order.length == 2);
    assert(order[0] == "nextTick", "nextTick must fire first, got: " ~ order[0]);
    assert(order[1] == "microtask", "microtask must fire second, got: " ~ order[1]);
}

mixin EngineTestRunner!("EventLoop Tests", dun.loop.test);
