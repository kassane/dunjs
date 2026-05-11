module dun.builtins.http;

// Basic HTTP/1.1 server (dun:http / node:http / require('http')).
// Uses the same raw POSIX + epoll pattern as net.d.  Supports:
//   http.createServer(callback)  → Server
//   server.listen(port, [host], [callback])
//   server.close()
//   req: { method, url, httpVersion, headers, on('data',cb), on('end',cb) }
//   res: { statusCode, setHeader(n,v), writeHead(code,[headers]),
//          write(data), end([data]) }

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind : jsArgToString, toJSValue;
import dun.loop.pending : pushPending;
import dun.loop.iopoller : IOPoller, IOEvent;
import std.string : toStringz;

// ---------------------------------------------------------------------------
// Module-level shared poller for HTTP connections
// ---------------------------------------------------------------------------

private IOPoller gHttpPoller;
private bool     gHttpPollerInited = false;

private void ensureHttpPoller() nothrow @trusted
{
    if (!gHttpPollerInited) { gHttpPoller.initialize(); gHttpPollerInited = true; }
}

// ---------------------------------------------------------------------------
// State registries
// ---------------------------------------------------------------------------

private struct HttpServerState
{
    JSContext* ctx;
    JSValue    requestCb;  // duped — function(req, res)
    int        listenFd;
    bool       active;
    ushort     port;
}

private enum MAX_BUF = 16 * 1024;  // 16 KB request buffer per connection

private struct HttpConnState
{
    JSContext* ctx;
    int        srvId;
    int        fd;
    bool       closed;
    // Raw receive buffer
    char[MAX_BUF] buf;
    size_t         bufLen;
    // Parsed request fields
    string method;
    string url;
    string httpVersion;
    string[string] headers;
    size_t  contentLength;
    size_t  bodyStart;   // offset in buf where body begins
    bool    headersDone;
    // JS response state
    int     statusCode;
    string[string] respHeaders;
    bool    headersSent;
}

private HttpServerState[] httpServers;
private HttpConnState[]   httpConns;
private int nextHttpServerId;
private int nextHttpConnId;

// ---------------------------------------------------------------------------
// Module registration
// ---------------------------------------------------------------------------

void registerHttpModule(JSContext* ctx) @trusted
{
    auto m = JS_NewCModule(ctx, "dun:http", &httpModuleInit);
    if (m is null) return;
    JS_AddModuleExport(ctx, m, "createServer");
    JS_AddModuleExport(ctx, m, "STATUS_CODES");

    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "createServer",
        JS_NewCFunction(ctx, &jsHttpCreateServer, "createServer", 1));
    JS_SetPropertyStr(ctx, obj, "STATUS_CODES",
        makeStatusCodes(ctx));
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__dun_cjs_http__", obj);
    JS_FreeValue(ctx, global);
}

private:

extern (C) int httpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
{
    JS_SetModuleExport(ctx, m, "createServer",
        JS_NewCFunction(ctx, &jsHttpCreateServer, "createServer", 1));
    JS_SetModuleExport(ctx, m, "STATUS_CODES", makeStatusCodes(ctx));
    return 0;
}

JSValue makeStatusCodes(JSContext* ctx) nothrow @trusted
{
    auto obj = JS_NewObject(ctx);
    static immutable string[2][] codes = [
        ["200", "OK"], ["201", "Created"], ["204", "No Content"],
        ["301", "Moved Permanently"], ["302", "Found"], ["304", "Not Modified"],
        ["400", "Bad Request"], ["401", "Unauthorized"], ["403", "Forbidden"],
        ["404", "Not Found"], ["405", "Method Not Allowed"],
        ["500", "Internal Server Error"], ["503", "Service Unavailable"],
    ];
    foreach (ref pair; codes)
        JS_SetPropertyStr(ctx, obj, pair[0].ptr,
            JS_NewStringLen(ctx, pair[1].ptr, pair[1].length));
    return obj;
}

// ---------------------------------------------------------------------------
// http.createServer([requestListener]) → Server
// ---------------------------------------------------------------------------
extern (C) JSValue jsHttpCreateServer(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    JSValue cb = JS_UNDEFINED();
    if (argc >= 1 && JS_IsFunction(ctx, argv[0]))
        cb = JS_DupValue(ctx, argv[0]);

    int id = nextHttpServerId++;
    try { httpServers ~= HttpServerState(ctx, cb, -1, false, 0); }
    catch (Throwable)
    {
        JS_FreeValue(ctx, cb);
        return JS_ThrowTypeError(ctx, "http.createServer: out of memory");
    }
    return makeHttpServerObj(ctx, id);
}

// ---------------------------------------------------------------------------
// Server object factory
// ---------------------------------------------------------------------------
JSValue makeHttpServerObj(JSContext* ctx, int id) nothrow @trusted
{
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "__hid", JS_NewInt32(ctx, id));
    JS_SetPropertyStr(ctx, obj, "listen",
        JS_NewCFunction(ctx, &jsHttpServerListen, "listen", 1));
    JS_SetPropertyStr(ctx, obj, "close",
        JS_NewCFunction(ctx, &jsHttpServerClose, "close", 0));
    JS_SetPropertyStr(ctx, obj, "on",
        JS_NewCFunction(ctx, &jsHttpServerOn, "on", 2));
    return obj;
}

// ---------------------------------------------------------------------------
// server.listen(port, [host], [callback])
// ---------------------------------------------------------------------------
extern (C) JSValue jsHttpServerListen(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    import core.stdc.string : memset;

    int idVal;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__hid");
      JS_ToInt32(ctx, &idVal, p); JS_FreeValue(ctx, p); }
    if (idVal < 0 || idVal >= cast(int) httpServers.length)
        return JS_ThrowTypeError(ctx, "server.listen: invalid server");

    auto srv = &httpServers[idVal];

    int port = 80;
    JSValue listenCb = JS_UNDEFINED();
    if (argc >= 1) { int v; JS_ToInt32(ctx, &v, argv[0]); port = v; }
    if (argc >= 2 && JS_IsFunction(ctx, argv[1]))
        listenCb = JS_DupValue(ctx, argv[1]);
    else if (argc >= 3 && JS_IsFunction(ctx, argv[2]))
        listenCb = JS_DupValue(ctx, argv[2]);

    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0) { JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "http server: socket() failed"); }

    int one = 1;
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);

    int fl = fcntl(lfd, F_GETFL, 0);
    fcntl(lfd, F_SETFL, fl | O_NONBLOCK);

    sockaddr_in addr;
    memset(&addr, 0, addr.sizeof);
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(cast(ushort) port);
    addr.sin_addr.s_addr = 0;

    if (bind(lfd, cast(sockaddr*)&addr, addr.sizeof) < 0)
    {
        import core.sys.posix.unistd : close;
        close(lfd); JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "http server: bind() failed");
    }
    if (listen(lfd, 128) < 0)
    {
        import core.sys.posix.unistd : close;
        close(lfd); JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "http server: listen() failed");
    }

    srv.listenFd = lfd;
    srv.active   = true;
    srv.port     = cast(ushort) port;

    ensureHttpPoller();
    gHttpPoller.watch(lfd, true, false);

    if (!JS_IsUndefined(listenCb))
    {
        JSValue[0] none;
        pushPending(ctx, listenCb, none[]);
        JS_FreeValue(ctx, listenCb);
    }
    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// server.close()
// ---------------------------------------------------------------------------
extern (C) JSValue jsHttpServerClose(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.unistd : close;
    int idVal;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__hid");
      JS_ToInt32(ctx, &idVal, p); JS_FreeValue(ctx, p); }
    if (idVal >= 0 && idVal < cast(int) httpServers.length)
    {
        auto srv = &httpServers[idVal];
        if (srv.listenFd >= 0)
        {
            gHttpPoller.unwatch(srv.listenFd);
            close(srv.listenFd);
            srv.listenFd = -1;
        }
        srv.active = false;
    }
    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// server.on('request', handler) — alias for setting requestCb
// ---------------------------------------------------------------------------
extern (C) JSValue jsHttpServerOn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2) return JS_DupValue(ctx, this_val);
    int idVal;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__hid");
      JS_ToInt32(ctx, &idVal, p); JS_FreeValue(ctx, p); }
    if (idVal < 0 || idVal >= cast(int) httpServers.length)
        return JS_DupValue(ctx, this_val);

    string ev;
    try { ev = jsArgToString(ctx, argv[0]); } catch (Exception) {}
    if ((ev == "request") && JS_IsFunction(ctx, argv[1]))
    {
        auto srv = &httpServers[idVal];
        if (!JS_IsUndefined(srv.requestCb)) JS_FreeValue(ctx, srv.requestCb);
        srv.requestCb = JS_DupValue(ctx, argv[1]);
    }
    return JS_DupValue(ctx, this_val);
}

// ---------------------------------------------------------------------------
// Request object factory
// ---------------------------------------------------------------------------
JSValue makeReqObj(JSContext* ctx, int connId) nothrow @trusted
{
    auto conn = &httpConns[connId];
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "__cid", JS_NewInt32(ctx, connId));
    JS_SetPropertyStr(ctx, obj, "method",
        JS_NewStringLen(ctx, conn.method.ptr, conn.method.length));
    JS_SetPropertyStr(ctx, obj, "url",
        JS_NewStringLen(ctx, conn.url.ptr, conn.url.length));
    JS_SetPropertyStr(ctx, obj, "httpVersion",
        JS_NewStringLen(ctx, conn.httpVersion.ptr, conn.httpVersion.length));

    // headers object
    auto hdrs = JS_NewObject(ctx);
    foreach (k, v; conn.headers)
        JS_SetPropertyStr(ctx, hdrs, k.toStringz,
            JS_NewStringLen(ctx, v.ptr, v.length));
    JS_SetPropertyStr(ctx, obj, "headers", hdrs);

    // on() stub for req.on('data'/'end') — body is already buffered
    JS_SetPropertyStr(ctx, obj, "on",
        JS_NewCFunction(ctx, &jsReqOn, "on", 2));
    return obj;
}

extern (C) JSValue jsReqOn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    // For simplicity, we fire 'data' and 'end' immediately on the next tick
    // since the request body is already fully buffered.
    if (argc < 2 || !JS_IsFunction(ctx, argv[1]))
        return JS_DupValue(ctx, this_val);

    int connId;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__cid");
      JS_ToInt32(ctx, &connId, p); JS_FreeValue(ctx, p); }
    if (connId < 0 || connId >= cast(int) httpConns.length)
        return JS_DupValue(ctx, this_val);

    string ev;
    try { ev = jsArgToString(ctx, argv[0]); } catch (Exception) {}

    auto conn = &httpConns[connId];
    auto cb = JS_DupValue(ctx, argv[1]);

    if (ev == "data")
    {
        // Fire with body string if there is one
        size_t bodyLen = conn.bufLen > conn.bodyStart
            ? conn.bufLen - conn.bodyStart : 0;
        if (bodyLen > 0)
        {
            auto jsBody = JS_NewStringLen(ctx,
                conn.buf.ptr + conn.bodyStart, bodyLen);
            JSValue[1] args = [jsBody];
            pushPending(ctx, cb, args[]);
            JS_FreeValue(ctx, jsBody);
        }
        JS_FreeValue(ctx, cb);
    }
    else if (ev == "end")
    {
        JSValue[0] none;
        pushPending(ctx, cb, none[]);
        JS_FreeValue(ctx, cb);
    }
    else
    {
        JS_FreeValue(ctx, cb);
    }
    return JS_DupValue(ctx, this_val);
}

// ---------------------------------------------------------------------------
// Response object factory
// ---------------------------------------------------------------------------
JSValue makeResObj(JSContext* ctx, int connId) nothrow @trusted
{
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "__cid",   JS_NewInt32(ctx, connId));
    JS_SetPropertyStr(ctx, obj, "statusCode", JS_NewInt32(ctx, 200));
    JS_SetPropertyStr(ctx, obj, "setHeader",
        JS_NewCFunction(ctx, &jsResSetHeader, "setHeader", 2));
    JS_SetPropertyStr(ctx, obj, "writeHead",
        JS_NewCFunction(ctx, &jsResWriteHead, "writeHead", 1));
    JS_SetPropertyStr(ctx, obj, "write",
        JS_NewCFunction(ctx, &jsResWrite, "write", 1));
    JS_SetPropertyStr(ctx, obj, "end",
        JS_NewCFunction(ctx, &jsResEnd, "end", 0));
    return obj;
}

extern (C) JSValue jsResSetHeader(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2) return JS_UNDEFINED();
    int connId;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__cid");
      JS_ToInt32(ctx, &connId, p); JS_FreeValue(ctx, p); }
    if (connId < 0 || connId >= cast(int) httpConns.length) return JS_UNDEFINED();
    try
    {
        string name = jsArgToString(ctx, argv[0]);
        string val  = jsArgToString(ctx, argv[1]);
        httpConns[connId].respHeaders[name] = val;
    }
    catch (Exception) {}
    return JS_UNDEFINED();
}

extern (C) JSValue jsResWriteHead(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    int connId;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__cid");
      JS_ToInt32(ctx, &connId, p); JS_FreeValue(ctx, p); }
    if (connId < 0 || connId >= cast(int) httpConns.length) return JS_UNDEFINED();

    auto conn = &httpConns[connId];
    if (argc >= 1) { int sc; JS_ToInt32(ctx, &sc, argv[0]); conn.statusCode = sc; }

    sendStatusLine(conn);
    return JS_UNDEFINED();
}

extern (C) JSValue jsResWrite(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1) return JS_NewBool(ctx, 0);
    int connId;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__cid");
      JS_ToInt32(ctx, &connId, p); JS_FreeValue(ctx, p); }
    if (connId < 0 || connId >= cast(int) httpConns.length) return JS_NewBool(ctx, 0);

    auto conn = &httpConns[connId];
    if (conn.closed || conn.fd < 0) return JS_NewBool(ctx, 0);

    if (!conn.headersSent) sendStatusLine(conn);

    string body;
    try { body = jsArgToString(ctx, argv[0]); } catch (Exception) {}
    sendRaw(conn, body);
    return JS_NewBool(ctx, 1);
}

extern (C) JSValue jsResEnd(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.unistd : close;

    int connId;
    { auto p = JS_GetPropertyStr(ctx, this_val, "__cid");
      JS_ToInt32(ctx, &connId, p); JS_FreeValue(ctx, p); }
    if (connId < 0 || connId >= cast(int) httpConns.length) return JS_UNDEFINED();

    auto conn = &httpConns[connId];
    if (conn.closed) return JS_UNDEFINED();

    if (!conn.headersSent) sendStatusLine(conn);

    if (argc >= 1)
    {
        string body;
        try { body = jsArgToString(ctx, argv[0]); } catch (Exception) {}
        sendRaw(conn, body);
    }

    conn.closed = true;
    if (conn.fd >= 0)
    {
        gHttpPoller.unwatch(conn.fd);
        close(conn.fd);
        conn.fd = -1;
    }
    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// Internal HTTP response helpers
// ---------------------------------------------------------------------------
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
        default:  statusText = "Unknown"; break;
    }

    try
    {
        import std.conv : to;
        string line = "HTTP/1.1 " ~ conn.statusCode.to!string ~ " " ~ statusText ~ "\r\n";
        // Default headers
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

// ---------------------------------------------------------------------------
// I/O polling — called by eventloop.d each tick
// ---------------------------------------------------------------------------
public void pollHttpIO() nothrow @trusted
{
    version (linux)
    {
        ensureHttpPoller();
        IOEvent[64] evBuf;
        auto events = gHttpPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            // Accept on listen sockets
            foreach (i, ref srv; httpServers)
                if (srv.active && srv.listenFd == ev.fd && ev.readable)
                    acceptHttpConnection(cast(int) i);
            // Read on connection sockets
            foreach (i, ref conn; httpConns)
                if (!conn.closed && conn.fd == ev.fd && ev.readable)
                    readHttpData(cast(int) i);
        }
    }
}

public bool hasActiveHttpIO() @safe nothrow
{
    foreach (ref s; httpServers) if (s.active) return true;
    foreach (ref c; httpConns)   if (!c.closed) return true;
    return false;
}

// ---------------------------------------------------------------------------
// Accept + buffer + parse HTTP request
// ---------------------------------------------------------------------------
void acceptHttpConnection(int srvId) nothrow @trusted
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
            c.ctx   = srv.ctx;
            c.srvId = srvId;
            c.fd    = fd;
            c.statusCode = 200;
            httpConns ~= c;
        }
        catch (Throwable)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            continue;
        }
        gHttpPoller.watch(fd, true, false);
    }
}

void readHttpData(int cid) nothrow @trusted
{
    import core.sys.posix.unistd : read;
    import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

    if (cid < 0 || cid >= cast(int) httpConns.length) return;
    auto conn = &httpConns[cid];
    if (conn.closed || conn.fd < 0) return;

    // Read into buffer
    while (conn.bufLen < MAX_BUF)
    {
        auto n = read(conn.fd, conn.buf.ptr + conn.bufLen, MAX_BUF - conn.bufLen);
        if (n <= 0) break;
        conn.bufLen += n;
    }

    if (!conn.headersDone)
        tryParseHeaders(conn, cid);
}

void tryParseHeaders(HttpConnState* conn, int cid) nothrow @trusted
{
    // Look for \r\n\r\n
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
    conn.bodyStart   = sepPos + 4;

    // Parse header section
    auto headerText = conn.buf[0 .. sepPos].idup;
    parseRequestHeaders(conn, headerText);

    // Check Content-Length
    if (auto cl = "content-length" in conn.headers)
    {
        import std.conv : to;
        try { conn.contentLength = (*cl).to!size_t; } catch (Exception) {}
    }

    // We have a complete request if body is fully buffered
    bool bodyComplete = conn.bufLen >= conn.bodyStart + conn.contentLength;
    if (!bodyComplete) return; // wait for more data

    // Fire the JS request callback
    auto srv = &httpServers[conn.srvId];
    if (!JS_IsUndefined(srv.requestCb))
    {
        auto reqObj = makeReqObj(conn.ctx, cid);
        auto resObj = makeResObj(conn.ctx, cid);
        JSValue[2] args = [reqObj, resObj];
        pushPending(conn.ctx, srv.requestCb, args[]);
        JS_FreeValue(conn.ctx, reqObj);
        JS_FreeValue(conn.ctx, resObj);
    }
}

void parseRequestHeaders(HttpConnState* conn, const(char)[] text) nothrow @trusted
{
    import std.algorithm : splitter;
    import std.string : toLower, strip;

    try
    {
        size_t lineStart = 0;
        int lineNo = 0;
        for (size_t i = 0; i <= text.length; i++)
        {
            if (i == text.length || (text[i] == '\n'))
            {
                size_t end = i;
                if (end > lineStart && text[end-1] == '\r') end--;
                auto line = cast(string) text[lineStart .. end].idup;
                lineStart = i + 1;

                if (lineNo == 0)
                {
                    // Request line: METHOD URL HTTP/1.x
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
                    // Header: Name: Value
                    size_t col = 0;
                    while (col < line.length && line[col] != ':') col++;
                    if (col < line.length)
                    {
                        string name = line[0 .. col].toLower;
                        string val  = line[col + 1 .. $].strip;
                        conn.headers[name] = val;
                    }
                }
                lineNo++;
            }
        }
    }
    catch (Exception) {}
}
