module dun.builtins.http;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.loop.agnostic_pending : pushAgnosticPending;

version (linux)
{
    private extern (C) int accept4(int, void*, void*, int) nothrow @nogc;
}

private enum {
    HTTP_STATUS_OK    = 200,
    HTTP_DEFAULT_PORT = 80,
    HTTP_LISTEN_BACKLOG = 1024,
    HTTP_MAX_HEADER_NAME = 128,
    IO_POLL_BATCH_SIZE = 256,
}

private string sizeToStr(size_t n) nothrow @trusted
{
    if (n < 100)
    {
        static immutable string[100] SMALL = () {
            string[100] t;
            foreach (i; 0 .. 100)
            {
                char[3] buf;
                int pos = 3;
                size_t v = i;
                if (v == 0) { buf[--pos] = '0'; }
                else while (v > 0) { buf[--pos] = cast(char)('0' + v % 10); v /= 10; }
                t[i] = buf[pos .. 3].idup;
            }
            return t;
        }();
        return SMALL[n];
    }
    char[20] buf;
    int pos = 20;
    while (n > 0) { buf[--pos] = cast(char)('0' + n % 10); n /= 10; }
    try return buf[pos .. 20].idup; catch (Exception) return "0";
}

// Interned header names — returns compile-time string for known headers,
// avoiding GC allocation (.idup) on every request
private string internHeaderName(const(char)[] raw) nothrow @trusted
{
    static immutable string[17] known = [
        "host", "connection", "content-type", "content-length",
        "accept", "accept-encoding", "accept-language", "user-agent",
        "cache-control", "cookie", "authorization", "transfer-encoding",
        "upgrade", "origin", "referer", "x-forwarded-for", "if-none-match",
    ];
    foreach (k; known)
        if (k.length == raw.length && k == raw)
            return k;
    // Uncommon header: must allocate
    try return cast(string) raw.idup;
    catch (Exception) return "";
}

private string sanitizeHeaderValue(string s) @safe pure
{
    foreach (ch; s)
        if (ch == '\r' || ch == '\n' || ch == '\0')
            return stripCRLF(s);
    return s;
}

private string stripCRLF(string s) @safe pure
{
    char[] result;
    result.reserve(s.length);
    foreach (ch; s)
        if (ch != '\r' && ch != '\n' && ch != '\0')
            result ~= ch;
    return result.idup;
}

void registerHttpModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerHttpModule");
    auto obj = engine.newObject();
    engine.setProperty(obj, "createServer", engine.newFunction(&jsHttpCreateServer, "createServer", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_http__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:http", &httpModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "createServer");
        JS_AddModuleExport(ctx, m, "STATUS_CODES");
    }

    private extern (C) int httpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in httpModuleInit");
        assert(m !is null, "Null JSModuleDef in httpModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto httpObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_http__");
        foreach (name; ["createServer", "STATUS_CODES"])
        {
            auto fn = JS_GetPropertyStr(ctx, httpObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, httpObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    private IOPoller gHttpPoller;
    private bool gHttpPollerInited = false;

    private void ensureHttpPoller() nothrow @trusted
    {
        if (!gHttpPollerInited) { gHttpPoller.initialize(); gHttpPollerInited = true; }
    }
}

private:

// Cached function handles for HTTP server/req/res objects
__gshared JSHandle _httpSrvListen, _httpSrvClose, _httpSrvOn;
__gshared JSHandle _httpReqOn;
__gshared JSHandle _httpResSetHeader, _httpResWriteHead, _httpResWrite, _httpResEnd;
__gshared JSHandle _httpJsDispatchFn;
__gshared JSHandle _httpCachedUndef;
__gshared bool _httpFnsCached = false;

void ensureHttpFnsCached(IJSEngine engine) @trusted
{
    if (_httpFnsCached) return;
    _httpSrvListen = engine.newFunction(&jsHttpServerListen, "listen", 1);
    _httpSrvClose = engine.newFunction(&jsHttpServerClose, "close", 0);
    _httpSrvOn = engine.newFunction(&jsHttpServerOn, "on", 2);
    _httpReqOn = engine.newFunction(&jsReqOn, "on", 2);
    _httpResSetHeader = engine.newFunction(&jsResSetHeader, "setHeader", 2);
    _httpResWriteHead = engine.newFunction(&jsResWriteHead, "writeHead", 1);
    _httpResWrite = engine.newFunction(&jsResWrite, "write", 1);
    _httpResEnd = engine.newFunction(&jsResEnd, "end", 0);

    // Install JS-level dispatch function — creates req/res objects in JS (JIT-optimized)
    // instead of through D→engine FFI calls, reducing per-request overhead
    auto global = engine.getGlobal();
    engine.setProperty(global, "__httpSetHeader", engine.dupValue(_httpResSetHeader));
    engine.setProperty(global, "__httpWriteHead", engine.dupValue(_httpResWriteHead));
    engine.setProperty(global, "__httpWrite", engine.dupValue(_httpResWrite));
    engine.setProperty(global, "__httpEnd", engine.dupValue(_httpResEnd));
    engine.setProperty(global, "__httpReqOn", engine.dupValue(_httpReqOn));

    // Native function to lazily retrieve headers for a connection
    auto getHdrsFn = engine.newFunction(&jsGetConnHeaders, "__httpGetHeaders", 1);
    engine.setProperty(global, "__httpGetHeaders", getHdrsFn);
    engine.freeValue(global);

    import dun.engine.iface : JSResult;
    auto dispatchResult = engine.eval(
        "(function(cb, method, url, cid) {" ~
        "  var _gh = globalThis.__httpGetHeaders;" ~
        "  var req = { method: method, url: url, httpVersion: 'HTTP/1.1', __cid: cid," ~
        "    get headers() { var h = _gh(cid); Object.defineProperty(this, 'headers', {value: h}); return h; }," ~
        "    on: globalThis.__httpReqOn };" ~
        "  var res = { __cid: cid, statusCode: 200," ~
        "    setHeader: globalThis.__httpSetHeader," ~
        "    writeHead: globalThis.__httpWriteHead," ~
        "    write: globalThis.__httpWrite," ~
        "    end: globalThis.__httpEnd };" ~
        "  cb(req, res);" ~
        "})", "<http-dispatch>");
    if (!dispatchResult.isError && engine.isFunction(dispatchResult.value))
        _httpJsDispatchFn = engine.dupValue(dispatchResult.value);
    engine.freeValue(dispatchResult.value);

    _httpCachedUndef = engine.newUndefined();
    _httpFnsCached = true;
}

struct HttpServerState
{
    IJSEngine engine;
    JSHandle requestCb;
    int listenFd = -1;
    bool active;
    ushort port;
    bool cbSet;
}

enum MAX_BUF = 16 * 1024;

struct HttpConnState
{
    IJSEngine engine;
    int srvId;
    int fd = -1;
    bool closed;
    char[MAX_BUF] buf;
    size_t bufLen;
    const(char)[] method;
    const(char)[] url;
    const(char)[] httpVersion;
    const(char)[][string] headers;
    size_t contentLength;
    size_t bodyStart;
    bool headersDone;
    int statusCode = HTTP_STATUS_OK;
    string[string] respHeaders;
    bool headersSent;
    bool keepAlive;
    // Buffered response — headers+body combined into single write()
    char[MAX_BUF] respBuf;
    size_t respLen;
}

// fd → connection index for O(1) lookup (avoids O(n) scan in pollHttpIO)
int[int] fdToConnId;

HttpServerState[] httpServers;
HttpConnState[] httpConns;
int nextHttpServerId;
int nextHttpConnId;

// Free list for connection slot reuse (avoids unbounded array growth)
int[] httpFreeSlots;

// Direct dispatch queue — bypasses agnostic pending for lower latency
enum MAX_HTTP_READY = 256;
int[MAX_HTTP_READY] httpReadyConns;
int httpReadyCount;

// Allocate or reuse a connection slot
int allocConnSlot() nothrow @trusted
{
    if (httpFreeSlots.length > 0)
    {
        try
        {
            int slot = httpFreeSlots[$ - 1];
            httpFreeSlots = httpFreeSlots[0 .. $ - 1];
            return slot;
        }
        catch (Throwable) {}
    }
    return nextHttpConnId++;
}

// Return a connection slot to the free list
void freeConnSlot(int slot) nothrow @trusted
{
    _activeConnCount--;
    try { httpFreeSlots ~= slot; } catch (Throwable) {}
}

JSHandle jsHttpCreateServer(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpCreateServer");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHttpCreateServer");
    auto engine = state.engine;

    JSHandle cb;
    bool hasCb = false;
    if (args.length >= 1 && engine.isFunction(args[0]))
    {
        cb = engine.dupValue(args[0]);
        hasCb = true;
    }

    int id = nextHttpServerId++;
    try
    {
        HttpServerState srv;
        srv.engine = engine;
        if (hasCb) { srv.requestCb = cb; srv.cbSet = true; }
        httpServers ~= srv;
    }
    catch (Throwable)
    {
        if (hasCb) engine.freeValue(cb);
        return engine.throwTypeError("http.createServer: out of memory");
    }
    return makeHttpServerObj(engine, id);
}

JSHandle makeHttpServerObj(IJSEngine engine, int id) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeHttpServerObj");
    ensureHttpFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__hid", engine.newInt(id));
    engine.setProperty(obj, "listen", engine.dupValue(_httpSrvListen));
    engine.setProperty(obj, "close", engine.dupValue(_httpSrvClose));
    engine.setProperty(obj, "on", engine.dupValue(_httpSrvOn));
    return obj;
}

JSHandle jsHttpServerListen(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpServerListen");
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsHttpServerListen");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__hid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) httpServers.length)
            return engine.throwTypeError("server.listen: invalid server");

        auto srv = &httpServers[idVal];

        int port = HTTP_DEFAULT_PORT;
        JSHandle listenCb;
        bool hasCb = false;
        if (args.length >= 1 && engine.isNumber(args[0]))
            port = engine.extractInt(args[0]);
        if (args.length >= 2 && engine.isFunction(args[1]))
        {
            listenCb = engine.dupValue(args[1]);
            hasCb = true;
        }
        else if (args.length >= 3 && engine.isFunction(args[2]))
        {
            listenCb = engine.dupValue(args[2]);
            hasCb = true;
        }

        int lfd = socket(AF_INET, SOCK_STREAM, 0);
        if (lfd < 0)
        {
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("http server: socket() failed");
        }

        int one = 1;
        setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);
        setsockopt(lfd, SOL_SOCKET, SO_REUSEPORT, &one, one.sizeof);

        int fl = fcntl(lfd, F_GETFL, 0);
        fcntl(lfd, F_SETFL, fl | O_NONBLOCK);

        sockaddr_in addr;
        memset(&addr, 0, addr.sizeof);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(cast(ushort) port);
        addr.sin_addr.s_addr = 0;

        if (bind(lfd, cast(sockaddr*)&addr, addr.sizeof) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("http server: bind() failed");
        }
        if (listen(lfd, HTTP_LISTEN_BACKLOG) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("http server: listen() failed");
        }

        srv.listenFd = lfd;
        srv.active = true;
        _activeServerCount++;
        srv.port = cast(ushort) port;

        version (linux)
        {
            ensureHttpPoller();
            gHttpPoller.watch(lfd, true, false);
        }

        if (hasCb)
        {
            JSHandle[0] noArgs;
            pushAgnosticPending(engine, listenCb, noArgs[]);
            engine.freeValue(listenCb);
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.throwTypeError("http server not supported on this platform");
    }
}

JSHandle jsHttpServerClose(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpServerClose");
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsHttpServerClose");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__hid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal >= 0 && idVal < cast(int) httpServers.length)
        {
            auto srv = &httpServers[idVal];
            if (srv.listenFd >= 0)
            {
                version (linux) gHttpPoller.unwatch(srv.listenFd);
                close(srv.listenFd);
                srv.listenFd = -1;
            }
            srv.active = false;
            _activeServerCount--;
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

JSHandle jsHttpServerOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpServerOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHttpServerOn");
    auto engine = state.engine;
    if (args.length < 2) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__hid");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) httpServers.length) return thisVal;

    auto ev = engine.extractString(args[0]);
    if (ev == "request" && engine.isFunction(args[1]))
    {
        auto srv = &httpServers[idVal];
        if (srv.cbSet) engine.freeValue(srv.requestCb);
        srv.requestCb = engine.dupValue(args[1]);
        srv.cbSet = true;
    }
    return thisVal;
}

// Request object
JSHandle makeReqObj(IJSEngine engine, int connId) @trusted
{
    auto conn = &httpConns[connId];
    auto obj = engine.newObject();
    engine.setProperty(obj, "__cid", engine.newInt(connId));
    engine.setProperty(obj, "method", engine.newString(conn.method));
    engine.setProperty(obj, "url", engine.newString(conn.url));
    engine.setProperty(obj, "httpVersion", engine.newString(conn.httpVersion));

    auto hdrs = engine.newObject();
    try
    {
        foreach (k, v; conn.headers)
            engine.setProperty(hdrs, k, engine.newString(v));
    }
    catch (Exception) {}
    engine.setProperty(obj, "headers", hdrs);
    ensureHttpFnsCached(engine);
    engine.setProperty(obj, "on", engine.dupValue(_httpReqOn));
    return obj;
}

JSHandle jsGetConnHeaders(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGetConnHeaders");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsGetConnHeaders");
    auto engine = state.engine;
    if (args.length < 1) return engine.newObject();
    int connId = engine.extractInt(args[0]);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newObject();
    auto conn = &httpConns[connId];
    auto hdrs = engine.newObject();
    try
    {
        foreach (k, v; conn.headers)
            engine.setProperty(hdrs, k, engine.newString(v));
    }
    catch (Exception) {}
    return hdrs;
}

JSHandle jsReqOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReqOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReqOn");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1])) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return thisVal;

    auto ev = engine.extractString(args[0]);
    auto conn = &httpConns[connId];
    auto cb = engine.dupValue(args[1]);

    if (ev == "data")
    {
        size_t bodyLen = conn.bufLen > conn.bodyStart ? conn.bufLen - conn.bodyStart : 0;
        if (bodyLen > 0)
        {
            auto jsBody = engine.newString(cast(string) conn.buf[conn.bodyStart .. conn.bufLen].idup);
            JSHandle[1] callArgs = [jsBody];
            pushAgnosticPending(engine, cb, callArgs[]);
            engine.freeValue(jsBody);
        }
        engine.freeValue(cb);
    }
    else if (ev == "end")
    {
        JSHandle[0] noArgs;
        pushAgnosticPending(engine, cb, noArgs[]);
        engine.freeValue(cb);
    }
    else
    {
        engine.freeValue(cb);
    }
    return thisVal;
}

// Response object
JSHandle makeResObj(IJSEngine engine, int connId) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "__cid", engine.newInt(connId));
    engine.setProperty(obj, "statusCode", engine.newInt(200));
    ensureHttpFnsCached(engine);
    engine.setProperty(obj, "setHeader", engine.dupValue(_httpResSetHeader));
    engine.setProperty(obj, "writeHead", engine.dupValue(_httpResWriteHead));
    engine.setProperty(obj, "write", engine.dupValue(_httpResWrite));
    engine.setProperty(obj, "end", engine.dupValue(_httpResEnd));
    return obj;
}

JSHandle jsResSetHeader(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResSetHeader");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResSetHeader");
    auto engine = state.engine;
    if (args.length < 2) return engine.newUndefined();

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

    try
    {
        string name = sanitizeHeaderValue(engine.extractString(args[0]));
        string val = sanitizeHeaderValue(engine.extractString(args[1]));
        httpConns[connId].respHeaders[name] = val;
    }
    catch (Exception) {}
    return engine.newUndefined();
}

JSHandle jsResWriteHead(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResWriteHead");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResWriteHead");
    auto engine = state.engine;

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

    auto conn = &httpConns[connId];
    if (args.length >= 1 && engine.isNumber(args[0]))
        conn.statusCode = engine.extractInt(args[0]);

    // Process headers object (second argument)
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        try
        {
            static immutable hdrs = [
                "Content-Type", "Content-Length", "Connection",
                "Cache-Control", "Location", "Server",
                "Set-Cookie", "Access-Control-Allow-Origin",
                "Transfer-Encoding", "X-Powered-By",
                "content-type", "content-length", "connection",
            ];
            foreach (name; hdrs)
            {
                auto val = engine.getProperty(args[1], name);
                if (!engine.isUndefined(val) && !engine.isNull(val))
                    conn.respHeaders[name] = sanitizeHeaderValue(engine.extractString(val));
                engine.freeValue(val);
            }
        }
        catch (Exception) {}
    }

    bufferStatusLine(conn);
    return engine.newUndefined();
}

JSHandle jsResWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResWrite");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsResWrite");
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newBool(false);

    auto conn = &httpConns[connId];
    if (conn.closed || conn.fd < 0) return engine.newBool(false);

    if (!conn.headersSent) bufferStatusLine(conn);
    // For streaming writes, flush buffer then send data directly
    flushResponse(conn);
    auto body_ = engine.extractString(args[0]);
    sendRaw(conn, body_);
    return engine.newBool(true);
}

JSHandle jsResEnd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResEnd");
    version (Posix)
    {
        import core.sys.posix.unistd : close;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsResEnd");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__cid");
        int connId = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

        auto conn = &httpConns[connId];
        if (conn.closed) return engine.newUndefined();

        // Buffer body data
        if (args.length >= 1)
        {
            auto body_ = engine.extractString(args[0]);
            // Auto-set Content-Length if not already set
            if (!conn.headersSent && "Content-Length" !in conn.respHeaders
                && "content-length" !in conn.respHeaders)
            {
                conn.respHeaders["Content-Length"] = sizeToStr(body_.length);
            }
            if (!conn.headersSent) bufferStatusLine(conn);
            bufferData(conn, body_);
        }
        else
        {
            if (!conn.headersSent) bufferStatusLine(conn);
        }

        // Flush everything in ONE write() — avoids Nagle+delayed-ACK latency
        flushResponse(conn);

        if (conn.keepAlive)
        {
            // Reset for next request on same connection
            size_t consumed = conn.bodyStart;
            if (conn.contentLength <= MAX_BUF - consumed)
                consumed += conn.contentLength;
            else
                consumed = conn.bufLen;
            size_t remaining = conn.bufLen > consumed ? conn.bufLen - consumed : 0;
            if (remaining > 0)
            {
                for (size_t i = 0; i < remaining; i++)
                    conn.buf[i] = conn.buf[consumed + i];
            }
            conn.bufLen = remaining;
            conn.headersDone = false;
            conn.headersSent = false;
            conn.bodyStart = 0;
            conn.contentLength = 0;
            conn.statusCode = HTTP_STATUS_OK;
            conn.respLen = 0;
            conn.method = null;
            conn.url = null;
            conn.httpVersion = null;
            try
            {
                conn.headers.clear();
                conn.respHeaders.clear();
            }
            catch (Throwable) {}

            // If we already have data from next request, try parsing it
            if (remaining > 0)
                tryParseHeaders(conn, connId);
        }
        else
        {
            conn.closed = true;
            if (conn.fd >= 0)
            {
                version (linux) gHttpPoller.unwatch(conn.fd);
                fdToConnId.remove(conn.fd);
                close(conn.fd);
                conn.fd = -1;
            }
            freeConnSlot(connId);
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

// CTFE pre-computed status lines — zero allocation in hot path
string statusLine(int code) pure nothrow @safe @nogc
{
    switch (code)
    {
        case 200: return "HTTP/1.1 200 OK\r\n";
        case 201: return "HTTP/1.1 201 Created\r\n";
        case 204: return "HTTP/1.1 204 No Content\r\n";
        case 301: return "HTTP/1.1 301 Moved Permanently\r\n";
        case 302: return "HTTP/1.1 302 Found\r\n";
        case 304: return "HTTP/1.1 304 Not Modified\r\n";
        case 400: return "HTTP/1.1 400 Bad Request\r\n";
        case 401: return "HTTP/1.1 401 Unauthorized\r\n";
        case 403: return "HTTP/1.1 403 Forbidden\r\n";
        case 404: return "HTTP/1.1 404 Not Found\r\n";
        case 413: return "HTTP/1.1 413 Payload Too Large\r\n";
        case 500: return "HTTP/1.1 500 Internal Server Error\r\n";
        default: return "HTTP/1.1 200 OK\r\n";
    }
}

void bufferStatusLine(HttpConnState* conn) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in bufferStatusLine");
    if (conn.headersSent || conn.fd < 0) return;
    conn.headersSent = true;

    try
    {
        void bufAppend(const(char)[] s) nothrow @trusted {
            size_t avail = MAX_BUF - conn.respLen;
            size_t n = s.length < avail ? s.length : avail;
            if (n > 0) {
                conn.respBuf[conn.respLen .. conn.respLen + n] = s[0 .. n];
                conn.respLen += n;
            }
        }

        bufAppend(statusLine(conn.statusCode));

        if ("Content-Type" !in conn.respHeaders)
            conn.respHeaders["Content-Type"] = "text/plain";
        if (!conn.keepAlive)
            conn.respHeaders["Connection"] = "close";
        else if ("Connection" !in conn.respHeaders)
            conn.respHeaders["Connection"] = "keep-alive";
        foreach (k, v; conn.respHeaders)
        {
            bufAppend(k);
            bufAppend(": ");
            bufAppend(v);
            bufAppend("\r\n");
        }
        bufAppend("\r\n");
    }
    catch (Exception) {}
}

void bufferData(HttpConnState* conn, const(char)[] data) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in bufferData");
    size_t avail = MAX_BUF - conn.respLen;
    size_t n = data.length < avail ? data.length : avail;
    if (n > 0)
    {
        conn.respBuf[conn.respLen .. conn.respLen + n] = data[0 .. n];
        conn.respLen += n;
    }
}

void flushResponse(HttpConnState* conn) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in flushResponse");
    version (Posix)
    {
        if (conn.fd < 0 || conn.respLen == 0) return;
        import core.sys.posix.sys.socket : send, MSG_NOSIGNAL;
        size_t sent = 0;
        while (sent < conn.respLen)
        {
            auto n = send(conn.fd, conn.respBuf.ptr + sent, conn.respLen - sent, MSG_NOSIGNAL);
            if (n <= 0) break;
            sent += n;
        }
        conn.respLen = 0;
    }
}

void sendError(HttpConnState* conn, int status, string text, int connSlot = -1) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in sendError");
    bufferData(conn, statusLine(status));
    bufferData(conn, "Content-Length: 0\r\nConnection: close\r\n\r\n");
    flushResponse(conn);
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        conn.closed = true;
        version (linux) if (conn.fd >= 0) gHttpPoller.unwatch(conn.fd);
        if (conn.fd >= 0)
        {
            try { fdToConnId.remove(conn.fd); } catch (Exception) {}
            close(conn.fd);
            conn.fd = -1;
        }
        if (connSlot >= 0) freeConnSlot(connSlot);
    }
}

void sendRaw(HttpConnState* conn, string data) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in sendRaw");
    version (Posix)
    {
        if (conn.fd < 0 || data.length == 0) return;
        import core.sys.posix.sys.socket : send, MSG_NOSIGNAL;
        size_t sent = 0;
        while (sent < data.length)
        {
            auto n = send(conn.fd, data.ptr + sent, data.length - sent, MSG_NOSIGNAL);
            if (n <= 0) break;
            sent += n;
        }
    }
}

// I/O polling
public void pollHttpIO() nothrow @trusted
{
    version (linux)
    {
        ensureHttpPoller();
        IOEvent[IO_POLL_BATCH_SIZE] evBuf;
        auto events = gHttpPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            if (!ev.readable) continue;

            // Check listen sockets first (rare — only on new connections)
            bool isListenFd = false;
            foreach (i, ref srv; httpServers)
            {
                if (srv.active && srv.listenFd == ev.fd)
                {
                    acceptHttpConnection(cast(int) i);
                    isListenFd = true;
                    break;
                }
            }

            // O(1) lookup for client connections via fd→cid map
            if (!isListenFd)
            {
                try
                {
                    if (auto cidp = ev.fd in fdToConnId)
                        readHttpData(*cidp);
                }
                catch (Exception) {}
            }
        }
    }
}

private __gshared int _activeServerCount = 0;
private __gshared int _activeConnCount = 0;

public bool hasActiveHttpIO() nothrow @nogc @trusted
{
    return _activeServerCount > 0 || _activeConnCount > 0;
}

// Direct dispatch — call JS callbacks for ready connections
public void dispatchHttpCallbacks() @trusted
{
    while (httpReadyCount > 0)
    {
        int count = httpReadyCount;
        httpReadyCount = 0;

        foreach (i; 0 .. count)
        {
            int cid = httpReadyConns[i];
            if (cid < 0 || cid >= cast(int) httpConns.length) continue;
            auto conn = &httpConns[cid];
            if (conn.closed) continue;
            auto srv = &httpServers[conn.srvId];
            if (!srv.cbSet) continue;

            try
            {
                auto engine = srv.engine;
                if (_httpJsDispatchFn != JSHandle.init && !engine.isUndefined(_httpJsDispatchFn))
                {
                    // Fast path: JS-level dispatch creates req/res in JIT-optimized JS
                    // Only passes primitive values across FFI (3 strings + 1 int)
                    auto jsMethod = engine.newString(conn.method);
                    auto jsUrl = engine.newString(conn.url);
                    auto jsCid = engine.newInt(cid);
                    JSHandle[4] dArgs = [srv.requestCb, jsMethod, jsUrl, jsCid];
                    auto ret = engine.callFunction(_httpJsDispatchFn, _httpCachedUndef, dArgs[]);
                    engine.freeValue(ret);
                    engine.freeValue(jsMethod);
                    engine.freeValue(jsUrl);
                    engine.freeValue(jsCid);
                }
                else
                {
                    // Fallback: D-level object creation
                    auto reqObj = makeReqObj(engine, cid);
                    auto resObj = makeResObj(engine, cid);
                    JSHandle[2] callArgs = [reqObj, resObj];
                    auto ret = engine.callFunction(srv.requestCb, _httpCachedUndef, callArgs[]);
                    engine.freeValue(ret);
                    engine.freeValue(reqObj);
                    engine.freeValue(resObj);
                }
            }
            catch (Exception) {}
        }
    }
}

void acceptHttpConnection(int srvId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : accept, setsockopt;
        import core.sys.posix.netinet.in_ : IPPROTO_TCP;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (srvId < 0 || srvId >= cast(int) httpServers.length) return;
        auto srv = &httpServers[srvId];

        while (true)
        {
            int fd;
            version (linux)
            {
                // accept4: sets NONBLOCK+CLOEXEC atomically, saves 2 syscalls per connection
                enum SOCK_NONBLOCK = 0x800;
                enum SOCK_CLOEXEC  = 0x80000;
                fd = accept4(srv.listenFd, null, null, SOCK_NONBLOCK | SOCK_CLOEXEC);
            }
            else
            {
                fd = accept(srv.listenFd, null, null);
            }
            if (fd < 0) { if (errno == EAGAIN || errno == EWOULDBLOCK) break; break; }

            version (linux) {} else
            {
                int fl = fcntl(fd, F_GETFL, 0);
                fcntl(fd, F_SETFL, fl | O_NONBLOCK);
            }

            // TCP_NODELAY: disable Nagle's algorithm to prevent 40ms delayed-ACK latency
            enum TCP_NODELAY = 1;
            int one = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, one.sizeof);

            int cid = allocConnSlot();
            try
            {
                HttpConnState c;
                c.engine = srv.engine;
                c.srvId = srvId;
                c.fd = fd;
                c.statusCode = 200;
                if (cid < cast(int) httpConns.length)
                    httpConns[cid] = c;
                else
                    httpConns ~= c;
                fdToConnId[fd] = cid;
                _activeConnCount++;
            }
            catch (Throwable)
            {
                import core.sys.posix.unistd : close;
                close(fd);
                continue;
            }
            version (linux) gHttpPoller.watch(fd, true, false);
        }
    }
}

void readHttpData(int cid) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.unistd : read, close;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (cid < 0 || cid >= cast(int) httpConns.length) return;
        auto conn = &httpConns[cid];
        if (conn.closed || conn.fd < 0) return;

        bool gotData = false;
        bool gotEof = false;
        while (conn.bufLen < MAX_BUF)
        {
            auto n = read(conn.fd, conn.buf.ptr + conn.bufLen, MAX_BUF - conn.bufLen);
            if (n > 0)
            {
                conn.bufLen += n;
                gotData = true;
            }
            else if (n == 0)
            {
                gotEof = true;
                break;
            }
            else
            {
                if (errno == EAGAIN || errno == EWOULDBLOCK)
                    break;
                gotEof = true;
                break;
            }
        }

        // Client closed the connection
        if (gotEof && !gotData)
        {
            conn.closed = true;
            version (linux) gHttpPoller.unwatch(conn.fd);
            try { fdToConnId.remove(conn.fd); } catch (Exception) {}
            close(conn.fd);
            conn.fd = -1;
            freeConnSlot(cid);
            return;
        }

        if (!conn.headersDone)
            tryParseHeaders(conn, cid);
    }
}

void tryParseHeaders(HttpConnState* conn, int cid) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in tryParseHeaders");
    size_t sepPos = 0;
    bool found = false;
    for (size_t i = 0; i + 3 < conn.bufLen; i++)
    {
        if (conn.buf[i] == '\r' && conn.buf[i+1] == '\n'
            && conn.buf[i+2] == '\r' && conn.buf[i+3] == '\n')
        {
            sepPos = i;
            found = true;
            break;
        }
    }
    if (!found) return;

    conn.headersDone = true;
    conn.bodyStart = sepPos + 4;

    parseRequestHeaders(conn, conn.buf[0 .. sepPos]);

    // HTTP/1.1 defaults to keep-alive; HTTP/1.0 defaults to close
    bool isHttp11 = conn.httpVersion == "HTTP/1.1" || conn.httpVersion == "1.1";
    auto connHdr = "connection" in conn.headers;
    if (isHttp11)
        conn.keepAlive = connHdr is null || (*connHdr) != "close";
    else
        conn.keepAlive = connHdr !is null && (*connHdr) == "keep-alive";

    bool hasTE = ("transfer-encoding" in conn.headers) !is null;
    bool hasCL = ("content-length" in conn.headers) !is null;

    if (hasTE && hasCL)
    {
        sendError(conn, 400, "Bad Request", cid);
        return;
    }

    if (hasCL)
    {
        import std.conv : to;
        try { conn.contentLength = conn.headers["content-length"].to!size_t; } catch (Exception) {}
    }

    // Reject requests with Content-Length exceeding buffer capacity
    if (conn.contentLength > MAX_BUF || conn.bodyStart + conn.contentLength > MAX_BUF)
    {
        sendError(conn, 413, "Payload Too Large", cid);
        return;
    }

    bool bodyComplete = conn.bufLen >= conn.bodyStart + conn.contentLength;
    if (!bodyComplete) return;

    auto srv = &httpServers[conn.srvId];
    if (srv.cbSet && httpReadyCount < MAX_HTTP_READY)
    {
        httpReadyConns[httpReadyCount++] = cid;
    }
}

void parseRequestHeaders(HttpConnState* conn, const(char)[] text) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in parseRequestHeaders");
    try
    {
        size_t lineStart = 0;
        int lineNo = 0;

        import dun.platform.simd : asciiToLowerBuf;

        for (size_t i = 0; i <= text.length; i++)
        {
            if (i == text.length || text[i] == '\n')
            {
                size_t end = i;
                if (end > lineStart && text[end-1] == '\r') end--;
                auto lineSlice = text[lineStart .. end];
                lineStart = i + 1;

                if (lineNo == 0)
                {
                    // Request line: METHOD URL HTTP/1.1
                    // Zero-copy: slice directly into conn.buf (lives until keep-alive reset)
                    size_t sp1 = 0;
                    while (sp1 < lineSlice.length && lineSlice[sp1] != ' ') sp1++;
                    conn.method = lineSlice[0 .. sp1];
                    size_t sp2 = sp1 + 1;
                    while (sp2 < lineSlice.length && lineSlice[sp2] != ' ') sp2++;
                    if (sp1 < lineSlice.length)
                        conn.url = lineSlice[sp1 + 1 .. sp2];
                    if (sp2 + 1 < lineSlice.length)
                        conn.httpVersion = lineSlice[sp2 + 1 .. $];
                }
                else if (lineSlice.length > 0)
                {
                    // Header: Name: Value
                    size_t col = 0;
                    while (col < lineSlice.length && lineSlice[col] != ':') col++;
                    if (col < lineSlice.length)
                    {
                        char[HTTP_MAX_HEADER_NAME] nameBuf = void;
                        size_t nameLen = col < HTTP_MAX_HEADER_NAME ? col : HTTP_MAX_HEADER_NAME;
                        nameBuf[0 .. nameLen] = lineSlice[0 .. nameLen];
                        asciiToLowerBuf(nameBuf[0 .. nameLen]);
                        // Intern common header names to avoid GC allocation per request
                        string name = internHeaderName(nameBuf[0 .. nameLen]);

                        // Trim leading whitespace from value
                        // Zero-copy: slice directly into conn.buf (lives until keep-alive reset)
                        size_t valStart = col + 1;
                        while (valStart < lineSlice.length && lineSlice[valStart] == ' ') valStart++;
                        conn.headers[name] = lineSlice[valStart .. $];
                    }
                }
                lineNo++;
            }
        }
    }
    catch (Exception) {}
}
