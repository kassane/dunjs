module dun.builtins.fs_promises;


/++
 + `@trusted policy`: promise-based file system API
 + (`fs.promises.*`). Every `@trusted` is one of:
 +
 +   1. POSIX file syscall — same surface as `fs.d` (open, read,
 +      write, stat, mkdir, …). Each call sits behind a
 +      `Permission.read` / `Permission.write` gate.
 +   2. Async work submission via `asyncSubmit` (worker thread
 +      runs the blocking syscall, main thread resolves the
 +      promise from the result). Thread-pool pattern from
 +      `dun.loop.async`.
 +   3. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +/
import dun.engine.iface : IJSEngine, JSHandle, JSResult, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.security.permissions : Permission;
import dun.builtins.fs : errnoMsg;
import dun.declarations : FILE_MODE_DEFAULT_FILE;

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
    engine.setProperty(obj, "symlink", engine.newFunction(&jsFspSymlink, "symlink", 2));
    engine.setProperty(obj, "open", engine.newFunction(&jsFspOpen, "open", 1));
    engine.setProperty(obj, "cp", engine.newFunction(&jsFspCopyFile, "cp", 2));

    auto global = engine.getGlobal();

    auto fsObj0 = engine.getProperty(global, "__dun_cjs_fs__");
    if (!engine.isUndefined(fsObj0))
    {
        auto fsConstants = engine.getProperty(fsObj0, "constants");
        if (!engine.isUndefined(fsConstants))
            engine.setProperty(obj, "constants", fsConstants);
        else
            engine.freeValue(fsConstants);
        engine.freeValue(fsObj0);
    }
    else
        engine.freeValue(fsObj0);

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
        "access", "realpath", "chmod", "chown", "truncate", "symlink",
        "open", "cp", "constants"
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
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

public import dun.security.permissions : checkPerm;

public import dun.builtins.fs : throwPermError;

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

// ── Flag parsing for open() ─────────────────────────────────────

int parseFsOpenFlags(string flags) nothrow @trusted
{
    version(Posix)
    {
        import core.sys.posix.fcntl : O_RDONLY, O_WRONLY, O_RDWR, O_CREAT, O_TRUNC, O_APPEND;
    }
    else
    {
        enum O_RDONLY = 0x0000, O_WRONLY = 0x0001, O_RDWR = 0x0002,
             O_CREAT = 0x0100, O_TRUNC = 0x0200, O_APPEND = 0x0008;
    }
    if (flags == "r") return O_RDONLY;
    if (flags == "r+") return O_RDWR;
    if (flags == "w") return O_WRONLY | O_CREAT | O_TRUNC;
    if (flags == "w+") return O_RDWR | O_CREAT | O_TRUNC;
    if (flags == "a") return O_WRONLY | O_CREAT | O_APPEND;
    if (flags == "a+") return O_RDWR | O_CREAT | O_APPEND;
    if (flags == "wx") return O_WRONLY | O_CREAT | O_TRUNC;
    return O_RDONLY;
}

JSHandle jsFspReadFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.builtins.fs : extractEncoding, createBufferFromBytes;

    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.readFile");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readFile requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    // Node semantics: no encoding → return a Buffer of raw bytes;
    // explicit encoding (e.g. "utf8") → return a string. Previously
    // we always called readText (UTF-8 validating), which threw
    // `Invalid UTF-8 sequence` on binary files.
    string encoding = extractEncoding(engine, args);
    bool wantString = encoding.length > 0;

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    auto work = () @trusted nothrow {
        try
        {
            import std.file : read, readText;
            if (wantString)
                return AsyncResult.ok(readText(path));
            // Read raw bytes -- D strings are byte-array-compatible
            // (immutable(char)[]), so we cast the byte slice without
            // UTF-8 validation. The result transform wraps it in a
            // Buffer on the JS side.
            auto raw = cast(string) cast(immutable(ubyte)[]) read(path);
            return AsyncResult.ok(raw);
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "read error"; }
            return AsyncResult.fail(msg);
        }
    };

    ResultTransform bytesTransform = (IJSEngine e, string s) @trusted
        => createBufferFromBytes(e, cast(const(ubyte)[]) s);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, work,
        wantString ? null : bytesTransform);

    return ph.promise;
}

JSHandle jsFspWriteFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.writeFile");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("writeFile requires path and data");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    // Binary path: Buffer / Uint8Array / ArrayBuffer-backed view write
    // raw bytes; only fall back to extractString for genuine strings.
    // Without the typed-array branch, every byte >= 0x80 became the
    // 3-byte UTF-8 replacement char, silently corrupting binary writes.
    // Slice is dup'd before async dispatch since the engine handle
    // doesn't survive into the worker thread.
    ubyte[] dataBytes;
    string dataStr;
    bool hasBytes = false;
    if (engine.isObject(args[1]))
    {
        auto bytes = engine.getTypedArrayBytes(args[1]);
        if (bytes !is null) { dataBytes = bytes.dup; hasBytes = true; }
    }
    if (!hasBytes)
        dataStr = engine.extractString(args[1]);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : write;
            if (hasBytes) write(path, dataBytes);
            else write(path, dataStr);
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

JSHandle jsFspAppendFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.appendFile");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("appendFile requires path and data");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    // Same Buffer / Uint8Array binary path as writeFile.
    ubyte[] dataBytes;
    string dataStr;
    bool hasBytes = false;
    if (engine.isObject(args[1]))
    {
        auto bytes = engine.getTypedArrayBytes(args[1]);
        if (bytes !is null) { dataBytes = bytes.dup; hasBytes = true; }
    }
    if (!hasBytes)
        dataStr = engine.extractString(args[1]);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : append;
            if (hasBytes) append(path, dataBytes);
            else append(path, dataStr);
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

JSHandle jsFspCopyFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspRename(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspUnlink(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspRmdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspRm(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.rm");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("rm requires a path argument");
    auto path = engine.extractString(args[0]);
    bool recursive = false;
    bool force = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        recursive = engine.extractBool(rv);
        engine.freeValue(rv);
        auto fv = engine.getProperty(args[1], "force");
        force = engine.extractBool(fv);
        engine.freeValue(fv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : remove, rmdirRecurse, isDir, exists;
            if (force && !exists(path))
                return AsyncResult.ok("");
            if (recursive && isDir(path))
                rmdirRecurse(path);
            else
                remove(path);
            return AsyncResult.ok("");
        }
        catch (Exception e)
        {
            if (force)
                return AsyncResult.ok("");
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "rm error"; }
            return AsyncResult.fail(msg);
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspMkdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspReaddir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.readdir");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readdir requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    // Detect { withFileTypes: true } so we can return Dirent objects
    // instead of plain strings. Same option as fs.readdirSync.
    bool withFileTypes = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto wft = engine.getProperty(args[1], "withFileTypes");
        withFileTypes = engine.extractBool(wft);
        engine.freeValue(wft);
    }

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : dirEntries, SpanMode, isFile, isDir, isSymlink;
            import std.path : baseName;
            string result;
            foreach (entry; dirEntries(path, SpanMode.shallow))
            {
                // Encode "<name>:<type>" per entry where type is one of
                // f/d/l/?, separated by newline.
                if (result.length > 0) result ~= "\n";
                char t = '?';
                try { if (entry.isSymlink) t = 'l';
                      else if (entry.isFile) t = 'f';
                      else if (entry.isDir)  t = 'd'; }
                catch (Exception) {}
                result ~= baseName(entry.name);
                result ~= ':';
                result ~= t;
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
        import dun.builtins.fs : createDirentObject;
        // Convert the encoded "name:type\n..." back to either Dirent
        // objects (withFileTypes) or plain strings.
        auto arr = e.newArray();
        if (result.length == 0) return arr;
        uint idx = 0;
        size_t start = 0;
        void emit(string entry) @trusted {
            auto colon = entry.length;
            foreach (i, ch; entry) if (ch == ':') { colon = i; break; }
            auto name = colon < entry.length ? entry[0 .. colon] : entry;
            if (withFileTypes)
            {
                int dtype = 0;  // DT_UNKNOWN
                if (colon + 1 < entry.length)
                {
                    immutable t = entry[colon + 1];
                    if (t == 'f') dtype = 8;       // DT_REG
                    else if (t == 'd') dtype = 4;  // DT_DIR
                    else if (t == 'l') dtype = 10; // DT_LNK
                }
                /* `createDirentObject` calls `engine.newString` on
                   the name, which copies into engine storage. The
                   previous `.idup` was a redundant immutable copy
                   on every directory entry. */
                e.setPropertyIndex(arr, idx++,
                    createDirentObject(e, name, dtype));
            }
            else
            {
                e.setPropertyIndex(arr, idx++, e.newString(name));
            }
        }
        foreach (i, c; result)
        {
            if (c == '\n')
            {
                emit(result[start .. i]);
                start = i + 1;
            }
        }
        if (start < result.length) emit(result[start .. $]);
        return arr;
    });

    return ph.promise;
}

JSHandle jsFspStat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspLstat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspAccess(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspRealpath(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspChmod(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsFspChown(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
                return AsyncResult.fail("EPERM: " ~ errnoMsg() ~ ", chown '" ~ path ~ "'");
        }
        return AsyncResult.ok("");
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

JSHandle jsFspTruncate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
                return AsyncResult.fail("EIO: " ~ errnoMsg() ~ ", truncate '" ~ path ~ "'");
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

// ── symlink ─────────────────────────────────────────────────────

JSHandle jsFspSymlink(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.symlink");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("symlink requires target and path");
    auto target = engine.extractString(args[0]);
    auto path = engine.extractString(args[1]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.unistd : symlink;
            auto ctarget = (target ~ '\0');
            auto cpath = (path ~ '\0');
            if (symlink(ctarget.ptr, cpath.ptr) != 0)
                return AsyncResult.fail("ESYMLINK: " ~ errnoMsg() ~ ", symlink '" ~ target ~ "' -> '" ~ path ~ "'");
            return AsyncResult.ok("");
        }
        else
        {
            return AsyncResult.fail("ENOSYS: symlink is not supported on this platform");
        }
    }, (IJSEngine e, string _) @trusted => e.newUndefined());

    return ph.promise;
}

// ── open (returns FileHandle) ───────────────────────────────────

JSHandle jsFspOpen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in fs.promises.open");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("open requires a path argument");
    auto path = engine.extractString(args[0]);
    string flags = "r";
    if (args.length >= 2 && engine.isString(args[1]))
        flags = engine.extractString(args[1]);
    int mode = FILE_MODE_DEFAULT_FILE;
    if (args.length >= 3 && engine.isNumber(args[2]))
        mode = engine.extractInt(args[2]);

    bool needsRead = (flags == "r" || flags == "r+" || flags == "w+" || flags == "a+");
    bool needsWrite = (flags != "r");
    if (needsRead && !checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    if (needsWrite && !checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        version(Posix)
        {
            import core.sys.posix.fcntl : open;
            int fd = open((path ~ '\0').ptr, parseFsOpenFlags(flags), mode);
            if (fd < 0)
                return AsyncResult.fail("ENOENT: " ~ errnoMsg() ~ ", open '" ~ path ~ "'");
            try
            {
                import std.conv : to;
                return AsyncResult.ok(to!string(fd));
            }
            catch (Exception)
            {
                return AsyncResult.fail("open: conversion error");
            }
        }
        else
        {
            return AsyncResult.fail("ENOSYS: open is not supported on this platform");
        }
    }, (IJSEngine e, string fdStr) @trusted => buildFileHandle(e, fdStr, path));

    return ph.promise;
}

// Cached factory for `fs.promises.open()` FileHandle objects —
// per /debug-native-callback hot-path eval pattern. Pre-cache fix:
// every `fs.promises.open()` re-compiled ~200 lines of JS factory
// source (JSC bytecode cache never evicts). The source string is
// static; the cached handle is reused per Worker. Thread-local
// because each Worker engine pins its own factory.
private static JSHandle _fileHandleFactory;
private static bool _fileHandleFactoryCached = false;

private void ensureFileHandleFactoryCached(IJSEngine engine) @trusted nothrow
{
    if (_fileHandleFactoryCached) return;
    enum string fileHandleFactorySource =
        "(function(fd, path) {"
        ~ "var fs = globalThis.__dun_cjs_fs__;"
        ~ "var fh = { fd: fd, path: path, _closed: false };"
        ~ "fh.read = function(buffer, offset, length, position) {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "var bytesRead = fs.readSync(self.fd, buffer, offset, length, position);"
        ~       "resolve({ bytesRead: bytesRead, buffer: buffer });"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.readFile = function(opts) {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "var content = fs.readFileSync(self.path, opts);"
        ~       "resolve(content);"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.writeFile = function(data, opts) {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "fs.writeFileSync(self.path, data, opts);"
        ~       "resolve();"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.write = function(data) {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "var written = fs.writeSync(self.fd, data);"
        ~       "resolve({ bytesWritten: written });"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.close = function() {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (!self._closed) { fs.closeSync(self.fd); self._closed = true; }"
        ~       "resolve();"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.stat = function() {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "var st = fs.statSync(self.path);"
        ~       "resolve(st);"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "fh.truncate = function(len) {"
        ~   "var self = this;"
        ~   "return new Promise(function(resolve, reject) {"
        ~     "try {"
        ~       "if (self._closed) throw new Error('FileHandle is closed');"
        ~       "fs.truncateSync(self.path, len || 0);"
        ~       "resolve();"
        ~     "} catch(e) { reject(e); }"
        ~   "});"
        ~ "};"
        ~ "return fh;"
        ~ "})";
    try
    {
        auto r = engine.eval(fileHandleFactorySource, "<fs_promises_filehandle>");
        if (!r.isError && engine.isFunction(r.value))
        {
            _fileHandleFactory = r.value;
            _fileHandleFactoryCached = true;
        }
        else
            engine.freeValue(r.value);
    }
    catch (Exception) {}
}

JSHandle buildFileHandle(IJSEngine engine, string fdStr, string path) @trusted
{
    assert(engine !is null, "Null engine in buildFileHandle");
    import std.conv : to;
    int fd;
    try { fd = to!int(fdStr); }
    catch (Exception) { return engine.throwTypeError("Invalid fd in FileHandle"); }

    ensureFileHandleFactoryCached(engine);
    if (!_fileHandleFactoryCached)
        return engine.throwTypeError("FileHandle factory init failed");

    JSHandle[2] callArgs;
    callArgs[0] = engine.newInt(fd);
    callArgs[1] = engine.newString(path);
    auto thisArg = engine.newUndefined();
    auto result = engine.callFunction(
        engine.dupValue(_fileHandleFactory), thisArg, callArgs[0 .. 2]);
    engine.freeValue(callArgs[0]);
    engine.freeValue(callArgs[1]);
    engine.freeValue(thisArg);
    return result;
}

// ── Stat helpers ────────────────────────────────────────────────

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
                // 0xFFFF mask = POSIX `S_IMODE` (file-type bits + perm
                // bits), excluding the kernel-internal flags Linux
                // packs into the upper bits of `st_mode`.
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
