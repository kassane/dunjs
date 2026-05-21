module dun.builtins.buffer;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum BUFFER_MAX_SIZE = 1024 * 1024 * 1024;

void registerBufferModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerBufferModule");

    // Buffer must be a function (not object) for npm compat: typeof Buffer === 'function'
    auto bufCtorRes = engine.eval(
        "(function Buffer(arg, enc, len) { return Buffer.from(arg, enc); })",
        "<buffer-ctor>");
    assert(!bufCtorRes.isError, "Failed to create Buffer constructor");
    auto bufferClass = bufCtorRes.value;

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

    // require('buffer') returns { Buffer: <constructor>, ... } (Node.js compat)
    auto bufModule = engine.newObject();
    engine.bindMethod(bufModule, "Buffer", bufferClass);
    engine.bindMethod(bufModule, "SlowBuffer", bufferClass);
    engine.setProperty(bufModule, "INSPECT_MAX_BYTES", engine.newInt(50));
    engine.setProperty(bufModule, "kMaxLength", engine.newInt(0x7FFFFFFF));
    engine.setProperty(global, "__dun_cjs_buffer__", bufModule);
    engine.freeValue(global);

    ensureBufferFnsCached(engine);

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
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int bufferModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in bufferModuleInit");
        assert(m !is null, "Null module def in bufferModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto bufObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_buffer__");
        JS_SetModuleExport(ctx, m, "Buffer", JS_DupValue(ctx, bufObj));
        JS_SetModuleExport(ctx, m, "default", bufObj);
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
    engine.bindMethod(_bufProto, "toString", _bufToString);
    engine.bindMethod(_bufProto, "toJSON", _bufToJSON);
    engine.bindMethod(_bufProto, "slice", _bufSlice);
    engine.bindMethod(_bufProto, "copy", _bufCopy);
    engine.bindMethod(_bufProto, "equals", _bufEquals);
    engine.bindMethod(_bufProto, "indexOf", _bufIndexOf);
    engine.bindMethod(_bufProto, "fill", _bufFill);
    engine.bindMethod(_bufProto, "write", _bufWrite);
    engine.bindMethod(_bufProto, "readUInt8", _bufReadUInt8);
    engine.bindMethod(_bufProto, "writeUInt8", _bufWriteUInt8);
    engine.bindMethod(_bufProto, "readUInt16LE", _bufReadUInt16LE);
    engine.bindMethod(_bufProto, "readUInt16BE", _bufReadUInt16BE);
    engine.bindMethod(_bufProto, "readUInt32LE", _bufReadUInt32LE);
    engine.bindMethod(_bufProto, "readUInt32BE", _bufReadUInt32BE);
    engine.bindMethod(_bufProto, "readInt8", _bufReadInt8);
    engine.bindMethod(_bufProto, "readInt16LE", _bufReadInt16LE);
    engine.bindMethod(_bufProto, "readInt16BE", _bufReadInt16BE);
    engine.bindMethod(_bufProto, "readInt32LE", _bufReadInt32LE);
    engine.bindMethod(_bufProto, "readInt32BE", _bufReadInt32BE);
    engine.bindMethod(_bufProto, "readFloatLE", _bufReadFloatLE);
    engine.bindMethod(_bufProto, "readFloatBE", _bufReadFloatBE);
    engine.bindMethod(_bufProto, "readDoubleLE", _bufReadDoubleLE);
    engine.bindMethod(_bufProto, "readDoubleBE", _bufReadDoubleBE);
    engine.bindMethod(_bufProto, "writeUInt16LE", _bufWriteUInt16LE);
    engine.bindMethod(_bufProto, "writeUInt16BE", _bufWriteUInt16BE);
    engine.bindMethod(_bufProto, "writeUInt32LE", _bufWriteUInt32LE);
    engine.bindMethod(_bufProto, "writeUInt32BE", _bufWriteUInt32BE);
    engine.bindMethod(_bufProto, "writeInt16LE", _bufWriteInt16LE);
    engine.bindMethod(_bufProto, "writeInt16BE", _bufWriteInt16BE);
    engine.bindMethod(_bufProto, "writeInt32LE", _bufWriteInt32LE);
    engine.bindMethod(_bufProto, "writeInt32BE", _bufWriteInt32BE);
    engine.bindMethod(_bufProto, "writeFloatLE", _bufWriteFloatLE);
    engine.bindMethod(_bufProto, "writeFloatBE", _bufWriteFloatBE);
    engine.bindMethod(_bufProto, "writeDoubleLE", _bufWriteDoubleLE);
    engine.bindMethod(_bufProto, "writeDoubleBE", _bufWriteDoubleBE);
    engine.bindMethod(_bufProto, "compare", _bufCompare);
    engine.bindMethod(_bufProto, "includes", _bufIncludes);
    engine.bindMethod(_bufProto, "subarray", _bufSubarray);

    // Store proto globally and create a fast JS-side factory function
    // that does Object.create + property assignment in a single JS call.
    auto global = engine.getGlobal();
    engine.bindMethod(global, "__dunBufProto__", _bufProto);
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
        "return i<b.length?{value:b[i++],done:false}:{value:undefined,done:true};" ~
        "},__proto__:{[Symbol.iterator]:function(){return this;}}};};" ~
        "p.entries=function(){var b=this,i=0;return{next:function(){" ~
        "return i<b.length?{value:[i,b[i++]],done:false}:{value:undefined,done:true};" ~
        "},__proto__:{[Symbol.iterator]:function(){return this;}}};};" ~
        "p[Symbol.iterator]=p.values;" ~

        // swap16/swap32/swap64 — byte swap in-place
        "p.swap16=function(){var u=this,l=u.length;" ~
        "if(l%2!==0)throw new RangeError('Buffer size must be a multiple of 16-bits');" ~
        "for(var i=0;i<l;i+=2){var t=u[i];u[i]=u[i+1];u[i+1]=t;}return this;};" ~
        "p.swap32=function(){var u=this,l=u.length;" ~
        "if(l%4!==0)throw new RangeError('Buffer size must be a multiple of 32-bits');" ~
        "for(var i=0;i<l;i+=4){var t=u[i];u[i]=u[i+3];u[i+3]=t;t=u[i+1];u[i+1]=u[i+2];u[i+2]=t;}return this;};" ~
        "p.swap64=function(){var u=this,l=u.length;" ~
        "if(l%8!==0)throw new RangeError('Buffer size must be a multiple of 64-bits');" ~
        "for(var i=0;i<l;i+=8){for(var j=0;j<4;j++){var t=u[i+j];u[i+j]=u[i+7-j];u[i+7-j]=t;}}return this;};" ~

        // lastIndexOf
        "p.lastIndexOf=function(v,o){var u=this,s=typeof v==='string'?new TextEncoder().encode(v):v instanceof Uint8Array?v:[v];" ~
        "var start=o!==undefined?Math.min(o,u.length-s.length):u.length-s.length;" ~
        "for(var i=start;i>=0;i--){var m=true;for(var j=0;j<s.length;j++){if(u[i+j]!==s[j]){m=false;break;}}if(m)return i;}return -1;};" ~

        // readIntBE/LE, readUIntBE/LE (1-6 byte variable-width)
        "p.readUIntBE=function(o,bl){var u=this,v=0;for(var i=0;i<bl;i++)v=v*256+u[o+i];return v;};" ~
        "p.readUIntLE=function(o,bl){var u=this,v=0;for(var i=bl-1;i>=0;i--)v=v*256+u[o+i];return v;};" ~
        "p.readIntBE=function(o,bl){var v=this.readUIntBE(o,bl);if(v>=(1<<(bl*8-1)))v-=(1<<(bl*8));return v;};" ~
        "p.readIntLE=function(o,bl){var v=this.readUIntLE(o,bl);if(v>=(1<<(bl*8-1)))v-=(1<<(bl*8));return v;};" ~
        "p.writeUIntBE=function(v,o,bl){var u=this;for(var i=bl-1;i>=0;i--){u[o+i]=v&0xFF;v=Math.floor(v/256);}return o+bl;};" ~
        "p.writeUIntLE=function(v,o,bl){var u=this;for(var i=0;i<bl;i++){u[o+i]=v&0xFF;v=Math.floor(v/256);}return o+bl;};" ~
        "p.writeIntBE=function(v,o,bl){if(v<0)v+=(1<<(bl*8));return this.writeUIntBE(v,o,bl);};" ~
        "p.writeIntLE=function(v,o,bl){if(v<0)v+=(1<<(bl*8));return this.writeUIntLE(v,o,bl);};" ~

        // BigInt read/write methods
        "p.readBigInt64BE=function(o){if(typeof BigInt==='undefined')throw new Error('BigInt not available');var u=this;o=o||0;var hi=((u[o]<<24)|(u[o+1]<<16)|(u[o+2]<<8)|u[o+3]);var lo=((u[o+4]<<24)|(u[o+5]<<16)|(u[o+6]<<8)|u[o+7])>>>0;return(BigInt(hi)<<BigInt(32))|BigInt(lo);};" ~
        "p.readBigUInt64BE=function(o){if(typeof BigInt==='undefined')throw new Error('BigInt not available');var u=this;o=o||0;var hi=((u[o]<<24)|(u[o+1]<<16)|(u[o+2]<<8)|u[o+3])>>>0;var lo=((u[o+4]<<24)|(u[o+5]<<16)|(u[o+6]<<8)|u[o+7])>>>0;return(BigInt(hi)<<BigInt(32))|BigInt(lo);};" ~
        "p.readBigInt64LE=function(o){if(typeof BigInt==='undefined')throw new Error('BigInt not available');var u=this;o=o||0;var lo=((u[o+3]<<24)|(u[o+2]<<16)|(u[o+1]<<8)|u[o])>>>0;var hi=((u[o+7]<<24)|(u[o+6]<<16)|(u[o+5]<<8)|u[o+4]);return(BigInt(hi)<<BigInt(32))|BigInt(lo);};" ~
        "p.readBigUInt64LE=function(o){if(typeof BigInt==='undefined')throw new Error('BigInt not available');var u=this;o=o||0;var lo=((u[o+3]<<24)|(u[o+2]<<16)|(u[o+1]<<8)|u[o])>>>0;var hi=((u[o+7]<<24)|(u[o+6]<<16)|(u[o+5]<<8)|u[o+4])>>>0;return(BigInt(hi)<<BigInt(32))|BigInt(lo);};" ~
        "p.writeBigInt64BE=function(v,o){var u=this;o=o||0;v=BigInt(v);for(var i=7;i>=0;i--){u[o+i]=Number(v&BigInt(0xFF));v>>=BigInt(8);}return o+8;};" ~
        "p.writeBigInt64LE=function(v,o){var u=this;o=o||0;v=BigInt(v);for(var i=0;i<8;i++){u[o+i]=Number(v&BigInt(0xFF));v>>=BigInt(8);}return o+8;};" ~
        "p.writeBigUInt64BE=p.writeBigInt64BE;" ~
        "p.writeBigUInt64LE=p.writeBigInt64LE;" ~

        // Sync Buffer.prototype with __dunBufProto__ for npm compat (safe-buffer, etc.)
        "if(typeof Buffer!=='undefined')Buffer.prototype=p;" ~
        // Make Buffer instances pass `instanceof Uint8Array` check (npm compat)
        "var origU8HasInstance=Uint8Array[Symbol.hasInstance];" ~
        "Object.defineProperty(Uint8Array,Symbol.hasInstance,{value:function(inst){" ~
        "return (inst&&inst.__isBuffer===true)||origU8HasInstance.call(this,inst);" ~
        "}});" ~

        "})()",
        "<buffer-iter>");
    if (!iterRes.isError)
        engine.freeValue(iterRes.value);

    // Re-parent __dunBufProto__ onto Uint8Array.prototype so Buffer
    // instances (which are now real Uint8Array subclass instances)
    // inherit the standard TypedArray methods (.set, .subarray, etc.)
    // alongside the Buffer extras. `__isBuffer = true` also lives on the
    // prototype so every instance reports it via inheritance.
    auto reparentRes = engine.eval(
        "(function(){"
        ~ "Object.setPrototypeOf(__dunBufProto__, Uint8Array.prototype);"
        ~ "__dunBufProto__.__isBuffer = true;"
        ~ "if (typeof Buffer !== 'undefined') Buffer.prototype = __dunBufProto__;"
        ~ "})()",
        "<buffer-reparent>");
    if (!reparentRes.isError)
        engine.freeValue(reparentRes.value);

    _bufFactory = engine.newUndefined();           // unused — kept for back-compat
    _bufFactoryThis = engine.newUndefined();

    _bufFnsCached = true;
}

__gshared JSHandle _bufFactory;
__gshared JSHandle _bufFactoryThis;

public JSHandle makeBufferObj(IJSEngine engine, const(ubyte)[] data) @trusted
{
    ensureBufferFnsCached(engine);
    // Single backend call: alloc + memcpy + setPrototype. On V8 this
    // collapses 3 withContext entries into 1 — meaningful win on the
    // Buffer.from hot path. On QuickJS / JSC the impl falls back to the
    // two-step path internally.
    return engine.newBufferWithProto(data, _bufProto, false);
}

public JSHandle makeBufferObjZeroed(IJSEngine engine, int size) @trusted
{
    ensureBufferFnsCached(engine);
    // 1 FFI call on V8 (fused ArrayBuffer + Uint8Array + SetPrototype);
    // QuickJS/JSC fall back internally to the 2-step path.
    return engine.newUint8ArrayZeroedWithProto(size, _bufProto);
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

/// Returned slice inherits `obj`'s scope (DIP1000 `return scope`):
/// callers must consume it inline or `.dup` to keep past `obj`'s
/// lifetime. Matches `IJSEngine.getTypedArrayBytes` which it wraps.
package ubyte[] extractBytes(IJSEngine engine, return scope JSHandle obj) @trusted
{
    // Buffer is now a Uint8Array subclass — no `.__u8` indirection needed.
    // Falls back to the legacy `.__u8` property in case some non-Buffer
    // object still uses the wrapper shape (e.g. user-constructed pseudo
    // buffers via `{ __isBuffer: true, __u8: ... }`). JSC's
    // JSObjectGetTypedArrayByteLength is unsafe on non-objects, so gate
    // on isObject before calling it.
    if (!engine.isObject(obj)) return null;
    auto bytes = engine.getTypedArrayBytes(obj);
    if (bytes !is null) return bytes;
    auto u8 = engine.getProperty(obj, "__u8");
    ubyte[] fallback = null;
    if (engine.isObject(u8))
        fallback = engine.getTypedArrayBytes(u8);
    engine.freeValue(u8);
    return fallback;
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
        // Common path: Buffer.from(str) with no encoding → fused
        // utf8-direct shim on V8, two-step fallback elsewhere.
        if (args.length < 2 || engine.isUndefined(args[1]))
        {
            ensureBufferFnsCached(engine);
            return engine.newBufferFromUtf8String(args[0], _bufProto);
        }

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
                // Node.js accepts both base64 and base64url in 'base64' mode
                auto normalized = base64urlToBase64(str);
                import std.base64 : Base64;
                auto bytes = Base64.decode(normalized);
                return makeBufferObj(engine, bytes);
            }
            catch (Exception)
            {
                return makeBufferObj(engine, cast(ubyte[]) []);
            }
        }
        else if (encoding == "base64url")
        {
            try
            {
                auto padded = base64urlToBase64(str);
                import std.base64 : Base64;
                auto bytes = Base64.decode(padded);
                return makeBufferObj(engine, bytes);
            }
            catch (Exception)
            {
                return makeBufferObj(engine, cast(ubyte[]) []);
            }
        }
        else if (encoding == "latin1" || encoding == "binary")
        {
            /* Latin1: each JS char's charCode (0-255) maps to one byte.
               extractString gives UTF-8, so decode codepoints and take
               low byte. Centralized helper (`utf8ToLatin1Buf`) shares
               UTF-8 constants with the encoder and the JSC backend
               decoder, so the surrogate / astral handling is identical
               across all three paths. */
            import dun.platform.simd : utf8ToLatin1Buf;
            auto bytes = new ubyte[str.length];  // output ≤ input bytes
            auto produced = utf8ToLatin1Buf(str, bytes);
            return makeBufferObj(engine, bytes[0 .. produced]);
        }
        else
        {
            return makeBufferObj(engine, cast(const(ubyte)[]) str);
        }
    }

    // Typed array (Uint8Array, Int8Array, etc.) or ArrayBuffer
    {
        auto bytes = engine.getTypedArrayBytes(args[0]);
        if (bytes !is null)
            return makeBufferObj(engine, bytes);
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

        // Check for ArrayBuffer via byteLength property and no length
        auto byteLenVal = engine.getProperty(args[0], "byteLength");
        auto lenCheck = engine.getProperty(args[0], "length");
        bool hasOnlyByteLength = engine.isNumber(byteLenVal) && !engine.isNumber(lenCheck);
        engine.freeValue(lenCheck);
        if (hasOnlyByteLength)
        {
            int byteLen = engine.extractInt(byteLenVal);
            engine.freeValue(byteLenVal);

            // Support Buffer.from(ArrayBuffer, byteOffset, length)
            bool hasOffset = args.length >= 2 && engine.isNumber(args[1]);
            if (hasOffset)
            {
                int offset = engine.extractInt(args[1]);
                int len = (args.length >= 3 && engine.isNumber(args[2]))
                    ? engine.extractInt(args[2])
                    : byteLen - offset;
                import std.conv : to;
                auto u8Result = engine.eval(
                    "(function(ab,off,len){return new Uint8Array(ab,off,len)})", "<buf-ab-off>");
                if (!u8Result.isError)
                {
                    auto u8arr = engine.callFunction(u8Result.value, engine.newUndefined(),
                        [args[0], engine.newInt(offset), engine.newInt(len)]);
                    engine.freeValue(u8Result.value);
                    auto bytes = engine.getTypedArrayBytes(u8arr);
                    engine.freeValue(u8arr);
                    if (bytes !is null)
                        return makeBufferObj(engine, bytes);
                }
                else
                    engine.freeValue(u8Result.value);
            }

            auto u8Result = engine.eval(
                "(function(ab){return new Uint8Array(ab)})", "<buf-ab>");
            if (!u8Result.isError)
            {
                auto u8arr = engine.callFunction(u8Result.value, engine.newUndefined(), [args[0]]);
                engine.freeValue(u8Result.value);
                auto bytes = engine.getTypedArrayBytes(u8arr);
                engine.freeValue(u8arr);
                if (bytes !is null)
                    return makeBufferObj(engine, bytes);
            }
            else
                engine.freeValue(u8Result.value);
            auto fallbackBytes = new ubyte[byteLen];
            return makeBufferObj(engine, fallbackBytes);
        }
        engine.freeValue(byteLenVal);

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

    if (args.length < 2 || engine.isUndefined(args[1]))
        return makeBufferObjZeroed(engine, size);

    if (engine.isNumber(args[1]))
    {
        ubyte fillByte = cast(ubyte) engine.extractInt(args[1]);
        if (fillByte == 0)
            return makeBufferObjZeroed(engine, size);
        auto bytes = new ubyte[size];
        bytes[] = fillByte;
        return makeBufferObj(engine, bytes);
    }

    if (engine.isString(args[1]))
    {
        string fillStr = engine.extractString(args[1]);
        if (fillStr.length == 0)
            return makeBufferObjZeroed(engine, size);

        string encoding = "utf8";
        if (args.length >= 3 && engine.isString(args[2]))
            encoding = engine.extractString(args[2]);

        const(ubyte)[] fillBytes;
        if (encoding == "hex")
            fillBytes = hexToBytes(fillStr);
        else
            fillBytes = cast(const(ubyte)[]) fillStr;

        if (fillBytes.length == 0)
            return makeBufferObjZeroed(engine, size);
        auto bytes = new ubyte[size];
        foreach (i; 0 .. size)
            bytes[i] = fillBytes[i % fillBytes.length];
        return makeBufferObj(engine, bytes);
    }

    // Fill with Buffer or typed array
    if (engine.isObject(args[1]))
    {
        auto fillBytes = engine.getTypedArrayBytes(args[1]);
        if (fillBytes is null)
            fillBytes = extractBytes(engine, args[1]);
        if (fillBytes.length > 0)
        {
            auto bytes = new ubyte[size];
            foreach (i; 0 .. size)
                bytes[i] = fillBytes[i % fillBytes.length];
            return makeBufferObj(engine, bytes);
        }
    }

    return makeBufferObjZeroed(engine, size);
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

    // V8 fused fast-path: one withContext scope replaces the
    // per-element getPropertyIndex + getTypedArrayBytes + freeValue
    // calls. We pass count + optional totalLen override (SIZE_MAX
    // sentinel = compute from elements). C++ does Get/As<TypedArray>/
    // ByteLength sum + memcpy + setPrototype against v8::Local<>
    // directly — zero FFI inside the loop. QuickJS/JSC return empty
    // (per-call FFI overhead asymmetry doesn't reward fusing on
    // those) and fall through to the generic path below.
    ensureBufferFnsCached(engine);
    size_t totalLenOverride = size_t.max; // sentinel: "compute it"
    if (args.length >= 2 && engine.isNumber(args[1]))
    {
        int requestedLen = engine.extractInt(args[1]);
        if (requestedLen >= 0)
            totalLenOverride = cast(size_t) requestedLen;
    }
    auto fused = engine.bufferConcatFused(args[0], count, totalLenOverride, _bufProto);
    if (fused != JSHandle.init)
        return fused;

    // --- Generic fallback (QuickJS / JSC) ---

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

    if (totalLenOverride != size_t.max)
        totalLen = totalLenOverride;

    // Create result typed array directly and memcpy segments into it.
    // Allocate AFTER the size pass so we know the total length, then keep
    // u8 protected (via dupValue) across the memcpy loop because freeValue
    // on the element handles can trigger GC and we hold a raw u8 ref.
    //
    // Note: we deliberately do NOT use the fused `newUint8ArrayZeroedWithProto`
    // here — setting the Buffer prototype BEFORE the typed-array writes
    // takes V8 off the fast inline-cache path for raw backing-store access
    // (regression measured at +35% on Buffer.concat in v1.1.16 trial).
    // Keep the post-memcpy SetPrototype so V8 sees the writes against
    // a plain Uint8Array shape.
    ensureBufferFnsCached(engine);
    auto u8 = engine.newUint8ArrayZeroed(totalLen);
    auto u8Pinned = engine.dupValue(u8);
    auto destBytes = engine.getTypedArrayBytes(u8);
    size_t pos = 0;
    for (int i = 0; i < count; i++)
    {
        if (slices[i] !is null && slices[i].length > 0 && destBytes !is null && pos < totalLen)
        {
            size_t copyLen = slices[i].length;
            if (pos + copyLen > totalLen)
                copyLen = totalLen - pos;
            memcpy(destBytes.ptr + pos, slices[i].ptr, copyLen);
            pos += copyLen;
        }
        engine.freeValue(elemHandles[i]);
    }

    // Buffer = Uint8Array subclass — set prototype directly, no JS factory call.
    engine.setPrototype(u8, _bufProto);
    engine.freeValue(u8Pinned);
    return u8;
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
    else if (encoding == "base64url")
    {
        try
        {
            import std.base64 : Base64;
            auto b64 = (() @trusted => cast(string) Base64.encode(slice))();
            return engine.newString(base64ToBase64url(b64));
        }
        catch (Exception) { return engine.newString(""); }
    }
    else if (encoding == "latin1" || encoding == "binary")
    {
        /* Latin-1 → UTF-8 via the SIMD scratch helper.
           `IJSEngine.newString` takes UTF-8, so bytes 0x80..0xFF must
           be encoded as 2-byte sequences (0xC2 0x80 .. 0xC3 0xBF) for
           the engine to read them as U+0080..U+00FF code points. The
           previous version cast bytes directly to `char` and lost the
           high half — `Buffer.from([0x80]).toString('latin1')` came
           back as the UTF-8 replacement char instead of "".

           StackFallback!STACK_LATIN1_BUDGET keeps the worst-case
           output (2× src) on the stack for typical Buffer-to-string
           conversions (≤ STACK_LATIN1_BUDGET / 2 bytes input) with
           zero GC pressure; larger buffers spill silently to GC. */
        import dun.platform.arena : StackFallback;
        import dun.platform.simd : latin1ToUtf8Buf, latin1ToUtf8MaxLen;
        enum STACK_LATIN1_BUDGET = 4096;
        StackFallback!STACK_LATIN1_BUDGET sfb;
        scope(exit) sfb.deallocateAll();
        if (slice.length == 0) return engine.newString("");
        auto raw = sfb.allocate(latin1ToUtf8MaxLen(slice.length));
        if (raw is null) return engine.newString("");
        auto chars = cast(char[]) raw;
        auto written = latin1ToUtf8Buf(slice, chars);
        return engine.newString(cast(const(char)[]) chars[0 .. written]);
    }
    else
    {
        /* `newString` copies the bytes into engine-owned storage,
           so we can pass the slice directly. The previous `.idup`
           allocated a redundant GC string on the hot Buffer.toString
           path. */
        return engine.newString(cast(const(char)[]) slice);
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

// buf.copy(target[, targetStart[, sourceStart[, sourceEnd]]])
JSHandle jsBufferCopy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsBufferCopy");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsBufferCopy");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.newInt(0);

    auto srcBytes = extractBytes(engine, thisVal);
    int targetStart = (args.length >= 2) ? engine.extractInt(args[1]) : 0;
    int sourceStart = (args.length >= 3) ? engine.extractInt(args[2]) : 0;
    int sourceEnd = (args.length >= 4) ? engine.extractInt(args[3]) : cast(int) srcBytes.length;

    if (sourceStart < 0) sourceStart = 0;
    if (sourceEnd > cast(int) srcBytes.length) sourceEnd = cast(int) srcBytes.length;
    if (targetStart < 0) targetStart = 0;
    if (sourceStart >= sourceEnd) return engine.newInt(0);

    auto src = srcBytes[sourceStart .. sourceEnd];

    // Get target's data property and write into it
    auto dataProp = engine.getProperty(args[0], "data");
    if (engine.isUndefined(dataProp) || !engine.isArray(dataProp))
    {
        engine.freeValue(dataProp);
        // Try direct byte extraction and reconstruction
        auto targetBytes = extractBytes(engine, args[0]);
        if (targetBytes.length == 0)
            return engine.newInt(0);

        // Copy into target bytes
        auto tgtMut = cast(ubyte[]) targetBytes;
        size_t copyLen = src.length;
        if (targetStart + copyLen > tgtMut.length)
            copyLen = tgtMut.length - targetStart;
        tgtMut[targetStart .. targetStart + copyLen] = src[0 .. copyLen];

        // Write back via data array
        auto dataArr = engine.getProperty(args[0], "data");
        if (!engine.isUndefined(dataArr) && engine.isArray(dataArr))
        {
            for (size_t i = 0; i < copyLen; i++)
                engine.setPropertyIndex(dataArr, cast(uint)(targetStart + i),
                    engine.newInt(cast(int) tgtMut[targetStart + i]));
        }
        engine.freeValue(dataArr);
        return engine.newInt(cast(int) copyLen);
    }

    // Copy bytes into target's data array
    size_t copyLen = src.length;
    auto targetLenH = engine.getProperty(args[0], "length");
    int targetLen = engine.extractInt(targetLenH);
    engine.freeValue(targetLenH);

    if (targetStart + cast(int) copyLen > targetLen)
        copyLen = targetLen - targetStart;

    for (size_t i = 0; i < copyLen; i++)
        engine.setPropertyIndex(dataProp, cast(uint)(targetStart + i),
            engine.newInt(cast(int) src[i]));

    engine.freeValue(dataProp);
    return engine.newInt(cast(int) copyLen);
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
    if (args.length < 1) return engine.dupValue(thisVal);
    auto bytes = extractBytes(engine, thisVal);

    if (engine.isNumber(args[0]))
    {
        ubyte fillVal = cast(ubyte) engine.extractInt(args[0]);
        bytes[] = fillVal;
    }
    else if (engine.isString(args[0]))
    {
        auto s = engine.extractString(args[0]);
        if (s.length > 0)
        {
            auto fillBytes = cast(const(ubyte)[]) s;
            foreach (i, ref b; bytes)
                b = fillBytes[i % fillBytes.length];
        }
        else
            bytes[] = 0;
    }
    else
        bytes[] = 0;
    return engine.dupValue(thisVal);
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

    /* Node-style argument parsing: write(string[, offset[, length[, encoding]]])
       Any positional arg can be the encoding string in place of a number,
       so we sniff each remaining slot for string-vs-number. */
    int offset = 0;
    int length = -1;        // -1 means "until end of buffer"
    string encoding = "utf8";
    if (args.length >= 2)
    {
        if (engine.isString(args[1]))
            encoding = engine.extractString(args[1]);
        else if (engine.isNumber(args[1]))
            offset = engine.extractInt(args[1]);
    }
    if (args.length >= 3)
    {
        if (engine.isString(args[2]))
            encoding = engine.extractString(args[2]);
        else if (engine.isNumber(args[2]))
            length = engine.extractInt(args[2]);
    }
    if (args.length >= 4 && engine.isString(args[3]))
        encoding = engine.extractString(args[3]);

    if (offset < 0 || offset > cast(int) bytes.length)
        return engine.throwRangeError("offset out of range");
    int avail = cast(int) bytes.length - offset;
    if (length < 0 || length > avail) length = avail;

    int written = 0;
    if (encoding == "latin1" || encoding == "binary")
    {
        /* JS strings hold UTF-8 in `extractString`; for latin1 we must
           decode each UTF-8 code point and store its low byte. Without
           this, `buf.write("\x80", 0, 1, "latin1")` would write 0xC2 (the
           UTF-8 lead byte) instead of 0x80 — the bug fixed in v1.1.4. */
        import dun.platform.simd : utf8ToLatin1Buf;
        // Decode into a scratch buffer, then memcpy up to `length` bytes.
        // Worst case: src.length == JS-string-length-in-UTF-8-bytes,
        // output is ≤ src bytes. Use a stack buffer for typical small
        // writes, GC for very large.
        import dun.platform.arena : StackFallback;
        enum WRITE_STACK_BUDGET = 4096;
        StackFallback!WRITE_STACK_BUDGET sfb;
        scope(exit) sfb.deallocateAll();
        auto raw = sfb.allocate(str.length);
        if (raw is null) return engine.newInt(0);
        auto decoded = cast(ubyte[]) raw;
        auto produced = utf8ToLatin1Buf(str, decoded);
        auto n = produced < cast(size_t) length ? produced : cast(size_t) length;
        bytes[offset .. offset + n] = decoded[0 .. n];
        written = cast(int) n;
    }
    else
    {
        // utf8 (default) and ascii: copy UTF-8 bytes through.
        // 'ascii' clamps each byte to its low 7 bits per Node semantics
        // — but only on byte ≥ 0x80, which the extractString UTF-8
        // already doesn't produce for ascii-only input.
        auto src = cast(const(ubyte)[]) str;
        size_t n = src.length < cast(size_t) length ? src.length : cast(size_t) length;
        bytes[offset .. offset + n] = src[0 .. n];
        if (encoding == "ascii")
            foreach (ref b; bytes[offset .. offset + n])
                if (b >= 0x80) b &= 0x7F;
        written = cast(int) n;
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
    import std.uni : toLower;
    import std.conv : to;
    string enc;
    try { enc = engine.extractString(args[0]).to!string.toLower; }
    catch (Exception) { return engine.newBool(false); }
    if (enc == "utf8" || enc == "utf-8" || enc == "ascii" || enc == "latin1" ||
        enc == "binary" || enc == "hex" || enc == "base64" || enc == "base64url" ||
        enc == "ucs2" || enc == "ucs-2" || enc == "utf16le" || enc == "utf-16le")
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

private string base64urlToBase64(string s) @safe pure
{
    import dun.platform.arena : Appender;
    Appender!(char[]) buf;
    buf.reserve(s.length + 4);
    foreach (c; s)
    {
        if (c == '-') buf ~= '+';
        else if (c == '_') buf ~= '/';
        else buf ~= c;
    }
    while (buf[].length % 4 != 0)
        buf ~= '=';
    return (() @trusted => cast(string) buf[])();
}

private string base64ToBase64url(string s) @safe pure
{
    import dun.platform.arena : Appender;
    Appender!(char[]) buf;
    buf.reserve(s.length);
    foreach (c; s)
    {
        if (c == '+') buf ~= '-';
        else if (c == '/') buf ~= '_';
        else if (c == '=') {}
        else buf ~= c;
    }
    return (() @trusted => cast(string) buf[])();
}
