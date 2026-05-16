module dun.builtins.http;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.loop.agnostic_pending : pushAgnosticPending;

version (Posix) { private import ssl = dun.platform.openssl; }

version (linux)
{
    private extern (C) int accept4(int, void*, void*, int) nothrow @nogc;
}

private enum {
    HTTP_STATUS_OK    = 200,
    HTTP_DEFAULT_PORT = 80,
    HTTP_LISTEN_BACKLOG = 1024,
    HTTP_MAX_HEADER_NAME = 128,
    HTTP_MAX_HEADER_SIZE = 16_384,
    IO_POLL_BATCH_SIZE = 256,
    HTTP_DEFAULT_TIMEOUT_MS     = 120_000,
    HTTP_KEEPALIVE_TIMEOUT_MS   = 5_000,
    HTTP_REQUEST_TIMEOUT_MS     = 60_000,
    HTTP_HEADERS_TIMEOUT_MS     = 300_000,
    HTTP_CONNECT_TIMEOUT_MS     = 2_000,
    HTTP_MAX_HEADERS_COUNT      = 2_000,
    HTTP_MAX_CONNECTIONS         = 10_000,
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

    // http.get/request/METHODS/STATUS_CODES via JS (uses fetch internally)
    auto httpExtResult = engine.eval(httpExtensionSource(), "<http-ext>");
    if (!httpExtResult.isError)
    {
        auto reqFn = engine.getProperty(httpExtResult.value, "request");
        auto getFn = engine.getProperty(httpExtResult.value, "get");
        auto methods = engine.getProperty(httpExtResult.value, "METHODS");
        auto codes = engine.getProperty(httpExtResult.value, "STATUS_CODES");
        auto agent = engine.getProperty(httpExtResult.value, "Agent");
        auto globalAgent = engine.getProperty(httpExtResult.value, "globalAgent");
        auto incomingMsg = engine.getProperty(httpExtResult.value, "IncomingMessage");
        auto serverRes = engine.getProperty(httpExtResult.value, "ServerResponse");
        auto clientReq = engine.getProperty(httpExtResult.value, "ClientRequest");
        engine.setProperty(obj, "request", reqFn);
        engine.setProperty(obj, "get", getFn);
        engine.setProperty(obj, "METHODS", methods);
        engine.setProperty(obj, "STATUS_CODES", codes);
        engine.setProperty(obj, "Agent", agent);
        engine.setProperty(obj, "globalAgent", globalAgent);
        engine.setProperty(obj, "IncomingMessage", incomingMsg);
        engine.setProperty(obj, "ServerResponse", serverRes);
        engine.setProperty(obj, "ClientRequest", clientReq);
    }
    engine.freeValue(httpExtResult.value);

    // http.Server (alias for createServer constructor)
    engine.setProperty(obj, "Server", engine.newFunction(&jsHttpCreateServer, "Server", 1));

    // http.maxHeaderSize
    engine.setProperty(obj, "maxHeaderSize", engine.newInt(HTTP_MAX_HEADER_SIZE));

    // http.validateHeaderName / http.validateHeaderValue via JS
    auto valResult = engine.eval(httpValidationSource(), "<http-validate>");
    if (!valResult.isError)
    {
        auto vhn = engine.getProperty(valResult.value, "validateHeaderName");
        auto vhv = engine.getProperty(valResult.value, "validateHeaderValue");
        engine.setProperty(obj, "validateHeaderName", vhn);
        engine.setProperty(obj, "validateHeaderValue", vhv);
    }
    engine.freeValue(valResult.value);

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
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:http", &httpModuleInit);
        if (m is null) return;
        foreach (name; ["createServer", "request", "get", "METHODS",
                        "STATUS_CODES", "Agent", "globalAgent",
                        "IncomingMessage", "ServerResponse", "ClientRequest",
                        "maxHeaderSize", "validateHeaderName", "validateHeaderValue"])
            JS_AddModuleExport(ctx, m, name.ptr);

            JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int httpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in httpModuleInit");
        assert(m !is null, "Null JSModuleDef in httpModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto httpObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_http__");
        foreach (name; ["createServer", "request", "get", "METHODS",
                        "STATUS_CODES", "Agent", "globalAgent",
                        "IncomingMessage", "ServerResponse", "ClientRequest",
                        "maxHeaderSize", "validateHeaderName", "validateHeaderValue"])
        {
            auto fn = JS_GetPropertyStr(ctx, httpObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", httpObj);
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
__gshared JSHandle _httpResGetHeader, _httpResGetHeaders, _httpResHasHeader, _httpResRemoveHeader;
__gshared JSHandle _httpResOn, _httpResEmit;
__gshared JSHandle _httpSrvAddress;
__gshared JSHandle _httpJsDispatchFn;
__gshared JSHandle _httpCachedUndef;
__gshared bool _httpFnsCached = false;

void ensureHttpFnsCached(IJSEngine engine) @trusted
{
    if (_httpFnsCached) return;
    _httpSrvListen = engine.newFunction(&jsHttpServerListen, "listen", 1);
    _httpSrvClose = engine.newFunction(&jsHttpServerClose, "close", 0);
    _httpSrvOn = engine.newFunction(&jsHttpServerOn, "on", 2);
    _httpSrvAddress = engine.newFunction(&jsHttpServerAddress, "address", 0);
    _httpReqOn = engine.newFunction(&jsReqOn, "on", 2);
    _httpResSetHeader = engine.newFunction(&jsResSetHeader, "setHeader", 2);
    _httpResWriteHead = engine.newFunction(&jsResWriteHead, "writeHead", 1);
    _httpResWrite = engine.newFunction(&jsResWrite, "write", 1);
    _httpResEnd = engine.newFunction(&jsResEnd, "end", 0);
    _httpResGetHeader = engine.newFunction(&jsResGetHeader, "getHeader", 1);
    _httpResGetHeaders = engine.newFunction(&jsResGetHeaders, "getHeaders", 0);
    _httpResHasHeader = engine.newFunction(&jsResHasHeader, "hasHeader", 1);
    _httpResRemoveHeader = engine.newFunction(&jsResRemoveHeader, "removeHeader", 1);

    // res.on() / res.emit() — JS-level EventEmitter using _events map on the object
    auto resOnResult = engine.eval(
        "(function(event, fn) {" ~
        "  if (!this._events) this._events = {};" ~
        "  if (!this._events[event]) this._events[event] = [];" ~
        "  this._events[event].push(fn);" ~
        "  return this;" ~
        "})", "<res-on>");
    if (!resOnResult.isError)
        _httpResOn = engine.dupValue(resOnResult.value);
    engine.freeValue(resOnResult.value);

    auto resEmitResult = engine.eval(
        "(function(event) {" ~
        "  if (!this._events || !this._events[event]) return false;" ~
        "  var args = Array.prototype.slice.call(arguments, 1);" ~
        "  var listeners = this._events[event].slice();" ~
        "  for (var i = 0; i < listeners.length; i++) listeners[i].apply(this, args);" ~
        "  return true;" ~
        "})", "<res-emit>");
    if (!resEmitResult.isError)
        _httpResEmit = engine.dupValue(resEmitResult.value);
    engine.freeValue(resEmitResult.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__httpSetHeader", engine.dupValue(_httpResSetHeader));
    engine.setProperty(global, "__httpWriteHead", engine.dupValue(_httpResWriteHead));
    engine.setProperty(global, "__httpWrite", engine.dupValue(_httpResWrite));
    engine.setProperty(global, "__httpEnd", engine.dupValue(_httpResEnd));
    engine.setProperty(global, "__httpReqOn", engine.dupValue(_httpReqOn));
    engine.setProperty(global, "__httpGetHeader", engine.dupValue(_httpResGetHeader));
    engine.setProperty(global, "__httpGetHeaders", engine.dupValue(_httpResGetHeaders));
    engine.setProperty(global, "__httpHasHeader", engine.dupValue(_httpResHasHeader));
    engine.setProperty(global, "__httpRemoveHeader", engine.dupValue(_httpResRemoveHeader));

    // Native function to lazily retrieve headers for a connection
    auto getHdrsFn = engine.newFunction(&jsGetConnHeaders, "__httpGetHeaders", 1);
    engine.setProperty(global, "__httpGetHeaders", getHdrsFn);

    // Store res.on/emit on globalThis for use in dispatch function
    engine.setProperty(global, "__httpResOn", engine.dupValue(_httpResOn));
    engine.setProperty(global, "__httpResEmit", engine.dupValue(_httpResEmit));
    engine.freeValue(global);

    import dun.engine.iface : JSResult;
    auto dispatchResult = engine.eval(
        "(function(cb, method, url, cid) {" ~
        "  var _gh = globalThis.__httpGetHeaders;" ~
        "  var _ron = globalThis.__httpResOn;" ~
        "  var _rem = globalThis.__httpResEmit;" ~
        "  var sock = { remoteAddress: '127.0.0.1', remotePort: 0, localAddress: '0.0.0.0'," ~
        "    localPort: 0, writable: true, readable: true," ~
        "    destroy: function(){this.writable=false;return this;}," ~
        "    write: function(){return true;}, end: function(){} };" ~
        "  var req = { method: method, url: url, httpVersion: 'HTTP/1.1', __cid: cid," ~
        "    complete: false, readable: true, aborted: false, rawHeaders: []," ~
        "    get headers() { var h = _gh(cid); Object.defineProperty(this, 'headers', {value: h}); return h; }," ~
        "    on: globalThis.__httpReqOn, once: globalThis.__httpReqOn," ~
        "    emit: _rem, _events: {}," ~
        "    connection: sock, socket: sock," ~
        "    resume: function(){return this;}, pause: function(){return this;}," ~
        "    destroy: function(){this.readable=false;return this;}," ~
        "    pipe: function(d){this.on('data',function(c){d.write(c)});this.on('end',function(){d.end()});return d;}" ~
        "  };" ~
        "  var res = { __cid: cid, statusCode: 200, statusMessage: 'OK', headersSent: false," ~
        "    finished: false, writableEnded: false, writableFinished: false," ~
        "    _events: {}, connection: sock, socket: sock," ~
        "    _headerValues: {}," ~
        "    setHeader: globalThis.__httpSetHeader," ~
        "    getHeader: globalThis.__httpGetHeader," ~
        "    getHeaders: globalThis.__httpGetHeaders," ~
        "    hasHeader: globalThis.__httpHasHeader," ~
        "    removeHeader: globalThis.__httpRemoveHeader," ~
        "    writeHead: globalThis.__httpWriteHead," ~
        "    write: globalThis.__httpWrite," ~
        "    end: globalThis.__httpEnd," ~
        "    on: _ron, once: _ron, emit: _rem," ~
        "    flushHeaders: function(){} };" ~
        "  try { cb(req, res); } catch(e) {" ~
        "    if (!res.headersSent) { try{res.writeHead(500);res.end('Internal Server Error');}catch(e2){} }" ~
        "    if (typeof process !== 'undefined' && process.emit) process.emit('uncaughtException', e);" ~
        "  }" ~
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
    version (Posix) { void* sslCtx; } // SSL_CTX* for TLS servers
}

enum INITIAL_BUF = 16 * 1024;
enum MAX_REQUEST_BODY = 16 * 1024 * 1024; // 16MB max request body

struct HttpConnState
{
    IJSEngine engine;
    int srvId;
    int fd = -1;
    bool closed;
    char[] buf;
    size_t bufLen;
    const(char)[] method;
    const(char)[] url;
    const(char)[] httpVersion;
    const(char)[][string] headers;
    size_t contentLength;
    size_t bodyStart;
    bool headersDone;
    int statusCode = HTTP_STATUS_OK;
    string[][string] respHeaders;
    bool headersSent;
    bool keepAlive;
    bool chunkedResponse;
    char[] respBuf;
    size_t respLen;
    version (Posix) { void* ssl; } // SSL* for TLS connections

    void ensureBufCapacity(size_t needed) nothrow @trusted {
        if (needed <= buf.length) return;
        size_t newCap = buf.length;
        while (newCap < needed) newCap = newCap * 2;
        if (newCap > MAX_REQUEST_BODY) newCap = MAX_REQUEST_BODY;
        try {
            auto newBuf = new char[](newCap);
            newBuf[0 .. bufLen] = buf[0 .. bufLen];
            buf = newBuf;
        } catch (Exception) {}
    }

    void ensureRespCapacity(size_t needed) nothrow @trusted {
        if (needed <= respBuf.length) return;
        size_t newCap = respBuf.length;
        while (newCap < needed) newCap = newCap * 2;
        try {
            auto newBuf = new char[](newCap);
            newBuf[0 .. respLen] = respBuf[0 .. respLen];
            respBuf = newBuf;
        } catch (Exception) {}
    }

    void initBuffers() nothrow @trusted {
        if (buf.length == 0) {
            try {
                buf = new char[](INITIAL_BUF);
                respBuf = new char[](INITIAL_BUF);
            } catch (Exception) {}
        }
    }

    void resetForKeepAlive() nothrow @trusted {
        bufLen = 0;
        method = null;
        url = null;
        httpVersion = null;
        try { headers = typeof(headers).init; } catch (Exception) {}
        contentLength = 0;
        bodyStart = 0;
        headersDone = false;
        statusCode = HTTP_STATUS_OK;
        try { respHeaders = typeof(respHeaders).init; } catch (Exception) {}
        headersSent = false;
        chunkedResponse = false;
        respLen = 0;
    }
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

void closeConnFd(HttpConnState* conn) nothrow @trusted
{
    version (Posix)
    {
        if (conn.ssl !is null)
        {
            auto sslp = cast(ssl.SSL*) conn.ssl;
            ssl.SSL_shutdown(sslp);
            ssl.SSL_free(sslp);
            conn.ssl = null;
        }
        if (conn.fd >= 0)
        {
            import core.sys.posix.unistd : close;
            close(conn.fd);
            conn.fd = -1;
        }
    }
}

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

// Return a connection slot to the free list and release large buffers
void freeConnSlot(int slot) nothrow @trusted
{
    _activeConnCount--;
    // Release connection buffers to free memory
    if (slot >= 0 && slot < cast(int) httpConns.length)
    {
        httpConns[slot].buf = null;
        httpConns[slot].respBuf = null;
        httpConns[slot].closed = true;
    }
    try { httpFreeSlots ~= slot; } catch (Throwable) {}
}

package JSHandle createServerWithTls(IJSEngine engine, JSHandle cb, bool hasCb,
    void* sslCtx = null) @trusted
{
    int id = nextHttpServerId++;
    try
    {
        HttpServerState srv;
        srv.engine = engine;
        if (hasCb) { srv.requestCb = cb; srv.cbSet = true; }
        version (Posix) { srv.sslCtx = sslCtx; }
        httpServers ~= srv;
    }
    catch (Throwable)
    {
        if (hasCb) engine.freeValue(cb);
        return engine.throwTypeError("http.createServer: out of memory");
    }
    return makeHttpServerObj(engine, id);
}

JSHandle jsHttpCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

    return createServerWithTls(engine, cb, hasCb);
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
    engine.setProperty(obj, "once", engine.dupValue(_httpSrvOn));
    engine.setProperty(obj, "emit", engine.dupValue(_httpResEmit));
    engine.setProperty(obj, "address", engine.dupValue(_httpSrvAddress));
    engine.setProperty(obj, "listening", engine.newBool(false));
    engine.setProperty(obj, "_events", engine.newObject());
    engine.setProperty(obj, "maxConnections", engine.newInt(0));
    engine.setProperty(obj, "timeout", engine.newInt(HTTP_DEFAULT_TIMEOUT_MS));
    engine.setProperty(obj, "keepAliveTimeout", engine.newInt(HTTP_KEEPALIVE_TIMEOUT_MS));
    engine.setProperty(obj, "headersTimeout", engine.newInt(HTTP_REQUEST_TIMEOUT_MS));
    engine.setProperty(obj, "requestTimeout", engine.newInt(HTTP_HEADERS_TIMEOUT_MS));
    engine.setProperty(obj, "maxHeadersCount", engine.newInt(HTTP_MAX_HEADERS_COUNT));
    engine.setProperty(obj, "setTimeout", engine.newFunction(&jsHttpServerSetTimeout, "setTimeout", 2));
    return obj;
}

JSHandle jsHttpServerSetTimeout(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null);
    auto engine = state.engine;
    if (args.length >= 1 && engine.isNumber(args[0]))
        engine.setProperty(thisVal, "timeout", engine.dupValue(args[0]));
    return engine.dupValue(thisVal);
}

JSHandle jsHttpServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

        // Query actual port (needed when port=0 lets OS assign)
        if (port == 0)
        {
            sockaddr_in boundAddr;
            socklen_t addrLen = boundAddr.sizeof;
            if (getsockname(lfd, cast(sockaddr*)&boundAddr, &addrLen) == 0)
                port = ntohs(boundAddr.sin_port);
        }
        srv.port = cast(ushort) port;
        engine.setProperty(thisVal, "listening", engine.newBool(true));

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
        return engine.dupValue(thisVal);
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.throwTypeError("http server not supported on this platform");
    }
}

JSHandle jsHttpServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
            if (srv.sslCtx !is null)
            {
                ssl.SSL_CTX_free(cast(ssl.SSL_CTX*) srv.sslCtx);
                srv.sslCtx = null;
            }
            srv.active = false;
            _activeServerCount--;
            engine.setProperty(thisVal, "listening", engine.newBool(false));

            // Close all active connections belonging to this server
            foreach (ci, ref conn; httpConns)
            {
                if (!conn.closed && conn.srvId == idVal)
                {
                    conn.closed = true;
                    version (linux) if (conn.fd >= 0) gHttpPoller.unwatch(conn.fd);
                    try { fdToConnId.remove(conn.fd); } catch (Exception) {}
                    closeConnFd(&conn);
                    freeConnSlot(cast(int) ci);
                }
            }

            // Emit 'close' event on the server object
            auto emitProp = engine.getProperty(thisVal, "emit");
            if (engine.isFunction(emitProp))
            {
                auto closeStr = engine.newString("close");
                JSHandle[1] emitArgs = [closeStr];
                auto emitRet = engine.callFunction(emitProp, thisVal, emitArgs[]);
                engine.freeValue(emitRet);
                engine.freeValue(closeStr);
            }
            engine.freeValue(emitProp);

            // Call callback if provided
            if (args.length >= 1 && engine.isFunction(args[0]))
            {
                auto undef = engine.newUndefined();
                JSHandle[0] noArgs;
                auto cbRet = engine.callFunction(args[0], undef, noArgs[]);
                engine.freeValue(cbRet);
                engine.freeValue(undef);
            }
        }
        return engine.dupValue(thisVal);
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

JSHandle jsHttpServerAddress(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpServerAddress");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHttpServerAddress");
    auto engine = state.engine;

    auto idProp = engine.getProperty(thisVal, "__hid");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal >= 0 && idVal < cast(int) httpServers.length)
    {
        auto srv = &httpServers[idVal];
        if (srv.active && srv.listenFd >= 0)
        {
            auto obj = engine.newObject();
            engine.setProperty(obj, "address", engine.newString("::"));
            engine.setProperty(obj, "family", engine.newString("IPv6"));
            import std.conv : to;
            engine.setProperty(obj, "port", engine.newInt(cast(int) srv.port));
            return obj;
        }
    }
    return engine.newNull();
}

JSHandle jsHttpServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHttpServerOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHttpServerOn");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1])) return engine.dupValue(thisVal);

    auto idProp = engine.getProperty(thisVal, "__hid");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) httpServers.length) return engine.dupValue(thisVal);

    auto ev = engine.extractString(args[0]);
    if (ev == "request")
    {
        auto srv = &httpServers[idVal];
        if (srv.cbSet) engine.freeValue(srv.requestCb);
        srv.requestCb = engine.dupValue(args[1]);
        srv.cbSet = true;
    }

    // Store arbitrary event listeners on _events map for emit()
    auto eventsMap = engine.getProperty(thisVal, "_events");
    if (engine.isUndefined(eventsMap) || engine.isNull(eventsMap))
    {
        engine.freeValue(eventsMap);
        eventsMap = engine.newObject();
        engine.setProperty(thisVal, "_events", engine.dupValue(eventsMap));
    }
    auto listeners = engine.getProperty(eventsMap, ev);
    if (engine.isUndefined(listeners) || engine.isNull(listeners) || !engine.isArray(listeners))
    {
        engine.freeValue(listeners);
        listeners = engine.eval("([])", "<http-srv-on>").value;
    }
    // Push the callback
    auto lenProp = engine.getProperty(listeners, "length");
    int len = engine.extractInt(lenProp);
    engine.freeValue(lenProp);
    engine.setPropertyIndex(listeners, len, engine.dupValue(args[1]));
    engine.setProperty(eventsMap, ev, engine.dupValue(listeners));
    engine.freeValue(listeners);
    engine.freeValue(eventsMap);

    return engine.dupValue(thisVal);
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
    auto sock = engine.newObject();
    engine.setProperty(sock, "remoteAddress", engine.newString("127.0.0.1"));
    engine.setProperty(sock, "remotePort", engine.newInt(0));
    engine.setProperty(obj, "connection", engine.dupValue(sock));
    engine.setProperty(obj, "socket", sock);
    ensureHttpFnsCached(engine);
    engine.setProperty(obj, "on", engine.dupValue(_httpReqOn));
    return obj;
}

JSHandle jsGetConnHeaders(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

JSHandle jsReqOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsReqOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsReqOn");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1])) return engine.dupValue(thisVal);

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.dupValue(thisVal);

    auto ev = engine.extractString(args[0]);
    auto conn = &httpConns[connId];
    auto cb = engine.dupValue(args[1]);

    if (ev == "data")
    {
        size_t bodyLen = conn.bufLen > conn.bodyStart ? conn.bufLen - conn.bodyStart : 0;
        if (bodyLen > 0)
        {
            import dun.builtins.buffer : makeBufferObj;
            auto bodyData = cast(const(ubyte)[]) conn.buf[conn.bodyStart .. conn.bufLen];
            auto jsBody = makeBufferObj(engine, bodyData);
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
    return engine.dupValue(thisVal);
}

// Response object
JSHandle makeResObj(IJSEngine engine, int connId) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "__cid", engine.newInt(connId));
    engine.setProperty(obj, "statusCode", engine.newInt(200));
    engine.setProperty(obj, "statusMessage", engine.newString("OK"));
    engine.setProperty(obj, "headersSent", engine.newBool(false));
    engine.setProperty(obj, "finished", engine.newBool(false));
    engine.setProperty(obj, "writableEnded", engine.newBool(false));
    engine.setProperty(obj, "writableFinished", engine.newBool(false));
    engine.setProperty(obj, "socket", engine.newObject());
    ensureHttpFnsCached(engine);
    engine.setProperty(obj, "setHeader", engine.dupValue(_httpResSetHeader));
    engine.setProperty(obj, "getHeader", engine.dupValue(_httpResGetHeader));
    engine.setProperty(obj, "getHeaders", engine.dupValue(_httpResGetHeaders));
    engine.setProperty(obj, "hasHeader", engine.dupValue(_httpResHasHeader));
    engine.setProperty(obj, "removeHeader", engine.dupValue(_httpResRemoveHeader));
    engine.setProperty(obj, "writeHead", engine.dupValue(_httpResWriteHead));
    engine.setProperty(obj, "write", engine.dupValue(_httpResWrite));
    engine.setProperty(obj, "end", engine.dupValue(_httpResEnd));
    engine.setProperty(obj, "on", engine.dupValue(_httpResOn));
    engine.setProperty(obj, "once", engine.dupValue(_httpResOn));
    engine.setProperty(obj, "emit", engine.dupValue(_httpResEmit));
    return obj;
}

JSHandle jsResSetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
        if (engine.isArray(args[1]))
        {
            int len = engine.getArrayLength(args[1]);
            string[] vals;
            vals.reserve(len);
            foreach (i; 0 .. len)
            {
                auto elem = engine.getPropertyIndex(args[1], cast(uint) i);
                vals ~= sanitizeHeaderValue(engine.extractString(elem));
                engine.freeValue(elem);
            }
            httpConns[connId].respHeaders[name] = vals;
        }
        else
        {
            string val = sanitizeHeaderValue(engine.extractString(args[1]));
            httpConns[connId].respHeaders[name] = [val];
        }
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsResGetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResGetHeader");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newUndefined();
    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();
    try
    {
        string name = engine.extractString(args[0]);
        string[]* found;
        if (auto val = name in httpConns[connId].respHeaders)
            found = val;
        else
        {
            foreach (k, ref v; httpConns[connId].respHeaders)
            {
                if (toLowerSimple(k) == toLowerSimple(name))
                    { found = &v; break; }
            }
        }
        if (found !is null)
        {
            if ((*found).length == 1)
                return engine.newString((*found)[0]);
            auto arr = engine.eval("[]", "<arr>");
            foreach (i, s; *found)
            {
                engine.setPropertyIndex(arr.value, cast(uint) i, engine.newString(s));
            }
            return arr.value;
        }
    }
    catch (Exception) {}
    return engine.newUndefined();
}

JSHandle jsResGetHeaders(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResGetHeaders");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    auto obj = engine.newObject();
    if (connId < 0 || connId >= cast(int) httpConns.length) return obj;
    try
    {
        foreach (k, vals; httpConns[connId].respHeaders)
        {
            if (vals.length == 1)
                engine.setProperty(obj, k, engine.newString(vals[0]));
            else if (vals.length > 1)
            {
                auto arr = engine.eval("[]", "<arr>");
                foreach (i, s; vals)
                    engine.setPropertyIndex(arr.value, cast(uint) i, engine.newString(s));
                engine.setProperty(obj, k, arr.value);
            }
        }
    }
    catch (Exception) {}
    return obj;
}

JSHandle jsResHasHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResHasHeader");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newBool(false);
    try
    {
        string name = engine.extractString(args[0]);
        if (name in httpConns[connId].respHeaders)
            return engine.newBool(true);
        foreach (k; httpConns[connId].respHeaders.byKey())
            if (toLowerSimple(k) == toLowerSimple(name))
                return engine.newBool(true);
    }
    catch (Exception) {}
    return engine.newBool(false);
}

JSHandle jsResRemoveHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsResRemoveHeader");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newUndefined();
    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();
    try
    {
        string name = engine.extractString(args[0]);
        httpConns[connId].respHeaders.remove(name);
    }
    catch (Exception) {}
    return engine.newUndefined();
}

private string toLowerSimple(string s) @trusted pure nothrow
{
    if (s.length == 0) return s;
    enum STACK_BUF = 256;
    if (s.length <= STACK_BUF)
    {
        char[STACK_BUF] buf = void;
        buf[0 .. s.length] = s[];
        import dun.platform.simd : asciiToLowerBuf;
        asciiToLowerBuf(buf[0 .. s.length]);
        try { return buf[0 .. s.length].idup; } catch (Exception) { return s; }
    }
    char[] result;
    try { result.reserve(s.length); } catch (Exception) {}
    foreach (c; s)
        result ~= (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
    try { return result.idup; } catch (Exception) { return s; }
}

JSHandle jsResWriteHead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
    {
        conn.statusCode = engine.extractInt(args[0]);
        engine.setProperty(thisVal, "statusCode", engine.newInt(conn.statusCode));
        engine.setProperty(thisVal, "statusMessage", engine.newString(statusMessage(conn.statusCode)));
    }

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
                {
                    if (engine.isArray(val))
                    {
                        int alen = engine.getArrayLength(val);
                        string[] vals;
                        vals.reserve(alen);
                        foreach (ai; 0 .. alen)
                        {
                            auto elem = engine.getPropertyIndex(val, cast(uint) ai);
                            vals ~= sanitizeHeaderValue(engine.extractString(elem));
                            engine.freeValue(elem);
                        }
                        conn.respHeaders[name] = vals;
                    }
                    else
                        conn.respHeaders[name] = [sanitizeHeaderValue(engine.extractString(val))];
                }
                engine.freeValue(val);
            }
        }
        catch (Exception) {}
    }

    engine.setProperty(thisVal, "headersSent", engine.newBool(true));
    return engine.newUndefined();
}

void syncStatusCode(IJSEngine engine, JSHandle thisVal, HttpConnState* conn) @trusted
{
    auto scProp = engine.getProperty(thisVal, "statusCode");
    if (engine.isNumber(scProp))
        conn.statusCode = engine.extractInt(scProp);
    engine.freeValue(scProp);
}

void syncJsHeaders(IJSEngine engine, JSHandle thisVal, HttpConnState* conn) @trusted
{
    auto hdrsProp = engine.getProperty(thisVal, "_headers");
    if (engine.isUndefined(hdrsProp) || engine.isNull(hdrsProp))
    {
        engine.freeValue(hdrsProp);
        return;
    }
    try
    {
        static immutable names = [
            "content-type", "content-length", "connection", "cache-control",
            "location", "server", "set-cookie", "access-control-allow-origin",
            "transfer-encoding", "x-powered-by", "x-custom",
            "access-control-allow-methods", "access-control-allow-headers",
            "access-control-allow-credentials", "etag",
        ];
        foreach (name; names)
        {
            auto val = engine.getProperty(hdrsProp, name);
            if (!engine.isUndefined(val) && !engine.isNull(val))
                conn.respHeaders[name] = [sanitizeHeaderValue(engine.extractString(val))];
            engine.freeValue(val);
        }
    }
    catch (Exception) {}
    engine.freeValue(hdrsProp);
}

JSHandle jsResWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

    if (!conn.headersSent)
    {
        syncStatusCode(engine, thisVal, conn);
        syncJsHeaders(engine, thisVal, conn);
        if ("Content-Length" !in conn.respHeaders && "content-length" !in conn.respHeaders)
        {
            conn.respHeaders["Transfer-Encoding"] = ["chunked"];
            conn.chunkedResponse = true;
        }
        bufferStatusLine(conn);
        flushResponse(conn);
    }

    auto body_ = engine.extractString(args[0]);
    if (body_.length == 0) return engine.newBool(true);

    if (conn.chunkedResponse)
        sendChunk(conn, body_);
    else
        sendRaw(conn, body_);
    return engine.newBool(true);
}

JSHandle jsResEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

        // Sync JS-level statusCode and headers to conn
        if (!conn.headersSent)
        {
            syncStatusCode(engine, thisVal, conn);
            syncJsHeaders(engine, thisVal, conn);
        }

        // Detect body data and callback arguments
        // Node.js: res.end([data[, encoding]][, callback])
        string body_;
        JSHandle endCallback = engine.newUndefined();
        bool hasCallback = false;
        if (args.length >= 1)
        {
            if (engine.isFunction(args[0]))
            {
                endCallback = engine.dupValue(args[0]);
                hasCallback = true;
            }
            else
            {
                body_ = engine.extractString(args[0]);
                if (args.length >= 2 && engine.isFunction(args[$ - 1]))
                {
                    endCallback = engine.dupValue(args[$ - 1]);
                    hasCallback = true;
                }
            }
        }

        if (body_.length > 0)
        {
            if (conn.chunkedResponse)
            {
                if (!conn.headersSent) bufferStatusLine(conn);
                flushResponse(conn);
                sendChunk(conn, body_);
                sendRaw(conn, "0\r\n\r\n");
            }
            else
            {
                if (!conn.headersSent && "Content-Length" !in conn.respHeaders
                    && "content-length" !in conn.respHeaders)
                {
                    conn.respHeaders["Content-Length"] = [sizeToStr(body_.length)];
                }
                if (!conn.headersSent) bufferStatusLine(conn);
                bufferData(conn, body_);
                flushResponse(conn);
            }
        }
        else
        {
            if (conn.chunkedResponse)
            {
                if (!conn.headersSent) bufferStatusLine(conn);
                flushResponse(conn);
                sendRaw(conn, "0\r\n\r\n");
            }
            else
            {
                if (!conn.headersSent)
                {
                    if ("Content-Length" !in conn.respHeaders
                        && "content-length" !in conn.respHeaders)
                        conn.respHeaders["Content-Length"] = ["0"];
                    bufferStatusLine(conn);
                }
                flushResponse(conn);
            }
        }

        // Mark response as finished (Node.js compat)
        engine.setProperty(thisVal, "finished", engine.newBool(true));
        engine.setProperty(thisVal, "writableEnded", engine.newBool(true));
        engine.setProperty(thisVal, "writableFinished", engine.newBool(true));

        // Fire 'finish' event listeners
        auto emitProp = engine.getProperty(thisVal, "emit");
        if (engine.isFunction(emitProp))
        {
            auto finishStr = engine.newString("finish");
            JSHandle[1] emitArgs = [finishStr];
            auto emitRet = engine.callFunction(emitProp, thisVal, emitArgs[]);
            engine.freeValue(emitRet);
            engine.freeValue(finishStr);
        }
        engine.freeValue(emitProp);

        // Fire end callback if provided
        if (hasCallback)
        {
            auto undef = engine.newUndefined();
            JSHandle[0] noArgs;
            auto cbRet = engine.callFunction(endCallback, undef, noArgs[]);
            engine.freeValue(cbRet);
            engine.freeValue(undef);
            engine.freeValue(endCallback);
        }
        else
        {
            engine.freeValue(endCallback);
        }

        if (conn.keepAlive)
        {
            // Reset for next request on same connection
            size_t consumed = conn.bodyStart + conn.contentLength;
            if (consumed > conn.bufLen)
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
            conn.chunkedResponse = false;
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
            version (linux) if (conn.fd >= 0) gHttpPoller.unwatch(conn.fd);
            try { fdToConnId.remove(conn.fd); } catch (Exception) {}
            closeConnFd(conn);
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

// CTFE pre-computed status message text for a given HTTP status code
string statusMessage(int code) pure nothrow @safe @nogc
{
    switch (code)
    {
        case 100: return "Continue";
        case 101: return "Switching Protocols";
        case 200: return "OK";
        case 201: return "Created";
        case 202: return "Accepted";
        case 204: return "No Content";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 304: return "Not Modified";
        case 307: return "Temporary Redirect";
        case 308: return "Permanent Redirect";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 408: return "Request Timeout";
        case 409: return "Conflict";
        case 410: return "Gone";
        case 413: return "Payload Too Large";
        case 415: return "Unsupported Media Type";
        case 422: return "Unprocessable Entity";
        case 429: return "Too Many Requests";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        case 504: return "Gateway Timeout";
        default: return "OK";
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
            if (s.length == 0) return;
            conn.ensureRespCapacity(conn.respLen + s.length);
            size_t avail = conn.respBuf.length - conn.respLen;
            size_t n = s.length < avail ? s.length : avail;
            if (n > 0) {
                conn.respBuf[conn.respLen .. conn.respLen + n] = s[0 .. n];
                conn.respLen += n;
            }
        }

        bufAppend(statusLine(conn.statusCode));

        if ("Content-Type" !in conn.respHeaders)
            conn.respHeaders["Content-Type"] = ["text/plain"];
        if (!conn.keepAlive)
            conn.respHeaders["Connection"] = ["close"];
        else if ("Connection" !in conn.respHeaders)
            conn.respHeaders["Connection"] = ["keep-alive"];
        foreach (k, vals; conn.respHeaders)
        {
            foreach (v; vals)
            {
                bufAppend(k);
                bufAppend(": ");
                bufAppend(v);
                bufAppend("\r\n");
            }
        }
        bufAppend("\r\n");
    }
    catch (Exception) {}
}

void bufferData(HttpConnState* conn, const(char)[] data) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in bufferData");
    if (data.length == 0) return;
    conn.ensureRespCapacity(conn.respLen + data.length);
    size_t avail = conn.respBuf.length - conn.respLen;
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
        if (conn.ssl !is null)
        {
            auto sslp = cast(ssl.SSL*) conn.ssl;
            size_t sent = 0;
            while (sent < conn.respLen)
            {
                auto n = ssl.SSL_write(sslp, conn.respBuf.ptr + sent,
                    cast(int)(conn.respLen - sent));
                if (n <= 0) break;
                sent += n;
            }
        }
        else
        {
            import core.sys.posix.sys.socket : send, MSG_NOSIGNAL;
            size_t sent = 0;
            while (sent < conn.respLen)
            {
                auto n = send(conn.fd, conn.respBuf.ptr + sent, conn.respLen - sent, MSG_NOSIGNAL);
                if (n <= 0) break;
                sent += n;
            }
        }
        conn.respLen = 0;
    }
}

void sendError(HttpConnState* conn, int status, string text, int connSlot = -1) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in sendError");
    conn.initBuffers();
    bufferData(conn, statusLine(status));
    bufferData(conn, "Content-Length: 0\r\nConnection: close\r\n\r\n");
    flushResponse(conn);
    version (Posix)
    {
        conn.closed = true;
        version (linux) if (conn.fd >= 0) gHttpPoller.unwatch(conn.fd);
        try { fdToConnId.remove(conn.fd); } catch (Exception) {}
        closeConnFd(conn);
        if (connSlot >= 0) freeConnSlot(connSlot);
    }
}

void sendChunk(HttpConnState* conn, string data) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in sendChunk");
    if (data.length == 0) return;
    // Format: <hex-size>\r\n<data>\r\n
    char[18] hexBuf = void; // max 16 hex digits + \r\n
    int pos = 16;
    size_t n = data.length;
    if (n == 0) { hexBuf[--pos] = '0'; }
    else while (n > 0) { hexBuf[--pos] = "0123456789abcdef"[n & 0xf]; n >>= 4; }
    hexBuf[16] = '\r';
    hexBuf[17] = '\n';
    sendRaw(conn, cast(string) hexBuf[pos .. 18]);
    sendRaw(conn, data);
    sendRaw(conn, "\r\n");
}

void sendRaw(HttpConnState* conn, string data) nothrow @trusted
{
    assert(conn !is null, "Null HttpConnState in sendRaw");
    version (Posix)
    {
        if (conn.fd < 0 || data.length == 0) return;
        if (conn.ssl !is null)
        {
            auto sslp = cast(ssl.SSL*) conn.ssl;
            size_t sent = 0;
            while (sent < data.length)
            {
                auto n = ssl.SSL_write(sslp, data.ptr + sent, cast(int)(data.length - sent));
                if (n <= 0) break;
                sent += n;
            }
        }
        else
        {
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

            // Enforce max connection limit to prevent FD exhaustion
            if (_activeConnCount >= HTTP_MAX_CONNECTIONS)
            {
                import core.sys.posix.unistd : close;
                close(fd);
                break;
            }

            version (linux) {} else
            {
                int fl = fcntl(fd, F_GETFL, 0);
                fcntl(fd, F_SETFL, fl | O_NONBLOCK);
            }

            // TCP_NODELAY: disable Nagle's algorithm to prevent 40ms delayed-ACK latency
            enum TCP_NODELAY = 1;
            int one = 1;
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, one.sizeof);

            // TLS handshake for HTTPS servers
            void* connSsl = null;
            if (srv.sslCtx !is null)
            {
                auto sctx = cast(ssl.SSL_CTX*) srv.sslCtx;
                auto tlsConn = ssl.SSL_new(sctx);
                if (tlsConn is null)
                {
                    import core.sys.posix.unistd : close;
                    close(fd);
                    continue;
                }
                ssl.SSL_set_fd(tlsConn, fd);
                ssl.ERR_clear_error();
                int ret = ssl.SSL_accept(tlsConn);
                if (ret != 1)
                {
                    ssl.SSL_free(tlsConn);
                    import core.sys.posix.unistd : close;
                    close(fd);
                    continue;
                }
                connSsl = cast(void*) tlsConn;
            }

            int cid = allocConnSlot();
            try
            {
                HttpConnState c;
                c.engine = srv.engine;
                c.srvId = srvId;
                c.fd = fd;
                c.statusCode = 200;
                c.ssl = connSsl;
                c.initBuffers();
                if (cid < cast(int) httpConns.length)
                    httpConns[cid] = c;
                else
                    httpConns ~= c;
                fdToConnId[fd] = cid;
                _activeConnCount++;
            }
            catch (Throwable)
            {
                if (connSsl !is null)
                    ssl.SSL_free(cast(ssl.SSL*) connSsl);
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
        enum READ_CHUNK = 16 * 1024;
        while (true)
        {
            if (conn.bufLen >= MAX_REQUEST_BODY) break;
            conn.ensureBufCapacity(conn.bufLen + READ_CHUNK);
            size_t space = conn.buf.length - conn.bufLen;
            if (space == 0) break;

            long n;
            if (conn.ssl !is null)
            {
                auto sslp = cast(ssl.SSL*) conn.ssl;
                auto ret = ssl.SSL_read(sslp, conn.buf.ptr + conn.bufLen,
                    cast(int)(space < int.max ? space : int.max));
                if (ret > 0) { n = ret; }
                else
                {
                    auto err = ssl.SSL_get_error(sslp, ret);
                    if (err == ssl.SSL_ERROR_WANT_READ || err == ssl.SSL_ERROR_WANT_WRITE)
                        break;
                    n = ret <= 0 ? 0 : ret;
                }
            }
            else
            {
                n = read(conn.fd, conn.buf.ptr + conn.bufLen, space);
            }
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
            version (linux) if (conn.fd >= 0) gHttpPoller.unwatch(conn.fd);
            try { fdToConnId.remove(conn.fd); } catch (Exception) {}
            closeConnFd(conn);
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

    if (conn.contentLength > MAX_REQUEST_BODY)
    {
        sendError(conn, 413, "Payload Too Large", cid);
        return;
    }
    conn.ensureBufCapacity(conn.bodyStart + conn.contentLength);

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

string httpExtensionSource() pure @safe nothrow
{
    return `(function() {
  var STATUS_CODES = {
    100: 'Continue', 101: 'Switching Protocols', 102: 'Processing',
    200: 'OK', 201: 'Created', 202: 'Accepted', 203: 'Non-Authoritative Information',
    204: 'No Content', 205: 'Reset Content', 206: 'Partial Content',
    300: 'Multiple Choices', 301: 'Moved Permanently', 302: 'Found',
    303: 'See Other', 304: 'Not Modified', 307: 'Temporary Redirect',
    308: 'Permanent Redirect',
    400: 'Bad Request', 401: 'Unauthorized', 402: 'Payment Required',
    403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed',
    406: 'Not Acceptable', 407: 'Proxy Authentication Required',
    408: 'Request Timeout', 409: 'Conflict', 410: 'Gone',
    411: 'Length Required', 412: 'Precondition Failed',
    413: 'Payload Too Large', 414: 'URI Too Long',
    415: 'Unsupported Media Type', 416: 'Range Not Satisfiable',
    417: 'Expectation Failed', 418: "I'm a Teapot",
    422: 'Unprocessable Entity', 425: 'Too Early',
    426: 'Upgrade Required', 428: 'Precondition Required',
    429: 'Too Many Requests', 431: 'Request Header Fields Too Large',
    451: 'Unavailable For Legal Reasons',
    500: 'Internal Server Error', 501: 'Not Implemented',
    502: 'Bad Gateway', 503: 'Service Unavailable',
    504: 'Gateway Timeout', 505: 'HTTP Version Not Supported',
    507: 'Insufficient Storage', 511: 'Network Authentication Required'
  };

  var METHODS = [
    'ACL', 'BIND', 'CHECKOUT', 'CONNECT', 'COPY', 'DELETE', 'GET',
    'HEAD', 'LINK', 'LOCK', 'M-SEARCH', 'MERGE', 'MKACTIVITY',
    'MKCALENDAR', 'MKCOL', 'MOVE', 'NOTIFY', 'OPTIONS', 'PATCH',
    'POST', 'PROPFIND', 'PROPPATCH', 'PURGE', 'PUT', 'REBIND',
    'REPORT', 'SEARCH', 'SOURCE', 'SUBSCRIBE', 'TRACE', 'UNBIND',
    'UNLINK', 'UNLOCK', 'UNSUBSCRIBE'
  ];

  function Agent(options) {
    this.maxSockets = (options && options.maxSockets) || Infinity;
    this.maxFreeSockets = (options && options.maxFreeSockets) || 256;
    this.keepAlive = (options && options.keepAlive) || false;
    this.keepAliveMsecs = (options && options.keepAliveMsecs) || 1000;
    this.requests = {};
    this.sockets = {};
    this.freeSockets = {};
  }
  Agent.prototype.destroy = function() {
    this.requests = {};
    this.sockets = {};
    this.freeSockets = {};
  };
  Agent.prototype.getName = function(options) {
    var name = (options.host || 'localhost') + ':';
    name += options.port || 80;
    if (options.localAddress) name += ':' + options.localAddress;
    return name;
  };

  var globalAgent = new Agent();

  function IncomingMessage(statusCode, headers, body) {
    EventEmitter.call(this);
    this.statusCode = statusCode;
    this.statusMessage = STATUS_CODES[statusCode] || '';
    this.headers = headers || {};
    this.httpVersion = '1.1';
    this._body = body;
    this._consumed = false;
  }
  IncomingMessage.prototype = Object.create(EventEmitter.prototype);
  IncomingMessage.prototype.constructor = IncomingMessage;

  function ClientRequest(options, callback) {
    EventEmitter.call(this);
    this._options = options;
    this._callback = callback;
    this._body = '';
    this._ended = false;
    this._aborted = false;
    this.method = (options.method || 'GET').toUpperCase();
    this.path = options.path || options.pathname || '/';
    this.headers = options.headers || {};
    this.socket = null;
    this.finished = false;
  }
  ClientRequest.prototype = Object.create(EventEmitter.prototype);
  ClientRequest.prototype.constructor = ClientRequest;

  ClientRequest.prototype.write = function(chunk) {
    if (this._ended) return false;
    this._body += (typeof chunk === 'string') ? chunk : String(chunk);
    return true;
  };

  ClientRequest.prototype.end = function(data, encoding, callback) {
    if (typeof data === 'function') { callback = data; data = undefined; }
    if (typeof encoding === 'function') { callback = encoding; encoding = undefined; }
    if (data !== undefined && data !== null) this.write(data);
    this._ended = true;
    this.finished = true;
    var self = this;

    var protocol = self._options.protocol || 'http:';
    var hostname = self._options.hostname || self._options.host || 'localhost';
    var port = self._options.port || (protocol === 'https:' ? 443 : 80);
    var path = self.path;
    var url = protocol + '//' + hostname + ':' + port + path;

    var fetchOpts = { method: self.method, headers: self.headers };
    if (self._body && self.method !== 'GET' && self.method !== 'HEAD') {
      fetchOpts.body = self._body;
    }

    if (typeof fetch === 'function') {
      try {
        fetch(url, fetchOpts).then(function(resp) {
          return resp.text().then(function(body) {
            var respHeaders = {};
            if (resp.headers && typeof resp.headers.forEach === 'function') {
              resp.headers.forEach(function(v, k) { respHeaders[k] = v; });
            }
            var res = new IncomingMessage(resp.status, respHeaders, body);
            if (self._callback) self._callback(res);
            self.emit('response', res);
            if (body) {
              res.emit('data', body);
            }
            res.emit('end');
          });
        })['catch'](function(err) {
          self.emit('error', err);
        });
      } catch(e) {
        Promise.resolve().then(function() { self.emit('error', e); });
      }
    } else {
      Promise.resolve().then(function() {
        self.emit('error', new Error('fetch not available'));
      });
    }

    if (callback) this.once('response', callback);
    return this;
  };

  ClientRequest.prototype.abort = function() {
    this._aborted = true;
    this.emit('abort');
  };

  ClientRequest.prototype.destroy = function(err) {
    this._aborted = true;
    if (err) this.emit('error', err);
    this.emit('close');
    return this;
  };

  ClientRequest.prototype.setTimeout = function(ms, callback) {
    if (callback) this.once('timeout', callback);
    return this;
  };

  ClientRequest.prototype.setNoDelay = function() { return this; };
  ClientRequest.prototype.setSocketKeepAlive = function() { return this; };
  ClientRequest.prototype.flushHeaders = function() {};
  ClientRequest.prototype.getHeader = function(name) {
    return this.headers[name.toLowerCase()];
  };
  ClientRequest.prototype.setHeader = function(name, value) {
    this.headers[name.toLowerCase()] = value;
  };
  ClientRequest.prototype.removeHeader = function(name) {
    delete this.headers[name.toLowerCase()];
  };

  function ServerResponse() {
    EventEmitter.call(this);
    this.statusCode = 200;
    this.statusMessage = 'OK';
    this.headersSent = false;
    this.finished = false;
    this.writableEnded = false;
    this.writableFinished = false;
    this._headers = {};
  }
  ServerResponse.prototype = Object.create(EventEmitter.prototype);
  ServerResponse.prototype.constructor = ServerResponse;
  ServerResponse.prototype.setHeader = function(name, value) { this._headers[name.toLowerCase()] = value; };
  ServerResponse.prototype.getHeader = function(name) { return this._headers[name.toLowerCase()]; };
  ServerResponse.prototype.removeHeader = function(name) { delete this._headers[name.toLowerCase()]; };
  ServerResponse.prototype.writeHead = function(statusCode, statusMessage, headers) {
    this.statusCode = statusCode;
    if (typeof statusMessage === 'string') { this.statusMessage = statusMessage; }
    else if (statusMessage && typeof statusMessage === 'object') { headers = statusMessage; }
    if (headers) {
      if (Array.isArray(headers)) { for (var i = 0; i < headers.length; i += 2) this.setHeader(headers[i], headers[i+1]); }
      else { var k = Object.keys(headers); for (var j = 0; j < k.length; j++) this.setHeader(k[j], headers[k[j]]); }
    }
    return this;
  };
  ServerResponse.prototype.write = function() { return true; };
  ServerResponse.prototype.end = function() { this.finished = true; this.writableEnded = true; };

  function request(urlOrOptions, optionsOrCallback, callback) {
    var options;
    if (typeof urlOrOptions === 'string') {
      try {
        var parsed = new URL(urlOrOptions);
        options = {
          protocol: parsed.protocol,
          hostname: parsed.hostname,
          port: parsed.port,
          path: parsed.pathname + parsed.search
        };
      } catch(e) {
        options = { path: urlOrOptions };
      }
      if (typeof optionsOrCallback === 'function') {
        callback = optionsOrCallback;
      } else if (typeof optionsOrCallback === 'object' && optionsOrCallback !== null) {
        var keys = Object.keys(optionsOrCallback);
        for (var i = 0; i < keys.length; i++) options[keys[i]] = optionsOrCallback[keys[i]];
      }
    } else {
      options = urlOrOptions || {};
      callback = typeof optionsOrCallback === 'function' ? optionsOrCallback : callback;
    }
    return new ClientRequest(options, callback);
  }

  function get(urlOrOptions, optionsOrCallback, callback) {
    var req = request(urlOrOptions, optionsOrCallback, callback);
    req.end();
    return req;
  }

  return {
    request: request,
    get: get,
    METHODS: METHODS,
    STATUS_CODES: STATUS_CODES,
    Agent: Agent,
    globalAgent: globalAgent,
    IncomingMessage: IncomingMessage,
    ServerResponse: ServerResponse,
    ClientRequest: ClientRequest
  };
})();`;
}

string httpValidationSource() pure @safe nothrow
{
    return "(function() {" ~
        "var INVALID_HEADER_NAME = /[^\\t\\x20-\\x7e\\x80-\\xff]/;" ~
        "var INVALID_HEADER_VALUE = /[\\x00-\\x08\\x0a-\\x1f\\x7f]/;" ~
        "function validateHeaderName(name) {" ~
        "  if (typeof name !== 'string' || name.length === 0)" ~
        "    throw new TypeError('Header name must be a valid HTTP token [\"' + name + '\"]');" ~
        "  if (INVALID_HEADER_NAME.test(name))" ~
        "    throw new TypeError('Header name must be a valid HTTP token [\"' + name + '\"]');" ~
        "}" ~
        "function validateHeaderValue(name, value) {" ~
        "  if (value === undefined)" ~
        "    throw new TypeError('Invalid value \"undefined\" for header \"' + name + '\"');" ~
        "  var s = String(value);" ~
        "  if (INVALID_HEADER_VALUE.test(s))" ~
        "    throw new TypeError('Invalid character in header content [\"' + name + '\"]');" ~
        "}" ~
        "return { validateHeaderName: validateHeaderName, validateHeaderValue: validateHeaderValue };" ~
        "})()";
}
