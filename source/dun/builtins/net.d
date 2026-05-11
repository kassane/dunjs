module dun.builtins.net;

// TCP networking built-in (dun:net / node:net / require('net')).
// Uses eventcore for non-blocking I/O: connections and reads are callback-
// driven via the dun.loop.pending queue, which the event loop drains each
// tick after processEvents returns.

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind : jsArgToString, toJSValue;
import dun.loop.pending : pushPending;
import std.string : toStringz;

void registerNetModule(JSContext* ctx) @trusted
{
    auto m = JS_NewCModule(ctx, "dun:net", &netModuleInit);
    if (m is null) return;
    JS_AddModuleExport(ctx, m, "createServer");
    JS_AddModuleExport(ctx, m, "createConnection");
    JS_AddModuleExport(ctx, m, "connect");

    // CJS-compatible object for require('net') / require('dun:net')
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "createServer",
        JS_NewCFunction(ctx, &jsCreateServer, "createServer", 1));
    JS_SetPropertyStr(ctx, obj, "createConnection",
        JS_NewCFunction(ctx, &jsCreateConnection, "createConnection", 2));
    JS_SetPropertyStr(ctx, obj, "connect",
        JS_NewCFunction(ctx, &jsCreateConnection, "connect", 2));
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__dun_cjs_net__", obj);
    JS_FreeValue(ctx, global);
}

// Shared epoll poller for all net fds (Linux only).
version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    IOPoller gNetPoller;
    bool gNetPollerInited = false;

    void ensurePoller() nothrow @trusted
    {
        if (!gNetPollerInited) { gNetPoller.initialize(); gNetPollerInited = true; }
    }
}

private:

extern (C) int netModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
{
    JS_SetModuleExport(ctx, m, "createServer",
        JS_NewCFunction(ctx, &jsCreateServer, "createServer", 1));
    JS_SetModuleExport(ctx, m, "createConnection",
        JS_NewCFunction(ctx, &jsCreateConnection, "createConnection", 2));
    JS_SetModuleExport(ctx, m, "connect",
        JS_NewCFunction(ctx, &jsCreateConnection, "connect", 2));
    return 0;
}

// ---------------------------------------------------------------------------
// Server / Socket state registries (thread-local, single-threaded runtime)
// ---------------------------------------------------------------------------

struct SocketState
{
    JSContext* ctx;
    JSValue onData;    // duped, JS_UNDEFINED if unset
    JSValue onEnd;
    JSValue onClose;
    JSValue onError;
    int fd;            // raw POSIX fd (-1 = closed)
    bool closed;
    ubyte[4096] readBuf;
}

struct ServerState
{
    JSContext* ctx;
    JSValue onConnection; // duped, JS_UNDEFINED if unset
    int listenFd;         // raw POSIX fd (-1 = not listening)
    bool active;
    ushort port;
}

ServerState[] servers;
SocketState[] sockets;
int nextServerId = 0;
int nextSocketId = 0;

// ---------------------------------------------------------------------------
// net.createServer([options], [connectionListener]) → Server object
// ---------------------------------------------------------------------------
extern (C) JSValue jsCreateServer(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    JSValue connCb = JS_UNDEFINED();
    if (argc >= 1 && JS_IsFunction(ctx, argv[0]))
        connCb = JS_DupValue(ctx, argv[0]);
    else if (argc >= 2 && JS_IsFunction(ctx, argv[1]))
        connCb = JS_DupValue(ctx, argv[1]);

    int id = nextServerId++;
    try
    {
        servers ~= ServerState(ctx, connCb, -1, false, 0);
    }
    catch (Throwable)
    {
        JS_FreeValue(ctx, connCb);
        return JS_ThrowTypeError(ctx, "net.createServer: out of memory");
    }

    return makeServerObject(ctx, id);
}

// ---------------------------------------------------------------------------
// net.createConnection(port, host, [callback]) → Socket
// ---------------------------------------------------------------------------
extern (C) JSValue jsCreateConnection(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.netdb : getaddrinfo, addrinfo, freeaddrinfo;
    import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK, F_GETFL;
    import core.stdc.string : memset;

    int port = 0;
    string host = "127.0.0.1";
    JSValue connectCb = JS_UNDEFINED();

    if (argc >= 1) { int v; JS_ToInt32(ctx, &v, argv[0]); port = v; }
    if (argc >= 2 && JS_IsString(argv[1]))
    {
        try { host = jsArgToString(ctx, argv[1]); } catch (Exception) {}
    }
    if (argc >= 3 && JS_IsFunction(ctx, argv[2]))
        connectCb = JS_DupValue(ctx, argv[2]);

    // Build socket
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        JS_FreeValue(ctx, connectCb);
        return JS_ThrowTypeError(ctx, "net.connect: socket() failed");
    }

    // Non-blocking
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    // Address
    sockaddr_in addr;
    memset(&addr, 0, addr.sizeof);
    addr.sin_family = AF_INET;
    addr.sin_port   = htons(cast(ushort) port);

    // Resolve host
    addrinfo hints;
    addrinfo* res;
    memset(&hints, 0, hints.sizeof);
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    import core.stdc.stdlib : atoi;
    if (getaddrinfo(host.toStringz, null, &hints, &res) == 0 && res !is null)
    {
        auto sin = cast(sockaddr_in*) res.ai_addr;
        addr.sin_addr = sin.sin_addr;
        freeaddrinfo(res);
    }
    else
    {
        import core.sys.posix.unistd : close;
        close(fd);
        JS_FreeValue(ctx, connectCb);
        return JS_ThrowTypeError(ctx, "net.connect: host resolution failed");
    }

    import core.sys.posix.unistd : close;
    import core.sys.posix.sys.socket : connect;
    import core.stdc.errno : errno, EINPROGRESS;
    int r = connect(fd, cast(sockaddr*)&addr, addr.sizeof);
    if (r < 0 && errno != EINPROGRESS)
    {
        close(fd);
        JS_FreeValue(ctx, connectCb);
        return JS_ThrowTypeError(ctx, "net.connect: connect() failed");
    }

    int id = nextSocketId++;
    try
    {
        SocketState s;
        s.ctx    = ctx;
        s.onData = s.onEnd = s.onClose = s.onError = JS_UNDEFINED();
        s.fd     = fd;
        sockets ~= s;
    }
    catch (Throwable)
    {
        close(fd);
        JS_FreeValue(ctx, connectCb);
        return JS_ThrowTypeError(ctx, "net.connect: out of memory");
    }

    // Register with IOPoller so data events arrive on next tick
    registerSocketForPolling(id);

    auto sockObj = makeSocketObject(ctx, id);

    // Fire connect callback on next tick
    if (!JS_IsUndefined(connectCb))
    {
        JSValue[0] noArgs;
        pushPending(ctx, connectCb, noArgs[]);
        JS_FreeValue(ctx, connectCb);
    }

    return sockObj;
}

// ---------------------------------------------------------------------------
// Server object factory
// ---------------------------------------------------------------------------
JSValue makeServerObject(JSContext* ctx, int id) nothrow @trusted
{
    auto obj = JS_NewObject(ctx);
    // Store id as __id property
    JS_SetPropertyStr(ctx, obj, "__id",
        JS_NewInt32(ctx, id));
    JS_SetPropertyStr(ctx, obj, "listen",
        JS_NewCFunction(ctx, &jsServerListen, "listen", 1));
    JS_SetPropertyStr(ctx, obj, "close",
        JS_NewCFunction(ctx, &jsServerClose, "close", 0));
    JS_SetPropertyStr(ctx, obj, "on",
        JS_NewCFunction(ctx, &jsServerOn, "on", 2));
    return obj;
}

// ---------------------------------------------------------------------------
// Socket object factory
// ---------------------------------------------------------------------------
JSValue makeSocketObject(JSContext* ctx, int id) nothrow @trusted
{
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "__id",
        JS_NewInt32(ctx, id));
    JS_SetPropertyStr(ctx, obj, "on",
        JS_NewCFunction(ctx, &jsSocketOn, "on", 2));
    JS_SetPropertyStr(ctx, obj, "write",
        JS_NewCFunction(ctx, &jsSocketWrite, "write", 1));
    JS_SetPropertyStr(ctx, obj, "end",
        JS_NewCFunction(ctx, &jsSocketEnd, "end", 0));
    JS_SetPropertyStr(ctx, obj, "destroy",
        JS_NewCFunction(ctx, &jsSocketEnd, "destroy", 0));
    return obj;
}

// ---------------------------------------------------------------------------
// server.listen(port, [host], [callback])
// ---------------------------------------------------------------------------
extern (C) JSValue jsServerListen(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    import core.stdc.string : memset;

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal < 0 || idVal >= cast(int) servers.length)
        return JS_ThrowTypeError(ctx, "server.listen: invalid server");

    auto srv = &servers[idVal];

    int port = 0;
    JSValue listenCb = JS_UNDEFINED();
    if (argc >= 1) { int v; JS_ToInt32(ctx, &v, argv[0]); port = v; }
    if (argc >= 2 && JS_IsFunction(ctx, argv[1]))
        listenCb = JS_DupValue(ctx, argv[1]);
    else if (argc >= 3 && JS_IsFunction(ctx, argv[2]))
        listenCb = JS_DupValue(ctx, argv[2]);

    // Create listen socket
    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0)
    {
        JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "server.listen: socket() failed");
    }

    // Reuse addr
    int optval = 1;
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &optval, optval.sizeof);

    // Non-blocking
    int flags = fcntl(lfd, F_GETFL, 0);
    fcntl(lfd, F_SETFL, flags | O_NONBLOCK);

    sockaddr_in addr;
    memset(&addr, 0, addr.sizeof);
    addr.sin_family      = AF_INET;
    addr.sin_port        = htons(cast(ushort) port);
    addr.sin_addr.s_addr = 0; // INADDR_ANY

    if (bind(lfd, cast(sockaddr*)&addr, addr.sizeof) < 0)
    {
        import core.sys.posix.unistd : close;
        close(lfd);
        JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "server.listen: bind() failed");
    }

    if (listen(lfd, 128) < 0)
    {
        import core.sys.posix.unistd : close;
        close(lfd);
        JS_FreeValue(ctx, listenCb);
        return JS_ThrowTypeError(ctx, "server.listen: listen() failed");
    }

    srv.listenFd = lfd;
    srv.active   = true;
    srv.port     = cast(ushort) port;

    // Register with the I/O poller so accept events arrive on ticks
    registerServerForPolling(idVal);

    // 'listening' callback fires on next tick
    if (!JS_IsUndefined(listenCb))
    {
        JSValue[0] noArgs;
        pushPending(ctx, listenCb, noArgs[]);
        JS_FreeValue(ctx, listenCb);
    }

    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// server.close()
// ---------------------------------------------------------------------------
extern (C) JSValue jsServerClose(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.unistd : close;

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal >= 0 && idVal < cast(int) servers.length)
    {
        auto srv = &servers[idVal];
        if (srv.listenFd >= 0)
        {
            unregisterServerFromPolling(idVal);
            close(srv.listenFd);
            srv.listenFd = -1;
        }
        srv.active = false;
    }
    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// server.on(event, handler)
// ---------------------------------------------------------------------------
extern (C) JSValue jsServerOn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2) return JS_DupValue(ctx, this_val);

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal < 0 || idVal >= cast(int) servers.length)
        return JS_DupValue(ctx, this_val);

    auto srv = &servers[idVal];
    string evName;
    try { evName = jsArgToString(ctx, argv[0]); } catch (Exception) {}

    if (evName == "connection" && JS_IsFunction(ctx, argv[1]))
    {
        if (!JS_IsUndefined(srv.onConnection)) JS_FreeValue(ctx, srv.onConnection);
        srv.onConnection = JS_DupValue(ctx, argv[1]);
    }
    return JS_DupValue(ctx, this_val);
}

// ---------------------------------------------------------------------------
// socket.on(event, handler)
// ---------------------------------------------------------------------------
extern (C) JSValue jsSocketOn(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2) return JS_DupValue(ctx, this_val);

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal < 0 || idVal >= cast(int) sockets.length)
        return JS_DupValue(ctx, this_val);

    auto sock = &sockets[idVal];
    string evName;
    try { evName = jsArgToString(ctx, argv[0]); } catch (Exception) {}

    if (JS_IsFunction(ctx, argv[1]))
    {
        if (evName == "data")
        {
            if (!JS_IsUndefined(sock.onData)) JS_FreeValue(ctx, sock.onData);
            sock.onData = JS_DupValue(ctx, argv[1]);
        }
        else if (evName == "end")
        {
            if (!JS_IsUndefined(sock.onEnd)) JS_FreeValue(ctx, sock.onEnd);
            sock.onEnd = JS_DupValue(ctx, argv[1]);
        }
        else if (evName == "close")
        {
            if (!JS_IsUndefined(sock.onClose)) JS_FreeValue(ctx, sock.onClose);
            sock.onClose = JS_DupValue(ctx, argv[1]);
        }
        else if (evName == "error")
        {
            if (!JS_IsUndefined(sock.onError)) JS_FreeValue(ctx, sock.onError);
            sock.onError = JS_DupValue(ctx, argv[1]);
        }
    }
    return JS_DupValue(ctx, this_val);
}

// ---------------------------------------------------------------------------
// socket.write(data, [encoding], [callback])
// ---------------------------------------------------------------------------
extern (C) JSValue jsSocketWrite(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.unistd : write;

    if (argc < 1) return JS_NewBool(ctx, 0);

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal < 0 || idVal >= cast(int) sockets.length) return JS_NewBool(ctx, 0);

    auto sock = &sockets[idVal];
    if (sock.closed || sock.fd < 0) return JS_NewBool(ctx, 0);

    string data;
    try { data = jsArgToString(ctx, argv[0]); } catch (Exception) {}

    if (data.length > 0)
    {
        size_t written = 0;
        while (written < data.length)
        {
            auto n = write(sock.fd, data.ptr + written, data.length - written);
            if (n <= 0) break;
            written += n;
        }
    }

    // Optional drain callback
    if (argc >= 3 && JS_IsFunction(ctx, argv[2]))
    {
        auto drainCb = JS_DupValue(ctx, argv[2]);
        JSValue[0] noArgs;
        pushPending(ctx, drainCb, noArgs[]);
        JS_FreeValue(ctx, drainCb);
    }

    return JS_NewBool(ctx, 1);
}

// ---------------------------------------------------------------------------
// socket.end() / socket.destroy()
// ---------------------------------------------------------------------------
extern (C) JSValue jsSocketEnd(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import core.sys.posix.unistd : close;

    int idVal;
    auto idProp = JS_GetPropertyStr(ctx, this_val, "__id");
    JS_ToInt32(ctx, &idVal, idProp);
    JS_FreeValue(ctx, idProp);
    if (idVal < 0 || idVal >= cast(int) sockets.length)
        return JS_UNDEFINED();

    auto sock = &sockets[idVal];
    if (sock.closed) return JS_UNDEFINED();
    sock.closed = true;
    if (sock.fd >= 0)
    {
        unregisterSocketFromPolling(idVal);
        close(sock.fd);
        sock.fd = -1;
    }

    // Fire 'close' if registered
    if (!JS_IsUndefined(sock.onClose))
    {
        JSValue[0] noArgs;
        pushPending(sock.ctx, sock.onClose, noArgs[]);
    }
    return JS_UNDEFINED();
}

// ---------------------------------------------------------------------------
// I/O polling integration — called from EventLoop.tick() Phase 4
// Uses the iopoller (epoll on Linux) to check ready file descriptors.
// ---------------------------------------------------------------------------

// Poll all registered fds once and push pending JS callbacks.
// Called by eventloop.d each tick.
public void pollNetIO() nothrow @trusted
{
    version (linux)
    {
        ensurePoller();
        IOEvent[64] evBuf;
        auto events = gNetPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            foreach (i, ref srv; servers)
                if (srv.active && srv.listenFd == ev.fd && ev.readable)
                    acceptPendingConnections(cast(int) i);
            foreach (i, ref sock; sockets)
                if (!sock.closed && sock.fd == ev.fd && ev.readable)
                    readSocketData(cast(int) i);
        }
    }
}

// ---------------------------------------------------------------------------
// Per-server / per-socket epoll registration helpers
// ---------------------------------------------------------------------------

void registerServerForPolling(int id) nothrow @trusted
{
    version (linux)
    {
        ensurePoller();
        if (id >= 0 && id < cast(int) servers.length && servers[id].listenFd >= 0)
            gNetPoller.watch(servers[id].listenFd, true, false);
    }
}

void unregisterServerFromPolling(int id) nothrow @trusted
{
    version (linux)
    {
        if (id >= 0 && id < cast(int) servers.length && servers[id].listenFd >= 0)
            gNetPoller.unwatch(servers[id].listenFd);
    }
}

void registerSocketForPolling(int id) nothrow @trusted
{
    version (linux)
    {
        ensurePoller();
        if (id >= 0 && id < cast(int) sockets.length && sockets[id].fd >= 0)
            gNetPoller.watch(sockets[id].fd, true, false);
    }
}

void unregisterSocketFromPolling(int id) nothrow @trusted
{
    version (linux)
    {
        if (id >= 0 && id < cast(int) sockets.length && sockets[id].fd >= 0)
            gNetPoller.unwatch(sockets[id].fd);
    }
}

// ---------------------------------------------------------------------------
// Accept connections on a listening server
// ---------------------------------------------------------------------------
void acceptPendingConnections(int srvId) nothrow @trusted
{
    import core.sys.posix.sys.socket : accept;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

    if (srvId < 0 || srvId >= cast(int) servers.length) return;
    auto srv = &servers[srvId];
    if (!srv.active || srv.listenFd < 0) return;

    while (true)
    {
        int connFd = accept(srv.listenFd, null, null);
        if (connFd < 0)
        {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            break;
        }

        // Non-blocking
        int flags = fcntl(connFd, F_GETFL, 0);
        fcntl(connFd, F_SETFL, flags | O_NONBLOCK);

        // Register socket
        int sid = nextSocketId++;
        try
        {
            SocketState s;
            s.ctx    = srv.ctx;
            s.onData = s.onEnd = s.onClose = s.onError = JS_UNDEFINED();
            s.fd     = connFd;
            sockets ~= s;
        }
        catch (Throwable)
        {
            import core.sys.posix.unistd : close;
            close(connFd);
            continue;
        }
        registerSocketForPolling(sid);

        // Schedule connection callback
        if (!JS_IsUndefined(srv.onConnection))
        {
            auto sockObj = makeSocketObject(srv.ctx, sid);
            JSValue[1] args = [sockObj];
            pushPending(srv.ctx, srv.onConnection, args[]);
            JS_FreeValue(srv.ctx, sockObj);
        }
    }
}

// ---------------------------------------------------------------------------
// Read data from a connected socket
// ---------------------------------------------------------------------------
void readSocketData(int sockId) nothrow @trusted
{
    import core.sys.posix.unistd : read;
    import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

    if (sockId < 0 || sockId >= cast(int) sockets.length) return;
    auto sock = &sockets[sockId];
    if (sock.closed || sock.fd < 0) return;

    auto n = read(sock.fd, sock.readBuf.ptr, sock.readBuf.length);
    if (n > 0)
    {
        if (!JS_IsUndefined(sock.onData))
        {
            // Pass data as a string
            auto jsData = JS_NewStringLen(sock.ctx,
                cast(const(char)*) sock.readBuf.ptr, n);
            JSValue[1] args = [jsData];
            pushPending(sock.ctx, sock.onData, args[]);
            JS_FreeValue(sock.ctx, jsData);
        }
    }
    else if (n == 0)
    {
        // EOF
        sock.closed = true;
        unregisterSocketFromPolling(sockId);
        import core.sys.posix.unistd : close;
        close(sock.fd);
        sock.fd = -1;

        if (!JS_IsUndefined(sock.onEnd))
        {
            JSValue[0] noArgs;
            pushPending(sock.ctx, sock.onEnd, noArgs[]);
        }
        if (!JS_IsUndefined(sock.onClose))
        {
            JSValue[0] noArgs;
            pushPending(sock.ctx, sock.onClose, noArgs[]);
        }
    }
}

// Whether there are active servers or sockets (keeps event loop alive)
public bool hasActiveNetIO() @safe nothrow
{
    foreach (ref s; servers) if (s.active) return true;
    foreach (ref s; sockets) if (!s.closed) return true;
    return false;
}
