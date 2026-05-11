module dun.loop.test;

version (DunTest):

import dun.engine.iface;
import dun.engine.test : Test, Describe, EngineTestRunner, runModuleTests;

// ---------------------------------------------------------------------------
// EventLoop ordering tests
// ---------------------------------------------------------------------------

@Describe("event loop")
@Test("nextTick drains before queueMicrotask")
void testNextTickBeforeMicrotask(IJSEngine engine)
{
    version (EngineQuickJS)
    {
        import dun.loop.eventloop : EventLoop;
        import dun.engine.quickjs.bindings;

        string[] order;

        static extern (C) JSValue tickCb(JSContext* ctx,
            JSValueConst, int, JSValueConst*) nothrow @trusted
        {
            auto p = cast(string[]*) JS_GetContextOpaque(ctx);
            try { (*p) ~= "nextTick"; } catch (Throwable) {}
            return JS_UNDEFINED();
        }

        static extern (C) JSValue microtaskCb(JSContext* ctx,
            JSValueConst, int, JSValueConst*) nothrow @trusted
        {
            auto p = cast(string[]*) JS_GetContextOpaque(ctx);
            try { (*p) ~= "microtask"; } catch (Throwable) {}
            return JS_UNDEFINED();
        }

        engine.setContextOpaque(cast(void*) &order);
        auto rawCtx = cast(JSContext*) engine.rawContext();

        EventLoop loop;
        loop.initialize(engine);

        auto tickFn = JS_NewCFunction(rawCtx, &tickCb, "t", 0);
        auto mtFn   = JS_NewCFunction(rawCtx, &microtaskCb, "m", 0);

        loop.nextTicks.enqueue(rawCtx, tickFn);
        loop.microtasks.enqueue(rawCtx, mtFn);

        JS_FreeValue(rawCtx, tickFn);
        JS_FreeValue(rawCtx, mtFn);

        while (loop.hasWork())
            loop.tick();

        assert(order.length == 2);
        assert(order[0] == "nextTick",  "nextTick must fire first, got: " ~ order[0]);
        assert(order[1] == "microtask", "microtask must fire second, got: " ~ order[1]);
    }
}

// Per-backend instantiation
mixin EngineTestRunner!("EventLoop Tests", dun.loop.test);
