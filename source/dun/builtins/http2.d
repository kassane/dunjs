module dun.builtins.http2;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.loop.agnostic_pending : pushAgnosticPending;
import dun.platform.arena : Appender;
import dun.declarations : DEFAULT_LISTEN_BACKLOG;

void registerHttp2Module(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerHttp2Module");
    auto obj = engine.newObject();
    engine.setProperty(obj, "createServer", engine.newFunction(&jsHttp2CreateServer, "createServer", 1));
    engine.setProperty(obj, "createSecureServer", engine.newFunction(&jsHttp2CreateSecureServer, "createSecureServer", 1));
    engine.setProperty(obj, "connect", engine.newFunction(&jsHttp2Connect, "connect", 1));
    engine.setProperty(obj, "constants", makeHttp2Constants(engine));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_http2__", obj);
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
        auto m = JS_NewCModule(ctx, "dun:http2", &http2ModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "createServer");
        JS_AddModuleExport(ctx, m, "createSecureServer");
        JS_AddModuleExport(ctx, m, "connect");
        JS_AddModuleExport(ctx, m, "constants");
    }

    private extern (C) int http2ModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null);
        assert(m !is null);
        auto global = JS_GetGlobalObject(ctx);
        auto h2Obj = JS_GetPropertyStr(ctx, global, "__dun_cjs_http2__");
        foreach (name; ["createServer", "createSecureServer", "connect", "constants"])
        {
            auto fn = JS_GetPropertyStr(ctx, h2Obj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", h2Obj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

// ── HTTP/2 Frame Types (RFC 9113 §4) ────────────────────────────

enum H2FrameType : ubyte
{
    DATA          = 0x0,
    HEADERS       = 0x1,
    PRIORITY      = 0x2,
    RST_STREAM    = 0x3,
    SETTINGS      = 0x4,
    PUSH_PROMISE  = 0x5,
    PING          = 0x6,
    GOAWAY        = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION  = 0x9,
}

enum H2Flag : ubyte
{
    NONE        = 0x0,
    ACK         = 0x1,
    END_STREAM  = 0x1,
    END_HEADERS = 0x4,
    PADDED      = 0x8,
    PRIORITY    = 0x20,
}

enum H2Error : uint
{
    NO_ERROR            = 0x0,
    PROTOCOL_ERROR      = 0x1,
    INTERNAL_ERROR      = 0x2,
    FLOW_CONTROL_ERROR  = 0x3,
    SETTINGS_TIMEOUT    = 0x4,
    STREAM_CLOSED       = 0x5,
    FRAME_SIZE_ERROR    = 0x6,
    REFUSED_STREAM      = 0x7,
    CANCEL              = 0x8,
    COMPRESSION_ERROR   = 0x9,
    CONNECT_ERROR       = 0xa,
    ENHANCE_YOUR_CALM   = 0xb,
    INADEQUATE_SECURITY = 0xc,
    HTTP_1_1_REQUIRED   = 0xd,
}

enum H2Setting : ushort
{
    HEADER_TABLE_SIZE      = 0x1,
    ENABLE_PUSH            = 0x2,
    MAX_CONCURRENT_STREAMS = 0x3,
    INITIAL_WINDOW_SIZE    = 0x4,
    MAX_FRAME_SIZE         = 0x5,
    MAX_HEADER_LIST_SIZE   = 0x6,
}

enum H2_FRAME_HEADER_SIZE = 9;
enum H2_DEFAULT_WINDOW_SIZE = 65_535;
enum H2_DEFAULT_MAX_FRAME_SIZE = 16_384;
enum H2_DEFAULT_HEADER_TABLE_SIZE = 4_096;
enum H2_MAX_FRAME_SIZE = 16_777_215;
enum H2_CONNECTION_PREFACE_LEN = 24;
enum H2_SETTING_ENTRY_SIZE = 6;
enum H2_SETTINGS_COUNT = 3;
enum H2_DEFAULT_MAX_CONCURRENT_STREAMS = 100;
enum H2_DEFAULT_TLS_PORT = 443;
private alias H2_LISTEN_BACKLOG = DEFAULT_LISTEN_BACKLOG;
enum IO_POLL_BATCH_SIZE = 64;

enum : ubyte {
    HPACK_INDEXED_PREFIX     = 0x80,
    HPACK_INCR_INDEX_PREFIX  = 0x40,
    HPACK_NO_INDEX_PREFIX    = 0x00,
}
enum HPACK_INDEXED_PREFIX_BITS      = 7;
enum HPACK_INCR_INDEX_PREFIX_BITS   = 6;
enum HPACK_STRING_LENGTH_PREFIX_BITS = 7;
enum HPACK_AVG_ENTRY_SIZE = 32;

immutable ubyte[] H2_CLIENT_PREFACE = cast(immutable ubyte[])
    "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

// ── HTTP/2 Frame ─────────────────────────────────────────────────

struct H2Frame
{
    uint length;
    H2FrameType type;
    ubyte flags;
    uint streamId;
    const(ubyte)[] payload;
}

ubyte[H2_FRAME_HEADER_SIZE] encodeFrameHeader(uint length, H2FrameType type, ubyte flags, uint streamId)
    pure nothrow @safe @nogc
{
    ubyte[H2_FRAME_HEADER_SIZE] hdr;
    hdr[0] = cast(ubyte)((length >> 16) & 0xFF);
    hdr[1] = cast(ubyte)((length >> 8) & 0xFF);
    hdr[2] = cast(ubyte)(length & 0xFF);
    hdr[3] = cast(ubyte) type;
    hdr[4] = flags;
    uint sid = streamId & 0x7FFF_FFFF;
    hdr[5] = cast(ubyte)((sid >> 24) & 0xFF);
    hdr[6] = cast(ubyte)((sid >> 16) & 0xFF);
    hdr[7] = cast(ubyte)((sid >> 8) & 0xFF);
    hdr[8] = cast(ubyte)(sid & 0xFF);
    return hdr;
}

bool parseFrameHeader(scope const(ubyte)[] data, out H2Frame frame) pure nothrow @safe @nogc
{
    if (data.length < H2_FRAME_HEADER_SIZE) return false;
    frame.length = (cast(uint) data[0] << 16) | (cast(uint) data[1] << 8) | data[2];
    frame.type = cast(H2FrameType) data[3];
    frame.flags = data[4];
    frame.streamId = ((cast(uint) data[5] << 24) | (cast(uint) data[6] << 16)
        | (cast(uint) data[7] << 8) | data[8]) & 0x7FFF_FFFF;
    return true;
}

// ── HPACK (RFC 7541) ─────────────────────────────────────────────

struct HeaderField
{
    string name;
    string value;
}

// HPACK static table (RFC 7541 Appendix A)
immutable HeaderField[] HPACK_STATIC_TABLE = [
    HeaderField("", ""),  // index 0 unused
    HeaderField(":authority", ""),
    HeaderField(":method", "GET"),
    HeaderField(":method", "POST"),
    HeaderField(":path", "/"),
    HeaderField(":path", "/index.html"),
    HeaderField(":scheme", "http"),
    HeaderField(":scheme", "https"),
    HeaderField(":status", "200"),
    HeaderField(":status", "204"),
    HeaderField(":status", "206"),
    HeaderField(":status", "304"),
    HeaderField(":status", "400"),
    HeaderField(":status", "404"),
    HeaderField(":status", "500"),
    HeaderField("accept-charset", ""),
    HeaderField("accept-encoding", "gzip, deflate"),
    HeaderField("accept-language", ""),
    HeaderField("accept-ranges", ""),
    HeaderField("accept", ""),
    HeaderField("access-control-allow-origin", ""),
    HeaderField("age", ""),
    HeaderField("allow", ""),
    HeaderField("authorization", ""),
    HeaderField("cache-control", ""),
    HeaderField("content-disposition", ""),
    HeaderField("content-encoding", ""),
    HeaderField("content-language", ""),
    HeaderField("content-length", ""),
    HeaderField("content-location", ""),
    HeaderField("content-range", ""),
    HeaderField("content-type", ""),
    HeaderField("cookie", ""),
    HeaderField("date", ""),
    HeaderField("etag", ""),
    HeaderField("expect", ""),
    HeaderField("expires", ""),
    HeaderField("from", ""),
    HeaderField("host", ""),
    HeaderField("if-match", ""),
    HeaderField("if-modified-since", ""),
    HeaderField("if-none-match", ""),
    HeaderField("if-range", ""),
    HeaderField("if-unmodified-since", ""),
    HeaderField("last-modified", ""),
    HeaderField("link", ""),
    HeaderField("location", ""),
    HeaderField("max-forwards", ""),
    HeaderField("proxy-authenticate", ""),
    HeaderField("proxy-authorization", ""),
    HeaderField("range", ""),
    HeaderField("referer", ""),
    HeaderField("refresh", ""),
    HeaderField("retry-after", ""),
    HeaderField("server", ""),
    HeaderField("set-cookie", ""),
    HeaderField("strict-transport-security", ""),
    HeaderField("transfer-encoding", ""),
    HeaderField("user-agent", ""),
    HeaderField("vary", ""),
    HeaderField("via", ""),
    HeaderField("www-authenticate", ""),
];

struct HpackDecoder
{
    HeaderField[] dynamicTable;
    size_t dynamicTableSize;
    size_t maxDynamicTableSize = H2_DEFAULT_HEADER_TABLE_SIZE;

    HeaderField[] decode(scope const(ubyte)[] block) @trusted nothrow
    {
        HeaderField[] headers;
        size_t pos = 0;
        while (pos < block.length)
        {
            ubyte b = block[pos];

            if (b & 0x80)
            {
                // Indexed header field (§6.1)
                uint idx;
                if (!decodeInt(block, pos, 7, idx)) break;
                auto hf = lookupIndex(idx);
                if (hf.name.length > 0)
                {
                    try { headers ~= hf; } catch (Throwable) { break; }
                }
            }
            else if (b & 0x40)
            {
                // Literal with incremental indexing (§6.2.1)
                uint idx;
                if (!decodeInt(block, pos, 6, idx)) break;
                string name;
                if (idx > 0)
                {
                    auto hf = lookupIndex(idx);
                    name = hf.name;
                }
                else
                {
                    if (!decodeString(block, pos, name)) break;
                }
                string value;
                if (!decodeString(block, pos, value)) break;
                auto entry = HeaderField(name, value);
                try { headers ~= entry; } catch (Throwable) { break; }
                addToDynamicTable(entry);
            }
            else if (b & 0x20)
            {
                // Dynamic table size update (§6.3)
                uint newSize;
                if (!decodeInt(block, pos, 5, newSize)) break;
                maxDynamicTableSize = newSize;
                evictDynamicTable();
            }
            else
            {
                // Literal without indexing (§6.2.2) or never indexed (§6.2.3)
                int prefix = (b & 0x10) ? 4 : 4;
                uint idx;
                if (!decodeInt(block, pos, prefix, idx)) break;
                string name;
                if (idx > 0)
                {
                    auto hf = lookupIndex(idx);
                    name = hf.name;
                }
                else
                {
                    if (!decodeString(block, pos, name)) break;
                }
                string value;
                if (!decodeString(block, pos, value)) break;
                try { headers ~= HeaderField(name, value); } catch (Throwable) { break; }
            }
        }
        return headers;
    }

    private HeaderField lookupIndex(uint idx) nothrow @safe
    {
        if (idx < HPACK_STATIC_TABLE.length)
            return HPACK_STATIC_TABLE[idx];
        uint dynIdx = cast(uint)(idx - HPACK_STATIC_TABLE.length);
        if (dynIdx < dynamicTable.length)
            return dynamicTable[dynIdx];
        return HeaderField("", "");
    }

    private void addToDynamicTable(HeaderField entry) nothrow @trusted
    {
        size_t entrySize = entry.name.length + entry.value.length + 32;
        try
        {
            HeaderField[] newTable;
            newTable ~= entry;
            foreach (ref e; dynamicTable)
                newTable ~= e;
            dynamicTable = newTable;
            dynamicTableSize += entrySize;
        }
        catch (Throwable) { return; }
        evictDynamicTable();
    }

    private void evictDynamicTable() nothrow @trusted
    {
        while (dynamicTableSize > maxDynamicTableSize && dynamicTable.length > 0)
        {
            auto last = dynamicTable[$ - 1];
            size_t lastSize = last.name.length + last.value.length + 32;
            dynamicTableSize -= lastSize;
            try { dynamicTable = dynamicTable[0 .. $ - 1]; }
            catch (Throwable) { break; }
        }
    }
}

bool decodeInt(scope const(ubyte)[] data, ref size_t pos, int prefix, out uint result) pure nothrow @safe @nogc
{
    if (pos >= data.length) return false;
    uint mask = (1 << prefix) - 1;
    result = data[pos] & mask;
    pos++;
    if (result < mask) return true;

    uint shift = 0;
    while (pos < data.length)
    {
        ubyte b = data[pos++];
        result += cast(uint)(b & 0x7F) << shift;
        shift += 7;
        if (!(b & 0x80)) return true;
        if (shift > 28) return false;
    }
    return false;
}

bool decodeString(scope const(ubyte)[] data, ref size_t pos, out string result) nothrow @trusted
{
    if (pos >= data.length) return false;
    bool huffman = (data[pos] & 0x80) != 0;
    uint length;
    if (!decodeInt(data, pos, 7, length)) return false;
    if (pos + length > data.length) return false;

    auto raw = data[pos .. pos + length];
    pos += length;

    if (huffman)
    {
        result = huffmanDecode(raw);
        return result !is null || raw.length == 0;
    }
    else
    {
        try { result = (cast(const(char)[]) raw).idup; }
        catch (Throwable) { return false; }
        return true;
    }
}

// ── HPACK Huffman Decoding (RFC 7541 Appendix B) ─────────────────

// Simplified Huffman decoder using the HPACK Huffman table
// Each entry: (code, bit_length)
struct HuffEntry { uint code; ubyte bits; }

// RFC 7541 Appendix B — full HPACK Huffman table (256 symbols + EOS)
immutable HuffEntry[257] HPACK_HUFFMAN_TABLE = [
    HuffEntry(0x1ff8, 13),     // 0
    HuffEntry(0x7fffd8, 23),   // 1
    HuffEntry(0xfffffe2, 28),  // 2
    HuffEntry(0xfffffe3, 28),  // 3
    HuffEntry(0xfffffe4, 28),  // 4
    HuffEntry(0xfffffe5, 28),  // 5
    HuffEntry(0xfffffe6, 28),  // 6
    HuffEntry(0xfffffe7, 28),  // 7
    HuffEntry(0xfffffe8, 28),  // 8
    HuffEntry(0xffffea, 24),   // 9
    HuffEntry(0x3ffffffc, 30), // 10
    HuffEntry(0xfffffe9, 28),  // 11
    HuffEntry(0xfffffea, 28),  // 12
    HuffEntry(0x3ffffffd, 30), // 13
    HuffEntry(0xfffffeb, 28),  // 14
    HuffEntry(0xfffffec, 28),  // 15
    HuffEntry(0xfffffed, 28),  // 16
    HuffEntry(0xfffffee, 28),  // 17
    HuffEntry(0xfffffef, 28),  // 18
    HuffEntry(0xffffff0, 28),  // 19
    HuffEntry(0xffffff1, 28),  // 20
    HuffEntry(0xffffff2, 28),  // 21
    HuffEntry(0x3ffffffe, 30), // 22
    HuffEntry(0xffffff3, 28),  // 23
    HuffEntry(0xffffff4, 28),  // 24
    HuffEntry(0xffffff5, 28),  // 25
    HuffEntry(0xffffff6, 28),  // 26
    HuffEntry(0xffffff7, 28),  // 27
    HuffEntry(0xffffff8, 28),  // 28
    HuffEntry(0xffffff9, 28),  // 29
    HuffEntry(0xffffffa, 28),  // 30
    HuffEntry(0xffffffb, 28),  // 31
    HuffEntry(0x14, 6),        // 32 ' '
    HuffEntry(0x3f8, 10),      // 33 '!'
    HuffEntry(0x3f9, 10),      // 34 '"'
    HuffEntry(0xffa, 12),      // 35 '#'
    HuffEntry(0x1ff9, 13),     // 36 '$'
    HuffEntry(0x15, 6),        // 37 '%'
    HuffEntry(0xf8, 8),        // 38 '&'
    HuffEntry(0x7fa, 11),      // 39 '\''
    HuffEntry(0x3fa, 10),      // 40 '('
    HuffEntry(0x3fb, 10),      // 41 ')'
    HuffEntry(0xf9, 8),        // 42 '*'
    HuffEntry(0x7fb, 11),      // 43 '+'
    HuffEntry(0xfa, 8),        // 44 ','
    HuffEntry(0x16, 6),        // 45 '-'
    HuffEntry(0x17, 6),        // 46 '.'
    HuffEntry(0x18, 6),        // 47 '/'
    HuffEntry(0x0, 5),         // 48 '0'
    HuffEntry(0x1, 5),         // 49 '1'
    HuffEntry(0x2, 5),         // 50 '2'
    HuffEntry(0x19, 6),        // 51 '3'
    HuffEntry(0x1a, 6),        // 52 '4'
    HuffEntry(0x1b, 6),        // 53 '5'
    HuffEntry(0x1c, 6),        // 54 '6'
    HuffEntry(0x1d, 6),        // 55 '7'
    HuffEntry(0x1e, 6),        // 56 '8'
    HuffEntry(0x1f, 6),        // 57 '9'
    HuffEntry(0x5c, 7),        // 58 ':'
    HuffEntry(0xfb, 8),        // 59 ';'
    HuffEntry(0x7ffc, 15),     // 60 '<'
    HuffEntry(0x20, 6),        // 61 '='
    HuffEntry(0xffb, 12),      // 62 '>'
    HuffEntry(0x3fc, 10),      // 63 '?'
    HuffEntry(0x1ffa, 13),     // 64 '@'
    HuffEntry(0x21, 6),        // 65 'A'
    HuffEntry(0x5d, 7),        // 66 'B'
    HuffEntry(0x5e, 7),        // 67 'C'
    HuffEntry(0x5f, 7),        // 68 'D'
    HuffEntry(0x60, 7),        // 69 'E'
    HuffEntry(0x61, 7),        // 70 'F'
    HuffEntry(0x62, 7),        // 71 'G'
    HuffEntry(0x63, 7),        // 72 'H'
    HuffEntry(0x64, 7),        // 73 'I'
    HuffEntry(0x65, 7),        // 74 'J'
    HuffEntry(0x66, 7),        // 75 'K'
    HuffEntry(0x67, 7),        // 76 'L'
    HuffEntry(0x68, 7),        // 77 'M'
    HuffEntry(0x69, 7),        // 78 'N'
    HuffEntry(0x6a, 7),        // 79 'O'
    HuffEntry(0x6b, 7),        // 80 'P'
    HuffEntry(0x6c, 7),        // 81 'Q'
    HuffEntry(0x6d, 7),        // 82 'R'
    HuffEntry(0x6e, 7),        // 83 'S'
    HuffEntry(0x6f, 7),        // 84 'T'
    HuffEntry(0x70, 7),        // 85 'U'
    HuffEntry(0x71, 7),        // 86 'V'
    HuffEntry(0x72, 7),        // 87 'W'
    HuffEntry(0xfc, 8),        // 88 'X'
    HuffEntry(0x73, 7),        // 89 'Y'
    HuffEntry(0xfd, 8),        // 90 'Z'
    HuffEntry(0x1ffb, 13),     // 91 '['
    HuffEntry(0x7fff0, 19),    // 92 '\'
    HuffEntry(0x1ffc, 13),     // 93 ']'
    HuffEntry(0x3ffc, 14),     // 94 '^'
    HuffEntry(0x22, 6),        // 95 '_'
    HuffEntry(0x7ffd, 15),     // 96 '`'
    HuffEntry(0x3, 5),         // 97 'a'
    HuffEntry(0x23, 6),        // 98 'b'
    HuffEntry(0x4, 5),         // 99 'c'
    HuffEntry(0x24, 6),        // 100 'd'
    HuffEntry(0x5, 5),         // 101 'e'
    HuffEntry(0x25, 6),        // 102 'f'
    HuffEntry(0x26, 6),        // 103 'g'
    HuffEntry(0x27, 6),        // 104 'h'
    HuffEntry(0x6, 5),         // 105 'i'
    HuffEntry(0x74, 7),        // 106 'j'
    HuffEntry(0x75, 7),        // 107 'k'
    HuffEntry(0x28, 6),        // 108 'l'
    HuffEntry(0x29, 6),        // 109 'm'
    HuffEntry(0x2a, 6),        // 110 'n'
    HuffEntry(0x7, 5),         // 111 'o'
    HuffEntry(0x2b, 6),        // 112 'p'
    HuffEntry(0x76, 7),        // 113 'q'
    HuffEntry(0x2c, 6),        // 114 'r'
    HuffEntry(0x8, 5),         // 115 's'
    HuffEntry(0x9, 5),         // 116 't'
    HuffEntry(0x2d, 6),        // 117 'u'
    HuffEntry(0x77, 7),        // 118 'v'
    HuffEntry(0x78, 7),        // 119 'w'
    HuffEntry(0x79, 7),        // 120 'x'
    HuffEntry(0x7a, 7),        // 121 'y'
    HuffEntry(0x7b, 7),        // 122 'z'
    HuffEntry(0x7fffe, 19),    // 123 '{'
    HuffEntry(0x7fc, 11),      // 124 '|'
    HuffEntry(0x3ffd, 14),     // 125 '}'
    HuffEntry(0x1ffd, 13),     // 126 '~'
    HuffEntry(0xffffffc, 28),  // 127
    HuffEntry(0xfffe6, 20),    // 128
    HuffEntry(0x3fffd2, 22),   // 129
    HuffEntry(0xfffe7, 20),    // 130
    HuffEntry(0xfffe8, 20),    // 131
    HuffEntry(0x3fffd3, 22),   // 132
    HuffEntry(0x3fffd4, 22),   // 133
    HuffEntry(0x3fffd5, 22),   // 134
    HuffEntry(0x7fffd9, 23),   // 135
    HuffEntry(0x3fffd6, 22),   // 136
    HuffEntry(0x7fffda, 23),   // 137
    HuffEntry(0x7fffdb, 23),   // 138
    HuffEntry(0x7fffdc, 23),   // 139
    HuffEntry(0x7fffdd, 23),   // 140
    HuffEntry(0x7fffde, 23),   // 141
    HuffEntry(0xffffeb, 24),   // 142
    HuffEntry(0x7fffdf, 23),   // 143
    HuffEntry(0xffffec, 24),   // 144
    HuffEntry(0xffffed, 24),   // 145
    HuffEntry(0x3fffd7, 22),   // 146
    HuffEntry(0x7fffe0, 23),   // 147
    HuffEntry(0xffffee, 24),   // 148
    HuffEntry(0x7fffe1, 23),   // 149
    HuffEntry(0x7fffe2, 23),   // 150
    HuffEntry(0x7fffe3, 23),   // 151
    HuffEntry(0x7fffe4, 23),   // 152
    HuffEntry(0x1fffdc, 21),   // 153
    HuffEntry(0x3fffd8, 22),   // 154
    HuffEntry(0x7fffe5, 23),   // 155
    HuffEntry(0x3fffd9, 22),   // 156
    HuffEntry(0x7fffe6, 23),   // 157
    HuffEntry(0x7fffe7, 23),   // 158
    HuffEntry(0xffffef, 24),   // 159
    HuffEntry(0x3fffda, 22),   // 160
    HuffEntry(0x1fffdd, 21),   // 161
    HuffEntry(0xfffe9, 20),    // 162
    HuffEntry(0x3fffdb, 22),   // 163
    HuffEntry(0x3fffdc, 22),   // 164
    HuffEntry(0x7fffe8, 23),   // 165
    HuffEntry(0x7fffe9, 23),   // 166
    HuffEntry(0x1fffde, 21),   // 167
    HuffEntry(0x7fffea, 23),   // 168
    HuffEntry(0x3fffdd, 22),   // 169
    HuffEntry(0x3fffde, 22),   // 170
    HuffEntry(0xfffff0, 24),   // 171
    HuffEntry(0x1fffdf, 21),   // 172
    HuffEntry(0x3fffdf, 22),   // 173
    HuffEntry(0x7fffeb, 23),   // 174
    HuffEntry(0x7fffec, 23),   // 175
    HuffEntry(0x1fffe0, 21),   // 176
    HuffEntry(0x1fffe1, 21),   // 177
    HuffEntry(0x3fffe0, 22),   // 178
    HuffEntry(0x1fffe2, 21),   // 179
    HuffEntry(0x7fffed, 23),   // 180
    HuffEntry(0x3fffe1, 22),   // 181
    HuffEntry(0x7fffee, 23),   // 182
    HuffEntry(0x7fffef, 23),   // 183
    HuffEntry(0xfffea, 20),    // 184
    HuffEntry(0x3fffe2, 22),   // 185
    HuffEntry(0x3fffe3, 22),   // 186
    HuffEntry(0x3fffe4, 22),   // 187
    HuffEntry(0x7ffff0, 23),   // 188
    HuffEntry(0x3fffe5, 22),   // 189
    HuffEntry(0x3fffe6, 22),   // 190
    HuffEntry(0x7ffff1, 23),   // 191
    HuffEntry(0x3ffffe0, 26),  // 192
    HuffEntry(0x3ffffe1, 26),  // 193
    HuffEntry(0xfffeb, 20),    // 194
    HuffEntry(0x7fff1, 19),    // 195
    HuffEntry(0x3fffe7, 22),   // 196
    HuffEntry(0x7ffff2, 23),   // 197
    HuffEntry(0x3fffe8, 22),   // 198
    HuffEntry(0x1ffffec, 25),  // 199
    HuffEntry(0x3ffffe2, 26),  // 200
    HuffEntry(0x3ffffe3, 26),  // 201
    HuffEntry(0x3ffffe4, 26),  // 202
    HuffEntry(0x7ffffde, 27),  // 203
    HuffEntry(0x7ffffdf, 27),  // 204
    HuffEntry(0x3ffffe5, 26),  // 205
    HuffEntry(0xfffff1, 24),   // 206
    HuffEntry(0x1ffffed, 25),  // 207
    HuffEntry(0x7fff2, 19),    // 208
    HuffEntry(0x1fffe3, 21),   // 209
    HuffEntry(0x3ffffe6, 26),  // 210
    HuffEntry(0x7ffffe0, 27),  // 211
    HuffEntry(0x7ffffe1, 27),  // 212
    HuffEntry(0x3ffffe7, 26),  // 213
    HuffEntry(0x7ffffe2, 27),  // 214
    HuffEntry(0xfffff2, 24),   // 215
    HuffEntry(0x1fffe4, 21),   // 216
    HuffEntry(0x1fffe5, 21),   // 217
    HuffEntry(0x3ffffe8, 26),  // 218
    HuffEntry(0x3ffffe9, 26),  // 219
    HuffEntry(0xffffffd, 28),  // 220
    HuffEntry(0x7ffffe3, 27),  // 221
    HuffEntry(0x7ffffe4, 27),  // 222
    HuffEntry(0x7ffffe5, 27),  // 223
    HuffEntry(0xfffec, 20),    // 224
    HuffEntry(0xfffff3, 24),   // 225
    HuffEntry(0xfffed, 20),    // 226
    HuffEntry(0x1fffe6, 21),   // 227
    HuffEntry(0x3fffe9, 22),   // 228
    HuffEntry(0x1fffe7, 21),   // 229
    HuffEntry(0x1fffe8, 21),   // 230
    HuffEntry(0x7ffff3, 23),   // 231
    HuffEntry(0x3fffea, 22),   // 232
    HuffEntry(0x3fffeb, 22),   // 233
    HuffEntry(0x1ffffee, 25),  // 234
    HuffEntry(0x1ffffef, 25),  // 235
    HuffEntry(0xfffff4, 24),   // 236
    HuffEntry(0xfffff5, 24),   // 237
    HuffEntry(0x3ffffea, 26),  // 238
    HuffEntry(0x7ffff4, 23),   // 239
    HuffEntry(0x3ffffeb, 26),  // 240
    HuffEntry(0x7ffffe6, 27),  // 241
    HuffEntry(0x3ffffec, 26),  // 242
    HuffEntry(0x3ffffed, 26),  // 243
    HuffEntry(0x7ffffe7, 27),  // 244
    HuffEntry(0x7ffffe8, 27),  // 245
    HuffEntry(0x7ffffe9, 27),  // 246
    HuffEntry(0x7ffffea, 27),  // 247
    HuffEntry(0x7ffffeb, 27),  // 248
    HuffEntry(0xffffffe, 28),  // 249
    HuffEntry(0x7ffffec, 27),  // 250
    HuffEntry(0x7ffffed, 27),  // 251
    HuffEntry(0x7ffffee, 27),  // 252
    HuffEntry(0x7ffffef, 27),  // 253
    HuffEntry(0x7fffff0, 27),  // 254
    HuffEntry(0x3ffffee, 26),  // 255
    HuffEntry(0x3fffffff, 30), // 256 EOS
];

string huffmanDecode(const(ubyte)[] data) nothrow @trusted
{
    // Build decode lookup on first call
    static __gshared bool tableBuilt = false;
    static __gshared ubyte[65536] lut8sym;
    static __gshared ubyte[65536] lut8bits;
    static __gshared bool[65536] lut8valid;

    if (!tableBuilt)
    {
        // Build 8-bit fast lookup for codes ≤ 8 bits
        for (int sym = 0; sym < 257; sym++)
        {
            auto entry = HPACK_HUFFMAN_TABLE[sym];
            if (entry.bits <= 8)
            {
                int padding = 8 - entry.bits;
                uint base = entry.code << padding;
                for (int j = 0; j < (1 << padding); j++)
                {
                    uint idx = base | j;
                    if (idx < 65536)
                    {
                        lut8sym[idx] = cast(ubyte) sym;
                        lut8bits[idx] = entry.bits;
                        lut8valid[idx] = true;
                    }
                }
            }
        }
        tableBuilt = true;
    }

    // Bit-by-bit decoding using the Huffman table
    ubyte[] result;
    uint accum = 0;
    int bits = 0;

    foreach (b; data)
    {
        accum = (accum << 8) | b;
        bits += 8;

        while (bits >= 5)
        {
            bool matched = false;
            for (int sym = 0; sym < 256; sym++)
            {
                auto entry = HPACK_HUFFMAN_TABLE[sym];
                if (entry.bits <= bits)
                {
                    uint shifted = accum >> (bits - entry.bits);
                    if (shifted == entry.code)
                    {
                        try { result ~= cast(ubyte) sym; }
                        catch (Throwable) { return null; }
                        bits -= entry.bits;
                        accum &= (1 << bits) - 1;
                        matched = true;
                        break;
                    }
                }
            }
            if (!matched) break;
        }
    }

    try { return (cast(const(char)[]) result).idup; }
    catch (Throwable) { return null; }
}

// ── HPACK Encoder ────────────────────────────────────────────────

ubyte[] hpackEncode(HeaderField[] headers) nothrow @trusted
{
    Appender!(ubyte[]) result;
    try { result.reserve(headers.length * HPACK_AVG_ENTRY_SIZE); }
    catch (Throwable) { return null; }

    foreach (ref hf; headers)
    {
        int staticIdx = findStaticIndex(hf.name, hf.value);

        if (staticIdx > 0 && HPACK_STATIC_TABLE[staticIdx].value == hf.value
            && hf.value.length > 0)
        {
            encodeIntHpackTo(result, cast(uint) staticIdx,
                HPACK_INDEXED_PREFIX_BITS, HPACK_INDEXED_PREFIX);
        }
        else if (staticIdx > 0)
        {
            encodeIntHpackTo(result, cast(uint) staticIdx,
                HPACK_INCR_INDEX_PREFIX_BITS, HPACK_INCR_INDEX_PREFIX);
            encodeLiteralStringTo(result, hf.value);
        }
        else
        {
            result ~= HPACK_NO_INDEX_PREFIX;
            encodeLiteralStringTo(result, hf.name);
            encodeLiteralStringTo(result, hf.value);
        }
    }
    return (() @trusted => result[])();
}

int findStaticIndex(string name, string value) pure nothrow @safe
{
    int nameMatch = -1;
    for (int i = 1; i < cast(int) HPACK_STATIC_TABLE.length; i++)
    {
        if (HPACK_STATIC_TABLE[i].name == name)
        {
            if (HPACK_STATIC_TABLE[i].value == value)
                return i;
            if (nameMatch < 0) nameMatch = i;
        }
    }
    return nameMatch > 0 ? nameMatch : 0;
}

void encodeIntHpackTo(ref Appender!(ubyte[]) result, uint value, int prefix, ubyte pattern)
    nothrow @trusted
{
    uint mask = (1 << prefix) - 1;
    if (value < mask)
    {
        result ~= cast(ubyte)(pattern | (value & 0xFF));
        return;
    }
    result ~= cast(ubyte)(pattern | mask);
    value -= mask;
    while (value >= 128)
    {
        result ~= cast(ubyte)((value & 0x7F) | 0x80);
        value >>= 7;
    }
    result ~= cast(ubyte) value;
}

ubyte[] encodeIntHpack(uint value, int prefix, ubyte pattern) nothrow @trusted
{
    Appender!(ubyte[]) result;
    encodeIntHpackTo(result, value, prefix, pattern);
    return (() @trusted => result[])();
}

void encodeLiteralStringTo(ref Appender!(ubyte[]) result, string s) nothrow @trusted
{
    encodeIntHpackTo(result, cast(uint) s.length,
        HPACK_STRING_LENGTH_PREFIX_BITS, HPACK_NO_INDEX_PREFIX);
    foreach (c; s)
        result ~= cast(ubyte) c;
}

ubyte[] encodeLiteralString(string s) nothrow @trusted
{
    Appender!(ubyte[]) result;
    encodeLiteralStringTo(result, s);
    return (() @trusted => result[])();
}

// ── HTTP/2 Stream State Machine ──────────────────────────────────

enum H2StreamState
{
    idle,
    reservedLocal,
    reservedRemote,
    open,
    halfClosedLocal,
    halfClosedRemote,
    closed,
}

struct H2Stream
{
    uint streamId;
    H2StreamState state = H2StreamState.idle;
    string method;
    string path;
    string scheme;
    string authority;
    HeaderField[] headers;
    ubyte[] body_;
    int sendWindow = H2_DEFAULT_WINDOW_SIZE;
    int recvWindow = H2_DEFAULT_WINDOW_SIZE;
    bool endStream;
}

// ── HTTP/2 Connection State ──────────────────────────────────────

struct H2Settings
{
    uint headerTableSize = H2_DEFAULT_HEADER_TABLE_SIZE;
    bool enablePush = true;
    uint maxConcurrentStreams = H2_DEFAULT_MAX_CONCURRENT_STREAMS;
    uint initialWindowSize = H2_DEFAULT_WINDOW_SIZE;
    uint maxFrameSize = H2_DEFAULT_MAX_FRAME_SIZE;
    uint maxHeaderListSize = uint.max;
}

struct H2Connection
{
    IJSEngine engine;
    int fd = -1;
    bool isServer;
    bool prefaceReceived;
    bool prefaceSent;
    bool closed;
    H2Settings localSettings;
    H2Settings remoteSettings;
    int connectionSendWindow = H2_DEFAULT_WINDOW_SIZE;
    int connectionRecvWindow = H2_DEFAULT_WINDOW_SIZE;
    uint lastStreamId;
    uint nextStreamId = 1;
    H2Stream[uint] streams;
    HpackDecoder decoder;
    ubyte[] recvBuf;
    int srvId = -1;

    version (Posix) void* sslPtr; // SSL* for TLS connections

    void sendConnectionPreface() nothrow @trusted
    {
        if (prefaceSent) return;
        prefaceSent = true;

        if (isServer)
        {
            auto settingsPayload = encodeSettings(localSettings);
            auto frame = encodeFrameHeader(
                cast(uint) settingsPayload.length,
                H2FrameType.SETTINGS, H2Flag.NONE, 0);
            sendRawBytes(frame[]);
            sendRawBytes(settingsPayload);
        }
        else
        {
            sendRawBytes(H2_CLIENT_PREFACE);
            auto settingsPayload = encodeSettings(localSettings);
            auto frame = encodeFrameHeader(
                cast(uint) settingsPayload.length,
                H2FrameType.SETTINGS, H2Flag.NONE, 0);
            sendRawBytes(frame[]);
            sendRawBytes(settingsPayload);
        }
    }

    void processReceivedData(const(ubyte)[] data) nothrow @trusted
    {
        try { recvBuf ~= data; }
        catch (Throwable) { return; }

        if (!prefaceReceived && isServer)
        {
            if (recvBuf.length >= H2_CONNECTION_PREFACE_LEN)
            {
                if (recvBuf[0 .. H2_CONNECTION_PREFACE_LEN] == H2_CLIENT_PREFACE)
                {
                    prefaceReceived = true;
                    try { recvBuf = recvBuf[H2_CONNECTION_PREFACE_LEN .. $].dup; }
                    catch (Throwable) { return; }
                }
                else
                {
                    sendGoaway(H2Error.PROTOCOL_ERROR);
                    return;
                }
            }
            else return;
        }

        while (recvBuf.length >= H2_FRAME_HEADER_SIZE)
        {
            H2Frame frame;
            if (!parseFrameHeader(recvBuf, frame)) break;
            size_t totalLen = H2_FRAME_HEADER_SIZE + frame.length;
            if (recvBuf.length < totalLen) break;

            frame.payload = recvBuf[H2_FRAME_HEADER_SIZE .. totalLen];
            processFrame(frame);

            try { recvBuf = recvBuf[totalLen .. $].dup; }
            catch (Throwable) { return; }
        }
    }

    void processFrame(ref H2Frame frame) nothrow @trusted
    {
        final switch (frame.type)
        {
            case H2FrameType.SETTINGS:
                processSettings(frame);
                break;
            case H2FrameType.HEADERS:
                processHeaders(frame);
                break;
            case H2FrameType.DATA:
                processData(frame);
                break;
            case H2FrameType.WINDOW_UPDATE:
                processWindowUpdate(frame);
                break;
            case H2FrameType.PING:
                processPing(frame);
                break;
            case H2FrameType.RST_STREAM:
                processRstStream(frame);
                break;
            case H2FrameType.GOAWAY:
                processGoaway(frame);
                break;
            case H2FrameType.PRIORITY:
            case H2FrameType.PUSH_PROMISE:
            case H2FrameType.CONTINUATION:
                break;
        }
    }

    void processSettings(ref H2Frame frame) nothrow @trusted
    {
        if (frame.flags & H2Flag.ACK) return;
        if (frame.streamId != 0)
        {
            sendGoaway(H2Error.PROTOCOL_ERROR);
            return;
        }

        auto payload = frame.payload;
        while (payload.length >= 6)
        {
            ushort id = cast(ushort)((payload[0] << 8) | payload[1]);
            uint val = (cast(uint) payload[2] << 24) | (cast(uint) payload[3] << 16)
                | (cast(uint) payload[4] << 8) | payload[5];
            payload = payload[6 .. $];

            switch (id)
            {
                case H2Setting.HEADER_TABLE_SIZE:
                    remoteSettings.headerTableSize = val;
                    decoder.maxDynamicTableSize = val;
                    break;
                case H2Setting.ENABLE_PUSH:
                    remoteSettings.enablePush = val != 0;
                    break;
                case H2Setting.MAX_CONCURRENT_STREAMS:
                    remoteSettings.maxConcurrentStreams = val;
                    break;
                case H2Setting.INITIAL_WINDOW_SIZE:
                    if (val > 0x7FFF_FFFF)
                    {
                        sendGoaway(H2Error.FLOW_CONTROL_ERROR);
                        return;
                    }
                    remoteSettings.initialWindowSize = val;
                    break;
                case H2Setting.MAX_FRAME_SIZE:
                    if (val < H2_DEFAULT_MAX_FRAME_SIZE || val > H2_MAX_FRAME_SIZE)
                    {
                        sendGoaway(H2Error.PROTOCOL_ERROR);
                        return;
                    }
                    remoteSettings.maxFrameSize = val;
                    break;
                case H2Setting.MAX_HEADER_LIST_SIZE:
                    remoteSettings.maxHeaderListSize = val;
                    break;
                default:
                    break;
            }
        }

        // Send SETTINGS ACK
        auto ack = encodeFrameHeader(0, H2FrameType.SETTINGS, H2Flag.ACK, 0);
        sendRawBytes(ack[]);
    }

    void processHeaders(ref H2Frame frame) nothrow @trusted
    {
        auto payload = frame.payload;
        size_t offset = 0;

        if (frame.flags & H2Flag.PADDED)
        {
            if (payload.length < 1) return;
            offset = 1;
        }
        if (frame.flags & H2Flag.PRIORITY)
        {
            if (payload.length < offset + 5) return;
            offset += 5;
        }

        auto headerBlock = payload[offset .. $];
        auto headers = decoder.decode(headerBlock);

        H2Stream stream;
        stream.streamId = frame.streamId;
        stream.state = H2StreamState.open;
        stream.sendWindow = remoteSettings.initialWindowSize;
        stream.recvWindow = localSettings.initialWindowSize;
        stream.headers = headers;

        foreach (ref hf; headers)
        {
            if (hf.name == ":method") stream.method = hf.value;
            else if (hf.name == ":path") stream.path = hf.value;
            else if (hf.name == ":scheme") stream.scheme = hf.value;
            else if (hf.name == ":authority") stream.authority = hf.value;
        }

        if (frame.flags & H2Flag.END_STREAM)
        {
            stream.endStream = true;
            stream.state = H2StreamState.halfClosedRemote;
        }

        if (frame.streamId > lastStreamId)
            lastStreamId = frame.streamId;

        try { streams[frame.streamId] = stream; }
        catch (Throwable) { return; }

        if (isServer && engine !is null)
            dispatchStreamRequest(frame.streamId);
    }

    void processData(ref H2Frame frame) nothrow @trusted
    {
        if (frame.streamId == 0)
        {
            sendGoaway(H2Error.PROTOCOL_ERROR);
            return;
        }

        if (auto p = frame.streamId in streams)
        {
            try { p.body_ ~= frame.payload; }
            catch (Throwable) { return; }

            connectionRecvWindow -= cast(int) frame.length;
            p.recvWindow -= cast(int) frame.length;

            // Send WINDOW_UPDATE if window gets low
            if (connectionRecvWindow < H2_DEFAULT_WINDOW_SIZE / 2)
            {
                int increment = H2_DEFAULT_WINDOW_SIZE - connectionRecvWindow;
                sendWindowUpdate(0, increment);
                connectionRecvWindow += increment;
            }
            if (p.recvWindow < H2_DEFAULT_WINDOW_SIZE / 2)
            {
                int increment = H2_DEFAULT_WINDOW_SIZE - p.recvWindow;
                sendWindowUpdate(frame.streamId, increment);
                p.recvWindow += increment;
            }

            if (frame.flags & H2Flag.END_STREAM)
            {
                p.endStream = true;
                if (p.state == H2StreamState.open)
                    p.state = H2StreamState.halfClosedRemote;
                else if (p.state == H2StreamState.halfClosedLocal)
                    p.state = H2StreamState.closed;
            }
        }
    }

    void processWindowUpdate(ref H2Frame frame) nothrow @trusted
    {
        if (frame.payload.length < 4) return;
        uint increment = ((cast(uint) frame.payload[0] << 24)
            | (cast(uint) frame.payload[1] << 16)
            | (cast(uint) frame.payload[2] << 8)
            | frame.payload[3]) & 0x7FFF_FFFF;

        if (increment == 0)
        {
            if (frame.streamId == 0)
                sendGoaway(H2Error.PROTOCOL_ERROR);
            else
                sendRstStream(frame.streamId, H2Error.PROTOCOL_ERROR);
            return;
        }

        if (frame.streamId == 0)
            connectionSendWindow += increment;
        else if (auto p = frame.streamId in streams)
            p.sendWindow += increment;
    }

    void processPing(ref H2Frame frame) nothrow @trusted
    {
        if (frame.flags & H2Flag.ACK) return;
        if (frame.streamId != 0 || frame.payload.length != 8)
        {
            sendGoaway(H2Error.PROTOCOL_ERROR);
            return;
        }
        auto pong = encodeFrameHeader(8, H2FrameType.PING, H2Flag.ACK, 0);
        sendRawBytes(pong[]);
        sendRawBytes(frame.payload);
    }

    void processRstStream(ref H2Frame frame) nothrow @trusted
    {
        if (frame.streamId == 0 || frame.payload.length < 4) return;
        if (auto p = frame.streamId in streams)
            p.state = H2StreamState.closed;
    }

    void processGoaway(ref H2Frame frame) nothrow @trusted
    {
        closed = true;
    }

    // ── Send helpers ─────────────────────────────────────────────

    void sendHeaders(uint streamId, HeaderField[] headers, bool endStream) nothrow @trusted
    {
        auto encoded = hpackEncode(headers);
        if (encoded is null) return;

        ubyte flags = H2Flag.END_HEADERS;
        if (endStream) flags |= H2Flag.END_STREAM;

        auto frame = encodeFrameHeader(cast(uint) encoded.length,
            H2FrameType.HEADERS, flags, streamId);
        sendRawBytes(frame[]);
        sendRawBytes(encoded);
    }

    void sendData(uint streamId, const(ubyte)[] data, bool endStream) nothrow @trusted
    {
        size_t offset = 0;
        while (offset < data.length)
        {
            uint chunkSize = cast(uint)(data.length - offset);
            if (chunkSize > remoteSettings.maxFrameSize)
                chunkSize = remoteSettings.maxFrameSize;

            ubyte flags = (offset + chunkSize >= data.length && endStream)
                ? H2Flag.END_STREAM : H2Flag.NONE;
            auto frame = encodeFrameHeader(chunkSize, H2FrameType.DATA, flags, streamId);
            sendRawBytes(frame[]);
            sendRawBytes(data[offset .. offset + chunkSize]);
            offset += chunkSize;
        }

        if (data.length == 0 && endStream)
        {
            auto frame = encodeFrameHeader(0, H2FrameType.DATA, H2Flag.END_STREAM, streamId);
            sendRawBytes(frame[]);
        }
    }

    void sendGoaway(H2Error errorCode) nothrow @trusted
    {
        ubyte[8] payload;
        payload[0] = cast(ubyte)((lastStreamId >> 24) & 0xFF);
        payload[1] = cast(ubyte)((lastStreamId >> 16) & 0xFF);
        payload[2] = cast(ubyte)((lastStreamId >> 8) & 0xFF);
        payload[3] = cast(ubyte)(lastStreamId & 0xFF);
        payload[4] = cast(ubyte)((cast(uint) errorCode >> 24) & 0xFF);
        payload[5] = cast(ubyte)((cast(uint) errorCode >> 16) & 0xFF);
        payload[6] = cast(ubyte)((cast(uint) errorCode >> 8) & 0xFF);
        payload[7] = cast(ubyte)(cast(uint) errorCode & 0xFF);
        auto frame = encodeFrameHeader(8, H2FrameType.GOAWAY, H2Flag.NONE, 0);
        sendRawBytes(frame[]);
        sendRawBytes(payload[]);
        closed = true;
    }

    void sendRstStream(uint streamId, H2Error errorCode) nothrow @trusted
    {
        ubyte[4] payload;
        payload[0] = cast(ubyte)((cast(uint) errorCode >> 24) & 0xFF);
        payload[1] = cast(ubyte)((cast(uint) errorCode >> 16) & 0xFF);
        payload[2] = cast(ubyte)((cast(uint) errorCode >> 8) & 0xFF);
        payload[3] = cast(ubyte)(cast(uint) errorCode & 0xFF);
        auto frame = encodeFrameHeader(4, H2FrameType.RST_STREAM, H2Flag.NONE, streamId);
        sendRawBytes(frame[]);
        sendRawBytes(payload[]);
        if (auto p = streamId in streams)
            p.state = H2StreamState.closed;
    }

    void sendWindowUpdate(uint streamId, int increment) nothrow @trusted
    {
        ubyte[4] payload;
        uint inc = cast(uint) increment & 0x7FFF_FFFF;
        payload[0] = cast(ubyte)((inc >> 24) & 0xFF);
        payload[1] = cast(ubyte)((inc >> 16) & 0xFF);
        payload[2] = cast(ubyte)((inc >> 8) & 0xFF);
        payload[3] = cast(ubyte)(inc & 0xFF);
        auto frame = encodeFrameHeader(4, H2FrameType.WINDOW_UPDATE, H2Flag.NONE, streamId);
        sendRawBytes(frame[]);
        sendRawBytes(payload[]);
    }

    void sendRawBytes(const(ubyte)[] data) nothrow @trusted
    {
        version (Posix)
        {
            if (fd < 0 || data.length == 0) return;

            if (sslPtr !is null)
            {
                import dun.platform.openssl : SSL, SSL_write;
                auto ssl = cast(SSL*) sslPtr;
                size_t sent = 0;
                while (sent < data.length)
                {
                    auto n = SSL_write(ssl, data.ptr + sent,
                        cast(int)(data.length - sent));
                    if (n <= 0) break;
                    sent += n;
                }
            }
            else
            {
                import core.sys.posix.unistd : write;
                size_t sent = 0;
                while (sent < data.length)
                {
                    auto n = write(fd, data.ptr + sent, data.length - sent);
                    if (n <= 0) break;
                    sent += n;
                }
            }
        }
    }

    void sendRawBytes(const(char)[] data) nothrow @trusted
    {
        sendRawBytes(cast(const(ubyte)[]) data);
    }

    // ── Dispatch to JS callback ──────────────────────────────────

    void dispatchStreamRequest(uint streamId) nothrow @trusted
    {
        if (srvId < 0 || srvId >= cast(int) h2Servers.length) return;
        auto srv = &h2Servers[srvId];
        if (!srv.hasCb || engine is null) return;

        auto stream = streamId in streams;
        if (stream is null) return;

        try
        {
            auto reqObj = engine.newObject();
            engine.setProperty(reqObj, "method", engine.newString(stream.method));
            engine.setProperty(reqObj, "url", engine.newString(stream.path));
            engine.setProperty(reqObj, "httpVersion", engine.newString("2.0"));
            engine.setProperty(reqObj, "scheme", engine.newString(stream.scheme));
            engine.setProperty(reqObj, "authority", engine.newString(stream.authority));

            auto hdrs = engine.newObject();
            foreach (ref hf; stream.headers)
            {
                if (hf.name.length > 0 && hf.name[0] != ':')
                    engine.setProperty(hdrs, hf.name, engine.newString(hf.value));
            }
            engine.setProperty(reqObj, "headers", hdrs);

            auto resObj = makeH2ResponseObj(engine, this, streamId);

            JSHandle[2] callArgs = [reqObj, resObj];
            pushAgnosticPending(engine, srv.requestCb, callArgs[]);
            engine.freeValue(reqObj);
            engine.freeValue(resObj);
        }
        catch (Throwable) {}
    }
}

ubyte[] encodeSettings(ref H2Settings s) nothrow @trusted
{
    enum bufSize = H2_SETTINGS_COUNT * H2_SETTING_ENTRY_SIZE;
    ubyte[bufSize] buf;
    size_t pos = 0;

    void addSetting(ushort id, uint val) nothrow @nogc
    {
        buf[pos++] = cast(ubyte)((id >> 8) & 0xFF);
        buf[pos++] = cast(ubyte)(id & 0xFF);
        buf[pos++] = cast(ubyte)((val >> 24) & 0xFF);
        buf[pos++] = cast(ubyte)((val >> 16) & 0xFF);
        buf[pos++] = cast(ubyte)((val >> 8) & 0xFF);
        buf[pos++] = cast(ubyte)(val & 0xFF);
    }
    addSetting(H2Setting.MAX_CONCURRENT_STREAMS, s.maxConcurrentStreams);
    addSetting(H2Setting.INITIAL_WINDOW_SIZE, s.initialWindowSize);
    addSetting(H2Setting.MAX_FRAME_SIZE, s.maxFrameSize);
    assert(pos == bufSize);
    return buf[0 .. pos].dup;
}

// ── HTTP/2 Server State ──────────────────────────────────────────

private:

// Cached function handles for HTTP/2 objects
__gshared JSHandle _h2ClientReq, _h2ClientClose;
__gshared JSHandle _h2SrvListen, _h2SrvClose, _h2SrvOn;
__gshared JSHandle _h2ResWriteHead, _h2ResWrite, _h2ResEnd, _h2ResSetHeader;
__gshared JSHandle _h2ClientSessionOn, _h2StreamOn, _h2StreamEnd, _h2StreamWrite;
__gshared bool _h2FnsCached = false;

void ensureH2FnsCached(IJSEngine engine) @trusted
{
    if (_h2FnsCached) return;
    _h2ClientReq = engine.newFunction(&jsH2ClientRequest, "request", 1);
    _h2ClientClose = engine.newFunction(&jsH2ClientClose, "close", 0);
    _h2SrvListen = engine.newFunction(&jsH2ServerListen, "listen", 1);
    _h2SrvClose = engine.newFunction(&jsH2ServerClose, "close", 0);
    _h2SrvOn = engine.newFunction(&jsH2ServerOn, "on", 2);
    _h2ResWriteHead = engine.newFunction(&jsH2ResWriteHead, "writeHead", 2);
    _h2ResWrite = engine.newFunction(&jsH2ResWrite, "write", 1);
    _h2ResEnd = engine.newFunction(&jsH2ResEnd, "end", 0);
    _h2ResSetHeader = engine.newFunction(&jsH2ResSetHeader, "setHeader", 2);
    _h2ClientSessionOn = engine.newFunction(&jsH2ClientSessionOn, "on", 2);
    _h2StreamOn = engine.newFunction(&jsH2StreamOn, "on", 2);
    _h2StreamEnd = engine.newFunction(&jsH2StreamEnd, "end", 1);
    _h2StreamWrite = engine.newFunction(&jsH2StreamWrite, "write", 1);
    _h2FnsCached = true;
}

struct H2ServerState
{
    IJSEngine engine;
    JSHandle requestCb;
    int listenFd = -1;
    bool active;
    ushort port;
    bool hasCb;
    bool secure;
    version (Posix) void* sslCtx; // SSL_CTX*
}

H2ServerState[] h2Servers;
H2Connection[] h2Connections;
int nextH2ServerId;

// ── HTTP/2 Client Session State ─────────────────────────────────

enum H2_CLIENT_RECV_BUF_SIZE = 16_384;
enum H2_CLIENT_MAX_SESSIONS = 256;

struct ClientH2Session
{
    IJSEngine engine;
    int fd = -1;
    string host;
    ushort port;
    bool closed;
    uint nextStreamId = 1; // Client streams use odd IDs (1, 3, 5, ...)
    uint lastStreamId;
    H2Settings localSettings;
    H2Settings remoteSettings;
    int connectionSendWindow = H2_DEFAULT_WINDOW_SIZE;
    int connectionRecvWindow = H2_DEFAULT_WINDOW_SIZE;
    HpackDecoder decoder;
    ubyte[] recvBuf;
    bool prefaceSent;
    bool settingsAckReceived;
    bool connectPending; // true if non-blocking connect() returned EINPROGRESS
    bool connected;      // true once the TCP connection is established

    // Per-stream callbacks (response, data, end, error)
    JSHandle[uint] responseCbs;
    JSHandle[uint] dataCbs;
    JSHandle[uint] endCbs;
    JSHandle[uint] errorCbs;

    // Session-level callbacks
    JSHandle connectCb;
    bool hasConnectCb;
    JSHandle errorSessionCb;
    bool hasErrorSessionCb;

    version (Posix) void* sslPtr; // SSL* for TLS connections

    void sendConnectionPreface() nothrow @trusted
    {
        assert(fd >= 0, "sendConnectionPreface on invalid fd");
        if (prefaceSent) return;
        prefaceSent = true;

        // Client sends magic preface + SETTINGS
        sendRawBytes(H2_CLIENT_PREFACE);
        auto settingsPayload = encodeSettings(localSettings);
        auto frame = encodeFrameHeader(
            cast(uint) settingsPayload.length,
            H2FrameType.SETTINGS, H2Flag.NONE, 0);
        sendRawBytes(frame[]);
        sendRawBytes(settingsPayload);
    }

    uint allocateStreamId() nothrow @safe @nogc
    {
        uint id = nextStreamId;
        nextStreamId += 2; // Client streams are odd
        return id;
    }

    void sendHeaders(uint streamId, HeaderField[] headers, bool endStream) nothrow @trusted
    {
        auto encoded = hpackEncode(headers);
        if (encoded is null) return;

        ubyte flags = H2Flag.END_HEADERS;
        if (endStream) flags |= H2Flag.END_STREAM;

        auto frame = encodeFrameHeader(cast(uint) encoded.length,
            H2FrameType.HEADERS, flags, streamId);
        sendRawBytes(frame[]);
        sendRawBytes(encoded);
    }

    void sendData(uint streamId, const(ubyte)[] data, bool endStream) nothrow @trusted
    {
        size_t offset = 0;
        while (offset < data.length)
        {
            uint chunkSize = cast(uint)(data.length - offset);
            if (chunkSize > remoteSettings.maxFrameSize)
                chunkSize = remoteSettings.maxFrameSize;

            ubyte flags = (offset + chunkSize >= data.length && endStream)
                ? H2Flag.END_STREAM : H2Flag.NONE;
            auto frame = encodeFrameHeader(chunkSize, H2FrameType.DATA, flags, streamId);
            sendRawBytes(frame[]);
            sendRawBytes(data[offset .. offset + chunkSize]);
            offset += chunkSize;
        }

        if (data.length == 0 && endStream)
        {
            auto frame = encodeFrameHeader(0, H2FrameType.DATA, H2Flag.END_STREAM, streamId);
            sendRawBytes(frame[]);
        }
    }

    void sendGoaway(H2Error errorCode) nothrow @trusted
    {
        ubyte[8] payload;
        payload[0] = cast(ubyte)((lastStreamId >> 24) & 0xFF);
        payload[1] = cast(ubyte)((lastStreamId >> 16) & 0xFF);
        payload[2] = cast(ubyte)((lastStreamId >> 8) & 0xFF);
        payload[3] = cast(ubyte)(lastStreamId & 0xFF);
        payload[4] = cast(ubyte)((cast(uint) errorCode >> 24) & 0xFF);
        payload[5] = cast(ubyte)((cast(uint) errorCode >> 16) & 0xFF);
        payload[6] = cast(ubyte)((cast(uint) errorCode >> 8) & 0xFF);
        payload[7] = cast(ubyte)(cast(uint) errorCode & 0xFF);
        auto frame = encodeFrameHeader(8, H2FrameType.GOAWAY, H2Flag.NONE, 0);
        sendRawBytes(frame[]);
        sendRawBytes(payload[]);
        closed = true;
    }

    void sendWindowUpdate(uint streamId, int increment) nothrow @trusted
    {
        ubyte[4] payload;
        uint inc = cast(uint) increment & 0x7FFF_FFFF;
        payload[0] = cast(ubyte)((inc >> 24) & 0xFF);
        payload[1] = cast(ubyte)((inc >> 16) & 0xFF);
        payload[2] = cast(ubyte)((inc >> 8) & 0xFF);
        payload[3] = cast(ubyte)(inc & 0xFF);
        auto frame = encodeFrameHeader(4, H2FrameType.WINDOW_UPDATE, H2Flag.NONE, streamId);
        sendRawBytes(frame[]);
        sendRawBytes(payload[]);
    }

    void processReceivedData(const(ubyte)[] data) nothrow @trusted
    {
        try { recvBuf ~= data; }
        catch (Throwable) { return; }

        while (recvBuf.length >= H2_FRAME_HEADER_SIZE)
        {
            H2Frame frame;
            if (!parseFrameHeader(recvBuf, frame)) break;
            size_t totalLen = H2_FRAME_HEADER_SIZE + frame.length;
            if (recvBuf.length < totalLen) break;

            frame.payload = recvBuf[H2_FRAME_HEADER_SIZE .. totalLen];
            processFrame(frame);

            try { recvBuf = recvBuf[totalLen .. $].dup; }
            catch (Throwable) { return; }
        }
    }

    void processFrame(ref H2Frame frame) nothrow @trusted
    {
        switch (frame.type)
        {
            case H2FrameType.SETTINGS:
                processSettings(frame);
                break;
            case H2FrameType.HEADERS:
                processResponseHeaders(frame);
                break;
            case H2FrameType.DATA:
                processResponseData(frame);
                break;
            case H2FrameType.WINDOW_UPDATE:
                processWindowUpdate(frame);
                break;
            case H2FrameType.PING:
                processPing(frame);
                break;
            case H2FrameType.GOAWAY:
                closed = true;
                break;
            default:
                break;
        }
    }

    void processSettings(ref H2Frame frame) nothrow @trusted
    {
        if (frame.flags & H2Flag.ACK)
        {
            settingsAckReceived = true;
            return;
        }
        if (frame.streamId != 0) return;

        auto payload = frame.payload;
        while (payload.length >= 6)
        {
            ushort id = cast(ushort)((payload[0] << 8) | payload[1]);
            uint val = (cast(uint) payload[2] << 24) | (cast(uint) payload[3] << 16)
                | (cast(uint) payload[4] << 8) | payload[5];
            payload = payload[6 .. $];

            switch (id)
            {
                case H2Setting.HEADER_TABLE_SIZE:
                    remoteSettings.headerTableSize = val;
                    decoder.maxDynamicTableSize = val;
                    break;
                case H2Setting.ENABLE_PUSH:
                    remoteSettings.enablePush = val != 0;
                    break;
                case H2Setting.MAX_CONCURRENT_STREAMS:
                    remoteSettings.maxConcurrentStreams = val;
                    break;
                case H2Setting.INITIAL_WINDOW_SIZE:
                    if (val <= 0x7FFF_FFFF)
                        remoteSettings.initialWindowSize = val;
                    break;
                case H2Setting.MAX_FRAME_SIZE:
                    if (val >= H2_DEFAULT_MAX_FRAME_SIZE && val <= H2_MAX_FRAME_SIZE)
                        remoteSettings.maxFrameSize = val;
                    break;
                case H2Setting.MAX_HEADER_LIST_SIZE:
                    remoteSettings.maxHeaderListSize = val;
                    break;
                default:
                    break;
            }
        }

        // Send SETTINGS ACK
        auto ack = encodeFrameHeader(0, H2FrameType.SETTINGS, H2Flag.ACK, 0);
        sendRawBytes(ack[]);
    }

    void processResponseHeaders(ref H2Frame frame) nothrow @trusted
    {
        auto payload = frame.payload;
        size_t offset = 0;

        if (frame.flags & H2Flag.PADDED)
        {
            if (payload.length < 1) return;
            offset = 1;
        }
        if (frame.flags & H2Flag.PRIORITY)
        {
            if (payload.length < offset + 5) return;
            offset += 5;
        }

        auto headerBlock = payload[offset .. $];
        auto headers = decoder.decode(headerBlock);

        if (frame.streamId > lastStreamId)
            lastStreamId = frame.streamId;

        // Dispatch 'response' callback for this stream
        if (engine !is null)
        {
            if (auto cbp = frame.streamId in responseCbs)
            {
                try
                {
                    auto hdrsObj = engine.newObject();
                    string statusStr;
                    foreach (ref hf; headers)
                    {
                        if (hf.name == ":status")
                            statusStr = hf.value;
                        else if (hf.name.length > 0)
                            engine.setProperty(hdrsObj, hf.name, engine.newString(hf.value));
                    }
                    if (statusStr.length > 0)
                        engine.setProperty(hdrsObj, ":status", engine.newString(statusStr));

                    // Create flags object with endStream indicator
                    auto flagsObj = engine.newObject();
                    bool es = (frame.flags & H2Flag.END_STREAM) != 0;
                    engine.setProperty(flagsObj, "endStream", engine.newBool(es));

                    JSHandle[2] callArgs = [hdrsObj, flagsObj];
                    pushAgnosticPending(engine, *cbp, callArgs[]);
                    engine.freeValue(hdrsObj);
                    engine.freeValue(flagsObj);
                }
                catch (Throwable) {}
            }
        }

        // If END_STREAM, dispatch 'end' callback
        if (frame.flags & H2Flag.END_STREAM)
        {
            dispatchEndCallback(frame.streamId);
        }
    }

    void processResponseData(ref H2Frame frame) nothrow @trusted
    {
        if (frame.streamId == 0) return;

        connectionRecvWindow -= cast(int) frame.length;
        if (connectionRecvWindow < H2_DEFAULT_WINDOW_SIZE / 2)
        {
            int increment = H2_DEFAULT_WINDOW_SIZE - connectionRecvWindow;
            sendWindowUpdate(0, increment);
            connectionRecvWindow += increment;
        }

        // Dispatch 'data' callback for this stream
        if (engine !is null)
        {
            if (auto cbp = frame.streamId in dataCbs)
            {
                try
                {
                    auto bufStr = engine.newString(
                        cast(string) cast(const(char)[]) frame.payload);
                    JSHandle[1] callArgs = [bufStr];
                    pushAgnosticPending(engine, *cbp, callArgs[]);
                    engine.freeValue(bufStr);
                }
                catch (Throwable) {}
            }
        }

        // If END_STREAM, dispatch 'end' callback
        if (frame.flags & H2Flag.END_STREAM)
        {
            dispatchEndCallback(frame.streamId);
        }
    }

    void processWindowUpdate(ref H2Frame frame) nothrow @trusted
    {
        if (frame.payload.length < 4) return;
        uint increment = ((cast(uint) frame.payload[0] << 24)
            | (cast(uint) frame.payload[1] << 16)
            | (cast(uint) frame.payload[2] << 8)
            | frame.payload[3]) & 0x7FFF_FFFF;

        if (increment == 0) return;
        if (frame.streamId == 0)
            connectionSendWindow += increment;
    }

    void processPing(ref H2Frame frame) nothrow @trusted
    {
        if (frame.flags & H2Flag.ACK) return;
        if (frame.streamId != 0 || frame.payload.length != 8) return;
        auto pong = encodeFrameHeader(8, H2FrameType.PING, H2Flag.ACK, 0);
        sendRawBytes(pong[]);
        sendRawBytes(frame.payload);
    }

    void dispatchEndCallback(uint streamId) nothrow @trusted
    {
        if (engine is null) return;
        if (auto cbp = streamId in endCbs)
        {
            try
            {
                JSHandle[0] noArgs;
                pushAgnosticPending(engine, *cbp, noArgs[]);
            }
            catch (Throwable) {}
        }
    }

    void sendRawBytes(const(ubyte)[] data) nothrow @trusted
    {
        version (Posix)
        {
            if (fd < 0 || data.length == 0 || connectPending) return;

            if (sslPtr !is null)
            {
                import dun.platform.openssl : SSL, SSL_write;
                auto ssl = cast(SSL*) sslPtr;
                size_t sent = 0;
                while (sent < data.length)
                {
                    auto n = SSL_write(ssl, data.ptr + sent,
                        cast(int)(data.length - sent));
                    if (n <= 0) break;
                    sent += n;
                }
            }
            else
            {
                import core.sys.posix.sys.socket : send, MSG_NOSIGNAL;
                size_t sent = 0;
                while (sent < data.length)
                {
                    auto n = send(fd, data.ptr + sent, data.length - sent, MSG_NOSIGNAL);
                    if (n <= 0) break;
                    sent += n;
                }
            }
        }
    }

    void sendRawBytes(const(char)[] data) nothrow @trusted
    {
        sendRawBytes(cast(const(ubyte)[]) data);
    }

    void closeConnection() nothrow @trusted
    {
        version (Posix)
        {
            if (fd >= 0)
            {
                version (linux) { if (gH2PollerInited) gH2Poller.unwatch(fd); }
                if (sslPtr !is null)
                {
                    import dun.platform.openssl : SSL, SSL_shutdown, SSL_free;
                    auto ssl = cast(SSL*) sslPtr;
                    SSL_shutdown(ssl);
                    SSL_free(ssl);
                    sslPtr = null;
                }
                import core.sys.posix.unistd : close;
                close(fd);
                fd = -1;
            }
        }
        closed = true;
    }
}

ClientH2Session[] h2ClientSessions;
int nextH2ClientSessionId;

version (linux)
{
    import dun.loop.iopoller : IOPoller, IOEvent;
    private IOPoller gH2Poller;
    private bool gH2PollerInited = false;

    private void ensureH2Poller() nothrow @trusted
    {
        if (!gH2PollerInited) { gH2Poller.initialize(); gH2PollerInited = true; }
    }
}

JSHandle makeHttp2Constants(IJSEngine engine) @trusted
{
    auto obj = engine.newObject();
    engine.setProperty(obj, "HTTP2_HEADER_METHOD", engine.newString(":method"));
    engine.setProperty(obj, "HTTP2_HEADER_PATH", engine.newString(":path"));
    engine.setProperty(obj, "HTTP2_HEADER_SCHEME", engine.newString(":scheme"));
    engine.setProperty(obj, "HTTP2_HEADER_STATUS", engine.newString(":status"));
    engine.setProperty(obj, "HTTP2_HEADER_AUTHORITY", engine.newString(":authority"));
    engine.setProperty(obj, "HTTP2_HEADER_CONTENT_TYPE", engine.newString("content-type"));
    engine.setProperty(obj, "HTTP2_HEADER_CONTENT_LENGTH", engine.newString("content-length"));
    engine.setProperty(obj, "NGHTTP2_NO_ERROR", engine.newInt(0));
    engine.setProperty(obj, "NGHTTP2_PROTOCOL_ERROR", engine.newInt(1));
    engine.setProperty(obj, "NGHTTP2_INTERNAL_ERROR", engine.newInt(2));
    engine.setProperty(obj, "NGHTTP2_FLOW_CONTROL_ERROR", engine.newInt(3));
    engine.setProperty(obj, "NGHTTP2_CANCEL", engine.newInt(8));
    return obj;
}

// ── JS API: createServer (cleartext h2c) ─────────────────────────

JSHandle jsHttp2CreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;

    JSHandle cb;
    bool hasCb = false;
    if (args.length >= 1 && engine.isFunction(args[0]))
    {
        cb = engine.dupValue(args[0]);
        hasCb = true;
    }

    int id = nextH2ServerId++;
    try
    {
        H2ServerState srv;
        srv.engine = engine;
        srv.secure = false;
        if (hasCb) { srv.requestCb = cb; srv.hasCb = true; }
        h2Servers ~= srv;
    }
    catch (Throwable)
    {
        if (hasCb) engine.freeValue(cb);
        return engine.throwTypeError("http2.createServer: allocation failed");
    }
    return makeH2ServerObj(engine, id);
}

// ── JS API: createSecureServer (h2 over TLS) ────────────────────

JSHandle jsHttp2CreateSecureServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    version (Posix)
    {
        auto state = ctxState(ctx);
        auto engine = state.engine;

        JSHandle cb;
        bool hasCb = false;
        string certFile, keyFile;

        if (args.length >= 1 && engine.isObject(args[0]))
        {
            auto opts = args[0];
            auto certVal = engine.getProperty(opts, "cert");
            if (engine.isString(certVal))
                certFile = engine.extractString(certVal);
            engine.freeValue(certVal);

            auto keyVal = engine.getProperty(opts, "key");
            if (engine.isString(keyVal))
                keyFile = engine.extractString(keyVal);
            engine.freeValue(keyVal);
        }

        if (args.length >= 2 && engine.isFunction(args[1]))
        {
            cb = engine.dupValue(args[1]);
            hasCb = true;
        }
        else if (args.length >= 1 && engine.isFunction(args[0]))
        {
            cb = engine.dupValue(args[0]);
            hasCb = true;
        }

        int id = nextH2ServerId++;
        try
        {
            H2ServerState srv;
            srv.engine = engine;
            srv.secure = true;
            if (hasCb) { srv.requestCb = cb; srv.hasCb = true; }

            import dun.platform.openssl;
            ensureTlsServerInit();

            auto sslCtx = SSL_CTX_new(TLS_method());
            if (sslCtx is null)
            {
                if (hasCb) engine.freeValue(cb);
                return engine.throwTypeError("http2: SSL_CTX_new failed");
            }

            SSL_CTX_set_options(sslCtx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3);
            SSL_CTX_ctrl(sslCtx, SSL_CTRL_SET_MIN_PROTO_VERSION, TLS1_2_VERSION, null);

            // Set ALPN to advertise h2
            static immutable ubyte[] alpnProtos = [2, 'h', '2'];
            SSL_CTX_set_alpn_protos(sslCtx, alpnProtos.ptr, cast(uint) alpnProtos.length);

            if (certFile.length > 0 && keyFile.length > 0)
            {
                import std.string : toStringz;
                if (SSL_CTX_use_certificate_file(sslCtx, certFile.toStringz, SSL_FILETYPE_PEM) != 1
                    || SSL_CTX_use_PrivateKey_file(sslCtx, keyFile.toStringz, SSL_FILETYPE_PEM) != 1
                    || SSL_CTX_check_private_key(sslCtx) != 1)
                {
                    SSL_CTX_free(sslCtx);
                    if (hasCb) engine.freeValue(cb);
                    return engine.throwTypeError("http2: certificate/key error");
                }
            }

            srv.sslCtx = cast(void*) sslCtx;
            h2Servers ~= srv;
        }
        catch (Throwable)
        {
            if (hasCb) engine.freeValue(cb);
            return engine.throwTypeError("http2.createSecureServer: allocation failed");
        }
        return makeH2ServerObj(engine, id);
    }
    else
    {
        auto state = ctxState(ctx);
        return state.engine.throwTypeError("http2: TLS not supported on this platform");
    }
}

void ensureTlsServerInit() nothrow @trusted
{
    version (Posix)
    {
        import dun.platform.openssl;
        static __gshared bool inited = false;
        if (inited) return;
        OPENSSL_init_ssl(
            OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);
        inited = true;
    }
}

// ── JS API: connect (client) ─────────────────────────────────────

// Parse an HTTP/2 URL into host, port, and scheme.
// Supports "http://host:port" and "https://host:port" forms.
void parseH2Url(string url, out string host, out ushort port, out bool useTls) nothrow @trusted
{
    useTls = false;
    host = "localhost";
    port = 80;

    string rest = url;
    if (rest.length >= 8 && rest[0 .. 8] == "https://")
    {
        useTls = true;
        port = 443;
        rest = rest[8 .. $];
    }
    else if (rest.length >= 7 && rest[0 .. 7] == "http://")
    {
        rest = rest[7 .. $];
    }

    // Strip path
    size_t pathIdx = rest.length;
    foreach (i, c; rest)
    {
        if (c == '/')
        {
            pathIdx = i;
            break;
        }
    }
    rest = rest[0 .. pathIdx];

    // Split host:port
    size_t colonIdx = rest.length;
    foreach (i, c; rest)
    {
        if (c == ':')
        {
            colonIdx = i;
            break;
        }
    }

    if (colonIdx < rest.length)
    {
        host = rest[0 .. colonIdx];
        auto portStr = rest[colonIdx + 1 .. $];
        uint p = 0;
        foreach (c; portStr)
        {
            if (c >= '0' && c <= '9')
                p = p * 10 + (c - '0');
            else
                break;
        }
        if (p > 0 && p <= 65535)
            port = cast(ushort) p;
    }
    else
    {
        host = rest;
    }

    if (host.length == 0) host = "localhost";
}

JSHandle jsHttp2Connect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("http2.connect: URL string required");

    auto url = engine.extractString(args[0]);
    ensureH2FnsCached(engine);

    // Parse URL
    string host;
    ushort port;
    bool useTls;
    parseH2Url(url, host, port, useTls);

    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.netdb : getaddrinfo, addrinfo, freeaddrinfo;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;
        import core.stdc.errno : errno, EINPROGRESS;
        import std.string : toStringz;

        // Create TCP socket
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0)
            return engine.throwTypeError("http2.connect: socket() failed");

        // Resolve host
        sockaddr_in addr;
        memset(&addr, 0, addr.sizeof);
        addr.sin_family = AF_INET;
        addr.sin_port = htons(port);

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
            return engine.throwTypeError("http2.connect: host resolution failed");
        }

        // Set non-blocking + TCP_NODELAY
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        int one = 1;
        enum IPPROTO_TCP = 6;
        enum TCP_NODELAY = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, one.sizeof);

        // Attempt TCP connect
        import core.sys.posix.sys.socket : connect;
        int r = connect(fd, cast(sockaddr*)&addr, addr.sizeof);
        bool immediateConnect = (r == 0);
        bool pending = (!immediateConnect && errno == EINPROGRESS);

        if (!immediateConnect && !pending)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            return engine.throwTypeError("http2.connect: connect() failed");
        }

        // Allocate client session
        int sessionId = nextH2ClientSessionId++;
        try
        {
            ClientH2Session session;
            session.engine = engine;
            session.fd = fd;
            session.host = host;
            session.port = port;
            session.connectPending = pending;
            session.connected = immediateConnect;

            // TLS setup only when immediately connected (TLS needs completed TCP)
            if (immediateConnect && useTls)
            {
                import dun.platform.openssl;
                ensureTlsServerInit();

                auto sslCtx = SSL_CTX_new(TLS_method());
                if (sslCtx !is null)
                {
                    SSL_CTX_set_options(sslCtx, SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3);
                    SSL_CTX_ctrl(sslCtx, SSL_CTRL_SET_MIN_PROTO_VERSION, TLS1_2_VERSION, null);

                    static immutable ubyte[] alpnProtos = [2, 'h', '2'];
                    SSL_CTX_set_alpn_protos(sslCtx, alpnProtos.ptr, cast(uint) alpnProtos.length);

                    auto ssl = SSL_new(sslCtx);
                    if (ssl !is null)
                    {
                        SSL_set_fd(ssl, fd);
                        enum SSL_CTRL_SET_TLSEXT_HOSTNAME = 55;
                        enum TLSEXT_NAMETYPE_host_name = 0;
                        SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME,
                            TLSEXT_NAMETYPE_host_name, cast(void*) host.toStringz);

                        int ret = SSL_connect(ssl);
                        if (ret != 1)
                            SSL_free(ssl);
                        else
                            session.sslPtr = cast(void*) ssl;
                    }
                    SSL_CTX_free(sslCtx);
                }
            }

            // Send connection preface only if TCP is already connected
            // (not pending EINPROGRESS — preface will be sent on connect completion)
            if (immediateConnect)
                session.sendConnectionPreface();

            h2ClientSessions ~= session;
        }
        catch (Throwable)
        {
            import core.sys.posix.unistd : close;
            close(fd);
            return engine.throwTypeError("http2.connect: allocation failed");
        }

        // Register with IO poller for async response reading and connect completion
        version (linux)
        {
            ensureH2Poller();
            gH2Poller.watch(fd, true, true); // readable + writable (for connect completion)
        }

        // Build the session JS object
        auto obj = engine.newObject();
        engine.setProperty(obj, "__h2_csid", engine.newInt(sessionId));
        engine.setProperty(obj, "__h2_url", engine.newString(url));
        engine.bindMethod(obj, "request", _h2ClientReq);
        engine.bindMethod(obj, "close", _h2ClientClose);
        engine.bindMethod(obj, "on", _h2ClientSessionOn);
        return obj;
    }
    else
    {
        // Non-Posix: return a stub object (no TCP support)
        auto obj = engine.newObject();
        engine.setProperty(obj, "__h2_csid", engine.newInt(-1));
        engine.setProperty(obj, "__h2_url", engine.newString(url));
        engine.bindMethod(obj, "request", _h2ClientReq);
        engine.bindMethod(obj, "close", _h2ClientClose);
        engine.bindMethod(obj, "on", _h2ClientSessionOn);
        return obj;
    }
}

JSHandle jsH2ClientSessionOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    if (args.length < 2 || !engine.isFunction(args[1])) return engine.dupValue(thisVal);

    auto sidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(sidProp);
    engine.freeValue(sidProp);
    if (sessionId < 0 || sessionId >= cast(int) h2ClientSessions.length) return engine.dupValue(thisVal);

    auto ev = engine.extractString(args[0]);
    auto session = &h2ClientSessions[sessionId];

    if (ev == "connect")
    {
        if (session.hasConnectCb) engine.freeValue(session.connectCb);
        session.connectCb = engine.dupValue(args[1]);
        session.hasConnectCb = true;
    }
    else if (ev == "error")
    {
        if (session.hasErrorSessionCb) engine.freeValue(session.errorSessionCb);
        session.errorSessionCb = engine.dupValue(args[1]);
        session.hasErrorSessionCb = true;
    }
    return engine.dupValue(thisVal);
}

JSHandle jsH2ClientRequest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    ensureH2FnsCached(engine);

    // Get session ID from thisVal
    auto sidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(sidProp);
    engine.freeValue(sidProp);

    if (sessionId < 0 || sessionId >= cast(int) h2ClientSessions.length)
    {
        // Fallback: return a stub stream object for non-connected sessions
        auto streamObj = engine.newObject();
        engine.bindMethod(streamObj, "on", _h2StreamOn);
        engine.bindMethod(streamObj, "end", _h2StreamEnd);
        engine.bindMethod(streamObj, "write", _h2StreamWrite);
        return streamObj;
    }

    auto session = &h2ClientSessions[sessionId];

    // Parse headers from first argument
    HeaderField[] h2Headers;
    string method = "GET";
    string path = "/";
    string scheme = "http";
    string authority = session.host;
    if (session.port != 80 && session.port != 443)
    {
        import std.conv : to;
        try { authority = session.host ~ ":" ~ session.port.to!string; }
        catch (Throwable) {}
    }

    if (args.length >= 1 && engine.isObject(args[0]))
    {
        auto hdrsObj = args[0];

        auto methodVal = engine.getProperty(hdrsObj, ":method");
        if (engine.isString(methodVal)) method = engine.extractString(methodVal);
        engine.freeValue(methodVal);

        auto pathVal = engine.getProperty(hdrsObj, ":path");
        if (engine.isString(pathVal)) path = engine.extractString(pathVal);
        engine.freeValue(pathVal);

        auto schemeVal = engine.getProperty(hdrsObj, ":scheme");
        if (engine.isString(schemeVal)) scheme = engine.extractString(schemeVal);
        engine.freeValue(schemeVal);

        auto authVal = engine.getProperty(hdrsObj, ":authority");
        if (engine.isString(authVal)) authority = engine.extractString(authVal);
        engine.freeValue(authVal);
    }

    // Allocate stream ID (odd for client)
    uint streamId = session.allocateStreamId();

    // Build HPACK headers
    try
    {
        h2Headers ~= HeaderField(":method", method);
        h2Headers ~= HeaderField(":path", path);
        h2Headers ~= HeaderField(":scheme", scheme);
        h2Headers ~= HeaderField(":authority", authority);
    }
    catch (Throwable)
    {
        auto streamObj = engine.newObject();
        engine.bindMethod(streamObj, "on", _h2StreamOn);
        engine.bindMethod(streamObj, "end", _h2StreamEnd);
        engine.bindMethod(streamObj, "write", _h2StreamWrite);
        return streamObj;
    }

    // Send HEADERS frame (don't end stream yet — user may write body or call end())
    bool endStream = (method == "GET" || method == "HEAD");
    session.sendHeaders(streamId, h2Headers, endStream);

    // Build the stream JS object
    auto streamObj = engine.newObject();
    engine.setProperty(streamObj, "__h2_csid", engine.newInt(sessionId));
    engine.setProperty(streamObj, "__h2_stream_id", engine.newInt(cast(int) streamId));
    engine.bindMethod(streamObj, "on", _h2StreamOn);
    engine.bindMethod(streamObj, "end", _h2StreamEnd);
    engine.bindMethod(streamObj, "write", _h2StreamWrite);
    return streamObj;
}

JSHandle jsH2ClientClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    auto sidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(sidProp);
    engine.freeValue(sidProp);

    if (sessionId >= 0 && sessionId < cast(int) h2ClientSessions.length)
    {
        auto session = &h2ClientSessions[sessionId];
        if (!session.closed)
        {
            // Only send GOAWAY if the connection is established
            if (session.connected && !session.connectPending)
                session.sendGoaway(H2Error.NO_ERROR);
            session.closeConnection();
        }
    }
    return engine.newUndefined();
}

// ── Client Stream event handlers ────────────────────────────────

JSHandle jsH2StreamOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    if (args.length < 2 || !engine.isFunction(args[1])) return engine.dupValue(thisVal);

    auto csidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(csidProp);
    engine.freeValue(csidProp);

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);

    if (sessionId < 0 || sessionId >= cast(int) h2ClientSessions.length)
        return engine.dupValue(thisVal);

    auto session = &h2ClientSessions[sessionId];
    auto ev = engine.extractString(args[0]);
    auto cb = engine.dupValue(args[1]);

    try
    {
        if (ev == "response")
            session.responseCbs[streamId] = cb;
        else if (ev == "data")
            session.dataCbs[streamId] = cb;
        else if (ev == "end")
            session.endCbs[streamId] = cb;
        else if (ev == "error")
            session.errorCbs[streamId] = cb;
        else
            engine.freeValue(cb);
    }
    catch (Throwable)
    {
        engine.freeValue(cb);
    }
    return engine.dupValue(thisVal);
}

JSHandle jsH2StreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    auto csidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(csidProp);
    engine.freeValue(csidProp);

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);

    if (sessionId < 0 || sessionId >= cast(int) h2ClientSessions.length)
        return engine.newUndefined();

    auto session = &h2ClientSessions[sessionId];

    // If there's a body argument, send it as DATA + END_STREAM
    if (args.length >= 1 && engine.isString(args[0]))
    {
        auto body_ = engine.extractString(args[0]);
        session.sendData(streamId, cast(const(ubyte)[]) body_, true);
    }
    else
    {
        // Just send empty DATA with END_STREAM
        session.sendData(streamId, null, true);
    }
    return engine.newUndefined();
}

JSHandle jsH2StreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    assert(state.engine !is null);
    auto engine = state.engine;

    if (args.length < 1) return engine.newBool(false);

    auto csidProp = engine.getProperty(thisVal, "__h2_csid");
    int sessionId = engine.extractInt(csidProp);
    engine.freeValue(csidProp);

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);

    if (sessionId < 0 || sessionId >= cast(int) h2ClientSessions.length)
        return engine.newBool(false);

    auto session = &h2ClientSessions[sessionId];
    auto body_ = engine.extractString(args[0]);
    session.sendData(streamId, cast(const(ubyte)[]) body_, false);
    return engine.newBool(true);
}

// ── Server object ────────────────────────────────────────────────

JSHandle makeH2ServerObj(IJSEngine engine, int id) @trusted
{
    ensureH2FnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__h2sid", engine.newInt(id));
    engine.bindMethod(obj, "listen", _h2SrvListen);
    engine.bindMethod(obj, "close", _h2SrvClose);
    engine.bindMethod(obj, "on", _h2SrvOn);
    return obj;
}

JSHandle jsH2ServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    version (Posix)
    {
        import core.sys.posix.sys.socket;
        import core.sys.posix.netinet.in_;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.string : memset;

        auto state = ctxState(ctx);
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__h2sid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal < 0 || idVal >= cast(int) h2Servers.length)
            return engine.throwTypeError("h2 server.listen: invalid server");

        auto srv = &h2Servers[idVal];
        int port = H2_DEFAULT_TLS_PORT;
        JSHandle listenCb;
        bool hasCb = false;

        if (args.length >= 1 && engine.isNumber(args[0]))
            port = engine.extractInt(args[0]);
        if (args.length >= 2 && engine.isFunction(args[1]))
        {
            listenCb = engine.dupValue(args[1]);
            hasCb = true;
        }

        int lfd = socket(AF_INET, SOCK_STREAM, 0);
        if (lfd < 0)
        {
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("h2 server: socket() failed");
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
            return engine.throwTypeError("h2 server: bind() failed");
        }
        if (listen(lfd, H2_LISTEN_BACKLOG) < 0)
        {
            import core.sys.posix.unistd : close;
            close(lfd);
            if (hasCb) engine.freeValue(listenCb);
            return engine.throwTypeError("h2 server: listen() failed");
        }

        srv.listenFd = lfd;
        srv.active = true;
        srv.port = cast(ushort) port;

        version (linux)
        {
            ensureH2Poller();
            gH2Poller.watch(lfd, true, false);
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
        auto state = ctxState(ctx);
        return state.engine.throwTypeError("h2 server not supported on this platform");
    }
}

JSHandle jsH2ServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    version (Posix)
    {
        import core.sys.posix.unistd : close;
        auto state = ctxState(ctx);
        auto engine = state.engine;

        auto idProp = engine.getProperty(thisVal, "__h2sid");
        int idVal = engine.extractInt(idProp);
        engine.freeValue(idProp);
        if (idVal >= 0 && idVal < cast(int) h2Servers.length)
        {
            auto srv = &h2Servers[idVal];
            if (srv.listenFd >= 0)
            {
                version (linux) gH2Poller.unwatch(srv.listenFd);
                close(srv.listenFd);
                srv.listenFd = -1;
            }
            srv.active = false;
        }
        return engine.newUndefined();
    }
    else
    {
        auto state = ctxState(ctx);
        return state.engine.newUndefined();
    }
}

JSHandle jsH2ServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 2) return engine.dupValue(thisVal);

    auto idProp = engine.getProperty(thisVal, "__h2sid");
    int idVal = engine.extractInt(idProp);
    engine.freeValue(idProp);
    if (idVal < 0 || idVal >= cast(int) h2Servers.length) return engine.dupValue(thisVal);

    auto ev = engine.extractString(args[0]);
    if ((ev == "stream" || ev == "request") && engine.isFunction(args[1]))
    {
        auto srv = &h2Servers[idVal];
        if (srv.hasCb) engine.freeValue(srv.requestCb);
        srv.requestCb = engine.dupValue(args[1]);
        srv.hasCb = true;
    }
    return engine.dupValue(thisVal);
}

// ── HTTP/2 Response Object ───────────────────────────────────────

JSHandle makeH2ResponseObj(IJSEngine engine, ref H2Connection conn, uint streamId) @trusted
{
    ensureH2FnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__h2_stream_id", engine.newInt(cast(int) streamId));
    engine.bindMethod(obj, "writeHead", _h2ResWriteHead);
    engine.bindMethod(obj, "write", _h2ResWrite);
    engine.bindMethod(obj, "end", _h2ResEnd);
    engine.bindMethod(obj, "setHeader", _h2ResSetHeader);
    return obj;
}

// Store per-stream response state
struct H2ResponseState
{
    uint streamId;
    int connIdx = -1;
    int statusCode = 200;
    HeaderField[] pendingHeaders;
    bool headersSent;
}

H2ResponseState[] h2ResponseStates;

int findOrCreateResponseState(uint streamId) nothrow @trusted
{
    foreach (i, ref rs; h2ResponseStates)
        if (rs.streamId == streamId) return cast(int) i;
    try
    {
        H2ResponseState rs;
        rs.streamId = streamId;
        h2ResponseStates ~= rs;
        return cast(int)(h2ResponseStates.length - 1);
    }
    catch (Throwable) { return -1; }
}

JSHandle jsH2ResWriteHead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);
    int rsIdx = findOrCreateResponseState(streamId);
    if (rsIdx < 0) return engine.newUndefined();

    auto rs = &h2ResponseStates[rsIdx];
    if (args.length >= 1 && engine.isNumber(args[0]))
        rs.statusCode = engine.extractInt(args[0]);

    return engine.newUndefined();
}

JSHandle jsH2ResSetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 2) return engine.newUndefined();

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);
    int rsIdx = findOrCreateResponseState(streamId);
    if (rsIdx < 0) return engine.newUndefined();

    try
    {
        string name = engine.extractString(args[0]);
        string val = engine.extractString(args[1]);
        h2ResponseStates[rsIdx].pendingHeaders ~= HeaderField(name, val);
    }
    catch (Exception) {}
    return engine.newUndefined();
}

JSHandle jsH2ResWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);
    int rsIdx = findOrCreateResponseState(streamId);
    if (rsIdx < 0) return engine.newBool(false);

    auto rs = &h2ResponseStates[rsIdx];
    if (!rs.headersSent)
    {
        rs.headersSent = true;
        sendH2ResponseHeaders(streamId, rs);
    }

    auto body_ = engine.extractString(args[0]);
    foreach (ref conn; h2Connections)
    {
        if (!conn.closed && streamId in conn.streams)
        {
            conn.sendData(streamId, cast(const(ubyte)[]) body_, false);
            break;
        }
    }
    return engine.newBool(true);
}

JSHandle jsH2ResEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;

    auto sidProp = engine.getProperty(thisVal, "__h2_stream_id");
    uint streamId = cast(uint) engine.extractInt(sidProp);
    engine.freeValue(sidProp);
    int rsIdx = findOrCreateResponseState(streamId);
    if (rsIdx < 0) return engine.newUndefined();

    auto rs = &h2ResponseStates[rsIdx];
    string bodyData;
    if (args.length >= 1 && engine.isString(args[0]))
        bodyData = engine.extractString(args[0]);

    if (!rs.headersSent)
    {
        rs.headersSent = true;
        bool endStream = bodyData.length == 0;
        sendH2ResponseHeaders(streamId, rs);
    }

    foreach (ref conn; h2Connections)
    {
        if (!conn.closed && streamId in conn.streams)
        {
            conn.sendData(streamId, cast(const(ubyte)[]) bodyData, true);
            auto stream = streamId in conn.streams;
            if (stream !is null)
                stream.state = H2StreamState.halfClosedLocal;
            break;
        }
    }
    return engine.newUndefined();
}

void sendH2ResponseHeaders(uint streamId, H2ResponseState* rs) nothrow @trusted
{
    import std.conv : to;
    foreach (ref conn; h2Connections)
    {
        if (!conn.closed && streamId in conn.streams)
        {
            HeaderField[] headers;
            try
            {
                headers ~= HeaderField(":status", rs.statusCode.to!string);
                bool hasContentType = false;
                foreach (ref hf; rs.pendingHeaders)
                {
                    headers ~= hf;
                    if (hf.name == "content-type") hasContentType = true;
                }
                if (!hasContentType)
                    headers ~= HeaderField("content-type", "text/plain");
            }
            catch (Throwable) { return; }
            conn.sendHeaders(streamId, headers, false);
            break;
        }
    }
}

// ── I/O Polling ──────────────────────────────────────────────────

public void pollHttp2IO() nothrow @trusted
{
    version (linux)
    {
        ensureH2Poller();
        IOEvent[IO_POLL_BATCH_SIZE] evBuf;
        auto events = gH2Poller.poll(0, evBuf[]);
        foreach (ref ev; events)
        {
            foreach (i, ref srv; h2Servers)
                if (srv.active && srv.listenFd == ev.fd && ev.readable)
                    acceptH2Connection(cast(int) i);
            foreach (ref conn; h2Connections)
                if (!conn.closed && conn.fd == ev.fd && ev.readable)
                    readH2Data(conn);
            foreach (ref cs; h2ClientSessions)
            {
                if (cs.closed || cs.fd != ev.fd) continue;
                // Handle connect completion
                if (cs.connectPending && ev.writable)
                    completeH2ClientConnect(cs);
                if (!cs.closed && ev.readable)
                    readH2ClientData(cs);
            }
        }
    }
}

public bool hasActiveHttp2IO() @safe nothrow
{
    foreach (ref s; h2Servers) if (s.active) return true;
    foreach (ref c; h2Connections) if (!c.closed) return true;
    foreach (ref cs; h2ClientSessions) if (!cs.closed) return true;
    return false;
}

void acceptH2Connection(int srvId) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : accept;
        import core.sys.posix.fcntl : fcntl, F_SETFL, F_GETFL, O_NONBLOCK;
        import core.stdc.errno : errno, EAGAIN, EWOULDBLOCK;

        if (srvId < 0 || srvId >= cast(int) h2Servers.length) return;
        auto srv = &h2Servers[srvId];

        while (true)
        {
            int fd = accept(srv.listenFd, null, null);
            if (fd < 0) { if (errno == EAGAIN || errno == EWOULDBLOCK) break; break; }

            int fl = fcntl(fd, F_GETFL, 0);
            fcntl(fd, F_SETFL, fl | O_NONBLOCK);

            try
            {
                H2Connection conn;
                conn.engine = srv.engine;
                conn.fd = fd;
                conn.isServer = true;
                conn.srvId = srvId;

                if (srv.secure && srv.sslCtx !is null)
                {
                    import dun.platform.openssl : SSL, SSL_new, SSL_set_fd,
                        SSL_accept, SSL_CTX;
                    auto sslCtx = cast(SSL_CTX*) srv.sslCtx;
                    auto ssl = SSL_new(sslCtx);
                    if (ssl !is null)
                    {
                        SSL_set_fd(ssl, fd);
                        int ret = SSL_accept(ssl);
                        if (ret != 1)
                        {
                            import dun.platform.openssl : SSL_free;
                            SSL_free(ssl);
                            import core.sys.posix.unistd : close;
                            close(fd);
                            continue;
                        }
                        conn.sslPtr = cast(void*) ssl;
                    }
                }

                conn.sendConnectionPreface();
                h2Connections ~= conn;
            }
            catch (Throwable)
            {
                import core.sys.posix.unistd : close;
                close(fd);
                continue;
            }
            version (linux) gH2Poller.watch(fd, true, false);
        }
    }
}

void completeH2ClientConnect(ref ClientH2Session session) nothrow @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.socket : getsockopt, SOL_SOCKET, SO_ERROR;

        // Check if connection actually succeeded
        int err;
        uint errlen = err.sizeof;
        getsockopt(session.fd, SOL_SOCKET, SO_ERROR, &err, &errlen);

        session.connectPending = false;

        if (err != 0)
        {
            // Connection failed (e.g. ECONNREFUSED)
            session.closeConnection();
            return;
        }

        session.connected = true;

        // Now send the connection preface
        session.sendConnectionPreface();

        // Dispatch connect callback if registered
        if (session.hasConnectCb && session.engine !is null)
        {
            try
            {
                JSHandle[0] noArgs;
                pushAgnosticPending(session.engine, session.connectCb, noArgs[]);
            }
            catch (Throwable) {}
        }
    }
}

void readH2Data(ref H2Connection conn) nothrow @trusted
{
    version (Posix)
    {
        ubyte[H2_DEFAULT_MAX_FRAME_SIZE] buf;
        while (true)
        {
            int n;
            if (conn.sslPtr !is null)
            {
                import dun.platform.openssl : SSL, SSL_read;
                n = SSL_read(cast(SSL*) conn.sslPtr, buf.ptr, cast(int) buf.length);
            }
            else
            {
                import core.sys.posix.unistd : read;
                n = cast(int) read(conn.fd, buf.ptr, buf.length);
            }
            if (n <= 0) break;
            conn.processReceivedData(buf[0 .. n]);
        }
    }
}

void readH2ClientData(ref ClientH2Session session) nothrow @trusted
{
    version (Posix)
    {
        ubyte[H2_CLIENT_RECV_BUF_SIZE] buf;
        while (true)
        {
            int n;
            if (session.sslPtr !is null)
            {
                import dun.platform.openssl : SSL, SSL_read;
                n = SSL_read(cast(SSL*) session.sslPtr, buf.ptr, cast(int) buf.length);
            }
            else
            {
                import core.sys.posix.unistd : read;
                n = cast(int) read(session.fd, buf.ptr, buf.length);
            }
            if (n <= 0)
            {
                // Connection closed by peer
                if (n == 0 && !session.closed)
                    session.closed = true;
                break;
            }
            session.processReceivedData(buf[0 .. n]);
        }
    }
}

// ── Unit Tests ───────────────────────────────────────────────────

version (DunTest):

@("h2: frame header encode/decode roundtrip")
unittest
{
    auto hdr = encodeFrameHeader(256, H2FrameType.HEADERS, H2Flag.END_HEADERS, 1);
    H2Frame frame;
    assert(parseFrameHeader(hdr[], frame));
    assert(frame.length == 256);
    assert(frame.type == H2FrameType.HEADERS);
    assert(frame.flags == H2Flag.END_HEADERS);
    assert(frame.streamId == 1);
}

@("h2: frame header - zero length DATA")
unittest
{
    auto hdr = encodeFrameHeader(0, H2FrameType.DATA, H2Flag.END_STREAM, 3);
    H2Frame frame;
    assert(parseFrameHeader(hdr[], frame));
    assert(frame.length == 0);
    assert(frame.type == H2FrameType.DATA);
    assert(frame.flags == H2Flag.END_STREAM);
    assert(frame.streamId == 3);
}

@("h2: frame header - large payload length")
unittest
{
    auto hdr = encodeFrameHeader(H2_MAX_FRAME_SIZE, H2FrameType.DATA, H2Flag.NONE, 5);
    H2Frame frame;
    assert(parseFrameHeader(hdr[], frame));
    assert(frame.length == H2_MAX_FRAME_SIZE);
}

@("h2: frame header - SETTINGS stream 0")
unittest
{
    auto hdr = encodeFrameHeader(18, H2FrameType.SETTINGS, H2Flag.NONE, 0);
    H2Frame frame;
    assert(parseFrameHeader(hdr[], frame));
    assert(frame.type == H2FrameType.SETTINGS);
    assert(frame.streamId == 0);
}

@("h2: frame header - insufficient data")
unittest
{
    ubyte[5] short_;
    H2Frame frame;
    assert(!parseFrameHeader(short_[], frame));
}

@("h2: HPACK integer decode - small value")
unittest
{
    ubyte[1] data = [0x0A]; // 10 with 5-bit prefix
    size_t pos = 0;
    uint result;
    assert(decodeInt(data[], pos, 5, result));
    assert(result == 10);
    assert(pos == 1);
}

@("h2: HPACK integer decode - multibyte")
unittest
{
    // 1337 encoded with 5-bit prefix (RFC 7541 §C.1.2)
    ubyte[3] data = [0x1F, 0x9A, 0x0A];
    size_t pos = 0;
    uint result;
    assert(decodeInt(data[], pos, 5, result));
    assert(result == 1337);
}

@("h2: HPACK literal string decode")
unittest
{
    // Length 5, then "hello"
    ubyte[6] data = [0x05, 'h', 'e', 'l', 'l', 'o'];
    size_t pos = 0;
    string result;
    assert(decodeString(data[], pos, result));
    assert(result == "hello");
    assert(pos == 6);
}

@("h2: HPACK indexed header field")
unittest
{
    // Index 2 = :method GET
    ubyte[1] data = [0x82];
    HpackDecoder dec;
    auto headers = dec.decode(data[]);
    assert(headers.length == 1);
    assert(headers[0].name == ":method");
    assert(headers[0].value == "GET");
}

@("h2: HPACK indexed :path /")
unittest
{
    ubyte[1] data = [0x84];
    HpackDecoder dec;
    auto headers = dec.decode(data[]);
    assert(headers.length == 1);
    assert(headers[0].name == ":path");
    assert(headers[0].value == "/");
}

@("h2: HPACK encode/decode roundtrip")
unittest
{
    auto input = [
        HeaderField(":method", "GET"),
        HeaderField(":path", "/index.html"),
        HeaderField("content-type", "text/html"),
    ];
    auto encoded = hpackEncode(input);
    assert(encoded !is null);
    assert(encoded.length > 0);

    HpackDecoder dec;
    auto decoded = dec.decode(encoded);
    assert(decoded.length == 3);
    assert(decoded[0].name == ":method");
    assert(decoded[0].value == "GET");
    assert(decoded[1].name == ":path");
    assert(decoded[1].value == "/index.html");
    assert(decoded[2].name == "content-type");
    assert(decoded[2].value == "text/html");
}

@("h2: HPACK static table index lookup")
unittest
{
    assert(findStaticIndex(":method", "GET") == 2);
    assert(findStaticIndex(":method", "POST") == 3);
    assert(findStaticIndex(":path", "/") == 4);
    assert(findStaticIndex(":scheme", "https") == 7);
    assert(findStaticIndex(":status", "200") == 8);
    assert(findStaticIndex("nonexistent", "") == 0);
}

@("h2: settings encode")
unittest
{
    H2Settings s;
    auto encoded = encodeSettings(s);
    assert(encoded !is null);
    assert(encoded.length == 18); // 3 settings x 6 bytes each
}

@("h2: client preface constant")
unittest
{
    assert(H2_CLIENT_PREFACE.length == H2_CONNECTION_PREFACE_LEN);
    assert((cast(const(char)[]) H2_CLIENT_PREFACE) == "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n");
}

@("h2: frame types match RFC 9113")
unittest
{
    assert(cast(ubyte) H2FrameType.DATA == 0x0);
    assert(cast(ubyte) H2FrameType.HEADERS == 0x1);
    assert(cast(ubyte) H2FrameType.SETTINGS == 0x4);
    assert(cast(ubyte) H2FrameType.PING == 0x6);
    assert(cast(ubyte) H2FrameType.GOAWAY == 0x7);
    assert(cast(ubyte) H2FrameType.WINDOW_UPDATE == 0x8);
}
