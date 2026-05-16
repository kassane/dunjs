module dun.builtins.fs;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

private enum : size_t {
    READLINK_BUF_SIZE = 4096,
    MAX_READ_LENGTH   = 64 * 1024 * 1024,
}

private enum {
    FILE_MODE_0644 = 0x1A4,
    S_IFREG_0644   = 0x81A4,
}

// ── Cross-platform compatibility layer ──────────────────────────

version(Posix)
{
    private extern(C) nothrow @nogc
    {
        int truncate(const(char)* path, long length);
        int fdatasync(int fd);
    }
}
else version(Windows)
{
    private extern(C) nothrow @nogc
    {
        int _open(const(char)* filename, int oflag, ...);
        int _close(int fd);
        int _read(int fd, void* buffer, uint count);
        int _write(int fd, const(void)* buffer, uint count);
        long _lseeki64(int fd, long offset, int origin);
        int _chsize(int fd, long size);
        int _commit(int fd);
        int _mkdir(const(char)* dirname);
    }
    private enum _O_BINARY = 0x8000;
}

/// File read using C stdio — no D exceptions, portable across all platforms.
private string safeReadFile(string path, out string errMsg) @trusted nothrow
{
    import core.stdc.stdio : FILE, fopen, fread, fclose, fseek, ftell, SEEK_END, SEEK_SET;
    import core.stdc.errno : errno;
    import core.stdc.string : strerror;
    import std.string : fromStringz;

    auto cpath = (path ~ '\0');
    auto fp = fopen(cpath.ptr, "rb");
    if (fp is null)
    {
        auto e = errno;
        try { errMsg = cast(string) fromStringz(strerror(e)); } catch (Exception) { errMsg = "I/O error"; }
        return null;
    }
    scope(exit) fclose(fp);

    fseek(fp, 0, SEEK_END);
    auto size = ftell(fp);
    if (size < 0 || size > MAX_READ_LENGTH)
    {
        errMsg = size < 0 ? "failed to determine file size" : "file too large";
        return null;
    }
    fseek(fp, 0, SEEK_SET);

    char[] buf;
    try { buf = new char[cast(size_t) size]; }
    catch (Exception) { errMsg = "out of memory"; return null; }

    auto nread = fread(buf.ptr, 1, buf.length, fp);
    if (nread != buf.length)
    {
        try { errMsg = cast(string) fromStringz(strerror(errno)); } catch (Exception) { errMsg = "read error"; }
        return null;
    }
    string result;
    try { result = cast(string) buf[0 .. nread]; } catch (Exception) { errMsg = "cast error"; return null; }
    return result;
}

private ubyte[] safeReadFileBytes(string path, out string errMsg) @trusted nothrow
{
    import core.stdc.stdio : FILE, fopen, fread, fclose, fseek, ftell, SEEK_END, SEEK_SET;
    import core.stdc.errno : errno;
    import core.stdc.string : strerror;
    import std.string : fromStringz;

    auto cpath = (path ~ '\0');
    auto fp = fopen(cpath.ptr, "rb");
    if (fp is null)
    {
        auto e = errno;
        try { errMsg = cast(string) fromStringz(strerror(e)); } catch (Exception) { errMsg = "I/O error"; }
        return null;
    }
    scope(exit) fclose(fp);

    fseek(fp, 0, SEEK_END);
    auto size = ftell(fp);
    if (size < 0 || size > MAX_READ_LENGTH)
    {
        errMsg = size < 0 ? "failed to determine file size" : "file too large";
        return null;
    }
    fseek(fp, 0, SEEK_SET);

    ubyte[] buf;
    try { buf = new ubyte[cast(size_t) size]; }
    catch (Exception) { errMsg = "out of memory"; return null; }

    auto nread = fread(buf.ptr, 1, buf.length, fp);
    if (nread != buf.length)
    {
        try { errMsg = cast(string) fromStringz(strerror(errno)); } catch (Exception) { errMsg = "read error"; }
        return null;
    }
    return buf[0 .. nread];
}

/// File write using C stdio — portable across all platforms.
private bool safeWriteFile(string path, string data, out string errMsg) @trusted nothrow
{
    import core.stdc.stdio : FILE, fopen, fwrite, fclose;
    import core.stdc.errno : errno;
    import core.stdc.string : strerror;
    import std.string : fromStringz;

    auto cpath = (path ~ '\0');
    auto fp = fopen(cpath.ptr, "wb");
    if (fp is null)
    {
        auto e = errno;
        try { errMsg = cast(string) fromStringz(strerror(e)); } catch (Exception) { errMsg = "I/O error"; }
        return false;
    }
    scope(exit) fclose(fp);

    if (data.length > 0)
    {
        auto nwritten = fwrite(data.ptr, 1, data.length, fp);
        if (nwritten != data.length)
        {
            try { errMsg = cast(string) fromStringz(strerror(errno)); } catch (Exception) { errMsg = "write error"; }
            return false;
        }
    }
    return true;
}

/// Existence check — portable across POSIX and Windows.
private bool safeExists(string path) @trusted nothrow
{
    version(Posix)
    {
        import core.sys.posix.unistd : access, F_OK;
        auto cpath = (path ~ '\0');
        return access(cpath.ptr, F_OK) == 0;
    }
    else
    {
        import core.stdc.stdio : fopen, fclose;
        auto cpath = (path ~ '\0');
        auto fp = fopen(cpath.ptr, "rb");
        if (fp is null) return false;
        fclose(fp);
        return true;
    }
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
    engine.setProperty(obj, "mkdtempSync", engine.newFunction(&jsMkdtempSync, "mkdtempSync", 1));
    engine.setProperty(obj, "cpSync", engine.newFunction(&jsCpSync, "cpSync", 2));
    engine.setProperty(obj, "utimesSync", engine.newFunction(&jsUtimesSync, "utimesSync", 3));

    auto constRes = engine.eval(fsConstantsSource(), "<fs-constants>");
    if (!constRes.isError)
        engine.setProperty(obj, "constants", constRes.value);
    else
        engine.freeValue(constRes.value);

    auto direntRes = engine.eval(fsDirentSource(), "<fs-dirent>");
    if (!direntRes.isError)
        engine.setProperty(obj, "Dirent", direntRes.value);
    else
        engine.freeValue(direntRes.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_fs__", obj);
    engine.freeValue(global);

    // Install JS-level fs.watchFile / fs.unwatchFile (stat-polling)
    auto watchRes = engine.eval(fsWatchSource(), "<fs-watch>");
    if (watchRes.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("[fs-watch] eval error: ", engine.getException());
            stderr.flush();
        }
        catch (Exception) {}
    }
    engine.freeValue(watchRes.value);

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
        "fdatasyncSync", "createReadStream", "createWriteStream", "watch",
        "watchFile", "unwatchFile", "mkdtempSync", "cpSync", "utimesSync",
        "ftruncateSync", "futimesSync", "lutimesSync",
        "constants", "Dirent"
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:fs", &fsModuleInit);
        if (m is null) return;
        foreach (name; fsExports)
            JS_AddModuleExport(ctx, m, name.ptr);
        JS_AddModuleExport(ctx, m, "default");
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
        JS_SetModuleExport(ctx, m, "default", fsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

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

package struct SafeStatResult
{
    long size;
    uint mode;
    int uid, gid;
    long dev, ino;
    int nlink;
    double atimeMs, mtimeMs, ctimeMs;
    bool isFile, isDir, isLink;
}

version(Posix)
{
    import core.sys.posix.sys.stat : stat_t;

    private SafeStatResult statToResult(ref stat_t buf) @trusted nothrow
    {
        import core.sys.posix.sys.stat : S_ISREG, S_ISDIR, S_ISLNK;
        SafeStatResult r;
        r.isFile = S_ISREG(buf.st_mode);
        r.isDir = S_ISDIR(buf.st_mode);
        r.isLink = S_ISLNK(buf.st_mode);
        r.size = buf.st_size;
        r.mode = buf.st_mode & 0xFFFF;
        r.uid = cast(int) buf.st_uid;
        r.gid = cast(int) buf.st_gid;
        r.dev = buf.st_dev;
        r.ino = buf.st_ino;
        r.nlink = cast(int) buf.st_nlink;
        static if (__traits(hasMember, typeof(buf), "st_atim"))
        {
            r.atimeMs = cast(double)(buf.st_atim.tv_sec * 1000L + buf.st_atim.tv_nsec / 1_000_000L);
            r.mtimeMs = cast(double)(buf.st_mtim.tv_sec * 1000L + buf.st_mtim.tv_nsec / 1_000_000L);
            r.ctimeMs = cast(double)(buf.st_ctim.tv_sec * 1000L + buf.st_ctim.tv_nsec / 1_000_000L);
        }
        else
        {
            r.atimeMs = cast(double)(buf.st_atime) * 1000.0;
            r.mtimeMs = cast(double)(buf.st_mtime) * 1000.0;
            r.ctimeMs = cast(double)(buf.st_ctime) * 1000.0;
        }
        return r;
    }

    private int safeStat(const(char)* cpath, out SafeStatResult result) @trusted nothrow
    {
        import core.sys.posix.sys.stat : stat_t, stat;
        stat_t st;
        auto ret = stat(cpath, &st);
        if (ret == 0) result = statToResult(st);
        return ret;
    }

    private int safeLstat(const(char)* cpath, out SafeStatResult result) @trusted nothrow
    {
        import core.sys.posix.sys.stat : stat_t, lstat;
        stat_t st;
        auto ret = lstat(cpath, &st);
        if (ret == 0) result = statToResult(st);
        return ret;
    }

    private int safeFstat(int fd, out SafeStatResult result) @trusted nothrow
    {
        import core.sys.posix.sys.stat : stat_t, fstat;
        stat_t st;
        auto ret = fstat(fd, &st);
        if (ret == 0) result = statToResult(st);
        return ret;
    }

    JSHandle buildStatFromPosix(IJSEngine engine, ref stat_t buf) @trusted
    {
        auto r = statToResult(buf);
        return buildStatObject(engine, r);
    }
}
else version(Windows)
{
    private int safeStat(const(char)* cpath, out SafeStatResult result) @trusted nothrow
    {
        import core.stdc.stdio : FILE, fopen, fclose, fseek, ftell, SEEK_END;
        result = SafeStatResult.init;
        auto fp = fopen(cpath, "rb");
        if (fp is null) return -1;
        fseek(fp, 0, SEEK_END);
        auto size = ftell(fp);
        fclose(fp);
        result.size = size >= 0 ? size : 0;
        result.isFile = true;
        result.mode = S_IFREG_0644;
        return 0;
    }

    private int safeLstat(const(char)* cpath, out SafeStatResult result) @trusted nothrow
    {
        return safeStat(cpath, result);
    }

    private int safeFstat(int fd, out SafeStatResult result) @trusted nothrow
    {
        result = SafeStatResult.init;
        result.isFile = true;
        return 0;
    }
}

package JSHandle buildStatObject(IJSEngine engine, ref SafeStatResult r) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "_type", engine.newInt(r.isFile ? 1 : r.isDir ? 2 : r.isLink ? 3 : 0));
    engine.setProperty(obj, "size", engine.newFloat(cast(double) r.size));
    engine.setProperty(obj, "mode", engine.newInt(cast(int) r.mode));
    engine.setProperty(obj, "uid", engine.newInt(r.uid));
    engine.setProperty(obj, "gid", engine.newInt(r.gid));
    engine.setProperty(obj, "dev", engine.newFloat(cast(double) r.dev));
    engine.setProperty(obj, "ino", engine.newFloat(cast(double) r.ino));
    engine.setProperty(obj, "nlink", engine.newInt(r.nlink));
    engine.setProperty(obj, "atimeMs", engine.newFloat(r.atimeMs));
    engine.setProperty(obj, "mtimeMs", engine.newFloat(r.mtimeMs));
    engine.setProperty(obj, "ctimeMs", engine.newFloat(r.ctimeMs));
    engine.setProperty(obj, "atime", makeDate(engine, r.atimeMs));
    engine.setProperty(obj, "mtime", makeDate(engine, r.mtimeMs));
    engine.setProperty(obj, "ctime", makeDate(engine, r.ctimeMs));
    engine.setProperty(obj, "birthtimeMs", engine.newFloat(r.ctimeMs));
    engine.setProperty(obj, "birthtime", makeDate(engine, r.ctimeMs));
    ensureStatFnsCached(engine);
    engine.setProperty(obj, "isFile", engine.dupValue(_cachedIsFileFn));
    engine.setProperty(obj, "isDirectory", engine.dupValue(_cachedIsDirFn));
    engine.setProperty(obj, "isSymbolicLink", engine.dupValue(_cachedIsSymlinkFn));
    return obj;
}

JSHandle makeDate(IJSEngine engine, double ms) @trusted
{
    assert(engine !is null, "Null engine in makeDate");
    auto dateCtor = engine.eval("(function(ms){return new Date(ms)})", "<date>");
    if (dateCtor.isError)
    {
        engine.freeValue(dateCtor.value);
        return engine.newNull();
    }
    auto msVal = engine.newFloat(ms);
    auto result = engine.callFunction(dateCtor.value, engine.newUndefined(), (&msVal)[0 .. 1]);
    engine.freeValue(msVal);
    engine.freeValue(dateCtor.value);
    return result;
}

public import dun.security.permissions : checkPerm;

string detectErrCode(string msg) @trusted nothrow
{
    if (msg.length == 0) return "ERR_FS_ERROR";
    import std.string : indexOf;
    try
    {
        if (indexOf(msg, "No such file") >= 0 || indexOf(msg, "not found") >= 0
            || indexOf(msg, "cannot find") >= 0)
            return "ENOENT";
        if (indexOf(msg, "Permission denied") >= 0 || indexOf(msg, "ccess") >= 0)
            return "EACCES";
        if (indexOf(msg, "already exists") >= 0 || indexOf(msg, "File exists") >= 0)
            return "EEXIST";
        if (indexOf(msg, "Not a directory") >= 0)
            return "ENOTDIR";
        if (indexOf(msg, "Is a directory") >= 0)
            return "EISDIR";
        if (indexOf(msg, "not empty") >= 0)
            return "ENOTEMPTY";
        if (indexOf(msg, "No space") >= 0)
            return "ENOSPC";
    }
    catch (Exception) {}
    return "EIO";
}

int errnoFromCode(string code) @safe pure nothrow @nogc
{
    if (code == "ENOENT") return -2;
    if (code == "EACCES") return -13;
    if (code == "EEXIST") return -17;
    if (code == "ENOTDIR") return -20;
    if (code == "EISDIR") return -21;
    if (code == "ENOTEMPTY") return -39;
    if (code == "ENOSPC") return -28;
    if (code == "EPERM") return -1;
    if (code == "EIO") return -5;
    return -1;
}

package JSHandle throwNodeError(IJSEngine engine, string code, string msg,
    string syscall = "", string path = "") @trusted
{
    auto fullMsg = code ~ ": " ~ msg;
    if (syscall.length > 0)
        fullMsg ~= ", " ~ syscall;
    if (path.length > 0)
        fullMsg ~= " '" ~ path ~ "'";

    auto errResult = engine.eval(
        "(function(){var e=new Error('" ~ escapeJs(fullMsg) ~ "');"
        ~ "e.code='" ~ escapeJs(code) ~ "';"
        ~ "e.errno=" ~ intToStr(errnoFromCode(code)) ~ ";"
        ~ (syscall.length > 0 ? "e.syscall='" ~ escapeJs(syscall) ~ "';" : "")
        ~ (path.length > 0 ? "e.path='" ~ escapeJs(path) ~ "';" : "")
        ~ "return e;})()", "<fs-error>");
    if (!errResult.isError)
    {
        auto thrown = engine.throwValue(errResult.value);
        engine.freeValue(errResult.value);
        return thrown;
    }
    engine.freeValue(errResult.value);
    return engine.throwTypeError(fullMsg);
}

JSHandle throwSystemError(IJSEngine engine, string syscall, string path, Exception e) @trusted
{
    string msg = "";
    try { msg = e.msg; } catch (Exception) {}
    string code = detectErrCode(msg);
    return throwNodeError(engine, code, msg, syscall, path);
}

private string escapeJs(string s) @safe pure nothrow
{
    string r;
    foreach (c; s)
    {
        if (c == '\'') r ~= "\\'";
        else if (c == '\\') r ~= "\\\\";
        else if (c == '\n') r ~= "\\n";
        else if (c == '\r') r ~= "\\r";
        else r ~= c;
    }
    return r;
}

private string intToStr(int n) @trusted pure nothrow
{
    if (n == 0) return "0";
    bool neg = n < 0;
    uint v = neg ? cast(uint)(-n) : cast(uint) n;
    char[12] buf;
    int pos = 11;
    while (v > 0) { buf[pos--] = cast(char)('0' + v % 10); v /= 10; }
    if (neg) buf[pos--] = '-';
    return cast(string) buf[pos + 1 .. 12].dup;
}

JSHandle throwPermError(IJSEngine engine, string perm, string path = "") @trusted
{
    return throwNodeError(engine, "ERR_PERMISSION_DENIED",
        "Requires --allow-" ~ perm ~ " permission", "", path);
}

/// Read errno and return the system's localized error message as a
/// GC-allocated string. Safe to call after any libc call that may
/// have set errno. Returns "I/O error" on the rare strerror failure.
package string errnoMsg() @trusted nothrow
{
    import core.stdc.errno : errno;
    import core.stdc.string : strerror;
    import std.string : fromStringz;
    try { return cast(string) fromStringz(strerror(errno)).idup; }
    catch (Exception) { return "I/O error"; }
}

string extractEncoding(IJSEngine engine, scope JSHandle[] args) @trusted
{
    if (args.length < 2) return null;
    if (engine.isString(args[1]))
        return engine.extractString(args[1]);
    if (engine.isObject(args[1]))
    {
        auto enc = engine.getProperty(args[1], "encoding");
        scope(exit) engine.freeValue(enc);
        if (engine.isString(enc))
            return engine.extractString(enc);
    }
    return null;
}

__gshared JSHandle _bufFromFn;
__gshared bool _bufFromCached = false;

void ensureBufFromCached(IJSEngine engine) @trusted
{
    if (_bufFromCached) return;
    auto global = engine.getGlobal();
    auto bufCtor = engine.getProperty(global, "Buffer");
    _bufFromFn = engine.getProperty(bufCtor, "from");
    engine.freeValue(bufCtor);
    engine.freeValue(global);
    _bufFromCached = true;
}

JSHandle createBufferFromBytes(IJSEngine engine, const(ubyte)[] data) @trusted
{
    assert(engine !is null, "Null engine in createBufferFromBytes");
    ensureBufFromCached(engine);

    if (engine.isUndefined(_bufFromFn) || !engine.isFunction(_bufFromFn))
        return engine.newUint8Array(data);

    auto uint8 = engine.newUint8Array(data);
    auto global = engine.getGlobal();
    auto bufCtor = engine.getProperty(global, "Buffer");
    auto result = engine.callFunction(_bufFromFn, bufCtor, [uint8]);
    engine.freeValue(bufCtor);
    engine.freeValue(global);
    engine.freeValue(uint8);
    return result;
}

JSHandle jsReadFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadFileSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadFileSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readFileSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    string encoding = extractEncoding(engine, args);

    if (encoding.length > 0)
    {
        string errMsg;
        auto content = safeReadFile(path, errMsg);
        if (errMsg.length > 0)
            return throwNodeError(engine, "ENOENT", errMsg, "open", path);
        return engine.newString(content !is null ? content : "");
    }

    string errMsg;
    auto bytes = safeReadFileBytes(path, errMsg);
    if (errMsg.length > 0)
        return throwNodeError(engine, "ENOENT", errMsg, "open", path);
    return createBufferFromBytes(engine, bytes);
}

JSHandle jsWriteFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
    string errMsg;
    if (!safeWriteFile(path, data, errMsg))
        return throwNodeError(engine, "EIO", errMsg, "open", path);
    return engine.newUndefined();
}

JSHandle jsExistsSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsExistsSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsExistsSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("existsSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);
    return engine.newBool(safeExists(path));
}

JSHandle jsReaddirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReaddirSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReaddirSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("readdirSync requires a path argument");
    auto dirPath = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, dirPath))
        return throwPermError(engine, "read", dirPath);

    bool withFileTypes = false;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto wftProp = engine.getProperty(args[1], "withFileTypes");
        withFileTypes = engine.extractBool(wftProp);
        engine.freeValue(wftProp);
    }

    version (Posix)
    {
        import core.sys.posix.dirent : DIR, dirent, opendir, readdir, closedir, DT_REG,
            DT_DIR, DT_LNK, DT_FIFO, DT_SOCK, DT_CHR, DT_BLK, DT_UNKNOWN;
        import core.stdc.string : strlen;
        auto cpath = (dirPath ~ '\0');
        auto dir = opendir(cpath.ptr);
        if (dir is null)
            return throwNodeError(engine, "ENOENT", "no such file or directory", "scandir", dirPath);
        scope(exit) closedir(dir);
        auto arr = engine.newArray();
        uint idx = 0;
        while (true)
        {
            auto entry = readdir(dir);
            if (entry is null) break;
            auto name = cast(string) entry.d_name.ptr[0 .. strlen(entry.d_name.ptr)];
            if (name == "." || name == "..") continue;
            if (withFileTypes)
            {
                int dtype = dtypeToDirent(entry.d_type, dirPath, name);
                auto direntObj = createDirentObject(engine, name, dtype);
                engine.setPropertyIndex(arr, idx++, direntObj);
            }
            else
            {
                engine.setPropertyIndex(arr, idx++, engine.newString(name));
            }
        }
        return arr;
    }
    else
    {
        try
        {
            import std.file : dirEntries, SpanMode;
            import std.path : baseName;
            auto arr = engine.newArray();
            uint idx = 0;
            foreach (entry; dirEntries(dirPath, SpanMode.shallow))
                engine.setPropertyIndex(arr, idx++, engine.newString(baseName(entry.name)));
            return arr;
        }
        catch (Exception e) { return throwSystemError(engine, "scandir", dirPath, e); }
    }
}

JSHandle jsStatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("statSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    auto cpath = (path ~ '\0');
    SafeStatResult sr;
    if (safeStat(cpath.ptr, sr) != 0)
        return throwNodeError(engine, "ENOENT", "no such file or directory", "stat", path);
    return buildStatObject(engine, sr);
}

JSHandle jsStatIsFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsFile");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsFile");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    scope(exit) engine.freeValue(typeVal);
    return engine.newBool(engine.extractInt(typeVal) == 1);
}

JSHandle jsStatIsDirectory(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsDirectory");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsDirectory");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    scope(exit) engine.freeValue(typeVal);
    return engine.newBool(engine.extractInt(typeVal) == 2);
}

JSHandle jsMkdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        engine.freeValue(rv);
    }
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    if (recursive)
    {
        try
        {
            import std.file : mkdirRecurse;
            mkdirRecurse(path);
            return engine.newUndefined();
        }
        catch (Exception e) { return throwSystemError(engine, "mkdir", path, e); }
    }
    else
    {
        auto cpath = (path ~ '\0');
        int ret;
        version(Posix)
        {
            import core.sys.posix.sys.stat : mkdir;
            import std.conv : octal;
            ret = mkdir(cpath.ptr, octal!755);
        }
        else version(Windows)
        {
            ret = _mkdir(cpath.ptr);
        }
        if (ret != 0)
        {
            import core.stdc.errno : errno, EEXIST, ENOENT;
            import core.stdc.string : strerror;
            import std.string : fromStringz;
            auto e = errno;
            string code = e == EEXIST ? "EEXIST" : e == ENOENT ? "ENOENT" : "EIO";
            string msg;
            try { msg = cast(string) fromStringz(strerror(e)); } catch (Exception) { msg = "mkdir error"; }
            return engine.throwTypeError(code ~ ": " ~ msg ~ ", mkdir '" ~ path ~ "'");
        }
        return engine.newUndefined();
    }
}

JSHandle jsUnlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsUnlinkSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsUnlinkSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("unlinkSync requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return throwPermError(engine, "write", path);
    import core.stdc.stdio : remove;
    auto cpath = (path ~ '\0');
    if (remove(cpath.ptr) != 0)
        return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", unlink '" ~ path ~ "'");
    return engine.newUndefined();
}

JSHandle jsReadFileAsync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmitSafe, AsyncResult;

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

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : readText;
            return AsyncResult.ok(readText(path));
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "read error"; }
            return AsyncResult.fail(msg);
        }
    });

    return ph.promise;
}

JSHandle jsWriteFileAsync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmitSafe, AsyncResult;

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

    asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {
        try
        {
            import std.file : write;
            write(path, data);
            return AsyncResult.ok("ok");
        }
        catch (Exception e)
        {
            string msg;
            try { msg = e.msg; } catch (Exception) { msg = "write error"; }
            return AsyncResult.fail(msg);
        }
    });

    return ph.promise;
}

JSHandle jsAppendFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsCopyFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsRenameSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsRmdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsRmSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        engine.freeValue(rv);
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

JSHandle jsAccessSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsRealpathSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
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
        else
        {
            import std.path : absolutePath, buildNormalizedPath;
            auto resolved = buildNormalizedPath(absolutePath(path));
            if (!safeExists(resolved))
                return engine.throwTypeError("ENOENT: no such file or directory, realpath '" ~ path ~ "'");
            return engine.newString(resolved);
        }
    }
    catch (Exception e) { return throwSystemError(engine, "realpath", path, e); }
}

JSHandle jsChmodSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsStatIsSymbolicLink(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStatIsSymbolicLink");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStatIsSymbolicLink");
    auto engine = state.engine;
    auto typeVal = engine.getProperty(thisVal, "_type");
    scope(exit) engine.freeValue(typeVal);
    return engine.newBool(engine.extractInt(typeVal) == 3);
}

// ── lstatSync ───────────────────────────────────────────────────

JSHandle jsLstatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        auto cpath = (path ~ '\0');
        SafeStatResult sr;
        if (safeLstat(cpath.ptr, sr) != 0)
            return engine.throwTypeError("ENOENT: no such file or directory, lstat '" ~ path ~ "'");
        return buildStatObject(engine, sr);
    }
    catch (Exception e) { return throwSystemError(engine, "lstat", path, e); }
}

// ── linkSync ────────────────────────────────────────────────────

JSHandle jsLinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
        {
            import core.sys.posix.unistd : link;
            import std.string : toStringz;
            if (link(existingPath.toStringz, newPath.toStringz) != 0)
                return engine.throwTypeError("ELINK: " ~ errnoMsg() ~ ", link '" ~ existingPath ~ "' -> '" ~ newPath ~ "'");
            return engine.newUndefined();
        }
        else
        {
            return engine.throwTypeError("ENOSYS: linkSync is not supported on this platform");
        }
    }
    catch (Exception e) { return throwSystemError(engine, "link", existingPath, e); }
}

// ── symlinkSync ─────────────────────────────────────────────────

JSHandle jsSymlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
        {
            import core.sys.posix.unistd : symlink;
            import std.string : toStringz;
            if (symlink(target.toStringz, path.toStringz) != 0)
                return engine.throwTypeError("ESYMLINK: " ~ errnoMsg() ~ ", symlink '" ~ target ~ "' -> '" ~ path ~ "'");
            return engine.newUndefined();
        }
        else
        {
            return engine.throwTypeError("ENOSYS: symlinkSync is not supported on this platform");
        }
    }
    catch (Exception e) { return throwSystemError(engine, "symlink", target, e); }
}

// ── readlinkSync ────────────────────────────────────────────────

JSHandle jsReadlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
        {
            import core.sys.posix.unistd : readlink;
            import std.string : toStringz;
            char[READLINK_BUF_SIZE] buf;
            auto len = readlink(path.toStringz, buf.ptr, buf.length);
            if (len < 0)
                return engine.throwTypeError("ENOENT: no such file or directory, readlink '" ~ path ~ "'");
            return engine.newString(cast(string) buf[0 .. len]);
        }
        else
        {
            return engine.throwTypeError("ENOSYS: readlinkSync is not supported on this platform");
        }
    }
    catch (Exception e) { return throwSystemError(engine, "readlink", path, e); }
}

// ── truncateSync ────────────────────────────────────────────────

JSHandle jsTruncateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
        {
            import std.string : toStringz;
            if (truncate(path.toStringz, len) != 0)
                return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", truncate '" ~ path ~ "'");
        }
        else version(Windows)
        {
            import std.string : toStringz;
            enum _O_RDWR_WIN = 0x0002, _O_BINARY_WIN = 0x8000;
            auto wfd = _open(path.toStringz, _O_RDWR_WIN | _O_BINARY_WIN);
            if (wfd < 0)
                return engine.throwTypeError("ENOENT: cannot open file, truncate '" ~ path ~ "'");
            if (_chsize(wfd, len) != 0)
            {
                _close(wfd);
                return engine.throwTypeError("EIO: truncate failed, truncate '" ~ path ~ "'");
            }
            _close(wfd);
        }
        return engine.newUndefined();
    }
    catch (Exception e) { return throwSystemError(engine, "truncate", path, e); }
}

// ── chownSync ───────────────────────────────────────────────────

JSHandle jsChownSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        version(Posix)
        {
            import core.sys.posix.unistd : chown;
            import std.string : toStringz;
            if (chown(path.toStringz, uid, gid) != 0)
                return engine.throwTypeError("EPERM: " ~ errnoMsg() ~ ", chown '" ~ path ~ "'");
            return engine.newUndefined();
        }
        else
        {
            return engine.newUndefined();
        }
    }
    catch (Exception e) { return throwSystemError(engine, "chown", path, e); }
}

// ── openSync / closeSync / readSync / writeSync ─────────────────

int parseFsFlags(string flags) nothrow @trusted
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

JSHandle jsOpenSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
    int mode = FILE_MODE_0644;
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
        import std.string : toStringz;
        int fd;
        version(Posix)
        {
            import core.sys.posix.fcntl : open;
            fd = open(path.toStringz, parseFsFlags(flags), mode);
        }
        else version(Windows)
        {
            fd = _open(path.toStringz, parseFsFlags(flags) | _O_BINARY, mode);
        }
        if (fd < 0)
            return engine.throwTypeError("ENOENT: " ~ errnoMsg() ~ ", open '" ~ path ~ "'");
        return engine.newInt(fd);
    }
    catch (Exception e) { return throwSystemError(engine, "open", path, e); }
}

JSHandle jsCloseSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCloseSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCloseSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("closeSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    version(Posix)
    {
        import core.sys.posix.unistd : close;
        close(fd);
    }
    else version(Windows)
    {
        _close(fd);
    }
    return engine.newUndefined();
}

JSHandle jsReadSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
            if (pos >= 0)
            {
                version(Posix)
                {
                    import core.sys.posix.unistd : lseek;
                    import core.sys.posix.sys.types : off_t;
                    lseek(fd, cast(off_t) pos, 0);
                }
                else version(Windows)
                {
                    _lseeki64(fd, cast(long) pos, 0);
                }
            }
            auto buf = new ubyte[length];
            long bytesRead;
            version(Posix)
            {
                import core.sys.posix.unistd : read;
                bytesRead = read(fd, buf.ptr, length);
            }
            else version(Windows)
            {
                bytesRead = _read(fd, buf.ptr, cast(uint) length);
            }
            if (bytesRead < 0)
                return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", read");
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
        auto buf = new ubyte[length];
        long bytesRead;
        version(Posix)
        {
            import core.sys.posix.unistd : read;
            bytesRead = read(fd, buf.ptr, length);
        }
        else version(Windows)
        {
            bytesRead = _read(fd, buf.ptr, cast(uint) length);
        }
        if (bytesRead < 0)
            return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", read");
        return engine.newString(cast(string) buf[0 .. bytesRead]);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EIO: read error");
    }
}

JSHandle jsWriteSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        long written;
        version(Posix)
        {
            import core.sys.posix.unistd : write;
            written = write(fd, data.ptr, data.length);
        }
        else version(Windows)
        {
            written = _write(fd, data.ptr, cast(uint) data.length);
        }
        if (written < 0)
            return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", write");
        return engine.newInt(cast(int) written);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EIO: write error");
    }
}

// ── fstatSync / fsyncSync / fdatasyncSync ───────────────────────

JSHandle jsFstatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFstatSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFstatSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fstatSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    try
    {
        SafeStatResult sr;
        if (safeFstat(fd, sr) != 0)
            return engine.throwTypeError("EBADF: " ~ errnoMsg() ~ ", fstat");
        return buildStatObject(engine, sr);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("EBADF: fstat error");
    }
}

JSHandle jsFsyncSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFsyncSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFsyncSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fsyncSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    int ret;
    version(Posix)
    {
        import core.sys.posix.unistd : fsync;
        ret = fsync(fd);
    }
    else version(Windows)
    {
        ret = _commit(fd);
    }
    if (ret != 0)
        return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", fsync");
    return engine.newUndefined();
}

JSHandle jsFdatasyncSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsFdatasyncSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsFdatasyncSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("fdatasyncSync requires a file descriptor");
    auto fd = engine.extractInt(args[0]);
    int ret;
    version(Posix)
    {
        ret = fdatasync(fd);
    }
    else version(Windows)
    {
        ret = _commit(fd);
    }
    if (ret != 0)
        return engine.throwTypeError("EIO: " ~ errnoMsg() ~ ", fdatasync");
    return engine.newUndefined();
}

// ── createReadStream ────────────────────────────────────────────

// ReadStream state for chunked I/O
private enum RS_HIGH_WATER_MARK = 65_536; // 64 KiB default chunk size
private enum RS_MAX_STREAMS = 256;
private struct ReadStreamState {
    int fd = -1;
    bool ended;
    string encoding;
}
private __gshared ReadStreamState[RS_MAX_STREAMS] rsStates;
private __gshared int rsCount = 0;

JSHandle jsCreateReadStream(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCreateReadStream");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCreateReadStream");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createReadStream requires a path argument");
    auto path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return throwPermError(engine, "read", path);

    string encoding;
    int highWaterMark = RS_HIGH_WATER_MARK;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto encProp = engine.getProperty(args[1], "encoding");
        if (engine.isString(encProp))
            encoding = engine.extractString(encProp);
        engine.freeValue(encProp);
        auto hwmProp = engine.getProperty(args[1], "highWaterMark");
        if (engine.isNumber(hwmProp))
            highWaterMark = engine.extractInt(hwmProp);
        engine.freeValue(hwmProp);
    }

    version (Posix)
    {
        import core.sys.posix.fcntl : open, O_RDONLY;
        import core.sys.posix.unistd : close;
        import core.stdc.string : strerror;
        import core.stdc.errno : errno;

        // Null-terminate path for POSIX open()
        char[4096] pathBuf = void;
        if (path.length >= pathBuf.length)
            return engine.throwTypeError("Path too long");
        pathBuf[0 .. path.length] = path[];
        pathBuf[path.length] = '\0';

        int fd = open(pathBuf.ptr, O_RDONLY);
        if (fd < 0)
        {
            int err = errno;
            if (err == 2) // ENOENT
                return engine.throwTypeError("ENOENT: no such file or directory, open '" ~ path ~ "'");
            return engine.throwTypeError("Failed to open '" ~ path ~ "'");
        }

        if (rsCount >= RS_MAX_STREAMS)
        {
            close(fd);
            return engine.throwTypeError("Too many open read streams");
        }
        int rsId = rsCount++;
        rsStates[rsId].fd = fd;
        rsStates[rsId].ended = false;
        rsStates[rsId].encoding = encoding;

        auto stream = engine.newObject();
        engine.setProperty(stream, "_rsId", engine.newInt(rsId));
        engine.setProperty(stream, "_hwm", engine.newInt(highWaterMark));
        engine.setProperty(stream, "_listeners", engine.newObject());
        engine.setProperty(stream, "_ended", engine.newBool(false));
        engine.setProperty(stream, "readable", engine.newBool(true));
        engine.setProperty(stream, "path", engine.newString(path));
        engine.setProperty(stream, "on", engine.newFunction(&jsStreamOn, "on", 2));
        engine.setProperty(stream, "once", engine.newFunction(&jsStreamOn, "once", 2));
        engine.setProperty(stream, "pipe", engine.newFunction(&jsReadStreamPipe, "pipe", 1));
        engine.setProperty(stream, "destroy", engine.newFunction(&jsReadStreamDestroy, "destroy", 0));
        engine.setProperty(stream, "read", engine.newFunction(&jsReadStreamRead, "read", 0));
        engine.setProperty(stream, "resume", engine.newFunction(&jsReadStreamResume, "resume", 0));

        return stream;
    }
    else
    {
        return engine.throwTypeError("createReadStream not supported on this platform");
    }
}

// ── createWriteStream ───────────────────────────────────────────

JSHandle jsCreateWriteStream(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
    engine.setProperty(stream, "writable", engine.newBool(true));
    engine.setProperty(stream, "path", engine.newString(path));
    engine.setProperty(stream, "bytesWritten", engine.newInt(0));
    engine.setProperty(stream, "on", engine.newFunction(&jsStreamOn, "on", 2));
    engine.setProperty(stream, "once", engine.newFunction(&jsStreamOn, "once", 2));
    engine.setProperty(stream, "write", engine.newFunction(&jsWriteStreamWrite, "write", 1));
    engine.setProperty(stream, "end", engine.newFunction(&jsWriteStreamEnd, "end", 0));
    engine.setProperty(stream, "destroy", engine.newFunction(&jsStreamDestroy, "destroy", 0));
    engine.setProperty(stream, "close", engine.newFunction(&jsStreamDestroy, "close", 0));
    return stream;
}

// ── Stream helpers (shared by createReadStream/createWriteStream) ──

JSHandle jsStreamOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStreamOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsStreamOn");
    auto engine = state.engine;
    if (args.length < 2) return engine.dupValue(thisVal);
    auto eventName = engine.extractString(args[0]);
    auto listeners = engine.getProperty(thisVal, "_listeners");
    engine.setProperty(listeners, eventName, engine.dupValue(args[1]));
    engine.freeValue(listeners);
    return engine.dupValue(thisVal);
}

JSHandle jsStreamDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsStreamDestroy");
    auto state = cast(DunState*) ctx;
    return state.engine.newUndefined();
}

JSHandle jsReadStreamDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamDestroy");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadStreamDestroy");
    auto engine = state.engine;

    auto rsIdProp = engine.getProperty(thisVal, "_rsId");
    int rsId = engine.extractInt(rsIdProp);
    engine.freeValue(rsIdProp);

    if (rsId >= 0 && rsId < rsCount && rsStates[rsId].fd >= 0)
    {
        version (Posix)
        {
            import core.sys.posix.unistd : close;
            close(rsStates[rsId].fd);
        }
        rsStates[rsId].fd = -1;
        rsStates[rsId].ended = true;
    }
    engine.setProperty(thisVal, "_ended", engine.newBool(true));
    engine.setProperty(thisVal, "readable", engine.newBool(false));
    return engine.newUndefined();
}

JSHandle jsReadStreamResume(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamResume");
    auto state = cast(DunState*) ctx;
    return state.engine.dupValue(thisVal);
}

JSHandle jsReadStreamRead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamRead");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadStreamRead");
    auto engine = state.engine;

    auto endedProp = engine.getProperty(thisVal, "_ended");
    auto ended = engine.extractBool(endedProp);
    engine.freeValue(endedProp);
    if (ended) return engine.newNull();

    auto rsIdProp = engine.getProperty(thisVal, "_rsId");
    int rsId = engine.extractInt(rsIdProp);
    engine.freeValue(rsIdProp);

    if (rsId < 0 || rsId >= rsCount || rsStates[rsId].fd < 0)
    {
        engine.setProperty(thisVal, "_ended", engine.newBool(true));
        return engine.newNull();
    }

    version (Posix)
    {
        import core.sys.posix.unistd : read, close;
        import dun.builtins.buffer : makeBufferObj;

        int fd = rsStates[rsId].fd;
        auto hwmProp = engine.getProperty(thisVal, "_hwm");
        int hwm = engine.extractInt(hwmProp);
        engine.freeValue(hwmProp);
        if (hwm <= 0) hwm = RS_HIGH_WATER_MARK;

        ubyte[] collected;
        auto chunk = new ubyte[hwm];

        while (true)
        {
            auto nread = read(fd, chunk.ptr, chunk.length);
            if (nread <= 0) break;
            collected ~= chunk[0 .. nread];
        }

        close(fd);
        rsStates[rsId].fd = -1;
        rsStates[rsId].ended = true;
        engine.setProperty(thisVal, "_ended", engine.newBool(true));
        engine.setProperty(thisVal, "readable", engine.newBool(false));

        if (collected.length == 0)
            return engine.newNull();

        string enc = rsStates[rsId].encoding;
        if (enc == "utf8" || enc == "utf-8")
            return engine.newString(cast(string) cast(char[]) collected);

        return makeBufferObj(engine, collected);
    }
    else
    {
        return engine.newNull();
    }
}

JSHandle jsReadStreamPipe(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReadStreamPipe");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReadStreamPipe");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("pipe requires a destination");

    auto data = jsReadStreamRead(ctx, thisVal, null);
    if (!engine.isNull(data))
    {
        auto writeFn = engine.getProperty(args[0], "write");
        if (engine.isFunction(writeFn))
            engine.callFunction(writeFn, args[0], [data]);
        engine.freeValue(writeFn);
    }
    engine.freeValue(data);

    auto endFn = engine.getProperty(args[0], "end");
    if (engine.isFunction(endFn))
        engine.callFunction(endFn, args[0], []);
    engine.freeValue(endFn);
    return engine.dupValue(args[0]);
}

JSHandle jsWriteStreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteStreamWrite");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteStreamWrite");
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    auto chunks = engine.getProperty(thisVal, "_chunks");
    auto countProp = engine.getProperty(thisVal, "_chunkCount");
    auto idx = engine.extractInt(countProp);
    engine.freeValue(countProp);
    engine.setPropertyIndex(chunks, cast(uint) idx, engine.dupValue(args[0]));
    engine.freeValue(chunks);
    engine.setProperty(thisVal, "_chunkCount", engine.newInt(idx + 1));
    return engine.newBool(true);
}

JSHandle jsWriteStreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWriteStreamEnd");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWriteStreamEnd");
    auto engine = state.engine;
    if (args.length >= 1 && engine.isString(args[0]))
    {
        auto chunks0 = engine.getProperty(thisVal, "_chunks");
        auto countProp0 = engine.getProperty(thisVal, "_chunkCount");
        auto idx = engine.extractInt(countProp0);
        engine.freeValue(countProp0);
        engine.setPropertyIndex(chunks0, cast(uint) idx, engine.dupValue(args[0]));
        engine.freeValue(chunks0);
        engine.setProperty(thisVal, "_chunkCount", engine.newInt(idx + 1));
    }
    auto pathProp = engine.getProperty(thisVal, "_path");
    auto path = engine.extractString(pathProp);
    engine.freeValue(pathProp);
    auto chunks = engine.getProperty(thisVal, "_chunks");
    auto countProp = engine.getProperty(thisVal, "_chunkCount");
    auto count = engine.extractInt(countProp);
    engine.freeValue(countProp);
    string allData;
    foreach (i; 0 .. count)
    {
        auto elem = engine.getPropertyIndex(chunks, cast(uint) i);
        allData ~= engine.extractString(elem);
        engine.freeValue(elem);
    }
    engine.freeValue(chunks);
    try
    {
        import std.file : write;
        write(path, allData);
        engine.setProperty(thisVal, "_ended", engine.newBool(true));
        engine.setProperty(thisVal, "writable", engine.newBool(false));
        engine.setProperty(thisVal, "bytesWritten", engine.newInt(cast(int) allData.length));
        auto streamRef = engine.dupValue(thisVal);
        auto emitFn = engine.eval(
            "(function(s){process.nextTick(function(){"
            ~ "var l=s._listeners;"
            ~ "if(l&&typeof l.finish==='function')l.finish.call(s);"
            ~ "if(l&&typeof l.close==='function')l.close.call(s);"
            ~ "});})", "<ws:emit>"
        );
        if (!emitFn.isError)
            engine.callFunction(emitFn.value, engine.newUndefined(), [streamRef]);
        engine.freeValue(emitFn.value);
        engine.freeValue(streamRef);
    }
    catch (Exception) {}
    return engine.newUndefined();
}

// ── watch ───────────────────────────────────────────────────────

JSHandle jsWatch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatch");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatch");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsWatch");
    if (args.length < 1) return engine.throwTypeError("watch requires a filename argument");
    auto filename = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, filename))
        return throwPermError(engine, "read", filename);

    // Parse options and listener from flexible argument order:
    //   watch(filename, listener)
    //   watch(filename, options, listener)
    //   watch(filename, options)
    //   watch(filename)
    int pollInterval = 1000;
    bool hasListener = false;
    JSHandle listenerFn;

    if (args.length >= 3 && engine.isObject(args[1]) && engine.isFunction(args[2]))
    {
        // watch(filename, options, listener)
        auto intervalProp = engine.getProperty(args[1], "interval");
        if (!engine.isUndefined(intervalProp))
        {
            auto iv = engine.extractInt(intervalProp);
            if (iv > 0) pollInterval = iv;
        }
        engine.freeValue(intervalProp);
        hasListener = true;
        listenerFn = args[2];
    }
    else if (args.length >= 2 && engine.isFunction(args[1]))
    {
        // watch(filename, listener)
        hasListener = true;
        listenerFn = args[1];
    }
    else if (args.length >= 2 && engine.isObject(args[1]))
    {
        // watch(filename, options)
        auto intervalProp = engine.getProperty(args[1], "interval");
        if (!engine.isUndefined(intervalProp))
        {
            auto iv = engine.extractInt(intervalProp);
            if (iv > 0) pollInterval = iv;
        }
        engine.freeValue(intervalProp);
    }

    auto watcher = engine.newObject();
    engine.setProperty(watcher, "filename", engine.newString(filename));
    engine.setProperty(watcher, "_closed", engine.newBool(false));
    engine.setProperty(watcher, "_listeners", engine.newObject());
    engine.setProperty(watcher, "close", engine.newFunction(&jsWatcherClose, "close", 0));
    engine.setProperty(watcher, "on", engine.newFunction(&jsWatcherOn, "on", 2));
    engine.setProperty(watcher, "ref", engine.newFunction(&jsWatcherRef, "ref", 0));
    engine.setProperty(watcher, "unref", engine.newFunction(&jsWatcherUnref, "unref", 0));

    // If listener provided, register as 'change' listener
    if (hasListener)
    {
        auto listeners = engine.getProperty(watcher, "_listeners");
        engine.setProperty(listeners, "change", listenerFn);
        engine.freeValue(listeners);
    }

    // Get initial stat for comparison
    auto cpath = (filename ~ '\0');
    SafeStatResult sr;
    bool hadStat = safeStat(cpath.ptr, sr) == 0;
    engine.setProperty(watcher, "_hadStat", engine.newBool(hadStat));
    if (hadStat)
    {
        engine.setProperty(watcher, "_prevMtimeMs", engine.newFloat(sr.mtimeMs));
        engine.setProperty(watcher, "_prevSize", engine.newFloat(cast(double) sr.size));
    }
    else
    {
        engine.setProperty(watcher, "_prevMtimeMs", engine.newFloat(0.0));
        engine.setProperty(watcher, "_prevSize", engine.newFloat(0.0));
    }

    // Store watcher in global registry for polling from JS timer
    engine.setProperty(watcher, "_pollInterval", engine.newInt(pollInterval));
    engine.setProperty(watcher, "_pollFn", engine.newFunction(&jsWatcherPoll, "_poll", 0));

    // Start polling via JS setInterval
    auto startPollSrc = "(function(w) {"
        ~ "w._timer = setInterval(function() {"
        ~ "  if (w._closed) { clearInterval(w._timer); return; }"
        ~ "  w._pollFn.call(w);"
        ~ "}, w._pollInterval);"
        ~ "return w;"
        ~ "})";
    auto evalRes = engine.eval(startPollSrc, "<fs-watch-start>");
    if (!evalRes.isError)
    {
        auto global = engine.getGlobal();
        engine.callFunction(evalRes.value, global, [watcher]);
        engine.freeValue(global);
    }
    engine.freeValue(evalRes.value);

    return watcher;
}

JSHandle jsWatcherPoll(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherPoll");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherPoll");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsWatcherPoll");

    auto closedProp = engine.getProperty(thisVal, "_closed");
    auto closed = engine.extractBool(closedProp);
    engine.freeValue(closedProp);
    if (closed) return engine.newUndefined();

    auto filenameProp = engine.getProperty(thisVal, "filename");
    auto filename = engine.extractString(filenameProp);
    engine.freeValue(filenameProp);

    auto prevMtimeProp = engine.getProperty(thisVal, "_prevMtimeMs");
    auto prevMtime = engine.extractFloat(prevMtimeProp);
    engine.freeValue(prevMtimeProp);

    auto prevSizeProp = engine.getProperty(thisVal, "_prevSize");
    auto prevSize = engine.extractFloat(prevSizeProp);
    engine.freeValue(prevSizeProp);

    auto hadStatProp = engine.getProperty(thisVal, "_hadStat");
    auto hadStat = engine.extractBool(hadStatProp);
    engine.freeValue(hadStatProp);

    auto cpath = (filename ~ '\0');
    SafeStatResult sr;
    bool hasStat = safeStat(cpath.ptr, sr) == 0;

    string eventType = null;
    if (hadStat && !hasStat)
    {
        // File was removed
        eventType = "rename";
        engine.setProperty(thisVal, "_hadStat", engine.newBool(false));
        engine.setProperty(thisVal, "_prevMtimeMs", engine.newFloat(0.0));
        engine.setProperty(thisVal, "_prevSize", engine.newFloat(0.0));
    }
    else if (!hadStat && hasStat)
    {
        // File was created
        eventType = "rename";
        engine.setProperty(thisVal, "_hadStat", engine.newBool(true));
        engine.setProperty(thisVal, "_prevMtimeMs", engine.newFloat(sr.mtimeMs));
        engine.setProperty(thisVal, "_prevSize", engine.newFloat(cast(double) sr.size));
    }
    else if (hasStat)
    {
        // File exists, check for changes
        if (sr.mtimeMs != prevMtime || cast(double) sr.size != prevSize)
        {
            eventType = "change";
            engine.setProperty(thisVal, "_prevMtimeMs", engine.newFloat(sr.mtimeMs));
            engine.setProperty(thisVal, "_prevSize", engine.newFloat(cast(double) sr.size));
        }
    }

    if (eventType !is null)
    {
        auto listeners = engine.getProperty(thisVal, "_listeners");
        auto changeCb = engine.getProperty(listeners, "change");
        if (engine.isFunction(changeCb))
        {
            auto evtArg = engine.newString(eventType);
            auto fnArg = engine.newString(filename);
            auto global = engine.getGlobal();
            engine.callFunction(changeCb, global, [evtArg, fnArg]);
            engine.freeValue(global);
            engine.freeValue(evtArg);
            engine.freeValue(fnArg);
        }
        engine.freeValue(changeCb);
        engine.freeValue(listeners);
    }

    return engine.newUndefined();
}

JSHandle jsWatcherClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherClose");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherClose");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsWatcherClose");
    engine.setProperty(thisVal, "_closed", engine.newBool(true));
    // Clear the interval timer via JS
    auto clearSrc = "(function(w) { if (w._timer) { clearInterval(w._timer); w._timer = null; } })";
    auto evalRes = engine.eval(clearSrc, "<fs-watch-close>");
    if (!evalRes.isError)
    {
        auto global = engine.getGlobal();
        engine.callFunction(evalRes.value, global, [thisVal]);
        engine.freeValue(global);
    }
    engine.freeValue(evalRes.value);
    return engine.newUndefined();
}

JSHandle jsWatcherOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherOn");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsWatcherOn");
    if (args.length < 2) return engine.dupValue(thisVal);
    auto eventName = engine.extractString(args[0]);
    auto listeners = engine.getProperty(thisVal, "_listeners");
    engine.setProperty(listeners, eventName, engine.dupValue(args[1]));
    engine.freeValue(listeners);
    return engine.dupValue(thisVal);
}

JSHandle jsWatcherRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherRef");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherRef");
    return state.engine.dupValue(thisVal);
}

JSHandle jsWatcherUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWatcherUnref");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWatcherUnref");
    return state.engine.dupValue(thisVal);
}

// ── mkdtempSync ─────────────────────────────────────────────────

JSHandle jsMkdtempSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsMkdtempSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsMkdtempSync");
    auto engine = state.engine;
    if (args.length < 1)
        return engine.throwTypeError("mkdtempSync requires a prefix argument");
    auto prefix = engine.extractString(args[0]);
    if (!state.permissions.check(Permission.write, prefix))
        return engine.throwTypeError("Requires --allow-write permission");
    version (Posix)
    {
        import core.sys.posix.stdlib : mkdtemp;
        auto tmpl = prefix ~ "XXXXXX";
        char[] buf = tmpl.dup;
        buf ~= '\0';
        auto result = mkdtemp(buf.ptr);
        if (result is null)
            return engine.throwTypeError("ENOENT: mkdtempSync failed");
        import core.stdc.string : strlen;
        return engine.newString(cast(string) buf[0 .. strlen(result)]);
    }
    else
        return engine.throwTypeError("mkdtempSync not supported on this platform");
}

// ── cpSync ──────────────────────────────────────────────────────

JSHandle jsCpSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCpSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCpSync");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("cpSync requires source and destination arguments");
    auto src = engine.extractString(args[0]);
    auto dst = engine.extractString(args[1]);
    if (!state.permissions.check(Permission.read, src))
        return engine.throwTypeError("Requires --allow-read permission");
    if (!state.permissions.check(Permission.write, dst))
        return engine.throwTypeError("Requires --allow-write permission");

    bool recursive = false;
    if (args.length >= 3 && engine.isObject(args[2]))
    {
        auto recProp = engine.getProperty(args[2], "recursive");
        scope(exit) engine.freeValue(recProp);
        if (!engine.isUndefined(recProp) && !engine.isNull(recProp))
            recursive = engine.extractBool(recProp);
    }

    try
    {
        import std.file : isDir, copy, dirEntries, SpanMode, mkdirRecurse;
        if (isDir(src))
        {
            if (!recursive)
                return engine.throwTypeError(
                    "ERR_FS_CP_DIR_TO_NON_DIR: source is a directory, use {recursive: true}");
            mkdirRecurse(dst);
            foreach (entry; dirEntries(src, SpanMode.breadth))
            {
                import std.path : relativePath, buildPath;
                auto rel = relativePath(entry.name, src);
                auto target = buildPath(dst, rel);
                if (entry.isDir)
                    mkdirRecurse(target);
                else
                    copy(entry.name, target);
            }
        }
        else
            copy(src, dst);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("cpSync failed: " ~ e.msg);
    }
}

// ── utimesSync ──────────────────────────────────────────────────

JSHandle jsUtimesSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsUtimesSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsUtimesSync");
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("utimesSync requires path, atime, and mtime");
    auto filePath = engine.extractString(args[0]);
    if (!state.permissions.check(Permission.write, filePath))
        return engine.throwTypeError("Requires --allow-write permission");
    version (Posix)
    {
        import core.sys.posix.utime : utimbuf, utime;
        import std.string : toStringz;
        auto atime = cast(long) engine.extractFloat(args[1]);
        auto mtime = cast(long) engine.extractFloat(args[2]);
        utimbuf times;
        times.actime = atime;
        times.modtime = mtime;
        if (utime(toStringz(filePath), &times) != 0)
            return engine.throwTypeError("ENOENT: utimesSync failed for '" ~ filePath ~ "'");
        return engine.newUndefined();
    }
    else
        return engine.throwTypeError("utimesSync not supported on this platform");
}

// ── watchFile / unwatchFile (JS-level stat polling) ─────────────

string fsWatchSource() pure @safe nothrow
{
    return `(function() {
  var fs = globalThis.__dun_cjs_fs__;
  if (!fs) return;

  var _statWatchers = {};

  function StatWatcher(filename, options, listener) {
    this._filename = filename;
    this._closed = false;
    this._persistent = options ? options.persistent !== false : true;
    this._interval = (options && typeof options.interval === 'number' && options.interval > 0)
      ? options.interval : 5007;
    this._listeners = [];
    this._prevStat = null;
    this._timer = null;

    try { this._prevStat = fs.statSync(filename); } catch(e) {
      this._prevStat = { dev: 0, mode: 0, nlink: 0, uid: 0, gid: 0, size: 0,
        atimeMs: 0, mtimeMs: 0, ctimeMs: 0, ino: 0,
        isFile: function(){return false;}, isDirectory: function(){return false;},
        isSymbolicLink: function(){return false;} };
    }

    if (typeof listener === 'function') {
      this._listeners.push(listener);
    }

    var self = this;
    this._timer = setInterval(function() {
      if (self._closed) return;
      var curr;
      try { curr = fs.statSync(self._filename); } catch(e) {
        curr = { dev: 0, mode: 0, nlink: 0, uid: 0, gid: 0, size: 0,
          atimeMs: 0, mtimeMs: 0, ctimeMs: 0, ino: 0,
          isFile: function(){return false;}, isDirectory: function(){return false;},
          isSymbolicLink: function(){return false;} };
      }
      var prev = self._prevStat;
      if (curr.mtimeMs !== prev.mtimeMs || curr.size !== prev.size) {
        self._prevStat = curr;
        for (var i = 0; i < self._listeners.length; i++) {
          try { self._listeners[i](curr, prev); } catch(e) {}
        }
      }
    }, self._interval);
  }

  StatWatcher.prototype.close = function() {
    this._closed = true;
    if (this._timer) { clearInterval(this._timer); this._timer = null; }
  };

  StatWatcher.prototype.ref = function() { return this; };
  StatWatcher.prototype.unref = function() { return this; };

  StatWatcher.prototype.on = function(ev, cb) {
    if (ev === 'change' && typeof cb === 'function') {
      this._listeners.push(cb);
    }
    return this;
  };

  StatWatcher.prototype.removeListener = function(ev, cb) {
    if (ev === 'change') {
      var idx = this._listeners.indexOf(cb);
      if (idx !== -1) this._listeners.splice(idx, 1);
    }
    return this;
  };

  fs.watchFile = function(filename, options, listener) {
    if (typeof options === 'function') {
      listener = options;
      options = {};
    }
    if (typeof listener !== 'function') {
      throw new TypeError('"listener" argument must be a function');
    }
    var key = '' + filename;
    if (_statWatchers[key]) {
      _statWatchers[key]._listeners.push(listener);
      return _statWatchers[key];
    }
    var watcher = new StatWatcher(filename, options || {}, listener);
    _statWatchers[key] = watcher;
    return watcher;
  };

  fs.unwatchFile = function(filename, listener) {
    var key = '' + filename;
    var watcher = _statWatchers[key];
    if (!watcher) return;
    if (typeof listener === 'function') {
      var idx = watcher._listeners.indexOf(listener);
      if (idx !== -1) watcher._listeners.splice(idx, 1);
      if (watcher._listeners.length === 0) {
        watcher.close();
        delete _statWatchers[key];
      }
    } else {
      watcher.close();
      delete _statWatchers[key];
    }
  };

  if (!fs.ftruncateSync) fs.ftruncateSync = function(fd, len) { throw new Error('fs.ftruncateSync requires fd-based API (not yet implemented)'); };
  if (!fs.futimesSync) fs.futimesSync = function(fd, atime, mtime) { throw new Error('fs.futimesSync requires fd-based API (not yet implemented)'); };
  if (!fs.lutimesSync) fs.lutimesSync = function(path, atime, mtime) { fs.utimesSync(path, atime, mtime); };

  globalThis.__dun_cjs_fs__ = fs;
})()`;
}

string fsConstantsSource() pure nothrow @safe
{
    return `(function() {
    return {
        F_OK: 0, R_OK: 4, W_OK: 2, X_OK: 1,
        COPYFILE_EXCL: 1, COPYFILE_FICLONE: 2, COPYFILE_FICLONE_FORCE: 4,
        O_RDONLY: 0, O_WRONLY: 1, O_RDWR: 2, O_CREAT: 64, O_EXCL: 128,
        O_NOCTTY: 256, O_TRUNC: 512, O_APPEND: 1024, O_DIRECTORY: 65536,
        O_NOATIME: 262144, O_NOFOLLOW: 131072, O_SYNC: 1052672, O_DSYNC: 4096,
        O_NONBLOCK: 2048,
        S_IFMT: 61440, S_IFREG: 32768, S_IFDIR: 16384, S_IFCHR: 8192,
        S_IFBLK: 24576, S_IFIFO: 4096, S_IFLNK: 40960, S_IFSOCK: 49152,
        S_IRWXU: 448, S_IRUSR: 256, S_IWUSR: 128, S_IXUSR: 64,
        S_IRWXG: 56, S_IRGRP: 32, S_IWGRP: 16, S_IXGRP: 8,
        S_IRWXO: 7, S_IROTH: 4, S_IWOTH: 2, S_IXOTH: 1,
        UV_FS_SYMLINK_DIR: 1, UV_FS_SYMLINK_JUNCTION: 2,
        UV_DIRENT_UNKNOWN: 0, UV_DIRENT_FILE: 1, UV_DIRENT_DIR: 2,
        UV_DIRENT_LINK: 3, UV_DIRENT_FIFO: 4, UV_DIRENT_SOCKET: 5,
        UV_DIRENT_CHAR: 6, UV_DIRENT_BLOCK: 7
    };
})()`;
}

version (Posix)
{
    int dtypeToDirent(ubyte dtype, string dirPath, string name) nothrow @trusted
    {
        import core.sys.posix.dirent : DT_REG, DT_DIR, DT_LNK, DT_FIFO, DT_SOCK, DT_CHR, DT_BLK, DT_UNKNOWN;
        switch (dtype)
        {
            case DT_REG: return 1;
            case DT_DIR: return 2;
            case DT_LNK: return 3;
            case DT_FIFO: return 4;
            case DT_SOCK: return 5;
            case DT_CHR: return 6;
            case DT_BLK: return 7;
            default:
                import core.sys.posix.sys.stat : stat_t, lstat, S_ISREG, S_ISDIR, S_ISLNK;
                try
                {
                    auto fullPath = dirPath ~ "/" ~ name ~ '\0';
                    stat_t st;
                    if (lstat(fullPath.ptr, &st) == 0)
                    {
                        if (S_ISREG(st.st_mode)) return 1;
                        if (S_ISDIR(st.st_mode)) return 2;
                        if (S_ISLNK(st.st_mode)) return 3;
                    }
                }
                catch (Exception) {}
                return 0;
        }
    }
}

JSHandle createDirentObject(IJSEngine engine, string name, int dtype) @trusted
{
    auto global = engine.getGlobal();
    auto factory = engine.getProperty(global, "__dunDirentFactory__");
    engine.freeValue(global);
    if (engine.isFunction(factory))
    {
        auto nameVal = engine.newString(name);
        auto typeVal = engine.newInt(dtype);
        auto undef = engine.newUndefined();
        JSHandle[2] callArgs = [nameVal, typeVal];
        auto result = engine.callFunction(factory, undef, callArgs[]);
        engine.freeValue(nameVal);
        engine.freeValue(typeVal);
        engine.freeValue(undef);
        engine.freeValue(factory);
        return result;
    }
    engine.freeValue(factory);
    auto obj = engine.newObject();
    engine.setProperty(obj, "name", engine.newString(name));
    engine.setProperty(obj, "_type", engine.newInt(dtype));
    return obj;
}

string fsDirentSource() pure nothrow @safe
{
    return `(function() {
    function Dirent(name, type) {
        this.name = name;
        this._type = type;
    }
    Dirent.prototype.isFile = function() { return this._type === 1; };
    Dirent.prototype.isDirectory = function() { return this._type === 2; };
    Dirent.prototype.isSymbolicLink = function() { return this._type === 3; };
    Dirent.prototype.isFIFO = function() { return this._type === 4; };
    Dirent.prototype.isSocket = function() { return this._type === 5; };
    Dirent.prototype.isCharacterDevice = function() { return this._type === 6; };
    Dirent.prototype.isBlockDevice = function() { return this._type === 7; };
    globalThis.__dunDirentFactory__ = function(name, type) { return new Dirent(name, type); };
    return Dirent;
})()`;
}

