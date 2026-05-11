module dun.runtime.globals;

import dun.engine.iface : IJSEngine;
import dun.loop.eventloop : EventLoop;
import dun.security.permissions : PermissionRegistry;

struct DunState
{
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}

void installGlobals(IJSEngine engine, DunState* state) @trusted
{
    engine.setContextOpaque(cast(void*) state);

    version (EngineQuickJS)
    {
        import dun.runtime.console : installConsole;
        installConsole(engine);
    }
    else version (EngineV8)
    {
        installV8Console(engine);
    }
}

version (EngineV8)
{
    import dun.engine.v8.bindings;
    import dun.engine.v8.backend : V8Engine;

    private void installV8Console(IJSEngine engine) @trusted
    {
        auto v8 = cast(V8Engine) engine;
        auto ctx = cast(DunV8Context*) engine.rawContext();

        auto console = dun_v8_new_object(ctx);
        auto global = dun_v8_global(ctx);

        dun_v8_set_property(ctx, console, "log",
            dun_v8_new_function(ctx, &v8ConsoleLog, "log", null));
        dun_v8_set_property(ctx, console, "info",
            dun_v8_new_function(ctx, &v8ConsoleLog, "info", null));
        dun_v8_set_property(ctx, console, "debug",
            dun_v8_new_function(ctx, &v8ConsoleLog, "debug", null));
        dun_v8_set_property(ctx, console, "warn",
            dun_v8_new_function(ctx, &v8ConsoleWarn, "warn", null));
        dun_v8_set_property(ctx, console, "error",
            dun_v8_new_function(ctx, &v8ConsoleError, "error", null));

        dun_v8_set_property(ctx, global, "console", console);
        dun_v8_value_unref(global);
        dun_v8_value_unref(console);
    }

    private extern (C) DunV8Value* v8ConsoleLog(DunV8Context* ctx,
        DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow
    {
        v8WriteArgs(ctx, argc, argv, false);
        return dun_v8_new_undefined(ctx);
    }

    private extern (C) DunV8Value* v8ConsoleWarn(DunV8Context* ctx,
        DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow
    {
        v8WriteArgs(ctx, argc, argv, true);
        return dun_v8_new_undefined(ctx);
    }

    private extern (C) DunV8Value* v8ConsoleError(DunV8Context* ctx,
        DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow
    {
        v8WriteArgs(ctx, argc, argv, true);
        return dun_v8_new_undefined(ctx);
    }

    private void v8WriteArgs(DunV8Context* ctx, int argc,
        DunV8Value** argv, bool useStderr) nothrow @trusted
    {
        try
        {
            import std.stdio : stdout, stderr, write, writeln;
            auto output = useStderr ? stderr : stdout;

            for (int i = 0; i < argc; i++)
            {
                if (i > 0)
                    output.write(' ');

                size_t len;
                auto cstr = dun_v8_value_to_string(ctx, argv[i], &len);
                if (cstr !is null)
                {
                    output.write(cstr[0 .. len]);
                    dun_v8_free_string(cstr);
                }
            }
            output.writeln();
            output.flush();
        }
        catch (Exception) {}
    }
}
