module dun.security.test;

import dun.security.permissions;

// ---------------------------------------------------------------------------
// Default deny
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read));
    assert(!perms.check(Permission.write));
    assert(!perms.check(Permission.net));
    assert(!perms.check(Permission.env));
    assert(!perms.check(Permission.run));
    assert(!perms.check(Permission.ffi));
    assert(!perms.check(Permission.hrtime));
}

unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read, "/etc/passwd"));
    assert(!perms.check(Permission.net, "example.com"));
}

// ---------------------------------------------------------------------------
// Global grant
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.read, "/any/path"));
    assert(!perms.check(Permission.write));
}

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.net);
    assert(perms.check(Permission.net));
    assert(perms.check(Permission.net, "example.com"));
    assert(!perms.check(Permission.read));
}

// ---------------------------------------------------------------------------
// --allow-all
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.all);
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.write));
    assert(perms.check(Permission.net));
    assert(perms.check(Permission.env));
    assert(perms.check(Permission.run));
    assert(perms.check(Permission.ffi));
    assert(perms.check(Permission.hrtime));
}

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.all);
    assert(perms.check(Permission.read, "/etc/shadow"));
    assert(perms.check(Permission.net, "evil.com:443"));
}

// ---------------------------------------------------------------------------
// Scoped grants
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, ["./data"]);
    assert(perms.check(Permission.read, "./data"));
    assert(perms.check(Permission.read, "./data/file.txt"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}

unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.net, ["example.com"]);
    assert(perms.check(Permission.net, "example.com"));
    assert(!perms.check(Permission.net, "evil.com"));
}

unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, ["./src", "./tests"]);
    assert(perms.check(Permission.read, "./src"));
    assert(perms.check(Permission.read, "./tests"));
    assert(!perms.check(Permission.read, "./secrets"));
}

// ---------------------------------------------------------------------------
// Deny overrides allow
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    perms.denyScoped(Permission.read, ["/etc"]);
    assert(perms.check(Permission.read, "/home/user"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.all);
    perms.denyScoped(Permission.write, ["/etc"]);
    assert(perms.check(Permission.write, "/tmp/file"));
    assert(!perms.check(Permission.write, "/etc/shadow"));
}

unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, ["/data"]);
    perms.denyScoped(Permission.read, ["/data/secret"]);
    assert(perms.check(Permission.read, "/data/public"));
    assert(!perms.check(Permission.read, "/data/secret/key"));
}

// ---------------------------------------------------------------------------
// parseFlag
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-read");
    assert(perms.check(Permission.read));
    assert(!perms.check(Permission.write));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-all");
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.write));
    assert(perms.check(Permission.net));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("-A");
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.write));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-read=./data,/tmp");
    assert(perms.check(Permission.read, "./data"));
    assert(perms.check(Permission.read, "/tmp"));
    assert(!perms.check(Permission.read, "/etc"));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-net=example.com,api.test.io");
    assert(perms.check(Permission.net, "example.com"));
    assert(perms.check(Permission.net, "api.test.io"));
    assert(!perms.check(Permission.net, "evil.com"));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-write");
    perms.parseFlag("--deny-write=/etc");
    assert(perms.check(Permission.write, "/tmp/file"));
    assert(!perms.check(Permission.write, "/etc/passwd"));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-env=HOME,PATH");
    assert(perms.check(Permission.env, "HOME"));
    assert(perms.check(Permission.env, "PATH"));
    assert(!perms.check(Permission.env, "SECRET_KEY"));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-run=ls,cat");
    assert(perms.check(Permission.run, "ls"));
    assert(perms.check(Permission.run, "cat"));
    assert(!perms.check(Permission.run, "rm"));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-ffi");
    assert(perms.check(Permission.ffi));
}

unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-hrtime");
    assert(perms.check(Permission.hrtime));
}

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read, ""));
}

unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    assert(perms.check(Permission.read, ""));
}

unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, [""]);
    assert(perms.check(Permission.read, "/anything"));
}

unittest
{
    // Global deny then global grant — grant overwrites the state.
    // To truly deny, use scoped deny which is checked separately.
    PermissionRegistry perms;
    perms.parseFlag("--deny-read");
    assert(!perms.check(Permission.read));
}

unittest
{
    // Scoped deny persists even after global grant
    PermissionRegistry perms;
    perms.parseFlag("--deny-read=/etc");
    perms.grant(Permission.read);
    assert(perms.check(Permission.read, "/home"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}
