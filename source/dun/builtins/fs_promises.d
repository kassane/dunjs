module dun.builtins.fs_promises;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void registerFsPromisesModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerFsPromisesModule");

    auto obj = engine.newObject();

    engine.setProperty(obj, "readFile", engine.newFunction(&jsFspReadFile, "readFile", 1));
    engine.setProperty(obj, "writeFile", engine.newFunction(&jsFspWriteFile, "writeFile", 2));
    engine.setProperty(obj, "appendFile", engine.newFunction(&jsFspAppendFile, "appendFile", 2));
    engine.setProperty(obj, "copyFile", engine.newFunction(&jsFspCopyFile, "copyFile", 2));
    engine.setProperty(obj, "rename", engine.newFunction(&jsFspRename, "rename", 2));
    engine.setProperty(obj, "unlink", engine.newFunction(&jsFspUnlink, "unlink", 1));
    engine.setProperty(obj, "rmdir", engine.newFunction(&jsFspRmdir, "rmdir", 1));
    engine.setProperty(obj, "rm", engine.newFunction(&jsFspRm, "rm", 1));
    engine.setProperty(obj, "mkdir", engine.newFunction(&jsFspMkdir, "mkdir", 1));
    engine.setProperty(obj, "readdir", engine.newFunction(&jsFspReaddir, "readdir", 1));
    engine.setProperty(obj, "stat", engine.newFunction(&jsFspStat, "stat", 1));
    engine.setProperty(obj, "lstat", engine.newFunction(&jsFspLstat, "lstat", 1));
    engine.setProperty(obj, "access", engine.newFunction(&jsFspAccess, "access", 1));
    engine.setProperty(obj, "realpath", engine.newFunction(&jsFspRealpath, "realpath", 1));
    engine.setProperty(obj, "chmod", engine.newFunction(&jsFspChmod, "chmod", 2));
    engine.setProperty(obj, "chown", engine.newFunction(&jsFspChown, "chown", 3));
    engine.setProperty(obj, "truncate", engine.newFunction(&jsFspTruncate, "truncate", 2));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_fs_promises__", obj);

    auto fsObj = engine.getProperty(global, "__dun_cjs_fs__");
    if (!engine.isUndefined(fsObj))
    {
        engine.setProperty(fsObj, "promises", engine.dupValue(obj));
        engine.freeValue(fsObj);
    }

    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private enum fspExports = [
        "readFile", "writeFile", "appendFile", "copyFile", "rename",
        "unlink", "rmdir", "rm", "mkdir", "readdir", "stat", "lstat",
        "access", "realpath", "chmod", "chown", "truncate"
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in fs_promises registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:fs/promises", &fspModuleInit);
        if (m is null) return;
        foreach (name; fspExports)
            JS_AddModuleExport(ctx, m, name.ptr);
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int fspModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in fspModuleInit");
        assert(m !is null, "Null JSModuleDef in fspModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_fs_promises__");
        foreach (name; fspExports)
        {
            auto fn = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

import dun.engine.iface : PromiseHandles;
import dun.loop.async : asyncSubmitSafe, AsyncResult, ResultTransform;

bool checkPerm(DunState* state, Permission perm, string resource = "") nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

JSHandle throwPermError(IJSEngine engine, string perm, string path = "") @trusted
{
    import dun.builtins.fs : throwNodeError;
    return throwNodeError(engine, "ERR_PERMISSION_DENIED",
        "Requires --allow-" ~ perm ~ " permission", "", path);
}

// Wraps std.file operations safely — never throws in async thread
string safeFileOp(string delegate() op) nothrow @trusted
{
    try { return op(); }
    catch (Exception) { return null; }
}

string safeExMsg(string delegate() op) nothrow @trusted
{
    try { op(); return null; }
    catch (Exception e)
    {
        try { return e.msg; }
        catch (Exception) { return "I/O error"; }
    }
}

JSHandle jsFspReadFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.readFile");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.readFile");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readFile requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        string content;
        try
        {
            import std.file : readText;
            content = readText(path);
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "read error"; }
            return AsyncResult.fail(msg);
        }
        return AsyncResult.ok(content);
    });

    return ph.promise;
}

JSHandle jsFspWriteFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.writeFile");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.writeFile");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("writeFile requires path and data");
    auto path = engine.extractString(args[0]);
    auto data = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : write;
            write(path, data);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "write error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspAppendFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.appendFile");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.appendFile");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("appendFile requires path and data");
    auto path = engine.extractString(args[0]);
    auto data = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : append;
            append(path, data);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "append error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspCopyFile(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.copyFile");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.copyFile");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("copyFile requires src and dest");
    auto src = engine.extractString(args[0]);
    auto dest = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.read, src))
        return throwPermError(engine, "read", src);
    if (!checkPerm(state, Permission.write, dest))
        return throwPermError(engine, "write", dest);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : copy;
            copy(src, dest);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "copy error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspRename(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.rename");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.rename");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("rename requires oldPath and newPath");
    auto oldPath = engine.extractString(args[0]);
    auto newPath = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, oldPath))
        return throwPermError(engine, "write", oldPath);
    if (!checkPerm(state, Permission.write, newPath))
        return throwPermError(engine, "write", newPath);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : rename;
            rename(oldPath, newPath);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "rename error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspUnlink(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.unlink");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.unlink");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("unlink requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : remove;
            remove(path);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "unlink error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspRmdir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.rmdir");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.rmdir");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("rmdir requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : rmdir;
            rmdir(path);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "rmdir error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspRm(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.rm");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.rm");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("rm requires a path argument");
    auto path = engine.extractString(args[0]);
    bool recursive = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        recursive = engine.extractBool(rv);
        engine.freeValue(rv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : remove, rmdirRecurse, isDir;
            if (recursive && isDir(path))
                rmdirRecurse(path);
            else
                remove(path);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "rm error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspMkdir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.mkdir");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.mkdir");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("mkdir requires a path argument");
    auto path = engine.extractString(args[0]);
    bool recursive = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        recursive = engine.extractBool(rv);
        engine.freeValue(rv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            if (recursive)
            {
                import std.file : mkdirRecurse;
                mkdirRecurse(path);
            }
            else
            {
                import std.file : mkdir;
                mkdir(path);
            }
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "mkdir error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspReaddir(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.readdir");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.readdir");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readdir requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : dirEntries, SpanMode;
            import std.path : baseName;
            string result;
            foreach (entry; dirEntries(path, SpanMode.shallow))
            {
                if (result.length > 0) result ~= "\n";
                result ~= baseName(entry.name);
            }
            return AsyncResult.ok(result);
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "readdir error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string result) @trusted {
        auto arr = e.newArray();
        if (result.length == 0) return arr;
        uint idx = 0;
        size_t start = 0;
        foreach (i, c; result)
        {
            if (c == '\n')
            {
                e.setPropertyIndex(arr, idx++, e.newString(result[start .. i]));
                start = i + 1;
            }
        }
        if (start < result.length)
            e.setPropertyIndex(arr, idx++, e.newString(result[start .. $]));
        return arr;
    });

    return ph.promise;
}

JSHandle jsFspStat(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.stat");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.stat");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("stat requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        return serializeStatSafe(path, false);
    }, (IJSEngine e, string result) @trusted => deserializeStatObj(e, result));

    return ph.promise;
}

JSHandle jsFspLstat(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.lstat");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.lstat");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("lstat requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        return serializeStatSafe(path, true);
    }, (IJSEngine e, string result) @trusted => deserializeStatObj(e, result));

    return ph.promise;
}

JSHandle jsFspAccess(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.access");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.access");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("access requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.unistd : access, F_OK;
            auto cpath = (path ~ '\0');
            if (access(cpath.ptr, F_OK) != 0)
                return AsyncResult.fail("ENOENT: no such file or directory, access '" ~ path ~ "'");
        }
        else
        {
            import core.stdc.stdio : fopen, fclose;
            auto cpath = (path ~ '\0');
            auto fp = fopen(cpath.ptr, "rb");
            if (fp is null)
                return AsyncResult.fail("ENOENT: no such file or directory, access '" ~ path ~ "'");
            fclose(fp);
        }
        return AsyncResult.ok("");
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspRealpath(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.realpath");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.realpath");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("realpath requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.stdlib : realpath;
            import std.string : fromStringz;
            import core.stdc.stdlib : free;
            auto result = realpath(cast(const(char)*)(path ~ "\0").ptr, null);
            if (result is null)
                return AsyncResult.fail("ENOENT: no such file or directory, realpath '" ~ path ~ "'");
            string resolved;
            try { resolved = fromStringz(result).idup; }
            catch (Exception) { free(result); return AsyncResult.fail("realpath encoding error"); }
            free(result);
            return AsyncResult.ok(resolved);
        }
        else
        {
            try
            {
                import std.path : absolutePath, buildNormalizedPath;
                import std.file : exists;
                auto resolved = buildNormalizedPath(absolutePath(path));
                if (!exists(resolved))
                    return AsyncResult.fail("ENOENT: no such file or directory, realpath '" ~ path ~ "'");
                return AsyncResult.ok(resolved);
            }
            catch (Exception)
            {
                return AsyncResult.fail("ENOENT: realpath failed for '" ~ path ~ "'");
            }
        }
    });

    return ph.promise;
}

JSHandle jsFspChmod(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.chmod");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.chmod");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("chmod requires path and mode");
    auto path = engine.extractString(args[0]);
    auto mode = cast(uint) engine.extractInt(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : setAttributes;
            setAttributes(path, mode);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "chmod error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspChown(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.chown");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.chown");
    auto engine = state.engine;
    if (args.length < 3) return engine.throwTypeError("chown requires path, uid, gid");
    auto path = engine.extractString(args[0]);
    auto uid = engine.extractInt(args[1]);
    auto gid = engine.extractInt(args[2]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.unistd : chown;
            import std.string : toStringz;
            auto cpath = (path ~ '\0');
            if (chown(cpath.ptr, uid, gid) != 0)
            {
                import core.stdc.errno : errno;
                import core.stdc.string : strerror;
                import std.string : fromStringz;
                string msg;
                try { msg = fromStringz(strerror(errno)).idup; }
                catch (Exception) { msg = "chown error"; }
                return AsyncResult.fail("EPERM: " ~ msg ~ ", chown '" ~ path ~ "'");
            }
        }
        return AsyncResult.ok("");
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspTruncate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in fs.promises.truncate");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in fs.promises.truncate");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("truncate requires a path argument");
    auto path = engine.extractString(args[0]);
    long len = 0;
    if (args.length >= 2) len = cast(long) engine.extractFloat(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.unistd : truncate_ = truncate;
            auto cpath = (path ~ '\0');
            if (truncate_(cpath.ptr, len) != 0)
            {
                import core.stdc.errno : errno;
                import core.stdc.string : strerror;
                import std.string : fromStringz;
                string msg;
                try { msg = fromStringz(strerror(errno)).idup; }
                catch (Exception) { msg = "truncate error"; }
                return AsyncResult.fail("EIO: " ~ msg ~ ", truncate '" ~ path ~ "'");
            }
        }
        else version(Windows)
        {
            try
            {
                import std.file : write, readText;
                auto content = readText(path);
                if (len < content.length)
                    write(path, content[0 .. cast(size_t) len]);
            }
            catch (Exception)
            {
                return AsyncResult.fail("EIO: truncate failed for '" ~ path ~ "'");
            }
        }
        return AsyncResult.ok("");
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

AsyncResult serializeStatSafe(string path, bool useLstat) nothrow @trusted
{
    version(Posix)
    {
        import core.sys.posix.sys.stat : stat_t, stat, lstat, S_ISREG, S_ISDIR, S_ISLNK;
        stat_t st;
        auto cpath = (path ~ '\0');
        int ret;
        if (useLstat)
            ret = lstat(cpath.ptr, &st);
        else
            ret = stat(cpath.ptr, &st);
        if (ret != 0)
            return AsyncResult.fail("ENOENT: no such file or directory, stat '" ~ path ~ "'");

        bool isFile = S_ISREG(st.st_mode);
        bool isDir = S_ISDIR(st.st_mode);
        bool isLink = S_ISLNK(st.st_mode);
        int typeVal = isFile ? 1 : isDir ? 2 : isLink ? 3 : 0;

        double atimeMs, mtimeMs, ctimeMs;
        static if (__traits(hasMember, typeof(st), "st_atim"))
        {
            atimeMs = cast(double)(st.st_atim.tv_sec * 1000L + st.st_atim.tv_nsec / 1_000_000L);
            mtimeMs = cast(double)(st.st_mtim.tv_sec * 1000L + st.st_mtim.tv_nsec / 1_000_000L);
            ctimeMs = cast(double)(st.st_ctim.tv_sec * 1000L + st.st_ctim.tv_nsec / 1_000_000L);
        }
        else
        {
            atimeMs = cast(double)(st.st_atime) * 1000.0;
            mtimeMs = cast(double)(st.st_mtime) * 1000.0;
            ctimeMs = cast(double)(st.st_ctime) * 1000.0;
        }

        try
        {
            import std.conv : to;
            return AsyncResult.ok(
                to!string(typeVal) ~ "\n"
                ~ to!string(st.st_size) ~ "\n"
                ~ to!string(st.st_mode & 0xFFFF) ~ "\n"
                ~ to!string(cast(int) st.st_uid) ~ "\n"
                ~ to!string(cast(int) st.st_gid) ~ "\n"
                ~ to!string(st.st_dev) ~ "\n"
                ~ to!string(st.st_ino) ~ "\n"
                ~ to!string(cast(int) st.st_nlink) ~ "\n"
                ~ to!string(atimeMs) ~ "\n"
                ~ to!string(mtimeMs) ~ "\n"
                ~ to!string(ctimeMs));
        }
        catch (Exception)
        {
            return AsyncResult.fail("stat serialization error");
        }
    }
    else
    {
        try
        {
            import std.file : getSize, exists, isFile, isDir;
            import std.conv : to;
            if (!exists(path))
                return AsyncResult.fail("ENOENT: no such file or directory, stat '" ~ path ~ "'");
            int typeVal = isFile(path) ? 1 : isDir(path) ? 2 : 0;
            auto size = getSize(path);
            return AsyncResult.ok(
                to!string(typeVal) ~ "\n"
                ~ to!string(size) ~ "\n"
                ~ "33188\n0\n0\n0\n0\n1\n0\n0\n0");
        }
        catch (Exception)
        {
            return AsyncResult.fail("ENOENT: stat failed for '" ~ path ~ "'");
        }
    }
}

JSHandle deserializeStatObj(IJSEngine engine, string data) @trusted
{
    import dun.builtins.fs : buildStatObject;

    string[] fields;
    size_t start = 0;
    foreach (i, c; data)
    {
        if (c == '\n')
        {
            fields ~= data[start .. i];
            start = i + 1;
        }
    }
    if (start < data.length)
        fields ~= data[start .. $];

    if (fields.length < 11)
        return engine.throwTypeError("Internal stat deserialization error");

    import std.conv : to;
    import dun.builtins.fs : SafeStatResult;
    SafeStatResult sr;
    sr.isFile = fields[0] == "1";
    sr.isDir = fields[0] == "2";
    sr.isLink = fields[0] == "3";
    sr.size = to!long(fields[1]);
    sr.mode = to!uint(fields[2]);
    sr.uid = to!int(fields[3]);
    sr.gid = to!int(fields[4]);
    sr.dev = to!long(fields[5]);
    sr.ino = to!long(fields[6]);
    sr.nlink = to!int(fields[7]);
    sr.atimeMs = to!double(fields[8]);
    sr.mtimeMs = to!double(fields[9]);
    sr.ctimeMs = to!double(fields[10]);

    return buildStatObject(engine, sr);
}
