module dun.security.test;

import dun.security.permissions;

// ---------------------------------------------------------------------------
// Default deny
// ---------------------------------------------------------------------------

@("default deny: all permissions denied by default")
unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read));
    assert(!perms.check(Permission.write));
    assert(!perms.check(Permission.net));
    assert(!perms.check(Permission.env));
    assert(!perms.check(Permission.run));
    assert(!perms.check(Permission.ffi));
    assert(!perms.check(Permission.sys));
    assert(!perms.check(Permission.hrtime));
}

@("net scope: host[:port] granularity matches Deno semantics")
unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.net, ["example.com"]);
    assert( perms.check(Permission.net, "example.com"));
    assert( perms.check(Permission.net, "example.com:80"));
    assert( perms.check(Permission.net, "example.com:443"));
    assert(!perms.check(Permission.net, "other.com"));

    PermissionRegistry perms2;
    perms2.grantScoped(Permission.net, ["example.com:443"]);
    assert( perms2.check(Permission.net, "example.com:443"));
    assert(!perms2.check(Permission.net, "example.com:80"));
    assert(!perms2.check(Permission.net, "example.com"));

    PermissionRegistry perms3;
    perms3.grantScoped(Permission.net, ["*"]);
    assert( perms3.check(Permission.net, "anything.com"));
    assert( perms3.check(Permission.net, "anything.com:1234"));
}

@("sys scope: matches by exact name (cpus, networkInterfaces, ...)")
unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.sys, ["cpus", "networkInterfaces"]);
    assert( perms.check(Permission.sys, "cpus"));
    assert( perms.check(Permission.sys, "networkInterfaces"));
    assert(!perms.check(Permission.sys, "userInfo"));
}

@("default deny: scoped paths denied by default")
unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read, "/etc/passwd"));
    assert(!perms.check(Permission.net, "example.com"));
}

// ---------------------------------------------------------------------------
// Global grant
// ---------------------------------------------------------------------------

@("global grant: read allows all paths")
unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.read, "/any/path"));
    assert(!perms.check(Permission.write));
}

@("global grant: net allows all hosts")
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

@("allow-all: grants every permission")
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

@("allow-all: grants any scoped path")
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

@("scoped grant: read limited to directory")
unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, ["./data"]);
    assert(perms.check(Permission.read, "./data"));
    assert(perms.check(Permission.read, "./data/file.txt"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}

@("scoped grant: net limited to host")
unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.net, ["example.com"]);
    assert(perms.check(Permission.net, "example.com"));
    assert(!perms.check(Permission.net, "evil.com"));
}

@("scoped grant: multiple paths")
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

@("deny overrides: global grant + scoped deny")
unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    perms.denyScoped(Permission.read, ["/etc"]);
    assert(perms.check(Permission.read, "/home/user"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}

@("deny overrides: allow-all + scoped deny")
unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.all);
    perms.denyScoped(Permission.write, ["/etc"]);
    assert(perms.check(Permission.write, "/tmp/file"));
    assert(!perms.check(Permission.write, "/etc/shadow"));
}

@("deny overrides: scoped grant + scoped deny subtree")
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

@("parseFlag: --allow-read")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-read");
    assert(perms.check(Permission.read));
    assert(!perms.check(Permission.write));
}

@("parseFlag: --allow-all grants everything")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-all");
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.write));
    assert(perms.check(Permission.net));
}

@("parseFlag: -A shorthand for --allow-all")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("-A");
    assert(perms.check(Permission.read));
    assert(perms.check(Permission.write));
}

@("parseFlag: --allow-read=paths scoped")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-read=./data,/tmp");
    assert(perms.check(Permission.read, "./data"));
    assert(perms.check(Permission.read, "/tmp"));
    assert(!perms.check(Permission.read, "/etc"));
}

@("parseFlag: --allow-net=hosts scoped")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-net=example.com,api.test.io");
    assert(perms.check(Permission.net, "example.com"));
    assert(perms.check(Permission.net, "api.test.io"));
    assert(!perms.check(Permission.net, "evil.com"));
}

@("parseFlag: --deny-write overrides --allow-write")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-write");
    perms.parseFlag("--deny-write=/etc");
    assert(perms.check(Permission.write, "/tmp/file"));
    assert(!perms.check(Permission.write, "/etc/passwd"));
}

@("parseFlag: --allow-env=scoped")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-env=HOME,PATH");
    assert(perms.check(Permission.env, "HOME"));
    assert(perms.check(Permission.env, "PATH"));
    assert(!perms.check(Permission.env, "SECRET_KEY"));
}

@("parseFlag: --allow-run=scoped")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-run=ls,cat");
    assert(perms.check(Permission.run, "ls"));
    assert(perms.check(Permission.run, "cat"));
    assert(!perms.check(Permission.run, "rm"));
}

@("parseFlag: --allow-ffi")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-ffi");
    assert(perms.check(Permission.ffi));
}

@("parseFlag: --allow-hrtime")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--allow-hrtime");
    assert(perms.check(Permission.hrtime));
}

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

@("edge: empty path denied by default")
unittest
{
    PermissionRegistry perms;
    assert(!perms.check(Permission.read, ""));
}

@("edge: empty path allowed with global grant")
unittest
{
    PermissionRegistry perms;
    perms.grant(Permission.read);
    assert(perms.check(Permission.read, ""));
}

@("edge: empty scope matches everything")
unittest
{
    PermissionRegistry perms;
    perms.grantScoped(Permission.read, [""]);
    assert(perms.check(Permission.read, "/anything"));
}

@("edge: --deny-read without grant stays denied")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--deny-read");
    assert(!perms.check(Permission.read));
}

@("edge: scoped deny persists after global grant")
unittest
{
    PermissionRegistry perms;
    perms.parseFlag("--deny-read=/etc");
    perms.grant(Permission.read);
    assert(perms.check(Permission.read, "/home"));
    assert(!perms.check(Permission.read, "/etc/passwd"));
}
