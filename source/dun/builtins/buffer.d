module dun.builtins.buffer;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerBufferModule(IJSEngine engine) @trusted
{
    auto bufferClass = engine.newObject();

    engine.setProperty(bufferClass, "from", engine.newFunction(&jsBufferFrom, "from", 1));
    engine.setProperty(bufferClass, "alloc", engine.newFunction(&jsBufferAlloc, "alloc", 1));
    engine.setProperty(bufferClass, "allocUnsafe", engine.newFunction(&jsBufferAllocUnsafe, "allocUnsafe", 1));
    engine.setProperty(bufferClass, "isBuffer", engine.newFunction(&jsBufferIsBuffer, "isBuffer", 1));
    engine.setProperty(bufferClass, "concat", engine.newFunction(&jsBufferConcat, "concat", 1));
    engine.setProperty(bufferClass, "byteLength", engine.newFunction(&jsBufferByteLength, "byteLength", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "Buffer", bufferClass);
    engine.setProperty(global, "__dun_cjs_buffer__", bufferClass);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:buffer", &bufferModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "Buffer");
    }

    private extern (C) int bufferModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto bufObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_buffer__");
        JS_SetModuleExport(ctx, m, "Buffer", bufObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

// Cached Buffer method handles — registered once to avoid callback slot exhaustion
__gshared JSHandle _bufToString, _bufToJSON, _bufSlice, _bufCopy;
__gshared JSHandle _bufEquals, _bufIndexOf, _bufFill, _bufWrite;
__gshared JSHandle _bufReadUInt8, _bufWriteUInt8;
__gshared bool _bufFnsCached = false;

void ensureBufferFnsCached(IJSEngine engine) @trusted
{
    if (_bufFnsCached) return;
    _bufToString = engine.newFunction(&jsBufferToString, "toString", 1);
    _bufToJSON = engine.newFunction(&jsBufferToJSON, "toJSON", 0);
    _bufSlice = engine.newFunction(&jsBufferSlice, "slice", 2);
    _bufCopy = engine.newFunction(&jsBufferCopy, "copy", 1);
    _bufEquals = engine.newFunction(&jsBufferEquals, "equals", 1);
    _bufIndexOf = engine.newFunction(&jsBufferIndexOf, "indexOf", 1);
    _bufFill = engine.newFunction(&jsBufferFill, "fill", 1);
    _bufWrite = engine.newFunction(&jsBufferWrite, "write", 1);
    _bufReadUInt8 = engine.newFunction(&jsBufferReadUInt8, "readUInt8", 1);
    _bufWriteUInt8 = engine.newFunction(&jsBufferWriteUInt8, "writeUInt8", 2);
    _bufFnsCached = true;
}

JSHandle makeBufferObj(IJSEngine engine, const(ubyte)[] data) @trusted
{
    ensureBufferFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "__isBuffer", engine.newBool(true));
    engine.setProperty(obj, "length", engine.newInt(cast(int) data.length));

    try
    {
        engine.setProperty(obj, "__data", engine.newString(bytesToHex(data)));
    }
    catch (Exception)
    {
        engine.setProperty(obj, "__data", engine.newString(""));
    }

    engine.setProperty(obj, "toString", engine.dupValue(_bufToString));
    engine.setProperty(obj, "toJSON", engine.dupValue(_bufToJSON));
    engine.setProperty(obj, "slice", engine.dupValue(_bufSlice));
    engine.setProperty(obj, "copy", engine.dupValue(_bufCopy));
    engine.setProperty(obj, "equals", engine.dupValue(_bufEquals));
    engine.setProperty(obj, "indexOf", engine.dupValue(_bufIndexOf));
    engine.setProperty(obj, "fill", engine.dupValue(_bufFill));
    engine.setProperty(obj, "write", engine.dupValue(_bufWrite));
    engine.setProperty(obj, "readUInt8", engine.dupValue(_bufReadUInt8));
    engine.setProperty(obj, "writeUInt8", engine.dupValue(_bufWriteUInt8));
    return obj;
}

private immutable char[512] hexLUT = () {
    char[512] t;
    foreach (i; 0 .. 256)
    {
        t[i * 2]     = "0123456789abcdef"[i >> 4];
        t[i * 2 + 1] = "0123456789abcdef"[i & 0xF];
    }
    return t;
}();

string bytesToHex(const(ubyte)[] data) @trusted nothrow
{
    if (data.length == 0) return "";
    try
    {
        auto buf = new char[data.length * 2];
        foreach (i, b; data)
        {
            buf[i * 2]     = hexLUT[b * 2];
            buf[i * 2 + 1] = hexLUT[b * 2 + 1];
        }
        return cast(string) buf;
    }
    catch (Exception) { return ""; }
}

ubyte[] hexToBytes(string hex) @trusted
{
    if (hex.length % 2 != 0) return [];
    ubyte[] result;
    try
    {
        result = new ubyte[hex.length / 2];
        for (size_t i = 0; i < hex.length; i += 2)
        {
            result[i / 2] = cast(ubyte)(hexDigit(hex[i]) * 16 + hexDigit(hex[i + 1]));
        }
    }
    catch (Exception) { return []; }
    return result;
}

ubyte hexDigit(char c) pure @safe
{
    if (c >= '0' && c <= '9') return cast(ubyte)(c - '0');
    if (c >= 'a' && c <= 'f') return cast(ubyte)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return cast(ubyte)(c - 'A' + 10);
    return 0;
}

ubyte[] extractBytes(IJSEngine engine, JSHandle obj) @trusted
{
    auto hexVal = engine.getProperty(obj, "__data");
    auto hex = engine.extractString(hexVal);
    return hexToBytes(hex);
}

// Buffer.from(input, [encoding])
JSHandle jsBufferFrom(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("Buffer.from requires an argument");

    if (engine.isString(args[0]))
    {
        auto str = engine.extractString(args[0]);
        string encoding = "utf8";
        if (args.length >= 2 && engine.isString(args[1]))
            encoding = engine.extractString(args[1]);

        if (encoding == "hex")
        {
            auto bytes = hexToBytes(str);
            return makeBufferObj(engine, bytes);
        }
        else if (encoding == "base64")
        {
            try
            {
                import std.base64 : Base64;
                auto bytes = Base64.decode(str);
                return makeBufferObj(engine, bytes);
            }
            catch (Exception)
            {
                return makeBufferObj(engine, cast(ubyte[]) []);
            }
        }
        else
        {
            return makeBufferObj(engine, cast(const(ubyte)[]) str);
        }
    }

    // Array-like or Buffer
    if (engine.isObject(args[0]))
    {
        auto isBuf = engine.getProperty(args[0], "__isBuffer");
        if (engine.isBool(isBuf) && engine.extractBool(isBuf))
        {
            auto bytes = extractBytes(engine, args[0]);
            return makeBufferObj(engine, bytes);
        }

        // Try as array
        auto lenVal = engine.getProperty(args[0], "length");
        if (engine.isNumber(lenVal))
        {
            int len = engine.extractInt(lenVal);
            auto bytes = new ubyte[len];
            for (int i = 0; i < len; i++)
            {
                auto elem = engine.getPropertyIndex(args[0], cast(uint) i);
                if (engine.isNumber(elem))
                    bytes[i] = cast(ubyte) engine.extractInt(elem);
                engine.freeValue(elem);
            }
            return makeBufferObj(engine, bytes);
        }
    }

    return engine.throwTypeError("Buffer.from: unsupported argument type");
}

// Buffer.alloc(size, [fill], [encoding])
JSHandle jsBufferAlloc(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("Buffer.alloc requires a size");
    int size = engine.extractInt(args[0]);
    if (size < 0 || size > 1024 * 1024 * 1024)
        return engine.throwRangeError("Invalid buffer size");

    ubyte fillByte = 0;
    if (args.length >= 2 && engine.isNumber(args[1]))
        fillByte = cast(ubyte) engine.extractInt(args[1]);

    auto bytes = new ubyte[size];
    bytes[] = fillByte;
    return makeBufferObj(engine, bytes);
}

// Buffer.allocUnsafe(size)
JSHandle jsBufferAllocUnsafe(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("Buffer.allocUnsafe requires a size");
    int size = engine.extractInt(args[0]);
    if (size < 0 || size > 1024 * 1024 * 1024)
        return engine.throwRangeError("Invalid buffer size");

    auto bytes = new ubyte[size];
    return makeBufferObj(engine, bytes);
}

// Buffer.isBuffer(obj)
JSHandle jsBufferIsBuffer(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.newBool(false);
    auto isBuf = engine.getProperty(args[0], "__isBuffer");
    return engine.newBool(engine.isBool(isBuf) && engine.extractBool(isBuf));
}

// Buffer.concat(list, [totalLength])
JSHandle jsBufferConcat(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return makeBufferObj(engine, cast(ubyte[]) []);

    ubyte[] combined;
    auto lenVal = engine.getProperty(args[0], "length");
    if (!engine.isNumber(lenVal)) return makeBufferObj(engine, cast(ubyte[]) []);
    int count = engine.extractInt(lenVal);

    for (int i = 0; i < count; i++)
    {
        auto elem = engine.getPropertyIndex(args[0], cast(uint) i);
        if (engine.isObject(elem))
        {
            auto bytes = extractBytes(engine, elem);
            combined ~= bytes;
        }
        engine.freeValue(elem);
    }
    return makeBufferObj(engine, combined);
}

// Buffer.byteLength(string, [encoding])
JSHandle jsBufferByteLength(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newInt(0);
    if (engine.isString(args[0]))
    {
        auto str = engine.extractString(args[0]);
        return engine.newInt(cast(int) str.length);
    }
    if (engine.isObject(args[0]))
    {
        auto lenProp = engine.getProperty(args[0], "length");
        if (engine.isNumber(lenProp)) return lenProp;
    }
    return engine.newInt(0);
}

// buf.toString([encoding], [start], [end])
JSHandle jsBufferToString(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    string encoding = "utf8";
    if (args.length >= 1 && engine.isString(args[0]))
        encoding = engine.extractString(args[0]);

    int start = 0;
    int end = cast(int) bytes.length;
    if (args.length >= 2 && engine.isNumber(args[1]))
        start = engine.extractInt(args[1]);
    if (args.length >= 3 && engine.isNumber(args[2]))
        end = engine.extractInt(args[2]);

    if (start < 0) start = 0;
    if (end > cast(int) bytes.length) end = cast(int) bytes.length;
    if (start >= end) return engine.newString("");

    auto slice = bytes[start .. end];

    if (encoding == "hex")
    {
        return engine.newString(bytesToHex(slice));
    }
    else if (encoding == "base64")
    {
        try
        {
            import std.base64 : Base64;
            return engine.newString(Base64.encode(slice));
        }
        catch (Exception) { return engine.newString(""); }
    }
    else
    {
        return engine.newString(cast(string) slice.idup);
    }
}

// buf.toJSON()
JSHandle jsBufferToJSON(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    auto obj = engine.newObject();
    engine.setProperty(obj, "type", engine.newString("Buffer"));
    auto arr = engine.newArray();
    foreach (i, b; bytes)
        engine.setPropertyIndex(arr, cast(uint) i, engine.newInt(cast(int) b));
    engine.setProperty(obj, "data", arr);
    return obj;
}

// buf.slice([start], [end])
JSHandle jsBufferSlice(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int start = 0;
    int end = cast(int) bytes.length;
    if (args.length >= 1 && engine.isNumber(args[0]))
        start = engine.extractInt(args[0]);
    if (args.length >= 2 && engine.isNumber(args[1]))
        end = engine.extractInt(args[1]);

    if (start < 0) start = cast(int) bytes.length + start;
    if (end < 0) end = cast(int) bytes.length + end;
    if (start < 0) start = 0;
    if (end > cast(int) bytes.length) end = cast(int) bytes.length;
    if (start >= end) return makeBufferObj(engine, cast(ubyte[]) []);

    return makeBufferObj(engine, bytes[start .. end]);
}

// buf.copy(target)
JSHandle jsBufferCopy(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto srcBytes = extractBytes(engine, thisVal);
    return engine.newInt(cast(int) srcBytes.length);
}

// buf.equals(other)
JSHandle jsBufferEquals(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.newBool(false);
    auto a = extractBytes(engine, thisVal);
    auto b = extractBytes(engine, args[0]);
    return engine.newBool(a == b);
}

// buf.indexOf(value)
JSHandle jsBufferIndexOf(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newInt(-1);
    auto bytes = extractBytes(engine, thisVal);

    if (engine.isString(args[0]))
    {
        auto needle = cast(const(ubyte)[]) engine.extractString(args[0]);
        for (size_t i = 0; i + needle.length <= bytes.length; i++)
        {
            if (bytes[i .. i + needle.length] == needle)
                return engine.newInt(cast(int) i);
        }
        return engine.newInt(-1);
    }
    if (engine.isNumber(args[0]))
    {
        ubyte val = cast(ubyte) engine.extractInt(args[0]);
        foreach (i, b; bytes)
            if (b == val) return engine.newInt(cast(int) i);
        return engine.newInt(-1);
    }
    return engine.newInt(-1);
}

// buf.fill(value)
JSHandle jsBufferFill(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return thisVal;
    auto bytes = extractBytes(engine, thisVal);

    ubyte fillVal = 0;
    if (engine.isNumber(args[0]))
        fillVal = cast(ubyte) engine.extractInt(args[0]);
    else if (engine.isString(args[0]))
    {
        auto s = engine.extractString(args[0]);
        if (s.length > 0) fillVal = cast(ubyte) s[0];
    }

    bytes[] = fillVal;
    engine.setProperty(thisVal, "__data", engine.newString(bytesToHex(bytes)));
    return thisVal;
}

// buf.write(string, [offset])
JSHandle jsBufferWrite(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newInt(0);

    auto bytes = extractBytes(engine, thisVal);
    auto str = engine.extractString(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1]))
        offset = engine.extractInt(args[1]);

    int written = 0;
    auto src = cast(const(ubyte)[]) str;
    for (size_t i = 0; i < src.length && offset + i < bytes.length; i++)
    {
        bytes[offset + i] = src[i];
        written++;
    }

    engine.setProperty(thisVal, "__data", engine.newString(bytesToHex(bytes)));
    return engine.newInt(written);
}

// buf.readUInt8([offset])
JSHandle jsBufferReadUInt8(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0]))
        offset = engine.extractInt(args[0]);
    if (offset < 0 || offset >= cast(int) bytes.length)
        return engine.throwRangeError("Offset out of range");
    return engine.newInt(cast(int) bytes[offset]);
}

// buf.writeUInt8(value, [offset])
JSHandle jsBufferWriteUInt8(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("writeUInt8 requires a value");

    auto bytes = extractBytes(engine, thisVal);
    int value = engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1]))
        offset = engine.extractInt(args[1]);
    if (offset < 0 || offset >= cast(int) bytes.length)
        return engine.throwRangeError("Offset out of range");

    bytes[offset] = cast(ubyte) value;
    engine.setProperty(thisVal, "__data", engine.newString(bytesToHex(bytes)));
    return engine.newInt(offset + 1);
}
