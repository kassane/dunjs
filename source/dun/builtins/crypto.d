module dun.builtins.crypto;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum {
    SCRYPT_DEFAULT_N      = 16_384,
    SCRYPT_DEFAULT_R      = 8,
    SCRYPT_DEFAULT_P      = 1,
    SCRYPT_DEFAULT_MAXMEM = 32 * 1024 * 1024,
    SCRYPT_MAX_KEYLEN     = 1024,
}

// OpenSSL bindings for HMAC, PBKDF2, scrypt
private extern (C) @nogc nothrow
{
    alias EVP_MD = void;
    const(EVP_MD)* EVP_md5();
    const(EVP_MD)* EVP_sha1();
    const(EVP_MD)* EVP_sha256();
    const(EVP_MD)* EVP_sha512();

    // HMAC: returns pointer to result buffer (static internal), outLen set to digest length
    ubyte* HMAC(const(EVP_MD)* evp_md, const(void)* key, int key_len,
                const(ubyte)* data, size_t data_len, ubyte* md, uint* md_len);

    // PBKDF2
    int PKCS5_PBKDF2_HMAC(const(char)* pass, int passlen,
                           const(ubyte)* salt, int saltlen,
                           int iter, const(EVP_MD)* digest,
                           int keylen, ubyte* outbuf);

    // scrypt
    int EVP_PBE_scrypt(const(char)* pass, size_t passlen,
                       const(ubyte)* salt, size_t saltlen,
                       ulong N, ulong r, ulong p, ulong maxmem,
                       ubyte* key, size_t keylen);

    // Timing-safe comparison
    int CRYPTO_memcmp(const(void)* a, const(void)* b, size_t len);
}

private const(EVP_MD)* getEvpMd(string algo) @trusted nothrow @nogc
{
    if (algo == "md5") return EVP_md5();
    if (algo == "sha1") return EVP_sha1();
    if (algo == "sha256") return EVP_sha256();
    if (algo == "sha512") return EVP_sha512();
    return null;
}

void registerCryptoModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerCryptoModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "randomBytes", engine.newFunction(&jsCryptoRandomBytes, "randomBytes", 1));
    engine.setProperty(obj, "randomUUID", engine.newFunction(&jsCryptoRandomUUID, "randomUUID", 0));
    engine.setProperty(obj, "createHash", engine.newFunction(&jsCryptoCreateHash, "createHash", 1));
    engine.setProperty(obj, "createHmac", engine.newFunction(&jsCryptoCreateHmac, "createHmac", 2));
    engine.setProperty(obj, "timingSafeEqual", engine.newFunction(&jsCryptoTimingSafeEqual, "timingSafeEqual", 2));
    engine.setProperty(obj, "randomInt", engine.newFunction(&jsCryptoRandomInt, "randomInt", 2));
    engine.setProperty(obj, "pbkdf2Sync", engine.newFunction(&jsCryptoPbkdf2Sync, "pbkdf2Sync", 5));
    engine.setProperty(obj, "scryptSync", engine.newFunction(&jsCryptoScryptSync, "scryptSync", 3));
    engine.setProperty(obj, "getHashes", engine.newFunction(&jsCryptoGetHashes, "getHashes", 0));
    engine.setProperty(obj, "getCiphers", engine.newFunction(&jsCryptoGetCiphers, "getCiphers", 0));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_crypto__", obj);
    engine.freeValue(global);

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
        foreach (name; ["randomBytes", "randomUUID", "createHash", "createHmac",
                        "timingSafeEqual", "randomInt", "pbkdf2Sync", "scryptSync",
                        "getHashes", "getCiphers"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int cryptoModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in cryptoModuleInit");
        assert(m !is null, "Null JSModuleDef in cryptoModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto cryptoObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_crypto__");
        foreach (name; ["randomBytes", "randomUUID", "createHash", "createHmac",
                        "timingSafeEqual", "randomInt", "pbkdf2Sync", "scryptSync",
                        "getHashes", "getCiphers"])
        {
            auto fn = JS_GetPropertyStr(ctx, cryptoObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, cryptoObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

// Public API for cross-module access (used by dun.runtime.web_apis)
JSHandle jsCryptoRandomUUID(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoRandomUUID");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoRandomUUID");
    auto engine = state.engine;
    try
    {
        auto bytes = nextUUIDBytes();
        bytes[6] = cast(ubyte)((bytes[6] & 0x0f) | 0x40);
        bytes[8] = cast(ubyte)((bytes[8] & 0x3f) | 0x80);
        import dun.platform.simd : hexEncodeBuf;
        char[32] hex = void;
        hexEncodeBuf(bytes[], hex[]);
        char[36] uuid = void;
        uuid[0 .. 8] = hex[0 .. 8];
        uuid[8] = '-';
        uuid[9 .. 13] = hex[8 .. 12];
        uuid[13] = '-';
        uuid[14 .. 18] = hex[12 .. 16];
        uuid[18] = '-';
        uuid[19 .. 23] = hex[16 .. 20];
        uuid[23] = '-';
        uuid[24 .. 36] = hex[20 .. 32];
        return engine.newString(cast(string) uuid[]);
    }
    catch (Exception) { return engine.throwTypeError("Failed to generate UUID"); }
}

JSHandle jsCryptoRandomBytes(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import core.stdc.stdlib : malloc, free;

    assert(ctx !is null, "Null ctx in jsCryptoRandomBytes");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoRandomBytes");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("randomBytes requires a length argument");
    int n = engine.extractInt(args[0]);
    if (n < 0) return engine.throwTypeError("randomBytes length must be non-negative");
    enum STACK_LIMIT = 256;
    ubyte[STACK_LIMIT] stackBuf = void;
    if (n <= STACK_LIMIT)
    {
        auto buf = stackBuf[0 .. n];
        fillRandomBytes(buf);
        return engine.newUint8Array(buf);
    }
    auto buf = cast(ubyte*) malloc(n);
    if (buf is null) return engine.throwTypeError("Failed to allocate random bytes buffer");
    scope(exit) free(buf);
    fillRandomBytes(buf[0 .. n]);
    return engine.newUint8Array(buf[0 .. n]);
}

void fillRandomBytesPublic(ubyte[] buf) @trusted
{
    fillRandomBytes(buf);
}

private:

// Pre-filled random byte pool — amortizes getrandom syscall cost across UUIDs
enum UUID_POOL_UUIDS = 64;
enum UUID_POOL_BYTES = UUID_POOL_UUIDS * 16;
__gshared ubyte[UUID_POOL_BYTES] _uuidPool = void;
__gshared size_t _uuidPoolPos = UUID_POOL_BYTES;

ubyte[16] nextUUIDBytes() @trusted
{
    if (_uuidPoolPos >= UUID_POOL_BYTES)
    {
        fillRandomBytes(_uuidPool[]);
        _uuidPoolPos = 0;
    }
    ubyte[16] r = _uuidPool[_uuidPoolPos .. _uuidPoolPos + 16];
    _uuidPoolPos += 16;
    return r;
}

immutable char[16] hexLUT = "0123456789abcdef";

__gshared int _urandomFd = -1;

private void fillRandomBytes(ubyte[] buf) @trusted
{
    version (linux)
    {
        // getrandom syscall: no fd management, faster for small buffers
        import core.sys.linux.unistd : syscall;
        import core.sys.linux.sys.syscall : __NR_getrandom;
        {
            size_t total = 0;
            while (total < buf.length)
            {
                auto n = syscall(__NR_getrandom, buf.ptr + total, buf.length - total, 0);
                if (n <= 0) break;
                total += n;
            }
            if (total >= buf.length) return;
        }
    }
    version (Posix)
    {
        import core.sys.posix.unistd : read;
        import core.sys.posix.fcntl : open, O_RDONLY;
        if (_urandomFd < 0)
            _urandomFd = open("/dev/urandom", O_RDONLY);
        assert(_urandomFd >= 0, "Failed to open /dev/urandom");
        size_t total = 0;
        while (total < buf.length)
        {
            auto n = read(_urandomFd, buf.ptr + total, buf.length - total);
            if (n <= 0) break;
            total += n;
        }
    }
    else
    {
        auto bytes = osRandomBytes(cast(int) buf.length);
        buf[0 .. bytes.length] = bytes[];
    }
}

// Cached function handles — registered once to avoid callback slot exhaustion
private __gshared JSHandle _cachedUpdateFn;
private __gshared JSHandle _cachedDigestFn;
private __gshared bool _hashFnsCached = false;

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

    if (!_hashFnsCached)
    {
        _cachedUpdateFn = engine.newFunction(&jsHashUpdate, "update", 1);
        _cachedDigestFn = engine.newFunction(&jsHashDigest, "digest", 1);
        _hashFnsCached = true;
    }

    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_data", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedUpdateFn));
    engine.setProperty(obj, "digest", engine.dupValue(_cachedDigestFn));
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
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto prev = engine.extractString(dataProp);
        engine.freeValue(dataProp);
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
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto data = engine.extractString(dataProp);
        engine.freeValue(dataProp);
        return engine.newString(computeHash(algo, data));
    }
    catch (Exception) { return engine.throwTypeError("Failed to compute hash"); }
}

// --- createHmac ---

private __gshared JSHandle _cachedHmacUpdateFn;
private __gshared JSHandle _cachedHmacDigestFn;
private __gshared bool _hmacFnsCached = false;

JSHandle jsCryptoCreateHmac(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoCreateHmac");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoCreateHmac");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("createHmac requires algorithm and key arguments");
    auto algo = engine.extractString(args[0]);
    auto key = engine.extractString(args[1]);
    if (getEvpMd(algo) is null)
        return engine.throwTypeError("Unsupported HMAC algorithm: " ~ algo);

    if (!_hmacFnsCached)
    {
        _cachedHmacUpdateFn = engine.newFunction(&jsHmacUpdate, "update", 1);
        _cachedHmacDigestFn = engine.newFunction(&jsHmacDigest, "digest", 1);
        _hmacFnsCached = true;
    }

    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_key", engine.newString(key));
    engine.setProperty(obj, "_data", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedHmacUpdateFn));
    engine.setProperty(obj, "digest", engine.dupValue(_cachedHmacDigestFn));
    return obj;
}

JSHandle jsHmacUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHmacUpdate");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHmacUpdate");
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);
    try
    {
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto prev = engine.extractString(dataProp);
        engine.freeValue(dataProp);
        auto chunk = engine.extractString(args[0]);
        engine.setProperty(thisVal, "_data", engine.newString(prev ~ chunk));
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsHmacDigest(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsHmacDigest");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsHmacDigest");
    auto engine = state.engine;
    try
    {
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);
        auto keyProp = engine.getProperty(thisVal, "_key");
        auto key = engine.extractString(keyProp);
        engine.freeValue(keyProp);
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto data = engine.extractString(dataProp);
        engine.freeValue(dataProp);
        return engine.newString(computeHmac(algo, key, data));
    }
    catch (Exception) { return engine.throwTypeError("Failed to compute HMAC"); }
}

// --- timingSafeEqual ---

JSHandle jsCryptoTimingSafeEqual(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoTimingSafeEqual");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoTimingSafeEqual");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("timingSafeEqual requires two arguments");
    try
    {
        auto a = engine.extractString(args[0]);
        auto b = engine.extractString(args[1]);
        if (a.length != b.length)
            return engine.throwTypeError("Input buffers must have the same byte length");
        if (a.length == 0)
            return engine.newBool(true);
        int result = CRYPTO_memcmp(cast(const(void)*) a.ptr, cast(const(void)*) b.ptr, a.length);
        return engine.newBool(result == 0);
    }
    catch (Exception) { return engine.throwTypeError("timingSafeEqual failed"); }
}

// --- randomInt ---

JSHandle jsCryptoRandomInt(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoRandomInt");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoRandomInt");
    auto engine = state.engine;
    int minVal = 0;
    int maxVal = 0;
    if (args.length >= 2 && engine.isNumber(args[0]) && engine.isNumber(args[1]))
    {
        minVal = engine.extractInt(args[0]);
        maxVal = engine.extractInt(args[1]);
    }
    else if (args.length >= 1 && engine.isNumber(args[0]))
    {
        maxVal = engine.extractInt(args[0]);
    }
    else
        return engine.throwTypeError("randomInt requires at least one numeric argument");

    if (minVal >= maxVal)
        return engine.throwTypeError("min must be less than max");
    try
    {
        auto bytes = osRandomBytes(4);
        uint raw = (cast(uint) bytes[0]) | (cast(uint) bytes[1] << 8) |
                   (cast(uint) bytes[2] << 16) | (cast(uint) bytes[3] << 24);
        int range = maxVal - minVal;
        int val = minVal + cast(int)(raw % cast(uint) range);
        return engine.newInt(val);
    }
    catch (Exception) { return engine.throwTypeError("randomInt failed"); }
}

// --- pbkdf2Sync ---

JSHandle jsCryptoPbkdf2Sync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoPbkdf2Sync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoPbkdf2Sync");
    auto engine = state.engine;
    if (args.length < 5)
        return engine.throwTypeError("pbkdf2Sync requires password, salt, iterations, keylen, digest");
    try
    {
        auto password = engine.extractString(args[0]);
        auto salt = engine.extractString(args[1]);
        int iterations = engine.extractInt(args[2]);
        int keylen = engine.extractInt(args[3]);
        auto digest = engine.extractString(args[4]);

        auto md = getEvpMd(digest);
        if (md is null)
            return engine.throwTypeError("Unsupported digest: " ~ digest);
        if (iterations <= 0)
            return engine.throwTypeError("iterations must be positive");
        if (keylen <= 0 || keylen > 1024)
            return engine.throwTypeError("keylen must be between 1 and 1024");

        auto outbuf = new ubyte[keylen];
        int rc = PKCS5_PBKDF2_HMAC(
            password.ptr, cast(int) password.length,
            cast(const(ubyte)*) salt.ptr, cast(int) salt.length,
            iterations, md, keylen, outbuf.ptr);
        if (rc != 1)
            return engine.throwTypeError("PBKDF2 failed");

        // Return as hex string
        import std.digest : toHexString, LetterCase;
        return engine.newString(toHexString!(LetterCase.lower)(outbuf).idup);
    }
    catch (Exception) { return engine.throwTypeError("pbkdf2Sync failed"); }
}

// --- scryptSync ---

JSHandle jsCryptoScryptSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoScryptSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoScryptSync");
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("scryptSync requires password, salt, keylen");
    try
    {
        auto password = engine.extractString(args[0]);
        auto salt = engine.extractString(args[1]);
        int keylen = engine.extractInt(args[2]);

        if (keylen <= 0 || keylen > SCRYPT_MAX_KEYLEN)
            return engine.throwTypeError("keylen must be between 1 and 1024");

        ulong N = SCRYPT_DEFAULT_N;
        ulong r = SCRYPT_DEFAULT_R;
        ulong p = SCRYPT_DEFAULT_P;
        ulong maxmem = SCRYPT_DEFAULT_MAXMEM;

        // Optional options object as 4th arg
        if (args.length >= 4 && engine.isObject(args[3]))
        {
            auto optN = engine.getProperty(args[3], "N");
            auto optR = engine.getProperty(args[3], "r");
            auto optP = engine.getProperty(args[3], "p");
            if (engine.isNumber(optN)) N = cast(ulong) engine.extractInt(optN);
            if (engine.isNumber(optR)) r = cast(ulong) engine.extractInt(optR);
            if (engine.isNumber(optP)) p = cast(ulong) engine.extractInt(optP);
            engine.freeValue(optN);
            engine.freeValue(optR);
            engine.freeValue(optP);
        }

        auto outbuf = new ubyte[keylen];
        int rc = EVP_PBE_scrypt(
            password.ptr, password.length,
            cast(const(ubyte)*) salt.ptr, salt.length,
            N, r, p, maxmem,
            outbuf.ptr, cast(size_t) keylen);
        if (rc != 1)
            return engine.throwTypeError("scrypt failed");

        import std.digest : toHexString, LetterCase;
        return engine.newString(toHexString!(LetterCase.lower)(outbuf).idup);
    }
    catch (Exception) { return engine.throwTypeError("scryptSync failed"); }
}

// --- getHashes / getCiphers ---

JSHandle jsCryptoGetHashes(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoGetHashes");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoGetHashes");
    auto engine = state.engine;
    auto arr = engine.newArray();
    uint idx = 0;
    foreach (name; ["md5", "sha1", "sha256", "sha512"])
        engine.setPropertyIndex(arr, idx++, engine.newString(name));
    return arr;
}

JSHandle jsCryptoGetCiphers(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoGetCiphers");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoGetCiphers");
    auto engine = state.engine;
    auto arr = engine.newArray();
    uint idx = 0;
    foreach (name; ["aes-128-cbc", "aes-192-cbc", "aes-256-cbc",
                    "aes-128-gcm", "aes-256-gcm",
                    "des-ede3-cbc", "rc4", "chacha20-poly1305"])
        engine.setPropertyIndex(arr, idx++, engine.newString(name));
    return arr;
}

// --- Helper functions ---

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

private string computeHmac(string algo, string key, string data) @trusted
{
    auto md = getEvpMd(algo);
    if (md is null) return "";

    ubyte[64] outBuf;
    uint outLen = 0;

    auto result = HMAC(md,
        cast(const(void)*) key.ptr, cast(int) key.length,
        cast(const(ubyte)*) data.ptr, data.length,
        outBuf.ptr, &outLen);

    if (result is null || outLen == 0) return "";

    import std.digest : toHexString, LetterCase;
    return toHexString!(LetterCase.lower)(outBuf[0 .. outLen]).idup;
}
