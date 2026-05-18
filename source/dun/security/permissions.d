/// Default-deny permission registry, populated from CLI flags.
module dun.security.permissions;

/// Permission categories.
enum Permission
{
    read, /// --allow-read[=path1,path2]
    write, /// --allow-write[=path1,path2]
    net, /// --allow-net[=host1:port,host2]
    env, /// --allow-env[=VAR1,VAR2]
    run, /// --allow-run[=cmd1,cmd2]
    ffi, /// --allow-ffi[=lib1,lib2]
    sys, /// --allow-sys[=cpus,networkInterfaces,uid,gid,...]  (Deno parity)
    hrtime, /// --allow-hrtime
    all, /// --allow-all / -A
}

static assert(__traits(allMembers, Permission).length == 9,
    "Permission enum member count changed -- update parseFlag mappings");

/// State of a permission.
enum PermissionState
{
    granted,
    denied,
    prompt, // Future: interactive prompt
}

/// Registry of granted permissions, populated from CLI flags.
struct PermissionRegistry
{
    private PermissionState[Permission] globalPerms;
    private string[][Permission] scopedAllowList;
    private string[][Permission] scopedDenyList;

    /// Grant a global permission (no scope restriction).
    void grant(Permission perm) @safe
    {
        globalPerms[perm] = PermissionState.granted;
    }

    /// Grant a scoped permission (e.g., read access to specific paths).
    void grantScoped(Permission perm, string[] scopes) @safe
    {
        if (perm !in scopedAllowList)
            scopedAllowList[perm] = [];
        scopedAllowList[perm] ~= scopes;
    }

    /// Deny a scoped permission (overrides allow).
    void denyScoped(Permission perm, string[] scopes) @safe
    {
        if (perm !in scopedDenyList)
            scopedDenyList[perm] = [];
        scopedDenyList[perm] ~= scopes;
    }

    /// Check if a permission is granted for the given resource.
    bool check(Permission perm, string resource = "") @safe
    {
        // --allow-all grants everything
        if (auto s = Permission.all in globalPerms)
        {
            if (*s == PermissionState.granted)
            {
                // But still check deny list
                if (!isDenied(perm, resource))
                    return true;
            }
        }

        // Check deny list first (deny overrides allow)
        if (isDenied(perm, resource))
            return false;

        // Check global grant
        if (auto s = perm in globalPerms)
        {
            if (*s == PermissionState.granted)
                return true;
        }

        // Check scoped allow list
        if (auto scopes = perm in scopedAllowList)
        {
            foreach (scope_; *scopes)
            {
                if (matchesScopeForPerm(perm, resource, scope_))
                    return true;
            }
        }

        return false; // Default deny
    }

    /// Parse a CLI flag like --allow-read=./data,/tmp
    void parseFlag(string flag) @safe
    {
        import std.algorithm : startsWith;
        import std.string : split;

        if (flag == "--allow-all" || flag == "-A")
        {
            grant(Permission.all);
            return;
        }

        struct FlagMapping
        {
            string prefix;
            string denyPrefix;
            Permission perm;
        }

        static immutable mappings = [
            FlagMapping("--allow-read", "--deny-read", Permission.read),
            FlagMapping("--allow-write", "--deny-write", Permission.write),
            FlagMapping("--allow-net", "--deny-net", Permission.net),
            FlagMapping("--allow-env", "--deny-env", Permission.env),
            FlagMapping("--allow-run", "--deny-run", Permission.run),
            FlagMapping("--allow-ffi", "--deny-ffi", Permission.ffi),
            FlagMapping("--allow-sys", "--deny-sys", Permission.sys),
            FlagMapping("--allow-hrtime", "", Permission.hrtime),
        ];

        foreach (m; mappings)
        {
            // Allow flags
            if (flag == m.prefix)
            {
                grant(m.perm);
                return;
            }
            if (flag.startsWith(m.prefix ~ "="))
            {
                auto scopeStr = flag[m.prefix.length + 1 .. $];
                auto scopes = scopeStr.split(",");
                grantScoped(m.perm, scopes);
                return;
            }

            // Deny flags
            if (m.denyPrefix.length > 0)
            {
                if (flag == m.denyPrefix)
                {
                    globalPerms[m.perm] = PermissionState.denied;
                    return;
                }
                if (flag.startsWith(m.denyPrefix ~ "="))
                {
                    auto scopeStr = flag[m.denyPrefix.length + 1 .. $];
                    auto scopes = scopeStr.split(",");
                    denyScoped(m.perm, scopes);
                    return;
                }
            }
        }
    }

    bool isGlobalGrant(Permission perm) @safe
    {
        if (auto s = Permission.all in globalPerms)
            if (*s == PermissionState.granted)
                return true;
        if (auto s = perm in globalPerms)
            if (*s == PermissionState.granted)
                return true;
        return false;
    }

    private bool isDenied(Permission perm, string resource) @safe
    {
        if (auto scopes = perm in scopedDenyList)
        {
            foreach (scope_; *scopes)
            {
                if (matchesScopeForPerm(perm, resource, scope_))
                    return true;
            }
        }
        return false;
    }

    // Per-permission scope matcher. `read`/`write`/`run`/`ffi` match
    // by subpath (existing behaviour). `net` matches host[:port] with
    // optional port restriction: scope `example.com` allows any port;
    // scope `example.com:443` requires the port to match. `env`/`sys`
    // match by exact name. `hrtime` has no resource.
    private bool matchesScopeForPerm(Permission perm, string resource, string pattern) @safe
    {
        if (resource.length == 0 || pattern.length == 0)
            return true; // No scope = matches all

        final switch (perm) with (Permission)
        {
            case read: case write: case run: case ffi:
                import dun.platform.paths : isSubpathOf;
                return isSubpathOf(resource, pattern);
            case net:
                return matchesNetScope(resource, pattern);
            case env: case sys:
                return resource == pattern;
            case hrtime: case all:
                return true;
        }
    }

    // host[:port] vs scope[:port]. Scope without port matches any
    // port on that host; scope with port requires exact match. Wildcard
    // host `*` matches anything. Mirrors Deno's `NetDescriptor`
    // semantics at the host:port grain.
    private static bool matchesNetScope(string resource, string pattern) @safe pure nothrow
    {
        if (pattern == "*") return true;
        if (resource == pattern) return true;
        // Split host:port for both. `lastIndexOf` (not `indexOf`) is
        // IPv6-safe: `[::1]:8080` splits on the colon before `8080`.
        string rHost = resource, pHost = pattern;
        string rPort, pPort;
        auto rColon = lastColonNotInBrackets(resource);
        if (rColon >= 0) { rHost = resource[0 .. rColon]; rPort = resource[rColon + 1 .. $]; }
        auto pColon = lastColonNotInBrackets(pattern);
        if (pColon >= 0) { pHost = pattern[0 .. pColon]; pPort = pattern[pColon + 1 .. $]; }
        if (pHost != rHost && pHost != "*") return false;
        if (pPort.length == 0) return true;          // pattern is host-only: any port
        return pPort == rPort;
    }

    private static long lastColonNotInBrackets(string s) @safe pure nothrow @nogc
    {
        int depth = 0;
        long lastColon = -1;
        foreach (i, c; s)
        {
            if (c == '[') depth++;
            else if (c == ']') depth--;
            else if (c == ':' && depth == 0) lastColon = cast(long) i;
        }
        return lastColon;
    }
}

/// `extern(C)`-safe permission check — nothrow, defaults to deny on
/// null state so a misconfigured DunState* can't silently permit I/O.
bool checkPerm(StateT)(StateT* state, Permission perm, string resource = "") @trusted nothrow
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}
