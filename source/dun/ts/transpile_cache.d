/// Persistent transpile cache for the default tsc TS->JS path.
///
/// Skip the ~300-700 ms cold-start of loading typescript +
/// `transpileModule()` when the same source file was already
/// transpiled with the same compiler options. Cache key is the
/// SHA-256 of (source bytes + filename + compiler-options
/// fingerprint + typescript version), so any change to inputs
/// invalidates exactly its own entries.
///
/// Cache layout:
///   ~/.dun/cache/tsc/<first-2-chars>/<full-hash>.js
///
/// Eviction: bounded by `DUN_TSC_CACHE_MAX_ENTRIES` (default 2000)
/// and `DUN_TSC_CACHE_MAX_MB` (default 64). When the cache exceeds
/// either limit, the oldest-modified files are dropped.
module dun.ts.transpile_cache;

import std.file : exists, mkdirRecurse, write, read, dirEntries,
                  SpanMode, remove, getSize, timeLastModified;
import std.path : buildPath, dirName;
import std.digest.sha : sha256Of;
import std.algorithm : sort, min;
import std.array : array;
import std.process : environment;
import std.conv : to;

private string cacheRoot() @trusted
{
    import dun.platform.paths : dunGlobalRoot;
    return buildPath(dunGlobalRoot(), "cache", "tsc");
}

/// Build the cache key for a transpile request. The compiler-options
/// fingerprint is a static string today (we use the same options for
/// every transpile); when that changes, bump the literal here so
/// stale entries from older configs invalidate automatically.
string cacheKey(scope const(char)[] source, string filename,
    string tscVersion) @safe
{
    enum string COMPILER_OPTS_FINGERPRINT =
        "esnext-esnext-jsx:react-decorators:legacy-isolated:on-v1";
    ubyte[32] hash = sha256Of(
        cast(const(ubyte)[]) source,
        cast(const(ubyte)[]) filename,
        cast(const(ubyte)[]) tscVersion,
        cast(const(ubyte)[]) COMPILER_OPTS_FINGERPRINT);
    char[64] hex;
    static immutable hexChars = "0123456789abcdef";
    foreach (i, b; hash)
    {
        hex[i * 2]     = hexChars[b >> 4];
        hex[i * 2 + 1] = hexChars[b & 0xF];
    }
    return hex.idup;
}

/// Read a cached transpile result. Returns the cached JS or null on miss.
string lookup(string key) @trusted
{
    try
    {
        auto path = buildPath(cacheRoot(), key[0 .. 2], key ~ ".js");
        if (!exists(path)) return null;
        return cast(string) read(path);
    }
    catch (Throwable) { return null; }
}

/// Store a transpile result under the given key. Best-effort: if the
/// disk write fails (full disk, permissions, etc.) we silently skip --
/// the caller already has the in-memory output.
void store(string key, string output) @trusted
{
    assert(key.length == 64, "cache key must be 64-char SHA-256 hex");
    try
    {
        auto dir = buildPath(cacheRoot(), key[0 .. 2]);
        if (!exists(dir)) mkdirRecurse(dir);
        auto path = buildPath(dir, key ~ ".js");
        write(path, output);
    }
    catch (Throwable e)
    {
        import std.process : environment;
        if (environment.get("DUN_TSC_CACHE_DEBUG", "") == "1")
        {
            import std.stdio : stderr;
            try { stderr.writeln("dun: tsc cache store failed: ", e.msg); }
            catch (Throwable) {}
        }
    }
    // Best-effort trim. Self-rate-limited via .last_trim marker file
    // (see maybeTrim()) so this is cheap to call on every store.
    maybeTrim();
}

/// Best-effort cache trim. Called once per `store()` but rate-limited
/// via an mtime marker file (since every `dun` invocation is a fresh
/// process, an in-process counter would never advance). Trims at most
/// once per `DUN_TSC_CACHE_TRIM_INTERVAL_SECS` (default 300 = 5 min).
/// Errors are swallowed.
void maybeTrim() @trusted
{
    import std.datetime : Clock;
    enum long DEFAULT_TRIM_INTERVAL_SECS = 300;
    enum string DEFAULT_MAX_ENTRIES = "2000";
    enum string DEFAULT_MAX_MB = "64";

    immutable long trimIntervalSecs = environment.get(
        "DUN_TSC_CACHE_TRIM_INTERVAL_SECS",
        DEFAULT_TRIM_INTERVAL_SECS.to!string).to!long;

    auto root = cacheRoot();
    if (!exists(root)) return;
    auto marker = buildPath(root, ".last_trim");
    immutable now = Clock.currTime.toUnixTime;
    if (exists(marker))
    {
        try
        {
            immutable lastTrim = timeLastModified(marker).toUnixTime;
            if (now - lastTrim < trimIntervalSecs) return;
        }
        catch (Throwable) {}
    }
    // Touch marker first so concurrent dun invocations bail out fast.
    try { write(marker, ""); }
    catch (Throwable) { return; }

    immutable maxEntries = environment.get(
        "DUN_TSC_CACHE_MAX_ENTRIES", DEFAULT_MAX_ENTRIES).to!int;
    immutable maxBytes   = environment.get(
        "DUN_TSC_CACHE_MAX_MB",      DEFAULT_MAX_MB).to!size_t * 1024 * 1024;
    assert(maxEntries > 0, "DUN_TSC_CACHE_MAX_ENTRIES must be > 0");
    assert(maxBytes   > 0, "DUN_TSC_CACHE_MAX_MB must be > 0");

    try
    {
        struct Entry { string path; size_t size; long mtime; }
        Entry[] entries;
        foreach (de; dirEntries(root, "*.js", SpanMode.depth))
        {
            entries ~= Entry(de.name, getSize(de.name),
                timeLastModified(de.name).stdTime);
        }
        sort!"a.mtime < b.mtime"(entries);
        size_t totalSize = 0;
        foreach (e; entries) totalSize += e.size;
        size_t i = 0;
        while ((entries.length - i > maxEntries
             || totalSize > maxBytes) && i < entries.length)
        {
            try { remove(entries[i].path); totalSize -= entries[i].size; }
            catch (Throwable) {}
            i++;
        }
    }
    catch (Throwable) {}
}

/// Manual cache clear -- exposed for `dun clean` later if wired.
void clear() @trusted
{
    import std.file : rmdirRecurse;
    try { if (exists(cacheRoot())) rmdirRecurse(cacheRoot()); }
    catch (Throwable) {}
}

unittest
{
    // Determinism: same inputs -> same key.
    auto k1 = cacheKey("const x = 1;", "/tmp/a.ts", "5.4.5");
    auto k2 = cacheKey("const x = 1;", "/tmp/a.ts", "5.4.5");
    assert(k1 == k2);
    assert(k1.length == 64);  // SHA-256 hex
    // Source change -> different key.
    auto k3 = cacheKey("const y = 2;", "/tmp/a.ts", "5.4.5");
    assert(k1 != k3);
    // Filename change -> different key.
    auto k4 = cacheKey("const x = 1;", "/tmp/b.ts", "5.4.5");
    assert(k1 != k4);
    // tsc version change -> different key.
    auto k5 = cacheKey("const x = 1;", "/tmp/a.ts", "5.5.0");
    assert(k1 != k5);
}
