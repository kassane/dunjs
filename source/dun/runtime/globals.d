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
        import dun.runtime.timers_api : installTimers;
        import dun.runtime.microtask_api : installMicrotask;
        import dun.runtime.process_api : installProcess;
        import dun.runtime.rejection_tracker : installRejectionTracker;
        import dun.builtins.fs : registerFsModule;
        import dun.builtins.path : registerPathModule;
        import dun.builtins.crypto : registerCryptoModule;
        import dun.builtins.net : registerNetModule;
        import dun.builtins.http : registerHttpModule;
        import dun.modules.require : installRequire;
        import dun.engine.quickjs.bindings : JSContext, JS_GetRuntime;
        auto ctx = cast(JSContext*) engine.rawContext();
        installConsole(engine);
        installTimers(ctx, state);
        installMicrotask(ctx);
        installProcess(ctx);
        installRejectionTracker(JS_GetRuntime(ctx), state);
        registerFsModule(ctx);
        registerPathModule(ctx);
        registerCryptoModule(ctx);
        registerNetModule(ctx);
        registerHttpModule(ctx);
        installRequire(ctx);
    }
    else version (EngineJSC)
    {
        installJSCConsole(engine);
    }
    else version (EngineV8)
    {
        installV8Console(engine);
    }
}

version (EngineJSC)
{
    import dun.engine.jsc.bindings;
    import dun.engine.jsc.backend : JSCEngine;

    private void installJSCConsole(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSGlobalContextRef) engine.rawContext();
        auto global = JSContextGetGlobalObject(ctx);

        auto console = JSObjectMake(ctx, null, null);

        setJSCFunction(ctx, console, "log", &jscConsoleLog);
        setJSCFunction(ctx, console, "info", &jscConsoleLog);
        setJSCFunction(ctx, console, "debug", &jscConsoleLog);
        setJSCFunction(ctx, console, "warn", &jscConsoleWarn);
        setJSCFunction(ctx, console, "error", &jscConsoleError);
        setJSCFunction(ctx, console, "assert", &jscConsoleAssert);

        auto consoleName = JSStringCreateWithUTF8CString("console");
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, global, consoleName,
            cast(JSValueRef) console, kJSPropertyAttributeNone, &exc);
        JSStringRelease(consoleName);
    }

    private void setJSCFunction(JSGlobalContextRef ctx, JSObjectRef parent,
        const(char)* name, JSObjectCallAsFunctionCallback cb) @trusted
    {
        auto jsName = JSStringCreateWithUTF8CString(name);
        auto fn = JSObjectMakeFunctionWithCallback(ctx, jsName, cb);
        JSValueRef exc = null;
        JSObjectSetProperty(ctx, parent, jsName,
            cast(JSValueRef) fn, kJSPropertyAttributeNone, &exc);
        JSStringRelease(jsName);
    }

    private extern (C) JSValueRef jscConsoleLog(JSContextRef ctx,
        JSObjectRef func, JSObjectRef thisObject,
        size_t argumentCount, const(JSValueRef)* arguments,
        JSValueRef* exception) nothrow
    {
        jscWriteArgs(ctx, argumentCount, arguments, false);
        return JSValueMakeUndefined(ctx);
    }

    private extern (C) JSValueRef jscConsoleWarn(JSContextRef ctx,
        JSObjectRef func, JSObjectRef thisObject,
        size_t argumentCount, const(JSValueRef)* arguments,
        JSValueRef* exception) nothrow
    {
        jscWriteArgs(ctx, argumentCount, arguments, true);
        return JSValueMakeUndefined(ctx);
    }

    private extern (C) JSValueRef jscConsoleError(JSContextRef ctx,
        JSObjectRef func, JSObjectRef thisObject,
        size_t argumentCount, const(JSValueRef)* arguments,
        JSValueRef* exception) nothrow
    {
        jscWriteArgs(ctx, argumentCount, arguments, true);
        return JSValueMakeUndefined(ctx);
    }

    private extern (C) JSValueRef jscConsoleAssert(JSContextRef ctx,
        JSObjectRef func, JSObjectRef thisObject,
        size_t argumentCount, const(JSValueRef)* arguments,
        JSValueRef* exception) nothrow @trusted
    {
        if (argumentCount > 0 && JSValueToBoolean(ctx, arguments[0]))
            return JSValueMakeUndefined(ctx);

        try
        {
            import std.stdio : stderr;
            stderr.write("Assertion failed: ");
            if (argumentCount > 1)
                jscWriteArgs(ctx, argumentCount - 1, arguments + 1, true);
            else
            {
                stderr.writeln("console.assert");
                stderr.flush();
            }
        }
        catch (Exception)
        {
        }
        return JSValueMakeUndefined(ctx);
    }

    private void jscWriteArgs(JSContextRef ctx, size_t argc,
        const(JSValueRef)* argv, bool useStderr) nothrow @trusted
    {
        try
        {
            import std.stdio : stdout, stderr, write, writeln;
            auto output = useStderr ? stderr : stdout;

            for (size_t i = 0; i < argc; i++)
            {
                if (i > 0)
                    output.write(' ');

                JSValueRef exc = null;
                auto jsStr = JSValueToStringCopy(ctx, argv[i], &exc);
                if (jsStr !is null)
                {
                    auto maxSize = JSStringGetMaximumUTF8CStringSize(jsStr);
                    if (maxSize > 0)
                    {
                        auto buf = new char[maxSize];
                        auto written = JSStringGetUTF8CString(jsStr, buf.ptr, maxSize);
                        if (written > 1)
                            output.write(buf[0 .. written - 1]);
                    }
                    JSStringRelease(jsStr);
                }
            }
            output.writeln();
            output.flush();
        }
        catch (Exception)
        {
        }
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
        dun_v8_set_property(ctx, console, "assert",
            dun_v8_new_function(ctx, &v8ConsoleAssert, "assert", null));

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

    private extern (C) DunV8Value* v8ConsoleAssert(DunV8Context* ctx,
        DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow @trusted
    {
        if (argc > 0 && dun_v8_value_to_bool(ctx, argv[0]) != 0)
            return dun_v8_new_undefined(ctx);

        try
        {
            import std.stdio : stderr;
            stderr.write("Assertion failed: ");
            if (argc > 1)
                v8WriteArgs(ctx, argc - 1, argv + 1, true);
            else
            {
                stderr.writeln("console.assert");
                stderr.flush();
            }
        }
        catch (Exception)
        {
        }
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
