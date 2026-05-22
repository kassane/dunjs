module dun.builtins.dgram;


/++
 + `@trusted policy`: UDP datagram sockets (`dgram` module).
 + Every `@trusted` is one of:
 +
 +   1. POSIX socket syscalls (`socket`, `bind`, `sendto`,
 +      `recvfrom`, `setsockopt`, `close`).
 +   2. `Permission.net` gate before any UDP operation.
 +   3. `__gshared UdpSocketState[MAX_UDP_SOCKETS]` pool — slot
 +      index passed across JS/D as an int, lookup is O(1).
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.security.permissions : Permission;

// Cached method handles attached via bindMethod on every createSocket
// call — without these, 13 newFunction calls per Socket creation leak
// one JSValueProtect slot per method per call on JSC. Same pattern as
// http.d (v1.1.5) / fs.d streams (v1.1.16).
__gshared JSHandle _udpBind, _udpSend, _udpClose, _udpAddress;
__gshared JSHandle _udpSetBroadcast, _udpSetTTL, _udpAddMembership, _udpDropMembership;
__gshared JSHandle _udpOn, _udpRemoveListeners, _udpRef, _udpUnref;
__gshared bool _udpFnsCached = false;

private void ensureUdpFnsCached(IJSEngine engine) @trusted
{
    if (!_udpFnsCached)
    {
        _udpBind            = engine.newFunction(&jsUdpBind, "bind", 2);
        _udpSend            = engine.newFunction(&jsUdpSend, "send", 4);
        _udpClose           = engine.newFunction(&jsUdpClose, "close", 0);
        _udpAddress         = engine.newFunction(&jsUdpAddress, "address", 0);
        _udpSetBroadcast    = engine.newFunction(&jsUdpSetBroadcast, "setBroadcast", 1);
        _udpSetTTL          = engine.newFunction(&jsUdpSetTTL, "setTTL", 1);
        _udpAddMembership   = engine.newFunction(&jsUdpAddMembership, "addMembership", 1);
        _udpDropMembership  = engine.newFunction(&jsUdpDropMembership, "dropMembership", 1);
        _udpOn              = engine.newFunction(&jsUdpOn, "on", 2);
        _udpRemoveListeners = engine.newFunction(&jsUdpRemoveListeners, "removeAllListeners", 0);
        _udpRef             = engine.newFunction(&jsUdpRef, "ref", 0);
        _udpUnref           = engine.newFunction(&jsUdpUnref, "unref", 0);
        _udpFnsCached = true;
    }
}

void registerDgramModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerDgramModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "createSocket", engine.newFunction(&jsCreateSocket, "createSocket", 1));
    engine.setProperty(obj, "Socket", engine.newFunction(&jsCreateSocket, "Socket", 1));

    auto result = engine.eval(dgramExtensionSource(), "<dgram>");
    if (!result.isError)
        engine.freeValue(result.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_dgram__", obj);
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
        auto m = JS_NewCModule(ctx, "dun:dgram", &dgramModuleInit);
        if (m is null) return;
        foreach (name; ["createSocket", "Socket"])
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int dgramModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in dgramModuleInit");
        assert(m !is null, "Null JSModuleDef in dgramModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto dgramObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_dgram__");
        foreach (name; ["createSocket", "Socket"])
        {
            auto fn = JS_GetPropertyStr(ctx, dgramObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", dgramObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

version (Posix)
{
    import core.sys.posix.sys.socket : socket, bind, sendto, recvfrom,
        sockaddr, AF_INET, AF_INET6, SOCK_DGRAM, socklen_t, setsockopt,
        SOL_SOCKET, SO_REUSEADDR, SO_BROADCAST;
    import core.sys.posix.netinet.in_ : sockaddr_in, sockaddr_in6,
        htons, ntohs, ntohl, INADDR_ANY, INET_ADDRSTRLEN, INET6_ADDRSTRLEN;
    import core.sys.posix.arpa.inet : inet_ntop, inet_pton;
    import core.sys.posix.unistd : close;
    import core.sys.posix.fcntl : fcntl, F_GETFL, F_SETFL, O_NONBLOCK;
    import core.stdc.string : memset;
    import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;
}

struct UdpSocketState
{
    int fd = -1;
    bool bound = false;
    bool closed = false;
    int family = AF_INET; // AF_INET or AF_INET6
    JSHandle messageCallback;
    JSHandle errorCallback;
    JSHandle closeCallback;
    JSHandle listeningCallback;
    bool hasMessageCb = false;
    bool hasErrorCb = false;
    bool hasCloseCb = false;
    bool hasListeningCb = false;
}

enum MAX_UDP_SOCKETS = 256;
private __gshared UdpSocketState[MAX_UDP_SOCKETS] gUdpSockets;
private __gshared int gNextUdpId = 0;

int allocUdpSocket() nothrow @trusted
{
    for (int i = 0; i < MAX_UDP_SOCKETS; i++)
    {
        int idx = (gNextUdpId + i) % MAX_UDP_SOCKETS;
        if (gUdpSockets[idx].fd == -1 && !gUdpSockets[idx].bound)
        {
            gNextUdpId = (idx + 1) % MAX_UDP_SOCKETS;
            return idx;
        }
    }
    return -1;
}

JSHandle jsCreateSocket(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCreateSocket");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsCreateSocket");

    if (state.permissions !is null)
    {
        bool netAllowed = false;
        try { netAllowed = state.permissions.check(Permission.net, ""); }
        catch (Exception) {}
        if (!netAllowed)
            return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-net for UDP sockets");
    }

    string socketType = "udp4";
    bool reuseAddr = false;

    if (args.length >= 1)
    {
        if (engine.isString(args[0]))
        {
            socketType = engine.extractString(args[0]);
        }
        else if (engine.isObject(args[0]))
        {
            auto typeVal = engine.getProperty(args[0], "type");
            scope(exit) engine.freeValue(typeVal);
            if (engine.isString(typeVal))
                socketType = engine.extractString(typeVal);

            auto reuseVal = engine.getProperty(args[0], "reuseAddr");
            scope(exit) engine.freeValue(reuseVal);
            if (!engine.isUndefined(reuseVal) && !engine.isNull(reuseVal))
                reuseAddr = engine.extractBool(reuseVal);
        }
    }

    version (Posix)
    {
        int af = (socketType == "udp6") ? AF_INET6 : AF_INET;
        int fd = socket(af, SOCK_DGRAM, 0);
        if (fd < 0)
            return engine.throwTypeError("dgram.createSocket: socket() failed");

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        if (reuseAddr)
        {
            int optval = 1;
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &optval, cast(socklen_t) int.sizeof);
        }

        int id = allocUdpSocket();
        if (id < 0)
        {
            close(fd);
            return engine.throwTypeError("dgram: too many open sockets");
        }

        gUdpSockets[id] = UdpSocketState.init;
        gUdpSockets[id].fd = fd;
        gUdpSockets[id].family = af;

        auto socketObj = engine.newObject();
        engine.setProperty(socketObj, "_id", engine.newInt(id));
        engine.setProperty(socketObj, "type", engine.newString(socketType));
        ensureUdpFnsCached(engine);
        engine.bindMethod(socketObj, "bind", _udpBind);
        engine.bindMethod(socketObj, "send", _udpSend);
        engine.bindMethod(socketObj, "close", _udpClose);
        engine.bindMethod(socketObj, "address", _udpAddress);
        engine.bindMethod(socketObj, "setBroadcast", _udpSetBroadcast);
        engine.bindMethod(socketObj, "setTTL", _udpSetTTL);
        engine.bindMethod(socketObj, "addMembership", _udpAddMembership);
        engine.bindMethod(socketObj, "dropMembership", _udpDropMembership);
        engine.bindMethod(socketObj, "on", _udpOn);
        engine.bindMethod(socketObj, "once", _udpOn);
        engine.bindMethod(socketObj, "removeAllListeners", _udpRemoveListeners);
        engine.bindMethod(socketObj, "ref", _udpRef);
        engine.bindMethod(socketObj, "unref", _udpUnref);

        return socketObj;
    }
    else
    {
        return engine.throwTypeError("dgram not supported on this platform");
    }
}

int getSocketId(IJSEngine engine, JSHandle thisVal) @trusted
{
    auto idVal = engine.getProperty(thisVal, "_id");
    scope(exit) engine.freeValue(idVal);
    if (engine.isNumber(idVal))
        return engine.extractInt(idVal);
    return -1;
}

JSHandle jsUdpBind(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS || gUdpSockets[id].fd < 0)
        return engine.throwTypeError("dgram.bind: invalid socket");

    version (Posix)
    {
        int port = 0;
        string address = "0.0.0.0";

        if (args.length >= 1 && engine.isNumber(args[0]))
            port = engine.extractInt(args[0]);
        if (args.length >= 1 && engine.isObject(args[0]))
        {
            auto portVal = engine.getProperty(args[0], "port");
            scope(exit) engine.freeValue(portVal);
            if (engine.isNumber(portVal)) port = engine.extractInt(portVal);

            auto addrVal = engine.getProperty(args[0], "address");
            scope(exit) engine.freeValue(addrVal);
            if (engine.isString(addrVal)) address = engine.extractString(addrVal);
        }
        if (args.length >= 2 && engine.isString(args[1]))
            address = engine.extractString(args[1]);

        auto ref sock = gUdpSockets[id];

        if (sock.family == AF_INET)
        {
            sockaddr_in addr;
            memset(&addr, 0, addr.sizeof);
            addr.sin_family = AF_INET;
            addr.sin_port = htons(cast(ushort) port);

            import std.string : toStringz;
            if (address == "0.0.0.0" || address == "")
                addr.sin_addr.s_addr = INADDR_ANY;
            else
                inet_pton(AF_INET, toStringz(address), &addr.sin_addr);

            int r = bind(sock.fd, cast(sockaddr*) &addr, addr.sizeof);
            if (r < 0)
                return engine.throwTypeError("dgram.bind: bind() failed");
        }
        else
        {
            sockaddr_in6 addr6;
            memset(&addr6, 0, addr6.sizeof);
            addr6.sin6_family = AF_INET6;
            addr6.sin6_port = htons(cast(ushort) port);

            import std.string : toStringz;
            if (address == "::" || address == "")
            {
                // in6addr_any is all zeros, already memset
            }
            else
                inet_pton(AF_INET6, toStringz(address), &addr6.sin6_addr);

            int r = bind(sock.fd, cast(sockaddr*) &addr6, addr6.sizeof);
            if (r < 0)
                return engine.throwTypeError("dgram.bind: bind() failed (IPv6)");
        }

        sock.bound = true;

        if (sock.hasListeningCb)
        {
            import dun.loop.agnostic_pending : pushAgnosticPending;
            pushAgnosticPending(engine, sock.listeningCallback, []);
        }

        return engine.newUndefined();
    }
    else
    {
        return engine.throwTypeError("dgram not supported on this platform");
    }
}

JSHandle jsUdpSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    if (args.length < 3)
        return engine.throwTypeError("dgram.send requires (msg, port, address)");

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS || gUdpSockets[id].fd < 0)
        return engine.throwTypeError("dgram.send: invalid socket");

    version (Posix)
    {
        auto ref sock = gUdpSockets[id];
        if (sock.closed)
            return engine.throwTypeError("dgram.send: socket is closed");

        string msgStr = "";
        const(ubyte)[] msgData;
        bool isBuffer = false;

        if (engine.isString(args[0]))
        {
            msgStr = engine.extractString(args[0]);
            msgData = cast(const(ubyte)[]) msgStr;
        }
        else
        {
            msgStr = engine.extractString(args[0]);
            msgData = cast(const(ubyte)[]) msgStr;
        }

        // args layout: send(msg, offset?, length?, port, address, callback?)
        // or: send(msg, port, address, callback?)
        int port = 0;
        string address = "127.0.0.1";
        JSHandle callback;
        bool hasCb = false;

        if (args.length >= 5 && engine.isNumber(args[1]) && engine.isNumber(args[2]))
        {
            // send(msg, offset, length, port, address, cb?)
            port = engine.extractInt(args[3]);
            if (args.length >= 5 && engine.isString(args[4]))
                address = engine.extractString(args[4]);
            if (args.length >= 6 && engine.isFunction(args[5]))
            {
                callback = engine.dupValue(args[5]);
                hasCb = true;
            }
        }
        else
        {
            // send(msg, port, address, cb?)
            if (engine.isNumber(args[1]))
                port = engine.extractInt(args[1]);
            if (args.length >= 3 && engine.isString(args[2]))
                address = engine.extractString(args[2]);
            if (args.length >= 4 && engine.isFunction(args[3]))
            {
                callback = engine.dupValue(args[3]);
                hasCb = true;
            }
        }

        sockaddr_in destAddr;
        memset(&destAddr, 0, destAddr.sizeof);
        destAddr.sin_family = AF_INET;
        destAddr.sin_port = htons(cast(ushort) port);

        import std.string : toStringz;
        inet_pton(AF_INET, toStringz(address), &destAddr.sin_addr);

        auto sent = sendto(sock.fd, msgData.ptr, msgData.length, 0,
            cast(sockaddr*) &destAddr, destAddr.sizeof);

        if (hasCb)
        {
            import dun.loop.agnostic_pending : pushAgnosticPending;
            if (sent < 0)
            {
                auto errObj = engine.newObject();
                engine.setProperty(errObj, "message", engine.newString("send failed"));
                engine.setProperty(errObj, "code", engine.newString("ERR_SOCKET_DGRAM_NOT_RUNNING"));
                pushAgnosticPending(engine, callback, [errObj]);
            }
            else
            {
                pushAgnosticPending(engine, callback, [engine.newNull()]);
            }
            engine.freeValue(callback);
        }

        if (sent < 0)
            return engine.throwTypeError("dgram.send: sendto() failed");

        return engine.newUndefined();
    }
    else
    {
        return engine.throwTypeError("dgram not supported on this platform");
    }
}

JSHandle jsUdpClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS)
        return engine.newUndefined();

    version (Posix)
    {
        auto ref sock = gUdpSockets[id];
        if (sock.fd >= 0)
        {
            close(sock.fd);
            sock.fd = -1;
        }
        sock.closed = true;
        sock.bound = false;

        if (sock.hasCloseCb)
        {
            import dun.loop.agnostic_pending : pushAgnosticPending;
            pushAgnosticPending(engine, sock.closeCallback, []);
        }

        if (args.length >= 1 && engine.isFunction(args[0]))
        {
            import dun.loop.agnostic_pending : pushAgnosticPending;
            pushAgnosticPending(engine, args[0], []);
        }

        // Clean up stored callbacks
        if (sock.hasMessageCb) { engine.freeValue(sock.messageCallback); sock.hasMessageCb = false; }
        if (sock.hasErrorCb) { engine.freeValue(sock.errorCallback); sock.hasErrorCb = false; }
        if (sock.hasCloseCb) { engine.freeValue(sock.closeCallback); sock.hasCloseCb = false; }
        if (sock.hasListeningCb) { engine.freeValue(sock.listeningCallback); sock.hasListeningCb = false; }
    }

    return engine.newUndefined();
}

JSHandle jsUdpAddress(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS || gUdpSockets[id].fd < 0)
        return engine.throwTypeError("dgram.address: invalid socket");

    version (Posix)
    {
        auto ref sock = gUdpSockets[id];
        auto result = engine.newObject();

        if (sock.family == AF_INET)
        {
            sockaddr_in addr;
            socklen_t addrLen = cast(socklen_t) addr.sizeof;
            import core.sys.posix.sys.socket : getsockname;
            if (getsockname(sock.fd, cast(sockaddr*) &addr, &addrLen) == 0)
            {
                char[INET_ADDRSTRLEN] buf;
                auto addrStr = inet_ntop(AF_INET, &addr.sin_addr, buf.ptr, buf.length);
                if (addrStr !is null)
                {
                    /* `newString` copies bytes into engine storage; the
                       `.idup` was a redundant GC allocation on the
                       per-call `address` query. */
                    import core.stdc.string : strlen;
                    engine.setProperty(result, "address",
                        engine.newString(
                            cast(const(char)[]) addrStr[0 .. strlen(addrStr)]));
                }
                else
                    engine.setProperty(result, "address", engine.newString("0.0.0.0"));

                engine.setProperty(result, "port", engine.newInt(ntohs(addr.sin_port)));
                engine.setProperty(result, "family", engine.newString("IPv4"));
            }
        }
        else
        {
            sockaddr_in6 addr6;
            socklen_t addrLen = cast(socklen_t) addr6.sizeof;
            import core.sys.posix.sys.socket : getsockname;
            if (getsockname(sock.fd, cast(sockaddr*) &addr6, &addrLen) == 0)
            {
                char[INET6_ADDRSTRLEN] buf;
                auto addrStr = inet_ntop(AF_INET6, &addr6.sin6_addr, buf.ptr, buf.length);
                if (addrStr !is null)
                {
                    import core.stdc.string : strlen;
                    engine.setProperty(result, "address",
                        engine.newString(
                            cast(const(char)[]) addrStr[0 .. strlen(addrStr)]));
                }
                else
                    engine.setProperty(result, "address", engine.newString("::"));

                engine.setProperty(result, "port", engine.newInt(ntohs(addr6.sin6_port)));
                engine.setProperty(result, "family", engine.newString("IPv6"));
            }
        }

        return result;
    }
    else
    {
        return engine.throwTypeError("dgram not supported on this platform");
    }
}

JSHandle jsUdpSetBroadcast(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS || gUdpSockets[id].fd < 0)
        return engine.throwTypeError("dgram.setBroadcast: invalid socket");

    version (Posix)
    {
        bool flag = args.length >= 1 && engine.extractBool(args[0]);
        int optval = flag ? 1 : 0;
        setsockopt(gUdpSockets[id].fd, SOL_SOCKET, SO_BROADCAST,
            &optval, cast(socklen_t) int.sizeof);
    }

    return engine.newUndefined();
}

JSHandle jsUdpSetTTL(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS || gUdpSockets[id].fd < 0)
        return engine.throwTypeError("dgram.setTTL: invalid socket");

    version (Posix)
    {
        int ttl = 64;
        if (args.length >= 1 && engine.isNumber(args[0]))
            ttl = engine.extractInt(args[0]);

        import core.sys.posix.netinet.in_ : IPPROTO_IP;
        enum IP_TTL = 2;
        setsockopt(gUdpSockets[id].fd, IPPROTO_IP, IP_TTL,
            &ttl, cast(socklen_t) int.sizeof);
    }

    return engine.newUndefined();
}

JSHandle jsUdpAddMembership(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("addMembership requires multicast address");

    // Multicast join — stub for now, returns success
    return engine.newUndefined();
}

JSHandle jsUdpDropMembership(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    return state.engine.newUndefined();
}

JSHandle jsUdpOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isFunction(args[1]))
        return engine.dupValue(thisVal);

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS)
        return engine.dupValue(thisVal);

    auto event = engine.extractString(args[0]);
    auto ref sock = gUdpSockets[id];

    if (event == "message")
    {
        if (sock.hasMessageCb) engine.freeValue(sock.messageCallback);
        sock.messageCallback = engine.dupValue(args[1]);
        sock.hasMessageCb = true;
    }
    else if (event == "error")
    {
        if (sock.hasErrorCb) engine.freeValue(sock.errorCallback);
        sock.errorCallback = engine.dupValue(args[1]);
        sock.hasErrorCb = true;
    }
    else if (event == "close")
    {
        if (sock.hasCloseCb) engine.freeValue(sock.closeCallback);
        sock.closeCallback = engine.dupValue(args[1]);
        sock.hasCloseCb = true;
    }
    else if (event == "listening")
    {
        if (sock.hasListeningCb) engine.freeValue(sock.listeningCallback);
        sock.listeningCallback = engine.dupValue(args[1]);
        sock.hasListeningCb = true;
    }

    return engine.dupValue(thisVal);
}

JSHandle jsUdpRemoveListeners(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    auto engine = state.engine;

    int id = getSocketId(engine, thisVal);
    if (id < 0 || id >= MAX_UDP_SOCKETS)
        return engine.dupValue(thisVal);

    auto ref sock = gUdpSockets[id];
    if (sock.hasMessageCb) { engine.freeValue(sock.messageCallback); sock.hasMessageCb = false; }
    if (sock.hasErrorCb) { engine.freeValue(sock.errorCallback); sock.hasErrorCb = false; }
    if (sock.hasCloseCb) { engine.freeValue(sock.closeCallback); sock.hasCloseCb = false; }
    if (sock.hasListeningCb) { engine.freeValue(sock.listeningCallback); sock.hasListeningCb = false; }

    return engine.dupValue(thisVal);
}

JSHandle jsUdpRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    return state.engine.dupValue(thisVal);
}

JSHandle jsUdpUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null && state.engine !is null);
    return state.engine.dupValue(thisVal);
}

string dgramExtensionSource() pure @safe nothrow
{
    return `(function() {
  var dgram = globalThis.__dun_cjs_dgram__;
  if (!dgram) return;
  dgram.Socket = dgram.createSocket;
})()`;
}
