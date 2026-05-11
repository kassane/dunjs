module dun.builtins.crypto;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind;

void registerCryptoModule(JSContext* ctx) @trusted
{
    auto m = JS_NewCModule(ctx, "dun:crypto", &cryptoModuleInit);
    if (m is null)
        return;
    JS_AddModuleExport(ctx, m, "randomBytes");
    JS_AddModuleExport(ctx, m, "randomUUID");
    JS_AddModuleExport(ctx, m, "createHash");

    // CJS-compatible object stored on globalThis for require('dun:crypto') / require('crypto')
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "randomBytes", JS_NewCFunction(ctx, &jsCryptoRandomBytes, "randomBytes", 1));
    JS_SetPropertyStr(ctx, obj, "randomUUID",  JS_NewCFunction(ctx, &jsCryptoRandomUUID,  "randomUUID",  0));
    JS_SetPropertyStr(ctx, obj, "createHash",  JS_NewCFunction(ctx, &jsCryptoCreateHash,  "createHash",  1));
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__dun_cjs_crypto__", obj);
    JS_FreeValue(ctx, global);
}

private:

extern (C) int cryptoModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
{
    JS_SetModuleExport(ctx, m, "randomBytes",
        JS_NewCFunction(ctx, &jsCryptoRandomBytes, "randomBytes", 1));
    JS_SetModuleExport(ctx, m, "randomUUID",
        JS_NewCFunction(ctx, &jsCryptoRandomUUID, "randomUUID", 0));
    JS_SetModuleExport(ctx, m, "createHash",
        JS_NewCFunction(ctx, &jsCryptoCreateHash, "createHash", 1));
    return 0;
}

// Returns an Array of n random byte values (0-255)
extern (C) JSValue jsCryptoRandomBytes(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "randomBytes requires a length argument");

    int n;
    if (JS_ToInt32(ctx, &n, argv[0]) < 0 || n < 0)
        return JS_ThrowTypeError(ctx, "randomBytes length must be a non-negative integer");

    try
    {
        auto bytes = osRandomBytes(n);
        auto arr = JS_NewArray(ctx);
        for (uint i = 0; i < cast(uint) n; i++)
            JS_SetPropertyUint32(ctx, arr, i, JS_NewInt32(ctx, bytes[i]));
        return arr;
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to generate random bytes");
    }
}

// Returns a UUID v4 string
extern (C) JSValue jsCryptoRandomUUID(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    try
    {
        auto bytes = osRandomBytes(16);
        // Set version 4 (0100xxxx in byte 6)
        bytes[6] = cast(ubyte)((bytes[6] & 0x0f) | 0x40);
        // Set variant bits (10xxxxxx in byte 8)
        bytes[8] = cast(ubyte)((bytes[8] & 0x3f) | 0x80);

        // Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        import std.format : format;
        auto uuid = format(
            "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0],  bytes[1],  bytes[2],  bytes[3],
            bytes[4],  bytes[5],
            bytes[6],  bytes[7],
            bytes[8],  bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);
        return toJSValue(ctx, uuid);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to generate UUID");
    }
}

// Returns a hash builder: { update(data), digest(encoding) }
// State stored as _algo and _data properties on the returned object.
extern (C) JSValue jsCryptoCreateHash(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "createHash requires an algorithm argument");

    auto algo = jsArgToString(ctx, argv[0]);

    // Validate algorithm early
    if (algo != "md5" && algo != "sha1" && algo != "sha256" && algo != "sha512")
        return JS_ThrowTypeError(ctx, "Unsupported hash algorithm (md5, sha1, sha256, sha512)");

    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "_algo", toJSValue(ctx, algo));
    JS_SetPropertyStr(ctx, obj, "_data", toJSValue(ctx, ""));
    JS_SetPropertyStr(ctx, obj, "update",
        JS_NewCFunction(ctx, &jsHashUpdate, "update", 1));
    JS_SetPropertyStr(ctx, obj, "digest",
        JS_NewCFunction(ctx, &jsHashDigest, "digest", 1));
    return obj;
}

// hash.update(data) — appends to _data, returns `this` for chaining
extern (C) JSValue jsHashUpdate(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_DupValue(ctx, this_val);

    try
    {
        auto existing = JS_GetPropertyStr(ctx, this_val, "_data");
        auto prev = jsArgToString(ctx, existing);
        JS_FreeValue(ctx, existing);
        auto chunk = jsArgToString(ctx, argv[0]);
        JS_SetPropertyStr(ctx, this_val, "_data", toJSValue(ctx, prev ~ chunk));
    }
    catch (Exception) {}

    return JS_DupValue(ctx, this_val);
}

// hash.digest(encoding) — computes hash and returns hex string
extern (C) JSValue jsHashDigest(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    try
    {
        auto algoVal = JS_GetPropertyStr(ctx, this_val, "_algo");
        auto dataVal = JS_GetPropertyStr(ctx, this_val, "_data");
        auto algo = jsArgToString(ctx, algoVal);
        auto data = jsArgToString(ctx, dataVal);
        JS_FreeValue(ctx, algoVal);
        JS_FreeValue(ctx, dataVal);

        auto hex = computeHash(algo, data);
        return toJSValue(ctx, hex);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to compute hash");
    }
}

// --- Internal helpers ---

private ubyte[] osRandomBytes(int n) @trusted
{
    version (Posix)
    {
        import std.file : read;
        auto raw = cast(ubyte[]) read("/dev/urandom", cast(size_t) n);
        return raw;
    }
    else version (Windows)
    {
        import core.sys.windows.windows : BOOL, ULONG;
        extern (Windows) BOOL BCryptGenRandom(void*, ubyte*, ULONG, ULONG) nothrow;
        auto buf = new ubyte[n];
        BCryptGenRandom(null, buf.ptr, cast(ULONG) n, 0x00000002 /* BCRYPT_USE_SYSTEM_PREFERRED_RNG */);
        return buf;
    }
    else
    {
        import std.random : uniform;
        auto buf = new ubyte[n];
        foreach (ref b; buf)
            b = cast(ubyte) uniform(0, 256);
        return buf;
    }
}

private string computeHash(string algo, string data) @trusted
{
    import std.digest : toHexString, LetterCase;

    switch (algo)
    {
        case "md5":
        {
            import std.digest.md : MD5, digest;
            return toHexString!(LetterCase.lower)(digest!MD5(data)).idup;
        }
        case "sha1":
        {
            import std.digest.sha : SHA1, digest;
            return toHexString!(LetterCase.lower)(digest!SHA1(data)).idup;
        }
        case "sha256":
        {
            import std.digest.sha : SHA256, digest;
            return toHexString!(LetterCase.lower)(digest!SHA256(data)).idup;
        }
        case "sha512":
        {
            import std.digest.sha : SHA512, digest;
            return toHexString!(LetterCase.lower)(digest!SHA512(data)).idup;
        }
        default:
            return "";
    }
}
