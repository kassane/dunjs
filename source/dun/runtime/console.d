module dun.runtime.console;

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

extern (C) JSValue jsConsoleLog(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    import core.stdc.stdio : fwrite, fputc, stdout;

    writeArgs(stdout, ctx, argc, argv);
    fputc('\n', stdout);
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleWarn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    import core.stdc.stdio : fwrite, fputc, stderr;

    writeArgs(stderr, ctx, argc, argv);
    fputc('\n', stderr);
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleError(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    import core.stdc.stdio : fwrite, fputc, stderr;

    writeArgs(stderr, ctx, argc, argv);
    fputc('\n', stderr);
    return JS_UNDEFINED();
}

extern (C) JSValue jsConsoleAssert(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc > 0 && JS_ToBool(ctx, argv[0]) != 0)
        return JS_UNDEFINED();

    import core.stdc.stdio : fwrite, fputc, stderr;

    enum msg = "Assertion failed: ";
    fwrite(msg.ptr, 1, msg.length, stderr);

    if (argc > 1)
        writeArgs(stderr, ctx, argc - 1, argv + 1);
    else
    {
        enum defaultMsg = "console.assert";
        fwrite(defaultMsg.ptr, 1, defaultMsg.length, stderr);
    }

    fputc('\n', stderr);
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
