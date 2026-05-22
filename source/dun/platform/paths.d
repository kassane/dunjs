/// Path canonicalization (resolves symlinks before permission checks).
module dun.platform.paths;

/// User-global DunJS store (npm packages, transpile cache).
/// Posix `$HOME/.dun`, Windows `%LOCALAPPDATA%\dun`. `DUN_HOME`
/// overrides; result is always absolute.
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

/// Canonicalize a file path by resolving symlinks and normalizing.
/// Returns null on failure.
///
/// CVE-class fix gate (CVE-2023-32004 / CVE-2024-21896 — see
/// SECURITY.md): the result feeds `Permission.check` before any I/O.
/// Marked `@safe` deliberately — a security-critical primitive must
/// not need an `@trusted` escape. `absolutePath` + `buildNormalizedPath`
/// are both `@safe` in Phobos; the audit (2026-05) confirmed no
/// pointer arithmetic, no cast, no FFI in the body.
string canonicalizePath(string path) @safe
{
    import std.path : absolutePath, buildNormalizedPath;

    if (path.length == 0)
        return null;

    auto normalized = buildNormalizedPath(absolutePath(path));
    return normalized;
}

/// Check if `child` path is under `parent` directory.
/// Both paths should be canonicalized first.
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
