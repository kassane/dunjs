module dun.cli.inspector;

version (Posix):

import dun.engine.iface : IJSEngine;

private enum DEFAULT_INSPECTOR_PORT = 9229;
private enum RECV_BUF_SIZE = 4096;
private enum WS_FIN_TEXT = 0x81;
private enum WS_PAYLOAD_16BIT = 126;
private enum WS_PAYLOAD_64BIT = 127;
private enum WS_PAYLOAD_16BIT_MAX = 65536;

private __gshared bool gInspectorActive = false;
private __gshared int gInspectorFd = -1;
private __gshared int gClientFd = -1;
private __gshared ushort gInspectorPort = DEFAULT_INSPECTOR_PORT;
private __gshared IJSEngine gInspectorEngine;

bool isInspectorActive() nothrow @trusted
{
    return gInspectorActive;
}

void startInspector(IJSEngine engine, ushort port = DEFAULT_INSPECTOR_PORT) @trusted
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

    ubyte[RECV_BUF_SIZE] buf;
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

    ubyte[RECV_BUF_SIZE] buf;
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

        // Bucket 1: enable-style + ack-only methods that DevTools
        // sends at startup. We acknowledge with `{}` so the UI moves
        // on instead of hanging on a pending request.
        if (method == "Runtime.enable" || method == "Debugger.enable"
            || method == "Profiler.enable" || method == "HeapProfiler.enable"
            || method == "Console.enable" || method == "Network.enable"
            || method == "Page.enable" || method == "Inspector.enable"
            || method == "DOM.enable" || method == "CSS.enable"
            || method == "Log.enable" || method == "ServiceWorker.enable"
            || method == "Profiler.disable" || method == "HeapProfiler.disable"
            || method == "Debugger.disable" || method == "Runtime.disable"
            || method == "Debugger.setPauseOnExceptions"
            || method == "Debugger.setAsyncCallStackDepth"
            || method == "Debugger.setBlackboxPatterns"
            || method == "Debugger.setBlackboxExecutionContexts"
            || method == "Debugger.setSkipAllPauses"
            || method == "Runtime.setMaxCallStackSizeToCapture"
            || method == "Runtime.setAsyncCallStackDepth"
            || method == "Runtime.runIfWaitingForDebugger"
            || method == "Runtime.discardConsoleEntries"
            || method == "Runtime.releaseObject"
            || method == "Runtime.releaseObjectGroup"
            || method == "Target.setAutoAttach"
            || method == "Target.setDiscoverTargets"
            || method == "Profiler.setSamplingInterval"
            || method == "Page.setBypassCSP"
            || method == "Page.startScreencast"
            || method == "Page.stopScreencast")
        {
            sendCDPResponse(id, "{}");
        }
        else if (method == "Runtime.evaluate"
              || method == "Runtime.callFunctionOn")
        {
            // For callFunctionOn we wrap the expression in (function(){})()
            // so the function source executes with whatever 'arguments'
            // the DevTools sends. Best-effort approximation that handles
            // the common 'show me the value' use case from the console.
            string expr = "";
            if ("params" in j)
            {
                auto params = j["params"];
                if ("expression" in params)
                    expr = params["expression"].str;
                else if ("functionDeclaration" in params)
                    expr = "(" ~ params["functionDeclaration"].str ~ ")()";
            }

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
        else if (method == "Runtime.getProperties")
        {
            // Properties listing: return empty arrays. A real impl would
            // mirror engine.getProperty(handle, ...) for the object id
            // the client passed in, but we don't yet track those.
            sendCDPResponse(id, `{"result":[],"internalProperties":[]}`);
        }
        else if (method == "Runtime.compileScript")
        {
            sendCDPResponse(id, `{"scriptId":"1"}`);
        }
        else if (method == "Runtime.getHeapUsage")
        {
            // memoryUsage()-style numbers. Best-effort via D rt.
            import core.memory : GC;
            auto stats = GC.stats;
            import std.conv : to;
            sendCDPResponse(id,
                `{"usedSize":` ~ stats.usedSize.to!string
                ~ `,"totalSize":` ~ (stats.usedSize + stats.freeSize).to!string
                ~ `,"embedderHeapUsedSize":0,"backingStorageSize":0}`);
        }
        else if (method == "Debugger.setBreakpointByUrl"
              || method == "Debugger.setBreakpoint"
              || method == "Debugger.removeBreakpoint")
        {
            // We don't have a real debugger, but acknowledging the breakpoint
            // request lets DevTools' breakpoint UI render without errors.
            // Use a fixed phony breakpointId so removes ack cleanly too.
            sendCDPResponse(id, `{"breakpointId":"dun:bp:1","locations":[]}`);
        }
        else if (method == "Debugger.getScriptSource")
        {
            sendCDPResponse(id, `{"scriptSource":""}`);
        }
        else if (method == "HeapProfiler.takeHeapSnapshot"
              || method == "HeapProfiler.collectGarbage")
        {
            import core.memory : GC;
            try { GC.collect(); } catch (Exception) {}
            sendCDPResponse(id, "{}");
        }
        else if (method == "Profiler.start" || method == "Profiler.stop"
              || method == "Profiler.startTypeProfile"
              || method == "Profiler.stopTypeProfile")
        {
            sendCDPResponse(id, `{"profile":{"nodes":[],"startTime":0,"endTime":0,"samples":[],"timeDeltas":[]}}`);
        }
        else if (method == "Page.getResourceTree")
        {
            sendCDPResponse(id,
                `{"frameTree":{"frame":{"id":"dun","loaderId":"dun-loader","url":"file:///","mimeType":"text/javascript","securityOrigin":"","domainAndRegistry":""},"resources":[]}}`);
        }
        else if (method == "Target.getTargetInfo" || method == "Target.attachToTarget")
        {
            sendCDPResponse(id,
                `{"targetInfo":{"targetId":"dun","type":"node","title":"DunJS","url":"file:///","attached":true,"canAccessOpener":false}}`);
        }
        // Debugger evaluation (used by the Sources panel on a paused frame
        // and by hover-evaluate). Reuses the same engine.eval path as
        // Runtime.evaluate -- we don't track call frames, but evaluating
        // against the live global is what most "what's this variable" UI
        // gestures expect anyway.
        else if (method == "Debugger.evaluateOnCallFrame")
        {
            string expr = "";
            if ("params" in j && "expression" in j["params"])
                expr = j["params"]["expression"].str;
            string resultJson = `{"type":"undefined"}`;
            if (gInspectorEngine !is null && expr.length > 0)
            {
                auto r = gInspectorEngine.eval(expr, "<inspector>");
                if (!r.isError)
                {
                    import std.json : JSONValue;
                    auto val = gInspectorEngine.extractString(r.value);
                    resultJson = `{"type":"string","value":`
                        ~ JSONValue(val).toString() ~ `}`;
                    gInspectorEngine.freeValue(r.value);
                }
                else
                {
                    import std.json : JSONValue;
                    resultJson = `{"type":"object","subtype":"error","description":`
                        ~ JSONValue(r.errorMessage).toString() ~ `}`;
                    gInspectorEngine.freeValue(r.value);
                }
            }
            sendCDPResponse(id, `{"result":` ~ resultJson ~ `}`);
        }
        // Execution control. We don't have a paused state, so resume /
        // step are no-ops; acknowledging keeps the UI buttons responsive.
        else if (method == "Debugger.resume"
              || method == "Debugger.stepOver"
              || method == "Debugger.stepInto"
              || method == "Debugger.stepOut"
              || method == "Debugger.pause"
              || method == "Debugger.continueToLocation"
              || method == "Debugger.restartFrame")
        {
            sendCDPResponse(id, "{}");
        }
        // Top-level scope inspector. Stub list -- a real impl would walk
        // the global object via IJSEngine.
        else if (method == "Runtime.globalLexicalScopeNames")
        {
            sendCDPResponse(id, `{"names":[]}`);
        }
        else if (method == "Runtime.queryObjects")
        {
            sendCDPResponse(id, `{"objects":{"type":"object","subtype":"array","objectId":"dun:queryObjects:1","className":"Array","description":"Array(0)"}}`);
        }
        // Network / Page extras for the Sources panel.
        else if (method == "Network.setUserAgentOverride"
              || method == "Network.setCacheDisabled"
              || method == "Page.reload"
              || method == "Page.navigate"
              || method == "Page.setLifecycleEventsEnabled")
        {
            sendCDPResponse(id, "{}");
        }
        else
        {
            // Unknown methods get an empty success response. We log
            // them in verbose mode so adding handlers later is easy.
            sendCDPResponse(id, "{}");
        }
    }
    catch (Throwable) {}
}

/// Forward a `console.{log,info,warn,error,debug}` call from JS to a
/// connected DevTools session via `Runtime.consoleAPICalled` event.
/// Called from the runtime's console.* implementations; no-op if no
/// client is attached.
public void emitConsoleAPICalled(string level, string text) nothrow @trusted
{
    if (gClientFd < 0) return;
    try
    {
        import std.json : JSONValue;
        import std.conv : to;
        auto textJson = JSONValue(text).toString();
        auto event =
            `{"method":"Runtime.consoleAPICalled","params":{`
            ~ `"type":"` ~ level ~ `",`
            ~ `"args":[{"type":"string","value":` ~ textJson ~ `}],`
            ~ `"executionContextId":1,`
            ~ `"timestamp":` ~ (cast(double) (gMonotonicMs())).to!string
            ~ `,"stackTrace":{"callFrames":[]}}}`;
        sendWebSocketFrame(cast(ubyte[]) event.dup);
    }
    catch (Throwable) {}
}

/// Monotonic milliseconds for CDP event timestamps. nothrow so the
/// console hooks above stay nothrow.
private long gMonotonicMs() nothrow @trusted
{
    try
    {
        import core.time : MonoTime, msecs, Duration;
        return MonoTime.currTime.ticks;
    }
    catch (Exception) { return 0; }
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

    header[0] = WS_FIN_TEXT;
    if (payload.length < WS_PAYLOAD_16BIT)
    {
        header[1] = cast(ubyte) payload.length;
        headerLen = 2;
    }
    else if (payload.length < WS_PAYLOAD_16BIT_MAX)
    {
        header[1] = WS_PAYLOAD_16BIT;
        header[2] = cast(ubyte)(payload.length >> 8);
        header[3] = cast(ubyte)(payload.length & 0xFF);
        headerLen = 4;
    }
    else
    {
        header[1] = WS_PAYLOAD_64BIT;
        foreach (i; 0 .. 8)
            header[2 + i] = cast(ubyte)((payload.length >> ((7 - i) * 8)) & 0xFF);
        headerLen = 10;
    }

    send(gClientFd, header.ptr, headerLen, 0);
    if (payload.length > 0)
        send(gClientFd, payload.ptr, payload.length, 0);
}
