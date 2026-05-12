module dun.runtime.process_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void installProcess(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    auto state = cast(DunState*) engine.getContextOpaque();
    auto global = engine.getGlobal();
    auto process = engine.newObject();

    engine.setProperty(process, "nextTick",
        engine.newFunction(&jsNextTick, "nextTick", 1));

    auto envObj = engine.newObject();
    bool envAllowed = state !is null && state.permissions !is null &&
        state.permissions.check(Permission.env);
    if (envAllowed)
    {
        try
        {
            import std.process : environment;
            foreach (key, val; environment.toAA())
                engine.setProperty(envObj, key, engine.newString(val));
        }
        catch (Exception) {}
    }
    engine.setProperty(process, "env", envObj);

    // process.argv
    auto argvArr = engine.newArray();
    if (state !is null && state.scriptArgs !is null)
    {
        import std.conv : to;
        uint idx = 0;
        foreach (arg; state.scriptArgs)
            engine.setProperty(argvArr, (idx++).to!string, engine.newString(arg));
    }
    engine.setProperty(process, "argv", argvArr);

    // process.cwd
    engine.setProperty(process, "cwd",
        engine.newFunction(&jsCwd, "cwd", 0));

    // process.exit
    engine.setProperty(process, "exit",
        engine.newFunction(&jsExit, "exit", 1));

    // process.platform
    version (linux) engine.setProperty(process, "platform", engine.newString("linux"));
    else version (OSX) engine.setProperty(process, "platform", engine.newString("darwin"));
    else version (Windows) engine.setProperty(process, "platform", engine.newString("win32"));
    else engine.setProperty(process, "platform", engine.newString("unknown"));

    // process.arch
    version (X86_64) engine.setProperty(process, "arch", engine.newString("x64"));
    else version (AArch64) engine.setProperty(process, "arch", engine.newString("arm64"));
    else engine.setProperty(process, "arch", engine.newString("unknown"));

    // process.version
    engine.setProperty(process, "version", engine.newString("v21.0.0"));

    // process.pid
    version (Posix)
    {
        import core.sys.posix.unistd : getpid;
        engine.setProperty(process, "pid", engine.newInt(getpid()));
    }

    engine.setProperty(global, "process", process);
}

private:

JSHandle jsCwd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    try
    {
        import std.file : getcwd;
        return engine.newString(getcwd());
    }
    catch (Exception) { return engine.newString("."); }
}

JSHandle jsExit(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    int code = 0;
    if (args.length >= 1 && engine.isNumber(args[0]))
        code = engine.extractInt(args[0]);
    import core.stdc.stdlib : exit;
    exit(code);
    assert(0);
}

JSHandle jsNextTick(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.nextTick");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    assert(engine !is null, "Null engine in process.nextTick");

    if (args.length < 1 || !engine.isFunction(args[0]))
        return engine.throwTypeError("process.nextTick requires a function");

    state.eventLoop.nextTicks.enqueue(engine, args[0]);
    return engine.newUndefined();
}
