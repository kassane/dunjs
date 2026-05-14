module dun.cli.inspector;

version (Posix):

import dun.engine.iface : IJSEngine;

private __gshared bool gInspectorActive = false;
private __gshared int gInspectorFd = -1;
private __gshared int gClientFd = -1;
private __gshared ushort gInspectorPort = 9229;
private __gshared IJSEngine gInspectorEngine;

bool isInspectorActive() nothrow @trusted
{
    return gInspectorActive;
}

void startInspector(IJSEngine engine, ushort port = 9229) @trusted
{
    assert(engine !is null);
    import core.sys.posix.sys.socket;
    import core.sys.posix.netinet.in_;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    import core.stdc.string : memset;
    import std.stdio : writefln;

    gInspectorEngine = engine;
    gInspectorPort = port;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;

    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, one.sizeof);

    sockaddr_in addr;
    memset(&addr, 0, addr.sizeof);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, cast(sockaddr*)&addr, addr.sizeof) < 0)
    {
        import core.sys.posix.unistd : close;
        close(fd);
        return;
    }

    if (listen(fd, 1) < 0)
    {
        import core.sys.posix.unistd : close;
        close(fd);
        return;
    }

    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);

    gInspectorFd = fd;
    gInspectorActive = true;

    import std.uuid : randomUUID;
    writefln("Debugger listening on ws://127.0.0.1:%d/%s", port, "dun-inspector");
    writefln("For help, see: https://nodejs.org/en/docs/guides/debugging-getting-started");
}

void pollInspector() nothrow @trusted
{
    if (!gInspectorActive || gInspectorFd < 0) return;

    import core.sys.posix.sys.socket : accept, sockaddr, send, recv;
    import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
    import core.stdc.string : memset;

    if (gClientFd < 0)
    {
        auto cfd = accept(gInspectorFd, null, null);
        if (cfd >= 0)
        {
            int fl = fcntl(cfd, F_GETFL, 0);
            fcntl(cfd, F_SETFL, fl | O_NONBLOCK);
            gClientFd = cfd;
            handleHttpUpgrade(cfd);
        }
        return;
    }

    ubyte[4096] buf;
    auto n = recv(gClientFd, buf.ptr, buf.length, 0);
    if (n > 0)
    {
        try
        {
            processWebSocketFrame(buf[0 .. n]);
        }
        catch (Throwable) {}
    }
    else if (n == 0)
    {
        import core.sys.posix.unistd : close;
        close(gClientFd);
        gClientFd = -1;
    }
}

void stopInspector() nothrow @trusted
{
    import core.sys.posix.unistd : close;
    if (gClientFd >= 0) { close(gClientFd); gClientFd = -1; }
    if (gInspectorFd >= 0) { close(gInspectorFd); gInspectorFd = -1; }
    gInspectorActive = false;
}

private:

void handleHttpUpgrade(int fd) nothrow @trusted
{
    import core.sys.posix.sys.socket : recv, send;

    ubyte[4096] buf;
    auto n = recv(fd, buf.ptr, buf.length, 0);
    if (n <= 0) return;

    try
    {
        auto request = cast(string) buf[0 .. n];
        string wsKey;
        foreach (line; splitLines(request))
        {
            if (line.length > 19 && line[0 .. 19] == "Sec-WebSocket-Key: ")
                wsKey = line[19 .. $];
        }

        if (wsKey.length == 0) return;

        import std.digest.sha : sha1Of;
        import std.base64 : Base64;
        auto combined = wsKey ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
        auto hash = sha1Of(cast(const(ubyte)[]) combined);
        auto accept = Base64.encode(hash[]);

        string response = "HTTP/1.1 101 Switching Protocols\r\n"
            ~ "Upgrade: websocket\r\n"
            ~ "Connection: Upgrade\r\n"
            ~ "Sec-WebSocket-Accept: " ~ cast(string) accept ~ "\r\n\r\n";

        send(fd, response.ptr, response.length, 0);
    }
    catch (Throwable) {}
}

string[] splitLines(string s) nothrow @trusted
{
    try
    {
        string[] lines;
        size_t start = 0;
        foreach (i, c; s)
        {
            if (c == '\n')
            {
                auto end = i > 0 && s[i-1] == '\r' ? i - 1 : i;
                lines ~= s[start .. end];
                start = i + 1;
            }
        }
        if (start < s.length)
            lines ~= s[start .. $];
        return lines;
    }
    catch (Throwable) { return null; }
}

void processWebSocketFrame(ubyte[] data) @trusted
{
    if (data.length < 2) return;

    bool masked = (data[1] & 0x80) != 0;
    size_t payloadLen = data[1] & 0x7F;
    size_t offset = 2;

    if (payloadLen == 126)
    {
        if (data.length < 4) return;
        payloadLen = (cast(size_t) data[2] << 8) | data[3];
        offset = 4;
    }
    else if (payloadLen == 127)
    {
        if (data.length < 10) return;
        offset = 10;
    }

    ubyte[4] mask;
    if (masked)
    {
        if (data.length < offset + 4) return;
        mask[0 .. 4] = data[offset .. offset + 4];
        offset += 4;
    }

    if (data.length < offset + payloadLen) return;
    auto payload = data[offset .. offset + payloadLen].dup;
    if (masked)
    {
        foreach (i, ref b; payload)
            b ^= mask[i & 3];
    }

    auto msg = cast(string) payload;
    handleCDPMessage(msg);
}

void handleCDPMessage(string msg) @trusted
{
    import std.json : parseJSON, JSONType;
    try
    {
        auto j = parseJSON(msg);
        auto method = j["method"].str;
        int id = 0;
        if ("id" in j && j["id"].type == JSONType.integer)
            id = cast(int) j["id"].integer;

        if (method == "Runtime.enable" || method == "Debugger.enable"
            || method == "Profiler.enable" || method == "HeapProfiler.enable")
        {
            sendCDPResponse(id, "{}");
        }
        else if (method == "Runtime.evaluate")
        {
            string expr = "";
            if ("params" in j && "expression" in j["params"])
                expr = j["params"]["expression"].str;

            string resultJson = `{"type":"undefined"}`;
            if (gInspectorEngine !is null && expr.length > 0)
            {
                auto result = gInspectorEngine.eval(expr, "<inspector>");
                if (!result.isError)
                {
                    auto val = gInspectorEngine.extractString(result.value);
                    import std.json : JSONValue;
                    auto jv = JSONValue(val);
                    resultJson = `{"type":"string","value":` ~ jv.toString() ~ `}`;
                    gInspectorEngine.freeValue(result.value);
                }
                else
                {
                    auto errMsg = result.errorMessage;
                    import std.json : JSONValue;
                    auto jv = JSONValue(errMsg);
                    resultJson = `{"type":"object","subtype":"error","description":` ~ jv.toString() ~ `}`;
                    gInspectorEngine.freeValue(result.value);
                }
            }
            sendCDPResponse(id, `{"result":` ~ resultJson ~ `}`);
        }
        else if (method == "Runtime.getProperties" || method == "Runtime.compileScript")
        {
            sendCDPResponse(id, "{}");
        }
        else
        {
            sendCDPResponse(id, "{}");
        }
    }
    catch (Throwable) {}
}

void sendCDPResponse(int id, string resultJson) nothrow @trusted
{
    if (gClientFd < 0) return;
    try
    {
        import std.conv : to;
        auto response = `{"id":` ~ id.to!string ~ `,"result":` ~ resultJson ~ `}`;
        sendWebSocketFrame(cast(ubyte[]) response.dup);
    }
    catch (Throwable) {}
}

void sendWebSocketFrame(ubyte[] payload) nothrow @trusted
{
    if (gClientFd < 0) return;
    import core.sys.posix.sys.socket : send;

    ubyte[10] header;
    size_t headerLen;

    header[0] = 0x81; // FIN + text
    if (payload.length < 126)
    {
        header[1] = cast(ubyte) payload.length;
        headerLen = 2;
    }
    else if (payload.length < 65536)
    {
        header[1] = 126;
        header[2] = cast(ubyte)(payload.length >> 8);
        header[3] = cast(ubyte)(payload.length & 0xFF);
        headerLen = 4;
    }
    else
    {
        header[1] = 127;
        foreach (i; 0 .. 8)
            header[2 + i] = cast(ubyte)((payload.length >> ((7 - i) * 8)) & 0xFF);
        headerLen = 10;
    }

    send(gClientFd, header.ptr, headerLen, 0);
    if (payload.length > 0)
        send(gClientFd, payload.ptr, payload.length, 0);
}
