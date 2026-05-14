module dun.builtins.buffer;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum BUFFER_MAX_SIZE = 1024 * 1024 * 1024;

void registerBufferModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerBufferModule");
    auto bufferClass = engine.newObject();

    engine.setProperty(bufferClass, "from", engine.newFunction(&jsBufferFrom, "from", 1));
    engine.setProperty(bufferClass, "alloc", engine.newFunction(&jsBufferAlloc, "alloc", 1));
    engine.setProperty(bufferClass, "allocUnsafe", engine.newFunction(&jsBufferAllocUnsafe, "allocUnsafe", 1));
    engine.setProperty(bufferClass, "isBuffer", engine.newFunction(&jsBufferIsBuffer, "isBuffer", 1));
    engine.setProperty(bufferClass, "concat", engine.newFunction(&jsBufferConcat, "concat", 1));
    engine.setProperty(bufferClass, "byteLength", engine.newFunction(&jsBufferByteLength, "byteLength", 1));
    engine.setProperty(bufferClass, "isEncoding", engine.newFunction(&jsBufferIsEncoding, "isEncoding", 1));
    engine.setProperty(bufferClass, "compare", engine.newFunction(&jsBufferStaticCompare, "compare", 2));
    engine.setProperty(bufferClass, "allocUnsafeSlow", engine.newFunction(&jsBufferAllocUnsafe, "allocUnsafeSlow", 1));
    engine.setProperty(bufferClass, "poolSize", engine.newInt(8192));

    auto global = engine.getGlobal();
    engine.setProperty(global, "Buffer", bufferClass);
    engine.setProperty(global, "__dun_cjs_buffer__", bufferClass);
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
__gshared JSHandle _bufReadUInt16LE, _bufReadUInt16BE;
__gshared JSHandle _bufReadUInt32LE, _bufReadUInt32BE;
__gshared JSHandle _bufReadInt8;
__gshared JSHandle _bufReadInt16LE, _bufReadInt16BE;
__gshared JSHandle _bufReadInt32LE, _bufReadInt32BE;
__gshared JSHandle _bufReadFloatLE, _bufReadFloatBE;
__gshared JSHandle _bufReadDoubleLE, _bufReadDoubleBE;
__gshared JSHandle _bufWriteUInt16LE, _bufWriteUInt16BE;
__gshared JSHandle _bufWriteUInt32LE, _bufWriteUInt32BE;
__gshared JSHandle _bufWriteInt16LE, _bufWriteInt16BE;
__gshared JSHandle _bufWriteInt32LE, _bufWriteInt32BE;
__gshared JSHandle _bufWriteFloatLE, _bufWriteFloatBE;
__gshared JSHandle _bufWriteDoubleLE, _bufWriteDoubleBE;
__gshared JSHandle _bufCompare, _bufIncludes, _bufSubarray, _bufIsEncoding;
__gshared JSHandle _bufProto; // Shared prototype object with all methods
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
    _bufReadUInt16LE = engine.newFunction(&jsBufferReadUInt16LE, "readUInt16LE", 1);
    _bufReadUInt16BE = engine.newFunction(&jsBufferReadUInt16BE, "readUInt16BE", 1);
    _bufReadUInt32LE = engine.newFunction(&jsBufferReadUInt32LE, "readUInt32LE", 1);
    _bufReadUInt32BE = engine.newFunction(&jsBufferReadUInt32BE, "readUInt32BE", 1);
    _bufReadInt8 = engine.newFunction(&jsBufferReadInt8, "readInt8", 1);
    _bufReadInt16LE = engine.newFunction(&jsBufferReadInt16LE, "readInt16LE", 1);
    _bufReadInt16BE = engine.newFunction(&jsBufferReadInt16BE, "readInt16BE", 1);
    _bufReadInt32LE = engine.newFunction(&jsBufferReadInt32LE, "readInt32LE", 1);
    _bufReadInt32BE = engine.newFunction(&jsBufferReadInt32BE, "readInt32BE", 1);
    _bufReadFloatLE = engine.newFunction(&jsBufferReadFloatLE, "readFloatLE", 1);
    _bufReadFloatBE = engine.newFunction(&jsBufferReadFloatBE, "readFloatBE", 1);
    _bufReadDoubleLE = engine.newFunction(&jsBufferReadDoubleLE, "readDoubleLE", 1);
    _bufReadDoubleBE = engine.newFunction(&jsBufferReadDoubleBE, "readDoubleBE", 1);
    _bufWriteUInt16LE = engine.newFunction(&jsBufferWriteUInt16LE, "writeUInt16LE", 2);
    _bufWriteUInt16BE = engine.newFunction(&jsBufferWriteUInt16BE, "writeUInt16BE", 2);
    _bufWriteUInt32LE = engine.newFunction(&jsBufferWriteUInt32LE, "writeUInt32LE", 2);
    _bufWriteUInt32BE = engine.newFunction(&jsBufferWriteUInt32BE, "writeUInt32BE", 2);
    _bufWriteInt16LE = engine.newFunction(&jsBufferWriteInt16LE, "writeInt16LE", 2);
    _bufWriteInt16BE = engine.newFunction(&jsBufferWriteInt16BE, "writeInt16BE", 2);
    _bufWriteInt32LE = engine.newFunction(&jsBufferWriteInt32LE, "writeInt32LE", 2);
    _bufWriteInt32BE = engine.newFunction(&jsBufferWriteInt32BE, "writeInt32BE", 2);
    _bufWriteFloatLE = engine.newFunction(&jsBufferWriteFloatLE, "writeFloatLE", 2);
    _bufWriteFloatBE = engine.newFunction(&jsBufferWriteFloatBE, "writeFloatBE", 2);
    _bufWriteDoubleLE = engine.newFunction(&jsBufferWriteDoubleLE, "writeDoubleLE", 2);
    _bufWriteDoubleBE = engine.newFunction(&jsBufferWriteDoubleBE, "writeDoubleBE", 2);
    _bufCompare = engine.newFunction(&jsBufferCompare, "compare", 1);
    _bufIncludes = engine.newFunction(&jsBufferIncludes, "includes", 1);
    _bufSubarray = engine.newFunction(&jsBufferSubarray, "subarray", 2);
    _bufIsEncoding = engine.newFunction(&jsBufferIsEncoding, "isEncoding", 1);

    // Build shared prototype with all methods (set once, inherited by all buffers)
    _bufProto = engine.newObject();
    engine.setProperty(_bufProto, "toString", engine.dupValue(_bufToString));
    engine.setProperty(_bufProto, "toJSON", engine.dupValue(_bufToJSON));
    engine.setProperty(_bufProto, "slice", engine.dupValue(_bufSlice));
    engine.setProperty(_bufProto, "copy", engine.dupValue(_bufCopy));
    engine.setProperty(_bufProto, "equals", engine.dupValue(_bufEquals));
    engine.setProperty(_bufProto, "indexOf", engine.dupValue(_bufIndexOf));
    engine.setProperty(_bufProto, "fill", engine.dupValue(_bufFill));
    engine.setProperty(_bufProto, "write", engine.dupValue(_bufWrite));
    engine.setProperty(_bufProto, "readUInt8", engine.dupValue(_bufReadUInt8));
    engine.setProperty(_bufProto, "writeUInt8", engine.dupValue(_bufWriteUInt8));
    engine.setProperty(_bufProto, "readUInt16LE", engine.dupValue(_bufReadUInt16LE));
    engine.setProperty(_bufProto, "readUInt16BE", engine.dupValue(_bufReadUInt16BE));
    engine.setProperty(_bufProto, "readUInt32LE", engine.dupValue(_bufReadUInt32LE));
    engine.setProperty(_bufProto, "readUInt32BE", engine.dupValue(_bufReadUInt32BE));
    engine.setProperty(_bufProto, "readInt8", engine.dupValue(_bufReadInt8));
    engine.setProperty(_bufProto, "readInt16LE", engine.dupValue(_bufReadInt16LE));
    engine.setProperty(_bufProto, "readInt16BE", engine.dupValue(_bufReadInt16BE));
    engine.setProperty(_bufProto, "readInt32LE", engine.dupValue(_bufReadInt32LE));
    engine.setProperty(_bufProto, "readInt32BE", engine.dupValue(_bufReadInt32BE));
    engine.setProperty(_bufProto, "readFloatLE", engine.dupValue(_bufReadFloatLE));
    engine.setProperty(_bufProto, "readFloatBE", engine.dupValue(_bufReadFloatBE));
    engine.setProperty(_bufProto, "readDoubleLE", engine.dupValue(_bufReadDoubleLE));
    engine.setProperty(_bufProto, "readDoubleBE", engine.dupValue(_bufReadDoubleBE));
    engine.setProperty(_bufProto, "writeUInt16LE", engine.dupValue(_bufWriteUInt16LE));
    engine.setProperty(_bufProto, "writeUInt16BE", engine.dupValue(_bufWriteUInt16BE));
    engine.setProperty(_bufProto, "writeUInt32LE", engine.dupValue(_bufWriteUInt32LE));
    engine.setProperty(_bufProto, "writeUInt32BE", engine.dupValue(_bufWriteUInt32BE));
    engine.setProperty(_bufProto, "writeInt16LE", engine.dupValue(_bufWriteInt16LE));
    engine.setProperty(_bufProto, "writeInt16BE", engine.dupValue(_bufWriteInt16BE));
    engine.setProperty(_bufProto, "writeInt32LE", engine.dupValue(_bufWriteInt32LE));
    engine.setProperty(_bufProto, "writeInt32BE", engine.dupValue(_bufWriteInt32BE));
    engine.setProperty(_bufProto, "writeFloatLE", engine.dupValue(_bufWriteFloatLE));
    engine.setProperty(_bufProto, "writeFloatBE", engine.dupValue(_bufWriteFloatBE));
    engine.setProperty(_bufProto, "writeDoubleLE", engine.dupValue(_bufWriteDoubleLE));
    engine.setProperty(_bufProto, "writeDoubleBE", engine.dupValue(_bufWriteDoubleBE));
    engine.setProperty(_bufProto, "compare", engine.dupValue(_bufCompare));
    engine.setProperty(_bufProto, "includes", engine.dupValue(_bufIncludes));
    engine.setProperty(_bufProto, "subarray", engine.dupValue(_bufSubarray));

    // Store proto globally and create a fast JS-side factory function
    // that does Object.create + property assignment in a single JS call.
    auto global = engine.getGlobal();
    engine.setProperty(global, "__dunBufProto__", engine.dupValue(_bufProto));
    engine.freeValue(global);

    // Add iterator methods (keys, values, entries, Symbol.iterator) via JS
    // since Symbol.iterator requires JS-level access
    auto iterRes = engine.eval(
        "(function(){" ~
        "var p=__dunBufProto__;" ~
        "p.keys=function(){var b=this,i=0;return{next:function(){" ~
        "return i<b.length?{value:i++,done:false}:{value:undefined,done:true};" ~
        "},__proto__:{[Symbol.iterator]:function(){return this;}}};};" ~
        "p.values=function(){var b=this,i=0;return{next:function(){" ~
        "return i<b.length?{value:b.__u8[i++],done:false}:{value:undefined,done:true};" ~
        "},__proto__:{[Symbol.iterator]:function(){return this;}}};};" ~
        "p.entries=function(){var b=this,i=0;return{next:function(){" ~
        "return i<b.length?{value:[i,b.__u8[i++]],done:false}:{value:undefined,done:true};" ~
        "},__proto__:{[Symbol.iterator]:function(){return this;}}};};" ~
        "p[Symbol.iterator]=p.values;" ~
        "})()",
        "<buffer-iter>");
    if (!iterRes.isError)
        engine.freeValue(iterRes.value);

    auto factoryRes = engine.eval(
        "(function(){" ~
        "var p=__dunBufProto__,c=Object.create;" ~
        "return function __dunMkBuf(u8,len){" ~
        "var o=c(p);o.__isBuffer=true;o.length=len;o.__u8=u8;" ~
        "return new Proxy(o,{" ~
        "get:function(t,k,r){if(typeof k==='string'){var n=+k;if(n===(n|0)&&n>=0&&n<t.length)return t.__u8[n];}return Reflect.get(t,k,r);}," ~
        "set:function(t,k,v,r){if(typeof k==='string'){var n=+k;if(n===(n|0)&&n>=0&&n<t.length){t.__u8[n]=v;return true;}}return Reflect.set(t,k,v,r);}" ~
        "});};})()",
        "<buffer-factory>");
    assert(!factoryRes.isError, "Failed to create buffer factory");
    _bufFactory = factoryRes.value;
    _bufFactoryThis = engine.newUndefined();

    _bufFnsCached = true;
}

__gshared JSHandle _bufFactory;
__gshared JSHandle _bufFactoryThis;

JSHandle makeBufferObj(IJSEngine engine, const(ubyte)[] data) @trusted
{
    ensureBufferFnsCached(engine);
    auto u8 = engine.newUint8Array(data);
    auto lenVal = engine.newInt(cast(int) data.length);
    JSHandle[2] factoryArgs = [u8, lenVal];
    auto result = engine.callFunction(_bufFactory, _bufFactoryThis, factoryArgs[]);
    engine.freeValue(lenVal);
    engine.freeValue(u8);
    return result;
}

JSHandle makeBufferObjZeroed(IJSEngine engine, int size) @trusted
{
    ensureBufferFnsCached(engine);
    auto u8 = engine.newUint8ArrayZeroed(size);
    auto lenVal = engine.newInt(size);
    JSHandle[2] factoryArgs = [u8, lenVal];
    auto result = engine.callFunction(_bufFactory, _bufFactoryThis, factoryArgs[]);
    engine.freeValue(lenVal);
    engine.freeValue(u8);
    return result;
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
        import dun.platform.simd : hexEncodeBuf;
        hexEncodeBuf(data, buf);
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
    auto u8 = engine.getProperty(obj, "__u8");
    auto bytes = engine.getTypedArrayBytes(u8);
    engine.freeValue(u8);
    if (bytes !is null) return bytes;
    return null;
}

// Buffer.from(input, [encoding])
JSHandle jsBufferFrom(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferFrom");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferFrom");
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
        bool isBuffer = engine.isBool(isBuf) && engine.extractBool(isBuf);
        engine.freeValue(isBuf);
        if (isBuffer)
        {
            auto bytes = extractBytes(engine, args[0]);
            return makeBufferObj(engine, bytes);
        }

        // Try as array
        auto lenVal = engine.getProperty(args[0], "length");
        if (engine.isNumber(lenVal))
        {
            int len = engine.extractInt(lenVal);
            engine.freeValue(lenVal);
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
        engine.freeValue(lenVal);
    }

    return engine.throwTypeError("Buffer.from: unsupported argument type");
}

// Buffer.alloc(size, [fill], [encoding])
JSHandle jsBufferAlloc(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferAlloc");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferAlloc");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("Buffer.alloc requires a size");
    int size = engine.extractInt(args[0]);
    if (size < 0 || size > BUFFER_MAX_SIZE)
        return engine.throwRangeError("Invalid buffer size");

    bool hasFill = args.length >= 2 && engine.isNumber(args[1]);
    if (!hasFill)
    {
        return makeBufferObjZeroed(engine, size);
    }
    ubyte fillByte = cast(ubyte) engine.extractInt(args[1]);
    if (fillByte == 0)
        return makeBufferObjZeroed(engine, size);
    auto bytes = new ubyte[size];
    bytes[] = fillByte;
    return makeBufferObj(engine, bytes);
}

// Buffer.allocUnsafe(size)
JSHandle jsBufferAllocUnsafe(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferAllocUnsafe");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferAllocUnsafe");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("Buffer.allocUnsafe requires a size");
    int size = engine.extractInt(args[0]);
    if (size < 0 || size > BUFFER_MAX_SIZE)
        return engine.throwRangeError("Invalid buffer size");

    return makeBufferObjZeroed(engine, size);
}

// Buffer.isBuffer(obj)
JSHandle jsBufferIsBuffer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferIsBuffer");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferIsBuffer");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.newBool(false);
    auto isBuf = engine.getProperty(args[0], "__isBuffer");
    bool result = engine.isBool(isBuf) && engine.extractBool(isBuf);
    engine.freeValue(isBuf);
    return engine.newBool(result);
}

// Buffer.concat(list, [totalLength])
JSHandle jsBufferConcat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import core.stdc.string : memcpy;

    assert(ctx !is null, "Null ctx in jsBufferConcat");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferConcat");
    auto engine = state.engine;
    if (args.length < 1) return makeBufferObj(engine, cast(ubyte[]) []);

    auto lenVal = engine.getProperty(args[0], "length");
    if (!engine.isNumber(lenVal))
    {
        engine.freeValue(lenVal);
        return makeBufferObj(engine, cast(ubyte[]) []);
    }
    int count = engine.extractInt(lenVal);
    engine.freeValue(lenVal);
    if (count == 0) return makeBufferObj(engine, cast(ubyte[]) []);

    // Stack-allocate handles for small arrays, heap for large
    enum STACK_MAX = 16;
    JSHandle[STACK_MAX] stackHandles = void;
    ubyte[][STACK_MAX] stackSlices = void;
    JSHandle[] elemHandles;
    ubyte[][] slices;
    if (count <= STACK_MAX)
    {
        elemHandles = stackHandles[0 .. count];
        slices = stackSlices[0 .. count];
    }
    else
    {
        elemHandles = new JSHandle[count];
        slices = new ubyte[][count];
    }

    // First pass: extract all byte slices and compute total length
    size_t totalLen = 0;
    for (int i = 0; i < count; i++)
    {
        elemHandles[i] = engine.getPropertyIndex(args[0], cast(uint) i);
        slices[i] = null;
        if (engine.isObject(elemHandles[i]))
        {
            slices[i] = extractBytes(engine, elemHandles[i]);
            if (slices[i] !is null)
                totalLen += slices[i].length;
        }
    }

    // Create result typed array directly and memcpy segments into it
    ensureBufferFnsCached(engine);
    auto u8 = engine.newUint8ArrayZeroed(totalLen);
    auto destBytes = engine.getTypedArrayBytes(u8);
    size_t pos = 0;
    for (int i = 0; i < count; i++)
    {
        if (slices[i] !is null && slices[i].length > 0 && destBytes !is null)
        {
            memcpy(destBytes.ptr + pos, slices[i].ptr, slices[i].length);
            pos += slices[i].length;
        }
        engine.freeValue(elemHandles[i]);
    }

    auto totalLenVal = engine.newInt(cast(int) totalLen);
    JSHandle[2] factoryArgs = [u8, totalLenVal];
    return engine.callFunction(_bufFactory, _bufFactoryThis, factoryArgs[]);
}

// Buffer.byteLength(string, [encoding])
JSHandle jsBufferByteLength(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferByteLength");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferByteLength");
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
        engine.freeValue(lenProp);
    }
    return engine.newInt(0);
}

// buf.toString([encoding], [start], [end])
JSHandle jsBufferToString(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferToString");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferToString");
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
JSHandle jsBufferToJSON(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferToJSON");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferToJSON");
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
JSHandle jsBufferSlice(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferSlice");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferSlice");
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
JSHandle jsBufferCopy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferCopy");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferCopy");
    auto engine = state.engine;
    auto srcBytes = extractBytes(engine, thisVal);
    return engine.newInt(cast(int) srcBytes.length);
}

// buf.equals(other)
JSHandle jsBufferEquals(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferEquals");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferEquals");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.newBool(false);
    auto a = extractBytes(engine, thisVal);
    auto b = extractBytes(engine, args[0]);
    return engine.newBool(a == b);
}

// buf.indexOf(value)
JSHandle jsBufferIndexOf(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferIndexOf");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferIndexOf");
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
JSHandle jsBufferFill(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferFill");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferFill");
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
    return thisVal;
}

// buf.write(string, [offset])
JSHandle jsBufferWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWrite");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWrite");
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

    return engine.newInt(written);
}

// buf.readUInt8([offset])
JSHandle jsBufferReadUInt8(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadUInt8");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadUInt8");
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
JSHandle jsBufferWriteUInt8(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteUInt8");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteUInt8");
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
    return engine.newInt(offset + 1);
}

// Buffer.isEncoding(encoding)
JSHandle jsBufferIsEncoding(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferIsEncoding");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferIsEncoding");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isString(args[0])) return engine.newBool(false);
    auto enc = engine.extractString(args[0]);
    if (enc == "utf8" || enc == "utf-8" || enc == "ascii" || enc == "latin1" ||
        enc == "binary" || enc == "hex" || enc == "base64" || enc == "ucs2" ||
        enc == "ucs-2" || enc == "utf16le" || enc == "utf-16le")
        return engine.newBool(true);
    return engine.newBool(false);
}

// Buffer.compare(a, b)
JSHandle jsBufferStaticCompare(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferStaticCompare");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferStaticCompare");
    auto engine = state.engine;
    if (args.length < 2) return engine.throwTypeError("Buffer.compare requires two arguments");
    auto a = extractBytes(engine, args[0]);
    auto b = extractBytes(engine, args[1]);
    auto minLen = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. minLen)
    {
        if (a[i] < b[i]) return engine.newInt(-1);
        if (a[i] > b[i]) return engine.newInt(1);
    }
    if (a.length < b.length) return engine.newInt(-1);
    if (a.length > b.length) return engine.newInt(1);
    return engine.newInt(0);
}

// buf.readUInt16LE([offset])
JSHandle jsBufferReadUInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadUInt16LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadUInt16LE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    int val = cast(int) bytes[offset] | (cast(int) bytes[offset + 1] << 8);
    return engine.newInt(val);
}

JSHandle jsBufferReadUInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap16;
    assert(ctx !is null, "Null ctx in jsBufferReadUInt16BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadUInt16BE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ushort le = *cast(ushort*)(bytes.ptr + offset);
    return engine.newInt(cast(int) bswap16(le));
}

JSHandle jsBufferReadUInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadUInt32LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadUInt32LE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    uint val = cast(uint) bytes[offset] | (cast(uint) bytes[offset+1] << 8) | (cast(uint) bytes[offset+2] << 16) | (cast(uint) bytes[offset+3] << 24);
    return engine.newFloat(cast(double) val);
}

JSHandle jsBufferReadUInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferReadUInt32BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadUInt32BE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    uint le = *cast(uint*)(bytes.ptr + offset);
    return engine.newFloat(cast(double) bswap32(le));
}

JSHandle jsBufferReadInt8(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadInt8");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadInt8");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    return engine.newInt(cast(int) cast(byte) bytes[offset]);
}

JSHandle jsBufferReadInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadInt16LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadInt16LE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    short val = cast(short)(cast(ushort) bytes[offset] | (cast(ushort) bytes[offset + 1] << 8));
    return engine.newInt(cast(int) val);
}

JSHandle jsBufferReadInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap16;
    assert(ctx !is null, "Null ctx in jsBufferReadInt16BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadInt16BE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ushort le = *cast(ushort*)(bytes.ptr + offset);
    return engine.newInt(cast(int) cast(short) bswap16(le));
}

JSHandle jsBufferReadInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadInt32LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadInt32LE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    int val = cast(int)(cast(uint) bytes[offset] | (cast(uint) bytes[offset+1] << 8) | (cast(uint) bytes[offset+2] << 16) | (cast(uint) bytes[offset+3] << 24));
    return engine.newInt(val);
}

JSHandle jsBufferReadInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferReadInt32BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadInt32BE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    uint le = *cast(uint*)(bytes.ptr + offset);
    return engine.newInt(cast(int) bswap32(le));
}

JSHandle jsBufferReadFloatLE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadFloatLE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadFloatLE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ubyte[4] buf = [bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]];
    float val = *(cast(float*) buf.ptr);
    return engine.newFloat(cast(double) val);
}

JSHandle jsBufferReadFloatBE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferReadFloatBE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadFloatBE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    uint le = *cast(uint*)(bytes.ptr + offset);
    uint swapped = bswap32(le);
    float val = *cast(float*)&swapped;
    return engine.newFloat(cast(double) val);
}

JSHandle jsBufferReadDoubleLE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferReadDoubleLE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadDoubleLE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 7 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ubyte[8] buf;
    foreach (i; 0 .. 8) buf[i] = bytes[offset + i];
    double val = *(cast(double*) buf.ptr);
    return engine.newFloat(val);
}

JSHandle jsBufferReadDoubleBE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap64;
    assert(ctx !is null, "Null ctx in jsBufferReadDoubleBE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferReadDoubleBE");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int offset = 0;
    if (args.length >= 1 && engine.isNumber(args[0])) offset = engine.extractInt(args[0]);
    if (offset < 0 || offset + 7 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ulong le = *cast(ulong*)(bytes.ptr + offset);
    ulong swapped = bswap64(le);
    double val = *cast(double*)&swapped;
    return engine.newFloat(val);
}

JSHandle jsBufferWriteUInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteUInt16LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteUInt16LE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeUInt16LE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    int value = engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    bytes[offset] = cast(ubyte)(value & 0xFF);
    bytes[offset + 1] = cast(ubyte)((value >> 8) & 0xFF);
    return engine.newInt(offset + 2);
}

JSHandle jsBufferWriteUInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap16;
    assert(ctx !is null, "Null ctx in jsBufferWriteUInt16BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteUInt16BE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeUInt16BE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    int value = engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    *cast(ushort*)(bytes.ptr + offset) = bswap16(cast(ushort) value);
    return engine.newInt(offset + 2);
}

JSHandle jsBufferWriteUInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteUInt32LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteUInt32LE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeUInt32LE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    uint value = cast(uint) engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    bytes[offset] = cast(ubyte)(value & 0xFF);
    bytes[offset+1] = cast(ubyte)((value >> 8) & 0xFF);
    bytes[offset+2] = cast(ubyte)((value >> 16) & 0xFF);
    bytes[offset+3] = cast(ubyte)((value >> 24) & 0xFF);
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteUInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferWriteUInt32BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteUInt32BE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeUInt32BE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    uint value = cast(uint) engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    *cast(uint*)(bytes.ptr + offset) = bswap32(value);
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteInt16LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteInt16LE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeInt16LE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    ushort uval = cast(ushort) cast(short) engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    bytes[offset] = cast(ubyte)(uval & 0xFF);
    bytes[offset + 1] = cast(ubyte)((uval >> 8) & 0xFF);
    return engine.newInt(offset + 2);
}

JSHandle jsBufferWriteInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap16;
    assert(ctx !is null, "Null ctx in jsBufferWriteInt16BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteInt16BE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeInt16BE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    ushort uval = cast(ushort) cast(short) engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 1 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    *cast(ushort*)(bytes.ptr + offset) = bswap16(uval);
    return engine.newInt(offset + 2);
}

JSHandle jsBufferWriteInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteInt32LE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteInt32LE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeInt32LE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    uint uval = cast(uint) engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    bytes[offset] = cast(ubyte)(uval & 0xFF);
    bytes[offset+1] = cast(ubyte)((uval >> 8) & 0xFF);
    bytes[offset+2] = cast(ubyte)((uval >> 16) & 0xFF);
    bytes[offset+3] = cast(ubyte)((uval >> 24) & 0xFF);
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferWriteInt32BE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteInt32BE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeInt32BE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    uint uval = cast(uint) engine.extractInt(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    *cast(uint*)(bytes.ptr + offset) = bswap32(uval);
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteFloatLE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteFloatLE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteFloatLE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeFloatLE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    float value = cast(float) engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ubyte* fp = cast(ubyte*)&value;
    foreach (i; 0 .. 4) bytes[offset + i] = fp[i];
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteFloatBE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap32;
    assert(ctx !is null, "Null ctx in jsBufferWriteFloatBE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteFloatBE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeFloatBE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    float value = cast(float) engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 3 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    uint le = *cast(uint*)&value;
    *cast(uint*)(bytes.ptr + offset) = bswap32(le);
    return engine.newInt(offset + 4);
}

JSHandle jsBufferWriteDoubleLE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferWriteDoubleLE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteDoubleLE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeDoubleLE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    double value = engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 7 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ubyte* dp = cast(ubyte*)&value;
    foreach (i; 0 .. 8) bytes[offset + i] = dp[i];
    return engine.newInt(offset + 8);
}

JSHandle jsBufferWriteDoubleBE(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.simd : bswap64;
    assert(ctx !is null, "Null ctx in jsBufferWriteDoubleBE");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferWriteDoubleBE");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isNumber(args[0])) return engine.throwTypeError("writeDoubleBE requires a value");
    auto bytes = extractBytes(engine, thisVal);
    double value = engine.extractFloat(args[0]);
    int offset = 0;
    if (args.length >= 2 && engine.isNumber(args[1])) offset = engine.extractInt(args[1]);
    if (offset < 0 || offset + 7 >= cast(int) bytes.length) return engine.throwRangeError("Offset out of range");
    ulong le = *cast(ulong*)&value;
    *cast(ulong*)(bytes.ptr + offset) = bswap64(le);
    return engine.newInt(offset + 8);
}

JSHandle jsBufferCompare(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferCompare");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferCompare");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("compare requires a Buffer argument");
    auto a = extractBytes(engine, thisVal);
    auto b = extractBytes(engine, args[0]);
    auto minLen = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. minLen)
    {
        if (a[i] < b[i]) return engine.newInt(-1);
        if (a[i] > b[i]) return engine.newInt(1);
    }
    if (a.length < b.length) return engine.newInt(-1);
    if (a.length > b.length) return engine.newInt(1);
    return engine.newInt(0);
}

JSHandle jsBufferIncludes(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferIncludes");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferIncludes");
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    auto bytes = extractBytes(engine, thisVal);
    if (engine.isNumber(args[0]))
    {
        int val = engine.extractInt(args[0]);
        foreach (b; bytes) if (b == cast(ubyte) val) return engine.newBool(true);
        return engine.newBool(false);
    }
    if (engine.isString(args[0]))
    {
        auto needle = cast(const(ubyte)[]) engine.extractString(args[0]);
        if (needle.length == 0) return engine.newBool(true);
        if (needle.length > bytes.length) return engine.newBool(false);
        foreach (i; 0 .. bytes.length - needle.length + 1)
            if (bytes[i .. i + needle.length] == needle) return engine.newBool(true);
        return engine.newBool(false);
    }
    return engine.newBool(false);
}

JSHandle jsBufferSubarray(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferSubarray");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferSubarray");
    auto engine = state.engine;
    auto bytes = extractBytes(engine, thisVal);
    int start = 0;
    int end = cast(int) bytes.length;
    if (args.length >= 1 && engine.isNumber(args[0])) start = engine.extractInt(args[0]);
    if (args.length >= 2 && engine.isNumber(args[1])) end = engine.extractInt(args[1]);
    if (start < 0) start = cast(int) bytes.length + start;
    if (end < 0) end = cast(int) bytes.length + end;
    if (start < 0) start = 0;
    if (end > cast(int) bytes.length) end = cast(int) bytes.length;
    if (start >= end) return makeBufferObj(engine, []);
    return makeBufferObj(engine, bytes[start .. end]);
}
