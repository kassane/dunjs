module dun.builtins.os;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum HOSTNAME_BUF_SIZE = 256;

void registerOsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerOsModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "platform", engine.newFunction(&jsOsPlatform, "platform", 0));
    engine.setProperty(obj, "arch", engine.newFunction(&jsOsArch, "arch", 0));
    engine.setProperty(obj, "type", engine.newFunction(&jsOsType, "type", 0));
    engine.setProperty(obj, "hostname", engine.newFunction(&jsOsHostname, "hostname", 0));
    engine.setProperty(obj, "homedir", engine.newFunction(&jsOsHomedir, "homedir", 0));
    engine.setProperty(obj, "tmpdir", engine.newFunction(&jsOsTmpdir, "tmpdir", 0));
    engine.setProperty(obj, "cpus", engine.newFunction(&jsOsCpus, "cpus", 0));
    engine.setProperty(obj, "totalmem", engine.newFunction(&jsOsTotalmem, "totalmem", 0));
    engine.setProperty(obj, "freemem", engine.newFunction(&jsOsFreemem, "freemem", 0));
    engine.setProperty(obj, "uptime", engine.newFunction(&jsOsUptime, "uptime", 0));
    engine.setProperty(obj, "release", engine.newFunction(&jsOsRelease, "release", 0));
    engine.setProperty(obj, "endianness", engine.newFunction(&jsOsEndianness, "endianness", 0));
    engine.setProperty(obj, "networkInterfaces", engine.newFunction(&jsOsNetworkInterfaces, "networkInterfaces", 0));
    engine.setProperty(obj, "userInfo", engine.newFunction(&jsOsUserInfo, "userInfo", 0));
    engine.setProperty(obj, "loadavg", engine.newFunction(&jsOsLoadavg, "loadavg", 0));
    engine.setProperty(obj, "version", engine.newFunction(&jsOsVersion, "version", 0));
    engine.setProperty(obj, "machine", engine.newFunction(&jsOsMachine, "machine", 0));
    engine.setProperty(obj, "availableParallelism", engine.newFunction(&jsOsAvailableParallelism, "availableParallelism", 0));
    engine.setProperty(obj, "setPriority", engine.newFunction(&jsOsSetPriority, "setPriority", 2));
    engine.setProperty(obj, "getPriority", engine.newFunction(&jsOsGetPriority, "getPriority", 1));
    engine.setProperty(obj, "EOL", engine.newString(eol()));
    engine.setProperty(obj, "devNull", engine.newString(devNull()));

    auto constRes = engine.eval(osConstantsSource(), "<os-constants>");
    if (!constRes.isError)
    {
        engine.setProperty(obj, "constants", constRes.value);
    }
    else
        engine.freeValue(constRes.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_os__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:os", &osModuleInit);
        if (m is null) return;
        foreach (name; osExportNames)
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private static immutable osExportNames = [
        "platform", "arch", "type", "hostname", "homedir",
        "tmpdir", "cpus", "totalmem", "freemem", "uptime",
        "release", "endianness", "networkInterfaces",
        "userInfo", "loadavg", "version", "machine",
        "availableParallelism", "setPriority", "getPriority",
        "EOL", "devNull", "constants"
    ];

    private extern (C) int osModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto osObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_os__");
        foreach (name; osExportNames)
        {
            auto fn = JS_GetPropertyStr(ctx, osObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, osObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

IJSEngine getEngine(void* ctx) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null);
    return state.engine;
}

string eol() pure @safe nothrow
{
    version (Windows) return "\r\n";
    else return "\n";
}

string devNull() pure @safe nothrow
{
    version (Windows) return "\\\\.\\NUL";
    else return "/dev/null";
}

string platformStr() pure @safe nothrow
{
    version (linux) return "linux";
    else version (OSX) return "darwin";
    else version (Windows) return "win32";
    else version (FreeBSD) return "freebsd";
    else return "unknown";
}

string archStr() pure @safe nothrow
{
    version (X86_64) return "x64";
    else version (X86) return "ia32";
    else version (AArch64) return "arm64";
    else version (ARM) return "arm";
    else return "unknown";
}

JSHandle jsOsPlatform(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    return engine.newString(platformStr());
}

JSHandle jsOsArch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    return engine.newString(archStr());
}

JSHandle jsOsType(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux) return engine.newString("Linux");
    else version (OSX) return engine.newString("Darwin");
    else version (Windows) return engine.newString("Windows_NT");
    else return engine.newString("Unknown");
}

JSHandle jsOsHostname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    try
    {
        import std.process : environment;
        auto name = environment.get("HOSTNAME", "");
        if (name.length == 0)
        {
            version (Posix)
            {
                import core.sys.posix.unistd : gethostname;
                char[HOSTNAME_BUF_SIZE] buf;
                if (gethostname(buf.ptr, buf.length) == 0)
                {
                    import core.stdc.string : strlen;
                    name = cast(string) buf[0 .. strlen(buf.ptr)].idup;
                }
            }
        }
        return engine.newString(name);
    }
    catch (Exception) { return engine.newString(""); }
}

JSHandle jsOsHomedir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    try
    {
        import std.process : environment;
        version (Windows)
            auto home = environment.get("USERPROFILE", "");
        else
            auto home = environment.get("HOME", "");
        return engine.newString(home);
    }
    catch (Exception) { return engine.newString(""); }
}

JSHandle jsOsTmpdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    try
    {
        import std.file : tempDir;
        return engine.newString(tempDir());
    }
    catch (Exception) { return engine.newString("/tmp"); }
}

JSHandle jsOsCpus(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    auto arr = engine.newArray();
    try
    {
        import std.parallelism : totalCPUs;
        int cpuCount = totalCPUs;
        for (int i = 0; i < cpuCount; i++)
        {
            import std.conv : to;
            auto cpuObj = engine.newObject();
            engine.setProperty(cpuObj, "model", engine.newString("cpu"));
            engine.setProperty(cpuObj, "speed", engine.newInt(0));
            auto times = engine.newObject();
            engine.setProperty(times, "user", engine.newInt(0));
            engine.setProperty(times, "nice", engine.newInt(0));
            engine.setProperty(times, "sys", engine.newInt(0));
            engine.setProperty(times, "idle", engine.newInt(0));
            engine.setProperty(times, "irq", engine.newInt(0));
            engine.setProperty(cpuObj, "times", times);
            engine.setPropertyIndex(arr, cast(uint) i, cpuObj);
        }
    }
    catch (Exception) {}
    return arr;
}

JSHandle jsOsTotalmem(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import std.file : readText;
            import std.string : indexOf;
            auto info = readText("/proc/meminfo");
            auto idx = info.indexOf("MemTotal:");
            if (idx >= 0)
            {
                auto line = info[idx .. $];
                auto end = line.indexOf("\n");
                if (end > 0) line = line[0 .. end];
                import std.string : strip;
                import std.array : split;
                auto parts = line.split();
                if (parts.length >= 2)
                {
                    import std.conv : to;
                    long kb = parts[1].to!long;
                    return engine.newFloat(cast(double)(kb * 1024));
                }
            }
        }
        catch (Exception) {}
    }
    return engine.newFloat(0);
}

JSHandle jsOsFreemem(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import std.file : readText;
            import std.string : indexOf;
            auto info = readText("/proc/meminfo");
            auto idx = info.indexOf("MemAvailable:");
            if (idx >= 0)
            {
                auto line = info[idx .. $];
                auto end = line.indexOf("\n");
                if (end > 0) line = line[0 .. end];
                import std.array : split;
                auto parts = line.split();
                if (parts.length >= 2)
                {
                    import std.conv : to;
                    long kb = parts[1].to!long;
                    return engine.newFloat(cast(double)(kb * 1024));
                }
            }
        }
        catch (Exception) {}
    }
    return engine.newFloat(0);
}

JSHandle jsOsUptime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import std.file : readText;
            import std.array : split;
            import std.conv : to;
            auto content = readText("/proc/uptime");
            auto parts = content.split();
            if (parts.length >= 1)
                return engine.newFloat(parts[0].to!double);
        }
        catch (Exception) {}
    }
    return engine.newFloat(0);
}

JSHandle jsOsRelease(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import core.sys.posix.sys.utsname : utsname, uname;
            utsname buf;
            if (uname(&buf) == 0)
            {
                import core.stdc.string : strlen;
                auto p = buf.release.ptr;
                return engine.newString(cast(string) p[0 .. strlen(p)].idup);
            }
        }
        catch (Exception) {}
    }
    return engine.newString("");
}

JSHandle jsOsEndianness(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (LittleEndian)
        return engine.newString("LE");
    else
        return engine.newString("BE");
}

JSHandle jsOsNetworkInterfaces(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsOsNetworkInterfaces");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsOsNetworkInterfaces");
    // Stub: return empty object (ifaddrs not available in D runtime)
    return state.engine.newObject();
}

JSHandle jsOsUserInfo(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    auto obj = engine.newObject();
    version (Posix)
    {
        try
        {
            import core.sys.posix.unistd : getuid, getgid;
            import core.sys.posix.pwd : getpwuid;
            import core.stdc.string : strlen;
            import std.process : environment;

            auto uid = getuid();
            auto gid = getgid();
            engine.setProperty(obj, "uid", engine.newInt(cast(int) uid));
            engine.setProperty(obj, "gid", engine.newInt(cast(int) gid));

            auto pw = getpwuid(uid);
            if (pw !is null)
            {
                auto name = cast(string) pw.pw_name[0 .. strlen(pw.pw_name)].idup;
                auto dir = cast(string) pw.pw_dir[0 .. strlen(pw.pw_dir)].idup;
                auto shell = cast(string) pw.pw_shell[0 .. strlen(pw.pw_shell)].idup;
                engine.setProperty(obj, "username", engine.newString(name));
                engine.setProperty(obj, "homedir", engine.newString(dir));
                engine.setProperty(obj, "shell", engine.newString(shell));
            }
            else
            {
                engine.setProperty(obj, "username", engine.newString(environment.get("USER", "")));
                engine.setProperty(obj, "homedir", engine.newString(environment.get("HOME", "")));
                engine.setProperty(obj, "shell", engine.newString(environment.get("SHELL", "/bin/sh")));
            }
        }
        catch (Exception)
        {
            engine.setProperty(obj, "uid", engine.newInt(-1));
            engine.setProperty(obj, "gid", engine.newInt(-1));
            engine.setProperty(obj, "username", engine.newString(""));
            engine.setProperty(obj, "homedir", engine.newString(""));
            engine.setProperty(obj, "shell", engine.newString(""));
        }
    }
    else
    {
        engine.setProperty(obj, "uid", engine.newInt(-1));
        engine.setProperty(obj, "gid", engine.newInt(-1));
        engine.setProperty(obj, "username", engine.newString(""));
        engine.setProperty(obj, "homedir", engine.newString(""));
        engine.setProperty(obj, "shell", engine.newString(""));
    }
    return obj;
}

JSHandle jsOsLoadavg(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    auto arr = engine.newArray();
    version (linux)
    {
        try
        {
            import std.file : readText;
            import std.array : split;
            import std.conv : to;
            auto content = readText("/proc/loadavg");
            auto parts = content.split();
            if (parts.length >= 3)
            {
                engine.setPropertyIndex(arr, 0, engine.newFloat(parts[0].to!double));
                engine.setPropertyIndex(arr, 1, engine.newFloat(parts[1].to!double));
                engine.setPropertyIndex(arr, 2, engine.newFloat(parts[2].to!double));
                return arr;
            }
        }
        catch (Exception) {}
    }
    engine.setPropertyIndex(arr, 0, engine.newFloat(0));
    engine.setPropertyIndex(arr, 1, engine.newFloat(0));
    engine.setPropertyIndex(arr, 2, engine.newFloat(0));
    return arr;
}

JSHandle jsOsVersion(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import core.sys.posix.sys.utsname : utsname, uname;
            utsname buf;
            if (uname(&buf) == 0)
            {
                import core.stdc.string : strlen;
                auto p = buf.release.ptr;
                return engine.newString(cast(string) p[0 .. strlen(p)].idup);
            }
        }
        catch (Exception) {}
    }
    return engine.newString("");
}

JSHandle jsOsMachine(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (linux)
    {
        try
        {
            import core.sys.posix.sys.utsname : utsname, uname;
            utsname buf;
            if (uname(&buf) == 0)
            {
                import core.stdc.string : strlen;
                auto p = buf.machine.ptr;
                return engine.newString(cast(string) p[0 .. strlen(p)].idup);
            }
        }
        catch (Exception) {}
    }
    version (X86_64) return engine.newString("x86_64");
    else version (AArch64) return engine.newString("aarch64");
    else return engine.newString("unknown");
}

JSHandle jsOsAvailableParallelism(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    try
    {
        import std.parallelism : totalCPUs;
        return engine.newInt(totalCPUs);
    }
    catch (Exception) { return engine.newInt(1); }
}

JSHandle jsOsSetPriority(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (Posix)
    {
        int pid = 0;
        int priority = 0;
        if (args.length >= 2 && engine.isNumber(args[0]) && engine.isNumber(args[1]))
        {
            pid = engine.extractInt(args[0]);
            priority = engine.extractInt(args[1]);
        }
        else if (args.length >= 1 && engine.isNumber(args[0]))
        {
            // os.setPriority(priority) — sets for current process
            priority = engine.extractInt(args[0]);
        }
        else
            return engine.throwTypeError("os.setPriority requires priority argument");

        import core.sys.posix.sys.resource : setpriority, PRIO_PROCESS;
        auto ret = setpriority(PRIO_PROCESS, pid, priority);
        if (ret != 0)
            return engine.throwTypeError("os.setPriority failed");
        return engine.newUndefined();
    }
    else
        return engine.throwTypeError("os.setPriority not supported on this platform");
}

JSHandle jsOsGetPriority(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto engine = getEngine(ctx);
    version (Posix)
    {
        int pid = 0;
        if (args.length >= 1 && engine.isNumber(args[0]))
            pid = engine.extractInt(args[0]);

        import core.sys.posix.sys.resource : getpriority, PRIO_PROCESS;
        import core.stdc.errno : errno;
        errno = 0;
        auto prio = getpriority(PRIO_PROCESS, pid);
        if (prio == -1 && errno != 0)
            return engine.throwTypeError("os.getPriority failed");
        return engine.newInt(prio);
    }
    else
        return engine.newInt(0);
}

string osConstantsSource() pure nothrow @safe
{
    return `(function() {
    return {
        signals: {
            SIGHUP: 1, SIGINT: 2, SIGQUIT: 3, SIGILL: 4, SIGTRAP: 5,
            SIGABRT: 6, SIGBUS: 7, SIGFPE: 8, SIGKILL: 9, SIGUSR1: 10,
            SIGSEGV: 11, SIGUSR2: 12, SIGPIPE: 13, SIGALRM: 14, SIGTERM: 15,
            SIGCHLD: 17, SIGCONT: 18, SIGSTOP: 19, SIGTSTP: 20, SIGTTIN: 21,
            SIGTTOU: 22, SIGURG: 23, SIGXCPU: 24, SIGXFSZ: 25, SIGVTALRM: 26,
            SIGPROF: 27, SIGWINCH: 28, SIGIO: 29, SIGPWR: 30, SIGSYS: 31
        },
        errno: {
            E2BIG: 7, EACCES: 13, EADDRINUSE: 98, EADDRNOTAVAIL: 99,
            EAFNOSUPPORT: 97, EAGAIN: 11, EALREADY: 114, EBADF: 9,
            EBADMSG: 74, EBUSY: 16, ECANCELED: 125, ECHILD: 10,
            ECONNABORTED: 103, ECONNREFUSED: 111, ECONNRESET: 104,
            EDEADLK: 35, EDESTADDRREQ: 89, EDOM: 33, EDQUOT: 122,
            EEXIST: 17, EFAULT: 14, EFBIG: 27, EHOSTUNREACH: 113,
            EIDRM: 43, EILSEQ: 84, EINPROGRESS: 115, EINTR: 4,
            EINVAL: 22, EIO: 5, EISCONN: 106, EISDIR: 21,
            ELOOP: 40, EMFILE: 24, EMLINK: 31, EMSGSIZE: 90,
            ENAMETOOLONG: 36, ENETDOWN: 100, ENETRESET: 102,
            ENETUNREACH: 101, ENFILE: 23, ENOBUFS: 105, ENODATA: 61,
            ENODEV: 19, ENOENT: 2, ENOEXEC: 8, ENOLCK: 37,
            ENOMEM: 12, ENOMSG: 42, ENOPROTOOPT: 92, ENOSPC: 28,
            ENOSYS: 38, ENOTCONN: 107, ENOTDIR: 20, ENOTEMPTY: 39,
            ENOTSOCK: 88, ENOTSUP: 95, ENOTTY: 25, ENXIO: 6,
            EOPNOTSUPP: 95, EOVERFLOW: 75, EPERM: 1, EPIPE: 32,
            EPROTO: 71, EPROTONOSUPPORT: 93, EPROTOTYPE: 91,
            ERANGE: 34, EROFS: 30, ESPIPE: 29, ESRCH: 3,
            ESTALE: 116, ETIMEDOUT: 110, ETXTBSY: 26, EWOULDBLOCK: 11,
            EXDEV: 18
        },
        priority: {
            PRIORITY_LOW: 19,
            PRIORITY_BELOW_NORMAL: 10,
            PRIORITY_NORMAL: 0,
            PRIORITY_ABOVE_NORMAL: -7,
            PRIORITY_HIGH: -14,
            PRIORITY_HIGHEST: -20
        }
    };
})()`;
}
