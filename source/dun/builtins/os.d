module dun.builtins.os;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerOsModule(IJSEngine engine) @trusted
{
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
    engine.setProperty(obj, "EOL", engine.newString(eol()));
    engine.setProperty(obj, "devNull", engine.newString(devNull()));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_os__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:os", &osModuleInit);
        if (m is null) return;
        foreach (name; ["platform", "arch", "type", "hostname", "homedir",
                        "tmpdir", "cpus", "totalmem", "freemem", "uptime",
                        "release", "endianness", "EOL", "devNull"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int osModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto osObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_os__");
        foreach (name; ["platform", "arch", "type", "hostname", "homedir",
                        "tmpdir", "cpus", "totalmem", "freemem", "uptime",
                        "release", "endianness", "EOL", "devNull"])
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

JSHandle jsOsPlatform(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    return engine.newString(platformStr());
}

JSHandle jsOsArch(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    return engine.newString(archStr());
}

JSHandle jsOsType(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    version (linux) return engine.newString("Linux");
    else version (OSX) return engine.newString("Darwin");
    else version (Windows) return engine.newString("Windows_NT");
    else return engine.newString("Unknown");
}

JSHandle jsOsHostname(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    try
    {
        import std.process : environment;
        auto name = environment.get("HOSTNAME", "");
        if (name.length == 0)
        {
            version (Posix)
            {
                import core.sys.posix.unistd : gethostname;
                char[256] buf;
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

JSHandle jsOsHomedir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsTmpdir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    try
    {
        import std.file : tempDir;
        return engine.newString(tempDir());
    }
    catch (Exception) { return engine.newString("/tmp"); }
}

JSHandle jsOsCpus(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsTotalmem(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsFreemem(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsUptime(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsRelease(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
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

JSHandle jsOsEndianness(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto engine = (cast(DunState*) ctx).engine;
    version (LittleEndian)
        return engine.newString("LE");
    else
        return engine.newString("BE");
}
