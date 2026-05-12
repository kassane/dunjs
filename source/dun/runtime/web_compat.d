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

    // TextEncoder
    engine.setProperty(global, "TextEncoder",
        engine.newFunction(&jsTextEncoderConstructor, "TextEncoder", 0));

    // TextDecoder
    engine.setProperty(global, "TextDecoder",
        engine.newFunction(&jsTextDecoderConstructor, "TextDecoder", 0));

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
        return engine.newArray();

    string input = engine.extractString(args[0]);
    auto arr = engine.newArray();
    import std.conv : to;
    uint idx = 0;
    foreach (ubyte b; cast(ubyte[]) input)
        engine.setProperty(arr, (idx++).to!string, engine.newInt(cast(int) b));
    return arr;
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

    return engine.newString("");
}
