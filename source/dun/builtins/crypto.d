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
    const(EVP_MD)* EVP_sha224();
    const(EVP_MD)* EVP_sha256();
    const(EVP_MD)* EVP_sha384();
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

    // Cipher API (EVP)
    alias EVP_CIPHER_CTX = void;
    alias EVP_CIPHER = void;
    EVP_CIPHER_CTX* EVP_CIPHER_CTX_new();
    void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX* ctx);
    int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX* ctx, int type, int arg, void* ptr);

    const(EVP_CIPHER)* EVP_aes_128_cbc();
    const(EVP_CIPHER)* EVP_aes_192_cbc();
    const(EVP_CIPHER)* EVP_aes_256_cbc();
    const(EVP_CIPHER)* EVP_aes_128_gcm();
    const(EVP_CIPHER)* EVP_aes_256_gcm();

    int EVP_EncryptInit_ex(EVP_CIPHER_CTX* ctx, const(EVP_CIPHER)* type,
        void* impl, const(ubyte)* key, const(ubyte)* iv);
    int EVP_EncryptUpdate(EVP_CIPHER_CTX* ctx, ubyte* outbuf, int* outl,
        const(ubyte)* inbuf, int inl);
    int EVP_EncryptFinal_ex(EVP_CIPHER_CTX* ctx, ubyte* outbuf, int* outl);

    int EVP_DecryptInit_ex(EVP_CIPHER_CTX* ctx, const(EVP_CIPHER)* type,
        void* impl, const(ubyte)* key, const(ubyte)* iv);
    int EVP_DecryptUpdate(EVP_CIPHER_CTX* ctx, ubyte* outbuf, int* outl,
        const(ubyte)* inbuf, int inl);
    int EVP_DecryptFinal_ex(EVP_CIPHER_CTX* ctx, ubyte* outbuf, int* outl);

    enum EVP_CTRL_GCM_SET_IVLEN = 0x9;
    enum EVP_CTRL_GCM_GET_TAG = 0x10;
    enum EVP_CTRL_GCM_SET_TAG = 0x11;

    // EVP signing/verification
    alias EVP_MD_CTX = void;
    EVP_MD_CTX* EVP_MD_CTX_new();
    void EVP_MD_CTX_free(EVP_MD_CTX* ctx);
    int EVP_DigestSignInit(EVP_MD_CTX* ctx, void** pctx, const(EVP_MD)* type, void* e, EVP_PKEY* pkey);
    int EVP_DigestSignUpdate(EVP_MD_CTX* ctx, const(void)* d, size_t cnt);
    int EVP_DigestSignFinal(EVP_MD_CTX* ctx, ubyte* sig, size_t* siglen);
    int EVP_DigestVerifyInit(EVP_MD_CTX* ctx, void** pctx, const(EVP_MD)* type, void* e, EVP_PKEY* pkey);
    int EVP_DigestVerifyUpdate(EVP_MD_CTX* ctx, const(void)* d, size_t cnt);
    int EVP_DigestVerifyFinal(EVP_MD_CTX* ctx, const(ubyte)* sig, size_t siglen);

    // PEM key reading
    alias EVP_PKEY = void;
    EVP_PKEY* PEM_read_bio_PrivateKey(void* bp, EVP_PKEY** x, void* cb, void* u);
    EVP_PKEY* PEM_read_bio_PUBKEY(void* bp, EVP_PKEY** x, void* cb, void* u);
    void EVP_PKEY_free(EVP_PKEY* pkey);

    // BIO for reading PEM from memory
    alias BIO = void;
    alias BIO_METHOD = void;
    BIO* BIO_new_mem_buf(const(void)* buf, int len);
    BIO* BIO_new(const(BIO_METHOD)* type);
    const(BIO_METHOD)* BIO_s_mem();
    int BIO_free(BIO* a);
    int BIO_read(BIO* b, void* data, int dlen);
    long BIO_ctrl(BIO* bp, int cmd, long larg, void* parg);

    // Key generation (EVP_PKEY_CTX)
    alias EVP_PKEY_CTX = void;
    EVP_PKEY_CTX* EVP_PKEY_CTX_new_id(int id, void* e);
    void EVP_PKEY_CTX_free(EVP_PKEY_CTX* ctx);
    int EVP_PKEY_keygen_init(EVP_PKEY_CTX* ctx);
    int EVP_PKEY_keygen(EVP_PKEY_CTX* ctx, EVP_PKEY** ppkey);
    int EVP_PKEY_CTX_set_rsa_keygen_bits(EVP_PKEY_CTX* ctx, int mbits);

    // EC key generation
    int EVP_PKEY_CTX_set_ec_paramgen_curve_nid(EVP_PKEY_CTX* ctx, int nid);
    int OBJ_txt2nid(const(char)* s);

    // PEM writing
    int PEM_write_bio_PrivateKey(BIO* bp, EVP_PKEY* x, const(EVP_CIPHER)* enc,
                                 ubyte* kstr, int klen, void* cb, void* u);
    int PEM_write_bio_PUBKEY(BIO* bp, EVP_PKEY* pkey);

    // DH key exchange
    alias DH = void;
    alias BIGNUM = void;
    DH* DH_new();
    void DH_free(DH* dh);
    int DH_generate_parameters_ex(DH* dh, int prime_len, int generator, void* cb);
    int DH_generate_key(DH* dh);
    int DH_compute_key(ubyte* key, const(BIGNUM)* pub_key, DH* dh);
    int DH_size(const(DH)* dh);
    const(BIGNUM)* DH_get0_pub_key(const(DH)* dh);
    const(BIGNUM)* DH_get0_priv_key(const(DH)* dh);
    const(BIGNUM)* DH_get0_p(const(DH)* dh);
    const(BIGNUM)* DH_get0_g(const(DH)* dh);

    // BIGNUM helpers
    int BN_num_bits(const(BIGNUM)* a);
    int BN_bn2bin(const(BIGNUM)* a, ubyte* to);
    BIGNUM* BN_bin2bn(const(ubyte)* s, int len, BIGNUM* ret);
    void BN_free(BIGNUM* a);

    enum EVP_PKEY_RSA = 6;
    enum EVP_PKEY_EC = 408;
    enum BIO_CTRL_PENDING = 10;
}

private const(EVP_MD)* getEvpMd(string algo) @trusted nothrow @nogc
{
    if (algo == "md5") return EVP_md5();
    if (algo == "sha1") return EVP_sha1();
    if (algo == "sha224") return EVP_sha224();
    if (algo == "sha256") return EVP_sha256();
    if (algo == "sha384") return EVP_sha384();
    if (algo == "sha512") return EVP_sha512();
    return null;
}

/// Normalize algorithm name: accept "SHA256", "RSA-SHA256", etc.
private string normalizeAlgo(string algo) @safe pure nothrow
{
    // Convert to lowercase
    char[64] buf = void;
    if (algo.length > buf.length) return null;
    foreach (i, c; algo)
        buf[i] = (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
    auto lower = (() @trusted => cast(string) buf[0 .. algo.length])();

    // Strip "rsa-" or "ecdsa-" prefix
    if (lower.length > 4 && lower[0 .. 4] == "rsa-")
        lower = lower[4 .. $];
    else if (lower.length > 6 && lower[0 .. 6] == "ecdsa-")
        lower = lower[6 .. $];

    // Match known algorithms
    if (lower == "md5") return "md5";
    if (lower == "sha1") return "sha1";
    if (lower == "sha224") return "sha224";
    if (lower == "sha256") return "sha256";
    if (lower == "sha384") return "sha384";
    if (lower == "sha512") return "sha512";
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
    engine.setProperty(obj, "createCipheriv", engine.newFunction(&jsCryptoCreateCipheriv, "createCipheriv", 3));
    engine.setProperty(obj, "createDecipheriv", engine.newFunction(&jsCryptoCreateDecipheriv, "createDecipheriv", 3));
    engine.setProperty(obj, "getHashes", engine.newFunction(&jsCryptoGetHashes, "getHashes", 0));
    engine.setProperty(obj, "getCiphers", engine.newFunction(&jsCryptoGetCiphers, "getCiphers", 0));
    engine.setProperty(obj, "createSign", engine.newFunction(&jsCryptoCreateSign, "createSign", 1));
    engine.setProperty(obj, "createVerify", engine.newFunction(&jsCryptoCreateVerify, "createVerify", 1));
    engine.setProperty(obj, "generateKeyPairSync", engine.newFunction(&jsCryptoGenerateKeyPairSync, "generateKeyPairSync", 2));
    engine.setProperty(obj, "createDiffieHellman", engine.newFunction(&jsCryptoCreateDiffieHellman, "createDiffieHellman", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_crypto__", obj);

    auto cryptoExtResult = engine.eval(cryptoExtensionSource(), "<crypto-ext>");
    if (!cryptoExtResult.isError)
    {
        foreach (name; ["pbkdf2", "scrypt", "randomFillSync", "randomFill",
                        "constants", "KeyObject", "createSecretKey", "createPublicKey",
                        "createPrivateKey", "X509Certificate", "createECDH",
                        "generateKeySync", "hkdfSync", "hkdf", "generateKey",
                        "generateKeyPair", "getDiffieHellman", "createDiffieHellmanGroup",
                        "diffieHellman", "getCurves", "secureHeapUsed", "setFips",
                        "getFips", "checkPrime", "checkPrimeSync", "generatePrime",
                        "generatePrimeSync", "hash", "webcrypto", "subtle"])
        {
            auto prop = engine.getProperty(cryptoExtResult.value, name);
            engine.setProperty(obj, name, prop);
        }
    }
    engine.freeValue(cryptoExtResult.value);
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
        foreach (name; cryptoExportNames)
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private static immutable cryptoExportNames = [
        "randomBytes", "randomUUID", "createHash", "createHmac",
        "timingSafeEqual", "randomInt", "pbkdf2Sync", "scryptSync",
        "createCipheriv", "createDecipheriv",
        "getHashes", "getCiphers",
        "pbkdf2", "scrypt", "randomFillSync", "randomFill",
        "createSign", "createVerify", "generateKeyPairSync",
        "createDiffieHellman", "constants",
        "KeyObject", "createSecretKey", "createPublicKey", "createPrivateKey",
        "X509Certificate", "createECDH", "generateKeySync", "hkdfSync",
        "hkdf", "generateKey", "generateKeyPair", "getDiffieHellman",
        "createDiffieHellmanGroup", "diffieHellman", "getCurves",
        "secureHeapUsed", "setFips", "getFips", "checkPrime", "checkPrimeSync",
        "generatePrime", "generatePrimeSync", "hash", "webcrypto", "subtle"
    ];

    private extern (C) int cryptoModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in cryptoModuleInit");
        assert(m !is null, "Null JSModuleDef in cryptoModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto cryptoObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_crypto__");
        foreach (name; cryptoExportNames)
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
    if (algo != "md5" && algo != "sha1" && algo != "sha224" && algo != "sha256" && algo != "sha384" && algo != "sha512")
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

// --- createCipheriv / createDecipheriv ---

private const(EVP_CIPHER)* getEvpCipher(string algo) @trusted nothrow @nogc
{
    if (algo == "aes-128-cbc") return EVP_aes_128_cbc();
    if (algo == "aes-192-cbc") return EVP_aes_192_cbc();
    if (algo == "aes-256-cbc") return EVP_aes_256_cbc();
    if (algo == "aes-128-gcm") return EVP_aes_128_gcm();
    if (algo == "aes-256-gcm") return EVP_aes_256_gcm();
    return null;
}

private bool isGcmCipher(string algo) @safe pure nothrow
{
    return algo == "aes-128-gcm" || algo == "aes-256-gcm";
}

private __gshared JSHandle _cachedCipherUpdateFn;
private __gshared JSHandle _cachedCipherFinalFn;
private __gshared JSHandle _cachedCipherGetAuthTagFn;
private __gshared JSHandle _cachedDecipherUpdateFn;
private __gshared JSHandle _cachedDecipherFinalFn;
private __gshared JSHandle _cachedDecipherSetAuthTagFn;
private __gshared bool _cipherFnsCached = false;

private void ensureCipherFnsCached(IJSEngine engine) @trusted
{
    if (_cipherFnsCached) return;
    _cachedCipherUpdateFn = engine.newFunction(&jsCipherUpdate, "update", 1);
    _cachedCipherFinalFn = engine.newFunction(&jsCipherFinal, "final", 0);
    _cachedCipherGetAuthTagFn = engine.newFunction(&jsCipherGetAuthTag, "getAuthTag", 0);
    _cachedDecipherUpdateFn = engine.newFunction(&jsDecipherUpdate, "update", 1);
    _cachedDecipherFinalFn = engine.newFunction(&jsDecipherFinal, "final", 0);
    _cachedDecipherSetAuthTagFn = engine.newFunction(&jsDecipherSetAuthTag, "setAuthTag", 1);
    _cipherFnsCached = true;
}

JSHandle jsCryptoCreateCipheriv(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in createCipheriv");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("createCipheriv requires algorithm, key, iv");
    auto algo = engine.extractString(args[0]);
    auto cipher = getEvpCipher(algo);
    if (cipher is null)
        return engine.throwTypeError("Unsupported cipher: " ~ algo);
    auto key = engine.extractString(args[1]);
    auto iv = engine.extractString(args[2]);

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return engine.throwTypeError("Failed to create cipher context");

    if (EVP_EncryptInit_ex(evpCtx, cipher, null,
        cast(const(ubyte)*) key.ptr, cast(const(ubyte)*) iv.ptr) != 1)
    {
        EVP_CIPHER_CTX_free(evpCtx);
        return engine.throwTypeError("Failed to initialize cipher");
    }

    ensureCipherFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_evpCtx", engine.newFloat(cast(double) cast(size_t) evpCtx));
    engine.setProperty(obj, "_output", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedCipherUpdateFn));
    engine.setProperty(obj, "final", engine.dupValue(_cachedCipherFinalFn));
    if (isGcmCipher(algo))
        engine.setProperty(obj, "getAuthTag", engine.dupValue(_cachedCipherGetAuthTagFn));
    return obj;
}

JSHandle jsCipherUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in cipher.update");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Cipher already finalized");

    try
    {
        auto input = engine.extractString(args[0]);
        auto outbuf = new ubyte[input.length + 16];
        int outlen = 0;
        if (EVP_EncryptUpdate(evpCtx, outbuf.ptr, &outlen,
            cast(const(ubyte)*) input.ptr, cast(int) input.length) != 1)
            return engine.throwTypeError("Cipher update failed");

        import std.digest : toHexString, LetterCase;
        auto prevProp = engine.getProperty(thisVal, "_output");
        auto prev = engine.extractString(prevProp);
        engine.freeValue(prevProp);
        auto hex = toHexString!(LetterCase.lower)(outbuf[0 .. outlen]).idup;
        engine.setProperty(thisVal, "_output", engine.newString(prev ~ hex));
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsCipherFinal(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in cipher.final");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Cipher already finalized");

    ubyte[32] outbuf;
    int outlen = 0;
    auto rc = EVP_EncryptFinal_ex(evpCtx, outbuf.ptr, &outlen);

    auto algoProp = engine.getProperty(thisVal, "_algo");
    auto algo = engine.extractString(algoProp);
    engine.freeValue(algoProp);

    if (isGcmCipher(algo))
    {
        ubyte[16] tag;
        EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_GET_TAG, 16, tag.ptr);
        import std.digest : toHexString, LetterCase;
        engine.setProperty(thisVal, "_authTag", engine.newString(
            toHexString!(LetterCase.lower)(tag[]).idup));
    }

    EVP_CIPHER_CTX_free(evpCtx);
    engine.setProperty(thisVal, "_evpCtx", engine.newFloat(0));

    if (rc != 1)
        return engine.throwTypeError("Cipher final failed");

    auto prevProp = engine.getProperty(thisVal, "_output");
    auto prev = engine.extractString(prevProp);
    engine.freeValue(prevProp);

    if (outlen > 0)
    {
        import std.digest : toHexString, LetterCase;
        return engine.newString(prev ~ toHexString!(LetterCase.lower)(outbuf[0 .. outlen]).idup);
    }
    return engine.newString(prev);
}

JSHandle jsCipherGetAuthTag(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in cipher.getAuthTag");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto tagProp = engine.getProperty(thisVal, "_authTag");
    if (engine.isUndefined(tagProp) || engine.isNull(tagProp))
    {
        engine.freeValue(tagProp);
        return engine.throwTypeError("Auth tag not available — call .final() first");
    }
    return tagProp;
}

// --- Decipher ---

JSHandle jsCryptoCreateDecipheriv(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in createDecipheriv");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("createDecipheriv requires algorithm, key, iv");
    auto algo = engine.extractString(args[0]);
    auto cipher = getEvpCipher(algo);
    if (cipher is null)
        return engine.throwTypeError("Unsupported cipher: " ~ algo);
    auto key = engine.extractString(args[1]);
    auto iv = engine.extractString(args[2]);

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return engine.throwTypeError("Failed to create decipher context");

    if (EVP_DecryptInit_ex(evpCtx, cipher, null,
        cast(const(ubyte)*) key.ptr, cast(const(ubyte)*) iv.ptr) != 1)
    {
        EVP_CIPHER_CTX_free(evpCtx);
        return engine.throwTypeError("Failed to initialize decipher");
    }

    ensureCipherFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_evpCtx", engine.newFloat(cast(double) cast(size_t) evpCtx));
    engine.setProperty(obj, "_output", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedDecipherUpdateFn));
    engine.setProperty(obj, "final", engine.dupValue(_cachedDecipherFinalFn));
    if (isGcmCipher(algo))
        engine.setProperty(obj, "setAuthTag", engine.dupValue(_cachedDecipherSetAuthTagFn));
    return obj;
}

JSHandle jsDecipherUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in decipher.update");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Decipher already finalized");

    try
    {
        auto input = engine.extractString(args[0]);
        // Parse hex input to bytes
        if (input.length % 2 != 0)
            return engine.throwTypeError("Invalid hex input");
        auto inBytes = new ubyte[input.length / 2];
        foreach (i; 0 .. inBytes.length)
        {
            inBytes[i] = cast(ubyte)(hexVal(input[i * 2]) << 4 | hexVal(input[i * 2 + 1]));
        }

        auto outbuf = new ubyte[inBytes.length + 16];
        int outlen = 0;
        if (EVP_DecryptUpdate(evpCtx, outbuf.ptr, &outlen,
            inBytes.ptr, cast(int) inBytes.length) != 1)
            return engine.throwTypeError("Decipher update failed");

        auto prevProp = engine.getProperty(thisVal, "_output");
        auto prev = engine.extractString(prevProp);
        engine.freeValue(prevProp);
        engine.setProperty(thisVal, "_output",
            engine.newString(prev ~ (() @trusted => cast(string) outbuf[0 .. outlen])()));
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsDecipherFinal(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in decipher.final");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Decipher already finalized");

    ubyte[32] outbuf;
    int outlen = 0;
    auto rc = EVP_DecryptFinal_ex(evpCtx, outbuf.ptr, &outlen);
    EVP_CIPHER_CTX_free(evpCtx);
    engine.setProperty(thisVal, "_evpCtx", engine.newFloat(0));

    if (rc != 1)
        return engine.throwTypeError("Decipher final failed (bad padding or auth tag)");

    auto prevProp = engine.getProperty(thisVal, "_output");
    auto prev = engine.extractString(prevProp);
    engine.freeValue(prevProp);

    if (outlen > 0)
        return engine.newString(prev ~ (() @trusted => cast(string) outbuf[0 .. outlen])());
    return engine.newString(prev);
}

JSHandle jsDecipherSetAuthTag(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in decipher.setAuthTag");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("setAuthTag requires a tag");

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Decipher already finalized");

    auto tagHex = engine.extractString(args[0]);
    if (tagHex.length % 2 != 0)
        return engine.throwTypeError("Invalid auth tag hex");
    auto tagBytes = new ubyte[tagHex.length / 2];
    foreach (i; 0 .. tagBytes.length)
        tagBytes[i] = cast(ubyte)(hexVal(tagHex[i * 2]) << 4 | hexVal(tagHex[i * 2 + 1]));

    EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_SET_TAG, cast(int) tagBytes.length, tagBytes.ptr);
    return engine.dupValue(thisVal);
}

private ubyte hexVal(char c) @safe pure nothrow
{
    if (c >= '0' && c <= '9') return cast(ubyte)(c - '0');
    if (c >= 'a' && c <= 'f') return cast(ubyte)(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return cast(ubyte)(c - 'A' + 10);
    return 0;
}

// --- createSign / createVerify ---

private __gshared JSHandle _cachedSignUpdateFn;
private __gshared JSHandle _cachedSignSignFn;
private __gshared JSHandle _cachedVerifyUpdateFn;
private __gshared JSHandle _cachedVerifyVerifyFn;
private __gshared bool _signFnsCached = false;

private void ensureSignFnsCached(IJSEngine engine) @trusted
{
    if (_signFnsCached) return;
    _cachedSignUpdateFn = engine.newFunction(&jsSignUpdate, "update", 1);
    _cachedSignSignFn = engine.newFunction(&jsSignSign, "sign", 2);
    _cachedVerifyUpdateFn = engine.newFunction(&jsVerifyUpdate, "update", 1);
    _cachedVerifyVerifyFn = engine.newFunction(&jsVerifyVerify, "verify", 3);
    _signFnsCached = true;
}

JSHandle jsCryptoCreateSign(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoCreateSign");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoCreateSign");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createSign requires an algorithm argument");
    auto rawAlgo = engine.extractString(args[0]);
    auto algo = normalizeAlgo(rawAlgo);
    if (algo is null)
        return engine.throwTypeError("Unsupported sign algorithm: " ~ rawAlgo);

    ensureSignFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_data", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedSignUpdateFn));
    engine.setProperty(obj, "sign", engine.dupValue(_cachedSignSignFn));
    return obj;
}

JSHandle jsSignUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSignUpdate");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSignUpdate");
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

JSHandle jsSignSign(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSignSign");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSignSign");
    auto engine = state.engine;
    if (args.length < 1)
        return engine.throwTypeError("sign() requires a private key argument");
    try
    {
        // Extract algorithm
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);

        // Extract accumulated data
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto data = engine.extractString(dataProp);
        engine.freeValue(dataProp);

        // Extract private key (string or object with 'key' property)
        string pemKey;
        if (engine.isObject(args[0]))
        {
            auto keyProp = engine.getProperty(args[0], "key");
            pemKey = engine.extractString(keyProp);
            engine.freeValue(keyProp);
        }
        else
            pemKey = engine.extractString(args[0]);

        // Extract output encoding (default: 'buffer')
        string outputEncoding = "buffer";
        if (args.length >= 2 && engine.isString(args[1]))
            outputEncoding = engine.extractString(args[1]);

        // Perform the signing via OpenSSL
        auto signature = evpSign(algo, pemKey, data);
        if (signature is null)
            return engine.throwTypeError("Signing failed — invalid key or algorithm");

        return encodeOutput(engine, signature, outputEncoding);
    }
    catch (Exception e) { return engine.throwTypeError("sign() failed: " ~ e.msg); }
}

JSHandle jsCryptoCreateVerify(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoCreateVerify");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoCreateVerify");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createVerify requires an algorithm argument");
    auto rawAlgo = engine.extractString(args[0]);
    auto algo = normalizeAlgo(rawAlgo);
    if (algo is null)
        return engine.throwTypeError("Unsupported verify algorithm: " ~ rawAlgo);

    ensureSignFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_data", engine.newString(""));
    engine.setProperty(obj, "update", engine.dupValue(_cachedVerifyUpdateFn));
    engine.setProperty(obj, "verify", engine.dupValue(_cachedVerifyVerifyFn));
    return obj;
}

JSHandle jsVerifyUpdate(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsVerifyUpdate");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsVerifyUpdate");
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

JSHandle jsVerifyVerify(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsVerifyVerify");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsVerifyVerify");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("verify() requires a public key and signature");
    try
    {
        // Extract algorithm
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);

        // Extract accumulated data
        auto dataProp = engine.getProperty(thisVal, "_data");
        auto data = engine.extractString(dataProp);
        engine.freeValue(dataProp);

        // Extract public key (string or object with 'key' property)
        string pemKey;
        if (engine.isObject(args[0]))
        {
            auto keyProp = engine.getProperty(args[0], "key");
            pemKey = engine.extractString(keyProp);
            engine.freeValue(keyProp);
        }
        else
            pemKey = engine.extractString(args[0]);

        // Extract signature
        auto sigStr = engine.extractString(args[1]);

        // Extract signature encoding (default: 'buffer')
        string sigEncoding = "buffer";
        if (args.length >= 3 && engine.isString(args[2]))
            sigEncoding = engine.extractString(args[2]);

        // Decode the signature
        auto sigBytes = decodeInput(sigStr, sigEncoding);
        if (sigBytes is null && sigStr.length > 0)
            return engine.throwTypeError("Invalid signature encoding");

        // Perform the verification via OpenSSL
        auto result = evpVerify(algo, pemKey, data, sigBytes);
        return engine.newBool(result);
    }
    catch (Exception e) { return engine.throwTypeError("verify() failed: " ~ e.msg); }
}

/// Sign data using OpenSSL EVP_DigestSign
private ubyte[] evpSign(string algo, string pemKey, string data) @trusted nothrow
{
    assert(pemKey.length > 0, "Empty PEM key in evpSign");

    // Load private key from PEM
    auto bio = BIO_new_mem_buf(cast(const(void)*) pemKey.ptr, cast(int) pemKey.length);
    if (bio is null) return null;

    auto pkey = PEM_read_bio_PrivateKey(bio, null, null, null);
    BIO_free(bio);
    if (pkey is null) return null;
    scope(exit) EVP_PKEY_free(pkey);

    auto md = getEvpMd(algo);
    if (md is null) return null;

    auto mdCtx = EVP_MD_CTX_new();
    if (mdCtx is null) return null;
    scope(exit) EVP_MD_CTX_free(mdCtx);

    if (EVP_DigestSignInit(mdCtx, null, md, null, pkey) != 1)
        return null;
    if (EVP_DigestSignUpdate(mdCtx, cast(const(void)*) data.ptr, data.length) != 1)
        return null;

    // First call: get required signature length
    size_t sigLen = 0;
    if (EVP_DigestSignFinal(mdCtx, null, &sigLen) != 1)
        return null;

    // Allocate and sign
    ubyte[] sig;
    try { sig = new ubyte[sigLen]; } catch (Exception) { return null; }

    if (EVP_DigestSignFinal(mdCtx, sig.ptr, &sigLen) != 1)
        return null;

    return sig[0 .. sigLen];
}

/// Verify signature using OpenSSL EVP_DigestVerify
private bool evpVerify(string algo, string pemKey, string data, const(ubyte)[] signature) @trusted nothrow
{
    assert(pemKey.length > 0, "Empty PEM key in evpVerify");

    // Load public key from PEM
    auto bio = BIO_new_mem_buf(cast(const(void)*) pemKey.ptr, cast(int) pemKey.length);
    if (bio is null) return false;

    auto pkey = PEM_read_bio_PUBKEY(bio, null, null, null);
    BIO_free(bio);
    if (pkey is null) return false;
    scope(exit) EVP_PKEY_free(pkey);

    auto md = getEvpMd(algo);
    if (md is null) return false;

    auto mdCtx = EVP_MD_CTX_new();
    if (mdCtx is null) return false;
    scope(exit) EVP_MD_CTX_free(mdCtx);

    if (EVP_DigestVerifyInit(mdCtx, null, md, null, pkey) != 1)
        return false;
    if (EVP_DigestVerifyUpdate(mdCtx, cast(const(void)*) data.ptr, data.length) != 1)
        return false;

    return EVP_DigestVerifyFinal(mdCtx, signature.ptr, signature.length) == 1;
}

/// Encode binary data to the requested output encoding
private JSHandle encodeOutput(IJSEngine engine, const(ubyte)[] data, string encoding) @trusted
{
    if (encoding == "hex")
    {
        import std.digest : toHexString, LetterCase;
        return engine.newString(toHexString!(LetterCase.lower)(data).idup);
    }
    else if (encoding == "base64")
    {
        import std.base64 : Base64;
        return engine.newString(Base64.encode(data));
    }
    else // "buffer" — return as Uint8Array
    {
        return engine.newUint8Array(cast(ubyte[]) data);
    }
}

/// Decode input string from the given encoding to bytes
private ubyte[] decodeInput(string input, string encoding) @trusted
{
    if (encoding == "hex")
    {
        if (input.length % 2 != 0) return null;
        auto result = new ubyte[input.length / 2];
        foreach (i; 0 .. result.length)
            result[i] = cast(ubyte)(hexVal(input[i * 2]) << 4 | hexVal(input[i * 2 + 1]));
        return result;
    }
    else if (encoding == "base64")
    {
        import std.base64 : Base64;
        try { return Base64.decode(input); }
        catch (Exception) { return null; }
    }
    else // "buffer" — raw bytes
    {
        return cast(ubyte[]) input.dup;
    }
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
    foreach (name; ["md5", "sha1", "sha224", "sha256", "sha384", "sha512"])
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
        case "sha224": { import std.digest.sha : SHA224, digest; return toHexString!(LetterCase.lower)(digest!SHA224(data)).idup; }
        case "sha256": { import std.digest.sha : SHA256, digest; return toHexString!(LetterCase.lower)(digest!SHA256(data)).idup; }
        case "sha384": { import std.digest.sha : SHA384, digest; return toHexString!(LetterCase.lower)(digest!SHA384(data)).idup; }
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

// --- generateKeyPairSync ---

/// Read all pending data from a BIO into a D string
private string bioToString(BIO* bio) @trusted nothrow
{
    assert(bio !is null, "Null BIO in bioToString");
    auto pending = BIO_ctrl(bio, BIO_CTRL_PENDING, 0, null);
    if (pending <= 0) return null;

    ubyte[] buf;
    try { buf = new ubyte[cast(size_t) pending]; }
    catch (Exception) { return null; }

    auto n = BIO_read(bio, buf.ptr, cast(int) pending);
    if (n <= 0) return null;
    try { return (cast(char[]) buf[0 .. n]).idup; }
    catch (Exception) { return null; }
}

/// Generate an RSA or EC key pair via OpenSSL, returns (publicKeyPEM, privateKeyPEM)
private bool evpGenerateKeyPair(string type, int modulusLength, string namedCurve,
    out string publicKeyPEM, out string privateKeyPEM) @trusted nothrow
{
    int pkeyType;
    if (type == "rsa")
        pkeyType = EVP_PKEY_RSA;
    else if (type == "ec")
        pkeyType = EVP_PKEY_EC;
    else
        return false;

    auto pkCtx = EVP_PKEY_CTX_new_id(pkeyType, null);
    if (pkCtx is null) return false;
    scope(exit) EVP_PKEY_CTX_free(pkCtx);

    if (EVP_PKEY_keygen_init(pkCtx) <= 0) return false;

    if (type == "rsa")
    {
        if (EVP_PKEY_CTX_set_rsa_keygen_bits(pkCtx, modulusLength) <= 0)
            return false;
    }
    else if (type == "ec")
    {
        // Convert curve name to NID
        char[64] curveBuf = void;
        if (namedCurve.length >= curveBuf.length) return false;
        curveBuf[0 .. namedCurve.length] = cast(char[]) namedCurve[];
        curveBuf[namedCurve.length] = '\0';
        auto nid = OBJ_txt2nid(curveBuf.ptr);
        if (nid == 0) return false;
        if (EVP_PKEY_CTX_set_ec_paramgen_curve_nid(pkCtx, nid) <= 0)
            return false;
    }

    EVP_PKEY* pkey = null;
    if (EVP_PKEY_keygen(pkCtx, &pkey) <= 0) return false;
    if (pkey is null) return false;
    scope(exit) EVP_PKEY_free(pkey);

    // Write private key to PEM
    auto privBio = BIO_new(BIO_s_mem());
    if (privBio is null) return false;
    scope(exit) BIO_free(privBio);

    if (PEM_write_bio_PrivateKey(privBio, pkey, null, null, 0, null, null) != 1)
        return false;
    privateKeyPEM = bioToString(privBio);
    if (privateKeyPEM is null) return false;

    // Write public key to PEM
    auto pubBio = BIO_new(BIO_s_mem());
    if (pubBio is null) return false;
    scope(exit) BIO_free(pubBio);

    if (PEM_write_bio_PUBKEY(pubBio, pkey) != 1)
        return false;
    publicKeyPEM = bioToString(pubBio);
    if (publicKeyPEM is null) return false;

    return true;
}

JSHandle jsCryptoGenerateKeyPairSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoGenerateKeyPairSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoGenerateKeyPairSync");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("generateKeyPairSync requires a type argument");

    auto type = engine.extractString(args[0]);
    if (type != "rsa" && type != "ec")
        return engine.throwTypeError("Unsupported key type: " ~ type ~ " (supported: rsa, ec)");

    // Parse options
    int modulusLength = 2048;
    string namedCurve = "prime256v1";

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto opts = args[1];
        if (type == "rsa")
        {
            auto modProp = engine.getProperty(opts, "modulusLength");
            if (engine.isNumber(modProp))
                modulusLength = engine.extractInt(modProp);
            engine.freeValue(modProp);
        }
        else if (type == "ec")
        {
            auto curveProp = engine.getProperty(opts, "namedCurve");
            if (engine.isString(curveProp))
                namedCurve = engine.extractString(curveProp);
            engine.freeValue(curveProp);
        }
    }

    string publicKeyPEM, privateKeyPEM;
    if (!evpGenerateKeyPair(type, modulusLength, namedCurve, publicKeyPEM, privateKeyPEM))
        return engine.throwTypeError("Key generation failed");

    auto result = engine.newObject();
    engine.setProperty(result, "publicKey", engine.newString(publicKeyPEM));
    engine.setProperty(result, "privateKey", engine.newString(privateKeyPEM));
    return result;
}

// --- createDiffieHellman ---

private __gshared JSHandle _cachedDHGenerateKeysFn;
private __gshared JSHandle _cachedDHGetPublicKeyFn;
private __gshared JSHandle _cachedDHGetPrivateKeyFn;
private __gshared JSHandle _cachedDHComputeSecretFn;
private __gshared JSHandle _cachedDHGetPrimeFn;
private __gshared JSHandle _cachedDHGetGeneratorFn;
private __gshared bool _dhFnsCached = false;

private void ensureDHFnsCached(IJSEngine engine) @trusted
{
    if (_dhFnsCached) return;
    _cachedDHGenerateKeysFn = engine.newFunction(&jsDHGenerateKeys, "generateKeys", 0);
    _cachedDHGetPublicKeyFn = engine.newFunction(&jsDHGetPublicKey, "getPublicKey", 1);
    _cachedDHGetPrivateKeyFn = engine.newFunction(&jsDHGetPrivateKey, "getPrivateKey", 1);
    _cachedDHComputeSecretFn = engine.newFunction(&jsDHComputeSecret, "computeSecret", 3);
    _cachedDHGetPrimeFn = engine.newFunction(&jsDHGetPrime, "getPrime", 1);
    _cachedDHGetGeneratorFn = engine.newFunction(&jsDHGetGenerator, "getGenerator", 1);
    _dhFnsCached = true;
}

/// Encode a BIGNUM to hex string
private string bnToHex(const(BIGNUM)* bn) @trusted nothrow
{
    if (bn is null) return "";
    auto nbytes = (BN_num_bits(bn) + 7) / 8;
    if (nbytes <= 0) return "";
    ubyte[] buf;
    try { buf = new ubyte[nbytes]; }
    catch (Exception) { return ""; }
    BN_bn2bin(bn, buf.ptr);
    try
    {
        import std.digest : toHexString, LetterCase;
        return toHexString!(LetterCase.lower)(buf).idup;
    }
    catch (Exception) { return ""; }
}

JSHandle jsCryptoCreateDiffieHellman(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsCryptoCreateDiffieHellman");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsCryptoCreateDiffieHellman");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isNumber(args[0]))
        return engine.throwTypeError("createDiffieHellman requires a primeLength argument");

    int primeLength = engine.extractInt(args[0]);
    if (primeLength < 64 || primeLength > 8192)
        return engine.throwTypeError("primeLength must be between 64 and 8192");

    // Generate DH parameters
    auto dh = DH_new();
    if (dh is null)
        return engine.throwTypeError("Failed to create DH context");

    if (DH_generate_parameters_ex(dh, primeLength, 2, null) != 1)
    {
        DH_free(dh);
        return engine.throwTypeError("Failed to generate DH parameters");
    }

    ensureDHFnsCached(engine);
    auto obj = engine.newObject();
    // Store DH pointer as float (same pattern as cipher _evpCtx)
    engine.setProperty(obj, "_dh", engine.newFloat(cast(double) cast(size_t) dh));
    engine.setProperty(obj, "generateKeys", engine.dupValue(_cachedDHGenerateKeysFn));
    engine.setProperty(obj, "getPublicKey", engine.dupValue(_cachedDHGetPublicKeyFn));
    engine.setProperty(obj, "getPrivateKey", engine.dupValue(_cachedDHGetPrivateKeyFn));
    engine.setProperty(obj, "computeSecret", engine.dupValue(_cachedDHComputeSecretFn));
    engine.setProperty(obj, "getPrime", engine.dupValue(_cachedDHGetPrimeFn));
    engine.setProperty(obj, "getGenerator", engine.dupValue(_cachedDHGetGeneratorFn));
    return obj;
}

private DH* extractDH(IJSEngine engine, JSHandle thisVal) @trusted
{
    auto dhProp = engine.getProperty(thisVal, "_dh");
    auto dh = cast(DH*) cast(size_t) engine.extractFloat(dhProp);
    engine.freeValue(dhProp);
    return dh;
}

JSHandle jsDHGenerateKeys(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.generateKeys");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    if (DH_generate_key(dh) != 1)
        return engine.throwTypeError("Failed to generate DH key");

    // Return public key as hex by default
    auto pubKey = DH_get0_pub_key(dh);
    return engine.newString(bnToHex(pubKey));
}

JSHandle jsDHGetPublicKey(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.getPublicKey");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto pubKey = DH_get0_pub_key(dh);
    if (pubKey is null) return engine.throwTypeError("Keys not yet generated");
    return engine.newString(bnToHex(pubKey));
}

JSHandle jsDHGetPrivateKey(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.getPrivateKey");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto privKey = DH_get0_priv_key(dh);
    if (privKey is null) return engine.throwTypeError("Keys not yet generated");
    return engine.newString(bnToHex(privKey));
}

JSHandle jsDHComputeSecret(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.computeSecret");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");
    if (args.length < 1) return engine.throwTypeError("computeSecret requires otherPublicKey");

    auto otherKeyHex = engine.extractString(args[0]);

    // Decode hex to BIGNUM
    auto otherKeyBytes = decodeInput(otherKeyHex, "hex");
    if (otherKeyBytes is null)
        return engine.throwTypeError("Invalid hex encoding for otherPublicKey");

    auto otherPub = BN_bin2bn(otherKeyBytes.ptr, cast(int) otherKeyBytes.length, null);
    if (otherPub is null)
        return engine.throwTypeError("Failed to decode other public key");
    scope(exit) BN_free(otherPub);

    auto secretLen = DH_size(dh);
    if (secretLen <= 0)
        return engine.throwTypeError("DH_size returned invalid length");

    ubyte[] secret;
    try { secret = new ubyte[secretLen]; }
    catch (Exception) { return engine.throwTypeError("Failed to allocate secret buffer"); }

    auto n = DH_compute_key(secret.ptr, otherPub, dh);
    if (n < 0)
        return engine.throwTypeError("DH_compute_key failed");

    import std.digest : toHexString, LetterCase;
    try { return engine.newString(toHexString!(LetterCase.lower)(secret[0 .. n]).idup); }
    catch (Exception) { return engine.throwTypeError("Failed to encode secret"); }
}

JSHandle jsDHGetPrime(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.getPrime");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto p = DH_get0_p(dh);
    if (p is null) return engine.throwTypeError("No prime available");
    return engine.newString(bnToHex(p));
}

JSHandle jsDHGetGenerator(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in DH.getGenerator");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto g = DH_get0_g(dh);
    if (g is null) return engine.throwTypeError("No generator available");
    return engine.newString(bnToHex(g));
}

string cryptoExtensionSource() pure @safe nothrow
{
    return `(function() {
  var crypto = globalThis.__dun_cjs_crypto__;

  function pbkdf2(password, salt, iterations, keylen, digest, callback) {
    if (typeof digest === 'function') { callback = digest; digest = 'sha1'; }
    Promise.resolve().then(function() {
      try {
        var result = crypto.pbkdf2Sync(password, salt, iterations, keylen, digest);
        callback(null, result);
      } catch(e) {
        callback(e);
      }
    });
  }

  function scrypt(password, salt, keylen, options, callback) {
    if (typeof options === 'function') { callback = options; options = {}; }
    Promise.resolve().then(function() {
      try {
        var result = crypto.scryptSync(password, salt, keylen);
        callback(null, result);
      } catch(e) {
        callback(e);
      }
    });
  }

  function randomFillSync(buf, offset, size) {
    offset = offset || 0;
    size = size || (buf.length - offset);
    var rnd = crypto.randomBytes(size);
    if (typeof rnd === 'string') {
      for (var i = 0; i < size && i < rnd.length; i++) {
        buf[offset + i] = rnd.charCodeAt(i);
      }
    } else if (rnd && rnd.length) {
      for (var i = 0; i < size && i < rnd.length; i++) {
        buf[offset + i] = rnd[i];
      }
    }
    return buf;
  }

  function randomFill(buf, offset, size, callback) {
    if (typeof offset === 'function') { callback = offset; offset = 0; size = buf.length; }
    if (typeof size === 'function') { callback = size; size = buf.length - offset; }
    Promise.resolve().then(function() {
      try {
        callback(null, randomFillSync(buf, offset, size));
      } catch(e) {
        callback(e);
      }
    });
  }

  var constants = {
    SSL_OP_ALL: 0,
    ENGINE_METHOD_RSA: 1,
    DH_CHECK_P_NOT_SAFE_PRIME: 2,
    RSA_PKCS1_PADDING: 1,
    RSA_PKCS1_OAEP_PADDING: 4,
    RSA_NO_PADDING: 3,
    POINT_CONVERSION_COMPRESSED: 2,
    POINT_CONVERSION_UNCOMPRESSED: 4,
    defaultCoreCipherList: 'TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256',
    defaultCipherList: 'TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256'
  };

  // --- Stub classes for npm compat ---
  function KeyObject(type, data) { this.type = type; this._data = data; this.asymmetricKeyType = undefined; this.symmetricKeySize = data ? data.length : 0; }
  KeyObject.prototype.export = function() { return this._data || Buffer.alloc(0); };
  KeyObject.from = function(key) { return new KeyObject('secret', key); };

  function createSecretKey(key, encoding) {
    if (typeof key === 'string') key = Buffer.from(key, encoding || 'utf8');
    return new KeyObject('secret', key);
  }
  function createPublicKey(key) { return new KeyObject('public', typeof key === 'string' ? Buffer.from(key) : (key.key || key)); }
  function createPrivateKey(key) { return new KeyObject('private', typeof key === 'string' ? Buffer.from(key) : (key.key || key)); }

  function X509Certificate(buf) { this._buf = buf; this.subject = ''; this.issuer = ''; this.validFrom = ''; this.validTo = ''; this.serialNumber = ''; this.fingerprint = ''; this.fingerprint256 = ''; }
  X509Certificate.prototype.toString = function() { return this._buf ? this._buf.toString() : ''; };
  X509Certificate.prototype.toJSON = function() { return { subject: this.subject, issuer: this.issuer }; };

  function createECDH(curveName) {
    return {
      generateKeys: function(enc) { return enc ? '' : Buffer.alloc(65); },
      getPublicKey: function(enc) { return enc ? '' : Buffer.alloc(65); },
      getPrivateKey: function(enc) { return enc ? '' : Buffer.alloc(32); },
      setPrivateKey: function() {},
      computeSecret: function(key) { return Buffer.alloc(32); }
    };
  }

  function generateKeySync(type, options) { return new KeyObject('secret', crypto.randomBytes(options && options.length || 32)); }

  function hkdfSync(digest, ikm, salt, info, keylen) {
    return crypto.pbkdf2Sync(typeof ikm === 'string' ? ikm : ikm.toString(), salt || '', 1, keylen, digest || 'sha256');
  }
  function hkdf(digest, ikm, salt, info, keylen, callback) {
    Promise.resolve().then(function() {
      try { callback(null, hkdfSync(digest, ikm, salt, info, keylen)); }
      catch(e) { callback(e); }
    });
  }

  function generateKey(type, options, callback) {
    Promise.resolve().then(function() {
      try { callback(null, generateKeySync(type, options)); }
      catch(e) { callback(e); }
    });
  }
  function generateKeyPair(type, options, callback) {
    Promise.resolve().then(function() {
      try { var r = crypto.generateKeyPairSync(type, options); callback(null, r.publicKey, r.privateKey); }
      catch(e) { callback(e); }
    });
  }

  function getDiffieHellman(groupName) { return crypto.createDiffieHellman(256); }
  var createDiffieHellmanGroup = getDiffieHellman;
  function diffieHellman(options) { return Buffer.alloc(32); }

  function getCurves() { return ['prime256v1','secp384r1','secp521r1','secp256k1']; }
  function secureHeapUsed() { return { total: 0, min: 0, used: 0 }; }
  function setFips(val) {}
  function getFips() { return 0; }
  function checkPrimeSync(candidate) { return false; }
  function checkPrime(candidate, callback) { Promise.resolve().then(function() { callback(null, checkPrimeSync(candidate)); }); }
  function generatePrimeSync(size) { return crypto.randomBytes(Math.ceil((size || 256) / 8)); }
  function generatePrime(size, callback) { Promise.resolve().then(function() { try { callback(null, generatePrimeSync(size)); } catch(e) { callback(e); } }); }
  function hash(algorithm, data, outputEncoding) {
    var h = crypto.createHash(algorithm);
    h.update(typeof data === 'string' ? data : data.toString());
    return h.digest(outputEncoding || 'hex');
  }

  var webcrypto = { subtle: {
    digest: function(algo, data) { return Promise.resolve(crypto.createHash(typeof algo === 'string' ? algo.replace('-','').toLowerCase() : algo.name.replace('-','').toLowerCase()).update(Buffer.from(data)).digest()); },
    encrypt: function() { return Promise.reject(new Error('Not implemented')); },
    decrypt: function() { return Promise.reject(new Error('Not implemented')); },
    sign: function() { return Promise.reject(new Error('Not implemented')); },
    verify: function() { return Promise.reject(new Error('Not implemented')); },
    generateKey: function() { return Promise.reject(new Error('Not implemented')); },
    importKey: function() { return Promise.reject(new Error('Not implemented')); },
    exportKey: function() { return Promise.reject(new Error('Not implemented')); },
    deriveBits: function() { return Promise.reject(new Error('Not implemented')); },
    deriveKey: function() { return Promise.reject(new Error('Not implemented')); },
    wrapKey: function() { return Promise.reject(new Error('Not implemented')); },
    unwrapKey: function() { return Promise.reject(new Error('Not implemented')); }
  }, getRandomValues: function(arr) { return crypto.randomFillSync(arr); }, randomUUID: function() { return crypto.randomUUID(); } };

  return {
    pbkdf2: pbkdf2,
    scrypt: scrypt,
    randomFillSync: randomFillSync,
    randomFill: randomFill,
    constants: constants,
    KeyObject: KeyObject,
    createSecretKey: createSecretKey,
    createPublicKey: createPublicKey,
    createPrivateKey: createPrivateKey,
    X509Certificate: X509Certificate,
    createECDH: createECDH,
    generateKeySync: generateKeySync,
    hkdfSync: hkdfSync,
    hkdf: hkdf,
    generateKey: generateKey,
    generateKeyPair: generateKeyPair,
    getDiffieHellman: getDiffieHellman,
    createDiffieHellmanGroup: createDiffieHellmanGroup,
    diffieHellman: diffieHellman,
    getCurves: getCurves,
    secureHeapUsed: secureHeapUsed,
    setFips: setFips,
    getFips: getFips,
    checkPrime: checkPrime,
    checkPrimeSync: checkPrimeSync,
    generatePrime: generatePrime,
    generatePrimeSync: generatePrimeSync,
    hash: hash,
    webcrypto: webcrypto,
    subtle: webcrypto.subtle
  };
})();`;
}
