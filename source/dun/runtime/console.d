module dun.runtime.console;

version (EngineQuickJS):

import dun.engine.iface : IJSEngine, JSHandle;
import dun.engine.quickjs.bindings;

void installConsole(IJSEngine engine) @trusted
{
    auto ctx = cast(JSContext*) engine.rawContext();

    auto console = JS_NewObject(ctx);

    JS_SetPropertyStr(ctx, console, "log",
        JS_NewCFunction(ctx, &jsConsoleLog, "log", 1));
    JS_SetPropertyStr(ctx, console, "info",
        JS_NewCFunction(ctx, &jsConsoleLog, "info", 1));
    JS_SetPropertyStr(ctx, console, "debug",
        JS_NewCFunction(ctx, &jsConsoleLog, "debug", 1));
    JS_SetPropertyStr(ctx, console, "warn",
        JS_NewCFunction(ctx, &jsConsoleWarn, "warn", 1));
    JS_SetPropertyStr(ctx, console, "error",
        JS_NewCFunction(ctx, &jsConsoleError, "error", 1));
    JS_SetPropertyStr(ctx, console, "assert",
        JS_NewCFunction(ctx, &jsConsoleAssert, "assert", 2));

    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "console", console);
    JS_FreeValue(ctx, global);
}

private:

imported!"core.stdc.stdio".FILE* getStdout() @trusted nothrow @nogc
{
    import core.stdc.stdio : stdout;
    return cast(imported!"core.stdc.stdio".FILE*) cast(void*) stdout;
}

imported!"core.stdc.stdio".FILE* getStderr() @trusted nothrow @nogc
{
    import core.stdc.stdio : stderr;
    return cast(imported!"core.stdc.stdio".FILE*) cast(void*) stderr;
}

extern (C) JSValue jsConsoleLog(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.stdc.stdio : fputc;
    writeArgs(getStdout(), ctx, argc, argv);
    fputc('\n', getStdout());
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleWarn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.stdc.stdio : fputc;
    writeArgs(getStderr(), ctx, argc, argv);
    fputc('\n', getStderr());
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleError(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.stdc.stdio : fputc;
    writeArgs(getStderr(), ctx, argc, argv);
    fputc('\n', getStderr());
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleAssert(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc > 0 && JS_ToBool(ctx, argv[0]) != 0)
        return JS_UNDEFINED();

    import core.stdc.stdio : fwrite, fputc;

    enum msg = "Assertion failed: ";
    fwrite(&msg[0], 1, msg.length, getStderr());

    if (argc > 1)
        writeArgs(getStderr(), ctx, argc - 1, argv + 1);
    else
    {
        enum defaultMsg = "console.assert";
        fwrite(&defaultMsg[0], 1, defaultMsg.length, getStderr());
    }

    fputc('\n', getStderr());
    return JS_UNDEFINED();
}

void writeArgs(imported!"core.stdc.stdio".FILE* file, JSContext* ctx,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.stdc.stdio : fwrite, fputc;

    for (int i = 0; i < argc; i++)
    {
        if (i > 0)
            fputc(' ', file);

        size_t len;
        const(char)* str = JS_ToCStringLen2(ctx, &len, argv[i], 0);
        if (str !is null)
        {
            fwrite(str, 1, len, file);
            JS_FreeCString(ctx, str);
        }
    }
}
