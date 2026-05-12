module dun.runtime.web_compat;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installWebCompat(IJSEngine engine) @trusted
{
    auto global = engine.getGlobal();

    // atob / btoa
    engine.setProperty(global, "atob", engine.newFunction(&jsAtob, "atob", 1));
    engine.setProperty(global, "btoa", engine.newFunction(&jsBtoa, "btoa", 1));

    // structuredClone (simplified: JSON round-trip)
    engine.setProperty(global, "structuredClone",
        engine.newFunction(&jsStructuredClone, "structuredClone", 1));

    // TextEncoder / TextDecoder — register as constructable via eval
    engine.setProperty(global, "__dun_te_init",
        engine.newFunction(&jsTextEncoderConstructor, "__dun_te_init", 0));
    engine.setProperty(global, "__dun_td_init",
        engine.newFunction(&jsTextDecoderConstructor, "__dun_td_init", 0));
    engine.setProperty(global, "__dun_te_encode",
        engine.newFunction(&jsTextEncoderEncode, "__dun_te_encode", 1));
    engine.setProperty(global, "__dun_td_decode",
        engine.newFunction(&jsTextDecoderDecode, "__dun_td_decode", 1));

    auto teRes = engine.eval(
        "globalThis.TextEncoder = function TextEncoder() {"
        ~ " this.encoding = 'utf-8';"
        ~ " this.encode = function(s) { return __dun_te_encode(s); };"
        ~ "};"
        ~ "globalThis.TextDecoder = function TextDecoder() {"
        ~ " this.encoding = 'utf-8';"
        ~ " this.decode = function(b) {"
        ~ "  if (typeof b === 'string') return b;"
        ~ "  if (!b || !b.length) return '';"
        ~ "  var r = '', i = 0, len = b.length;"
        ~ "  while (i < len) {"
        ~ "   var c = b[i++];"
        ~ "   if (c < 128) { r += String.fromCharCode(c); }"
        ~ "   else if (c < 224) { r += String.fromCharCode(((c & 31) << 6) | (b[i++] & 63)); }"
        ~ "   else if (c < 240) { r += String.fromCharCode(((c & 15) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63)); }"
        ~ "   else { var cp = ((c & 7) << 18) | ((b[i++] & 63) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63); cp -= 0x10000; r += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)); }"
        ~ "  } return r; };"
        ~ "};", "<web-compat>");
    if (!teRes.isError)
        engine.freeValue(teRes.value);

    engine.freeValue(global);
}

private:

// Base64 alphabet
immutable string b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

JSHandle jsAtob(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("atob requires a string argument");

    string encoded = engine.extractString(args[0]);
    try
    {
        import std.base64 : Base64;
        auto decoded = cast(string) Base64.decode(encoded);
        return engine.newString(decoded);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("Invalid base64: " ~ e.msg);
    }
}

JSHandle jsBtoa(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("btoa requires a string argument");

    string input = engine.extractString(args[0]);
    try
    {
        import std.base64 : Base64;
        return engine.newString(Base64.encode(cast(ubyte[]) input));
    }
    catch (Exception e)
    {
        return engine.throwTypeError("btoa: " ~ e.msg);
    }
}

JSHandle jsStructuredClone(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newUndefined();

    return deepClone(engine, args[0]);
}

JSHandle deepClone(IJSEngine engine, JSHandle val) @trusted
{
    if (engine.isNull(val) || engine.isUndefined(val))
        return val;
    if (engine.isString(val))
        return engine.newString(engine.extractString(val));
    if (engine.isNumber(val))
        return engine.newFloat(engine.extractFloat(val));
    if (engine.isBool(val))
        return engine.newBool(engine.extractBool(val));

    // For objects/arrays, use JSON round-trip via engine
    auto global = engine.getGlobal();
    auto jsonObj = engine.getProperty(global, "JSON");
    auto stringify = engine.getProperty(jsonObj, "stringify");
    auto parse = engine.getProperty(jsonObj, "parse");

    auto jsonStr = engine.callFunction(stringify, jsonObj, [val]);
    if (engine.isException(jsonStr))
    {
        engine.freeValue(parse);
        engine.freeValue(stringify);
        engine.freeValue(jsonObj);
        engine.freeValue(global);
        return engine.throwTypeError("structuredClone: not serializable");
    }

    auto result = engine.callFunction(parse, jsonObj, [jsonStr]);
    engine.freeValue(jsonStr);
    engine.freeValue(parse);
    engine.freeValue(stringify);
    engine.freeValue(jsonObj);
    engine.freeValue(global);

    if (engine.isException(result))
        return engine.throwTypeError("structuredClone: not serializable");

    return result;
}

JSHandle jsTextEncoderConstructor(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    auto obj = engine.newObject();
    engine.setProperty(obj, "encoding", engine.newString("utf-8"));
    engine.setProperty(obj, "encode", engine.newFunction(&jsTextEncoderEncode, "encode", 1));
    return obj;
}

JSHandle jsTextEncoderEncode(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newUint8Array(null);

    string input = engine.extractString(args[0]);
    return engine.newUint8Array(cast(const(ubyte)[]) input);
}

JSHandle jsTextDecoderConstructor(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    auto obj = engine.newObject();
    engine.setProperty(obj, "encoding", engine.newString("utf-8"));
    engine.setProperty(obj, "decode", engine.newFunction(&jsTextDecoderDecode, "decode", 1));
    return obj;
}

JSHandle jsTextDecoderDecode(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("");

    if (engine.isString(args[0]))
        return args[0];

    if (engine.isObject(args[0]))
    {
        int len = engine.getArrayLength(args[0]);
        if (len <= 0)
            return engine.newString("");
        try
        {
            auto buf = new char[len];
            foreach (i; 0 .. len)
            {
                auto elem = engine.getPropertyIndex(args[0], cast(uint) i);
                buf[i] = cast(char) engine.extractInt(elem);
                engine.freeValue(elem);
            }
            return engine.newString(buf[0 .. len]);
        }
        catch (Exception)
        {
            return engine.newString("");
        }
    }

    return engine.newString("");
}
