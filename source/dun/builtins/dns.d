module dun.builtins.dns;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void registerDnsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerDnsModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "lookup", engine.newFunction(&jsLookup, "lookup", 2));
    engine.setProperty(obj, "lookupSync", engine.newFunction(&jsLookupSync, "lookupSync", 1));
    engine.setProperty(obj, "resolve4", engine.newFunction(&jsResolve4, "resolve4", 2));
    engine.setProperty(obj, "resolve6", engine.newFunction(&jsResolve6, "resolve6", 2));
    engine.setProperty(obj, "resolve", engine.newFunction(&jsResolve, "resolve", 3));
    engine.setProperty(obj, "getServers", engine.newFunction(&jsGetServers, "getServers", 0));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_dns__", obj);
    engine.freeValue(global);

    // Evaluate JS extension for dns.promises
    auto extResult = engine.eval(dnsExtensionSource(), "<dns-ext>");
    if (!extResult.isError)
        engine.freeValue(extResult.value);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:dns", &dnsModuleInit);
        if (m is null) return;
        foreach (name; ["lookup", "lookupSync", "resolve4", "resolve6", "resolve", "getServers", "promises"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int dnsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in dnsModuleInit");
        assert(m !is null, "Null JSModuleDef in dnsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto dnsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_dns__");
        foreach (name; ["lookup", "lookupSync", "resolve4", "resolve6", "resolve", "getServers", "promises"])
        {
            auto fn = JS_GetPropertyStr(ctx, dnsObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, dnsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

bool checkNetPerm(DunState* state, string hostname) nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(Permission.net, hostname); }
    catch (Exception) { return false; }
}

version (Posix)
{
    import core.sys.posix.netdb : addrinfo, getaddrinfo, freeaddrinfo;
    import core.sys.posix.sys.socket : AF_INET, AF_INET6, AF_UNSPEC, sockaddr;
    import core.sys.posix.netinet.in_ : sockaddr_in, sockaddr_in6, INET_ADDRSTRLEN, INET6_ADDRSTRLEN;
    import core.sys.posix.arpa.inet : inet_ntop;
    import core.stdc.string : memset;

    struct DnsResult
    {
        string address;
        int family; // 4 or 6
    }

    DnsResult[] resolveHostname(string hostname, int afFamily) @trusted
    {
        import std.string : toStringz;

        addrinfo hints;
        memset(&hints, 0, hints.sizeof);
        hints.ai_family = afFamily;
        hints.ai_socktype = 1; // SOCK_STREAM

        addrinfo* res;
        int ret = getaddrinfo(toStringz(hostname), null, &hints, &res);
        if (ret != 0 || res is null)
            return [];

        scope(exit) freeaddrinfo(res);

        DnsResult[] results;
        for (auto p = res; p !is null; p = p.ai_next)
        {
            char[INET6_ADDRSTRLEN] buf;
            const(char)* addr = null;

            if (p.ai_family == AF_INET)
            {
                auto sa4 = cast(sockaddr_in*) p.ai_addr;
                addr = inet_ntop(AF_INET, &sa4.sin_addr, buf.ptr, buf.length);
            }
            else if (p.ai_family == AF_INET6)
            {
                auto sa6 = cast(sockaddr_in6*) p.ai_addr;
                addr = inet_ntop(AF_INET6, &sa6.sin6_addr, buf.ptr, buf.length);
            }

            if (addr !is null)
            {
                import core.stdc.string : strlen;
                auto s = cast(string) addr[0 .. strlen(addr)].idup;
                int fam = (p.ai_family == AF_INET6) ? 6 : 4;
                results ~= DnsResult(s, fam);
            }
        }
        return results;
    }
}

JSHandle jsLookupSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsLookupSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsLookupSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("lookup requires a hostname argument");

    auto hostname = engine.extractString(args[0]);
    if (!checkNetPerm(state, hostname))
        return engine.throwTypeError("Requires --allow-net to resolve DNS");

    version (Posix)
    {
        try
        {
            auto results = resolveHostname(hostname, AF_UNSPEC);
            if (results.length == 0)
                return engine.throwTypeError("getaddrinfo ENOTFOUND " ~ hostname);

            auto obj = engine.newObject();
            engine.setProperty(obj, "address", engine.newString(results[0].address));
            engine.setProperty(obj, "family", engine.newInt(results[0].family));
            return obj;
        }
        catch (Exception) { return engine.throwTypeError("DNS lookup failed"); }
    }
    else
    {
        return engine.throwTypeError("DNS lookup not supported on this platform");
    }
}

JSHandle jsLookup(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsLookup");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsLookup");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1]))
        return engine.throwTypeError("lookup requires (hostname, callback)");

    auto hostname = engine.extractString(args[0]);
    if (!checkNetPerm(state, hostname))
        return engine.throwTypeError("Requires --allow-net to resolve DNS");

    version (Posix)
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;

        try
        {
            auto results = resolveHostname(hostname, AF_UNSPEC);
            if (results.length == 0)
            {
                auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                pushAgnosticPending(engine, args[1],
                    [errObj, engine.newNull(), engine.newInt(0)]);
            }
            else
            {
                pushAgnosticPending(engine, args[1],
                    [engine.newNull(), engine.newString(results[0].address),
                     engine.newInt(results[0].family)]);
            }
        }
        catch (Exception)
        {
            auto errObj = engine.newString("DNS lookup failed");
            pushAgnosticPending(engine, args[1],
                [errObj, engine.newNull(), engine.newInt(0)]);
        }
    }
    else
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;
        auto errObj = engine.newString("DNS not supported on this platform");
        pushAgnosticPending(engine, args[1],
            [errObj, engine.newNull(), engine.newInt(0)]);
    }
    return engine.newUndefined();
}

JSHandle jsResolve4(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResolve4");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResolve4");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1]))
        return engine.throwTypeError("resolve4 requires (hostname, callback)");

    auto hostname = engine.extractString(args[0]);
    if (!checkNetPerm(state, hostname))
        return engine.throwTypeError("Requires --allow-net to resolve DNS");

    version (Posix)
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;

        try
        {
            auto results = resolveHostname(hostname, AF_INET);
            if (results.length == 0)
            {
                auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
            }
            else
            {
                auto arr = engine.newArray();
                foreach (i, r; results)
                    engine.setPropertyIndex(arr, cast(uint) i, engine.newString(r.address));
                pushAgnosticPending(engine, args[1], [engine.newNull(), arr]);
            }
        }
        catch (Exception)
        {
            auto errObj = engine.newString("DNS resolve4 failed");
            pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
        }
    }
    else
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;
        auto errObj = engine.newString("DNS not supported on this platform");
        pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
    }
    return engine.newUndefined();
}

JSHandle jsResolve6(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResolve6");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResolve6");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1]))
        return engine.throwTypeError("resolve6 requires (hostname, callback)");

    auto hostname = engine.extractString(args[0]);
    if (!checkNetPerm(state, hostname))
        return engine.throwTypeError("Requires --allow-net to resolve DNS");

    version (Posix)
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;

        try
        {
            auto results = resolveHostname(hostname, AF_INET6);
            if (results.length == 0)
            {
                auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
            }
            else
            {
                auto arr = engine.newArray();
                foreach (i, r; results)
                    engine.setPropertyIndex(arr, cast(uint) i, engine.newString(r.address));
                pushAgnosticPending(engine, args[1], [engine.newNull(), arr]);
            }
        }
        catch (Exception)
        {
            auto errObj = engine.newString("DNS resolve6 failed");
            pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
        }
    }
    else
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;
        auto errObj = engine.newString("DNS not supported on this platform");
        pushAgnosticPending(engine, args[1], [errObj, engine.newNull()]);
    }
    return engine.newUndefined();
}

JSHandle jsResolve(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResolve");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResolve");
    auto engine = state.engine;

    // resolve(hostname, [rrtype], callback)
    // Determine callback and rrtype from arguments
    string rrtype = "A";
    JSHandle callback;
    if (args.length >= 3 && engine.isFunction(args[2]))
    {
        rrtype = engine.extractString(args[1]);
        callback = args[2];
    }
    else if (args.length >= 2 && engine.isFunction(args[1]))
    {
        callback = args[1];
    }
    else
    {
        return engine.throwTypeError("resolve requires (hostname, [rrtype], callback)");
    }

    if (args.length < 1)
        return engine.throwTypeError("resolve requires a hostname argument");

    auto hostname = engine.extractString(args[0]);
    if (!checkNetPerm(state, hostname))
        return engine.throwTypeError("Requires --allow-net to resolve DNS");

    version (Posix)
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;

        try
        {
            if (rrtype == "A")
            {
                auto results = resolveHostname(hostname, AF_INET);
                if (results.length == 0)
                {
                    auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                    pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
                }
                else
                {
                    auto arr = engine.newArray();
                    foreach (i, r; results)
                        engine.setPropertyIndex(arr, cast(uint) i, engine.newString(r.address));
                    pushAgnosticPending(engine, callback, [engine.newNull(), arr]);
                }
            }
            else if (rrtype == "AAAA")
            {
                auto results = resolveHostname(hostname, AF_INET6);
                if (results.length == 0)
                {
                    auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                    pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
                }
                else
                {
                    auto arr = engine.newArray();
                    foreach (i, r; results)
                        engine.setPropertyIndex(arr, cast(uint) i, engine.newString(r.address));
                    pushAgnosticPending(engine, callback, [engine.newNull(), arr]);
                }
            }
            else if (rrtype == "ANY")
            {
                auto results = resolveHostname(hostname, AF_UNSPEC);
                if (results.length == 0)
                {
                    auto errObj = engine.newString("getaddrinfo ENOTFOUND " ~ hostname);
                    pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
                }
                else
                {
                    auto arr = engine.newArray();
                    foreach (i, r; results)
                    {
                        auto entry = engine.newObject();
                        engine.setProperty(entry, "address", engine.newString(r.address));
                        engine.setProperty(entry, "family", engine.newInt(r.family));
                        engine.setProperty(entry, "type", engine.newString(r.family == 4 ? "A" : "AAAA"));
                        engine.setPropertyIndex(arr, cast(uint) i, entry);
                    }
                    pushAgnosticPending(engine, callback, [engine.newNull(), arr]);
                }
            }
            else
            {
                auto errObj = engine.newString("queryTxt ENODATA " ~ hostname);
                pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
            }
        }
        catch (Exception)
        {
            auto errObj = engine.newString("DNS resolve failed");
            pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
        }
    }
    else
    {
        import dun.loop.agnostic_pending : pushAgnosticPending;
        auto errObj = engine.newString("DNS not supported on this platform");
        pushAgnosticPending(engine, callback, [errObj, engine.newNull()]);
    }
    return engine.newUndefined();
}

JSHandle jsGetServers(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGetServers");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsGetServers");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsGetServers");

    if (!checkNetPerm(state, ""))
        return engine.throwTypeError("Requires --allow-net to get DNS servers");

    version (Posix)
    {
        try
        {
            auto servers = parseResolvConf();
            auto arr = engine.newArray();
            foreach (i, s; servers)
                engine.setPropertyIndex(arr, cast(uint) i, engine.newString(s));
            return arr;
        }
        catch (Exception)
        {
            // Return empty array on error
            return engine.newArray();
        }
    }
    else
    {
        return engine.newArray();
    }
}

version (Posix)
{
    string[] parseResolvConf() @trusted
    {
        import std.stdio : File;
        import std.string : strip, startsWith;
        import std.array : split;

        string[] servers;
        try
        {
            auto f = File("/etc/resolv.conf", "r");
            scope(exit) f.close();
            foreach (line; f.byLine())
            {
                auto l = (cast(string) line).strip();
                if (l.startsWith("nameserver"))
                {
                    auto parts = l.split();
                    if (parts.length >= 2)
                        servers ~= parts[1].idup;
                }
            }
        }
        catch (Exception)
        {
            // File not readable; return empty
        }
        return servers;
    }
}

string dnsExtensionSource() pure @safe nothrow
{
    return `(function() {
    var dns = globalThis.__dun_cjs_dns__;
    if (!dns) return;
    dns.promises = {
        lookup: function(hostname, opts) {
            return new Promise(function(resolve, reject) {
                dns.lookup(hostname, function(err, address, family) {
                    if (err) reject(new Error(typeof err === 'string' ? err : String(err)));
                    else resolve({ address: address, family: family });
                });
            });
        },
        resolve4: function(hostname) {
            return new Promise(function(resolve, reject) {
                dns.resolve4(hostname, function(err, addresses) {
                    if (err) reject(new Error(typeof err === 'string' ? err : String(err)));
                    else resolve(addresses);
                });
            });
        },
        resolve6: function(hostname) {
            return new Promise(function(resolve, reject) {
                dns.resolve6(hostname, function(err, addresses) {
                    if (err) reject(new Error(typeof err === 'string' ? err : String(err)));
                    else resolve(addresses);
                });
            });
        },
        resolve: function(hostname, rrtype) {
            return new Promise(function(resolve, reject) {
                var cb = function(err, result) {
                    if (err) reject(new Error(typeof err === 'string' ? err : String(err)));
                    else resolve(result);
                };
                if (rrtype !== undefined) dns.resolve(hostname, rrtype, cb);
                else dns.resolve(hostname, cb);
            });
        }
    };
})()`;
}
