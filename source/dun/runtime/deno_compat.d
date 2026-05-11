module dun.runtime.deno_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void installDenoCompat(IJSEngine engine) @trusted
{
    auto denoObj = engine.newObject();

    // Deno.version
    auto versionObj = engine.newObject();
    engine.setProperty(versionObj, "deno", engine.newString("0.0.0"));
    engine.setProperty(versionObj, "v8", engine.newString("0.0.0"));
    engine.setProperty(versionObj, "typescript", engine.newString("5.0.0"));
    engine.setProperty(denoObj, "version", versionObj);

    // Deno.build
    auto buildObj = engine.newObject();
    version (linux) engine.setProperty(buildObj, "os", engine.newString("linux"));
    else version (OSX) engine.setProperty(buildObj, "os", engine.newString("darwin"));
    else version (Windows) engine.setProperty(buildObj, "os", engine.newString("windows"));
    else engine.setProperty(buildObj, "os", engine.newString("unknown"));
    version (X86_64) engine.setProperty(buildObj, "arch", engine.newString("x86_64"));
    else version (AArch64) engine.setProperty(buildObj, "arch", engine.newString("aarch64"));
    else engine.setProperty(buildObj, "arch", engine.newString("unknown"));
    engine.setProperty(denoObj, "build", buildObj);

    // Deno.env.get / Deno.env.set / Deno.env.toObject
    auto envObj = engine.newObject();
    engine.setProperty(envObj, "get", engine.newFunction(&denoEnvGet, "get", 1));
    engine.setProperty(envObj, "toObject", engine.newFunction(&denoEnvToObject, "toObject", 0));
    engine.setProperty(denoObj, "env", envObj);

    // Deno.readTextFileSync
    engine.setProperty(denoObj, "readTextFileSync",
        engine.newFunction(&denoReadTextFileSync, "readTextFileSync", 1));

    // Deno.writeTextFileSync
    engine.setProperty(denoObj, "writeTextFileSync",
        engine.newFunction(&denoWriteTextFileSync, "writeTextFileSync", 2));

    // Deno.readFileSync (returns Uint8Array-like, we return string for now)
    engine.setProperty(denoObj, "readFileSync",
        engine.newFunction(&denoReadTextFileSync, "readFileSync", 1));

    // Deno.cwd
    engine.setProperty(denoObj, "cwd",
        engine.newFunction(&denoCwd, "cwd", 0));

    // Deno.exit
    engine.setProperty(denoObj, "exit",
        engine.newFunction(&denoExit, "exit", 1));

    // Deno.args
    engine.setProperty(denoObj, "args", engine.newArray());

    // Deno.pid
    version (Posix)
    {
        import core.sys.posix.unistd : getpid;
        engine.setProperty(denoObj, "pid", engine.newInt(getpid()));
    }

    auto global = engine.getGlobal();
    engine.setProperty(global, "Deno", denoObj);
    engine.freeValue(global);
}

private:

JSHandle denoEnvGet(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newUndefined();

    try
    {
        if (!state.permissions.check(Permission.env))
            return engine.throwTypeError("Requires --allow-env");
    }
    catch (Exception) { return engine.throwTypeError("Permission check failed"); }

    string key = engine.extractString(args[0]);
    try
    {
        import std.process : environment;
        string val = environment.get(key, null);
        if (val is null) return engine.newUndefined();
        return engine.newString(val);
    }
    catch (Exception) { return engine.newUndefined(); }
}

JSHandle denoEnvToObject(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    try
    {
        if (!state.permissions.check(Permission.env))
            return engine.throwTypeError("Requires --allow-env");
    }
    catch (Exception) { return engine.throwTypeError("Permission check failed"); }

    auto obj = engine.newObject();
    try
    {
        import std.process : environment;
        foreach (k, v; environment.toAA())
            engine.setProperty(obj, k, engine.newString(v));
    }
    catch (Exception) {}
    return obj;
}

JSHandle denoReadTextFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readTextFileSync requires a path");

    string path = engine.extractString(args[0]);
    try
    {
        if (!state.permissions.check(Permission.read, path))
            return engine.throwTypeError("Requires --allow-read");
    }
    catch (Exception) { return engine.throwTypeError("Permission check failed"); }

    try
    {
        import std.file : readText;
        return engine.newString(readText(path));
    }
    catch (Exception e)
    {
        return engine.throwTypeError("readTextFileSync: " ~ e.msg);
    }
}

JSHandle denoWriteTextFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("writeTextFileSync requires (path, data)");

    string path = engine.extractString(args[0]);
    string data = engine.extractString(args[1]);

    try
    {
        if (!state.permissions.check(Permission.write, path))
            return engine.throwTypeError("Requires --allow-write");
    }
    catch (Exception) { return engine.throwTypeError("Permission check failed"); }

    try
    {
        import std.file : write;
        write(path, data);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("writeTextFileSync: " ~ e.msg);
    }
}

JSHandle denoCwd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
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

JSHandle denoExit(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
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
