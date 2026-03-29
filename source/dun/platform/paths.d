/// Platform-specific path handling utilities.
///
/// Provides path canonicalization (for security: resolving symlinks
/// before permission checks to prevent traversal attacks).
module dun.platform.paths;

/// Canonicalize a file path by resolving symlinks and normalizing.
/// Returns null on failure.
string canonicalizePath(string path) @trusted
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
    if (child.length < parent.length)
        return false;

    import std.algorithm : startsWith;

    if (!child.startsWith(parent))
        return false;

    // Ensure it's a directory boundary
    if (child.length == parent.length)
        return true;

    return child[parent.length] == '/' || parent[$ - 1] == '/';
}
