module dun.runtime.console;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installConsole(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto console = engine.newObject();
    auto global = engine.getGlobal();

    engine.setProperty(console, "log", engine.newFunction(&consoleLog, "log", 1));
    engine.setProperty(console, "info", engine.newFunction(&consoleLog, "info", 1));
    engine.setProperty(console, "debug", engine.newFunction(&consoleLog, "debug", 1));
    engine.setProperty(console, "warn", engine.newFunction(&consoleWarn, "warn", 1));
    engine.setProperty(console, "error", engine.newFunction(&consoleError, "error", 1));
    engine.setProperty(console, "assert", engine.newFunction(&consoleAssert, "assert", 2));

    engine.setProperty(global, "console", console);
}

private:

JSHandle consoleLog(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.log");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in console.log");
    writeArgs(state.engine, args, false);
    return state.engine.newUndefined();
}

JSHandle consoleWarn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.warn");
    auto state = cast(DunState*) ctx;
    writeArgs(state.engine, args, true);
    return state.engine.newUndefined();
}

JSHandle consoleError(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.error");
    auto state = cast(DunState*) ctx;
    writeArgs(state.engine, args, true);
    return state.engine.newUndefined();
}

JSHandle consoleAssert(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.assert");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length > 0 && engine.extractBool(args[0]))
        return engine.newUndefined();

    try
    {
        import std.stdio : stderr;
        stderr.write("Assertion failed: ");
        if (args.length > 1)
            writeArgs(engine, args[1 .. $], true);
        else
        {
            stderr.writeln("console.assert");
            stderr.flush();
        }
    }
    catch (Exception) {}
    return engine.newUndefined();
}

void writeArgs(IJSEngine engine, JSHandle[] args, bool useStderr) @trusted
{
    try
    {
        import std.stdio : stdout, stderr;
        auto output = useStderr ? stderr : stdout;

        foreach (i, arg; args)
        {
            if (i > 0)
                output.write(' ');
            output.write(engine.extractString(arg));
        }
        output.writeln();
        output.flush();
    }
    catch (Exception) {}
}
