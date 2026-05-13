module dun.builtins.fs;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

private enum : size_t {
    READLINK_BUF_SIZE = 4096,
    MAX_READ_LENGTH   = 64 * 1024 * 1024,
}

// POSIX functions not in all druntime builds (e.g. musl/Alpine)
private extern(C) nothrow @nogc
{
    int truncate(const(char)* path, long length);
    int fdatasync(int fd);
}

void registerFsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerFsModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "readFileSync", engine.newFunction(&jsReadFileSync, "readFileSync", 1));
    engine.setProperty(obj, "writeFileSync", engine.newFunction(&jsWriteFileSync, "writeFileSync", 2));
    engine.setProperty(obj, "existsSync", engine.newFunction(&jsExistsSync, "existsSync", 1));
    engine.setProperty(obj, "readdirSync", engine.newFunction(&jsReaddirSync, "readdirSync", 1));
    engine.setProperty(obj, "statSync", engine.newFunction(&jsStatSync, "statSync", 1));
    engine.setProperty(obj, "mkdirSync", engine.newFunction(&jsMkdirSync, "mkdirSync", 1));
    engine.setProperty(obj, "unlinkSync", engine.newFunction(&jsUnlinkSync, "unlinkSync", 1));
    engine.setProperty(obj, "readFile", engine.newFunction(&jsReadFileAsync, "readFile", 1));
    engine.setProperty(obj, "writeFile", engine.newFunction(&jsWriteFileAsync, "writeFile", 2));
    engine.setProperty(obj, "appendFileSync", engine.newFunction(&jsAppendFileSync, "appendFileSync", 2));
    engine.setProperty(obj, "copyFileSync", engine.newFunction(&jsCopyFileSync, "copyFileSync", 2));
    engine.setProperty(obj, "renameSync", engine.newFunction(&jsRenameSync, "renameSync", 2));
    engine.setProperty(obj, "rmdirSync", engine.newFunction(&jsRmdirSync, "rmdirSync", 1));
    engine.setProperty(obj, "rmSync", engine.newFunction(&jsRmSync, "rmSync", 1));
    engine.setProperty(obj, "accessSync", engine.newFunction(&jsAccessSync, "accessSync", 1));
    engine.setProperty(obj, "realpathSync", engine.newFunction(&jsRealpathSync, "realpathSync", 1));
    engine.setProperty(obj, "chmodSync", engine.newFunction(&jsChmodSync, "chmodSync", 2));
    engine.setProperty(obj, "lstatSync", engine.newFunction(&jsLstatSync, "lstatSync", 1));
    engine.setProperty(obj, "linkSync", engine.newFunction(&jsLinkSync, "linkSync", 2));
    engine.setProperty(obj, "symlinkSync", engine.newFunction(&jsSymlinkSync, "symlinkSync", 2));
    engine.setProperty(obj, "readlinkSync", engine.newFunction(&jsReadlinkSync, "readlinkSync", 1));
    engine.setProperty(obj, "truncateSync", engine.newFunction(&jsTruncateSync, "truncateSync", 2));
    engine.setProperty(obj, "chownSync", engine.newFunction(&jsChownSync, "chownSync", 3));
    engine.setProperty(obj, "openSync", engine.newFunction(&jsOpenSync, "openSync", 2));
    engine.setProperty(obj, "closeSync", engine.newFunction(&jsCloseSync, "closeSync", 1));
    engine.setProperty(obj, "readSync", engine.newFunction(&jsReadSync, "readSync", 2));
    engine.setProperty(obj, "writeSync", engine.newFunction(&jsWriteSync, "writeSync", 2));
    engine.setProperty(obj, "fstatSync", engine.newFunction(&jsFstatSync, "fstatSync", 1));
    engine.setProperty(obj, "fsyncSync", engine.newFunction(&jsFsyncSync, "fsyncSync", 1));
    engine.setProperty(obj, "fdatasyncSync", engine.newFunction(&jsFdatasyncSync, "fdatasyncSync", 1));
    engine.setProperty(obj, "createReadStream", engine.newFunction(&jsCreateReadStream, "createReadStream", 1));
    engine.setProperty(obj, "createWriteStream", engine.newFunction(&jsCreateWriteStream, "createWriteStream", 1));
    engine.setProperty(obj, "watch", engine.newFunction(&jsWatch, "watch", 2));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_fs__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;
    import dun.engine.quickjs.function_bind;

    private enum fsExports = [
        "readFileSync", "writeFileSync", "existsSync", "readdirSync",
        "statSync", "mkdirSync", "unlinkSync", "readFile", "writeFile",
        "appendFileSync", "copyFileSync", "renameSync", "rmdirSync",
        "rmSync", "accessSync", "realpathSync", "chmodSync",
        "lstatSync", "linkSync", "symlinkSync", "readlinkSync",
        "truncateSync", "chownSync", "openSync", "closeSync",
        "readSync", "writeSync", "fstatSync", "fsyncSync",
        "fdatasyncSync", "createReadStream", "createWriteStream", "watch"
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:fs", &fsModuleInit);
        if (m is null) return;
        foreach (name; fsExports)
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int fsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in fsModuleInit");
        assert(m !is null, "Null JSModuleDef in fsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto fsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_fs__");
        foreach (name; fsExports)
        {
            auto fn = JS_GetPropertyStr(ctx, fsObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, fsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

import core.sys.posix.sys.stat : stat_t;

// Cached stat method handles — registered once to avoid callback slot exhaustion
__gshared JSHandle _cachedIsFileFn, _cachedIsDirFn, _cachedIsSymlinkFn;
__gshared bool _statFnsCached = false;

void ensureStatFnsCached(IJSEngine engine) @trusted
{
    if (!_statFnsCached)
    {
        _cachedIsFileFn = engine.newFunction(&jsStatIsFile, "isFile", 0);
        _cachedIsDirFn = engine.newFunction(&jsStatIsDirectory, "isDirectory", 0);
        _cachedIsSymlinkFn = engine.newFunction(&jsStatIsSymbolicLink, "isSymbolicLink", 0);
        _statFnsCached = true;
    }
}

JSHandle buildStatFromPosix(IJSEngine engine, ref stat_t buf) @trusted
{
    import core.sys.posix.sys.stat : S_ISREG, S_ISDIR, S_ISLNK;
    auto obj = engine.newObject();
    bool isFile = S_ISREG(buf.st_mode);
    bool isDir = S_ISDIR(buf.st_mode);
    bool isLink = S_ISLNK(buf.st_mode);
    engine.setProperty(obj, "_type", engine.newInt(isFile ? 1 : isDir ? 2 : isLink ? 3 : 0));
    engine.setProperty(obj, "size", engine.newFloat(cast(double) buf.st_size));
    engine.setProperty(obj, "mode", engine.newInt(cast(int)(buf.st_mode & 0xFFFF)));
    engine.setProperty(obj, "uid", engine.newInt(cast(int) buf.st_uid));
    engine.setProperty(obj, "gid", engine.newInt(cast(int) buf.st_gid));
    engine.setProperty(obj, "dev", engine.newFloat(cast(double) buf.st_dev));
    engine.setProperty(obj, "ino", engine.newFloat(cast(double) buf.st_ino));
    engine.setProperty(obj, "nlink", engine.newInt(cast(int) buf.st_nlink));
    engine.setProperty(obj, "atimeMs", engine.newFloat(cast(double)(buf.st_atim.tv_sec * 1000L + buf.st_atim.tv_nsec / 1_000_000L)));
    engine.setProperty(obj, "mtimeMs", engine.newFloat(cast(double)(buf.st_mtim.tv_sec * 1000L + buf.st_mtim.tv_nsec / 1_000_000L)));
    engine.setProperty(obj, "ctimeMs", engine.newFloat(cast(double)(buf.st_ctim.tv_sec * 1000L + buf.st_ctim.tv_nsec / 1_000_000L)));
    ensureStatFnsCached(engine);
    engine.setProperty(obj, "isFile", engine.dupValue(_cachedIsFileFn));
    engine.setProperty(obj, "isDirectory", engine.dupValue(_cachedIsDirFn));
    engine.setProperty(obj, "isSymbolicLink", engine.dupValue(_cachedIsSymlinkFn));
    return obj;
}

bool checkPerm(DunState* state, Permission perm, string resource = "") nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

JSHandle throwSystemError(IJSEngine engine, string syscall, string path, Exception e) @trusted
{
    string msg = "";
    string code = "ERR_FS_ERROR";

    try { msg = e.msg; } catch (Exception) {}

    if (msg.length > 0)
    {
        import std.string : indexOf;
        if (indexOf(msg, "No such file") >= 0 || indexOf(msg, "not found") >= 0
            || indexOf(msg, "cannot find") >= 0)
            code = "ENOENT";
        else if (indexOf(msg, "Permission denied") >= 0 || indexOf(msg, "ccess") >= 0)
            code = "EACCES";
        else if (indexOf(msg, "already exists") >= 0 || indexOf(msg, "File exists") >= 0)
            code = "EEXIST";
        else if (indexOf(msg, "Not a directory") >= 0)
            code = "ENOTDIR";
        else if (indexOf(msg, "Is a directory") >= 0)
            code = "EISDIR";
        else if (indexOf(msg, "not empty") >= 0)
            code = "ENOTEMPTY";
        else if (indexOf(msg, "No space") >= 0)
            code = "ENOSPC";
    }

    return engine.throwTypeError(code ~ ": " ~ msg ~ ", " ~ syscall ~ " '" ~ path ~ "'");
}

JSHandle throwPermError(IJSEngine engine, string perm, string path = "") @trusted
{
    string msg = "Requires --allow-" ~ perm ~ " permission";
    if (path.length > 0)
        msg ~= ", path '" ~ path ~ "'";
    return engine.throwTypeError("[ERR_PERMISSION_DENIED] " ~ msg);
}

JSHandle jsReadFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadFileSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadFileSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readFileSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : readText;
        return engine.newString(readText(path));
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

JSHandle jsWriteFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteFileSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteFileSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("writeFileSync requires path and data");
    auto path = engine.extractString(args[0]);
    auto data = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : write;
        write(path, data);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

JSHandle jsExistsSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsExistsSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsExistsSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("existsSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : exists;
        return engine.newBool(exists(path));
    }
    catch (Exception) { return engine.newBool(false); }
}

JSHandle jsReaddirSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReaddirSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReaddirSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readdirSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : dirEntries, SpanMode;
        import std.path : baseName;
        auto arr = engine.newArray();
        uint idx = 0;
        foreach (entry; dirEntries(path, SpanMode.shallow))
            engine.setPropertyIndex(arr, idx++, engine.newString(baseName(entry.name)));
        return arr;
    }
    catch (Exception e) { return throwSystemError(engine, "scandir", path, e); }
}

JSHandle jsStatSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("statSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : exists, isFile, isDir, getSize, timeLastModified;
        if (!exists(path))
            return engine.throwTypeError("ENOENT: no such file or directory, stat '" ~ path ~ "'");

        bool pathIsFile, pathIsDir;
        ulong fileSize;
        long mtimeMs;
        try { pathIsFile = isFile(path); } catch (Exception) {}
        try { pathIsDir = isDir(path); } catch (Exception) {}
        try { fileSize = getSize(path); } catch (Exception) {}
        try { mtimeMs = timeLastModified(path).toUnixTime!long * 1000L; } catch (Exception) {}

        auto obj = engine.newObject();
        engine.setProperty(obj, "_type", engine.newInt(pathIsFile ? 1 : pathIsDir ? 2 : 0));
        engine.setProperty(obj, "size", engine.newFloat(cast(double) fileSize));
        engine.setProperty(obj, "mtimeMs", engine.newFloat(cast(double) mtimeMs));
        ensureStatFnsCached(engine);
        engine.setProperty(obj, "isFile", engine.dupValue(_cachedIsFileFn));
        engine.setProperty(obj, "isDirectory", engine.dupValue(_cachedIsDirFn));
        engine.setProperty(obj, "isSymbolicLink", engine.dupValue(_cachedIsSymlinkFn));
        return obj;
    }
    catch (Exception e) { return throwSystemError(engine, "stat", path, e); }
}

JSHandle jsStatIsFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsFile");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsFile");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    return engine.newBool(engine.extractInt(typeVal) == 1);
}

JSHandle jsStatIsDirectory(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsDirectory");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsDirectory");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    return engine.newBool(engine.extractInt(typeVal) == 2);
}

JSHandle jsMkdirSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsMkdirSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsMkdirSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("mkdirSync requires a path argument");
    auto path = engine.extractString(args[0]);
    bool recursive = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        recursive = engine.extractBool(rv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : mkdir, mkdirRecurse;
        if (recursive) mkdirRecurse(path); else mkdir(path);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "mkdir", path, e); }
}

JSHandle jsUnlinkSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsUnlinkSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsUnlinkSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("unlinkSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : remove;
        remove(path);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "unlink", path, e); }
}

JSHandle jsReadFileAsync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmit;

    assert(ctx !is null, "Null ctx in jsReadFileAsync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadFileAsync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readFile requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        import std.file : readText;
        return readText(path);
    });

    return ph.promise;
}

JSHandle jsWriteFileAsync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmit;

    assert(ctx !is null, "Null ctx in jsWriteFileAsync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteFileAsync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("writeFile requires path and data");
    auto path = engine.extractString(args[0]);
    auto data = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

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

JSHandle jsAppendFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsAppendFileSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsAppendFileSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("appendFileSync requires path and data");
    auto path = engine.extractString(args[0]);
    auto data = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : append;
        append(path, data);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

JSHandle jsCopyFileSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCopyFileSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCopyFileSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("copyFileSync requires src and dest");
    auto src = engine.extractString(args[0]);
    auto dest = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.read, src))
        return throwPermError(engine, "read", src);
    if (!checkPerm(state, Permission.write, dest))
        return throwPermError(engine, "write", dest);
    try
    {
        import std.file : copy;
        copy(src, dest);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "copyfile", src, e); }
}

JSHandle jsRenameSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsRenameSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsRenameSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("renameSync requires oldPath and newPath");
    auto oldPath = engine.extractString(args[0]);
    auto newPath = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, oldPath))
        return throwPermError(engine, "write", oldPath);
    if (!checkPerm(state, Permission.write, newPath))
        return throwPermError(engine, "write", newPath);
    try
    {
        import std.file : rename;
        rename(oldPath, newPath);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "rename", oldPath, e); }
}

JSHandle jsRmdirSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsRmdirSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsRmdirSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("rmdirSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : rmdir;
        rmdir(path);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "rmdir", path, e); }
}

JSHandle jsRmSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsRmSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsRmSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("rmSync requires a path argument");
    auto path = engine.extractString(args[0]);
    bool recursive = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        recursive = engine.extractBool(rv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : remove, rmdirRecurse, isDir;
        if (recursive && isDir(path))
            rmdirRecurse(path);
        else
            remove(path);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "rm", path, e); }
}

JSHandle jsAccessSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsAccessSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsAccessSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("accessSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : exists;
        if (!exists(path))
            return engine.throwTypeError("ENOENT: no such file or directory, access '" ~ path ~ "'");
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "access", path, e); }
}

JSHandle jsRealpathSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsRealpathSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsRealpathSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("realpathSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import core.sys.posix.stdlib : realpath;
        import std.string : fromStringz;
        auto result = (() @trusted => realpath(cast(const(char)*)(path ~ "\0").ptr, null))();
        if (result is null)
            return engine.throwTypeError("ENOENT: no such file or directory, realpath '" ~ path ~ "'");
        auto resolved = (() @trusted => fromStringz(result).idup)();
        import core.stdc.stdlib : free;
        (() @trusted => free(result))();
        return engine.newString(resolved);
    }
    catch (Exception e) { return throwSystemError(engine, "realpath", path, e); }
}

JSHandle jsChmodSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsChmodSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsChmodSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("chmodSync requires path and mode");
    auto path = engine.extractString(args[0]);
    auto mode = cast(uint) engine.extractInt(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.file : setAttributes;
        setAttributes(path, mode);
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "chmod", path, e); }
}

JSHandle jsStatIsSymbolicLink(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsSymbolicLink");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsSymbolicLink");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    return engine.newBool(engine.extractInt(typeVal) == 3);
}

// ── lstatSync ───────────────────────────────────────────────────

JSHandle jsLstatSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsLstatSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsLstatSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("lstatSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import core.sys.posix.sys.stat : lstat, stat_t;
        import std.string : toStringz;
        stat_t buf;
        if (lstat(path.toStringz, &buf) != 0)
            return engine.throwTypeError("ENOENT: no such file or directory, lstat '" ~ path ~ "'");
        return buildStatFromPosix(engine, buf);
    }
    catch (Exception e) { return throwSystemError(engine, "lstat", path, e); }
}

// ── linkSync ────────────────────────────────────────────────────

JSHandle jsLinkSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsLinkSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsLinkSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("linkSync requires existingPath and newPath");
    auto existingPath = engine.extractString(args[0]);
    auto newPath = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.read, existingPath))
        return throwPermError(engine, "read", existingPath);
    if (!checkPerm(state, Permission.write, newPath))
        return throwPermError(engine, "write", newPath);
    try
    {
        import core.sys.posix.unistd : link;
        import std.string : toStringz;
        if (link(existingPath.toStringz, newPath.toStringz) != 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("ELINK: " ~ msg ~ ", link '" ~ existingPath ~ "' -> '" ~ newPath ~ "'");
        }
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "link", existingPath, e); }
}

// ── symlinkSync ─────────────────────────────────────────────────

JSHandle jsSymlinkSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSymlinkSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSymlinkSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("symlinkSync requires target and path");
    auto target = engine.extractString(args[0]);
    auto path = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import core.sys.posix.unistd : symlink;
        import std.string : toStringz;
        if (symlink(target.toStringz, path.toStringz) != 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("ESYMLINK: " ~ msg ~ ", symlink '" ~ target ~ "' -> '" ~ path ~ "'");
        }
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "symlink", target, e); }
}

// ── readlinkSync ────────────────────────────────────────────────

JSHandle jsReadlinkSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadlinkSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadlinkSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readlinkSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import core.sys.posix.unistd : readlink;
        import std.string : toStringz;
        char[READLINK_BUF_SIZE] buf;
        auto len = readlink(path.toStringz, buf.ptr, buf.length);
        if (len < 0)
            return engine.throwTypeError("ENOENT: no such file or directory, readlink '" ~ path ~ "'");
        return engine.newString(cast(string) buf[0 .. len]);
    }
    catch (Exception e) { return throwSystemError(engine, "readlink", path, e); }
}

// ── truncateSync ────────────────────────────────────────────────

JSHandle jsTruncateSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsTruncateSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsTruncateSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("truncateSync requires a path argument");
    auto path = engine.extractString(args[0]);
    long len = 0;
    if (args.length >= 2) len = cast(long) engine.extractFloat(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import std.string : toStringz;
        if (truncate(path.toStringz, len) != 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("EIO: " ~ msg ~ ", truncate '" ~ path ~ "'");
        }
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "truncate", path, e); }
}

// ── chownSync ───────────────────────────────────────────────────

JSHandle jsChownSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsChownSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsChownSync");
    auto engine = state.engine;
    if (args.length < 3) return engine.throwTypeError("chownSync requires path, uid, gid");
    auto path = engine.extractString(args[0]);
    auto uid = engine.extractInt(args[1]);
    auto gid = engine.extractInt(args[2]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import core.sys.posix.unistd : chown;
        import std.string : toStringz;
        if (chown(path.toStringz, uid, gid) != 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("EPERM: " ~ msg ~ ", chown '" ~ path ~ "'");
        }
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "chown", path, e); }
}

// ── openSync / closeSync / readSync / writeSync ─────────────────

int parseFsFlags(string flags) nothrow @trusted
{
    import core.sys.posix.fcntl : O_RDONLY, O_WRONLY, O_RDWR, O_CREAT, O_TRUNC, O_APPEND;
    if (flags == "r") return O_RDONLY;
    if (flags == "r+") return O_RDWR;
    if (flags == "w") return O_WRONLY | O_CREAT | O_TRUNC;
    if (flags == "w+") return O_RDWR | O_CREAT | O_TRUNC;
    if (flags == "a") return O_WRONLY | O_CREAT | O_APPEND;
    if (flags == "a+") return O_RDWR | O_CREAT | O_APPEND;
    if (flags == "wx") return O_WRONLY | O_CREAT | O_TRUNC;
    return O_RDONLY;
}

JSHandle jsOpenSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsOpenSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsOpenSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("openSync requires a path argument");
    auto path = engine.extractString(args[0]);
    string flags = "r";
    if (args.length >= 2 && engine.isString(args[1]))
        flags = engine.extractString(args[1]);
    int mode = 0x1A4; // 0o644
    if (args.length >= 3 && engine.isNumber(args[2]))
        mode = engine.extractInt(args[2]);
    bool needsRead = (flags == "r" || flags == "r+" || flags == "w+" || flags == "a+");
    bool needsWrite = (flags != "r");
    if (needsRead && !checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    if (needsWrite && !checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    try
    {
        import core.sys.posix.fcntl : open;
        import std.string : toStringz;
        auto fd = open(path.toStringz, parseFsFlags(flags), mode);
        if (fd < 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("ENOENT: " ~ msg ~ ", open '" ~ path ~ "'");
        }
        return engine.newInt(fd);
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

JSHandle jsCloseSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCloseSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCloseSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("closeSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    import core.sys.posix.unistd : close;
    close(fd);
    return engine.newUndefined();
}

JSHandle jsReadSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("readSync requires fd and length");
    auto fd = engine.extractInt(args[0]);

    // Node.js signature: readSync(fd, buffer, offset, length, position) -> bytesRead
    // DunJS simple:      readSync(fd, length) -> string
    bool isBufferForm = args.length >= 4 && engine.isObject(args[1]);

    if (isBufferForm) {
        auto offset = engine.extractInt(args[2]);
        auto length = engine.extractInt(args[3]);
        if (length <= 0 || length > MAX_READ_LENGTH)
            return engine.throwRangeError("readSync length out of range");

        int pos = -1;
        if (args.length >= 5 && !engine.isNull(args[4]))
            pos = engine.extractInt(args[4]);

        try {
            import core.sys.posix.unistd : read, lseek;
            import core.sys.posix.sys.types : off_t;
            if (pos >= 0)
                lseek(fd, cast(off_t) pos, 0); // SEEK_SET
            auto buf = new ubyte[length];
            auto bytesRead = read(fd, buf.ptr, length);
            if (bytesRead < 0) {
                import core.stdc.errno : errno;
                import core.stdc.string : strerror;
                import std.string : fromStringz;
                return engine.throwTypeError("EIO: " ~ fromStringz(strerror(errno)).idup ~ ", read");
            }
            return engine.newFloat(cast(double) bytesRead);
        } catch (Exception e) {
            return engine.throwTypeError("EIO: read error");
        }
    }

    auto length = engine.extractInt(args[1]);
    if (length <= 0 || length > MAX_READ_LENGTH)
        return engine.throwRangeError("readSync length out of range");
    try
    {
        import core.sys.posix.unistd : read;
        auto buf = new ubyte[length];
        auto bytesRead = read(fd, buf.ptr, length);
        if (bytesRead < 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("EIO: " ~ msg ~ ", read");
        }
        return engine.newString(cast(string) buf[0 .. bytesRead]);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EIO: read error");
    }
}

JSHandle jsWriteSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteSync");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("writeSync requires fd and data");
    auto fd = engine.extractInt(args[0]);
    auto data = engine.extractString(args[1]);
    try
    {
        import core.sys.posix.unistd : write;
        auto written = write(fd, data.ptr, data.length);
        if (written < 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("EIO: " ~ msg ~ ", write");
        }
        return engine.newInt(cast(int) written);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EIO: write error");
    }
}

// ── fstatSync / fsyncSync / fdatasyncSync ───────────────────────

JSHandle jsFstatSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFstatSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFstatSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fstatSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    try
    {
        import core.sys.posix.sys.stat : fstat, stat_t;
        stat_t buf;
        if (fstat(fd, &buf) != 0)
        {
            import core.stdc.errno : errno;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto msg = fromStringz(strerror(errno)).idup;
            return engine.throwTypeError("EBADF: " ~ msg ~ ", fstat");
        }
        return buildStatFromPosix(engine, buf);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EBADF: fstat error");
    }
}

JSHandle jsFsyncSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFsyncSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFsyncSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fsyncSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    import core.sys.posix.unistd : fsync;
    if (fsync(fd) != 0)
    {
        import core.stdc.errno : errno;
        import core.stdc.string : strerror;
        import std.string : fromStringz;
        auto msg = fromStringz(strerror(errno)).idup;
        return engine.throwTypeError("EIO: " ~ msg ~ ", fsync");
    }
    return engine.newUndefined();
}

JSHandle jsFdatasyncSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFdatasyncSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFdatasyncSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fdatasyncSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    if (fdatasync(fd) != 0)
    {
        import core.stdc.errno : errno;
        import core.stdc.string : strerror;
        import std.string : fromStringz;
        auto msg = fromStringz(strerror(errno)).idup;
        return engine.throwTypeError("EIO: " ~ msg ~ ", fdatasync");
    }
    return engine.newUndefined();
}

// ── createReadStream ────────────────────────────────────────────

JSHandle jsCreateReadStream(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCreateReadStream");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCreateReadStream");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createReadStream requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    try
    {
        import std.file : readText, exists;
        if (!exists(path))
            return engine.throwTypeError("ENOENT: no such file or directory, open '" ~ path ~ "'");
        auto content = readText(path);
        auto stream = engine.newObject();
        engine.setProperty(stream, "_data", engine.newString(content));
        engine.setProperty(stream, "_listeners", engine.newObject());
        engine.setProperty(stream, "_ended", engine.newBool(false));
        engine.setProperty(stream, "path", engine.newString(path));
        engine.setProperty(stream, "on", engine.newFunction(&jsStreamOn, "on", 2));
        engine.setProperty(stream, "pipe", engine.newFunction(&jsReadStreamPipe, "pipe", 1));
        engine.setProperty(stream, "destroy", engine.newFunction(&jsStreamDestroy, "destroy", 0));
        engine.setProperty(stream, "read", engine.newFunction(&jsReadStreamRead, "read", 0));
        return stream;
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

// ── createWriteStream ───────────────────────────────────────────

JSHandle jsCreateWriteStream(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCreateWriteStream");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCreateWriteStream");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createWriteStream requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    auto stream = engine.newObject();
    engine.setProperty(stream, "_path", engine.newString(path));
    engine.setProperty(stream, "_chunks", engine.newArray());
    engine.setProperty(stream, "_chunkCount", engine.newInt(0));
    engine.setProperty(stream, "_listeners", engine.newObject());
    engine.setProperty(stream, "_ended", engine.newBool(false));
    engine.setProperty(stream, "path", engine.newString(path));
    engine.setProperty(stream, "on", engine.newFunction(&jsStreamOn, "on", 2));
    engine.setProperty(stream, "write", engine.newFunction(&jsWriteStreamWrite, "write", 1));
    engine.setProperty(stream, "end", engine.newFunction(&jsWriteStreamEnd, "end", 0));
    engine.setProperty(stream, "destroy", engine.newFunction(&jsStreamDestroy, "destroy", 0));
    return stream;
}

// ── Stream helpers (shared by createReadStream/createWriteStream) ──

JSHandle jsStreamOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStreamOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStreamOn");
    auto engine = state.engine;
    if (args.length < 2) return thisVal;
    auto eventName = engine.extractString(args[0]);
    auto listeners = engine.getProperty(thisVal, "_listeners");
    engine.setProperty(listeners, eventName, args[1]);
    return thisVal;
}

JSHandle jsStreamDestroy(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStreamDestroy");
    auto state = cast(DunState*) ctx;
    return state.engine.newUndefined();
}

JSHandle jsReadStreamRead(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamRead");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadStreamRead");
    auto engine = state.engine;
    auto ended = engine.extractBool(engine.getProperty(thisVal, "_ended"));
    if (ended) return engine.newNull();
    engine.setProperty(thisVal, "_ended", engine.newBool(true));
    return engine.getProperty(thisVal, "_data");
}

JSHandle jsReadStreamPipe(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamPipe");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadStreamPipe");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("pipe requires a destination");
    auto data = engine.getProperty(thisVal, "_data");
    auto writeFn = engine.getProperty(args[0], "write");
    if (engine.isFunction(writeFn))
        engine.callFunction(writeFn, args[0], [data]);
    auto endFn = engine.getProperty(args[0], "end");
    if (engine.isFunction(endFn))
        engine.callFunction(endFn, args[0], []);
    return args[0];
}

JSHandle jsWriteStreamWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteStreamWrite");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteStreamWrite");
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    auto chunks = engine.getProperty(thisVal, "_chunks");
    auto idx = engine.extractInt(engine.getProperty(thisVal, "_chunkCount"));
    engine.setPropertyIndex(chunks, cast(uint) idx, args[0]);
    engine.setProperty(thisVal, "_chunkCount", engine.newInt(idx + 1));
    return engine.newBool(true);
}

JSHandle jsWriteStreamEnd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteStreamEnd");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteStreamEnd");
    auto engine = state.engine;
    if (args.length >= 1 && engine.isString(args[0]))
    {
        auto chunks = engine.getProperty(thisVal, "_chunks");
        auto idx = engine.extractInt(engine.getProperty(thisVal, "_chunkCount"));
        engine.setPropertyIndex(chunks, cast(uint) idx, args[0]);
        engine.setProperty(thisVal, "_chunkCount", engine.newInt(idx + 1));
    }
    auto path = engine.extractString(engine.getProperty(thisVal, "_path"));
    auto chunks = engine.getProperty(thisVal, "_chunks");
    auto count = engine.extractInt(engine.getProperty(thisVal, "_chunkCount"));
    string allData;
    foreach (i; 0 .. count)
        allData ~= engine.extractString(engine.getPropertyIndex(chunks, cast(uint) i));
    try
    {
        import std.file : write;
        write(path, allData);
        engine.setProperty(thisVal, "_ended", engine.newBool(true));
        auto listeners = engine.getProperty(thisVal, "_listeners");
        auto finishCb = engine.getProperty(listeners, "finish");
        if (engine.isFunction(finishCb))
            engine.callFunction(finishCb, thisVal, []);
    }
    catch (Exception) {}
    return engine.newUndefined();
}

// ── watch ───────────────────────────────────────────────────────

JSHandle jsWatch(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatch");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatch");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("watch requires a filename argument");
    auto filename = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, filename))
        return throwPermError(engine, "read", filename);
    auto watcher = engine.newObject();
    engine.setProperty(watcher, "filename", engine.newString(filename));
    engine.setProperty(watcher, "_closed", engine.newBool(false));
    engine.setProperty(watcher, "close", engine.newFunction(&jsWatcherClose, "close", 0));
    engine.setProperty(watcher, "on", engine.newFunction(&jsStreamOn, "on", 2));
    engine.setProperty(watcher, "_listeners", engine.newObject());
    return watcher;
}

JSHandle jsWatcherClose(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherClose");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherClose");
    auto engine = state.engine;
    engine.setProperty(thisVal, "_closed", engine.newBool(true));
    return engine.newUndefined();
}
