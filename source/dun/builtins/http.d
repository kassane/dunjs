module dun.builtins.http;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.loop.agnostic_pending : pushAgnosticPending;

void registerHttpModule(IJSEngine engine) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "createServer", engine.newFunction(&jsHttpCreateServer, "createServer", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_http__", obj);

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
    string method;
    string url;
    string httpVersion;
    string[string] headers;
    size_t contentLength;
    size_t bodyStart;
    bool headersDone;
    int statusCode = 200;
    string[string] respHeaders;
    bool headersSent;
}

HttpServerState[] httpServers;
HttpConnState[] httpConns;
int nextHttpServerId;
int nextHttpConnId;

JSHandle jsHttpCreateServer(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
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
    auto obj = engine.newObject();
    engine.setProperty(obj, "__hid", engine.newInt(id));
    engine.setProperty(obj, "listen", engine.newFunction(&jsHttpServerListen, "listen", 1));
    engine.setProperty(obj, "close", engine.newFunction(&jsHttpServerClose, "close", 0));
    engine.setProperty(obj, "on", engine.newFunction(&jsHttpServerOn, "on", 2));
    return obj;
}

JSHandle jsHttpServerListen(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;

        auto state = cast(DunState*) ctx;
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__hid");
        int idVal = engine.extractInt(idProp);
        if (idVal < 0 || idVal >= cast(int) httpServers.length)
            return engine.throwTypeError("server.listen: invalid server");

        auto srv = &httpServers[idVal];

        int port = 80;
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
        if (listen(lfd, 128) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("http server: listen() failed");
        }

        srv.listenFd = lfd;
        srv.active = true;
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
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        auto state = cast(DunState*) ctx;
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__hid");
        int idVal = engine.extractInt(idProp);
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
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__hid");
    int idVal = engine.extractInt(idProp);
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
    engine.setProperty(obj, "on", engine.newFunction(&jsReqOn, "on", 2));
    return obj;
}

JSHandle jsReqOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1])) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
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
    engine.setProperty(obj, "setHeader", engine.newFunction(&jsResSetHeader, "setHeader", 2));
    engine.setProperty(obj, "writeHead", engine.newFunction(&jsResWriteHead, "writeHead", 1));
    engine.setProperty(obj, "write", engine.newFunction(&jsResWrite, "write", 1));
    engine.setProperty(obj, "end", engine.newFunction(&jsResEnd, "end", 0));
    return obj;
}

JSHandle jsResSetHeader(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2) return engine.newUndefined();

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

    try
    {
        string name = engine.extractString(args[0]);
        string val = engine.extractString(args[1]);
        httpConns[connId].respHeaders[name] = val;
    }
    catch (Exception) {}
    return engine.newUndefined();
}

JSHandle jsResWriteHead(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

    auto conn = &httpConns[connId];
    if (args.length >= 1 && engine.isNumber(args[0]))
        conn.statusCode = engine.extractInt(args[0]);

    sendStatusLine(conn);
    return engine.newUndefined();
}

JSHandle jsResWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);

    auto idProp = engine.getProperty(thisVal, "__cid");
    int connId = engine.extractInt(idProp);
    if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newBool(false);

    auto conn = &httpConns[connId];
    if (conn.closed || conn.fd < 0) return engine.newBool(false);

    if (!conn.headersSent) sendStatusLine(conn);
    auto body_ = engine.extractString(args[0]);
    sendRaw(conn, body_);
    return engine.newBool(true);
}

JSHandle jsResEnd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    version (Posix)
    {
        import core.sys.posix.unistd : close;

        auto state = cast(DunState*) ctx;
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__cid");
        int connId = engine.extractInt(idProp);
        if (connId < 0 || connId >= cast(int) httpConns.length) return engine.newUndefined();

        auto conn = &httpConns[connId];
        if (conn.closed) return engine.newUndefined();

        if (!conn.headersSent) sendStatusLine(conn);

        if (args.length >= 1)
        {
            auto body_ = engine.extractString(args[0]);
            sendRaw(conn, body_);
        }

        conn.closed = true;
        if (conn.fd >= 0)
        {
            version (linux) gHttpPoller.unwatch(conn.fd);
            close(conn.fd);
            conn.fd = -1;
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

void sendStatusLine(HttpConnState* conn) nothrow @trusted
{
    if (conn.headersSent || conn.fd < 0) return;
    conn.headersSent = true;

    string statusText = "OK";
    switch (conn.statusCode)
    {
        case 200: statusText = "OK"; break;
        case 201: statusText = "Created"; break;
        case 204: statusText = "No Content"; break;
        case 301: statusText = "Moved Permanently"; break;
        case 302: statusText = "Found"; break;
        case 304: statusText = "Not Modified"; break;
        case 400: statusText = "Bad Request"; break;
        case 401: statusText = "Unauthorized"; break;
        case 403: statusText = "Forbidden"; break;
        case 404: statusText = "Not Found"; break;
        case 500: statusText = "Internal Server Error"; break;
        default: statusText = "Unknown"; break;
    }

    try
    {
        import std.conv : to;
        string line = "HTTP/1.1 " ~ conn.statusCode.to!string ~ " " ~ statusText ~ "\r\n";
        if ("Content-Type" !in conn.respHeaders)
            conn.respHeaders["Content-Type"] = "text/plain";
        conn.respHeaders["Connection"] = "close";
        foreach (k, v; conn.respHeaders)
            line ~= k ~ ": " ~ v ~ "\r\n";
        line ~= "\r\n";
        sendRaw(conn, line);
    }
    catch (Exception) {}
}

void sendRaw(HttpConnState* conn, string data) nothrow @trusted
{
    version (Posix)
    {
        if (conn.fd < 0 || data.length == 0) return;
        import core.sys.posix.unistd : write;
        size_t sent = 0;
        while (sent < data.length)
        {
            auto n = write(conn.fd, data.ptr + sent, data.length - sent);
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
        IOEvent[64] evBuf;
        auto events = gHttpPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            foreach (i, ref srv; httpServers)
                if (srv.active && srv.listenFd == ev.fd && ev.readable)
                    acceptHttpConnection(cast(int) i);
            foreach (i, ref conn; httpConns)
                if (!conn.closed && conn.fd == ev.fd && ev.readable)
                    readHttpData(cast(int) i);
        }
    }
}

public bool hasActiveHttpIO() @safe nothrow
{
    foreach (ref s; httpServers) if (s.active) return true;
    foreach (ref c; httpConns) if (!c.closed) return true;
    return false;
}

void acceptHttpConnection(int srvId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : accept;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (srvId < 0 || srvId >= cast(int) httpServers.length) return;
        auto srv = &httpServers[srvId];

        while (true)
        {
            int fd = accept(srv.listenFd, null, null);
            if (fd < 0) { if (errno == EAGAIN || errno == EWOULDBLOCK) break; break; }

            int fl = fcntl(fd, F_GETFL, 0);
            fcntl(fd, F_SETFL, fl | O_NONBLOCK);

            int cid = nextHttpConnId++;
            try
            {
                HttpConnState c;
                c.engine = srv.engine;
                c.srvId = srvId;
                c.fd = fd;
                c.statusCode = 200;
                httpConns ~= c;
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
        import core.sys.posix.unistd : read;

        if (cid < 0 || cid >= cast(int) httpConns.length) return;
        auto conn = &httpConns[cid];
        if (conn.closed || conn.fd < 0) return;

        while (conn.bufLen < MAX_BUF)
        {
            auto n = read(conn.fd, conn.buf.ptr + conn.bufLen, MAX_BUF - conn.bufLen);
            if (n <= 0) break;
            conn.bufLen += n;
        }

        if (!conn.headersDone)
            tryParseHeaders(conn, cid);
    }
}

void tryParseHeaders(HttpConnState* conn, int cid) nothrow @trusted
{
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

    auto headerText = conn.buf[0 .. sepPos].idup;
    parseRequestHeaders(conn, headerText);

    if (auto cl = "content-length" in conn.headers)
    {
        import std.conv : to;
        try { conn.contentLength = (*cl).to!size_t; } catch (Exception) {}
    }

    bool bodyComplete = conn.bufLen >= conn.bodyStart + conn.contentLength;
    if (!bodyComplete) return;

    auto srv = &httpServers[conn.srvId];
    if (srv.cbSet)
    {
        try
        {
            auto reqObj = makeReqObj(srv.engine, cid);
            auto resObj = makeResObj(srv.engine, cid);
            JSHandle[2] callArgs = [reqObj, resObj];
            pushAgnosticPending(srv.engine, srv.requestCb, callArgs[]);
            srv.engine.freeValue(reqObj);
            srv.engine.freeValue(resObj);
        }
        catch (Throwable) {}
    }
}

void parseRequestHeaders(HttpConnState* conn, const(char)[] text) nothrow @trusted
{
    try
    {
        import std.string : toLower, strip;
        size_t lineStart = 0;
        int lineNo = 0;
        for (size_t i = 0; i <= text.length; i++)
        {
            if (i == text.length || text[i] == '\n')
            {
                size_t end = i;
                if (end > lineStart && text[end-1] == '\r') end--;
                auto line = cast(string) text[lineStart .. end].idup;
                lineStart = i + 1;

                if (lineNo == 0)
                {
                    size_t sp1 = 0;
                    while (sp1 < line.length && line[sp1] != ' ') sp1++;
                    conn.method = line[0 .. sp1];
                    size_t sp2 = sp1 + 1;
                    while (sp2 < line.length && line[sp2] != ' ') sp2++;
                    if (sp1 < line.length)
                        conn.url = line[sp1 + 1 .. sp2];
                    if (sp2 + 1 < line.length)
                        conn.httpVersion = line[sp2 + 1 .. $];
                }
                else
                {
                    size_t col = 0;
                    while (col < line.length && line[col] != ':') col++;
                    if (col < line.length)
                    {
                        string name = line[0 .. col].toLower;
                        string val = line[col + 1 .. $].strip;
                        conn.headers[name] = val;
                    }
                }
                lineNo++;
            }
        }
    }
    catch (Exception) {}
}
