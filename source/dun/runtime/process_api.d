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
    assert(engine !is null, "Null engine in installProcess");
    ensureStartTime();
    auto state = cast(DunState*) engine.getContextOpaque();
    assert(state !is null, "Null DunState in installProcess");
    auto global = engine.getGlobal();
    auto process = engine.newObject();

    engine.setProperty(process, "nextTick",
        engine.newFunction(&jsNextTick, "nextTick", 1));
    engine.setProperty(process, "on",
        engine.newFunction(&jsProcessOn, "on", 2));

    bool envAllowed = state !is null && state.permissions !is null &&
        state.permissions.check(Permission.env);
    if (envAllowed)
    {
        auto envSrc = `(function() {
  var _env = {};
  return new Proxy(_env, {
    get: function(target, prop) {
      if (typeof prop !== 'string') return undefined;
      return target[prop];
    },
    set: function(target, prop, value) {
      target[prop] = String(value);
      return true;
    },
    deleteProperty: function(target, prop) {
      delete target[prop];
      return true;
    },
    has: function(target, prop) {
      return prop in target;
    },
    ownKeys: function(target) {
      return Object.keys(target);
    },
    getOwnPropertyDescriptor: function(target, prop) {
      if (prop in target) return { value: target[prop], writable: true, enumerable: true, configurable: true };
      return undefined;
    }
  });
})()`;
        auto envResult = engine.eval(envSrc, "<env-proxy>");
        if (!envResult.isError)
        {
            try
            {
                import std.process : environment;
                foreach (key, val; environment.toAA())
                    engine.setProperty(envResult.value, key, engine.newString(val));
            }
            catch (Exception) {}
            engine.setProperty(process, "env", envResult.value);
        }
        else
        {
            engine.freeValue(envResult.value);
            auto envObj = engine.newObject();
            engine.setProperty(process, "env", envObj);
        }
    }
    else
    {
        auto envObj = engine.newObject();
        engine.setProperty(process, "env", envObj);
    }

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
    engine.setProperty(stdoutObj, "fd", engine.newInt(1));
    engine.setProperty(stdoutObj, "end", engine.newFunction(&jsNoop, "end", 0));
    engine.setProperty(stdoutObj, "on", engine.newFunction(&jsNoop, "on", 2));
    engine.setProperty(stdoutObj, "once", engine.newFunction(&jsNoop, "once", 2));
    engine.setProperty(stdoutObj, "emit", engine.newFunction(&jsNoop, "emit", 1));
    engine.setProperty(stdoutObj, "cork", engine.newFunction(&jsNoop, "cork", 0));
    engine.setProperty(stdoutObj, "uncork", engine.newFunction(&jsNoop, "uncork", 0));
    engine.setProperty(stdoutObj, "cursorTo", engine.newFunction(&jsNoop, "cursorTo", 2));
    engine.setProperty(stdoutObj, "clearLine", engine.newFunction(&jsNoop, "clearLine", 1));
    engine.setProperty(stdoutObj, "moveCursor", engine.newFunction(&jsNoop, "moveCursor", 2));
    engine.setProperty(stdoutObj, "getWindowSize", engine.newFunction(&jsGetWindowSize, "getWindowSize", 0));
    engine.setProperty(stdoutObj, "columns", engine.newInt(80));
    engine.setProperty(stdoutObj, "rows", engine.newInt(24));
    engine.setProperty(process, "stdout", stdoutObj);

    // process.stderr
    auto stderrObj = engine.newObject();
    engine.setProperty(stderrObj, "write", engine.newFunction(&jsStderrWrite, "write", 1));
    engine.setProperty(stderrObj, "writable", engine.newBool(true));
    engine.setProperty(stderrObj, "isTTY", engine.newBool(isattyFd(2)));
    engine.setProperty(stderrObj, "fd", engine.newInt(2));
    engine.setProperty(stderrObj, "end", engine.newFunction(&jsNoop, "end", 0));
    engine.setProperty(stderrObj, "on", engine.newFunction(&jsNoop, "on", 2));
    engine.setProperty(stderrObj, "once", engine.newFunction(&jsNoop, "once", 2));
    engine.setProperty(stderrObj, "emit", engine.newFunction(&jsNoop, "emit", 1));
    engine.setProperty(stderrObj, "cork", engine.newFunction(&jsNoop, "cork", 0));
    engine.setProperty(stderrObj, "uncork", engine.newFunction(&jsNoop, "uncork", 0));
    engine.setProperty(stderrObj, "columns", engine.newInt(80));
    engine.setProperty(stderrObj, "rows", engine.newInt(24));
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

    // process.argv0
    engine.setProperty(process, "argv0", engine.newString("dun"));

    // process.execArgv (empty — no Node-style exec args)
    engine.setProperty(process, "execArgv", engine.newArray());

    // process.mainModule (deprecated but still used)
    engine.setProperty(process, "mainModule", engine.newUndefined());

    // process.title
    engine.setProperty(process, "title", engine.newString("dun"));

    // process.versions
    auto versionsObj = engine.newObject();
    engine.setProperty(versionsObj, "dun", engine.newString("1.0.0"));
    // process.versions.node — npm packages check this for version compatibility
    engine.setProperty(versionsObj, "node", engine.newString("20.0.0"));
    version (EngineQuickJS)
        engine.setProperty(versionsObj, "quickjs", engine.newString("0.8.0"));
    else version (EngineJSC)
        engine.setProperty(versionsObj, "jsc", engine.newString("620.1"));
    else version (EngineV8)
        engine.setProperty(versionsObj, "v8", engine.newString("12.4.0"));
    engine.setProperty(versionsObj, "modules", engine.newString("127"));
    engine.setProperty(versionsObj, "openssl", engine.newString("3.0.0"));
    engine.setProperty(process, "versions", versionsObj);

    // process.release
    auto releaseObj = engine.newObject();
    engine.setProperty(releaseObj, "name", engine.newString("dun"));
    engine.setProperty(process, "release", releaseObj);

    // process.config (minimal — needed by some npm packages)
    auto configObj = engine.newObject();
    auto configVars = engine.newObject();
    engine.setProperty(configVars, "host_arch", engine.newString("x64"));
    engine.setProperty(configObj, "variables", configVars);
    engine.setProperty(process, "config", configObj);

    // process.features
    auto featObj = engine.newObject();
    engine.setProperty(featObj, "inspector", engine.newBool(false));
    engine.setProperty(featObj, "tls", engine.newBool(true));
    engine.setProperty(process, "features", featObj);

    // process.channel (undefined — no IPC by default)
    engine.setProperty(process, "channel", engine.newUndefined());

    // process.emitWarning(msg, type)
    engine.setProperty(process, "emitWarning",
        engine.newFunction(&jsEmitWarning, "emitWarning", 2));

    // process.kill(pid, signal)
    engine.setProperty(process, "kill",
        engine.newFunction(&jsProcessKill, "kill", 2));

    // process.ppid
    version (Posix)
    {
        import core.sys.posix.unistd : getppid;
        engine.setProperty(process, "ppid", engine.newInt(getppid()));
    }

    // process.exitCode (writable — defaults to undefined)
    engine.setProperty(process, "exitCode", engine.newUndefined());

    // process.abort()
    engine.setProperty(process, "abort",
        engine.newFunction(&jsProcessAbort, "abort", 0));

    // process.umask()
    engine.setProperty(process, "umask",
        engine.newFunction(&jsProcessUmask, "umask", 1));

    version (Posix)
    {
        engine.setProperty(process, "getuid",
            engine.newFunction(&jsProcessGetuid, "getuid", 0));
        engine.setProperty(process, "getgid",
            engine.newFunction(&jsProcessGetgid, "getgid", 0));
        engine.setProperty(process, "geteuid",
            engine.newFunction(&jsProcessGeteuid, "geteuid", 0));
        engine.setProperty(process, "getegid",
            engine.newFunction(&jsProcessGetegid, "getegid", 0));
        engine.setProperty(process, "getgroups",
            engine.newFunction(&jsProcessGetgroups, "getgroups", 0));
    }

    // process.debugPort
    engine.setProperty(process, "debugPort", engine.newInt(9229));

    // process.connected
    engine.setProperty(process, "connected", engine.newBool(false));

    // process.resourceUsage()
    engine.setProperty(process, "resourceUsage",
        engine.newFunction(&jsProcessResourceUsage, "resourceUsage", 0));

    engine.setProperty(global, "process", process);
    engine.freeValue(global);

    auto enhRes = engine.eval(processEnhanceSource(), "<process-enhance>");
    engine.freeValue(enhRes.value);
}

private:

JSHandle jsNoop(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsNoop");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsNoop");
    return state.engine.newUndefined();
}

JSHandle jsGetWindowSize(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGetWindowSize");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsGetWindowSize");
    auto engine = state.engine;
    auto arr = engine.newArray();
    engine.setPropertyIndex(arr, 0, engine.newInt(80));
    engine.setPropertyIndex(arr, 1, engine.newInt(24));
    return arr;
}

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

    if (args.length > 1)
    {
        auto boundArgs = args[1 .. $];
        auto global = engine.getGlobal();
        auto bindFn = engine.getProperty(args[0], "bind");
        if (engine.isFunction(bindFn))
        {
            JSHandle[16] bindArgs = void;
            bindArgs[0] = global;
            auto nExtra = args.length - 1;
            if (nExtra > 15) nExtra = 15;
            foreach (i; 0 .. nExtra)
                bindArgs[1 + i] = args[1 + i];
            auto bound = engine.callFunction(bindFn, args[0], bindArgs[0 .. 1 + nExtra]);
            state.eventLoop.nextTicks.enqueue(engine, bound);
            engine.freeValue(bound);
        }
        else
        {
            state.eventLoop.nextTicks.enqueue(engine, args[0]);
        }
        engine.freeValue(bindFn);
        engine.freeValue(global);
    }
    else
    {
        state.eventLoop.nextTicks.enqueue(engine, args[0]);
    }
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

JSHandle jsEmitWarning(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.emitWarning");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newUndefined();
    try
    {
        string msg;
        string wtype = "Warning";
        if (engine.isString(args[0]))
            msg = engine.extractString(args[0]);
        else if (engine.isObject(args[0]))
        {
            auto msgProp = engine.getProperty(args[0], "message");
            msg = engine.isString(msgProp) ? engine.extractString(msgProp) : "Unknown warning";
            engine.freeValue(msgProp);
        }
        if (args.length >= 2 && engine.isString(args[1]))
            wtype = engine.extractString(args[1]);
        import core.stdc.stdio : fprintf, stderr, fflush;
        fprintf(stderr, "(%.*s) %.*s\n",
            cast(int) wtype.length, wtype.ptr,
            cast(int) msg.length, msg.ptr);
        fflush(stderr);
    }
    catch (Exception) {}
    return engine.newUndefined();
}

JSHandle jsProcessKill(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.kill");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("process.kill requires a pid");
    version (Posix)
    {
        import core.sys.posix.signal : kill, SIGTERM;
        int pid = engine.extractInt(args[0]);
        int sig = SIGTERM;
        if (args.length >= 2 && engine.isNumber(args[1]))
            sig = engine.extractInt(args[1]);
        else if (args.length >= 2 && engine.isString(args[1]))
        {
            auto sigName = engine.extractString(args[1]);
            sig = sigNameToNum(sigName);
        }
        auto ret = kill(pid, sig);
        if (ret != 0)
            return engine.throwTypeError("kill failed");
        return engine.newBool(true);
    }
    else
        return engine.throwTypeError("process.kill not supported on this platform");
}

JSHandle jsProcessAbort(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.abort");
    import core.stdc.stdlib : abort;
    abort();
    assert(0);
}

JSHandle jsProcessUmask(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.umask");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    version (Posix)
    {
        import core.sys.posix.sys.stat : umask, mode_t;
        if (args.length >= 1 && engine.isNumber(args[0]))
        {
            auto newMask = cast(mode_t) engine.extractInt(args[0]);
            auto old = umask(newMask);
            return engine.newInt(cast(int) old);
        }
        auto cur = umask(0);
        umask(cur);
        return engine.newInt(cast(int) cur);
    }
    else
        return engine.newInt(0);
}

version (Posix)
{
    JSHandle jsProcessGetuid(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null);
        auto state = cast(DunState*) ctx;
        assert(state.engine !is null);
        import core.sys.posix.unistd : getuid;
        return state.engine.newInt(cast(int) getuid());
    }

    JSHandle jsProcessGetgid(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null);
        auto state = cast(DunState*) ctx;
        assert(state.engine !is null);
        import core.sys.posix.unistd : getgid;
        return state.engine.newInt(cast(int) getgid());
    }

    JSHandle jsProcessGeteuid(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null);
        auto state = cast(DunState*) ctx;
        assert(state.engine !is null);
        import core.sys.posix.unistd : geteuid;
        return state.engine.newInt(cast(int) geteuid());
    }

    JSHandle jsProcessGetegid(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null);
        auto state = cast(DunState*) ctx;
        assert(state.engine !is null);
        import core.sys.posix.unistd : getegid;
        return state.engine.newInt(cast(int) getegid());
    }

    JSHandle jsProcessGetgroups(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
    {
        assert(ctx !is null);
        auto state = cast(DunState*) ctx;
        assert(state.engine !is null);
        auto engine = state.engine;
        import core.sys.posix.unistd : getgroups;
        import core.sys.posix.sys.types : gid_t;
        enum MAX_GROUPS = 64;
        gid_t[MAX_GROUPS] groups;
        auto n = getgroups(MAX_GROUPS, groups.ptr);
        auto arr = engine.newArray();
        if (n > 0)
        {
            for (int i = 0; i < n; i++)
                engine.setPropertyIndex(arr, cast(uint) i, engine.newInt(cast(int) groups[i]));
        }
        return arr;
    }
}

private int sigNameToNum(string name) @safe nothrow
{
    if (name == "SIGTERM") return 15;
    if (name == "SIGINT") return 2;
    if (name == "SIGKILL") return 9;
    if (name == "SIGHUP") return 1;
    if (name == "SIGUSR1") return 10;
    if (name == "SIGUSR2") return 12;
    return 15;
}

JSHandle jsProcessResourceUsage(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in process.resourceUsage");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in process.resourceUsage");
    auto engine = state.engine;
    auto obj = engine.newObject();
    version (Posix)
    {
        import core.sys.posix.sys.resource : getrusage, rusage, RUSAGE_SELF;
        rusage ru;
        if (getrusage(RUSAGE_SELF, &ru) == 0)
        {
            engine.setProperty(obj, "userCPUTime", engine.newFloat(
                cast(double)(ru.ru_utime.tv_sec * 1_000_000L + ru.ru_utime.tv_usec)));
            engine.setProperty(obj, "systemCPUTime", engine.newFloat(
                cast(double)(ru.ru_stime.tv_sec * 1_000_000L + ru.ru_stime.tv_usec)));
            engine.setProperty(obj, "maxRSS", engine.newFloat(cast(double) ru.ru_maxrss));
            engine.setProperty(obj, "sharedMemorySize", engine.newFloat(cast(double) ru.ru_ixrss));
            engine.setProperty(obj, "unsharedDataSize", engine.newFloat(cast(double) ru.ru_idrss));
            engine.setProperty(obj, "unsharedStackSize", engine.newFloat(cast(double) ru.ru_isrss));
            engine.setProperty(obj, "minorPageFault", engine.newFloat(cast(double) ru.ru_minflt));
            engine.setProperty(obj, "majorPageFault", engine.newFloat(cast(double) ru.ru_majflt));
            engine.setProperty(obj, "swappedOut", engine.newFloat(cast(double) ru.ru_nswap));
            engine.setProperty(obj, "fsRead", engine.newFloat(cast(double) ru.ru_inblock));
            engine.setProperty(obj, "fsWrite", engine.newFloat(cast(double) ru.ru_oublock));
            engine.setProperty(obj, "ipcSent", engine.newFloat(cast(double) ru.ru_msgsnd));
            engine.setProperty(obj, "ipcReceived", engine.newFloat(cast(double) ru.ru_msgrcv));
            engine.setProperty(obj, "signalsCount", engine.newFloat(cast(double) ru.ru_nsignals));
            engine.setProperty(obj, "voluntaryContextSwitches", engine.newFloat(cast(double) ru.ru_nvcsw));
            engine.setProperty(obj, "involuntaryContextSwitches", engine.newFloat(cast(double) ru.ru_nivcsw));
        }
        else
        {
            engine.setProperty(obj, "userCPUTime", engine.newFloat(0));
            engine.setProperty(obj, "systemCPUTime", engine.newFloat(0));
            engine.setProperty(obj, "maxRSS", engine.newFloat(0));
            engine.setProperty(obj, "sharedMemorySize", engine.newFloat(0));
            engine.setProperty(obj, "unsharedDataSize", engine.newFloat(0));
            engine.setProperty(obj, "unsharedStackSize", engine.newFloat(0));
            engine.setProperty(obj, "minorPageFault", engine.newFloat(0));
            engine.setProperty(obj, "majorPageFault", engine.newFloat(0));
            engine.setProperty(obj, "swappedOut", engine.newFloat(0));
            engine.setProperty(obj, "fsRead", engine.newFloat(0));
            engine.setProperty(obj, "fsWrite", engine.newFloat(0));
            engine.setProperty(obj, "ipcSent", engine.newFloat(0));
            engine.setProperty(obj, "ipcReceived", engine.newFloat(0));
            engine.setProperty(obj, "signalsCount", engine.newFloat(0));
            engine.setProperty(obj, "voluntaryContextSwitches", engine.newFloat(0));
            engine.setProperty(obj, "involuntaryContextSwitches", engine.newFloat(0));
        }
    }
    else
    {
        engine.setProperty(obj, "userCPUTime", engine.newFloat(0));
        engine.setProperty(obj, "systemCPUTime", engine.newFloat(0));
        engine.setProperty(obj, "maxRSS", engine.newFloat(0));
        engine.setProperty(obj, "sharedMemorySize", engine.newFloat(0));
        engine.setProperty(obj, "unsharedDataSize", engine.newFloat(0));
        engine.setProperty(obj, "unsharedStackSize", engine.newFloat(0));
        engine.setProperty(obj, "minorPageFault", engine.newFloat(0));
        engine.setProperty(obj, "majorPageFault", engine.newFloat(0));
        engine.setProperty(obj, "swappedOut", engine.newFloat(0));
        engine.setProperty(obj, "fsRead", engine.newFloat(0));
        engine.setProperty(obj, "fsWrite", engine.newFloat(0));
        engine.setProperty(obj, "ipcSent", engine.newFloat(0));
        engine.setProperty(obj, "ipcReceived", engine.newFloat(0));
        engine.setProperty(obj, "signalsCount", engine.newFloat(0));
        engine.setProperty(obj, "voluntaryContextSwitches", engine.newFloat(0));
        engine.setProperty(obj, "involuntaryContextSwitches", engine.newFloat(0));
    }
    return obj;
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

string processEnhanceSource() pure @safe nothrow
{
    return `(function() {
  var p = process;
  if (!p) return;
  var _events = {};
  var _origOn = p.on;
  p.on = function(ev, cb) {
    if (typeof ev !== 'string' || typeof cb !== 'function') return p;
    if (ev === 'uncaughtException' || ev === 'unhandledRejection' ||
        ev === 'SIGTERM' || ev === 'SIGINT') {
      return _origOn.call(p, ev, cb);
    }
    if (!_events[ev]) _events[ev] = [];
    _events[ev].push(cb);
    return p;
  };
  p.addListener = p.on;
  p.once = function(ev, cb) {
    if (typeof cb !== 'function') return p;
    function w() {
      p.removeListener(ev, w);
      cb.apply(p, arguments);
    }
    w._orig = cb;
    return p.on(ev, w);
  };
  p.off = p.removeListener = function(ev, cb) {
    var cbs = _events[ev];
    if (!cbs) return p;
    for (var i = cbs.length - 1; i >= 0; i--) {
      if (cbs[i] === cb || cbs[i]._orig === cb) cbs.splice(i, 1);
    }
    return p;
  };
  p.removeAllListeners = function(ev) {
    if (ev) _events[ev] = [];
    else _events = {};
    return p;
  };
  p.listeners = function(ev) {
    return (_events[ev] || []).slice();
  };
  p.listenerCount = function(ev) {
    return (_events[ev] || []).length;
  };
  p.rawListeners = function(ev) {
    return (_events[ev] || []).slice();
  };
  p.eventNames = function() {
    return Object.keys(_events).filter(function(k) { return _events[k].length > 0; });
  };
  p.prependListener = function(ev, cb) {
    if (!_events[ev]) _events[ev] = [];
    _events[ev].unshift(cb);
    return p;
  };
  p.prependOnceListener = function(ev, cb) {
    function w() {
      p.removeListener(ev, w);
      cb.apply(p, arguments);
    }
    w._orig = cb;
    return p.prependListener(ev, w);
  };
  p.emit = function(ev) {
    var cbs = _events[ev];
    if (!cbs || cbs.length === 0) return false;
    var args = Array.prototype.slice.call(arguments, 1);
    var cc = cbs.slice();
    for (var i = 0; i < cc.length; i++) cc[i].apply(p, args);
    return true;
  };
  p.setMaxListeners = function() { return p; };
  p.getMaxListeners = function() { return 10; };
  p.report = {
    writeReport: function() { return ''; },
    getReport: function() { return {}; },
    reportOnSignal: false,
    reportOnFatalError: false,
    reportOnUncaughtException: false,
    directory: '',
    filename: ''
  };
  p.allowedNodeEnvironmentFlags = new Set();
  p.binding = function(name) { throw new Error('process.binding is deprecated and not supported'); };
  p._linkedBinding = function(name) { throw new Error('process._linkedBinding is not supported'); };
  var _uncaughtCb = null;
  p.hasUncaughtExceptionCaptureCallback = function() { return _uncaughtCb !== null; };
  p.setUncaughtExceptionCaptureCallback = function(fn) { _uncaughtCb = fn || null; };
  if (!p.config) p.config = { variables: {} };
  if (!p.features) p.features = { inspector: false, debug: false, uv: false, ipv6: true, tls_alpn: true, tls_sni: true, tls_ocsp: false, tls: true };
  if (!p.release) p.release = { name: 'dun' };
})()`;
}
