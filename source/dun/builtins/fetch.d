module dun.builtins.fetch;

import core.attribute : mustuse;
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.platform.arena : Appender;
import std.conv : to;

private enum : size_t {
    SERIALIZE_RESERVE    = 256,
    HEADERS_RESERVE      = 128,
    REQUEST_RESERVE      = 256,
    HTTP_READ_BUF        = 8192,
    JSON_RESERVE_EXTRA   = 512,
}

void registerFetchGlobal(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerFetchGlobal");
    auto global = engine.getGlobal();
    engine.setProperty(global, "fetch",
        engine.newFunction(&jsFetch, "fetch", 1));
    engine.freeValue(global);
}

private JSHandle jsFetch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmit;

    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in jsFetch");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("fetch: first argument must be a URL string");

    string url = engine.extractString(args[0]);

    import dun.security.permissions : Permission;
    auto parsed = parseUrl(url);
    if (!state.permissions.check(Permission.net, parsed.host))
        return engine.throwTypeError(
            "Requires net permission for " ~ parsed.host ~ " (use --allow-net)");

    string method = "GET";
    string reqBody;
    string[string] reqHeaders;
    bool hasBody = false;
    // Fetch spec redirect modes: "follow" (default — chase 3xx up to
    // MAX_FOLLOWS), "manual" (return the 3xx response as-is), "error"
    // (throw a TypeError on 3xx). Real Deno + Node + Bun all implement
    // the trio; without it, `fetch(redirect: 'manual')` silently
    // followed redirects and broke auth-flow scripts.
    string redirectMode = "follow";

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto opts = args[1];

        auto rVal = engine.getProperty(opts, "redirect");
        if (engine.isString(rVal))
        {
            auto r = engine.extractString(rVal);
            if (r == "follow" || r == "manual" || r == "error")
                redirectMode = r;
        }
        engine.freeValue(rVal);
        auto mVal = engine.getProperty(opts, "method");
        if (engine.isString(mVal))
            method = engine.extractString(mVal);
        engine.freeValue(mVal);

        auto bVal = engine.getProperty(opts, "body");
        if (engine.isString(bVal))
        {
            reqBody = engine.extractString(bVal);
            hasBody = true;
        }
        engine.freeValue(bVal);

        // Headers init may be a plain object, an Array<[k,v]>, or a
        // Headers instance. Flatten to a flat ["k1", "v1", "k2", "v2",
        // ...] string array via a JS helper — one engine.call instead
        // of an FFI-heavy forEach trampoline — and then iterate
        // pair-wise on the D side. The flat-array shape avoids the
        // need for getOwnPropertyNames (which isn't on IJSEngine).
        auto hVal = engine.getProperty(opts, "headers");
        if (engine.isObject(hVal))
        {
            ensureHeadersFlattener(engine);
            if (_fetchHeadersFlattenerCached)
            {
                JSHandle[1] callArgs = [hVal];
                auto flat = engine.callFunction(_fetchHeadersFlattener, engine.newUndefined(), callArgs[]);
                if (engine.isArray(flat))
                {
                    auto n = engine.getArrayLength(flat);
                    for (int i = 0; i + 1 < n; i += 2)
                    {
                        auto k = engine.getPropertyIndex(flat, cast(uint) i);
                        auto v = engine.getPropertyIndex(flat, cast(uint)(i + 1));
                        if (engine.isString(k) && engine.isString(v))
                            reqHeaders[engine.extractString(k)] = engine.extractString(v);
                        engine.freeValue(k);
                        engine.freeValue(v);
                    }
                }
                engine.freeValue(flat);
            }
        }
        engine.freeValue(hVal);
    }

    import dun.engine.iface : PromiseHandles;
    import dun.loop.async : asyncSubmit, ResultTransform;

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    ResultTransform transform = (IJSEngine eng, string serialized) @trusted {
        auto result = deserializeFetchResult(serialized);
        return makeResponse(eng, result);
    };

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        auto result = doFetch(url, method, reqBody, hasBody, reqHeaders, 0, redirectMode);
        return serializeFetchResult(result);
    }, transform);

    return ph.promise;
}

string serializeFetchResult(FetchResult r) @safe
{

    Appender!(char[]) s;
    s.reserve(SERIALIZE_RESERVE + r.body_.length);
    s ~= r.status.to!string; s ~= "\n";
    s ~= (r.ok ? "1" : "0"); s ~= "\n";
    s ~= r.statusText; s ~= "\n";
    s ~= r.url; s ~= "\n";

    Appender!(char[]) hdrs;
    hdrs.reserve(HEADERS_RESERVE);
    foreach (k, v; r.headers)
    { hdrs ~= k; hdrs ~= ": "; hdrs ~= v; hdrs ~= "\r\n"; }
    auto hdrSlice = (() @trusted => hdrs[])();
    s ~= hdrSlice.length.to!string; s ~= "\n";
    s ~= hdrSlice;
    s ~= r.body_;
    return (() @trusted => cast(string) s[])();
}

FetchResult deserializeFetchResult(string s) @safe
{
    import std.string : indexOf;

    FetchResult r;
    string remaining = s;

    string nextLine()
    {
        auto idx = remaining.indexOf('\n');
        if (idx < 0) { auto l = remaining; remaining = ""; return l; }
        auto l = remaining[0 .. idx];
        remaining = remaining[idx + 1 .. $];
        return l;
    }

    try { r.status = nextLine().to!int; } catch (Exception) {}
    r.ok = nextLine() == "1";
    r.statusText = nextLine();
    r.url = nextLine();
    size_t hdrLen;
    try { hdrLen = nextLine().to!size_t; } catch (Exception) {}
    if (hdrLen > 0 && hdrLen <= remaining.length)
    {
        auto hdrBlock = remaining[0 .. hdrLen];
        remaining = remaining[hdrLen .. $];
        while (hdrBlock.length > 0)
        {
            auto lineEnd = hdrBlock.indexOf("\r\n");
            if (lineEnd < 0) break;
            auto line = hdrBlock[0 .. lineEnd];
            hdrBlock = hdrBlock[lineEnd + 2 .. $];
            auto colonIdx = line.indexOf(':');
            if (colonIdx >= 0)
            {
                import std.string : strip;
                r.headers[line[0 .. colonIdx].strip] = line[colonIdx + 1 .. $].strip;
            }
        }
    }
    r.body_ = remaining;
    return r;
}

/// `@mustuse` (DIP 1038): silently dropping a fetch result swallows
/// the HTTP status + body. Every caller in this codebase consumes
/// either `status` (for redirect chains) or `body_` (for the JS-side
/// `Response` wrapper) — none legitimately ignores the whole struct.
@mustuse
struct FetchResult
{
    int status;
    string statusText;
    string body_;
    string[string] headers;
    string url;
    bool ok;
}

// Fetch spec hard limit of 20 redirect hops before erroring;
// we use 5 as a more conservative default consistent with curl's
// default. Bumpable via the redirectMode handling at the call site.
enum int MAX_REDIRECT_FOLLOWS = 5;

FetchResult doFetch(string url, string method, string reqBody,
    bool hasBody, string[string] reqHeaders, int redirectCount = 0,
    string redirectMode = "follow") @trusted
{
    import std.string : indexOf, toLower;

    if (redirectCount > MAX_REDIRECT_FOLLOWS)
        throw new Exception("too many redirects");

    auto parsed = parseUrl(url);

    if (parsed.scheme != "http" && parsed.scheme != "https")
        throw new Exception("fetch: unsupported scheme '" ~ parsed.scheme
            ~ "' (only http/https allowed)");

    bool isTls = parsed.scheme == "https";
    ushort port = parsed.port;
    if (port == 0)
        port = isTls ? cast(ushort) 443 : cast(ushort) 80;

    int fd = tcpConnect(parsed.host, port);
    if (fd < 0)
        throw new Exception("connection failed to " ~ parsed.host);

    version (Posix)
    {
        scope (exit)
        {
            if (!isTls)
            {
                import core.sys.posix.unistd : close;
                close(fd);
            }
        }
    }

    version (Posix)
    {
        if (isTls)
        {
            import dun.builtins.tls : TlsSocket;
            TlsSocket tls;
            auto hostZ = (parsed.host ~ "\0").ptr;
            if (!tls.connect(fd, hostZ))
            {
                import dun.builtins.tls : tlsLastError;
                throw new Exception("TLS handshake failed: " ~ tlsLastError());
            }

            string req = buildRequest(method, parsed, reqBody, hasBody, reqHeaders);
            auto reqBytes = cast(const(ubyte)[]) req;
            size_t sent = 0;
            while (sent < reqBytes.length)
            {
                int n = tls.write(reqBytes.ptr + sent,
                    cast(int)(reqBytes.length - sent));
                if (n <= 0) throw new Exception("TLS write failed");
                sent += n;
            }

            auto response = readHttpResponse(
                (ubyte[] buf) @trusted {
                    return tls.read(buf.ptr, cast(int) buf.length);
                });

            tls.close();

            // Redirect handling per Fetch spec: "follow" chases, "error"
            // throws a TypeError, "manual" returns the 3xx response so
            // the caller can inspect Location / set-cookie / etc.
            if (response.status >= 301 && response.status <= 308)
            {
                if (redirectMode == "error")
                    throw new Exception("fetch: redirected with redirect:error");
                if (redirectMode == "follow")
                {
                    if (auto loc = "location" in response.headers)
                    {
                        string newUrl = *loc;
                        if (newUrl.length > 0 && newUrl[0] == '/')
                            newUrl = parsed.scheme ~ "://" ~ parsed.host ~ newUrl;
                        return doFetch(newUrl, method, reqBody, hasBody,
                            reqHeaders, redirectCount + 1, redirectMode);
                    }
                }
                // redirectMode == "manual": fall through, return 3xx as-is.
            }
            response.url = url;
            return response;
        }
    }

    // Plain HTTP (Posix only — Windows uses TLS path or stubs)
    version (Posix)
    {
        string req = buildRequest(method, parsed, reqBody, hasBody, reqHeaders);
        auto reqBytes = cast(const(ubyte)[]) req;
        {
            import core.sys.posix.unistd : posixWrite = write;
            size_t sent = 0;
            while (sent < reqBytes.length)
            {
                auto n = posixWrite(fd, reqBytes.ptr + sent, reqBytes.length - sent);
                if (n <= 0) throw new Exception("write failed");
                sent += n;
            }
        }

        auto response = readHttpResponse(
            (ubyte[] buf) @trusted {
                import core.sys.posix.unistd : posixRead = read;
                return cast(int) posixRead(fd, buf.ptr, buf.length);
            });

        if (response.status >= 301 && response.status <= 308)
        {
            if (redirectMode == "error")
                throw new Exception("fetch: redirected with redirect:error");
            if (redirectMode == "follow")
            {
                if (auto loc = "location" in response.headers)
                {
                    string newUrl = *loc;
                    if (newUrl.length > 0 && newUrl[0] == '/')
                        newUrl = parsed.scheme ~ "://" ~ parsed.host ~ newUrl;
                    return doFetch(newUrl, method, reqBody, hasBody,
                        reqHeaders, redirectCount + 1, redirectMode);
                }
            }
            // redirectMode == "manual": fall through, return 3xx as-is.
        }
        response.url = url;
        return response;
    }
    else
    {
        throw new Exception("fetch not supported on this platform");
    }
}

struct ParsedUrl
{
    string scheme;
    string host;
    ushort port;
    string path;
}

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

string buildRequest(string method, ParsedUrl p, string body_,
    bool hasBody, string[string] extraHeaders) @safe
{

    Appender!(char[]) r;
    r.reserve(REQUEST_RESERVE + body_.length);
    r ~= method; r ~= " "; r ~= p.path; r ~= " HTTP/1.1\r\n";
    r ~= "Host: "; r ~= p.host;
    if (p.port != 0 && p.port != 80 && p.port != 443)
    { r ~= ":"; r ~= p.port.to!string; }
    r ~= "\r\n";
    r ~= "Connection: close\r\n";
    r ~= "User-Agent: DunJS/1.0\r\n";
    r ~= "Accept: */*\r\n";

    foreach (k, v; extraHeaders)
    { r ~= k; r ~= ": "; r ~= v; r ~= "\r\n"; }

    if (hasBody)
    {
        r ~= "Content-Length: "; r ~= body_.length.to!string; r ~= "\r\n";
        if ("content-type" !in extraHeaders && "Content-Type" !in extraHeaders)
            r ~= "Content-Type: application/json\r\n";
    }

    r ~= "\r\n";
    if (hasBody) r ~= body_;
    return (() @trusted => cast(string) r[])();
}

FetchResult readHttpResponse(scope int delegate(ubyte[]) @trusted reader) @trusted
{
    import std.string : indexOf, toLower, strip;
    import std.algorithm : min;

    FetchResult result;
    result.ok = false;


    // Read all data into a buffer
    Appender!(ubyte[]) raw;
    raw.reserve(HTTP_READ_BUF);
    ubyte[HTTP_READ_BUF] buf;
    while (true)
    {
        int n = reader(buf[]);
        if (n <= 0) break;
        raw ~= buf[0 .. n];

        // Check if we have the full headers
        auto rawSlice = raw[];
        auto rawStr = cast(string) rawSlice;
        auto headerEnd = rawStr.indexOf("\r\n\r\n");
        if (headerEnd >= 0)
        {
            // Parse headers
            auto headerPart = rawStr[0 .. headerEnd];
            auto bodyStart = headerEnd + 4;

            // Status line
            auto firstLine = headerPart;
            auto nlIdx = headerPart.indexOf("\r\n");
            if (nlIdx >= 0)
            {
                firstLine = headerPart[0 .. nlIdx];
                headerPart = headerPart[nlIdx + 2 .. $];
            }

            // Parse "HTTP/1.1 200 OK"
            auto sp1 = firstLine.indexOf(' ');
            if (sp1 >= 0)
            {
                auto afterProto = firstLine[sp1 + 1 .. $];
                auto sp2 = afterProto.indexOf(' ');
                if (sp2 >= 0)
                {
                    try { result.status = afterProto[0 .. sp2].to!int; }
                    catch (Exception) { result.status = 0; }
                    result.statusText = afterProto[sp2 + 1 .. $];
                }
                else
                {
                    try { result.status = afterProto.to!int; }
                    catch (Exception) { result.status = 0; }
                }
            }

            // Parse header lines
            while (headerPart.length > 0)
            {
                auto lineEnd = headerPart.indexOf("\r\n");
                string line;
                if (lineEnd >= 0)
                {
                    line = headerPart[0 .. lineEnd];
                    headerPart = headerPart[lineEnd + 2 .. $];
                }
                else
                {
                    line = headerPart;
                    headerPart = "";
                }
                auto colonIdx = line.indexOf(':');
                if (colonIdx >= 0)
                {
                    string key = line[0 .. colonIdx].toLower.strip;
                    string val = line[colonIdx + 1 .. $].strip;
                    result.headers[key] = val;
                }
            }

            // Check Content-Length
            long contentLen = -1;
            if (auto cl = "content-length" in result.headers)
            {
                try { contentLen = (*cl).to!long; }
                catch (Exception) {}
            }

            // Check for chunked encoding
            bool chunked = false;
            if (auto te = "transfer-encoding" in result.headers)
                chunked = (*te).toLower.indexOf("chunked") >= 0;

            if (chunked)
            {
                // Read remaining data for chunked
                while (true)
                {
                    n = reader(buf[]);
                    if (n <= 0) break;
                    raw ~= buf[0 .. n];
                }
                result.body_ = decodeChunked(
                    cast(string) raw[][bodyStart .. $]);
            }
            else if (contentLen >= 0)
            {
                // Read exactly contentLen bytes
                while (cast(long)(raw[].length - bodyStart) < contentLen)
                {
                    n = reader(buf[]);
                    if (n <= 0) break;
                    raw ~= buf[0 .. n];
                }
                auto end = min(bodyStart + cast(size_t) contentLen, raw[].length);
                result.body_ = (cast(string) raw[][bodyStart .. end]).idup;
            }
            else
            {
                // Connection: close — read until EOF
                while (true)
                {
                    n = reader(buf[]);
                    if (n <= 0) break;
                    raw ~= buf[0 .. n];
                }
                result.body_ = (cast(string) raw[][bodyStart .. $]).idup;
            }

            break;
        }
    }

    result.ok = result.status >= 200 && result.status < 300;
    return result;
}

string decodeChunked(string data) @safe
{
    import std.string : indexOf;

    string result;
    string remaining = data;

    while (remaining.length > 0)
    {
        auto lineEnd = remaining.indexOf("\r\n");
        if (lineEnd < 0) break;

        string sizeLine = remaining[0 .. lineEnd];
        remaining = remaining[lineEnd + 2 .. $];

        // Parse hex chunk size
        size_t chunkSize;
        try { chunkSize = sizeLine.to!size_t(16); }
        catch (Exception) { break; }

        if (chunkSize == 0) break;
        if (chunkSize > remaining.length) break;

        result ~= remaining[0 .. chunkSize];
        remaining = remaining[chunkSize .. $];

        // Skip trailing \r\n
        if (remaining.length >= 2 && remaining[0 .. 2] == "\r\n")
            remaining = remaining[2 .. $];
    }

    return result;
}

version (Posix)
{
    int tcpConnect(string host, ushort port) @trusted
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netdb : getaddrinfo, addrinfo, freeaddrinfo;
        import core.sys.posix.unistd : close;
        import core.stdc.string : memset;

        addrinfo hints;
        memset(&hints, 0, hints.sizeof);
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        auto portStr = port.to!string ~ "\0";
        auto hostZ = (host ~ "\0").ptr;

        addrinfo* res;
        if (getaddrinfo(hostZ, portStr.ptr, &hints, &res) != 0)
            return -1;
        scope (exit) freeaddrinfo(res);

        for (auto rp = res; rp !is null; rp = rp.ai_next)
        {
            int fd = socket(rp.ai_family, rp.ai_socktype, rp.ai_protocol);
            if (fd < 0) continue;

            if (connect(fd, rp.ai_addr, rp.ai_addrlen) == 0)
                return fd;

            close(fd);
        }

        return -1;
    }
}
else
{
    int tcpConnect(string, ushort) @trusted { return -1; }
}

/* Cached Response constructor. Compiled exactly once, then called
   per fetch with (body, status, statusText, url, headerEntries) as
   value arguments — no per-fetch bytecode compilation.

   Bisect via /debug-native-callback identified the previous
   per-fetch `engine.eval(<unique-source-with-embedded-body>)` as the
   root of the JSC fetch-cycle hang: each call compiled fresh
   bytecode into JSC's cache (uncacheable because the source string
   embedded the response body). At ~9 MB heap growth per fetch on
   JSC, the 27-fetch threshold matched a ~243 MB JSC heap budget.
   With the cache, only the value arguments allocate per fetch. */
__gshared JSHandle _fetchResponseBuilder;
__gshared bool _fetchResponseBuilderCached = false;
__gshared JSHandle _fetchHeadersFlattener;
__gshared bool _fetchHeadersFlattenerCached = false;

private void ensureHeadersFlattener(IJSEngine engine) @trusted
{
    if (_fetchHeadersFlattenerCached) return;
    enum src = "(h => { const out = []; if (!h) return out; "
        ~ "const push = (k, v) => { out.push(String(k).toLowerCase(), String(v)); }; "
        ~ "if (h instanceof Headers || typeof h.forEach === 'function') { "
        ~ "  h.forEach((v, k) => push(k, v)); return out; "
        ~ "} "
        ~ "if (Array.isArray(h)) { for (const [k, v] of h) push(k, v); return out; } "
        ~ "for (const k of Object.keys(h)) push(k, h[k]); return out; "
        ~ "})";
    auto result = engine.eval(src, "<fetch-headers-flatten>");
    if (!result.isError && engine.isFunction(result.value))
    {
        /* `dupValue` on JSC returns the same JSValueRef with the
           protect counter incremented; `freeValue` would decrement
           and bring it back to 0 (JSC's `JSEvaluateScript` returns
           an unprotected value). To pin the cached handle alive
           permanently, do TWO `dupValue` calls — the first matches
           the implicit eval-return ownership we're freeing; the
           second is the permanent root. On QJS / V8 this is a
           +1 refcount that lives forever (intended — this is a
           permanently-cached __gshared global). */
        engine.dupValue(result.value);
        _fetchHeadersFlattener = engine.dupValue(result.value);
        _fetchHeadersFlattenerCached = true;
    }
    engine.freeValue(result.value);
}

private void ensureResponseBuilder(IJSEngine engine) @trusted
{
    if (_fetchResponseBuilderCached) return;
    enum builderSrc = "(function(body,status,statusText,url,headerEntries){"
        ~ "var h=new Headers();"
        ~ "for(var i=0;i<headerEntries.length;i++)"
        ~ "  h.append(headerEntries[i][0],headerEntries[i][1]);"
        ~ "var r=new Response(body,{status:status,statusText:statusText,headers:h});"
        ~ "Object.defineProperty(r,'url',{value:url,writable:false,enumerable:true});"
        ~ "return r;"
        ~ "})";
    auto result = engine.eval(builderSrc, "<fetch-response-builder>");
    if (!result.isError && engine.isFunction(result.value))
    {
        // Double-dup so the cached __gshared handle survives the
        // freeValue below — JSC's eval returns an unprotected
        // JSValueRef and `freeValue` would otherwise drop the
        // protect counter back to 0. See ensureHeadersFlattener
        // for the full explanation.
        engine.dupValue(result.value);
        _fetchResponseBuilder = engine.dupValue(result.value);
        _fetchResponseBuilderCached = true;
    }
    engine.freeValue(result.value);
}

JSHandle makeResponse(IJSEngine engine, FetchResult r) @trusted
{
    ensureResponseBuilder(engine);
    if (!_fetchResponseBuilderCached)
        return makeResponseFallback(engine, r);

    auto bodyVal = engine.newString(r.body_);
    auto statusVal = engine.newInt(r.status);
    auto statusTextVal = engine.newString(r.statusText);
    auto urlVal = engine.newString(r.url);

    auto headerArr = engine.newArray();
    uint idx = 0;
    /* setPropertyIndex has split semantics across backends:
         QJS: consumes `val` (JS_SetPropertyUint32) — must NOT freeValue
         JSC: doesn't consume — caller must freeValue
         V8:  doesn't consume — caller must freeValue
       Same dual-path pattern as `setProperty` for req/socket aliasing
       in builtins/http.d:873-887. Without the version split, QJS
       double-frees and corrupts the malloc tcache; JSC/V8 leaks one
       refcount per pair. */
    foreach (k, v; r.headers)
    {
        auto pair = engine.newArray();
        auto kVal = engine.newString(k);
        auto vVal = engine.newString(v);
        engine.setPropertyIndex(pair, 0, kVal);
        engine.setPropertyIndex(pair, 1, vVal);
        version (EngineQuickJS)
        {
            // QJS consumed the values — nothing to free
        }
        else
        {
            engine.freeValue(kVal);
            engine.freeValue(vVal);
        }
        engine.setPropertyIndex(headerArr, idx, pair);
        version (EngineQuickJS)
        {
            // QJS consumed pair — nothing to free
        }
        else
        {
            engine.freeValue(pair);
        }
        idx++;
    }

    JSHandle[5] callArgs = [bodyVal, statusVal, statusTextVal, urlVal, headerArr];
    auto resp = engine.callFunction(_fetchResponseBuilder, engine.newUndefined(), callArgs[]);

    engine.freeValue(bodyVal);
    engine.freeValue(statusVal);
    engine.freeValue(statusTextVal);
    engine.freeValue(urlVal);
    engine.freeValue(headerArr);

    return resp;
}

JSHandle makeResponseFallback(IJSEngine engine, FetchResult r) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "status", engine.newInt(r.status));
    engine.setProperty(obj, "ok", engine.newBool(r.ok));
    engine.setProperty(obj, "statusText", engine.newString(r.statusText));
    engine.setProperty(obj, "url", engine.newString(r.url));
    engine.setProperty(obj, "__body", engine.newString(r.body_));
    engine.setProperty(obj, "text",
        engine.newFunction(&responseText, "text", 0));
    engine.setProperty(obj, "json",
        engine.newFunction(&responseJson, "json", 0));
    auto hdrs = engine.newObject();
    foreach (k, v; r.headers)
        engine.setProperty(hdrs, k, engine.newString(v));
    engine.setProperty(obj, "headers", hdrs);
    return obj;
}

JSHandle responseText(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in responseText");
    auto engine = state.engine;
    auto body_ = engine.getProperty(thisVal, "__body");
    return body_;
}

JSHandle responseJson(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in responseJson");
    auto engine = state.engine;
    auto body_ = engine.getProperty(thisVal, "__body");
    scope (exit) engine.freeValue(body_);

    if (!engine.isString(body_))
        return engine.throwTypeError("response body is not a string");

    string bodyStr = engine.extractString(body_);
    auto result = engine.eval("JSON.parse(" ~ jsonQuote(bodyStr) ~ ")", "<fetch>");
    if (result.isError)
        return engine.throwTypeError("invalid JSON in response body");
    return result.value;
}

string jsonQuote(string s) @safe
{
    Appender!(char[]) r;
    r.reserve(s.length + s.length / 4 + 2);
    r ~= '"';
    foreach (c; s)
    {
        switch (c)
        {
        case '"': r ~= `\"`; break;
        case '\\': r ~= `\\`; break;
        case '\n': r ~= `\n`; break;
        case '\r': r ~= `\r`; break;
        case '\t': r ~= `\t`; break;
        default: r ~= c;
        }
    }
    r ~= '"';
    return (() @trusted => cast(string) r[])();
}
