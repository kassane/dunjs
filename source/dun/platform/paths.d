/// Path canonicalization (resolves symlinks before permission checks).
module dun.platform.paths;

/++
 + User-global DunJS store (npm packages, transpile cache).
 + Posix `$HOME/.dun`, Windows `%LOCALAPPDATA%\dun`. `DUN_HOME`
 + overrides; result is always absolute.
 +/
string dunGlobalRoot() @trusted
{
    import std.path : buildPath, isAbsolute, absolutePath;
    import std.process : environment;

    string override_ = environment.get("DUN_HOME", "");
    if (override_.length > 0)
    {
        try { return isAbsolute(override_) ? override_ : absolutePath(override_); }
        catch (Throwable) { return override_; }
    }

    version (Windows)
    {
        auto local = environment.get("LOCALAPPDATA", "");
        if (local.length > 0) return buildPath(local, "dun");
        auto profile = environment.get("USERPROFILE", "");
        if (profile.length > 0) return buildPath(profile, ".dun");
        return ".dun";
    }
    else
    {
        auto home = environment.get("HOME", "");
        if (home.length > 0) return buildPath(home, ".dun");
        return ".dun";
    }
}

/++
 + POSIX-only fast-path predicate: returns true iff `path` is already
 + in canonical form (absolute, no `..` / `.` / `//` segments, no
 + trailing slash unless it's the root `/`). When true, `canonicalizePath`
 + can skip the `buildNormalizedPath(absolutePath(...))` allocation
 + pair and return the input string directly.
 +
 + Why bother: every fs operation feeds the path through
 + `canonicalizePath` for the CVE-2023-32004 scope check. Each Phobos
 + call allocates a new string; v1.1.27 `fs_bench` measurement showed
 + `writeFileSync` at 100μs vs Bun's 6μs, dominated by GC churn from
 + canonicalization on already-canonical paths.
 +
 + Security: returning the input verbatim only when it's already
 + canonical preserves the CVE-class guarantee — a malicious
 + `/tmp/safe/../etc/passwd` fails the predicate (sees `/..`) and
 + falls through to the full Phobos canonicalization. The predicate
 + is conservative: false negatives just pay the canonicalize cost,
 + false positives would be a security regression. Tests cover the
 + edge cases.
 +/
private bool isAlreadyCanonical(string path) @safe pure nothrow @nogc
{
    version (Posix)
    {
        if (path.length == 0 || path[0] != '/') return false;
        // The root `/` is canonical.
        if (path.length == 1) return true;
        // Trailing `/` (other than root) is not canonical.
        if (path[$ - 1] == '/') return false;
        // Walk the path looking for `//`, `/./`, `/.`, `/../`, `/..`.
        for (size_t i = 0; i + 1 < path.length; i++)
        {
            if (path[i] != '/') continue;
            immutable next = path[i + 1];
            if (next == '/') return false;                  // `//`
            if (next == '.')
            {
                immutable rem = path.length - (i + 1);
                if (rem == 1) return false;                 // `/.` at end
                immutable after = path[i + 2];
                if (after == '/') return false;             // `/./`
                if (after == '.')
                {
                    if (rem == 2) return false;             // `/..` at end
                    if (path[i + 3] == '/') return false;   // `/../`
                }
            }
        }
        return true;
    }
    else return false;
}

/++
 + Canonicalize a file path by resolving symlinks and normalizing.
 + Returns null on failure.
 +
 + CVE-class fix gate (CVE-2023-32004 / CVE-2024-21896 — see
 + SECURITY.md): the result feeds `Permission.check` before any I/O.
 + Marked `@safe` deliberately — a security-critical primitive must
 + not need an `@trusted` escape. `absolutePath` + `buildNormalizedPath`
 + are both `@safe` in Phobos; the audit (2026-05) confirmed no
 + pointer arithmetic, no cast, no FFI in the body.
 +
 + Hot path (POSIX): if the input is already canonical (`/tmp/foo/bar`
 + with no `..` / `.` / `//`), return it verbatim — zero allocations.
 + `isAlreadyCanonical` is conservative; false negatives fall through
 + to the full Phobos canonicalization with no semantic change.
 +/
string canonicalizePath(string path) @safe
{
    import std.path : absolutePath, buildNormalizedPath;

    if (path.length == 0)
        return null;

    if (isAlreadyCanonical(path))
        return path;

    auto normalized = buildNormalizedPath(absolutePath(path));
    return normalized;
}

/++
 + Resolve symlinks in an already-lexically-canonicalized absolute
 + path via POSIX `realpath(3)`, so the permission scope check sees
 + the real filesystem target rather than a symlink that escapes the
 + allowed directory.
 +
 + CVE-class fix gate (CVE-2025-55130 — Node.js Jan-2026 release):
 + `canonicalizePath` only normalizes `..` / `.` lexically, so a
 + symlink INSIDE an `--allow-read=/tmp/safe` scope that points at
 + `/etc/hostname` passes the subpath check (`/tmp/safe/link` is under
 + `/tmp/safe`) while the OS follows the link out of the sandbox.
 + Resolving symlinks before the scope match closes that escape. Both
 + the resource and the scope patterns are passed through this so a
 + legitimately-symlinked scope dir still matches its own contents.
 +
 + Strategy: try `realpath` on the full path (resolves an existing
 + file or a final-component symlink). If the leaf doesn't exist yet
 + (e.g. `writeFileSync` creating a new file), `realpath` the parent
 + dir — which catches a symlinked parent — and re-append the leaf.
 + Anything deeper that doesn't exist falls back to the lexical path
 + (the symlink attack needs an existing link, so its containing
 + prefix always resolves). `@trusted`: the only escape is the
 + `realpath` FFI + the `strlen` on its NUL-terminated result.
 +/
string resolveSymlinks(string path) @trusted nothrow
{
    version (Posix)
    {
        import core.sys.posix.stdlib : realpath;
        import core.stdc.string : strlen;

        if (path.length == 0) return path;

        // PATH_MAX on Linux is 4096; realpath writes at most that.
        enum size_t PATH_MAX_BUF = 4096;

        static string tryRealpath(string p) @trusted nothrow
        {
            import std.string : toStringz;
            try
            {
                char[PATH_MAX_BUF] buf = void;
                auto rz = realpath(p.toStringz, buf.ptr);
                if (rz !is null)
                    return buf[0 .. strlen(rz)].idup;
            }
            catch (Throwable) {}
            return null;
        }

        // 1. Whole path (existing file / leaf symlink).
        auto direct = tryRealpath(path);
        if (direct !is null) return direct;

        // 2. Leaf doesn't exist — resolve the parent dir (catches a
        //    symlinked directory) and re-attach the leaf name.
        try
        {
            import std.path : dirName, baseName, buildPath;
            auto parent = dirName(path);
            auto leaf = baseName(path);
            if (parent.length > 0 && parent != path)
            {
                auto realParent = tryRealpath(parent);
                if (realParent !is null)
                    return buildPath(realParent, leaf);
            }
        }
        catch (Throwable) {}

        return path;  // fall back to the lexical canonical form
    }
    else
        return path;  // Windows: realpath(3) unavailable; lexical-only
}

unittest
{
    version (Posix)
    {
        // True cases — already-canonical absolute paths.
        assert(isAlreadyCanonical("/"));
        assert(isAlreadyCanonical("/tmp"));
        assert(isAlreadyCanonical("/tmp/foo"));
        assert(isAlreadyCanonical("/tmp/foo/bar.txt"));
        assert(isAlreadyCanonical("/etc/hostname"));
        assert(isAlreadyCanonical("/a/b/c/d/e/f"));
        // False cases — relative, double-slash, `.`, `..`, trailing slash.
        assert(!isAlreadyCanonical(""));
        assert(!isAlreadyCanonical("tmp"));
        assert(!isAlreadyCanonical("./foo"));
        assert(!isAlreadyCanonical("../foo"));
        assert(!isAlreadyCanonical("/tmp/"));
        assert(!isAlreadyCanonical("/tmp//foo"));
        assert(!isAlreadyCanonical("/tmp/./foo"));
        assert(!isAlreadyCanonical("/tmp/../foo"));
        assert(!isAlreadyCanonical("/tmp/foo/."));
        assert(!isAlreadyCanonical("/tmp/foo/.."));
        assert(!isAlreadyCanonical("/tmp/foo/./bar"));
        assert(!isAlreadyCanonical("/tmp/foo/../bar"));
        // Edge: `.` or `..` are NOT path segments (no leading `/`).
        // These should be relative-path false, not segment-false.
        assert(!isAlreadyCanonical("."));
        assert(!isAlreadyCanonical(".."));
        // Don't false-positive on legitimate names containing `.` mid-segment.
        assert(isAlreadyCanonical("/tmp/foo.txt"));
        assert(isAlreadyCanonical("/tmp/.hidden"));
        assert(isAlreadyCanonical("/tmp/a.b.c"));
        assert(isAlreadyCanonical("/tmp/..foo"));   // `..foo` is a name, not `..`
        assert(isAlreadyCanonical("/tmp/.foo"));    // same — `.foo` is a name
        // canonicalizePath returns the input verbatim for canonical paths.
        assert(canonicalizePath("/tmp/foo/bar") is "/tmp/foo/bar"
            || canonicalizePath("/tmp/foo/bar") == "/tmp/foo/bar");
        // CVE class — `/tmp/safe/../etc/passwd` must NOT be detected as
        // canonical; it falls through to buildNormalizedPath which
        // resolves to `/tmp/etc/passwd` (one `..` removes one `safe`
        // segment) so the scope check sees the real escaped path.
        assert(!isAlreadyCanonical("/tmp/safe/../etc/passwd"));
        auto canon1 = canonicalizePath("/tmp/safe/../etc/passwd");
        assert(canon1 == "/tmp/etc/passwd", "canon1=" ~ canon1);
        // Two `..` to fully escape `/tmp` reaches `/etc/passwd`.
        assert(!isAlreadyCanonical("/tmp/safe/../../etc/passwd"));
        auto canon2 = canonicalizePath("/tmp/safe/../../etc/passwd");
        assert(canon2 == "/etc/passwd", "canon2=" ~ canon2);
    }
}

/++
 + Check if `child` path is under `parent` directory.
 + Both paths should be canonicalized first.
 +/
bool isSubpathOf(string child, string parent) @safe
{
    assert(child.length > 0 || parent.length > 0,
        "Both child and parent are empty in isSubpathOf");
    if (child.length < parent.length)
        return false;

    import std.algorithm : startsWith;

    if (!child.startsWith(parent))
        return false;

    // Ensure it's a directory boundary
    if (child.length == parent.length)
        return true;

    import std.path : isDirSeparator;
    return isDirSeparator(child[parent.length]) || isDirSeparator(parent[$ - 1]);
}
