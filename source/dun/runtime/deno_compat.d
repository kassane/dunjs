module dun.runtime.deno_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback, PromiseHandles;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission, PermissionState;

void installDenoCompat(IJSEngine engine) @trusted
{
    auto denoObj = engine.newObject();

    // Deno.version
    auto versionObj = engine.newObject();
    engine.setProperty(versionObj, "deno", engine.newString("1.46.0"));
    engine.setProperty(versionObj, "v8", engine.newString("12.9.202.13"));
    engine.setProperty(versionObj, "typescript", engine.newString("5.6.2"));
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
    engine.setProperty(buildObj, "target", engine.newString(buildTarget()));
    engine.setProperty(buildObj, "vendor", engine.newString("dun"));
    engine.setProperty(denoObj, "build", buildObj);

    // Deno.env
    auto envObj = engine.newObject();
    engine.setProperty(envObj, "get", engine.newFunction(&denoEnvGet, "get", 1));
    engine.setProperty(envObj, "set", engine.newFunction(&denoEnvSet, "set", 2));
    engine.setProperty(envObj, "delete", engine.newFunction(&denoEnvDelete, "delete", 1));
    engine.setProperty(envObj, "has", engine.newFunction(&denoEnvHas, "has", 1));
    engine.setProperty(envObj, "toObject", engine.newFunction(&denoEnvToObject, "toObject", 0));
    engine.setProperty(denoObj, "env", envObj);

    // Deno.readTextFileSync / Deno.readTextFile
    engine.setProperty(denoObj, "readTextFileSync",
        engine.newFunction(&denoReadTextFileSync, "readTextFileSync", 1));
    engine.setProperty(denoObj, "readTextFile",
        engine.newFunction(&denoReadTextFile, "readTextFile", 1));

    // Deno.writeTextFileSync / Deno.writeTextFile
    engine.setProperty(denoObj, "writeTextFileSync",
        engine.newFunction(&denoWriteTextFileSync, "writeTextFileSync", 2));
    engine.setProperty(denoObj, "writeTextFile",
        engine.newFunction(&denoWriteTextFile, "writeTextFile", 2));

    // Deno.readFileSync (returns string for now, should be Uint8Array)
    engine.setProperty(denoObj, "readFileSync",
        engine.newFunction(&denoReadTextFileSync, "readFileSync", 1));

    // Deno.statSync / Deno.lstatSync
    engine.setProperty(denoObj, "statSync",
        engine.newFunction(&denoStatSync, "statSync", 1));
    engine.setProperty(denoObj, "lstatSync",
        engine.newFunction(&denoStatSync, "lstatSync", 1));

    // Deno.mkdirSync
    engine.setProperty(denoObj, "mkdirSync",
        engine.newFunction(&denoMkdirSync, "mkdirSync", 1));

    // Deno.removeSync
    engine.setProperty(denoObj, "removeSync",
        engine.newFunction(&denoRemoveSync, "removeSync", 1));

    // Deno.renameSync
    engine.setProperty(denoObj, "renameSync",
        engine.newFunction(&denoRenameSync, "renameSync", 2));

    // Deno.copyFileSync
    engine.setProperty(denoObj, "copyFileSync",
        engine.newFunction(&denoCopyFileSync, "copyFileSync", 2));

    // Deno.readDirSync
    engine.setProperty(denoObj, "readDirSync",
        engine.newFunction(&denoReadDirSync, "readDirSync", 1));

    // Deno.realPathSync
    engine.setProperty(denoObj, "realPathSync",
        engine.newFunction(&denoRealPathSync, "realPathSync", 1));

    // Deno.truncateSync
    engine.setProperty(denoObj, "truncateSync",
        engine.newFunction(&denoTruncateSync, "truncateSync", 2));

    // Deno.cwd / Deno.chdir
    engine.setProperty(denoObj, "cwd",
        engine.newFunction(&denoCwd, "cwd", 0));
    engine.setProperty(denoObj, "chdir",
        engine.newFunction(&denoChdir, "chdir", 1));

    // Deno.exit
    engine.setProperty(denoObj, "exit",
        engine.newFunction(&denoExit, "exit", 1));

    // Deno.hostname
    engine.setProperty(denoObj, "hostname",
        engine.newFunction(&denoHostname, "hostname", 0));

    // Deno.args
    engine.setProperty(denoObj, "args", engine.newArray());

    // Deno.pid / Deno.ppid
    version (Posix)
    {
        import core.sys.posix.unistd : getpid, getppid;
        engine.setProperty(denoObj, "pid", engine.newInt(getpid()));
        engine.setProperty(denoObj, "ppid", engine.newInt(getppid()));
    }

    // Deno.noColor
    engine.setProperty(denoObj, "noColor", engine.newBool(noColorEnabled()));

    // Deno.mainModule (set by CLI before script execution)
    engine.setProperty(denoObj, "mainModule", engine.newString(""));

    // Deno.permissions
    auto permsObj = engine.newObject();
    engine.setProperty(permsObj, "query", engine.newFunction(&denoPermissionsQuery, "query", 1));
    engine.setProperty(denoObj, "permissions", permsObj);

    // Deno.inspect
    engine.setProperty(denoObj, "inspect",
        engine.newFunction(&denoInspect, "inspect", 1));

    // Deno.errors
    auto errorsObj = engine.newObject();
    engine.setProperty(errorsObj, "NotFound", engine.newObject());
    engine.setProperty(errorsObj, "PermissionDenied", engine.newObject());
    engine.setProperty(errorsObj, "AlreadyExists", engine.newObject());
    engine.setProperty(errorsObj, "InvalidData", engine.newObject());
    engine.setProperty(errorsObj, "TimedOut", engine.newObject());
    engine.setProperty(errorsObj, "ConnectionRefused", engine.newObject());
    engine.setProperty(errorsObj, "ConnectionReset", engine.newObject());
    engine.setProperty(errorsObj, "NotConnected", engine.newObject());
    engine.setProperty(errorsObj, "AddrInUse", engine.newObject());
    engine.setProperty(errorsObj, "AddrNotAvailable", engine.newObject());
    engine.setProperty(errorsObj, "BrokenPipe", engine.newObject());
    engine.setProperty(errorsObj, "WriteZero", engine.newObject());
    engine.setProperty(errorsObj, "UnexpectedEof", engine.newObject());
    engine.setProperty(errorsObj, "BadResource", engine.newObject());
    engine.setProperty(errorsObj, "Busy", engine.newObject());
    engine.setProperty(denoObj, "errors", errorsObj);

    auto global = engine.getGlobal();
    engine.setProperty(global, "Deno", denoObj);
    engine.freeValue(global);
}

private:

string buildTarget() pure @safe nothrow
{
    version (linux)
    {
        version (X86_64) return "x86_64-unknown-linux-gnu";
        else version (AArch64) return "aarch64-unknown-linux-gnu";
        else return "unknown-unknown-linux-gnu";
    }
    else version (OSX)
    {
        version (X86_64) return "x86_64-apple-darwin";
        else version (AArch64) return "aarch64-apple-darwin";
        else return "unknown-apple-darwin";
    }
    else version (Windows)
    {
        return "x86_64-pc-windows-msvc";
    }
    else return "unknown-unknown-unknown";
}

bool noColorEnabled() @trusted nothrow
{
    try
    {
        import std.process : environment;
        return environment.get("NO_COLOR", null) !is null;
    }
    catch (Exception) { return false; }
}

bool checkPerm(DunState* state, Permission perm, string resource = "") @trusted nothrow
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

// ── Deno.env ──

JSHandle denoEnvGet(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newUndefined();

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

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

JSHandle denoEnvSet(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("env.set requires (key, value)");

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        environment[engine.extractString(args[0])] = engine.extractString(args[1]);
        return engine.newUndefined();
    }
    catch (Exception e) { return engine.throwTypeError("env.set: " ~ e.msg); }
}

JSHandle denoEnvDelete(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("env.delete requires a key");

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        environment.remove(engine.extractString(args[0]));
        return engine.newUndefined();
    }
    catch (Exception e) { return engine.throwTypeError("env.delete: " ~ e.msg); }
}

JSHandle denoEnvHas(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newBool(false);

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        return engine.newBool(environment.get(engine.extractString(args[0]), null) !is null);
    }
    catch (Exception) { return engine.newBool(false); }
}

JSHandle denoEnvToObject(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

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

// ── Deno.readTextFileSync / readTextFile ──

JSHandle denoReadTextFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readTextFileSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

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

JSHandle denoReadTextFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.loop.async : asyncSubmit;

    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readTextFile requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        import std.file : readText;
        return readText(path);
    });

    return ph.promise;
}

// ── Deno.writeTextFileSync / writeTextFile ──

JSHandle denoWriteTextFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("writeTextFileSync requires (path, data)");

    string path = engine.extractString(args[0]);
    string data = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

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

JSHandle denoWriteTextFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.loop.async : asyncSubmit;

    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("writeTextFile requires (path, data)");

    string path = engine.extractString(args[0]);
    string data = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        import std.file : write;
        write(path, data);
        return "ok";
    });

    return ph.promise;
}

// ── Deno.statSync ──

JSHandle denoStatSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("statSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : exists, isFile, isDir, isSymlink, getSize, timeLastModified;
        if (!exists(path))
            return engine.throwTypeError("No such file or directory: " ~ path);

        bool pathIsFile, pathIsDir, pathIsSym;
        ulong fileSize;
        long mtimeMs;
        try { pathIsFile = isFile(path); } catch (Exception) {}
        try { pathIsDir = isDir(path); } catch (Exception) {}
        try { pathIsSym = isSymlink(path); } catch (Exception) {}
        try { fileSize = getSize(path); } catch (Exception) {}
        try { mtimeMs = timeLastModified(path).toUnixTime!long * 1000L; } catch (Exception) {}

        auto obj = engine.newObject();
        engine.setProperty(obj, "isFile", engine.newBool(pathIsFile));
        engine.setProperty(obj, "isDirectory", engine.newBool(pathIsDir));
        engine.setProperty(obj, "isSymlink", engine.newBool(pathIsSym));
        engine.setProperty(obj, "size", engine.newFloat(cast(double) fileSize));
        engine.setProperty(obj, "mtime", engine.newFloat(cast(double) mtimeMs));
        engine.setProperty(obj, "atime", engine.newNull());
        engine.setProperty(obj, "birthtime", engine.newNull());
        engine.setProperty(obj, "dev", engine.newNull());
        engine.setProperty(obj, "ino", engine.newNull());
        engine.setProperty(obj, "mode", engine.newNull());
        engine.setProperty(obj, "nlink", engine.newNull());
        engine.setProperty(obj, "uid", engine.newNull());
        engine.setProperty(obj, "gid", engine.newNull());
        engine.setProperty(obj, "rdev", engine.newNull());
        engine.setProperty(obj, "blksize", engine.newNull());
        engine.setProperty(obj, "blocks", engine.newNull());
        engine.setProperty(obj, "isBlockDevice", engine.newNull());
        engine.setProperty(obj, "isCharDevice", engine.newNull());
        engine.setProperty(obj, "isFifo", engine.newNull());
        engine.setProperty(obj, "isSocket", engine.newNull());
        return obj;
    }
    catch (Exception e)
    {
        return engine.throwTypeError("statSync: " ~ e.msg);
    }
}

// ── Deno.mkdirSync ──

JSHandle denoMkdirSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("mkdirSync requires a path");

    string path = engine.extractString(args[0]);
    bool recursive = false;

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        if (engine.isBool(rv)) recursive = engine.extractBool(rv);
    }

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : mkdir, mkdirRecurse;
        if (recursive) mkdirRecurse(path); else mkdir(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("mkdirSync: " ~ e.msg);
    }
}

// ── Deno.removeSync ──

JSHandle denoRemoveSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("removeSync requires a path");

    string path = engine.extractString(args[0]);
    bool recursive = false;

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        if (engine.isBool(rv)) recursive = engine.extractBool(rv);
    }

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : remove, rmdirRecurse, isDir;
        if (recursive && isDir(path))
            rmdirRecurse(path);
        else
            remove(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("removeSync: " ~ e.msg);
    }
}

// ── Deno.renameSync ──

JSHandle denoRenameSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("renameSync requires (oldpath, newpath)");

    string oldpath = engine.extractString(args[0]);
    string newpath = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.read, oldpath))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");
    if (!checkPerm(state, Permission.write, newpath))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : rename;
        rename(oldpath, newpath);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("renameSync: " ~ e.msg);
    }
}

// ── Deno.copyFileSync ──

JSHandle denoCopyFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("copyFileSync requires (src, dest)");

    string src = engine.extractString(args[0]);
    string dest = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.read, src))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");
    if (!checkPerm(state, Permission.write, dest))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : copy;
        copy(src, dest);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("copyFileSync: " ~ e.msg);
    }
}

// ── Deno.readDirSync ──

JSHandle denoReadDirSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readDirSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : dirEntries, SpanMode, isFile, isDir, isSymlink;
        import std.path : baseName;
        import std.conv : to;

        auto arr = engine.newArray();
        uint idx = 0;
        foreach (entry; dirEntries(path, SpanMode.shallow))
        {
            auto entryObj = engine.newObject();
            engine.setProperty(entryObj, "name", engine.newString(baseName(entry.name)));
            bool eIsFile, eIsDir, eIsSym;
            try { eIsFile = isFile(entry.name); } catch (Exception) {}
            try { eIsDir = isDir(entry.name); } catch (Exception) {}
            try { eIsSym = isSymlink(entry.name); } catch (Exception) {}
            engine.setProperty(entryObj, "isFile", engine.newBool(eIsFile));
            engine.setProperty(entryObj, "isDirectory", engine.newBool(eIsDir));
            engine.setProperty(entryObj, "isSymlink", engine.newBool(eIsSym));
            engine.setProperty(arr, (idx++).to!string, entryObj);
        }
        return arr;
    }
    catch (Exception e)
    {
        return engine.throwTypeError("readDirSync: " ~ e.msg);
    }
}

// ── Deno.realPathSync ──

JSHandle denoRealPathSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("realPathSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.path : absolutePath;
        import std.file : getcwd;
        return engine.newString(absolutePath(path, getcwd()));
    }
    catch (Exception e)
    {
        return engine.throwTypeError("realPathSync: " ~ e.msg);
    }
}

// ── Deno.truncateSync ──

JSHandle denoTruncateSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("truncateSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : write;
        write(path, "");
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("truncateSync: " ~ e.msg);
    }
}

// ── Deno.cwd / Deno.chdir ──

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

JSHandle denoChdir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("chdir requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : chdir;
        chdir(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("chdir: " ~ e.msg);
    }
}

// ── Deno.exit ──

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

// ── Deno.hostname ──

JSHandle denoHostname(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    try
    {
        version (Posix)
        {
            import core.sys.posix.unistd : gethostname;
            char[256] buf;
            if (gethostname(buf.ptr, buf.length) == 0)
            {
                import std.string : fromStringz;
                return engine.newString(cast(string) fromStringz(buf.ptr));
            }
        }
        version (Windows)
        {
            import std.process : environment;
            auto name = environment.get("COMPUTERNAME", "localhost");
            return engine.newString(name);
        }
        return engine.newString("localhost");
    }
    catch (Exception) { return engine.newString("localhost"); }
}

// ── Deno.permissions.query ──

JSHandle denoPermissionsQuery(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.throwTypeError("permissions.query requires a descriptor object");

    auto nameVal = engine.getProperty(args[0], "name");
    if (!engine.isString(nameVal))
        return engine.throwTypeError("descriptor.name must be a string");

    string name = engine.extractString(nameVal);
    Permission perm;
    string stateStr;

    if (name == "read") perm = Permission.read;
    else if (name == "write") perm = Permission.write;
    else if (name == "net") perm = Permission.net;
    else if (name == "env") perm = Permission.env;
    else if (name == "run") perm = Permission.run;
    else if (name == "ffi") perm = Permission.ffi;
    else if (name == "hrtime") perm = Permission.hrtime;
    else
    {
        stateStr = "prompt";
        goto makeResult;
    }

    stateStr = checkPerm(state, perm) ? "granted" : "prompt";

makeResult:
    auto ph = engine.newPromise();
    auto resultObj = engine.newObject();
    engine.setProperty(resultObj, "state", engine.newString(stateStr));
    engine.callFunction(ph.resolve, engine.newUndefined(), [resultObj]);
    engine.freeValue(ph.resolve);
    engine.freeValue(ph.reject);
    return ph.promise;
}

// ── Deno.inspect ──

JSHandle denoInspect(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("undefined");

    if (engine.isString(args[0]))
        return engine.newString("\"" ~ engine.extractString(args[0]) ~ "\"");
    if (engine.isNumber(args[0]))
    {
        import std.conv : to;
        return engine.newString(engine.extractFloat(args[0]).to!string);
    }
    if (engine.isBool(args[0]))
        return engine.newString(engine.extractBool(args[0]) ? "true" : "false");
    if (engine.isNull(args[0]))
        return engine.newString("null");
    if (engine.isUndefined(args[0]))
        return engine.newString("undefined");

    return engine.newString("[Object]");
}
