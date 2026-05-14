module dun.builtins.net;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.loop.agnostic_pending : pushAgnosticPending;

private enum : size_t {
    SOCKET_READ_BUF_SIZE = 4096,
    LISTEN_BACKLOG       = 1024,
    IO_POLL_BATCH_SIZE   = 64,
}

void registerNetModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerNetModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "createServer", engine.newFunction(&jsCreateServer, "createServer", 1));
    engine.setProperty(obj, "createConnection", engine.newFunction(&jsCreateConnection, "createConnection", 2));
    engine.setProperty(obj, "connect", engine.newFunction(&jsCreateConnection, "connect", 2));
    engine.setProperty(obj, "isIP", engine.newFunction(&jsNetIsIP, "isIP", 1));
    engine.setProperty(obj, "isIPv4", engine.newFunction(&jsNetIsIPv4, "isIPv4", 1));
    engine.setProperty(obj, "isIPv6", engine.newFunction(&jsNetIsIPv6, "isIPv6", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_net__", obj);
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
        auto m = JS_NewCModule(ctx, "dun:net", &netModuleInit);
        if (m is null) return;
        foreach (name; ["createServer", "createConnection", "connect", "isIP", "isIPv4", "isIPv6"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int netModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in netModuleInit");
        assert(m !is null, "Null JSModuleDef in netModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto netObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_net__");
        foreach (name; ["createServer", "createConnection", "connect", "isIP", "isIPv4", "isIPv6"])
        {
            auto fn = JS_GetPropertyStr(ctx, netObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, netObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    private IOPoller gNetPoller;
    private bool gNetPollerInited = false;

    private void ensurePoller() nothrow @trusted
    {
        if (!gNetPollerInited) { gNetPoller.initialize(); gNetPollerInited = true; }
    }
}

private:

string formatIPv4(uint ip) nothrow @trusted
{
    char[15] buf;
    int pos = 0;
    foreach (i; 0 .. 4)
    {
        uint octet = (ip >> (24 - i * 8)) & 0xFF;
        if (octet >= 100) { buf[pos++] = cast(char)('0' + octet / 100); octet %= 100; buf[pos++] = cast(char)('0' + octet / 10); buf[pos++] = cast(char)('0' + octet % 10); }
        else if (octet >= 10) { buf[pos++] = cast(char)('0' + octet / 10); buf[pos++] = cast(char)('0' + octet % 10); }
        else buf[pos++] = cast(char)('0' + octet);
        if (i < 3) buf[pos++] = '.';
    }
    try return buf[0 .. pos].idup;
    catch (Exception) return "0.0.0.0";
}

// Cached function handles for server/socket objects
__gshared JSHandle _srvListen, _srvClose, _srvOn;
__gshared JSHandle _sockOn, _sockWrite, _sockEnd, _sockDestroy;
__gshared bool _netFnsCached = false;

struct SocketState
{
    IJSEngine engine;
    JSHandle onData;
    JSHandle onEnd;
    JSHandle onClose;
    JSHandle onError;
    int fd = -1;
    bool closed;
    bool eventsSet;
    ubyte[SOCKET_READ_BUF_SIZE] readBuf;
    string remoteAddress;
    ushort remotePort;
    string localAddress;
    ushort localPort;
}

struct ServerState
{
    IJSEngine engine;
    JSHandle onConnection;
    int listenFd = -1;
    bool active;
    ushort port;
    bool connCbSet;
}

ServerState[] servers;
SocketState[] sockets;
int nextServerId = 0;
int nextSocketId = 0;

JSHandle jsCreateServer(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCreateServer");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCreateServer");
    auto engine = state.engine;

    JSHandle connCb;
    bool hasCb = false;
    if (args.length >= 1 && engine.isFunction(args[0]))
    {
        connCb = engine.dupValue(args[0]);
        hasCb = true;
    }
    else if (args.length >= 2 && engine.isFunction(args[1]))
    {
        connCb = engine.dupValue(args[1]);
        hasCb = true;
    }

    int id = nextServerId++;
    try
    {
        ServerState srv;
        srv.engine = engine;
        if (hasCb) { srv.onConnection = connCb; srv.connCbSet = true; }
        servers ~= srv;
    }
    catch (Throwable)
    {
        if (hasCb) engine.freeValue(connCb);
        return engine.throwTypeError("net.createServer: out of memory");
    }

    return makeServerObject(engine, id);
}

JSHandle jsCreateConnection(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCreateConnection");
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.netdb : getaddrinfo, addrinfo, freeaddrinfo;
        import core.sys.posix.fcntl : fcntl, F_SETFL, O_NONBLOCK, F_GETFL;
        import core.stdc.string : memset;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsCreateConnection");
        auto engine = state.engine;

        int port = 0;
        string host = "127.0.0.1";
        JSHandle connectCb;
        bool hasCb = false;

        if (args.length >= 1 && engine.isNumber(args[0]))
            port = engine.extractInt(args[0]);
        if (args.length >= 2 && engine.isString(args[1]))
            host = engine.extractString(args[1]);
        if (args.length >= 3 && engine.isFunction(args[2]))
        {
            connectCb = engine.dupValue(args[2]);
            hasCb = true;
        }

        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0)
        {
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError("net.connect: socket() failed");
        }

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        sockaddr_in addr;
        memset(&addr, 0, addr.sizeof);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(cast(ushort) port);

        import std.string : toStringz;
        addrinfo hints;
        addrinfo* res;
        memset(&hints, 0, hints.sizeof);
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_STREAM;
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
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError("net.connect: host resolution failed");
        }

        import core.sys.posix.sys.socket : connect;
        import core.stdc.errno : errno, EINPROGRESS;
        int r = connect(fd, cast(sockaddr*)&addr, addr.sizeof);
        if (r < 0 && errno != EINPROGRESS)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError("net.connect: connect() failed");
        }

        int id = nextSocketId++;
        try
        {
            SocketState s;
            s.engine = engine;
            s.fd = fd;
            sockets ~= s;
        }
        catch (Throwable)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError("net.connect: out of memory");
        }

        registerSocketForPolling(id);

        auto sockObj = makeSocketObject(engine, id);

        if (hasCb)
        {
            JSHandle[0] noArgs;
            pushAgnosticPending(engine, connectCb, noArgs[]);
            engine.freeValue(connectCb);
        }

        return sockObj;
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.throwTypeError("net.connect not supported on this platform");
    }
}

void ensureNetFnsCached(IJSEngine engine) @trusted
{
    if (_netFnsCached) return;
    _srvListen = engine.newFunction(&jsServerListen, "listen", 1);
    _srvClose = engine.newFunction(&jsServerClose, "close", 0);
    _srvOn = engine.newFunction(&jsServerOn, "on", 2);
    _sockOn = engine.newFunction(&jsSocketOn, "on", 2);
    _sockWrite = engine.newFunction(&jsSocketWrite, "write", 1);
    _sockEnd = engine.newFunction(&jsSocketEnd, "end", 0);
    _sockDestroy = engine.newFunction(&jsSocketEnd, "destroy", 0);
    _netFnsCached = true;
}

JSHandle makeServerObject(IJSEngine engine, int id) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeServerObject");
    ensureNetFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__id", engine.newInt(id));
    engine.setProperty(obj, "listen", engine.dupValue(_srvListen));
    engine.setProperty(obj, "close", engine.dupValue(_srvClose));
    engine.setProperty(obj, "on", engine.dupValue(_srvOn));
    return obj;
}

JSHandle makeSocketObject(IJSEngine engine, int id) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeSocketObject");
    ensureNetFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__id", engine.newInt(id));
    engine.setProperty(obj, "on", engine.dupValue(_sockOn));
    engine.setProperty(obj, "write", engine.dupValue(_sockWrite));
    engine.setProperty(obj, "end", engine.dupValue(_sockEnd));
    engine.setProperty(obj, "destroy", engine.dupValue(_sockDestroy));

    if (id >= 0 && id < cast(int) sockets.length)
    {
        auto sock = &sockets[id];
        if (sock.remoteAddress.length > 0)
        {
            engine.setProperty(obj, "remoteAddress", engine.newString(sock.remoteAddress));
            engine.setProperty(obj, "remotePort", engine.newInt(cast(int) sock.remotePort));
            engine.setProperty(obj, "remoteFamily", engine.newString("IPv4"));
        }
        if (sock.localAddress.length > 0)
        {
            engine.setProperty(obj, "localAddress", engine.newString(sock.localAddress));
            engine.setProperty(obj, "localPort", engine.newInt(cast(int) sock.localPort));
        }
    }

    return obj;
}

JSHandle jsServerListen(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsServerListen");
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsServerListen");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__id");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) servers.length)
            return engine.throwTypeError("server.listen: invalid server");

        auto srv = &servers[idVal];

        int port = 0;
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
            return engine.throwTypeError("server.listen: socket() failed");
        }

        int optval = 1;
        setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &optval, optval.sizeof);

        int flags = fcntl(lfd, F_GETFL, 0);
        fcntl(lfd, F_SETFL, flags | O_NONBLOCK);

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
            return engine.throwTypeError("server.listen: bind() failed");
        }

        if (listen(lfd, LISTEN_BACKLOG) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("server.listen: listen() failed");
        }

        srv.listenFd = lfd;
        srv.active = true;
        srv.port = cast(ushort) port;

        registerServerForPolling(idVal);

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
        return state.engine.throwTypeError("server.listen not supported on this platform");
    }
}

JSHandle jsServerClose(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsServerClose");
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsServerClose");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__id");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
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
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

JSHandle jsServerOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsServerOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsServerOn");
    auto engine = state.engine;
    if (args.length < 2) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__id");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) servers.length) return thisVal;

    auto srv = &servers[idVal];
    auto evName = engine.extractString(args[0]);

    if (evName == "connection" && engine.isFunction(args[1]))
    {
        if (srv.connCbSet) engine.freeValue(srv.onConnection);
        srv.onConnection = engine.dupValue(args[1]);
        srv.connCbSet = true;
    }
    return thisVal;
}

JSHandle jsSocketOn(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSocketOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSocketOn");
    auto engine = state.engine;
    if (args.length < 2) return thisVal;

    auto idProp = engine.getProperty(thisVal, "__id");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) sockets.length) return thisVal;

    auto sock = &sockets[idVal];
    auto evName = engine.extractString(args[0]);

    if (engine.isFunction(args[1]))
    {
        if (evName == "data")
            sock.onData = engine.dupValue(args[1]);
        else if (evName == "end")
            sock.onEnd = engine.dupValue(args[1]);
        else if (evName == "close")
            sock.onClose = engine.dupValue(args[1]);
        else if (evName == "error")
            sock.onError = engine.dupValue(args[1]);
        sock.eventsSet = true;
    }
    return thisVal;
}

JSHandle jsSocketWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSocketWrite");
    version (Posix)
    {
        import core.sys.posix.unistd : write;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsSocketWrite");
        auto engine = state.engine;
        if (args.length < 1) return engine.newBool(false);

        auto idProp = engine.getProperty(thisVal, "__id");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) sockets.length) return engine.newBool(false);

        auto sock = &sockets[idVal];
        if (sock.closed || sock.fd < 0) return engine.newBool(false);

        auto data = engine.extractString(args[0]);
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
        return engine.newBool(true);
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newBool(false);
    }
}

JSHandle jsSocketEnd(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSocketEnd");
    version (Posix)
    {
        import core.sys.posix.unistd : close;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsSocketEnd");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__id");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) sockets.length)
            return engine.newUndefined();

        auto sock = &sockets[idVal];
        if (sock.closed) return engine.newUndefined();
        sock.closed = true;
        if (sock.fd >= 0)
        {
            unregisterSocketFromPolling(idVal);
            close(sock.fd);
            sock.fd = -1;
        }

        if (sock.eventsSet && engine.isFunction(sock.onClose))
        {
            JSHandle[0] noArgs;
            pushAgnosticPending(engine, sock.onClose, noArgs[]);
        }

        // Free JS callback handles to prevent leaks
        if (sock.eventsSet)
        {
            try
            {
                engine.freeValue(sock.onData);
                engine.freeValue(sock.onEnd);
                engine.freeValue(sock.onClose);
                engine.freeValue(sock.onError);
            }
            catch (Throwable) {}
            sock.eventsSet = false;
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

// I/O polling
public void pollNetIO() nothrow @trusted
{
    version (linux)
    {
        ensurePoller();
        IOEvent[IO_POLL_BATCH_SIZE] evBuf;
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

void acceptPendingConnections(int srvId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : accept, getsockname, sockaddr, socklen_t;
        import core.sys.posix.netinet.in_ : sockaddr_in, ntohs, ntohl;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (srvId < 0 || srvId >= cast(int) servers.length) return;
        auto srv = &servers[srvId];
        if (!srv.active || srv.listenFd < 0) return;

        while (true)
        {
            sockaddr_in peerAddr;
            socklen_t peerLen = cast(socklen_t) sockaddr_in.sizeof;
            int connFd = accept(srv.listenFd, cast(sockaddr*) &peerAddr, &peerLen);
            if (connFd < 0)
            {
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                break;
            }

            int flags = fcntl(connFd, F_GETFL, 0);
            fcntl(connFd, F_SETFL, flags | O_NONBLOCK);

            int sid = nextSocketId++;
            try
            {
                SocketState s;
                s.engine = srv.engine;
                s.fd = connFd;

                uint ip = ntohl(peerAddr.sin_addr.s_addr);
                s.remotePort = ntohs(peerAddr.sin_port);
                s.remoteAddress = formatIPv4(ip);

                sockaddr_in localAddr;
                socklen_t localLen = cast(socklen_t) sockaddr_in.sizeof;
                if (getsockname(connFd, cast(sockaddr*) &localAddr, &localLen) == 0)
                {
                    uint localIp = ntohl(localAddr.sin_addr.s_addr);
                    s.localPort = ntohs(localAddr.sin_port);
                    s.localAddress = formatIPv4(localIp);
                }

                sockets ~= s;
            }
            catch (Throwable)
            {
                import core.sys.posix.unistd : close;
                close(connFd);
                continue;
            }
            registerSocketForPolling(sid);

            if (srv.connCbSet)
            {
                try
                {
                    auto sockObj = makeSocketObject(srv.engine, sid);
                    JSHandle[1] callArgs = [sockObj];
                    pushAgnosticPending(srv.engine, srv.onConnection, callArgs[]);
                    srv.engine.freeValue(sockObj);
                }
                catch (Throwable) {}
            }
        }
    }
}

void readSocketData(int sockId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.unistd : read;

        if (sockId < 0 || sockId >= cast(int) sockets.length) return;
        auto sock = &sockets[sockId];
        if (sock.closed || sock.fd < 0) return;

        auto n = read(sock.fd, sock.readBuf.ptr, sock.readBuf.length);
        if (n > 0)
        {
            try
            {
                if (sock.eventsSet && sock.engine.isFunction(sock.onData))
                {
                    auto jsData = sock.engine.newString(cast(string) sock.readBuf[0 .. n].idup);
                    JSHandle[1] callArgs = [jsData];
                    pushAgnosticPending(sock.engine, sock.onData, callArgs[]);
                    sock.engine.freeValue(jsData);
                }
            }
            catch (Throwable) {}
        }
        else if (n == 0)
        {
            sock.closed = true;
            unregisterSocketFromPolling(sockId);
            import core.sys.posix.unistd : close;
            close(sock.fd);
            sock.fd = -1;

            try
            {
                if (sock.eventsSet && sock.engine.isFunction(sock.onEnd))
                {
                    JSHandle[0] noArgs;
                    pushAgnosticPending(sock.engine, sock.onEnd, noArgs[]);
                }
                if (sock.eventsSet && sock.engine.isFunction(sock.onClose))
                {
                    JSHandle[0] noArgs;
                    pushAgnosticPending(sock.engine, sock.onClose, noArgs[]);
                }
            }
            catch (Throwable) {}
        }
    }
}

JSHandle jsNetIsIP(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in net.isIP");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newInt(0);
    auto addr = engine.extractString(args[0]);
    if (isIPv4(addr)) return engine.newInt(4);
    if (isIPv6(addr)) return engine.newInt(6);
    return engine.newInt(0);
}

JSHandle jsNetIsIPv4(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in net.isIPv4");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newBool(false);
    return engine.newBool(isIPv4(engine.extractString(args[0])));
}

JSHandle jsNetIsIPv6(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in net.isIPv6");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newBool(false);
    return engine.newBool(isIPv6(engine.extractString(args[0])));
}

private bool isIPv4(string addr) @safe pure nothrow
{
    int dots = 0;
    int digitCount = 0;
    int val = 0;
    foreach (c; addr)
    {
        if (c == '.')
        {
            if (digitCount == 0 || val > 255) return false;
            dots++;
            digitCount = 0;
            val = 0;
        }
        else if (c >= '0' && c <= '9')
        {
            val = val * 10 + (c - '0');
            digitCount++;
            if (digitCount > 3) return false;
        }
        else return false;
    }
    return dots == 3 && digitCount > 0 && val <= 255;
}

private bool isIPv6(string addr) @safe pure nothrow
{
    if (addr.length < 2) return false;
    int colons = 0;
    bool hasDoubleColon = false;
    foreach (i, c; addr)
    {
        if (c == ':')
        {
            colons++;
            if (i + 1 < addr.length && addr[i + 1] == ':')
                hasDoubleColon = true;
        }
        else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
            return false;
    }
    return colons >= 2 && colons <= 7;
}

public bool hasActiveNetIO() @safe nothrow
{
    foreach (ref s; servers) if (s.active) return true;
    foreach (ref s; sockets) if (!s.closed) return true;
    return false;
}
