module dun.platform.url_parser;

/++
 + `@trusted policy`: pure URL-string parser. `@safe` throughout —
 + no FFI, no `@trusted`. Lives in `platform/` so fuzz harnesses
 + + tools can depend on it without pulling the entire `fetch.d`
 + transitive surface (TLS, async work pool, permissions, ...).
 +
 + Mirrors the original `dun.builtins.fetch.parseUrl` signature
 + and behaviour; `fetch.d` now re-exports from here.
 +/

import std.conv : to;

struct ParsedUrl
{
    string scheme;
    string host;
    ushort port;
    string path;
}

/++
 + Parse `scheme://host[:port][/path]` into a `ParsedUrl`. Throws
 + `Exception("invalid URL: ...")` if the input has no `"://"`.
 + `port == 0` means "no explicit port" (caller picks the
 + scheme-default).
 +/
ParsedUrl parseUrl(string url) @safe
{
    import std.string : indexOf;

    ParsedUrl p;
    p.path = "/";

    auto schemeEnd = url.indexOf("://");
    if (schemeEnd < 0) throw new Exception("invalid URL: " ~ url);
    p.scheme = url[0 .. schemeEnd];
    auto rest = url[schemeEnd + 3 .. $];

    auto pathStart = rest.indexOf('/');
    string hostPort;
    if (pathStart < 0)
        hostPort = rest;
    else
    {
        hostPort = rest[0 .. pathStart];
        p.path = rest[pathStart .. $];
    }

    auto colonIdx = hostPort.indexOf(':');
    if (colonIdx < 0)
    {
        p.host = hostPort;
        p.port = 0;
    }
    else
    {
        p.host = hostPort[0 .. colonIdx];
        try { p.port = hostPort[colonIdx + 1 .. $].to!ushort; }
        catch (Exception) { p.port = 0; }
    }

    return p;
}

unittest
{
    auto p = parseUrl("https://example.com:8080/path");
    assert(p.scheme == "https");
    assert(p.host == "example.com");
    assert(p.port == 8080);
    assert(p.path == "/path");

    auto p2 = parseUrl("http://example.com");
    assert(p2.scheme == "http");
    assert(p2.host == "example.com");
    assert(p2.port == 0);
    assert(p2.path == "/");

    auto p3 = parseUrl("http://host:abc/path");
    assert(p3.port == 0);  // bad port falls back to 0
}
