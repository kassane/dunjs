module dun.builtins.tls;

/++
 + `@trusted policy`: this file is the TLS layer over OpenSSL.
 + Every `@trusted` is one of:
 +
 +   1. OpenSSL FFI (SSL_CTX_new, SSL_new, SSL_set_fd, SSL_connect,
 +      SSL_read, SSL_write, SSL_free, …) — `@trusted` is the
 +      security signal. `dun.platform.openssl` is the @system
 +      bindings module.
 +   2. `setsockopt` / `fcntl` / socket fd operations on the
 +      underlying TCP socket — POSIX surface, same justification
 +      as `net.d`.
 +   3. `__gshared SSL_CTX* gClientCtx` initialized lazily under
 +      `gInitDone` flag, single-threaded init guarded by the
 +      engine's main-thread-only contract.
 +
 + RAII: `TlsSocket` struct is non-copyable (`@disable this(this)`)
 + and has a destructor that calls `SSL_free`. Matches the audit
 + pattern from Bun's @safe-rust review — manual SSL_free is
 + otherwise a frequent leak source.
 +/

version (Posix):

import dun.platform.openssl;

private __gshared SSL_CTX* gClientCtx;
private __gshared bool gInitDone;

void ensureTlsInit() @trusted nothrow @nogc
{
    if (gInitDone) return;
    OPENSSL_init_ssl(
        OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);

    gClientCtx = SSL_CTX_new(TLS_client_method());
    if (gClientCtx)
    {
        SSL_CTX_set_default_verify_paths(gClientCtx);
        SSL_CTX_set_verify(gClientCtx, SSL_VERIFY_PEER, null);
        SSL_CTX_ctrl(gClientCtx, SSL_CTRL_SET_MIN_PROTO_VERSION,
            TLS1_2_VERSION, null);
    }
    gInitDone = true;
}

struct TlsSocket
{
    SSL* ssl;
    int fd = -1;

    @disable this(this);

    bool connect(int sockFd, const(char)* hostname) @trusted nothrow @nogc
    {
        ensureTlsInit();
        if (!gClientCtx) return false;

        ssl = SSL_new(gClientCtx);
        if (!ssl) return false;
        fd = sockFd;

        SSL_set_fd(ssl, fd);

        // SNI
        SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME,
            TLSEXT_NAMETYPE_host_name, cast(void*) hostname);

        // hostname verification (OpenSSL 1.1+)
        SSL_set1_host(ssl, hostname);

        ERR_clear_error();
        int ret = SSL_connect(ssl);
        return ret == 1;
    }

    int read(void* buf, int len) @trusted nothrow @nogc
    {
        if (!ssl) return -1;
        return SSL_read(ssl, buf, len);
    }

    int write(const(void)* buf, int len) @trusted nothrow @nogc
    {
        if (!ssl) return -1;
        return SSL_write(ssl, buf, len);
    }

    void close() @trusted nothrow @nogc
    {
        if (ssl)
        {
            SSL_shutdown(ssl);
            SSL_free(ssl);
            ssl = null;
        }
        if (fd >= 0)
        {
            import core.sys.posix.unistd : posixClose = close;
            posixClose(fd);
            fd = -1;
        }
    }

    ~this() @trusted nothrow @nogc
    {
        close();
    }
}

string tlsLastError() @trusted nothrow
{
    auto e = ERR_peek_last_error();
    if (e == 0) return "unknown TLS error";
    auto s = ERR_reason_error_string(e);
    if (!s) return "unknown TLS error";
    size_t len = 0;
    while (s[len] != 0) len++;
    try { return (cast(const(char)*) s)[0 .. len].idup; }
    catch (Throwable) { return "unknown TLS error"; }
}

// ============================================================================
// TLS JavaScript module registration (engine-agnostic)
// ============================================================================

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.loop.agnostic_pending : pushAgnosticPending;
import dun.declarations : HTTPS_DEFAULT_PORT_NUM;

private enum : size_t {
    TLS_READ_BUF_SIZE  = 8192,
    TLS_MAX_CONNS      = 1024,
}

void registerTlsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerTlsModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "connect", engine.newFunction(&jsTlsConnect, "connect", 2));
    engine.setProperty(obj, "getCiphers", engine.newFunction(&jsTlsGetCiphers, "getCiphers", 0));

    // Evaluate the JS extension for TLSSocket, createServer stub, and constants
    auto extResult = engine.eval(tlsExtensionSource(), "<tls-ext>");
    if (!extResult.isError)
    {
        foreach (name; ["TLSSocket", "createServer",
                        "DEFAULT_MIN_VERSION", "DEFAULT_MAX_VERSION",
                        "DEFAULT_CIPHERS"])
        {
            auto prop = engine.getProperty(extResult.value, name);
            engine.setProperty(obj, name, prop);
        }
    }
    engine.freeValue(extResult.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_tls__", obj);
    engine.setProperty(global, "__dun_tls_write__",
        engine.newFunction(&jsTlsWrite, "__dun_tls_write__", 2));
    engine.setProperty(global, "__dun_tls_end__",
        engine.newFunction(&jsTlsEnd, "__dun_tls_end__", 1));
    engine.setProperty(global, "__dun_tls_on__",
        engine.newFunction(&jsTlsOn, "__dun_tls_on__", 3));
    engine.setProperty(global, "__dun_tls_destroy__",
        engine.newFunction(&jsTlsDestroy, "__dun_tls_destroy__", 1));
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
        auto m = JS_NewCModule(ctx, "dun:tls", &tlsModuleInit);
        if (m is null) return;
        foreach (name; ["connect", "getCiphers", "TLSSocket", "createServer",
                        "DEFAULT_MIN_VERSION", "DEFAULT_MAX_VERSION",
                        "DEFAULT_CIPHERS"])
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int tlsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in tlsModuleInit");
        assert(m !is null, "Null JSModuleDef in tlsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto tlsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_tls__");
        foreach (name; ["connect", "getCiphers", "TLSSocket", "createServer",
                        "DEFAULT_MIN_VERSION", "DEFAULT_MAX_VERSION",
                        "DEFAULT_CIPHERS"])
        {
            auto fn = JS_GetPropertyStr(ctx, tlsObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", tlsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

// --- TLS connection state ---

struct TlsConnState
{
    IJSEngine engine;
    SSL* ssl;
    int fd = -1;
    bool closed;
    bool eventsSet;
    JSHandle onData;
    JSHandle onEnd;
    JSHandle onClose;
    JSHandle onError;
    JSHandle onSecureConnect;
    bool hasSecureConnectCb;
    ubyte[TLS_READ_BUF_SIZE] readBuf;
}

__gshared TlsConnState[] tlsConns;
__gshared int nextTlsId = 0;

version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    private IOPoller gTlsPoller;
    private bool gTlsPollerInited = false;

    private void ensureTlsPoller() nothrow @trusted
    {
        if (!gTlsPollerInited) { gTlsPoller.initialize(); gTlsPollerInited = true; }
    }
}

void registerTlsForPolling(int id) nothrow @trusted
{
    version (linux)
    {
        ensureTlsPoller();
        if (id >= 0 && id < cast(int) tlsConns.length && tlsConns[id].fd >= 0)
            gTlsPoller.watch(tlsConns[id].fd, true, false);
    }
}

void unregisterTlsFromPolling(int id) nothrow @trusted
{
    version (linux)
    {
        if (id >= 0 && id < cast(int) tlsConns.length && tlsConns[id].fd >= 0)
            gTlsPoller.unwatch(tlsConns[id].fd);
    }
}

// --- Public I/O polling (called by event loop) ---

public void pollTlsIO() nothrow @trusted
{
    version (linux)
    {
        enum IO_POLL_BATCH = 64;
        ensureTlsPoller();
        IOEvent[IO_POLL_BATCH] evBuf;
        auto events = gTlsPoller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            foreach (i, ref conn; tlsConns)
                if (!conn.closed && conn.fd == ev.fd && ev.readable)
                    readTlsData(cast(int) i);
        }
    }
}

public bool hasActiveTlsIO() @trusted nothrow
{
    foreach (ref c; tlsConns)
        if (!c.closed) return true;
    return false;
}

// --- TLS data reading ---

void readTlsData(int id) nothrow @trusted
{
    if (id < 0 || id >= cast(int) tlsConns.length) return;
    auto conn = &tlsConns[id];
    if (conn.closed || conn.ssl is null) return;

    auto n = SSL_read(conn.ssl, conn.readBuf.ptr, cast(int) conn.readBuf.length);
    if (n > 0)
    {
        try
        {
            if (conn.eventsSet && conn.engine.isFunction(conn.onData))
            {
                /* `newString` takes `scope const(char)[]` and copies bytes
                   into engine-owned storage. The previous `.idup` was a
                   per-read GC allocation on the hot TLS data path. */
                auto jsData = conn.engine.newString(
                    cast(const(char)[]) conn.readBuf[0 .. n]);
                JSHandle[1] callArgs = [jsData];
                pushAgnosticPending(conn.engine, conn.onData, callArgs[]);
                conn.engine.freeValue(jsData);
            }
        }
        catch (Throwable) {}
    }
    else if (n == 0)
    {
        closeTlsConn(id);
    }
    else
    {
        auto err = SSL_get_error(conn.ssl, n);
        if (err != SSL_ERROR_WANT_READ && err != SSL_ERROR_WANT_WRITE)
            closeTlsConn(id);
    }
}

void closeTlsConn(int id) nothrow @trusted
{
    if (id < 0 || id >= cast(int) tlsConns.length) return;
    auto conn = &tlsConns[id];
    if (conn.closed) return;
    conn.closed = true;
    unregisterTlsFromPolling(id);

    if (conn.ssl !is null)
    {
        SSL_shutdown(conn.ssl);
        SSL_free(conn.ssl);
        conn.ssl = null;
    }
    if (conn.fd >= 0)
    {
        import core.sys.posix.unistd : posixClose = close;
        posixClose(conn.fd);
        conn.fd = -1;
    }

    try
    {
        if (conn.eventsSet && conn.engine.isFunction(conn.onEnd))
        {
            JSHandle[0] noArgs;
            pushAgnosticPending(conn.engine, conn.onEnd, noArgs[]);
        }
        if (conn.eventsSet && conn.engine.isFunction(conn.onClose))
        {
            auto hadError = conn.engine.newBool(false);
            JSHandle[1] closeArgs = [hadError];
            pushAgnosticPending(conn.engine, conn.onClose, closeArgs[]);
            conn.engine.freeValue(hadError);
        }
    }
    catch (Throwable) {}

    freeTlsCallbacks(conn);
}

void freeTlsCallbacks(TlsConnState* conn) nothrow @trusted
{
    assert(conn !is null, "Null conn in freeTlsCallbacks");
    if (!conn.eventsSet) return;
    try
    {
        conn.engine.freeValue(conn.onData);
        conn.engine.freeValue(conn.onEnd);
        conn.engine.freeValue(conn.onClose);
        conn.engine.freeValue(conn.onError);
        if (conn.hasSecureConnectCb)
            conn.engine.freeValue(conn.onSecureConnect);
    }
    catch (Throwable) {}
    conn.eventsSet = false;
    conn.hasSecureConnectCb = false;
}

// --- Native callback: tls.connect ---

JSHandle jsTlsConnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsConnect");
    assert(state.engine !is null, "Null engine in jsTlsConnect");
    auto engine = state.engine;

    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.netdb : getaddrinfo, addrinfo, freeaddrinfo;
    import core.stdc.string : memset;
    import std.string : toStringz;

    // Parse arguments: tls.connect(options[, callback]) or tls.connect(port[, host[, callback]])
    int port = HTTPS_DEFAULT_PORT_NUM;
    string host = "localhost";
    string servername;
    bool rejectUnauthorized = true;
    JSHandle connectCb;
    bool hasCb = false;

    if (args.length >= 1 && engine.isObject(args[0]))
    {
        auto opts = args[0];

        auto portProp = engine.getProperty(opts, "port");
        if (engine.isNumber(portProp))
            port = engine.extractInt(portProp);
        engine.freeValue(portProp);

        auto hostProp = engine.getProperty(opts, "host");
        if (engine.isString(hostProp))
            host = engine.extractString(hostProp);
        engine.freeValue(hostProp);

        auto snProp = engine.getProperty(opts, "servername");
        if (engine.isString(snProp))
            servername = engine.extractString(snProp);
        engine.freeValue(snProp);

        auto rejProp = engine.getProperty(opts, "rejectUnauthorized");
        if (!engine.isUndefined(rejProp))
            rejectUnauthorized = engine.extractInt(rejProp) != 0;
        engine.freeValue(rejProp);

        if (args.length >= 2 && engine.isFunction(args[1]))
        {
            connectCb = engine.dupValue(args[1]);
            hasCb = true;
        }
    }
    else if (args.length >= 1 && engine.isNumber(args[0]))
    {
        port = engine.extractInt(args[0]);
        if (args.length >= 2 && engine.isString(args[1]))
        {
            host = engine.extractString(args[1]);
            if (args.length >= 3 && engine.isFunction(args[2]))
            {
                connectCb = engine.dupValue(args[2]);
                hasCb = true;
            }
        }
        else if (args.length >= 2 && engine.isFunction(args[1]))
        {
            connectCb = engine.dupValue(args[1]);
            hasCb = true;
        }
    }

    if (servername.length == 0)
        servername = host;

    // Permission check
    import dun.security.permissions : Permission;
    if (state.permissions !is null)
    {
        bool netAllowed = false;
        try { netAllowed = state.permissions.check(Permission.net, host); }
        catch (Exception) {}
        if (!netAllowed)
        {
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError(
                "Requires net permission for " ~ host ~ " (use --allow-net)");
        }
    }

    // Create TCP socket
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
    {
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: socket() failed");
    }

    // Resolve and connect
    sockaddr_in addr;
    memset(&addr, 0, addr.sizeof);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cast(ushort) port);

    addrinfo hints;
    addrinfo* res;
    memset(&hints, 0, hints.sizeof);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host.toStringz, null, &hints, &res) != 0 || res is null)
    {
        import core.sys.posix.unistd : posixClose = close;
        posixClose(fd);
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: host resolution failed for " ~ host);
    }
    auto sin = cast(sockaddr_in*) res.ai_addr;
    addr.sin_addr = sin.sin_addr;
    freeaddrinfo(res);

    import core.sys.posix.sys.socket : connect;
    int r = connect(fd, cast(sockaddr*)&addr, addr.sizeof);
    if (r < 0)
    {
        import core.stdc.errno : errno, EINPROGRESS;
        if (errno != EINPROGRESS)
        {
            import core.sys.posix.unistd : posixClose = close;
            posixClose(fd);
            if (hasCb) engine.freeValue(connectCb);
            return engine.throwTypeError("tls.connect: TCP connect() failed");
        }
    }

    // TLS handshake
    ensureTlsInit();
    if (!gClientCtx)
    {
        import core.sys.posix.unistd : posixClose = close;
        posixClose(fd);
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: failed to initialize SSL context");
    }

    auto ssl = SSL_new(gClientCtx);
    if (ssl is null)
    {
        import core.sys.posix.unistd : posixClose = close;
        posixClose(fd);
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: SSL_new() failed");
    }

    SSL_set_fd(ssl, fd);

    // Set SNI hostname
    SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME,
        TLSEXT_NAMETYPE_host_name, cast(void*) servername.toStringz);

    if (rejectUnauthorized)
        SSL_set1_host(ssl, servername.toStringz);

    ERR_clear_error();
    int sslRet = SSL_connect(ssl);
    if (sslRet != 1)
    {
        string errMsg = tlsLastError();
        SSL_free(ssl);
        import core.sys.posix.unistd : posixClose = close;
        posixClose(fd);
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: TLS handshake failed: " ~ errMsg);
    }

    // Set non-blocking after handshake completes
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    // Store connection state
    assert(nextTlsId < TLS_MAX_CONNS, "TLS connection limit reached");
    int id = nextTlsId++;
    try
    {
        TlsConnState conn;
        conn.engine = engine;
        conn.ssl = ssl;
        conn.fd = fd;
        if (hasCb)
        {
            conn.onSecureConnect = connectCb;
            conn.hasSecureConnectCb = true;
        }
        tlsConns ~= conn;
    }
    catch (Throwable)
    {
        SSL_shutdown(ssl);
        SSL_free(ssl);
        import core.sys.posix.unistd : posixClose = close;
        posixClose(fd);
        if (hasCb) engine.freeValue(connectCb);
        return engine.throwTypeError("tls.connect: out of memory");
    }

    registerTlsForPolling(id);

    // Build the JS TLSSocket-like object via the extension
    auto global = engine.getGlobal();
    auto makeFn = engine.getProperty(global, "__dun_make_tls_socket__");
    engine.freeValue(global);

    JSHandle sockObj;
    if (engine.isFunction(makeFn))
    {
        auto idVal = engine.newInt(id);
        auto hostVal = engine.newString(host);
        auto portVal = engine.newInt(port);
        auto authVal = engine.newBool(true); // authorized (handshake passed)
        JSHandle[4] makeArgs = [idVal, hostVal, portVal, authVal];
        sockObj = engine.callFunction(makeFn, engine.newUndefined(), makeArgs[]);
        engine.freeValue(idVal);
        engine.freeValue(hostVal);
        engine.freeValue(portVal);
        engine.freeValue(authVal);
    }
    else
    {
        // Fallback: just create a basic object
        sockObj = engine.newObject();
        engine.setProperty(sockObj, "__tlsId", engine.newInt(id));
    }
    engine.freeValue(makeFn);

    // Schedule 'secureConnect' callback
    if (hasCb)
    {
        auto connRef = &tlsConns[id];
        JSHandle[0] noArgs;
        pushAgnosticPending(engine, connRef.onSecureConnect, noArgs[]);
    }

    return sockObj;
}

// --- Native callback: __dun_tls_write__ ---

JSHandle jsTlsWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsWrite");
    auto engine = state.engine;

    if (args.length < 2) return engine.newBool(false);

    auto idVal = engine.extractInt(args[0]);
    if (idVal < 0 || idVal >= cast(int) tlsConns.length) return engine.newBool(false);

    auto conn = &tlsConns[idVal];
    if (conn.closed || conn.ssl is null) return engine.newBool(false);

    auto data = engine.extractString(args[1]);
    if (data.length == 0) return engine.newBool(true);

    size_t written = 0;
    while (written < data.length)
    {
        auto remaining = cast(int)(data.length - written);
        auto n = SSL_write(conn.ssl, data.ptr + written, remaining);
        if (n <= 0)
        {
            auto err = SSL_get_error(conn.ssl, n);
            if (err == SSL_ERROR_WANT_WRITE || err == SSL_ERROR_WANT_READ)
                continue;
            break;
        }
        written += n;
    }
    return engine.newBool(written == data.length);
}

// --- Native callback: __dun_tls_end__ ---

JSHandle jsTlsEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsEnd");
    auto engine = state.engine;

    if (args.length < 1) return engine.newUndefined();

    auto idVal = engine.extractInt(args[0]);
    closeTlsConn(idVal);
    return engine.newUndefined();
}

// --- Native callback: __dun_tls_destroy__ ---

JSHandle jsTlsDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsDestroy");
    auto engine = state.engine;

    if (args.length < 1) return engine.newUndefined();

    auto idVal = engine.extractInt(args[0]);
    if (idVal < 0 || idVal >= cast(int) tlsConns.length)
        return engine.newUndefined();

    auto conn = &tlsConns[idVal];
    if (conn.closed) return engine.newUndefined();
    conn.closed = true;
    unregisterTlsFromPolling(idVal);

    if (conn.ssl !is null)
    {
        SSL_free(conn.ssl); // skip shutdown for destroy()
        conn.ssl = null;
    }
    if (conn.fd >= 0)
    {
        import core.sys.posix.unistd : posixClose = close;
        posixClose(conn.fd);
        conn.fd = -1;
    }
    freeTlsCallbacks(conn);
    return engine.newUndefined();
}

// --- Native callback: __dun_tls_on__ ---

JSHandle jsTlsOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsOn");
    auto engine = state.engine;

    if (args.length < 3) return engine.newUndefined();

    auto idVal = engine.extractInt(args[0]);
    if (idVal < 0 || idVal >= cast(int) tlsConns.length)
        return engine.newUndefined();

    auto conn = &tlsConns[idVal];
    auto evName = engine.extractString(args[1]);

    if (engine.isFunction(args[2]))
    {
        if (evName == "data")
            conn.onData = engine.dupValue(args[2]);
        else if (evName == "end")
            conn.onEnd = engine.dupValue(args[2]);
        else if (evName == "close")
            conn.onClose = engine.dupValue(args[2]);
        else if (evName == "error")
            conn.onError = engine.dupValue(args[2]);
        conn.eventsSet = true;
    }
    return engine.newUndefined();
}

// --- Native callback: tls.getCiphers ---

JSHandle jsTlsGetCiphers(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsTlsGetCiphers");
    auto engine = state.engine;

    auto arr = engine.newArray();
    ensureTlsInit();

    if (gClientCtx)
    {
        auto tempSsl = SSL_new(gClientCtx);
        if (tempSsl !is null)
        {
            auto ciphers = SSL_get_ciphers(tempSsl);
            if (ciphers !is null)
            {
                int num = OPENSSL_sk_num(ciphers);
                foreach (i; 0 .. num)
                {
                    auto c = OPENSSL_sk_value(ciphers, i);
                    if (c !is null)
                    {
                        auto name = SSL_CIPHER_get_name(c);
                        if (name !is null)
                        {
                            // Convert to D string
                            size_t len = 0;
                            while (name[len] != 0) len++;
                            try
                            {
                                // Convert to lowercase as Node.js does
                                auto nameStr = (cast(const(char)*) name)[0 .. len].idup;
                                char[] lower;
                                lower.length = nameStr.length;
                                foreach (j, ch; nameStr)
                                    lower[j] = (ch >= 'A' && ch <= 'Z')
                                        ? cast(char)(ch + 32) : ch;
                                engine.setPropertyIndex(arr, cast(uint) i,
                                    engine.newString(cast(string) lower));
                            }
                            catch (Throwable) {}
                        }
                    }
                }
            }
            SSL_free(tempSsl);
        }
    }

    return arr;
}

// --- JS extension source ---

string tlsExtensionSource() pure @safe nothrow
{
    return `(function() {
  var result = {};

  result.DEFAULT_MIN_VERSION = 'TLSv1.2';
  result.DEFAULT_MAX_VERSION = 'TLSv1.3';
  result.DEFAULT_CIPHERS = 'DEFAULT:!aNULL:!eNULL:!MD5';

  // TLSSocket constructor
  function TLSSocket(socket, options) {
    if (!(this instanceof TLSSocket))
      return new TLSSocket(socket, options);
    this.encrypted = true;
    this.authorized = false;
    this.authorizationError = null;
    this.readable = true;
    this.writable = true;
    this._id = -1;
    this._listeners = {};
  }

  TLSSocket.prototype.on = function(event, cb) {
    if (!this._listeners) this._listeners = {};
    if (!this._listeners[event]) this._listeners[event] = [];
    this._listeners[event].push(cb);
    if (this._id >= 0 && typeof __dun_tls_on__ === 'function') {
      __dun_tls_on__(this._id, event, cb);
    }
    return this;
  };

  TLSSocket.prototype.once = function(event, cb) {
    var self = this;
    function wrapper() {
      self.removeListener(event, wrapper);
      cb.apply(this, arguments);
    }
    return this.on(event, wrapper);
  };

  TLSSocket.prototype.emit = function(event) {
    var listeners = this._listeners && this._listeners[event];
    if (!listeners) return false;
    var args = Array.prototype.slice.call(arguments, 1);
    for (var i = 0; i < listeners.length; i++) {
      try { listeners[i].apply(this, args); } catch(e) {}
    }
    return true;
  };

  TLSSocket.prototype.removeListener = function(event, cb) {
    var listeners = this._listeners && this._listeners[event];
    if (!listeners) return this;
    var idx = listeners.indexOf(cb);
    if (idx >= 0) listeners.splice(idx, 1);
    return this;
  };

  TLSSocket.prototype.removeAllListeners = function(event) {
    if (event) {
      if (this._listeners) this._listeners[event] = [];
    } else {
      this._listeners = {};
    }
    return this;
  };

  TLSSocket.prototype.write = function(data, encoding, callback) {
    if (typeof encoding === 'function') { callback = encoding; encoding = undefined; }
    if (this._id < 0) return false;
    var ok = __dun_tls_write__(this._id, String(data));
    if (typeof callback === 'function') {
      try { callback(ok ? null : new Error('write failed')); } catch(e) {}
    }
    return ok;
  };

  TLSSocket.prototype.end = function(data, encoding, callback) {
    if (typeof data === 'function') { callback = data; data = undefined; }
    if (typeof encoding === 'function') { callback = encoding; encoding = undefined; }
    if (data !== undefined && data !== null) this.write(data, encoding);
    this.writable = false;
    if (this._id >= 0) __dun_tls_end__(this._id);
    if (typeof callback === 'function') {
      try { callback(); } catch(e) {}
    }
    return this;
  };

  TLSSocket.prototype.destroy = function(err) {
    this.readable = false;
    this.writable = false;
    if (this._id >= 0) {
      __dun_tls_destroy__(this._id);
      this._id = -1;
    }
    return this;
  };

  TLSSocket.prototype.setEncoding = function(enc) { this._encoding = enc; return this; };
  TLSSocket.prototype.pause = function() { return this; };
  TLSSocket.prototype.resume = function() { return this; };
  TLSSocket.prototype.setTimeout = function(ms, cb) { return this; };
  TLSSocket.prototype.setNoDelay = function() { return this; };
  TLSSocket.prototype.setKeepAlive = function() { return this; };
  TLSSocket.prototype.address = function() { return { port: 0, family: 'IPv4', address: '0.0.0.0' }; };
  TLSSocket.prototype.getPeerCertificate = function() { return {}; };
  TLSSocket.prototype.getCipher = function() { return { name: 'unknown', version: 'TLSv1.3' }; };
  TLSSocket.prototype.getProtocol = function() { return 'TLSv1.3'; };

  result.TLSSocket = TLSSocket;

  // tls.createServer stub (real impl in https.d)
  result.createServer = function(options, listener) {
    throw new Error('tls.createServer: use https.createServer() for TLS servers');
  };

  // Factory for making socket objects from native code
  globalThis.__dun_make_tls_socket__ = function(id, host, port, authorized) {
    var sock = new TLSSocket();
    sock._id = id;
    sock.remoteAddress = host;
    sock.remotePort = port;
    sock.authorized = authorized;
    sock.encrypted = true;
    sock.readable = true;
    sock.writable = true;
    return sock;
  };

  return result;
})();`;
}
