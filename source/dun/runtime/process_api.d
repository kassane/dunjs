module dun.runtime.process_api;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

private enum STDIN_READ_BUF_SIZE = 65_536;

private __gshared JSHandle gUncaughtHandler;
private __gshared IJSEngine gUncaughtEngine;
private __gshared bool gHasUncaughtHandler;

private __gshared JSHandle gRejectionHandler;
private __gshared IJSEngine gRejectionEngine;
private __gshared bool gHasRejectionHandler;

bool hasUncaughtExceptionHandler() @trusted nothrow @nogc
{
    return gHasUncaughtHandler;
}

bool invokeUncaughtExceptionHandler(IJSEngine engine, string errorMsg) @trusted nothrow
{
    if (!gHasUncaughtHandler || engine is null) return false;
    try
    {
        auto errObj = engine.newString(errorMsg);
        JSHandle[1] args = [errObj];
        auto global = engine.getGlobal();
        engine.callFunction(gUncaughtHandler, global, args[]);
        engine.freeValue(errObj);
        engine.freeValue(global);
        return true;
    }
    catch (Throwable) { return false; }
}

bool hasUnhandledRejectionHandler() @trusted nothrow @nogc
{
    return gHasRejectionHandler;
}

bool invokeUnhandledRejectionHandler(IJSEngine engine, JSHandle reason, JSHandle promise) @trusted nothrow
{
    if (!gHasRejectionHandler || engine is null) return false;
    try
    {
        JSHandle[2] args = [reason, promise];
        auto global = engine.getGlobal();
        engine.callFunction(gRejectionHandler, global, args[]);
        engine.freeValue(global);
        return true;
    }
    catch (Throwable) { return false; }
}

// Store process start time for uptime()
private __gshared long _processStartTimeTicks;
private __gshared bool _startTimeInit = false;

private void ensureStartTime() @trusted nothrow
{
    if (_startTimeInit) return;
    try
    {
        import core.time : MonoTime;
        _processStartTimeTicks = MonoTime.currTime.ticks;
    }
    catch (Throwable) {}
    _startTimeInit = true;
}

private bool isattyFd(int fd) @trusted nothrow
{
    version (Posix)
    {
        import core.sys.posix.unistd : isatty;
        return isatty(fd) == 1;
    }
    else
        return false;
}

void installProcess(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");
    ensureStartTime();
    auto state = cast(DunState*) engine.getContextOpaque();
    auto global = engine.getGlobal();
    auto process = engine.newObject();

    engine.setProperty(process, "nextTick",
        engine.newFunction(&jsNextTick, "nextTick", 1));
    engine.setProperty(process, "on",
        engine.newFunction(&jsProcessOn, "on", 2));

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
        uint idx = 0;
        foreach (arg; state.scriptArgs)
            engine.setPropertyIndex(argvArr, idx++, engine.newString(arg));
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

    // process.stdout
    auto stdoutObj = engine.newObject();
    engine.setProperty(stdoutObj, "write", engine.newFunction(&jsStdoutWrite, "write", 1));
    engine.setProperty(stdoutObj, "writable", engine.newBool(true));
    engine.setProperty(stdoutObj, "isTTY", engine.newBool(isattyFd(1)));
    engine.setProperty(process, "stdout", stdoutObj);

    // process.stderr
    auto stderrObj = engine.newObject();
    engine.setProperty(stderrObj, "write", engine.newFunction(&jsStderrWrite, "write", 1));
    engine.setProperty(stderrObj, "writable", engine.newBool(true));
    engine.setProperty(stderrObj, "isTTY", engine.newBool(isattyFd(2)));
    engine.setProperty(process, "stderr", stderrObj);

    // process.stdin
    auto stdinObj = engine.newObject();
    engine.setProperty(stdinObj, "read", engine.newFunction(&jsStdinRead, "read", 0));
    engine.setProperty(stdinObj, "readable", engine.newBool(true));
    engine.setProperty(stdinObj, "isTTY", engine.newBool(isattyFd(0)));
    engine.setProperty(stdinObj, "setEncoding", engine.newFunction(&jsStdinSetEncoding, "setEncoding", 1));
    engine.setProperty(stdinObj, "fd", engine.newInt(0));
    engine.setProperty(process, "stdin", stdinObj);

    // process.hrtime() and process.hrtime.bigint()
    auto hrtimeFn = engine.newFunction(&jsHrtime, "hrtime", 0);
    engine.setProperty(hrtimeFn, "bigint", engine.newFunction(&jsHrtimeBigint, "bigint", 0));
    engine.setProperty(process, "hrtime", hrtimeFn);

    // process.uptime()
    engine.setProperty(process, "uptime", engine.newFunction(&jsUptime, "uptime", 0));

    // process.memoryUsage()
    engine.setProperty(process, "memoryUsage", engine.newFunction(&jsMemoryUsage, "memoryUsage", 0));

    // process.cpuUsage()
    engine.setProperty(process, "cpuUsage", engine.newFunction(&jsCpuUsage, "cpuUsage", 0));

    // process.chdir(directory)
    engine.setProperty(process, "chdir", engine.newFunction(&jsChdir, "chdir", 1));

    // process.execPath
    try
    {
        import std.file : thisExePath;
        engine.setProperty(process, "execPath", engine.newString(thisExePath()));
    }
    catch (Exception)
    {
        engine.setProperty(process, "execPath", engine.newString("/usr/local/bin/dun"));
    }

    // process.title
    engine.setProperty(process, "title", engine.newString("dun"));

    // process.versions
    auto versionsObj = engine.newObject();
    engine.setProperty(versionsObj, "dun", engine.newString("1.0.0"));
    version (EngineQuickJS)
        engine.setProperty(versionsObj, "quickjs", engine.newString("0.8.0"));
    else version (EngineJSC)
        engine.setProperty(versionsObj, "jsc", engine.newString("620.1"));
    else version (EngineV8)
        engine.setProperty(versionsObj, "v8", engine.newString("12.4.0"));
    engine.setProperty(versionsObj, "modules", engine.newString("127"));
    engine.setProperty(versionsObj, "openssl", engine.newString("3.0.0"));
    engine.setProperty(process, "versions", versionsObj);

    engine.setProperty(global, "process", process);
    engine.freeValue(global);
}

private:

JSHandle jsCwd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCwd");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsCwd");
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
    assert(ctx !is null, "Null ctx in jsExit");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsExit");
    auto engine = state.engine;
    int code = 0;
    if (args.length >= 1 && engine.isNumber(args[0]))
        code = engine.extractInt(args[0]);
    import core.stdc.stdlib : exit;
    exit(code);
    assert(0);
}

JSHandle jsProcessOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.on");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2 || !engine.isString(args[0]) || !engine.isFunction(args[1]))
        return engine.throwTypeError("process.on requires event name and callback");

    auto event = engine.extractString(args[0]);
    if (event == "uncaughtException")
    {
        if (gHasUncaughtHandler)
            engine.freeValue(gUncaughtHandler);
        gUncaughtHandler = engine.dupValue(args[1]);
        gUncaughtEngine = engine;
        gHasUncaughtHandler = true;
    }
    else if (event == "unhandledRejection")
    {
        if (gHasRejectionHandler)
            engine.freeValue(gRejectionHandler);
        gRejectionHandler = engine.dupValue(args[1]);
        gRejectionEngine = engine;
        gHasRejectionHandler = true;
    }
    else if (event == "SIGTERM")
    {
        import dun.runtime.signals : registerSignalHandler, installSignalHandlers, SignalType;
        installSignalHandlers();
        registerSignalHandler(engine, SignalType.SIGTERM, args[1]);
    }
    else if (event == "SIGINT")
    {
        import dun.runtime.signals : registerSignalHandler, installSignalHandlers, SignalType;
        installSignalHandlers();
        registerSignalHandler(engine, SignalType.SIGINT, args[1]);
    }
    return engine.dupValue(thisVal);
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

JSHandle jsStdoutWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.stdout.write");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(true);
    try
    {
        auto data = engine.extractString(args[0]);
        import core.stdc.stdio : fwrite, stdout, fflush;
        fwrite(data.ptr, 1, data.length, stdout);
        fflush(stdout);
    }
    catch (Exception) {}
    return engine.newBool(true);
}

JSHandle jsStderrWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.stderr.write");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(true);
    try
    {
        auto data = engine.extractString(args[0]);
        import core.stdc.stdio : fwrite, stderr, fflush;
        fwrite(data.ptr, 1, data.length, stderr);
        fflush(stderr);
    }
    catch (Exception) {}
    return engine.newBool(true);
}

JSHandle jsHrtime(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.hrtime");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    try
    {
        import core.time : MonoTime, ticksToNSecs;
        auto now = MonoTime.currTime;
        long totalNs = ticksToNSecs(now.ticks);
        if (args.length >= 1 && engine.isArray(args[0]))
        {
            auto secH = engine.getPropertyIndex(args[0], 0);
            auto nsH = engine.getPropertyIndex(args[0], 1);
            auto prevSec = engine.extractFloat(secH);
            auto prevNs = engine.extractFloat(nsH);
            engine.freeValue(nsH);
            engine.freeValue(secH);
            long prevTotalNs = cast(long)(prevSec * 1_000_000_000.0 + prevNs);
            totalNs -= prevTotalNs;
        }
        long secs = totalNs / 1_000_000_000;
        long nanos = totalNs % 1_000_000_000;
        auto arr = engine.newArray();
        engine.setPropertyIndex(arr, 0, engine.newFloat(cast(double) secs));
        engine.setPropertyIndex(arr, 1, engine.newFloat(cast(double) nanos));
        return arr;
    }
    catch (Exception) { return engine.newArray(); }
}

JSHandle jsHrtimeBigint(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.hrtime.bigint");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    try
    {
        import core.time : MonoTime, ticksToNSecs;
        auto now = MonoTime.currTime;
        long totalNs = ticksToNSecs(now.ticks);
        return engine.newFloat(cast(double) totalNs);
    }
    catch (Exception) { return engine.newFloat(0.0); }
}

JSHandle jsUptime(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.uptime");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    try
    {
        import core.time : MonoTime, ticksToNSecs;
        auto now = MonoTime.currTime;
        long nowNs = ticksToNSecs(now.ticks);
        long startNs = ticksToNSecs(_processStartTimeTicks);
        double uptimeSecs = cast(double)(nowNs - startNs) / 1_000_000_000.0;
        return engine.newFloat(uptimeSecs);
    }
    catch (Exception) { return engine.newFloat(0.0); }
}

JSHandle jsMemoryUsage(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.memoryUsage");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto obj = engine.newObject();
    double rss = 0;
    version (linux)
    {
        try
        {
            import std.file : readText;
            import std.string : split;
            import std.conv : to;
            auto statm = readText("/proc/self/statm");
            auto parts = statm.split(" ");
            if (parts.length >= 2)
                rss = to!double(parts[1]) * 4096.0;
        }
        catch (Exception) {}
    }
    engine.setProperty(obj, "rss", engine.newFloat(rss));
    engine.setProperty(obj, "heapTotal", engine.newFloat(rss > 0 ? rss * 0.8 : 0));
    engine.setProperty(obj, "heapUsed", engine.newFloat(rss > 0 ? rss * 0.6 : 0));
    engine.setProperty(obj, "external", engine.newFloat(0));
    engine.setProperty(obj, "arrayBuffers", engine.newFloat(0));
    return obj;
}

JSHandle jsCpuUsage(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.cpuUsage");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto obj = engine.newObject();
    double userUs = 0;
    double sysUs = 0;
    version (Posix)
    {
        import core.sys.posix.sys.resource : rusage, getrusage, RUSAGE_SELF;
        rusage usage;
        if (getrusage(RUSAGE_SELF, &usage) == 0)
        {
            userUs = cast(double)(usage.ru_utime.tv_sec * 1_000_000L + usage.ru_utime.tv_usec);
            sysUs = cast(double)(usage.ru_stime.tv_sec * 1_000_000L + usage.ru_stime.tv_usec);
        }
    }
    engine.setProperty(obj, "user", engine.newFloat(userUs));
    engine.setProperty(obj, "system", engine.newFloat(sysUs));
    return obj;
}

JSHandle jsChdir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.chdir");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("process.chdir requires a directory path");
    auto dir = engine.extractString(args[0]);
    try
    {
        import std.file : chdir;
        chdir(dir);
        return engine.newUndefined();
    }
    catch (Exception)
    {
        return engine.throwTypeError("ENOENT: no such file or directory, chdir '" ~ dir ~ "'");
    }
}

JSHandle jsStdinRead(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.stdin.read");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    version (Posix)
    {
        import core.sys.posix.unistd : posixRead = read;
        import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;

        int fd = 0;
        auto origFlags = fcntl(fd, F_GETFL);
        fcntl(fd, F_SETFL, origFlags | O_NONBLOCK);
        scope (exit) fcntl(fd, F_SETFL, origFlags);

        ubyte[STDIN_READ_BUF_SIZE] buf = void;
        auto n = posixRead(fd, buf.ptr, buf.length);
        if (n <= 0)
            return engine.newNull();

        return engine.newString((() @trusted => cast(string) buf[0 .. n])());
    }
    else
        return engine.newNull();
}

JSHandle jsStdinSetEncoding(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.stdin.setEncoding");
    auto state = cast(DunState*) ctx;
    return state.engine.dupValue(thisVal);
}
