module dun.builtins.fs;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

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

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_fs__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;
    import dun.engine.quickjs.function_bind;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:fs", &fsModuleInit);
        if (m is null) return;
        foreach (name; ["readFileSync", "writeFileSync", "existsSync", "readdirSync",
                        "statSync", "mkdirSync", "unlinkSync", "readFile", "writeFile"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int fsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in fsModuleInit");
        assert(m !is null, "Null JSModuleDef in fsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto fsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_fs__");
        foreach (name; ["readFileSync", "writeFileSync", "existsSync", "readdirSync",
                        "statSync", "mkdirSync", "unlinkSync", "readFile", "writeFile"])
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

// Cached stat method handles — registered once to avoid callback slot exhaustion
__gshared JSHandle _cachedIsFileFn, _cachedIsDirFn;
__gshared bool _statFnsCached = false;

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
        if (!_statFnsCached)
        {
            _cachedIsFileFn = engine.newFunction(&jsStatIsFile, "isFile", 0);
            _cachedIsDirFn = engine.newFunction(&jsStatIsDirectory, "isDirectory", 0);
            _statFnsCached = true;
        }
        engine.setProperty(obj, "isFile", engine.dupValue(_cachedIsFileFn));
        engine.setProperty(obj, "isDirectory", engine.dupValue(_cachedIsDirFn));
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
