module dun.runtime.web_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installWebCompat(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installWebCompat");
    auto global = engine.getGlobal();

    engine.setProperty(global, "structuredClone",
        engine.newFunction(&jsStructuredClone, "structuredClone", 1));

    // Native btoa/atob — CTFE lookup tables, faster than pure-JS for interpreter
    // engines; JIT engines optimize both paths similarly.
    engine.setProperty(global, "btoa",
        engine.newFunction(&jsNativeBtoa, "btoa", 1));
    engine.setProperty(global, "atob",
        engine.newFunction(&jsNativeAtob, "atob", 1));

    // TextEncoder/TextDecoder — native D encode/decode backed by typed array
    // direct access.  D strings are already UTF-8, so encode is a cast+copy.
    auto teRes = engine.eval(textEncoderSetup(), "<web-compat>");
    if (!teRes.isError)
        engine.freeValue(teRes.value);

    auto encodeFn = engine.newFunction(&jsNativeTextEncoderEncode, "__dun_te_encode", 1);
    engine.setProperty(global, "__dun_te_encode", encodeFn);

    auto encodeIntoFn = engine.newFunction(&jsNativeTextEncoderEncodeInto, "__dun_te_encodeInto", 2);
    engine.setProperty(global, "__dun_te_encodeInto", encodeIntoFn);

    auto decodeFn = engine.newFunction(&jsNativeTextDecoderDecode, "__dun_td_decode", 1);
    engine.setProperty(global, "__dun_td_decode", decodeFn);

    auto wireRes = engine.eval(textEncoderWire(), "<web-compat-wire>");
    if (!wireRes.isError)
        engine.freeValue(wireRes.value);

    engine.freeValue(global);
}

private string textEncoderSetup() pure nothrow @safe
{
    return
    "(function(){"
    ~ "globalThis.TextEncoder=function TextEncoder(){this.encoding='utf-8';};"
    ~ "globalThis.TextDecoder=function TextDecoder(l){this.encoding=l||'utf-8';};"
    ~ "})();";
}

private string textEncoderWire() pure nothrow @safe
{
    return
    "(function(){"
    ~ "TextEncoder.prototype.encode=function(s){return __dun_te_encode(String(s||''));};"
    ~ "TextEncoder.prototype.encodeInto=function(s,u8){return __dun_te_encodeInto(String(s||''),u8);};"
    ~ "TextDecoder.prototype.decode=function(b){if(typeof b==='string')return b;return __dun_td_decode(b);};"
    ~ "})();";
}

private:

// CTFE base64 tables
enum B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
enum ubyte[128] B64_DECODE = () {
    ubyte[128] t = 0xFF;
    foreach (i, c; B64_CHARS)
        t[c] = cast(ubyte) i;
    return t;
}();

JSHandle jsNativeBtoa(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in btoa");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in btoa");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("");

    auto input = engine.extractString(args[0]);
    if (input.length == 0) return engine.newString("");

    auto len = input.length;
    auto outLen = ((len + 2) / 3) * 4;
    enum STACK_LIMIT = 4096;
    char[STACK_LIMIT] stackBuf = void;
    char[] buf;
    if (outLen <= STACK_LIMIT)
        buf = stackBuf[0 .. outLen];
    else
        buf = new char[outLen];
    size_t pos = 0;
    size_t i = 0;

    while (i + 2 < len)
    {
        uint a = cast(ubyte) input[i++];
        uint b = cast(ubyte) input[i++];
        uint c = cast(ubyte) input[i++];
        uint n = (a << 16) | (b << 8) | c;
        buf[pos++] = B64_CHARS[(n >> 18) & 63];
        buf[pos++] = B64_CHARS[(n >> 12) & 63];
        buf[pos++] = B64_CHARS[(n >> 6) & 63];
        buf[pos++] = B64_CHARS[n & 63];
    }
    auto rem = len - i;
    if (rem == 1)
    {
        uint a = cast(ubyte) input[i];
        buf[pos++] = B64_CHARS[(a >> 2) & 63];
        buf[pos++] = B64_CHARS[(a << 4) & 63];
        buf[pos++] = '=';
        buf[pos++] = '=';
    }
    else if (rem == 2)
    {
        uint a = cast(ubyte) input[i];
        uint b = cast(ubyte) input[i + 1];
        buf[pos++] = B64_CHARS[(a >> 2) & 63];
        buf[pos++] = B64_CHARS[((a << 4) | (b >> 4)) & 63];
        buf[pos++] = B64_CHARS[(b << 2) & 63];
        buf[pos++] = '=';
    }

    return engine.newString(cast(string) buf[0 .. pos]);
}

JSHandle jsNativeAtob(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in atob");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in atob");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("");

    auto input = engine.extractString(args[0]);
    auto len = input.length;
    while (len > 0 && input[len - 1] == '=') len--;
    if (len == 0) return engine.newString("");

    auto outLen = (len * 3) / 4;
    enum STACK_LIMIT = 4096;
    char[STACK_LIMIT] stackBuf = void;
    char[] buf;
    if (outLen <= STACK_LIMIT)
        buf = stackBuf[0 .. outLen];
    else
        buf = new char[outLen];
    size_t pos = 0;
    size_t i = 0;

    while (i + 3 < len)
    {
        ubyte a = B64_DECODE[input[i++] & 0x7F];
        ubyte b = B64_DECODE[input[i++] & 0x7F];
        ubyte c = B64_DECODE[input[i++] & 0x7F];
        ubyte d = B64_DECODE[input[i++] & 0x7F];
        buf[pos++] = cast(char)((a << 2) | (b >> 4));
        buf[pos++] = cast(char)(((b & 0xF) << 4) | (c >> 2));
        buf[pos++] = cast(char)(((c & 3) << 6) | d);
    }
    auto rem = len - i;
    if (rem >= 2)
    {
        ubyte a = B64_DECODE[input[i++] & 0x7F];
        ubyte b = B64_DECODE[input[i++] & 0x7F];
        buf[pos++] = cast(char)((a << 2) | (b >> 4));
        if (rem >= 3)
        {
            ubyte c = B64_DECODE[input[i++] & 0x7F];
            buf[pos++] = cast(char)(((b & 0xF) << 4) | (c >> 2));
        }
    }

    return engine.newString(cast(string) buf[0 .. pos]);
}

JSHandle jsNativeTextEncoderEncode(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextEncoder.encode");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextEncoder.encode");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newUint8Array(cast(ubyte[]) []);

    auto input = engine.extractString(args[0]);
    if (input.length == 0) return engine.newUint8Array(cast(ubyte[]) []);

    // D strings are already UTF-8
    return engine.newUint8Array(cast(const(ubyte)[]) input);
}

JSHandle jsNativeTextEncoderEncodeInto(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextEncoder.encodeInto");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextEncoder.encodeInto");
    auto engine = state.engine;

    if (args.length < 2)
        return engine.throwTypeError("encodeInto requires string and Uint8Array");

    auto input = engine.extractString(args[0]);
    auto destBytes = engine.getTypedArrayBytes(args[1]);
    if (destBytes is null)
        return engine.throwTypeError("encodeInto: second argument must be a Uint8Array");

    auto src = cast(const(ubyte)[]) input;
    auto written = src.length < destBytes.length ? src.length : destBytes.length;
    import core.stdc.string : memcpy;
    if (written > 0)
        memcpy(destBytes.ptr, src.ptr, written);

    auto result = engine.newObject();
    engine.setProperty(result, "read", engine.newInt(cast(int) input.length));
    engine.setProperty(result, "written", engine.newInt(cast(int) written));
    return result;
}

JSHandle jsNativeTextDecoderDecode(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in TextDecoder.decode");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in TextDecoder.decode");
    auto engine = state.engine;

    if (args.length < 1 || engine.isUndefined(args[0]) || engine.isNull(args[0]))
        return engine.newString("");

    auto bytes = engine.getTypedArrayBytes(args[0]);
    if (bytes !is null && bytes.length > 0)
        return engine.newString(cast(const(char)[]) bytes);

    if (engine.isObject(args[0]))
    {
        auto lenVal = engine.getProperty(args[0], "length");
        if (engine.isNumber(lenVal))
        {
            int len = engine.extractInt(lenVal);
            if (len == 0) return engine.newString("");
            auto buf = new ubyte[len];
            foreach (i; 0 .. len)
            {
                auto elem = engine.getPropertyIndex(args[0], cast(uint) i);
                buf[i] = cast(ubyte) engine.extractInt(elem);
                engine.freeValue(elem);
            }
            return engine.newString(cast(const(char)[]) buf);
        }
    }

    return engine.newString("");
}

JSHandle jsStructuredClone(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in structuredClone");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    assert(engine !is null, "Null engine in structuredClone");

    if (args.length < 1)
        return engine.newUndefined();

    return deepClone(engine, args[0]);
}

// Cached JSON.stringify/parse handles for structuredClone hot path
__gshared JSHandle _cloneJsonObj, _cloneStringify, _cloneParse;
__gshared bool _cloneCached = false;

void ensureCloneCache(IJSEngine engine) @trusted
{
    if (_cloneCached) return;
    auto global = engine.getGlobal();
    _cloneJsonObj = engine.getProperty(global, "JSON");
    _cloneStringify = engine.getProperty(_cloneJsonObj, "stringify");
    _cloneParse = engine.getProperty(_cloneJsonObj, "parse");
    engine.freeValue(global);
    _cloneCached = true;
}

JSHandle deepClone(IJSEngine engine, JSHandle val) @trusted
{
    assert(engine !is null, "Null engine in deepClone");
    if (engine.isNull(val) || engine.isUndefined(val))
        return val;
    if (engine.isString(val))
        return engine.newString(engine.extractString(val));
    if (engine.isNumber(val))
        return engine.newFloat(engine.extractFloat(val));
    if (engine.isBool(val))
        return engine.newBool(engine.extractBool(val));

    ensureCloneCache(engine);

    auto jsonStr = engine.callFunction(_cloneStringify, _cloneJsonObj, [val]);
    if (engine.isException(jsonStr))
        return engine.throwTypeError("structuredClone: not serializable");

    auto result = engine.callFunction(_cloneParse, _cloneJsonObj, [jsonStr]);
    engine.freeValue(jsonStr);

    if (engine.isException(result))
        return engine.throwTypeError("structuredClone: not serializable");

    return result;
}
