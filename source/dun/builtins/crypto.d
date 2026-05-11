module dun.builtins.crypto;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerCryptoModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerCryptoModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "randomBytes", engine.newFunction(&jsCryptoRandomBytes, "randomBytes", 1));
    engine.setProperty(obj, "randomUUID", engine.newFunction(&jsCryptoRandomUUID, "randomUUID", 0));
    engine.setProperty(obj, "createHash", engine.newFunction(&jsCryptoCreateHash, "createHash", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_crypto__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:crypto", &cryptoModuleInit);
        if (m is null) return;
        foreach (name; ["randomBytes", "randomUUID", "createHash"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int cryptoModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in cryptoModuleInit");
        assert(m !is null, "Null JSModuleDef in cryptoModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto cryptoObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_crypto__");
        foreach (name; ["randomBytes", "randomUUID", "createHash"])
        {
            auto fn = JS_GetPropertyStr(ctx, cryptoObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, cryptoObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

JSHandle jsCryptoRandomBytes(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoRandomBytes");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoRandomBytes");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("randomBytes requires a length argument");
    int n = engine.extractInt(args[0]);
    if (n < 0) return engine.throwTypeError("randomBytes length must be non-negative");
    try
    {
        import std.conv : to;
        auto bytes = osRandomBytes(n);
        auto arr = engine.newArray();
        foreach (i; 0 .. cast(uint) n)
            engine.setProperty(arr, i.to!string, engine.newInt(bytes[i]));
        return arr;
    }
    catch (Exception) { return engine.throwTypeError("Failed to generate random bytes"); }
}

JSHandle jsCryptoRandomUUID(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoRandomUUID");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoRandomUUID");
    auto engine = state.engine;
    try
    {
        auto bytes = osRandomBytes(16);
        bytes[6] = cast(ubyte)((bytes[6] & 0x0f) | 0x40);
        bytes[8] = cast(ubyte)((bytes[8] & 0x3f) | 0x80);
        import std.format : format;
        auto uuid = format(
            "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
            bytes[6], bytes[7], bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
        return engine.newString(uuid);
    }
    catch (Exception) { return engine.throwTypeError("Failed to generate UUID"); }
}

JSHandle jsCryptoCreateHash(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoCreateHash");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoCreateHash");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createHash requires an algorithm argument");
    auto algo = engine.extractString(args[0]);
    if (algo != "md5" && algo != "sha1" && algo != "sha256" && algo != "sha512")
        return engine.throwTypeError("Unsupported hash algorithm");

    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_data", engine.newString(""));
    engine.setProperty(obj, "update", engine.newFunction(&jsHashUpdate, "update", 1));
    engine.setProperty(obj, "digest", engine.newFunction(&jsHashDigest, "digest", 1));
    return obj;
}

JSHandle jsHashUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHashUpdate");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHashUpdate");
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);
    try
    {
        auto prev = engine.extractString(engine.getProperty(thisVal, "_data"));
        auto chunk = engine.extractString(args[0]);
        engine.setProperty(thisVal, "_data", engine.newString(prev ~ chunk));
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsHashDigest(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHashDigest");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHashDigest");
    auto engine = state.engine;
    try
    {
        auto algo = engine.extractString(engine.getProperty(thisVal, "_algo"));
        auto data = engine.extractString(engine.getProperty(thisVal, "_data"));
        return engine.newString(computeHash(algo, data));
    }
    catch (Exception) { return engine.throwTypeError("Failed to compute hash"); }
}

private ubyte[] osRandomBytes(int n) @trusted
{
    version (Posix)
    {
        import std.file : read;
        return cast(ubyte[]) read("/dev/urandom", cast(size_t) n);
    }
    else version (Windows)
    {
        import core.sys.windows.windows : BOOL, ULONG;
        extern (Windows) BOOL BCryptGenRandom(void*, ubyte*, ULONG, ULONG) nothrow;
        auto buf = new ubyte[n];
        BCryptGenRandom(null, buf.ptr, cast(ULONG) n, 0x00000002);
        return buf;
    }
    else
    {
        import std.random : uniform;
        auto buf = new ubyte[n];
        foreach (ref b; buf) b = cast(ubyte) uniform(0, 256);
        return buf;
    }
}

private string computeHash(string algo, string data) @trusted
{
    import std.digest : toHexString, LetterCase;
    switch (algo)
    {
        case "md5": { import std.digest.md : MD5, digest; return toHexString!(LetterCase.lower)(digest!MD5(data)).idup; }
        case "sha1": { import std.digest.sha : SHA1, digest; return toHexString!(LetterCase.lower)(digest!SHA1(data)).idup; }
        case "sha256": { import std.digest.sha : SHA256, digest; return toHexString!(LetterCase.lower)(digest!SHA256(data)).idup; }
        case "sha512": { import std.digest.sha : SHA512, digest; return toHexString!(LetterCase.lower)(digest!SHA512(data)).idup; }
        default: return "";
    }
}
