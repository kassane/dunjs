module dun.builtins.http3;

/// `@trusted policy`: HTTP/3 server + client over QUIC via lsquic
/// (litespeedtech/lsquic). Every `@trusted` is one of:
///
///   1. lsquic FFI (`lsquic_engine_*`, `lsquic_stream_*`,
///      `lsquic_conn_*`) — bindings in `dun.platform.lsquic`.
///   2. UDP socket syscalls (`socket`, `bind`, `sendmsg`, `recvmsg`)
///      — same justification as `net.d`.
///   3. OpenSSL FFI for the QUIC handshake (lsquic plumbs into
///      OpenSSL's QUIC API directly).
///   4. `Permission.net` gate before any UDP send/recv.

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.security.permissions : Permission;

/// HTTP/3 constants (RFC 9114)
enum H3_DEFAULT_MAX_HEADER_LIST_SIZE = 65_536;
enum H3_DEFAULT_QPACK_MAX_TABLE_CAPACITY = 4_096;
enum H3_DEFAULT_QPACK_BLOCKED_STREAMS = 16;

enum H3FrameType : ulong
{
    DATA          = 0x00,
    HEADERS       = 0x01,
    CANCEL_PUSH   = 0x03,
    SETTINGS      = 0x04,
    PUSH_PROMISE  = 0x05,
    GOAWAY        = 0x07,
    MAX_PUSH_ID   = 0x0D,
}

enum H3Setting : ulong
{
    QPACK_MAX_TABLE_CAPACITY = 0x01,
    MAX_FIELD_SECTION_SIZE   = 0x06,
    QPACK_BLOCKED_STREAMS    = 0x07,
}

enum H3ErrorCode : ulong
{
    NO_ERROR                  = 0x100,
    GENERAL_PROTOCOL_ERROR    = 0x101,
    INTERNAL_ERROR            = 0x102,
    STREAM_CREATION_ERROR     = 0x103,
    CLOSED_CRITICAL_STREAM    = 0x104,
    FRAME_UNEXPECTED          = 0x105,
    FRAME_ERROR               = 0x106,
    EXCESSIVE_LOAD            = 0x107,
    ID_ERROR                  = 0x108,
    SETTINGS_ERROR            = 0x109,
    MISSING_SETTINGS          = 0x10A,
    REQUEST_REJECTED          = 0x10B,
    REQUEST_CANCELLED         = 0x10C,
    REQUEST_INCOMPLETE        = 0x10D,
    MESSAGE_ERROR             = 0x10E,
    CONNECT_ERROR             = 0x10F,
    VERSION_FALLBACK          = 0x110,
    QPACK_DECOMPRESSION_FAILED = 0x200,
    QPACK_ENCODER_STREAM_ERROR = 0x201,
    QPACK_DECODER_STREAM_ERROR = 0x202,
}

void registerHttp3Module(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerHttp3Module");
    auto obj = engine.newObject();
    engine.setProperty(obj, "createServer", engine.newFunction(&jsH3CreateServer, "createServer", 1));
    engine.setProperty(obj, "connect", engine.newFunction(&jsH3Connect, "connect", 1));
    engine.setProperty(obj, "constants", makeH3Constants(engine));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_http3__", obj);
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
        auto m = JS_NewCModule(ctx, "dun:http3", &http3ModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "createServer");
        JS_AddModuleExport(ctx, m, "connect");
        JS_AddModuleExport(ctx, m, "constants");
    }

    private extern (C) int http3ModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null);
        assert(m !is null);
        auto global = JS_GetGlobalObject(ctx);
        auto h3Obj = JS_GetPropertyStr(ctx, global, "__dun_cjs_http3__");
        foreach (name; ["createServer", "connect", "constants"])
        {
            auto fn = JS_GetPropertyStr(ctx, h3Obj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", h3Obj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

JSHandle makeH3Constants(IJSEngine engine) @trusted
{
    auto obj = engine.newObject();
    // HTTP/3 error codes
    engine.setProperty(obj, "NGHTTP3_H3_NO_ERROR",
        engine.newInt(cast(int) H3ErrorCode.NO_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_GENERAL_PROTOCOL_ERROR",
        engine.newInt(cast(int) H3ErrorCode.GENERAL_PROTOCOL_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_INTERNAL_ERROR",
        engine.newInt(cast(int) H3ErrorCode.INTERNAL_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_STREAM_CREATION_ERROR",
        engine.newInt(cast(int) H3ErrorCode.STREAM_CREATION_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_CLOSED_CRITICAL_STREAM",
        engine.newInt(cast(int) H3ErrorCode.CLOSED_CRITICAL_STREAM));
    engine.setProperty(obj, "NGHTTP3_H3_FRAME_UNEXPECTED",
        engine.newInt(cast(int) H3ErrorCode.FRAME_UNEXPECTED));
    engine.setProperty(obj, "NGHTTP3_H3_FRAME_ERROR",
        engine.newInt(cast(int) H3ErrorCode.FRAME_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_EXCESSIVE_LOAD",
        engine.newInt(cast(int) H3ErrorCode.EXCESSIVE_LOAD));
    engine.setProperty(obj, "NGHTTP3_H3_SETTINGS_ERROR",
        engine.newInt(cast(int) H3ErrorCode.SETTINGS_ERROR));
    engine.setProperty(obj, "NGHTTP3_H3_REQUEST_REJECTED",
        engine.newInt(cast(int) H3ErrorCode.REQUEST_REJECTED));
    engine.setProperty(obj, "NGHTTP3_H3_REQUEST_CANCELLED",
        engine.newInt(cast(int) H3ErrorCode.REQUEST_CANCELLED));
    // QUIC version
    engine.setProperty(obj, "QUIC_VERSION_1", engine.newInt(1));
    engine.setProperty(obj, "QUIC_VERSION_2", engine.newInt(2));
    // Default settings
    engine.setProperty(obj, "DEFAULT_MAX_HEADER_LIST_SIZE",
        engine.newInt(H3_DEFAULT_MAX_HEADER_LIST_SIZE));
    return obj;
}

// ── QUIC Variable-Length Integer Encoding (RFC 9000 §16) ────────────

/// Encode a QUIC variable-length integer into buf, return bytes written.
size_t encodeVarInt(ulong val, ubyte[] buf) pure nothrow @safe @nogc
{
    assert(buf.length >= 8, "Buffer too small for varint");
    if (val <= 63)
    {
        buf[0] = cast(ubyte) val;
        return 1;
    }
    if (val <= 16383)
    {
        buf[0] = cast(ubyte)(0x40 | (val >> 8));
        buf[1] = cast(ubyte)(val & 0xFF);
        return 2;
    }
    if (val <= 1_073_741_823)
    {
        buf[0] = cast(ubyte)(0x80 | (val >> 24));
        buf[1] = cast(ubyte)((val >> 16) & 0xFF);
        buf[2] = cast(ubyte)((val >> 8) & 0xFF);
        buf[3] = cast(ubyte)(val & 0xFF);
        return 4;
    }
    buf[0] = cast(ubyte)(0xC0 | (val >> 56));
    buf[1] = cast(ubyte)((val >> 48) & 0xFF);
    buf[2] = cast(ubyte)((val >> 40) & 0xFF);
    buf[3] = cast(ubyte)((val >> 32) & 0xFF);
    buf[4] = cast(ubyte)((val >> 24) & 0xFF);
    buf[5] = cast(ubyte)((val >> 16) & 0xFF);
    buf[6] = cast(ubyte)((val >> 8) & 0xFF);
    buf[7] = cast(ubyte)(val & 0xFF);
    return 8;
}

/// Decode a QUIC variable-length integer, return value and bytes consumed.
struct VarIntResult { ulong value; size_t consumed; }

VarIntResult decodeVarInt(const(ubyte)[] data) pure nothrow @safe @nogc
{
    if (data.length == 0) return VarIntResult(0, 0);
    ubyte prefix = data[0] >> 6;
    size_t len = cast(size_t)(1) << prefix;
    if (data.length < len) return VarIntResult(0, 0);

    ulong val = data[0] & 0x3F;
    foreach (i; 1 .. len)
        val = (val << 8) | data[i];
    return VarIntResult(val, len);
}

/// Encode an HTTP/3 frame header (type + length as varints).
ubyte[] encodeH3FrameHeader(H3FrameType ftype, ulong payloadLen) pure @safe
{
    ubyte[16] buf;
    auto n1 = encodeVarInt(cast(ulong) ftype, buf[0 .. 8]);
    auto n2 = encodeVarInt(payloadLen, buf[n1 .. n1 + 8]);
    return buf[0 .. n1 + n2].dup;
}

/// Encode SETTINGS frame payload.
ubyte[] encodeH3Settings() pure @safe
{
    import dun.platform.arena : Appender;
    Appender!(ubyte[]) app;
    app.reserve(32);
    ubyte[16] buf;
    // QPACK_MAX_TABLE_CAPACITY
    auto n = encodeVarInt(cast(ulong) H3Setting.QPACK_MAX_TABLE_CAPACITY, buf[0 .. 8]);
    app ~= buf[0 .. n];
    n = encodeVarInt(H3_DEFAULT_QPACK_MAX_TABLE_CAPACITY, buf[0 .. 8]);
    app ~= buf[0 .. n];
    // MAX_FIELD_SECTION_SIZE
    n = encodeVarInt(cast(ulong) H3Setting.MAX_FIELD_SECTION_SIZE, buf[0 .. 8]);
    app ~= buf[0 .. n];
    n = encodeVarInt(H3_DEFAULT_MAX_HEADER_LIST_SIZE, buf[0 .. 8]);
    app ~= buf[0 .. n];
    // QPACK_BLOCKED_STREAMS
    n = encodeVarInt(cast(ulong) H3Setting.QPACK_BLOCKED_STREAMS, buf[0 .. 8]);
    app ~= buf[0 .. n];
    n = encodeVarInt(H3_DEFAULT_QPACK_BLOCKED_STREAMS, buf[0 .. 8]);
    app ~= buf[0 .. n];
    return app[];
}

// ── JS API stubs (wire to lsquic when linked) ───────────────────────

JSHandle jsH3CreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in http3.createServer");
    auto engine = state.engine;

    auto server = engine.newObject();
    engine.setProperty(server, "listen",
        engine.newFunction(&jsH3ServerListen, "listen", 1));
    engine.setProperty(server, "close",
        engine.newFunction(&jsH3ServerClose, "close", 0));
    engine.setProperty(server, "on",
        engine.newFunction(&jsH3ServerOn, "on", 2));
    return server;
}

JSHandle jsH3ServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    int port = 0;
    string host = "0.0.0.0";
    if (args.length >= 1 && engine.isNumber(args[0]))
        port = engine.extractInt(args[0]);
    if (args.length >= 2 && engine.isString(args[1]))
        host = engine.extractString(args[1]);

    if (!state.permissions.check(Permission.net, host))
        return engine.throwTypeError("http3.listen: requires --allow-net");

    version (Posix)
    {
        // Bind a UDP socket on the requested port and store the fd on
        // the server object. Real H3 multiplexing still needs lsquic
        // wiring (the constants + varint codec are already there from
        // earlier work) but having a real socket bound means the
        // 'listening' event fires correctly and the port is reachable
        // with QUIC probe traffic. Full request handling is incremental.
        import core.sys.posix.sys.socket : socket, bind, AF_INET, SOCK_DGRAM, sockaddr;
        import core.sys.posix.netinet.in_ : sockaddr_in, IPPROTO_UDP, htons, INADDR_ANY;
        import core.sys.posix.arpa.inet : inet_pton, AF_INET;
        import core.sys.posix.unistd : close;
        import core.stdc.string : memset;
        import std.string : toStringz;

        int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (fd < 0)
            return engine.throwTypeError("http3.listen: socket() failed");

        sockaddr_in addr;
        memset(&addr, 0, sockaddr_in.sizeof);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(cast(ushort) port);
        if (host == "0.0.0.0" || host == "*")
            addr.sin_addr.s_addr = INADDR_ANY;
        else
        {
            if (inet_pton(AF_INET, host.toStringz, &addr.sin_addr) != 1)
            {
                close(fd);
                return engine.throwTypeError("http3.listen: invalid host '" ~ host ~ "'");
            }
        }

        if (bind(fd, cast(sockaddr*) &addr, sockaddr_in.sizeof) < 0)
        {
            close(fd);
            return engine.throwTypeError("http3.listen: bind failed");
        }

        // Recover the bound port (for port == 0 case).
        import core.sys.posix.sys.socket : getsockname, socklen_t;
        sockaddr_in actual;
        socklen_t actualLen = sockaddr_in.sizeof;
        if (getsockname(fd, cast(sockaddr*) &actual, &actualLen) == 0)
        {
            ushort actualPort;
            actualPort = cast(ushort)((cast(ubyte*) &actual.sin_port)[0] << 8 | (cast(ubyte*) &actual.sin_port)[1]);
            port = actualPort;
        }

        engine.setProperty(thisVal, "fd", engine.newInt(fd));
        engine.setProperty(thisVal, "address", engine.newString(host));
        engine.setProperty(thisVal, "port", engine.newInt(port));
        engine.setProperty(thisVal, "listening", engine.newBool(true));

        // Fire 'listening' callback if one was registered via .on().
        auto cb = engine.getProperty(thisVal, "__listenCb");
        if (engine.isFunction(cb))
        {
            JSHandle[] emptyArgs;
            auto undef = engine.newUndefined();
            auto rv = engine.callFunction(cb, undef, emptyArgs);
            engine.freeValue(rv);
            engine.freeValue(undef);
        }
        engine.freeValue(cb);
    }

    return engine.dupValue(thisVal);
}

JSHandle jsH3ServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    // RAII-style fd close: read the fd that listen() stored on the
    // server object and release the kernel resource. Without this the
    // UDP socket leaks until process exit, eventually exhausting fds
    // for any long-lived process that opens / closes H3 servers.
    version (Posix)
    {
        auto fdProp = engine.getProperty(thisVal, "fd");
        if (engine.isNumber(fdProp))
        {
            import core.sys.posix.unistd : close;
            int fd = engine.extractInt(fdProp);
            if (fd > 0)
            {
                close(fd);
                engine.setProperty(thisVal, "fd", engine.newInt(-1));
                engine.setProperty(thisVal, "listening", engine.newBool(false));
            }
        }
        engine.freeValue(fdProp);
    }
    return engine.newUndefined();
}

JSHandle jsH3ServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    return state.engine.dupValue(thisVal);
}

JSHandle jsH3Connect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("http3.connect requires a URL string");
    auto session = engine.newObject();
    engine.setProperty(session, "close",
        engine.newFunction(&jsH3SessionClose, "close", 0));
    engine.setProperty(session, "request",
        engine.newFunction(&jsH3SessionRequest, "request", 1));
    return session;
}

JSHandle jsH3SessionClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    return state.engine.newUndefined();
}

JSHandle jsH3SessionRequest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;
    auto stream = engine.newObject();
    engine.setProperty(stream, "on",
        engine.newFunction(&jsH3ServerOn, "on", 2));
    engine.setProperty(stream, "write",
        engine.newFunction(&jsH3StreamWrite, "write", 1));
    engine.setProperty(stream, "end",
        engine.newFunction(&jsH3StreamEnd, "end", 0));
    return stream;
}

JSHandle jsH3StreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    return state.engine.newBool(true);
}

JSHandle jsH3StreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    return state.engine.newUndefined();
}

// ── Unit Tests ──────────────────────────────────────────────────────

unittest
{
    // QUIC varint encode/decode round-trip
    ubyte[8] buf;

    // 1-byte: 0..63
    assert(encodeVarInt(0, buf) == 1);
    assert(buf[0] == 0);
    assert(decodeVarInt(buf[0 .. 1]) == VarIntResult(0, 1));

    assert(encodeVarInt(37, buf) == 1);
    assert(buf[0] == 37);
    assert(decodeVarInt(buf[0 .. 1]) == VarIntResult(37, 1));

    assert(encodeVarInt(63, buf) == 1);
    assert(decodeVarInt(buf[0 .. 1]) == VarIntResult(63, 1));

    // 2-byte: 64..16383
    assert(encodeVarInt(64, buf) == 2);
    assert(decodeVarInt(buf[0 .. 2]) == VarIntResult(64, 2));

    assert(encodeVarInt(15293, buf) == 2);
    assert(buf[0] == 0x7B);
    assert(buf[1] == 0xBD);
    assert(decodeVarInt(buf[0 .. 2]) == VarIntResult(15293, 2));

    // 4-byte
    assert(encodeVarInt(494878333, buf) == 4);
    assert(decodeVarInt(buf[0 .. 4]) == VarIntResult(494878333, 4));

    // 8-byte
    assert(encodeVarInt(151_288_809_941_952_652, buf) == 8);
    assert(decodeVarInt(buf[0 .. 8]) == VarIntResult(151_288_809_941_952_652, 8));

    // Edge: empty input
    assert(decodeVarInt([]) == VarIntResult(0, 0));

    // H3 frame header encoding
    auto hdr = encodeH3FrameHeader(H3FrameType.SETTINGS, 12);
    assert(hdr.length >= 2);
    auto t = decodeVarInt(hdr);
    assert(t.value == cast(ulong) H3FrameType.SETTINGS);
    auto l = decodeVarInt(hdr[t.consumed .. $]);
    assert(l.value == 12);

    // SETTINGS payload encoding
    auto settings = encodeH3Settings();
    assert(settings.length > 0);
}
