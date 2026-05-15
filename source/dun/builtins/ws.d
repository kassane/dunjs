module dun.builtins.ws;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.loop.agnostic_pending : pushAgnosticPending;

private enum : size_t {
    WS_PAYLOAD_LEN_16BIT  = 126,
    WS_PAYLOAD_LEN_64BIT  = 127,
    WS_MASK_KEY_LEN       = 4,
    WS_MIN_HEADER_SIZE    = 2,
    WS_SHA1_DIGEST_SIZE   = 20,
    UBYTE_RANGE           = 256,
}
private enum : ushort {
    WS_CLOSE_NORMAL       = 1000,
    WS_DEFAULT_PORT       = 80,
    WS_DEFAULT_TLS_PORT   = 443,
    WS_DEFAULT_SERVER_PORT = 8080,
}
private enum {
    WS_LISTEN_BACKLOG    = 1024,
    IO_POLL_BATCH_SIZE   = 64,
}

void registerWsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerWsModule");
    auto obj = engine.newObject();
    engine.setProperty(obj, "WebSocketServer", engine.newFunction(&jsWsCreateServer, "WebSocketServer", 1));
    engine.setProperty(obj, "WebSocket", engine.newFunction(&jsWsConnect, "WebSocket", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_ws__", obj);
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
        auto m = JS_NewCModule(ctx, "dun:ws", &wsModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "WebSocketServer");
        JS_AddModuleExport(ctx, m, "WebSocket");
    }

    private extern (C) int wsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in wsModuleInit");
        assert(m !is null, "Null JSModuleDef in wsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto wsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_ws__");
        foreach (name; ["WebSocketServer", "WebSocket"])
        {
            auto fn = JS_GetPropertyStr(ctx, wsObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, wsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    private IOPoller gWsPoller;
    private bool gWsPollerInited = false;

    private void ensureWsPoller() nothrow @trusted
    {
        if (!gWsPollerInited) { gWsPoller.initialize(); gWsPollerInited = true; }
    }
}

private:

// Cached function handles for WS server/client objects
__gshared JSHandle _wsSrvOn, _wsSrvClose, _wsSrvListen;
__gshared JSHandle _wsClientOn, _wsClientSend, _wsClientClose;
__gshared bool _wsFnsCached = false;

void ensureWsFnsCached(IJSEngine engine) @trusted
{
    if (_wsFnsCached) return;
    _wsSrvOn = engine.newFunction(&jsWsServerOn, "on", 2);
    _wsSrvClose = engine.newFunction(&jsWsServerClose, "close", 0);
    _wsSrvListen = engine.newFunction(&jsWsServerListen, "listen", 1);
    _wsClientOn = engine.newFunction(&jsWsClientOn, "on", 2);
    _wsClientSend = engine.newFunction(&jsWsClientSend, "send", 1);
    _wsClientClose = engine.newFunction(&jsWsClientClose, "close", 0);
    _wsFnsCached = true;
}

enum MAX_BUF = 16 * 1024;
enum MAX_WS_MESSAGE = 16 * 1024 * 1024;
enum WS_MAGIC = "258EAFA5-E914-47DA-95CA-5CF5AB53E0B5";

enum WsState : ubyte
{
    connecting,
    open,
    closing,
    closed,
}

enum WsOpcode : ubyte
{
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
}

struct WsConnState
{
    IJSEngine engine;
    int fd = -1;
    WsState state;
    bool isMasked;
    char[MAX_BUF] buf;
    size_t bufLen;
    int serverId = -1;

    JSHandle onopen;
    JSHandle onmessage;
    JSHandle onclose;
    JSHandle onerror;
    bool hasOnopen;
    bool hasOnmessage;
    bool hasOnclose;
    bool hasOnerror;

    bool handshakeDone;
}

struct WsServerState
{
    IJSEngine engine;
    int listenFd = -1;
    bool active;
    ushort port;
    JSHandle connectionCb;
    bool hasCb;
}

WsServerState[] wsServers;
WsConnState[] wsConns;
int nextWsServerId;
int nextWsConnId;

// --- Frame encoding/decoding ---

struct WsFrame
{
    bool fin;
    WsOpcode opcode;
    bool masked;
    ubyte[4] maskKey;
    const(ubyte)[] payload;
}

ubyte[] buildWsFrame(WsOpcode opcode, const(ubyte)[] payload, bool mask) @trusted
{
    // Pre-calculate frame size: 1 (opcode) + 1-9 (length) + 0|4 (mask key) + payload
    size_t headerLen = 2;
    if (payload.length >= WS_PAYLOAD_LEN_16BIT && payload.length <= 0xFFFF) headerLen = 4;
    else if (payload.length > 0xFFFF) headerLen = 10;
    size_t maskLen = mask ? WS_MASK_KEY_LEN : 0;
    size_t totalLen = headerLen + maskLen + payload.length;

    auto frame = new ubyte[totalLen];
    size_t pos = 0;

    frame[pos++] = cast(ubyte)(0x80 | (opcode & 0x0F));

    ubyte maskBit = mask ? 0x80 : 0;
    if (payload.length < WS_PAYLOAD_LEN_16BIT)
    {
        frame[pos++] = cast(ubyte)(maskBit | cast(ubyte) payload.length);
    }
    else if (payload.length <= 0xFFFF)
    {
        frame[pos++] = cast(ubyte)(maskBit | WS_PAYLOAD_LEN_16BIT);
        frame[pos++] = cast(ubyte)(payload.length >> 8);
        frame[pos++] = cast(ubyte)(payload.length & 0xFF);
    }
    else
    {
        frame[pos++] = cast(ubyte)(maskBit | WS_PAYLOAD_LEN_64BIT);
        ulong len = payload.length;
        foreach_reverse (i; 0 .. 8)
            frame[pos++] = cast(ubyte)((len >> (i * 8)) & 0xFF);
    }

    if (mask)
    {
        import std.random : uniform;
        ubyte[4] key;
        foreach (ref k; key) k = cast(ubyte) uniform(0, UBYTE_RANGE);
        frame[pos .. pos + 4] = key[];
        pos += 4;
        foreach (i, b; payload)
            frame[pos + i] = cast(ubyte)(b ^ key[i & 3]);
    }
    else
    {
        frame[pos .. pos + payload.length] = payload[];
    }
    return frame;
}

struct ParseResult
{
    bool valid;
    WsFrame frame;
    size_t consumed;
}

ParseResult parseWsFrame(const(ubyte)[] data) @trusted nothrow
{
    ParseResult fail;
    if (data.length < 2) return fail;

    WsFrame f;
    f.fin = (data[0] & 0x80) != 0;
    f.opcode = cast(WsOpcode)(data[0] & 0x0F);
    f.masked = (data[1] & 0x80) != 0;
    ulong payLen = data[1] & 0x7F;
    size_t offset = 2;

    if (payLen == WS_PAYLOAD_LEN_16BIT)
    {
        if (data.length < 4) return fail;
        payLen = (cast(ulong) data[2] << 8) | data[3];
        offset = 4;
    }
    else if (payLen == WS_PAYLOAD_LEN_64BIT)
    {
        if (data.length < 10) return fail;
        payLen = 0;
        foreach (i; 0 .. 8)
            payLen = (payLen << 8) | data[2 + i];
        offset = 10;
    }

    if (f.masked)
    {
        if (data.length < offset + 4) return fail;
        f.maskKey[0 .. 4] = data[offset .. offset + 4];
        offset += 4;
    }

    if (payLen > MAX_WS_MESSAGE || data.length < offset + payLen) return fail;

    if (f.masked)
    {
        auto unmasked = new ubyte[cast(size_t) payLen];
        foreach (i; 0 .. cast(size_t) payLen)
            unmasked[i] = data[offset + i] ^ f.maskKey[i & 3];
        f.payload = unmasked;
    }
    else
    {
        f.payload = data[offset .. offset + cast(size_t) payLen];
    }

    return ParseResult(true, f, offset + cast(size_t) payLen);
}

// --- SHA1 + Base64 for handshake ---

string computeAcceptKey(string clientKey) @trusted
{
    import std.digest.sha : SHA1;
    import std.base64 : Base64;
    SHA1 sha;
    sha.put(cast(const(ubyte)[]) clientKey);
    sha.put(cast(const(ubyte)[]) WS_MAGIC);
    auto hash = sha.finish();
    return cast(string) Base64.encode(hash[]);
}

// --- Server ---

JSHandle jsWsCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsCreateServer");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWsCreateServer");
    auto engine = state.engine;

    int port = WS_DEFAULT_SERVER_PORT;
    if (args.length >= 1 && engine.isObject(args[0]))
    {
        auto portProp = engine.getProperty(args[0], "port");
        if (engine.isNumber(portProp))
            port = engine.extractInt(portProp);
    }

    int id = nextWsServerId++;
    try
    {
        WsServerState srv;
        srv.engine = engine;
        srv.port = cast(ushort) port;
        wsServers ~= srv;
    }
    catch (Throwable)
    {
        return engine.throwTypeError("ws.WebSocketServer: out of memory");
    }
    return makeWsServerObj(engine, id);
}

JSHandle makeWsServerObj(IJSEngine engine, int id) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeWsServerObj");
    auto obj = engine.newObject();
    ensureWsFnsCached(engine);
    engine.setProperty(obj, "__wsid", engine.newInt(id));
    engine.setProperty(obj, "on", engine.dupValue(_wsSrvOn));
    engine.setProperty(obj, "close", engine.dupValue(_wsSrvClose));
    engine.setProperty(obj, "listen", engine.dupValue(_wsSrvListen));
    return obj;
}

JSHandle jsWsServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsServerListen");
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsWsServerListen");
        auto engine = state.engine;

        if (state.permissions !is null && !state.permissions.check(Permission.net, "0.0.0.0"))
            return engine.throwTypeError("WebSocketServer: requires --allow-net");

        auto idProp = engine.getProperty(thisVal, "__wsid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) wsServers.length)
            return engine.throwTypeError("WebSocketServer.listen: invalid server");

        auto srv = &wsServers[idVal];

        int port = srv.port;
        JSHandle listenCb;
        bool hasCb = false;
        if (args.length >= 1 && engine.isFunction(args[0]))
        {
            listenCb = engine.dupValue(args[0]);
            hasCb = true;
        }
        else if (args.length >= 1 && engine.isNumber(args[0]))
        {
            port = engine.extractInt(args[0]);
            if (args.length >= 2 && engine.isFunction(args[1]))
            {
                listenCb = engine.dupValue(args[1]);
                hasCb = true;
            }
        }

        int lfd = socket(AF_INET, SOCK_STREAM, 0);
        if (lfd < 0)
        {
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("WebSocketServer: socket() failed");
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
            return engine.throwTypeError("WebSocketServer: bind() failed");
        }
        if (listen(lfd, WS_LISTEN_BACKLOG) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("WebSocketServer: listen() failed");
        }

        srv.listenFd = lfd;
        srv.active = true;
        srv.port = cast(ushort) port;

        version (linux)
        {
            ensureWsPoller();
            gWsPoller.watch(lfd, true, false);
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
        return state.engine.throwTypeError("WebSocket server not supported on this platform");
    }
}

JSHandle jsWsServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsServerOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWsServerOn");
    auto engine = state.engine;
    if (args.length < 2) return engine.dupValue(thisVal);

    auto idProp = engine.getProperty(thisVal, "__wsid");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) wsServers.length) return engine.dupValue(thisVal);

    auto ev = engine.extractString(args[0]);
    if (ev == "connection" && engine.isFunction(args[1]))
    {
        auto srv = &wsServers[idVal];
        if (srv.hasCb) engine.freeValue(srv.connectionCb);
        srv.connectionCb = engine.dupValue(args[1]);
        srv.hasCb = true;
    }
    return engine.dupValue(thisVal);
}

JSHandle jsWsServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsServerClose");
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsWsServerClose");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__wsid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal >= 0 && idVal < cast(int) wsServers.length)
        {
            auto srv = &wsServers[idVal];
            if (srv.listenFd >= 0)
            {
                version (linux) gWsPoller.unwatch(srv.listenFd);
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

// --- Client ---

JSHandle jsWsConnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsConnect");
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;
        import core.stdc.errno : errno, EINPROGRESS;

        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsWsConnect");
        auto engine = state.engine;

        if (args.length < 1)
            return engine.throwTypeError("WebSocket: requires a URL argument");
        auto urlStr = engine.extractString(args[0]);

        if (state.permissions !is null && !state.permissions.check(Permission.net, urlStr))
            return engine.throwTypeError("WebSocket: requires --allow-net");

        string host;
        ushort port = WS_DEFAULT_PORT;
        string path = "/";
        if (!parseWsUrl(urlStr, host, port, path))
            return engine.throwTypeError("WebSocket: invalid ws:// URL");

        uint addr = resolveHost(host);
        if (addr == 0)
            return engine.throwTypeError("WebSocket: cannot resolve host");

        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0)
            return engine.throwTypeError("WebSocket: socket() failed");

        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);

        sockaddr_in saddr;
        memset(&saddr, 0, saddr.sizeof);
        saddr.sin_family = AF_INET;
        saddr.sin_port = htons(port);
        saddr.sin_addr.s_addr = addr;

        int ret = connect(fd, cast(sockaddr*)&saddr, saddr.sizeof);
        if (ret < 0 && errno != EINPROGRESS)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            return engine.throwTypeError("WebSocket: connect() failed");
        }

        int cid = nextWsConnId++;
        try
        {
            WsConnState conn;
            conn.engine = engine;
            conn.fd = fd;
            conn.state = WsState.connecting;
            conn.isMasked = true;
            wsConns ~= conn;
        }
        catch (Throwable)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            return engine.throwTypeError("WebSocket: out of memory");
        }

        version (linux)
        {
            ensureWsPoller();
            gWsPoller.watch(fd, true, true);
        }

        sendClientHandshake(fd, host, port, path);
        auto obj = makeWsClientObj(engine, cid);
        return obj;
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.throwTypeError("WebSocket not supported on this platform");
    }
}

JSHandle makeWsClientObj(IJSEngine engine, int cid) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeWsClientObj");
    ensureWsFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__wcid", engine.newInt(cid));
    engine.setProperty(obj, "on", engine.dupValue(_wsClientOn));
    engine.setProperty(obj, "send", engine.dupValue(_wsClientSend));
    engine.setProperty(obj, "close", engine.dupValue(_wsClientClose));
    engine.setProperty(obj, "readyState", engine.newInt(0));
    return obj;
}

JSHandle jsWsClientOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsClientOn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsWsClientOn");
    auto engine = state.engine;
    if (args.length < 2 || !engine.isFunction(args[1])) return engine.dupValue(thisVal);

    auto idProp = engine.getProperty(thisVal, "__wcid");
    int cid = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (cid < 0 || cid >= cast(int) wsConns.length) return engine.dupValue(thisVal);

    auto conn = &wsConns[cid];
    auto ev = engine.extractString(args[0]);

    if (ev == "open")
    {
        if (conn.hasOnopen) engine.freeValue(conn.onopen);
        conn.onopen = engine.dupValue(args[1]);
        conn.hasOnopen = true;
    }
    else if (ev == "message")
    {
        if (conn.hasOnmessage) engine.freeValue(conn.onmessage);
        conn.onmessage = engine.dupValue(args[1]);
        conn.hasOnmessage = true;
    }
    else if (ev == "close")
    {
        if (conn.hasOnclose) engine.freeValue(conn.onclose);
        conn.onclose = engine.dupValue(args[1]);
        conn.hasOnclose = true;
    }
    else if (ev == "error")
    {
        if (conn.hasOnerror) engine.freeValue(conn.onerror);
        conn.onerror = engine.dupValue(args[1]);
        conn.hasOnerror = true;
    }
    return engine.dupValue(thisVal);
}

JSHandle jsWsClientSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsClientSend");
    version (Posix)
    {
        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsWsClientSend");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__wcid");
        int cid = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (cid < 0 || cid >= cast(int) wsConns.length)
            return engine.throwTypeError("WebSocket.send: invalid connection");

        auto conn = &wsConns[cid];
        if (conn.state != WsState.open)
            return engine.throwTypeError("WebSocket is not open");
        if (args.length < 1)
            return engine.newUndefined();

        auto data = engine.extractString(args[0]);
        auto frame = buildWsFrame(WsOpcode.text, cast(const(ubyte)[]) data, conn.isMasked);
        sendRawBytes(conn.fd, frame);
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

JSHandle jsWsClientClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsWsClientClose");
    version (Posix)
    {
        auto state = cast(DunState*) ctx;
        assert(state !is null, "Null DunState in jsWsClientClose");
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__wcid");
        int cid = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (cid < 0 || cid >= cast(int) wsConns.length)
            return engine.newUndefined();

        auto conn = &wsConns[cid];
        if (conn.state == WsState.closed) return engine.newUndefined();

        ushort code = WS_CLOSE_NORMAL;
        string reason = "";
        if (args.length >= 1 && engine.isNumber(args[0]))
            code = cast(ushort) engine.extractInt(args[0]);
        if (args.length >= 2 && engine.isString(args[1]))
            reason = engine.extractString(args[1]);

        // Build close frame payload: 2-byte code + reason
        ubyte[] payload;
        payload ~= cast(ubyte)(code >> 8);
        payload ~= cast(ubyte)(code & 0xFF);
        if (reason.length > 0)
            payload ~= cast(const(ubyte)[]) reason;

        auto frame = buildWsFrame(WsOpcode.close, payload, conn.isMasked);
        sendRawBytes(conn.fd, frame);
        conn.state = WsState.closing;
        return engine.newUndefined();
    }
    else
    {
        auto state = cast(DunState*) ctx;
        return state.engine.newUndefined();
    }
}

// --- Server-side connection object (unmasked sends) ---

JSHandle makeWsServerConnObj(IJSEngine engine, int cid) @trusted
{
    assert(engine !is null, "Null IJSEngine in makeWsServerConnObj");
    ensureWsFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__wcid", engine.newInt(cid));
    engine.setProperty(obj, "on", engine.dupValue(_wsClientOn));
    engine.setProperty(obj, "send", engine.dupValue(_wsClientSend));
    engine.setProperty(obj, "close", engine.dupValue(_wsClientClose));
    return obj;
}

// --- I/O polling ---

public void pollWsIO() nothrow @trusted
{
    version (linux)
    {
        ensureWsPoller();
        IOEvent[IO_POLL_BATCH_SIZE] evBuf;
        auto events = gWsPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            foreach (i, ref srv; wsServers)
                if (srv.active && srv.listenFd == ev.fd && ev.readable)
                    acceptWsConnection(cast(int) i);
            foreach (i, ref conn; wsConns)
                if (conn.state != WsState.closed && conn.fd == ev.fd && ev.readable)
                    readWsData(cast(int) i);
        }
    }
}

public bool hasActiveWsIO() @safe nothrow
{
    foreach (ref s; wsServers) if (s.active) return true;
    foreach (ref c; wsConns) if (c.state != WsState.closed) return true;
    return false;
}

// --- Accept + handshake ---

void acceptWsConnection(int srvId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : accept;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (srvId < 0 || srvId >= cast(int) wsServers.length) return;
        auto srv = &wsServers[srvId];

        while (true)
        {
            int fd = accept(srv.listenFd, null, null);
            if (fd < 0) { if (errno == EAGAIN || errno == EWOULDBLOCK) break; break; }

            int fl = fcntl(fd, F_GETFL, 0);
            fcntl(fd, F_SETFL, fl | O_NONBLOCK);

            int cid = nextWsConnId++;
            try
            {
                WsConnState conn;
                conn.engine = srv.engine;
                conn.fd = fd;
                conn.state = WsState.connecting;
                conn.isMasked = false;
                conn.serverId = srvId;
                wsConns ~= conn;
            }
            catch (Throwable)
            {
                import core.sys.posix.unistd : close;
                close(fd);
                continue;
            }
            version (linux) gWsPoller.watch(fd, true, false);
        }
    }
}

void readWsData(int cid) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.unistd : read;

        if (cid < 0 || cid >= cast(int) wsConns.length) return;
        auto conn = &wsConns[cid];
        if (conn.state == WsState.closed || conn.fd < 0) return;

        while (conn.bufLen < MAX_BUF)
        {
            auto n = read(conn.fd, conn.buf.ptr + conn.bufLen, MAX_BUF - conn.bufLen);
            if (n <= 0) break;
            conn.bufLen += n;
        }

        if (!conn.handshakeDone)
        {
            handleHandshake(conn, cid);
            return;
        }

        processFrames(conn, cid);
    }
}

void handleHandshake(WsConnState* conn, int cid) nothrow @trusted
{
    assert(conn !is null, "Null WsConnState in handleHandshake");

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

    auto headerText = conn.buf[0 .. sepPos].idup;

    if (conn.serverId >= 0)
    {
        // Server side: parse client's Sec-WebSocket-Key and send accept response
        string wsKey = extractHeader(headerText, "sec-websocket-key");
        if (wsKey.length == 0) { closeConn(conn); return; }

        try
        {
            auto acceptKey = computeAcceptKey(wsKey);
            string resp = "HTTP/1.1 101 Switching Protocols\r\n"
                ~ "Upgrade: websocket\r\n"
                ~ "Connection: Upgrade\r\n"
                ~ "Sec-WebSocket-Accept: " ~ acceptKey ~ "\r\n"
                ~ "\r\n";
            sendRawBytes(conn.fd, cast(const(ubyte)[]) resp);
        }
        catch (Exception) { closeConn(conn); return; }

        conn.handshakeDone = true;
        conn.state = WsState.open;

        // Shift remaining data past the handshake
        size_t consumed = sepPos + 4;
        if (consumed < conn.bufLen)
        {
            for (size_t i = 0; i < conn.bufLen - consumed; i++)
                conn.buf[i] = conn.buf[consumed + i];
            conn.bufLen -= consumed;
        }
        else
        {
            conn.bufLen = 0;
        }

        // Fire 'connection' callback on server
        if (conn.serverId >= 0 && conn.serverId < cast(int) wsServers.length)
        {
            auto srv = &wsServers[conn.serverId];
            if (srv.hasCb)
            {
                try
                {
                    auto wsObj = makeWsServerConnObj(srv.engine, cid);
                    JSHandle[1] cbArgs = [wsObj];
                    pushAgnosticPending(srv.engine, srv.connectionCb, cbArgs[]);
                    srv.engine.freeValue(wsObj);
                }
                catch (Throwable) {}
            }
        }
    }
    else
    {
        // Client side: verify server's 101 response
        bool valid = false;
        try
        {
            import std.string : indexOf;
            if (headerText.indexOf("101") >= 0)
                valid = true;
        }
        catch (Exception) {}

        if (!valid) { closeConn(conn); return; }

        conn.handshakeDone = true;
        conn.state = WsState.open;

        size_t consumed = sepPos + 4;
        if (consumed < conn.bufLen)
        {
            for (size_t i = 0; i < conn.bufLen - consumed; i++)
                conn.buf[i] = conn.buf[consumed + i];
            conn.bufLen -= consumed;
        }
        else
        {
            conn.bufLen = 0;
        }

        if (conn.hasOnopen)
        {
            try
            {
                JSHandle[0] noArgs;
                pushAgnosticPending(conn.engine, conn.onopen, noArgs[]);
            }
            catch (Throwable) {}
        }
    }
}

void processFrames(WsConnState* conn, int cid) nothrow @trusted
{
    assert(conn !is null, "Null WsConnState in processFrames");
    if (conn.bufLen == 0) return;

    while (conn.bufLen > 0)
    {
        auto result = parseWsFrame(cast(const(ubyte)[]) conn.buf[0 .. conn.bufLen]);
        if (!result.valid) break;

        auto frame = result.frame;

        if (frame.opcode == WsOpcode.text || frame.opcode == WsOpcode.binary)
        {
            if (conn.hasOnmessage)
            {
                try
                {
                    auto msgStr = conn.engine.newString(cast(string) frame.payload.idup);
                    JSHandle[1] msgArgs = [msgStr];
                    pushAgnosticPending(conn.engine, conn.onmessage, msgArgs[]);
                    conn.engine.freeValue(msgStr);
                }
                catch (Throwable) {}
            }
        }
        else if (frame.opcode == WsOpcode.ping)
        {
            try
            {
                auto pong = buildWsFrame(WsOpcode.pong, frame.payload, conn.isMasked);
                sendRawBytes(conn.fd, pong);
            }
            catch (Throwable) {}
        }
        else if (frame.opcode == WsOpcode.close)
        {
            if (conn.state != WsState.closing)
            {
                try
                {
                    auto closeFrame = buildWsFrame(WsOpcode.close, frame.payload, conn.isMasked);
                    sendRawBytes(conn.fd, closeFrame);
                }
                catch (Throwable) {}
            }
            conn.state = WsState.closed;
            if (conn.hasOnclose)
            {
                try
                {
                    JSHandle[0] noArgs;
                    pushAgnosticPending(conn.engine, conn.onclose, noArgs[]);
                }
                catch (Throwable) {}
            }
            closeConn(conn);
            break;
        }

        // Shift buffer past consumed frame
        size_t consumed = result.consumed;
        if (consumed < conn.bufLen)
        {
            for (size_t i = 0; i < conn.bufLen - consumed; i++)
                conn.buf[i] = conn.buf[consumed + i];
            conn.bufLen -= consumed;
        }
        else
        {
            conn.bufLen = 0;
        }
    }
}

// --- Helpers ---

void closeConn(WsConnState* conn) nothrow @trusted
{
    assert(conn !is null, "Null WsConnState in closeConn");
    version (Posix)
    {
        import core.sys.posix.unistd : close;

        // Free JS callback handles to prevent leaks
        if (conn.engine !is null)
        {
            try
            {
                if (conn.hasOnopen)  { conn.engine.freeValue(conn.onopen);    conn.hasOnopen = false; }
                if (conn.hasOnmessage) { conn.engine.freeValue(conn.onmessage); conn.hasOnmessage = false; }
                if (conn.hasOnclose) { conn.engine.freeValue(conn.onclose);   conn.hasOnclose = false; }
                if (conn.hasOnerror) { conn.engine.freeValue(conn.onerror);   conn.hasOnerror = false; }
            }
            catch (Throwable) {}
        }

        if (conn.fd >= 0)
        {
            version (linux) gWsPoller.unwatch(conn.fd);
            close(conn.fd);
            conn.fd = -1;
        }
        conn.state = WsState.closed;
    }
}

void sendRawBytes(int fd, const(ubyte)[] data) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.unistd : write;
        if (fd < 0 || data.length == 0) return;
        size_t sent = 0;
        while (sent < data.length)
        {
            auto n = write(fd, data.ptr + sent, data.length - sent);
            if (n <= 0) break;
            sent += n;
        }
    }
}

void sendClientHandshake(int fd, string host, ushort port, string path) nothrow @trusted
{
    try
    {
        import std.base64 : Base64;
        import std.conv : to;

        auto keyBytes = new ubyte[16];
        version (Posix)
        {
            import std.file : read;
            try { keyBytes = cast(ubyte[]) read("/dev/urandom", 16); } catch (Exception) {}
        }
        string wsKey = cast(string) Base64.encode(keyBytes);
        string portStr = port == WS_DEFAULT_PORT ? "" : ":" ~ port.to!string;

        string req = "GET " ~ path ~ " HTTP/1.1\r\n"
            ~ "Host: " ~ host ~ portStr ~ "\r\n"
            ~ "Upgrade: websocket\r\n"
            ~ "Connection: Upgrade\r\n"
            ~ "Sec-WebSocket-Key: " ~ wsKey ~ "\r\n"
            ~ "Sec-WebSocket-Version: 13\r\n"
            ~ "\r\n";
        sendRawBytes(fd, cast(const(ubyte)[]) req);
    }
    catch (Exception) {}
}

string extractHeader(const(char)[] text, string name) nothrow @trusted
{
    try
    {
        import std.string : toLower, strip, indexOf;
        size_t lineStart = 0;
        for (size_t i = 0; i <= text.length; i++)
        {
            if (i == text.length || text[i] == '\n')
            {
                size_t end = i;
                if (end > lineStart && text[end-1] == '\r') end--;
                auto line = cast(string) text[lineStart .. end].idup;
                lineStart = i + 1;

                auto col = line.indexOf(':');
                if (col >= 0 && line[0 .. col].toLower == name)
                    return line[col + 1 .. $].strip;
            }
        }
    }
    catch (Exception) {}
    return "";
}

bool parseWsUrl(string url, out string host, out ushort port, out string path) nothrow @trusted
{
    try
    {
        if (url.length < 5) return false;
        string rest;
        if (url.length >= 5 && url[0 .. 5] == "ws://")
            rest = url[5 .. $];
        else if (url.length >= 6 && url[0 .. 6] == "wss://")
        {
            rest = url[6 .. $];
            port = WS_DEFAULT_TLS_PORT;
        }
        else
            return false;

        import std.string : indexOf;
        auto slashIdx = rest.indexOf('/');
        string hostPort;
        if (slashIdx >= 0)
        {
            hostPort = rest[0 .. slashIdx];
            path = rest[slashIdx .. $];
        }
        else
        {
            hostPort = rest;
            path = "/";
        }

        auto colonIdx = hostPort.indexOf(':');
        if (colonIdx >= 0)
        {
            host = hostPort[0 .. colonIdx];
            import std.conv : to;
            port = hostPort[colonIdx + 1 .. $].to!ushort;
        }
        else
        {
            host = hostPort;
            if (port == 0) port = WS_DEFAULT_PORT;
        }
        return host.length > 0;
    }
    catch (Exception) { return false; }
}

uint resolveHost(string host) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.netdb : gethostbyname, hostent;
        import core.sys.posix.netinet.in_ : in_addr;
        import std.string : toStringz;

        try
        {
            auto he = gethostbyname(toStringz(host));
            if (he is null || he.h_addr_list is null || he.h_addr_list[0] is null)
                return 0;
            return *(cast(uint*) he.h_addr_list[0]);
        }
        catch (Throwable) { return 0; }
    }
    else return 0;
}

import dun.security.permissions : Permission;

// --- Unit tests ---

version (DunTest):

unittest
{
    // Test: small text frame encoding
    auto frame = buildWsFrame(WsOpcode.text, cast(const(ubyte)[]) "hello", false);
    assert(frame.length == 7);
    assert(frame[0] == 0x81); // FIN + text opcode
    assert(frame[1] == 5);    // length 5, no mask
    assert(frame[2 .. 7] == cast(const(ubyte)[]) "hello");
}

unittest
{
    // Test: empty frame
    auto frame = buildWsFrame(WsOpcode.text, [], false);
    assert(frame.length == 2);
    assert(frame[0] == 0x81);
    assert(frame[1] == 0);
}

unittest
{
    // Test: close frame with code
    ubyte[] payload;
    payload ~= cast(ubyte)(WS_CLOSE_NORMAL >> 8);
    payload ~= cast(ubyte)(WS_CLOSE_NORMAL & 0xFF);
    auto frame = buildWsFrame(WsOpcode.close, payload, false);
    assert(frame[0] == 0x88); // FIN + close opcode
    assert(frame[1] == 2);
}

unittest
{
    // Test: parse unmasked text frame
    ubyte[] raw = [0x81, 0x05, 'H', 'e', 'l', 'l', 'o'];
    auto result = parseWsFrame(raw);
    assert(result.valid);
    assert(result.frame.fin);
    assert(result.frame.opcode == WsOpcode.text);
    assert(!result.frame.masked);
    assert(result.frame.payload == cast(const(ubyte)[]) "Hello");
    assert(result.consumed == 7);
}

unittest
{
    // Test: parse masked frame
    ubyte[4] key = [0x37, 0xfa, 0x21, 0x3d];
    ubyte[] raw = [0x81, 0x85]; // FIN + text, masked + len 5
    raw ~= key[];
    // "Hello" XOR'd with mask key
    ubyte[] masked;
    auto plain = cast(const(ubyte)[]) "Hello";
    foreach (i, b; plain) masked ~= cast(ubyte)(b ^ key[i & 3]);
    raw ~= masked;

    auto result = parseWsFrame(raw);
    assert(result.valid);
    assert(result.frame.masked);
    assert(result.frame.payload == cast(const(ubyte)[]) "Hello");
    assert(result.consumed == 11);
}

unittest
{
    // Test: incomplete frame returns invalid
    ubyte[] raw = [0x81]; // only one byte
    auto result = parseWsFrame(raw);
    assert(!result.valid);
}

unittest
{
    // Test: ping frame parse
    ubyte[] raw = [0x89, 0x00]; // FIN + ping, no payload
    auto result = parseWsFrame(raw);
    assert(result.valid);
    assert(result.frame.opcode == WsOpcode.ping);
    assert(result.frame.payload.length == 0);
}

unittest
{
    // Test: medium length (126-byte) frame header
    auto payload = new ubyte[200];
    payload[] = 0x41; // fill with 'A'
    auto frame = buildWsFrame(WsOpcode.text, payload, false);
    assert(frame[0] == 0x81);
    assert(frame[1] == 126); // extended 16-bit length
    ushort len = cast(ushort)((frame[2] << 8) | frame[3]);
    assert(len == 200);
    assert(frame.length == 4 + 200);
}

unittest
{
    // Test: round-trip encode/decode
    auto original = cast(const(ubyte)[]) "WebSocket test data";
    auto encoded = buildWsFrame(WsOpcode.text, original, false);
    auto decoded = parseWsFrame(encoded);
    assert(decoded.valid);
    assert(decoded.frame.opcode == WsOpcode.text);
    assert(decoded.frame.fin);
    assert(decoded.frame.payload == original);
}

unittest
{
    // Test: computeAcceptKey with RFC 6455 example
    auto key = computeAcceptKey("dGhlIHNhbXBsZSBub25jZQ==");
    assert(key == "0DOmF4M+b6WMoAsaXo23NFWUrnI=", "Accept key mismatch: " ~ key);
}
