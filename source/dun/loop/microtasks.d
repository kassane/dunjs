module dun.loop.microtasks;

struct NextTickQueue
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings;

        private Entry[] queue;

        private struct Entry
        {
            JSContext* ctx;
            JSValue func;
        }

        void enqueue(JSContext* ctx, JSValue func) nothrow @trusted
        {
            try { queue ~= Entry(ctx, JS_DupValue(ctx, func)); }
            catch (Throwable) { JS_FreeValue(ctx, func); }
        }

        void drain() @trusted
        {
            // Node semantics: new nextTicks enqueued during drain run in the
            // same drain pass (can starve the loop — intentional).
            while (queue.length > 0)
            {
                auto entry = queue[0];
                queue = queue[1 .. $];
                auto ret = JS_Call(entry.ctx, entry.func, JS_UNDEFINED(), 0, null);
                JS_FreeValue(entry.ctx, ret);
                JS_FreeValue(entry.ctx, entry.func);
            }
        }

        bool empty() const @safe { return queue.length == 0; }
    }
    else
    {
        void drain() @trusted {}
        bool empty() const @safe { return true; }
    }
}

struct MicrotaskQueue
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings;

        private Entry[] queue;

        private struct Entry
        {
            JSContext* ctx;
            JSValue func;
        }

        void enqueue(JSContext* ctx, JSValue func) nothrow @trusted
        {
            try { queue ~= Entry(ctx, JS_DupValue(ctx, func)); }
            catch (Throwable) { JS_FreeValue(ctx, func); }
        }

        void drain() @trusted
        {
            while (queue.length > 0)
            {
                auto entry = queue[0];
                queue = queue[1 .. $];

                auto ret = JS_Call(entry.ctx, entry.func,
                    JS_UNDEFINED(), 0, null);
                JS_FreeValue(entry.ctx, ret);
                JS_FreeValue(entry.ctx, entry.func);
            }
        }

        bool empty() const @safe
        {
            return queue.length == 0;
        }
    }
    else
    {
        void drain() @trusted {}

        bool empty() const @safe
        {
            return true;
        }
    }
}
