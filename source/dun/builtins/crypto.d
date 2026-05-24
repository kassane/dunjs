module dun.builtins.crypto;

/++
 + `@trusted policy`: this file implements Node's `crypto` module
 + surface (createHash, createHmac, randomBytes, createCipheriv,
 + pbkdf2Sync, scryptSync, createSign / createVerify, DH, subtle).
 +
 + Every `@trusted` block in this file falls into one of three
 + categories:
 +
 +   1. OpenSSL FFI call (EVP_*, HMAC_*, PKCS5_PBKDF2_HMAC, etc.).
 +      `@trusted` IS the security signal — these are the audited
 +      entry points to libcrypto/libssl. Annotated `@system` C
 +      bindings live in `dun.platform.openssl`. Each call sits
 +      inside a slot-based RAII pool (`_hashBuffers`, `_hmacBuffers`,
 +      `_cipherCtxs`, …) with free-list recycling.
 +   2. `cast(JSValueRef)` / `.ptr` slice access. The `.ptr` calls
 +      pass byte buffers to OpenSSL's `unsigned char*` parameters;
 +      length is asserted and bounded before each call.
 +   3. `__gshared` cipher / hash slot tables (`_hashFnsCached`,
 +      `_freeHashIds`, …). The append-only / slot-recycle pattern
 +      is single-threaded (matches the engine's main-thread-only
 +      contract).
 +
 + Per-function `///` overrides this baseline when a method has
 + additional invariants (e.g., HMAC key length, scrypt parameter
 + bounds) that aren't captured by the policy above.
 +/

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;

private enum {
    SCRYPT_DEFAULT_N      = 16_384,
    SCRYPT_DEFAULT_R      = 8,
    SCRYPT_DEFAULT_P      = 1,
    SCRYPT_DEFAULT_MAXMEM = 32 * 1024 * 1024,
    SCRYPT_MAX_KEYLEN     = 1024,

    // WebCrypto subtle constants
    SUBTLE_MAX_DIGEST_SIZE = 64,  // SHA-512 = 64 bytes
    SUBTLE_HMAC_MAX_KEY    = 1024,
    SUBTLE_AES_BLOCK_SIZE  = 16,
    SUBTLE_AES_GCM_IV_LEN = 12,
    SUBTLE_AES_GCM_TAG_LEN = 16,
    SUBTLE_AES_CBC_IV_LEN  = 16,
    // AES key sizes in bytes (AES-128 / AES-192 / AES-256).
    AES128_KEY_BYTES = 16,
    AES192_KEY_BYTES = 24,
    AES256_KEY_BYTES = 32,
    SUBTLE_MAX_DATA_SIZE   = 64 * 1024 * 1024,  // 64 MiB max input
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
    const(EVP_MD)* EVP_sha3_256();
    const(EVP_MD)* EVP_sha3_384();
    const(EVP_MD)* EVP_sha3_512();
    const(EVP_MD)* EVP_ripemd160();
    const(EVP_MD)* EVP_blake2s256();
    const(EVP_MD)* EVP_blake2b512();
    const(EVP_MD)* EVP_md_null();
    const(EVP_MD)* EVP_get_digestbyname(const(char)* name);

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

    // One-shot digest (for WebCrypto subtle.digest)
    int EVP_Digest(const(void)* data, size_t count, ubyte* md, uint* size,
                   const(EVP_MD)* type, void* impl);
    int EVP_MD_get_size(const(EVP_MD)* md);

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
    const(EVP_CIPHER)* EVP_aes_192_gcm();
    const(EVP_CIPHER)* EVP_aes_256_gcm();
    const(EVP_CIPHER)* EVP_aes_128_ctr();
    const(EVP_CIPHER)* EVP_aes_192_ctr();
    const(EVP_CIPHER)* EVP_aes_256_ctr();
    const(EVP_CIPHER)* EVP_aes_128_ecb();
    const(EVP_CIPHER)* EVP_aes_192_ecb();
    const(EVP_CIPHER)* EVP_aes_256_ecb();
    const(EVP_CIPHER)* EVP_aes_128_ofb();
    const(EVP_CIPHER)* EVP_aes_192_ofb();
    const(EVP_CIPHER)* EVP_aes_256_ofb();
    const(EVP_CIPHER)* EVP_aes_128_cfb128();
    const(EVP_CIPHER)* EVP_aes_192_cfb128();
    const(EVP_CIPHER)* EVP_aes_256_cfb128();
    const(EVP_CIPHER)* EVP_des_ede3_cbc();
    const(EVP_CIPHER)* EVP_des_ede3();
    const(EVP_CIPHER)* EVP_chacha20_poly1305();
    const(EVP_CIPHER)* EVP_rc4();

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
    if (algo == "sha3-256") return EVP_sha3_256();
    if (algo == "sha3-384") return EVP_sha3_384();
    if (algo == "sha3-512") return EVP_sha3_512();
    if (algo == "ripemd160") return EVP_ripemd160();
    if (algo == "blake2s256") return EVP_blake2s256();
    if (algo == "blake2b512") return EVP_blake2b512();
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
    if (lower == "sha3-256") return "sha3-256";
    if (lower == "sha3-384") return "sha3-384";
    if (lower == "sha3-512") return "sha3-512";
    if (lower == "ripemd160") return "ripemd160";
    if (lower == "blake2s256") return "blake2s256";
    if (lower == "blake2b512") return "blake2b512";
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
                        "generatePrimeSync", "hash", "webcrypto", "subtle",
                        "getRandomValues"])
        {
            auto prop = engine.getProperty(cryptoExtResult.value, name);
            engine.setProperty(obj, name, prop);
        }
    }
    engine.freeValue(cryptoExtResult.value);

    installNativeSubtle(engine, obj);

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
        auto m = JS_NewCModule(ctx, "dun:crypto", &cryptoModuleInit);
        if (m is null) return;
        foreach (name; cryptoExportNames)
            JS_AddModuleExport(ctx, m, name.ptr);

    JS_AddModuleExport(ctx, m, "default");
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
        "generatePrime", "generatePrimeSync", "hash", "webcrypto", "subtle",
        "getRandomValues"
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
        JS_SetModuleExport(ctx, m, "default", cryptoObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

// Public API for cross-module access (used by dun.runtime.web_apis)
JSHandle jsCryptoRandomUUID(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsCryptoRandomBytes(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import core.stdc.stdlib : malloc, free;

    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoRandomBytes");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("randomBytes requires a length argument");
    int n = engine.extractInt(args[0]);
    if (n < 0) return engine.throwTypeError("randomBytes length must be non-negative");
    import dun.builtins.buffer : makeBufferObj;
    enum STACK_LIMIT = 256;
    ubyte[STACK_LIMIT] stackBuf = void;
    if (n <= STACK_LIMIT)
    {
        auto buf = stackBuf[0 .. n];
        fillRandomBytes(buf);
        return makeBufferObj(engine, buf);
    }
    auto buf = cast(ubyte*) malloc(n);
    if (buf is null) return engine.throwTypeError("Failed to allocate random bytes buffer");
    scope(exit) free(buf);
    fillRandomBytes(buf[0 .. n]);
    return makeBufferObj(engine, buf[0 .. n]);
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
private __gshared int[] _freeHashIds;
private __gshared bool _hashFnsCached = false;

// D-side buffer registry for binary-safe hash accumulation
private __gshared ubyte[][int] _hashBuffers;
private __gshared int _nextHashId = 0;
enum MAX_HASH_SLOTS = 32_767;

JSHandle jsCryptoCreateHash(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoCreateHash");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("createHash requires an algorithm argument");
    auto algo = engine.extractString(args[0]);

    if (!_hashFnsCached)
    {
        _cachedUpdateFn = engine.newFunction(&jsHashUpdate, "update", 1);
        _cachedDigestFn = engine.newFunction(&jsHashDigest, "digest", 1);
        _hashFnsCached = true;
    }

    int id;
    if (_freeHashIds.length > 0)
    {
        id = _freeHashIds[$ - 1];
        _freeHashIds = _freeHashIds[0 .. $ - 1];
    }
    else
    {
        id = _nextHashId++;
        assert(_nextHashId < MAX_HASH_SLOTS, "Hash slot overflow");
    }
    _hashBuffers[id] = [];

    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_hid", engine.newInt(id));
    // bindMethod: shared cached fn → property without per-call dup leak (JSC)
    engine.bindMethod(obj, "update", _cachedUpdateFn);
    engine.bindMethod(obj, "digest", _cachedDigestFn);
    return obj;
}

JSHandle jsHashUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsHashUpdate");
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);
    try
    {
        auto hidProp = engine.getProperty(thisVal, "_hid");
        int hid = engine.extractInt(hidProp);
        engine.freeValue(hidProp);

        ubyte[] chunk;
        // Check if arg is a Buffer (has __u8 Uint8Array)
        if (engine.isObject(args[0]))
        {
            auto isBuf = engine.getProperty(args[0], "__isBuffer");
            bool isBuffer = engine.isBool(isBuf) && engine.extractBool(isBuf);
            engine.freeValue(isBuf);
            if (isBuffer)
            {
                import dun.builtins.buffer : extractBytes;
                chunk = extractBytes(engine, args[0]).dup;
            }
            else
            {
                // Try as Uint8Array
                auto u8 = engine.extractString(args[0]);
                chunk = cast(ubyte[]) u8.dup;
            }
        }
        else
        {
            auto str = engine.extractString(args[0]);
            chunk = cast(ubyte[]) str.dup;
        }

        if (auto p = hid in _hashBuffers)
            *p ~= chunk;
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsHashDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsHashDigest");
    auto engine = state.engine;
    try
    {
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);

        auto hidProp = engine.getProperty(thisVal, "_hid");
        int hid = engine.extractInt(hidProp);
        engine.freeValue(hidProp);

        ubyte[] data;
        if (auto p = hid in _hashBuffers)
        {
            data = *p;
            _hashBuffers.remove(hid);
            _freeHashIds ~= hid;  // recycle for future createHash calls
        }

        string encoding = "hex";
        if (args.length >= 1 && engine.isString(args[0]))
            encoding = engine.extractString(args[0]);

        auto result = computeHashBinary(algo, data);
        if (encoding == "hex")
            return engine.newString(bytesToHexStr(result));
        else if (encoding == "base64")
        {
            import std.base64 : Base64;
            return engine.newString((() @trusted => cast(string) Base64.encode(result))());
        }
        else if (encoding == "base64url")
            return engine.newString(bytesToBase64Url(result));
        else if (encoding == "buffer" || encoding == "binary")
        {
            import dun.builtins.buffer : makeBufferObj;
            return makeBufferObj(engine, result);
        }
        return engine.newString(bytesToHexStr(result));
    }
    catch (Exception) { return engine.throwTypeError("Failed to compute hash"); }
}

// --- createHmac ---

private __gshared JSHandle _cachedHmacUpdateFn;
private __gshared JSHandle _cachedHmacDigestFn;
private __gshared bool _hmacFnsCached = false;

// D-side buffer registry for binary-safe HMAC accumulation
private __gshared ubyte[][int] _hmacBuffers;
private __gshared ubyte[][int] _hmacKeys;
private __gshared int _nextHmacId = 0;
private __gshared int[] _freeHmacIds;

JSHandle jsCryptoCreateHmac(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoCreateHmac");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("createHmac requires algorithm and key arguments");
    auto algo = engine.extractString(args[0]);
    if (getEvpMd(algo) is null)
        return engine.throwTypeError("Unsupported HMAC algorithm: " ~ algo);

    if (!_hmacFnsCached)
    {
        _cachedHmacUpdateFn = engine.newFunction(&jsHmacUpdate, "update", 1);
        _cachedHmacDigestFn = engine.newFunction(&jsHmacDigest, "digest", 1);
        _hmacFnsCached = true;
    }

    // Extract key as binary. Supports:
    //  - string ("secretA")
    //  - Buffer (has __isBuffer flag)
    //  - KeyObject (jsonwebtoken / jws pass these: `{type:'secret', _data:Buffer}`)
    //    -- previously fell through to `extractString` which yielded
    //    "[object Object]", silently signing every JWT with a constant
    //    "key", breaking jws.verify on round-trips.
    ubyte[] keyBytes;
    if (engine.isObject(args[1]))
    {
        auto isBuf = engine.getProperty(args[1], "__isBuffer");
        bool isBuffer = engine.isBool(isBuf) && engine.extractBool(isBuf);
        engine.freeValue(isBuf);
        if (isBuffer)
        {
            import dun.builtins.buffer : extractBytes;
            keyBytes = extractBytes(engine, args[1]).dup;
        }
        else
        {
            // KeyObject: unwrap `._data` (a Buffer).
            auto data = engine.getProperty(args[1], "_data");
            scope (exit) engine.freeValue(data);
            if (engine.isObject(data))
            {
                auto dIsBuf = engine.getProperty(data, "__isBuffer");
                bool dataIsBuffer = engine.isBool(dIsBuf) && engine.extractBool(dIsBuf);
                engine.freeValue(dIsBuf);
                if (dataIsBuffer)
                {
                    import dun.builtins.buffer : extractBytes;
                    keyBytes = extractBytes(engine, data).dup;
                }
                else
                    keyBytes = cast(ubyte[]) engine.extractString(args[1]).dup;
            }
            else
                keyBytes = cast(ubyte[]) engine.extractString(args[1]).dup;
        }
    }
    else
        keyBytes = cast(ubyte[]) engine.extractString(args[1]).dup;

    int id;
    if (_freeHmacIds.length > 0)
    {
        id = _freeHmacIds[$ - 1];
        _freeHmacIds = _freeHmacIds[0 .. $ - 1];
    }
    else
    {
        id = _nextHmacId++;
        assert(_nextHmacId < MAX_HASH_SLOTS, "HMAC slot overflow");
    }
    _hmacBuffers[id] = [];
    _hmacKeys[id] = keyBytes;

    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_hid", engine.newInt(id));
    engine.bindMethod(obj, "update", _cachedHmacUpdateFn);
    engine.bindMethod(obj, "digest", _cachedHmacDigestFn);
    return obj;
}

JSHandle jsHmacUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsHmacUpdate");
    auto engine = state.engine;
    if (args.length < 1) return engine.dupValue(thisVal);
    try
    {
        auto hidProp = engine.getProperty(thisVal, "_hid");
        int hid = engine.extractInt(hidProp);
        engine.freeValue(hidProp);

        ubyte[] chunk;
        if (engine.isObject(args[0]))
        {
            auto isBuf = engine.getProperty(args[0], "__isBuffer");
            bool isBuffer = engine.isBool(isBuf) && engine.extractBool(isBuf);
            engine.freeValue(isBuf);
            if (isBuffer)
            {
                import dun.builtins.buffer : extractBytes;
                chunk = extractBytes(engine, args[0]).dup;
            }
            else
                chunk = cast(ubyte[]) engine.extractString(args[0]).dup;
        }
        else
            chunk = cast(ubyte[]) engine.extractString(args[0]).dup;

        if (auto p = hid in _hmacBuffers)
            *p ~= chunk;
    }
    catch (Exception) {}
    return engine.dupValue(thisVal);
}

JSHandle jsHmacDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsHmacDigest");
    auto engine = state.engine;
    try
    {
        auto algoProp = engine.getProperty(thisVal, "_algo");
        auto algo = engine.extractString(algoProp);
        engine.freeValue(algoProp);
        auto hidProp = engine.getProperty(thisVal, "_hid");
        int hid = engine.extractInt(hidProp);
        engine.freeValue(hidProp);

        ubyte[] data;
        bool recycled = false;
        if (auto p = hid in _hmacBuffers)
        {
            data = *p;
            _hmacBuffers.remove(hid);
            recycled = true;
        }
        ubyte[] key;
        if (auto p = hid in _hmacKeys)
        {
            key = *p;
            _hmacKeys.remove(hid);
        }
        if (recycled) _freeHmacIds ~= hid;

        string encoding = "hex";
        if (args.length >= 1 && engine.isString(args[0]))
            encoding = engine.extractString(args[0]);

        auto result = computeHmacBinary(algo, key, data);
        if (encoding == "hex")
            return engine.newString(bytesToHexStr(result));
        else if (encoding == "base64")
        {
            import std.base64 : Base64;
            return engine.newString((() @trusted => cast(string) Base64.encode(result))());
        }
        else if (encoding == "base64url")
            return engine.newString(bytesToBase64Url(result));
        else if (encoding == "buffer" || encoding == "binary")
        {
            import dun.builtins.buffer : makeBufferObj;
            return makeBufferObj(engine, result);
        }
        return engine.newString(bytesToHexStr(result));
    }
    catch (Exception) { return engine.throwTypeError("Failed to compute HMAC"); }
}

// --- timingSafeEqual ---

JSHandle jsCryptoTimingSafeEqual(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoTimingSafeEqual");
    auto engine = state.engine;
    if (args.length < 2)
        return engine.throwTypeError("timingSafeEqual requires two arguments");
    try
    {
        const(ubyte)[] a = extractArgBytes(engine, args[0]);
        const(ubyte)[] b = extractArgBytes(engine, args[1]);
        if (a.length != b.length)
            return engine.throwTypeError("Input buffers must have the same byte length");
        if (a.length == 0)
            return engine.newBool(true);
        int result = CRYPTO_memcmp(cast(const(void)*) a.ptr, cast(const(void)*) b.ptr, a.length);
        return engine.newBool(result == 0);
    }
    catch (Exception) { return engine.throwTypeError("timingSafeEqual failed"); }
}

private const(ubyte)[] extractArgBytes(IJSEngine engine, JSHandle arg) @trusted
{
    if (engine.isObject(arg))
    {
        auto isBuf = engine.getProperty(arg, "__isBuffer");
        bool isBuffer = engine.isBool(isBuf) && engine.extractBool(isBuf);
        engine.freeValue(isBuf);
        if (isBuffer)
        {
            import dun.builtins.buffer : extractBytes;
            return extractBytes(engine, arg);
        }
        auto bytes = engine.getTypedArrayBytes(arg);
        if (bytes !is null)
            return bytes;
    }
    return cast(const(ubyte)[]) engine.extractString(arg);
}

// --- randomInt ---

JSHandle jsCryptoRandomInt(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsCryptoPbkdf2Sync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, outbuf);
    }
    catch (Exception) { return engine.throwTypeError("pbkdf2Sync failed"); }
}

// --- scryptSync ---

JSHandle jsCryptoScryptSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, outbuf);
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
    if (algo == "aes-192-gcm") return EVP_aes_192_gcm();
    if (algo == "aes-256-gcm") return EVP_aes_256_gcm();
    if (algo == "aes-128-ctr") return EVP_aes_128_ctr();
    if (algo == "aes-192-ctr") return EVP_aes_192_ctr();
    if (algo == "aes-256-ctr") return EVP_aes_256_ctr();
    if (algo == "aes-128-ecb") return EVP_aes_128_ecb();
    if (algo == "aes-192-ecb") return EVP_aes_192_ecb();
    if (algo == "aes-256-ecb") return EVP_aes_256_ecb();
    if (algo == "aes-128-ofb") return EVP_aes_128_ofb();
    if (algo == "aes-192-ofb") return EVP_aes_192_ofb();
    if (algo == "aes-256-ofb") return EVP_aes_256_ofb();
    if (algo == "aes-128-cfb") return EVP_aes_128_cfb128();
    if (algo == "aes-192-cfb") return EVP_aes_192_cfb128();
    if (algo == "aes-256-cfb") return EVP_aes_256_cfb128();
    if (algo == "des-ede3-cbc" || algo == "des3") return EVP_des_ede3_cbc();
    if (algo == "des-ede3") return EVP_des_ede3();
    if (algo == "chacha20-poly1305") return EVP_chacha20_poly1305();
    if (algo == "rc4") return EVP_rc4();
    return null;
}

private bool isGcmCipher(string algo) @safe pure nothrow
{
    return algo == "aes-128-gcm" || algo == "aes-192-gcm" || algo == "aes-256-gcm"
        || algo == "chacha20-poly1305";
}

private bool isEcbCipher(string algo) @safe pure nothrow
{
    return algo == "aes-128-ecb" || algo == "aes-192-ecb" || algo == "aes-256-ecb";
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

JSHandle jsCryptoCreateCipheriv(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("createCipheriv requires algorithm, key, iv");
    auto algo = engine.extractString(args[0]);
    auto cipher = getEvpCipher(algo);
    if (cipher is null)
        return engine.throwTypeError("Unsupported cipher: " ~ algo);

    auto keyBytes = extractCryptoBytes(engine, args[1]);
    if (keyBytes is null)
        return engine.throwTypeError("Invalid key");

    ubyte[] ivBytes;
    bool ecb = isEcbCipher(algo);
    if (!ecb)
    {
        if (engine.isNull(args[2]) || engine.isUndefined(args[2]))
            return engine.throwTypeError("Invalid iv");
        ivBytes = extractCryptoBytes(engine, args[2]);
        if (ivBytes is null)
            return engine.throwTypeError("Invalid iv");
    }

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return engine.throwTypeError("Failed to create cipher context");

    if (EVP_EncryptInit_ex(evpCtx, cipher, null,
        cast(const(ubyte)*) keyBytes.ptr,
        ecb ? null : cast(const(ubyte)*) ivBytes.ptr) != 1)
    {
        EVP_CIPHER_CTX_free(evpCtx);
        return engine.throwTypeError("Failed to initialize cipher");
    }

    ensureCipherFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_evpCtx", engine.newFloat(cast(double) cast(size_t) evpCtx));
    engine.bindMethod(obj, "update", _cachedCipherUpdateFn);
    engine.bindMethod(obj, "final", _cachedCipherFinalFn);
    if (isGcmCipher(algo))
        engine.bindMethod(obj, "getAuthTag", _cachedCipherGetAuthTagFn);
    return obj;
}

JSHandle jsCipherUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 1) return engine.newString("");

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Cipher already finalized");

    try
    {
        // Get input encoding (arg[1]) and output encoding (arg[2])
        string outputEnc = "buffer";
        if (args.length >= 3)
            outputEnc = engine.extractString(args[2]);

        // Extract input bytes - handle Buffer, hex, or utf8
        const(ubyte)[] inputBytes;
        string inputStr;
        ubyte[] decodedBuf;
        if (engine.isObject(args[0]) && !engine.isString(args[0]))
        {
            import dun.builtins.buffer : extractBytes;
            auto bufBytes = extractBytes(engine, args[0]);
            inputBytes = cast(const(ubyte)[]) bufBytes;
        }
        else if (args.length >= 2)
        {
            auto inputEnc = engine.extractString(args[1]);
            if (inputEnc == "hex")
            {
                auto hexStr = engine.extractString(args[0]);
                decodedBuf = hexDecode(hexStr);
                inputBytes = cast(const(ubyte)[]) decodedBuf;
            }
            else if (inputEnc == "base64")
            {
                import std.base64 : Base64;
                inputStr = engine.extractString(args[0]);
                decodedBuf = Base64.decode(inputStr);
                inputBytes = cast(const(ubyte)[]) decodedBuf;
            }
            else
            {
                inputStr = engine.extractString(args[0]);
                inputBytes = cast(const(ubyte)[]) inputStr;
            }
        }
        else
        {
            inputStr = engine.extractString(args[0]);
            inputBytes = cast(const(ubyte)[]) inputStr;
        }

        auto outbuf = new ubyte[inputBytes.length + 32];
        int outlen = 0;
        if (EVP_EncryptUpdate(evpCtx, outbuf.ptr, &outlen,
            inputBytes.ptr, cast(int) inputBytes.length) != 1)
            return engine.throwTypeError("Cipher update failed");

        if (outputEnc == "hex")
        {
            /* SIMD path: hexEncode does a single GC allocation +
               16-byte/cycle interleave (LDC). Was `toHexString` from
               std.digest, which is a serial bit-twiddling loop on a
               GC-allocated char[]. */
            import dun.platform.simd : hexEncode;
            return engine.newString(cast(const(char)[])
                hexEncode(outbuf[0 .. outlen]));
        }
        else if (outputEnc == "base64")
        {
            import std.base64 : Base64;
            return engine.newString(Base64.encode(outbuf[0 .. outlen]));
        }
        else
        {
            import dun.builtins.buffer : makeBufferObj;
            return makeBufferObj(engine, outbuf[0 .. outlen]);
        }
    }
    catch (Exception) { return engine.throwTypeError("Cipher update failed"); }
}

JSHandle jsCipherFinal(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Cipher already finalized");

    string outputEnc = "buffer";
    if (args.length >= 1)
        outputEnc = engine.extractString(args[0]);

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
        /* GCM tag is always 16 bytes — use the CTFE-sized SIMD encoder
           (`hexEncodeFixed!16`) so the destination lives on the stack,
           zero GC allocation. `newString` copies the slice into engine
           storage before this frame unwinds. */
        import dun.platform.simd : hexEncodeFixed;
        auto hex = hexEncodeFixed(tag);
        engine.setProperty(thisVal, "_authTag", engine.newString(
            cast(const(char)[]) hex[]));
    }

    EVP_CIPHER_CTX_free(evpCtx);
    engine.setProperty(thisVal, "_evpCtx", engine.newFloat(0));

    if (rc != 1)
        return engine.throwTypeError("Cipher final failed");

    if (outputEnc == "hex")
    {
        import dun.platform.simd : hexEncode;
        return engine.newString(cast(const(char)[])
            hexEncode(outbuf[0 .. outlen]));
    }
    else if (outputEnc == "base64")
    {
        import std.base64 : Base64;
        return engine.newString(Base64.encode(outbuf[0 .. outlen]));
    }
    else
    {
        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, outbuf[0 .. outlen]);
    }
}

JSHandle jsCipherGetAuthTag(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsCryptoCreateDecipheriv(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 3)
        return engine.throwTypeError("createDecipheriv requires algorithm, key, iv");
    auto algo = engine.extractString(args[0]);
    auto cipher = getEvpCipher(algo);
    if (cipher is null)
        return engine.throwTypeError("Unsupported cipher: " ~ algo);

    auto keyBytes = extractCryptoBytes(engine, args[1]);
    if (keyBytes is null)
        return engine.throwTypeError("Invalid key");

    ubyte[] ivBytes;
    bool ecb = isEcbCipher(algo);
    if (!ecb)
    {
        if (engine.isNull(args[2]) || engine.isUndefined(args[2]))
            return engine.throwTypeError("Invalid iv");
        ivBytes = extractCryptoBytes(engine, args[2]);
        if (ivBytes is null)
            return engine.throwTypeError("Invalid iv");
    }

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return engine.throwTypeError("Failed to create decipher context");

    if (EVP_DecryptInit_ex(evpCtx, cipher, null,
        cast(const(ubyte)*) keyBytes.ptr,
        ecb ? null : cast(const(ubyte)*) ivBytes.ptr) != 1)
    {
        EVP_CIPHER_CTX_free(evpCtx);
        return engine.throwTypeError("Failed to initialize decipher");
    }

    ensureCipherFnsCached(engine);
    auto obj = engine.newObject();
    engine.setProperty(obj, "_algo", engine.newString(algo));
    engine.setProperty(obj, "_evpCtx", engine.newFloat(cast(double) cast(size_t) evpCtx));
    engine.bindMethod(obj, "update", _cachedDecipherUpdateFn);
    engine.bindMethod(obj, "final", _cachedDecipherFinalFn);
    if (isGcmCipher(algo))
        engine.bindMethod(obj, "setAuthTag", _cachedDecipherSetAuthTagFn);
    return obj;
}

JSHandle jsDecipherUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 1) return engine.newString("");

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Decipher already finalized");

    try
    {
        string inputEnc = "buffer";
        string outputEnc = "buffer";
        if (args.length >= 2)
            inputEnc = engine.extractString(args[1]);
        if (args.length >= 3)
            outputEnc = engine.extractString(args[2]);

        const(ubyte)[] inBytes;
        ubyte[] decodedBuf;
        string rawInput;
        if (inputEnc == "hex")
        {
            rawInput = engine.extractString(args[0]);
            decodedBuf = hexDecode(rawInput);
            inBytes = decodedBuf;
        }
        else if (inputEnc == "base64")
        {
            import std.base64 : Base64;
            rawInput = engine.extractString(args[0]);
            decodedBuf = Base64.decode(rawInput);
            inBytes = decodedBuf;
        }
        else
        {
            rawInput = engine.extractString(args[0]);
            inBytes = cast(const(ubyte)[]) rawInput;
        }

        auto outbuf = new ubyte[inBytes.length + 32];
        int outlen = 0;
        if (EVP_DecryptUpdate(evpCtx, outbuf.ptr, &outlen,
            inBytes.ptr, cast(int) inBytes.length) != 1)
            return engine.throwTypeError("Decipher update failed");

        if (outputEnc == "utf8" || outputEnc == "utf-8")
            return engine.newString(cast(const(char)[]) outbuf[0 .. outlen]);
        else if (outputEnc == "hex")
        {
            import dun.platform.simd : hexEncode;
            return engine.newString(cast(const(char)[])
                hexEncode(outbuf[0 .. outlen]));
        }
        else if (outputEnc == "base64")
        {
            import std.base64 : Base64;
            return engine.newString(Base64.encode(outbuf[0 .. outlen]));
        }
        else
        {
            import dun.builtins.buffer : makeBufferObj;
            return makeBufferObj(engine, outbuf[0 .. outlen]);
        }
    }
    catch (Exception) { return engine.throwTypeError("Decipher update failed"); }
}

JSHandle jsDecipherFinal(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;

    auto ctxProp = engine.getProperty(thisVal, "_evpCtx");
    auto evpCtx = cast(EVP_CIPHER_CTX*) cast(size_t) engine.extractFloat(ctxProp);
    engine.freeValue(ctxProp);
    if (evpCtx is null) return engine.throwTypeError("Decipher already finalized");

    string outputEnc = "buffer";
    if (args.length >= 1)
        outputEnc = engine.extractString(args[0]);

    ubyte[32] outbuf;
    int outlen = 0;
    auto rc = EVP_DecryptFinal_ex(evpCtx, outbuf.ptr, &outlen);
    EVP_CIPHER_CTX_free(evpCtx);
    engine.setProperty(thisVal, "_evpCtx", engine.newFloat(0));

    if (rc != 1)
        return engine.throwTypeError("Decipher final failed (bad padding or auth tag)");

    if (outputEnc == "utf8" || outputEnc == "utf-8")
        return engine.newString(cast(const(char)[]) outbuf[0 .. outlen]);
    else if (outputEnc == "hex")
    {
        import dun.platform.simd : hexEncode;
        return engine.newString(cast(const(char)[])
            hexEncode(outbuf[0 .. outlen]));
    }
    else if (outputEnc == "base64")
    {
        import std.base64 : Base64;
        return engine.newString(Base64.encode(outbuf[0 .. outlen]));
    }
    else
    {
        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, outbuf[0 .. outlen]);
    }
}

JSHandle jsDecipherSetAuthTag(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

private ubyte[] hexDecode(string hex) @safe pure nothrow
{
    if (hex.length % 2 != 0) return null;
    auto result = new ubyte[hex.length / 2];
    foreach (i; 0 .. result.length)
        result[i] = cast(ubyte)(hexVal(hex[i * 2]) << 4 | hexVal(hex[i * 2 + 1]));
    return result;
}

private ubyte[] extractCryptoBytes(IJSEngine engine, JSHandle arg) @trusted
{
    if (engine.isString(arg))
    {
        auto s = engine.extractString(arg);
        return cast(ubyte[]) s.dup;
    }
    if (engine.isObject(arg))
    {
        // Try as raw typed array first
        auto directBytes = engine.getTypedArrayBytes(arg);
        if (directBytes !is null) return directBytes;
        // Try as Buffer (has __u8 property)
        import dun.builtins.buffer : extractBytes;
        auto bytes = extractBytes(engine, arg);
        if (bytes !is null) return bytes;
    }
    return null;
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

JSHandle jsCryptoCreateSign(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
    engine.bindMethod(obj, "update", _cachedSignUpdateFn);
    engine.bindMethod(obj, "sign", _cachedSignSignFn);
    return obj;
}

JSHandle jsSignUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsSignSign(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsCryptoCreateVerify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
    engine.bindMethod(obj, "update", _cachedVerifyUpdateFn);
    engine.bindMethod(obj, "verify", _cachedVerifyVerifyFn);
    return obj;
}

JSHandle jsVerifyUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

JSHandle jsVerifyVerify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
        import dun.platform.simd : hexEncode;
        return engine.newString(cast(const(char)[]) hexEncode(data));
    }
    else if (encoding == "base64")
    {
        import std.base64 : Base64;
        return engine.newString(Base64.encode(data));
    }
    else if (encoding == "base64url")
        return engine.newString(bytesToBase64Url(data));
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
    else if (encoding == "base64url")
    {
        // Pad to mod-4 then map `-`/`_` -> `+`/`/` so std.base64 accepts it.
        import std.base64 : Base64;
        import dun.platform.arena : Appender;
        Appender!(char[]) buf;
        buf.reserve(input.length + 4);
        foreach (c; input)
        {
            if (c == '-') buf ~= '+';
            else if (c == '_') buf ~= '/';
            else buf ~= c;
        }
        while (buf[].length % 4 != 0) buf ~= '=';
        try { return Base64.decode(buf[]); }
        catch (Exception) { return null; }
    }
    else // "buffer" — raw bytes
    {
        return cast(ubyte[]) input.dup;
    }
}

// --- getHashes / getCiphers ---

JSHandle jsCryptoGetHashes(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoGetHashes");
    auto engine = state.engine;
    auto arr = engine.newArray();
    uint idx = 0;
    foreach (name; ["blake2b512", "blake2s256", "md5", "ripemd160",
                    "sha1", "sha224", "sha256", "sha384", "sha512",
                    "sha3-256", "sha3-384", "sha3-512"])
        engine.setPropertyIndex(arr, idx++, engine.newString(name));
    return arr;
}

JSHandle jsCryptoGetCiphers(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsCryptoGetCiphers");
    auto engine = state.engine;
    auto arr = engine.newArray();
    uint idx = 0;
    foreach (name; ["aes-128-cbc", "aes-192-cbc", "aes-256-cbc",
                    "aes-128-ctr", "aes-192-ctr", "aes-256-ctr",
                    "aes-128-ecb", "aes-192-ecb", "aes-256-ecb",
                    "aes-128-gcm", "aes-192-gcm", "aes-256-gcm",
                    "aes-128-ofb", "aes-192-ofb", "aes-256-ofb",
                    "aes-128-cfb", "aes-192-cfb", "aes-256-cfb",
                    "chacha20-poly1305",
                    "des-ede3-cbc", "des-ede3", "des3", "rc4"])
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
        // BCRYPT_USE_SYSTEM_PREFERRED_RNG — pulls from the system's
        // default RNG (CNG SP800-90 AES_CTR_DRBG on Win10+), avoiding
        // the algorithm-handle path. See Microsoft docs:
        // https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom
        enum ULONG BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002;
        auto buf = new ubyte[n];
        BCryptGenRandom(null, buf.ptr, cast(ULONG) n, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
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

private ubyte[] computeHashBinary(string algo, const(ubyte)[] data) @trusted
{
    auto md = getEvpMd(algo);
    if (md !is null)
    {
        ubyte[64] outBuf;
        uint outLen = 0;
        auto result = EVP_Digest(data.ptr, data.length, outBuf.ptr, &outLen, md, null);
        if (result == 1 && outLen > 0)
            return outBuf[0 .. outLen].dup;
    }
    // Fallback to std.digest for basic algorithms
    switch (algo)
    {
        case "md5": { import std.digest.md : MD5, digest; auto r = digest!MD5(data); return (cast(ubyte[]) r[]).dup; }
        case "sha1": { import std.digest.sha : SHA1, digest; auto r = digest!SHA1(data); return (cast(ubyte[]) r[]).dup; }
        case "sha256": { import std.digest.sha : SHA256, digest; auto r = digest!SHA256(data); return (cast(ubyte[]) r[]).dup; }
        case "sha384": { import std.digest.sha : SHA384, digest; auto r = digest!SHA384(data); return (cast(ubyte[]) r[]).dup; }
        case "sha512": { import std.digest.sha : SHA512, digest; auto r = digest!SHA512(data); return (cast(ubyte[]) r[]).dup; }
        default: return [];
    }
}

// Delegates to the SIMD-backed `buffer.bytesToHex` (16 bytes →
// 32 hex chars/cycle) instead of a scalar `HEX_LOWER` loop — the
// two were functionally identical, so this drops the duplicate.
private string bytesToHexStr(const(ubyte)[] data) @trusted nothrow
{
    import dun.builtins.buffer : bytesToHex;
    return bytesToHex(data);
}

/++
 + Encode raw bytes as base64url (RFC 7515 §2: `-`/`_` alphabet, no
 + padding). Used by digest / HMAC / cipher output paths when the
 + caller asks for `"base64url"`. Without this, the fallback path
 + returns hex, which silently corrupts JWT / WebPush / similar flows.
 +/
private string bytesToBase64Url(const(ubyte)[] data) @safe pure
{
    if (data.length == 0) return "";
    import std.base64 : Base64URLNoPadding;
    return (() @trusted => cast(string) Base64URLNoPadding.encode(data))();
}

private ubyte[] computeHmacBinary(string algo, const(ubyte)[] key, const(ubyte)[] data) @trusted
{
    auto md = getEvpMd(algo);
    if (md is null) return [];

    ubyte[64] outBuf;
    uint outLen = 0;

    auto result = HMAC(md,
        cast(const(void)*) key.ptr, cast(int) key.length,
        data.ptr, data.length,
        outBuf.ptr, &outLen);

    if (result is null || outLen == 0) return [];
    return outBuf[0 .. outLen].dup;
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

JSHandle jsCryptoGenerateKeyPairSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
        import dun.platform.simd : hexEncode;
        return cast(string) hexEncode(buf);
    }
    catch (Exception) { return ""; }
}

JSHandle jsCryptoCreateDiffieHellman(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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
    engine.bindMethod(obj, "generateKeys", _cachedDHGenerateKeysFn);
    engine.bindMethod(obj, "getPublicKey", _cachedDHGetPublicKeyFn);
    engine.bindMethod(obj, "getPrivateKey", _cachedDHGetPrivateKeyFn);
    engine.bindMethod(obj, "computeSecret", _cachedDHComputeSecretFn);
    engine.bindMethod(obj, "getPrime", _cachedDHGetPrimeFn);
    engine.bindMethod(obj, "getGenerator", _cachedDHGetGeneratorFn);
    return obj;
}

private DH* extractDH(IJSEngine engine, JSHandle thisVal) @trusted
{
    auto dhProp = engine.getProperty(thisVal, "_dh");
    auto dh = cast(DH*) cast(size_t) engine.extractFloat(dhProp);
    engine.freeValue(dhProp);
    return dh;
}

JSHandle jsDHGenerateKeys(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    if (DH_generate_key(dh) != 1)
        return engine.throwTypeError("Failed to generate DH key");

    // Return public key as hex by default
    auto pubKey = DH_get0_pub_key(dh);
    return engine.newString(bnToHex(pubKey));
}

JSHandle jsDHGetPublicKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto pubKey = DH_get0_pub_key(dh);
    if (pubKey is null) return engine.throwTypeError("Keys not yet generated");
    return engine.newString(bnToHex(pubKey));
}

JSHandle jsDHGetPrivateKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto privKey = DH_get0_priv_key(dh);
    if (privKey is null) return engine.throwTypeError("Keys not yet generated");
    return engine.newString(bnToHex(privKey));
}

JSHandle jsDHComputeSecret(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
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

    import dun.platform.simd : hexEncode;
    try { return engine.newString(cast(const(char)[]) hexEncode(secret[0 .. n])); }
    catch (Exception) { return engine.throwTypeError("Failed to encode secret"); }
}

JSHandle jsDHGetPrime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto p = DH_get0_p(dh);
    if (p is null) return engine.throwTypeError("No prime available");
    return engine.newString(bnToHex(p));
}

JSHandle jsDHGetGenerator(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto dh = extractDH(engine, thisVal);
    if (dh is null) return engine.throwTypeError("Invalid DH object");

    auto g = DH_get0_g(dh);
    if (g is null) return engine.throwTypeError("No generator available");
    return engine.newString(bnToHex(g));
}

// ═══════════════════════════════════════════════════
// WebCrypto subtle — native implementations (OpenSSL)
// ═══════════════════════════════════════════════════

private __gshared JSHandle _cachedSubtleDigestFn;
private __gshared JSHandle _cachedSubtleImportKeyFn;
private __gshared JSHandle _cachedSubtleSignFn;
private __gshared JSHandle _cachedSubtleVerifyFn;
private __gshared JSHandle _cachedSubtleEncryptFn;
private __gshared JSHandle _cachedSubtleDecryptFn;
private __gshared JSHandle _cachedSubtleGenerateKeyFn;
private __gshared JSHandle _cachedSubtleExportKeyFn;
private __gshared JSHandle _cachedSubtleDeriveBitsFn;
private __gshared JSHandle _cachedSubtleDeriveKeyFn;
private __gshared bool _subtleFnsCached = false;

private void ensureSubtleFnsCached(IJSEngine engine) @trusted
{
    if (_subtleFnsCached) return;
    _cachedSubtleDigestFn = engine.newFunction(&jsSubtleDigest, "digest", 2);
    _cachedSubtleImportKeyFn = engine.newFunction(&jsSubtleImportKey, "importKey", 5);
    _cachedSubtleSignFn = engine.newFunction(&jsSubtleSign, "sign", 3);
    _cachedSubtleVerifyFn = engine.newFunction(&jsSubtleVerify, "verify", 4);
    _cachedSubtleEncryptFn = engine.newFunction(&jsSubtleEncrypt, "encrypt", 3);
    _cachedSubtleDecryptFn = engine.newFunction(&jsSubtleDecrypt, "decrypt", 3);
    _cachedSubtleGenerateKeyFn = engine.newFunction(&jsSubtleGenerateKey, "generateKey", 3);
    _cachedSubtleExportKeyFn = engine.newFunction(&jsSubtleExportKey, "exportKey", 2);
    _cachedSubtleDeriveBitsFn = engine.newFunction(&jsSubtleDeriveBits, "deriveBits", 3);
    _cachedSubtleDeriveKeyFn = engine.newFunction(&jsSubtleDeriveKey, "deriveKey", 5);
    _subtleFnsCached = true;
}

/// Install native subtle object on the crypto module and webcrypto property
void installNativeSubtle(IJSEngine engine, JSHandle cryptoObj) @trusted
{
    assert(engine !is null, "Null engine in installNativeSubtle");

    ensureSubtleFnsCached(engine);

    auto subtle = engine.newObject();
    engine.bindMethod(subtle, "digest", _cachedSubtleDigestFn);
    engine.bindMethod(subtle, "importKey", _cachedSubtleImportKeyFn);
    engine.bindMethod(subtle, "sign", _cachedSubtleSignFn);
    engine.bindMethod(subtle, "verify", _cachedSubtleVerifyFn);
    engine.bindMethod(subtle, "encrypt", _cachedSubtleEncryptFn);
    engine.bindMethod(subtle, "decrypt", _cachedSubtleDecryptFn);
    engine.bindMethod(subtle, "generateKey", _cachedSubtleGenerateKeyFn);
    engine.bindMethod(subtle, "exportKey", _cachedSubtleExportKeyFn);
    engine.bindMethod(subtle, "deriveBits", _cachedSubtleDeriveBitsFn);
    engine.bindMethod(subtle, "deriveKey", _cachedSubtleDeriveKeyFn);

    auto stubNames = ["wrapKey", "unwrapKey"];
    foreach (name; stubNames)
        engine.setProperty(subtle, name, engine.newFunction(&jsSubtleNotImplemented, name, 0));

    engine.setProperty(cryptoObj, "subtle", engine.dupValue(subtle));

    // Update webcrypto.subtle if webcrypto property already exists
    auto webcrypto = engine.getProperty(cryptoObj, "webcrypto");
    if (!engine.isUndefined(webcrypto) && !engine.isNull(webcrypto))
        engine.setProperty(webcrypto, "subtle", engine.dupValue(subtle));
    engine.freeValue(webcrypto);

    engine.freeValue(subtle);
}

/// Install subtle on the global crypto object (called from web_apis.d)
public void installSubtleOnGlobalCrypto(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installSubtleOnGlobalCrypto");

    ensureSubtleFnsCached(engine);

    auto global = engine.getGlobal();
    auto cryptoObj = engine.getProperty(global, "crypto");
    if (!engine.isUndefined(cryptoObj) && !engine.isNull(cryptoObj))
    {
        auto subtle = engine.newObject();
        engine.bindMethod(subtle, "digest", _cachedSubtleDigestFn);
        engine.bindMethod(subtle, "importKey", _cachedSubtleImportKeyFn);
        engine.bindMethod(subtle, "sign", _cachedSubtleSignFn);
        engine.bindMethod(subtle, "verify", _cachedSubtleVerifyFn);
        engine.bindMethod(subtle, "encrypt", _cachedSubtleEncryptFn);
        engine.bindMethod(subtle, "decrypt", _cachedSubtleDecryptFn);
        engine.bindMethod(subtle, "generateKey", _cachedSubtleGenerateKeyFn);
        engine.bindMethod(subtle, "exportKey", _cachedSubtleExportKeyFn);
        engine.bindMethod(subtle, "deriveBits", _cachedSubtleDeriveBitsFn);
        engine.bindMethod(subtle, "deriveKey", _cachedSubtleDeriveKeyFn);

        auto stubNames = ["wrapKey", "unwrapKey"];
        foreach (name; stubNames)
            engine.setProperty(subtle, name, engine.newFunction(&jsSubtleNotImplemented, name, 0));

        engine.setProperty(cryptoObj, "subtle", subtle);
    }
    engine.freeValue(cryptoObj);
    engine.freeValue(global);
}

/++
 + Normalize WebCrypto algorithm name to OpenSSL-compatible name
 + Accepts: "SHA-256", "SHA-384", "SHA-512", "SHA-1", or {name: "SHA-256"}
 +/
private string normalizeSubtleAlgo(IJSEngine engine, JSHandle algoArg) @trusted
{
    assert(engine !is null, "Null engine in normalizeSubtleAlgo");
    string raw;
    if (engine.isString(algoArg))
    {
        raw = engine.extractString(algoArg);
    }
    else if (engine.isObject(algoArg))
    {
        auto nameProp = engine.getProperty(algoArg, "name");
        if (engine.isString(nameProp))
            raw = engine.extractString(nameProp);
        engine.freeValue(nameProp);
    }
    if (raw is null || raw.length == 0) return null;

    // Normalize: strip dashes, lowercase
    // "SHA-256" -> "sha256", "SHA-1" -> "sha1"
    char[32] buf = void;
    size_t pos = 0;
    foreach (c; raw)
    {
        if (c == '-') continue;
        if (pos >= buf.length) return null;
        buf[pos++] = (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
    }
    auto lower = (() @trusted => cast(string) buf[0 .. pos])();

    if (lower == "sha1") return "sha1";
    if (lower == "sha256") return "sha256";
    if (lower == "sha384") return "sha384";
    if (lower == "sha512") return "sha512";
    return null;
}

/++
 + Extract the HMAC hash algorithm from a WebCrypto algorithm descriptor
 + Accepts: {name: "HMAC", hash: "SHA-256"} or {name: "HMAC", hash: {name: "SHA-256"}}
 +/
private string extractHmacHash(IJSEngine engine, JSHandle algoArg) @trusted
{
    assert(engine !is null, "Null engine in extractHmacHash");
    if (!engine.isObject(algoArg)) return null;

    auto hashProp = engine.getProperty(algoArg, "hash");
    scope(exit) engine.freeValue(hashProp);

    if (engine.isString(hashProp))
        return normalizeSubtleAlgo(engine, hashProp);
    else if (engine.isObject(hashProp))
        return normalizeSubtleAlgo(engine, hashProp);
    return null;
}

/// Extract algorithm name from a WebCrypto algorithm descriptor
private string extractAlgoName(IJSEngine engine, JSHandle algoArg) @trusted
{
    assert(engine !is null, "Null engine in extractAlgoName");
    if (engine.isString(algoArg))
        return engine.extractString(algoArg);
    if (engine.isObject(algoArg))
    {
        auto nameProp = engine.getProperty(algoArg, "name");
        scope(exit) engine.freeValue(nameProp);
        if (engine.isString(nameProp))
            return engine.extractString(nameProp);
    }
    return null;
}

/++
 + Extract data from a JS argument: TypedArray, ArrayBuffer, or string
 + Returns empty slice (not null) for empty typed arrays on JSC/V8
 +/
private ubyte[] extractDataArg(IJSEngine engine, JSHandle arg) @trusted
{
    assert(engine !is null, "Null engine in extractDataArg");
    auto bytes = engine.getTypedArrayBytes(arg);
    if (bytes !is null)
        return bytes;
    // getTypedArrayBytes returns null for empty typed arrays on some backends
    // Check if it's an object with length === 0 (empty TypedArray/ArrayBuffer)
    if (engine.isObject(arg))
    {
        auto lenProp = engine.getProperty(arg, "length");
        scope(exit) engine.freeValue(lenProp);
        if (engine.isNumber(lenProp) && engine.extractInt(lenProp) == 0)
            return [];  // Empty slice (non-null .ptr is not guaranteed, but length is 0)
    }
    // Try string
    if (engine.isString(arg))
    {
        auto str = engine.extractString(arg);
        return cast(ubyte[]) str;
    }
    return null;
}

/// Helper: create a resolved promise wrapping a value
private JSHandle resolvedPromise(IJSEngine engine, JSHandle value) @trusted
{
    assert(engine !is null, "Null engine in resolvedPromise");
    import dun.engine.iface : PromiseHandles;
    auto ph = engine.newPromise();
    /* callFunction returns an owned protected value (cross-backend
       contract from v1.1.6) — discarding it without freeValue leaks
       one JSValueProtect per crypto-async-op on JSC. Audit fix. */
    engine.freeValue(engine.callFunction(ph.resolve, engine.newUndefined(), [value]));
    engine.freeValue(ph.resolve);
    engine.freeValue(ph.reject);
    return ph.promise;
}

// Cached `(msg) => new Error(msg)` factory. Previously each
// `rejectedPromise` call did `engine.eval("new Error('<inlined>')")`
// per subtle.crypto rejection — JSC caches bytecode per unique source
// forever (per /debug-native-callback hot-path eval pattern), so a
// busy WebCrypto user accumulated KB of bytecode per failed op. Cache
// the factory once + call with the message as a value arg.
// Thread-local — Workers run on their own threads with their own
// IJSEngine. See `_fsErrFactory` / `_hrtimeBigIntFactory` comments
// for the foreign-handle segfault that motivates `static` here.
private static JSHandle _cryptoErrFactory;
private static bool _cryptoErrFactoryCached = false;

private void ensureCryptoErrFactoryCached(IJSEngine engine) @trusted
{
    if (_cryptoErrFactoryCached) return;
    auto r = engine.eval("(function(m){return new Error(m);})", "<subtle-err>");
    if (!r.isError && engine.isFunction(r.value))
    {
        _cryptoErrFactory = r.value;
        _cryptoErrFactoryCached = true;
    }
    else
        engine.freeValue(r.value);
}

/// Helper: create a rejected promise with an error message
private JSHandle rejectedPromise(IJSEngine engine, string msg) @trusted
{
    assert(engine !is null, "Null engine in rejectedPromise");
    import dun.engine.iface : PromiseHandles;
    auto ph = engine.newPromise();
    ensureCryptoErrFactoryCached(engine);
    JSHandle errVal;
    bool errOk = false;
    if (_cryptoErrFactoryCached)
    {
        auto msgVal = engine.newString(msg);
        auto undef = engine.newUndefined();
        scope(exit) { engine.freeValue(msgVal); engine.freeValue(undef); }
        errVal = engine.callFunction(engine.dupValue(_cryptoErrFactory), undef, (&msgVal)[0 .. 1]);
        errOk = !engine.isException(errVal);
    }
    if (errOk)
    {
        engine.freeValue(engine.callFunction(ph.reject, engine.newUndefined(), (&errVal)[0 .. 1]));
        engine.freeValue(errVal);
    }
    else
    {
        engine.freeValue(errVal);
        auto fallback = engine.newString(msg);
        engine.freeValue(engine.callFunction(ph.reject, engine.newUndefined(), (&fallback)[0 .. 1]));
        engine.freeValue(fallback);
    }
    engine.freeValue(ph.resolve);
    engine.freeValue(ph.reject);
    return ph.promise;
}

/// Simple JS string escaping for error messages — delegates to the
/// canonical helper. `nothrow` shim wraps the throw-on-OOM Appender
/// path; on the unlikely throw the unescaped string is returned (the
/// legacy local impl swallowed the same way).
private string escapeJsStr(string s) @safe nothrow
{
    import dun.builtins.helpers : escapeJsString;
    try return escapeJsString(s);
    catch (Exception) return s;
}

// ── subtle.digest(algorithm, data) ──

JSHandle jsSubtleDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.digest");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.digest");

    if (args.length < 2)
        return rejectedPromise(engine, "subtle.digest requires algorithm and data arguments");

    auto algo = normalizeSubtleAlgo(engine, args[0]);
    if (algo is null)
        return rejectedPromise(engine, "Unsupported digest algorithm");

    auto md = getEvpMd(algo);
    if (md is null)
        return rejectedPromise(engine, "Unsupported digest algorithm: " ~ algo);

    auto inputBytes = extractDataArg(engine, args[1]);

    int mdSize = EVP_MD_get_size(md);
    assert(mdSize > 0 && mdSize <= SUBTLE_MAX_DIGEST_SIZE, "Invalid digest size from EVP_MD_get_size");

    ubyte[SUBTLE_MAX_DIGEST_SIZE] outBuf = void;
    uint outLen = 0;

    int rc = EVP_Digest(
        inputBytes.ptr, inputBytes.length,
        outBuf.ptr, &outLen,
        md, null);

    if (rc != 1 || outLen == 0)
        return rejectedPromise(engine, "Digest computation failed");

    auto result = engine.newUint8Array(outBuf[0 .. outLen]);
    return resolvedPromise(engine, result);
}

// ── subtle.importKey(format, keyData, algorithm, extractable, usages) ──

JSHandle jsSubtleImportKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.importKey");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.importKey");

    if (args.length < 5)
        return rejectedPromise(engine, "subtle.importKey requires format, keyData, algorithm, extractable, usages");

    auto format = engine.extractString(args[0]);
    if (format != "raw")
        return rejectedPromise(engine, "Only 'raw' format is supported for importKey");

    auto keyBytes = extractDataArg(engine, args[1]);
    if (keyBytes is null)
        return rejectedPromise(engine, "subtle.importKey: keyData must be ArrayBuffer or TypedArray");

    auto algoName = extractAlgoName(engine, args[2]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.importKey: algorithm must specify a name");

    // Normalize algo name to uppercase for comparison
    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    // Create a CryptoKey-like object that stores the raw key material
    auto keyObj = engine.newObject();
    engine.setProperty(keyObj, "type", engine.newString("secret"));
    engine.setProperty(keyObj, "extractable", engine.newBool(engine.extractBool(args[3])));

    // Store algorithm info
    auto algoObj = engine.newObject();
    engine.setProperty(algoObj, "name", engine.newString(upperName));

    // Store the hash sub-algorithm if HMAC
    if (upperName == "HMAC")
    {
        auto hashAlgo = extractHmacHash(engine, args[2]);
        if (hashAlgo !is null)
        {
            auto hashObj = engine.newObject();
            string hashName = subtleHashName(hashAlgo);
            engine.setProperty(hashObj, "name", engine.newString(hashName));
            engine.setProperty(algoObj, "hash", hashObj);
        }
    }
    engine.setProperty(keyObj, "algorithm", algoObj);

    // Store raw key data as a Uint8Array property
    auto keyData = new ubyte[keyBytes.length];
    keyData[] = keyBytes[];
    engine.setProperty(keyObj, "_keyData", engine.newUint8Array(keyData));

    // Store usages
    engine.setProperty(keyObj, "usages", engine.dupValue(args[4]));

    return resolvedPromise(engine, keyObj);
}

/// Convert internal hash name to WebCrypto format
private string subtleHashName(string algo) @safe pure nothrow
{
    if (algo == "sha1") return "SHA-1";
    if (algo == "sha256") return "SHA-256";
    if (algo == "sha384") return "SHA-384";
    if (algo == "sha512") return "SHA-512";
    return "SHA-256";
}

// ── subtle.sign(algorithm, key, data) ──

JSHandle jsSubtleSign(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.sign");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.sign");

    if (args.length < 3)
        return rejectedPromise(engine, "subtle.sign requires algorithm, key, and data arguments");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.sign: algorithm must specify a name");

    // Normalize to uppercase
    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    if (upperName != "HMAC")
        return rejectedPromise(engine, "subtle.sign: only HMAC is supported");

    // Get hash algorithm: from the sign() algorithm arg or from the key's algorithm
    string hashAlgo = extractHmacHash(engine, args[0]);
    if (hashAlgo is null)
    {
        // Try to get hash from the key's algorithm
        auto keyAlgo = engine.getProperty(args[1], "algorithm");
        if (!engine.isUndefined(keyAlgo) && !engine.isNull(keyAlgo))
            hashAlgo = extractHmacHash(engine, keyAlgo);
        engine.freeValue(keyAlgo);
    }
    if (hashAlgo is null)
        return rejectedPromise(engine, "subtle.sign: could not determine hash algorithm");

    auto md = getEvpMd(hashAlgo);
    if (md is null)
        return rejectedPromise(engine, "subtle.sign: unsupported hash algorithm");

    // Extract key data from CryptoKey
    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "subtle.sign: invalid key");

    // Extract input data
    auto inputBytes = extractDataArg(engine, args[2]);
    if (inputBytes is null)
        return rejectedPromise(engine, "subtle.sign: data must be ArrayBuffer or TypedArray");

    // Compute HMAC using OpenSSL
    ubyte[SUBTLE_MAX_DIGEST_SIZE] outBuf = void;
    uint outLen = 0;

    auto result = HMAC(md,
        cast(const(void)*) keyBytes.ptr, cast(int) keyBytes.length,
        inputBytes.ptr, inputBytes.length,
        outBuf.ptr, &outLen);

    if (result is null || outLen == 0)
        return rejectedPromise(engine, "HMAC sign failed");

    auto sig = engine.newUint8Array(outBuf[0 .. outLen]);
    return resolvedPromise(engine, sig);
}

// ── subtle.verify(algorithm, key, signature, data) ──

JSHandle jsSubtleVerify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.verify");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.verify");

    if (args.length < 4)
        return rejectedPromise(engine, "subtle.verify requires algorithm, key, signature, and data arguments");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.verify: algorithm must specify a name");

    // Normalize to uppercase
    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    if (upperName != "HMAC")
        return rejectedPromise(engine, "subtle.verify: only HMAC is supported");

    // Get hash algorithm
    string hashAlgo = extractHmacHash(engine, args[0]);
    if (hashAlgo is null)
    {
        auto keyAlgo = engine.getProperty(args[1], "algorithm");
        if (!engine.isUndefined(keyAlgo) && !engine.isNull(keyAlgo))
            hashAlgo = extractHmacHash(engine, keyAlgo);
        engine.freeValue(keyAlgo);
    }
    if (hashAlgo is null)
        return rejectedPromise(engine, "subtle.verify: could not determine hash algorithm");

    auto md = getEvpMd(hashAlgo);
    if (md is null)
        return rejectedPromise(engine, "subtle.verify: unsupported hash algorithm");

    // Extract key data
    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "subtle.verify: invalid key");

    // Extract provided signature
    auto sigBytes = engine.getTypedArrayBytes(args[2]);
    if (sigBytes is null || sigBytes.length == 0)
        return rejectedPromise(engine, "subtle.verify: signature must be ArrayBuffer or TypedArray");

    // Extract data
    auto inputBytes = extractDataArg(engine, args[3]);
    if (inputBytes is null)
        return rejectedPromise(engine, "subtle.verify: data must be ArrayBuffer or TypedArray");

    // Compute expected HMAC
    ubyte[SUBTLE_MAX_DIGEST_SIZE] outBuf = void;
    uint outLen = 0;

    auto hmacResult = HMAC(md,
        cast(const(void)*) keyBytes.ptr, cast(int) keyBytes.length,
        inputBytes.ptr, inputBytes.length,
        outBuf.ptr, &outLen);

    if (hmacResult is null || outLen == 0)
        return rejectedPromise(engine, "HMAC verify failed");

    // Timing-safe comparison
    bool isValid = false;
    if (sigBytes.length == outLen)
        isValid = CRYPTO_memcmp(sigBytes.ptr, outBuf.ptr, outLen) == 0;

    auto boolResult = engine.newBool(isValid);
    return resolvedPromise(engine, boolResult);
}

// ── subtle.encrypt(algorithm, key, data) ──

JSHandle jsSubtleEncrypt(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.encrypt");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.encrypt");

    if (args.length < 3)
        return rejectedPromise(engine, "subtle.encrypt requires algorithm, key, and data arguments");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.encrypt: algorithm must specify a name");

    // Normalize name
    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    if (upperName == "AES-GCM" || upperName == "AESGCM")
        return subtleAesGcmEncrypt(engine, args);
    else if (upperName == "AES-CBC" || upperName == "AESCBC")
        return subtleAesCbcEncrypt(engine, args);
    else
        return rejectedPromise(engine, "subtle.encrypt: unsupported algorithm '" ~ algoName ~ "'");
}

// ── subtle.decrypt(algorithm, key, data) ──

JSHandle jsSubtleDecrypt(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.decrypt");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.decrypt");

    if (args.length < 3)
        return rejectedPromise(engine, "subtle.decrypt requires algorithm, key, and data arguments");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.decrypt: algorithm must specify a name");

    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    if (upperName == "AES-GCM" || upperName == "AESGCM")
        return subtleAesGcmDecrypt(engine, args);
    else if (upperName == "AES-CBC" || upperName == "AESCBC")
        return subtleAesCbcDecrypt(engine, args);
    else
        return rejectedPromise(engine, "subtle.decrypt: unsupported algorithm '" ~ algoName ~ "'");
}

// ── AES-GCM encrypt ──
private JSHandle subtleAesGcmEncrypt(IJSEngine engine, scope JSHandle[] args) @trusted
{
    assert(engine !is null, "Null engine in subtleAesGcmEncrypt");

    // Extract IV from algorithm descriptor
    auto ivProp = engine.getProperty(args[0], "iv");
    auto iv = engine.getTypedArrayBytes(ivProp);
    engine.freeValue(ivProp);
    if (iv is null || iv.length == 0)
        return rejectedPromise(engine, "AES-GCM requires an 'iv' in the algorithm object");

    // Extract key data
    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "AES-GCM encrypt: invalid key");

    // Select cipher based on key length
    const(EVP_CIPHER)* cipher;
    if (keyBytes.length == AES128_KEY_BYTES)
        cipher = EVP_aes_128_gcm();
    else if (keyBytes.length == AES256_KEY_BYTES)
        cipher = EVP_aes_256_gcm();
    else
        return rejectedPromise(engine, "AES-GCM: key must be 128 or 256 bits");

    // Extract plaintext data
    auto plaintext = extractDataArg(engine, args[2]);
    if (plaintext is null)
        return rejectedPromise(engine, "AES-GCM encrypt: data must be ArrayBuffer or TypedArray");
    if (plaintext.length > SUBTLE_MAX_DATA_SIZE)
        return rejectedPromise(engine, "AES-GCM encrypt: data too large");

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return rejectedPromise(engine, "AES-GCM encrypt: failed to create cipher context");
    scope(exit) EVP_CIPHER_CTX_free(evpCtx);

    if (EVP_EncryptInit_ex(evpCtx, cipher, null, null, null) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: init failed");

    // Set IV length
    if (EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_SET_IVLEN, cast(int) iv.length, null) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: failed to set IV length");

    if (EVP_EncryptInit_ex(evpCtx, null, null, keyBytes.ptr, iv.ptr) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: key/iv init failed");

    // Encrypt
    auto outBuf = new ubyte[plaintext.length + SUBTLE_AES_BLOCK_SIZE];
    int outLen = 0;
    if (EVP_EncryptUpdate(evpCtx, outBuf.ptr, &outLen, plaintext.ptr, cast(int) plaintext.length) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: update failed");

    int finalLen = 0;
    if (EVP_EncryptFinal_ex(evpCtx, outBuf.ptr + outLen, &finalLen) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: final failed");
    outLen += finalLen;

    // Get auth tag
    ubyte[SUBTLE_AES_GCM_TAG_LEN] tag = void;
    if (EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_GET_TAG, SUBTLE_AES_GCM_TAG_LEN, tag.ptr) != 1)
        return rejectedPromise(engine, "AES-GCM encrypt: failed to get auth tag");

    // Result = ciphertext + tag (WebCrypto spec)
    auto result = new ubyte[outLen + SUBTLE_AES_GCM_TAG_LEN];
    result[0 .. outLen] = outBuf[0 .. outLen];
    result[outLen .. outLen + SUBTLE_AES_GCM_TAG_LEN] = tag[];

    auto resultArr = engine.newUint8Array(result);
    return resolvedPromise(engine, resultArr);
}

// ── AES-GCM decrypt ──
private JSHandle subtleAesGcmDecrypt(IJSEngine engine, scope JSHandle[] args) @trusted
{
    assert(engine !is null, "Null engine in subtleAesGcmDecrypt");

    auto ivProp = engine.getProperty(args[0], "iv");
    auto iv = engine.getTypedArrayBytes(ivProp);
    engine.freeValue(ivProp);
    if (iv is null || iv.length == 0)
        return rejectedPromise(engine, "AES-GCM requires an 'iv' in the algorithm object");

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "AES-GCM decrypt: invalid key");

    const(EVP_CIPHER)* cipher;
    if (keyBytes.length == AES128_KEY_BYTES)
        cipher = EVP_aes_128_gcm();
    else if (keyBytes.length == AES256_KEY_BYTES)
        cipher = EVP_aes_256_gcm();
    else
        return rejectedPromise(engine, "AES-GCM: key must be 128 or 256 bits");

    auto cipherData = extractDataArg(engine, args[2]);
    if (cipherData is null)
        return rejectedPromise(engine, "AES-GCM decrypt: data must be ArrayBuffer or TypedArray");
    if (cipherData.length < SUBTLE_AES_GCM_TAG_LEN)
        return rejectedPromise(engine, "AES-GCM decrypt: data too short (missing auth tag)");

    // Split ciphertext and tag (tag is appended at end per WebCrypto spec)
    auto ciphertext = cipherData[0 .. $ - SUBTLE_AES_GCM_TAG_LEN];
    auto tag = cipherData[$ - SUBTLE_AES_GCM_TAG_LEN .. $];

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return rejectedPromise(engine, "AES-GCM decrypt: failed to create cipher context");
    scope(exit) EVP_CIPHER_CTX_free(evpCtx);

    if (EVP_DecryptInit_ex(evpCtx, cipher, null, null, null) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: init failed");

    if (EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_SET_IVLEN, cast(int) iv.length, null) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: failed to set IV length");

    if (EVP_DecryptInit_ex(evpCtx, null, null, keyBytes.ptr, iv.ptr) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: key/iv init failed");

    auto outBuf = new ubyte[ciphertext.length + SUBTLE_AES_BLOCK_SIZE];
    int outLen = 0;
    if (EVP_DecryptUpdate(evpCtx, outBuf.ptr, &outLen, ciphertext.ptr, cast(int) ciphertext.length) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: update failed");

    // Set expected tag
    if (EVP_CIPHER_CTX_ctrl(evpCtx, EVP_CTRL_GCM_SET_TAG, SUBTLE_AES_GCM_TAG_LEN, cast(void*) tag.ptr) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: failed to set auth tag");

    int finalLen = 0;
    if (EVP_DecryptFinal_ex(evpCtx, outBuf.ptr + outLen, &finalLen) != 1)
        return rejectedPromise(engine, "AES-GCM decrypt: authentication failed");
    outLen += finalLen;

    auto resultArr = engine.newUint8Array(outBuf[0 .. outLen]);
    return resolvedPromise(engine, resultArr);
}

// ── AES-CBC encrypt ──
private JSHandle subtleAesCbcEncrypt(IJSEngine engine, scope JSHandle[] args) @trusted
{
    assert(engine !is null, "Null engine in subtleAesCbcEncrypt");

    auto ivProp = engine.getProperty(args[0], "iv");
    auto iv = engine.getTypedArrayBytes(ivProp);
    engine.freeValue(ivProp);
    if (iv is null || iv.length != SUBTLE_AES_CBC_IV_LEN)
        return rejectedPromise(engine, "AES-CBC requires a 16-byte 'iv'");

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "AES-CBC encrypt: invalid key");

    const(EVP_CIPHER)* cipher;
    if (keyBytes.length == AES128_KEY_BYTES)
        cipher = EVP_aes_128_cbc();
    else if (keyBytes.length == AES192_KEY_BYTES)
        cipher = EVP_aes_192_cbc();
    else if (keyBytes.length == AES256_KEY_BYTES)
        cipher = EVP_aes_256_cbc();
    else
        return rejectedPromise(engine, "AES-CBC: key must be 128, 192, or 256 bits");

    auto plaintext = extractDataArg(engine, args[2]);
    if (plaintext is null)
        return rejectedPromise(engine, "AES-CBC encrypt: data must be ArrayBuffer or TypedArray");
    if (plaintext.length > SUBTLE_MAX_DATA_SIZE)
        return rejectedPromise(engine, "AES-CBC encrypt: data too large");

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return rejectedPromise(engine, "AES-CBC encrypt: failed to create cipher context");
    scope(exit) EVP_CIPHER_CTX_free(evpCtx);

    if (EVP_EncryptInit_ex(evpCtx, cipher, null, keyBytes.ptr, iv.ptr) != 1)
        return rejectedPromise(engine, "AES-CBC encrypt: init failed");

    // Output can be up to input + one block of padding
    auto outBuf = new ubyte[plaintext.length + SUBTLE_AES_BLOCK_SIZE];
    int outLen = 0;
    if (EVP_EncryptUpdate(evpCtx, outBuf.ptr, &outLen, plaintext.ptr, cast(int) plaintext.length) != 1)
        return rejectedPromise(engine, "AES-CBC encrypt: update failed");

    int finalLen = 0;
    if (EVP_EncryptFinal_ex(evpCtx, outBuf.ptr + outLen, &finalLen) != 1)
        return rejectedPromise(engine, "AES-CBC encrypt: final failed");
    outLen += finalLen;

    auto resultArr = engine.newUint8Array(outBuf[0 .. outLen]);
    return resolvedPromise(engine, resultArr);
}

// ── AES-CBC decrypt ──
private JSHandle subtleAesCbcDecrypt(IJSEngine engine, scope JSHandle[] args) @trusted
{
    assert(engine !is null, "Null engine in subtleAesCbcDecrypt");

    auto ivProp = engine.getProperty(args[0], "iv");
    auto iv = engine.getTypedArrayBytes(ivProp);
    engine.freeValue(ivProp);
    if (iv is null || iv.length != SUBTLE_AES_CBC_IV_LEN)
        return rejectedPromise(engine, "AES-CBC requires a 16-byte 'iv'");

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null || keyBytes.length == 0)
        return rejectedPromise(engine, "AES-CBC decrypt: invalid key");

    const(EVP_CIPHER)* cipher;
    if (keyBytes.length == AES128_KEY_BYTES)
        cipher = EVP_aes_128_cbc();
    else if (keyBytes.length == AES192_KEY_BYTES)
        cipher = EVP_aes_192_cbc();
    else if (keyBytes.length == AES256_KEY_BYTES)
        cipher = EVP_aes_256_cbc();
    else
        return rejectedPromise(engine, "AES-CBC: key must be 128, 192, or 256 bits");

    auto ciphertext = extractDataArg(engine, args[2]);
    if (ciphertext is null)
        return rejectedPromise(engine, "AES-CBC decrypt: data must be ArrayBuffer or TypedArray");

    auto evpCtx = EVP_CIPHER_CTX_new();
    if (evpCtx is null)
        return rejectedPromise(engine, "AES-CBC decrypt: failed to create cipher context");
    scope(exit) EVP_CIPHER_CTX_free(evpCtx);

    if (EVP_DecryptInit_ex(evpCtx, cipher, null, keyBytes.ptr, iv.ptr) != 1)
        return rejectedPromise(engine, "AES-CBC decrypt: init failed");

    auto outBuf = new ubyte[ciphertext.length + SUBTLE_AES_BLOCK_SIZE];
    int outLen = 0;
    if (EVP_DecryptUpdate(evpCtx, outBuf.ptr, &outLen, ciphertext.ptr, cast(int) ciphertext.length) != 1)
        return rejectedPromise(engine, "AES-CBC decrypt: update failed");

    int finalLen = 0;
    if (EVP_DecryptFinal_ex(evpCtx, outBuf.ptr + outLen, &finalLen) != 1)
        return rejectedPromise(engine, "AES-CBC decrypt: decryption failed (bad padding or wrong key)");
    outLen += finalLen;

    auto resultArr = engine.newUint8Array(outBuf[0 .. outLen]);
    return resolvedPromise(engine, resultArr);
}

// ── subtle.generateKey(algorithm, extractable, keyUsages) ──
JSHandle jsSubtleGenerateKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.generateKey");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.generateKey");

    if (args.length < 3)
        return rejectedPromise(engine, "subtle.generateKey requires algorithm, extractable, keyUsages");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.generateKey: algorithm must specify a name");

    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    int keyLenBytes = 0;

    if (upperName == "AES-GCM" || upperName == "AES-CBC" || upperName == "AES-CTR"
        || upperName == "AESGCM" || upperName == "AESCBC" || upperName == "AESCTR")
    {
        auto lengthProp = engine.getProperty(args[0], "length");
        int bits = engine.isNumber(lengthProp) ? engine.extractInt(lengthProp) : 256;
        engine.freeValue(lengthProp);
        if (bits != 128 && bits != 192 && bits != 256)
            return rejectedPromise(engine, "subtle.generateKey: AES key length must be 128, 192, or 256");
        keyLenBytes = bits / 8;
    }
    else if (upperName == "HMAC")
    {
        auto lengthProp = engine.getProperty(args[0], "length");
        if (engine.isNumber(lengthProp))
        {
            keyLenBytes = engine.extractInt(lengthProp) / 8;
        }
        else
        {
            auto hashAlgo = extractHmacHash(engine, args[0]);
            if (hashAlgo == "sha1") keyLenBytes = 64;
            else if (hashAlgo == "sha256") keyLenBytes = 64;
            else if (hashAlgo == "sha384") keyLenBytes = 128;
            else if (hashAlgo == "sha512") keyLenBytes = 128;
            else keyLenBytes = 64;
        }
        engine.freeValue(lengthProp);
        if (keyLenBytes <= 0 || keyLenBytes > 1024)
            return rejectedPromise(engine, "subtle.generateKey: invalid HMAC key length");
    }
    else
        return rejectedPromise(engine, "subtle.generateKey: unsupported algorithm '" ~ algoName ~ "'");

    auto keyBytes = new ubyte[keyLenBytes];
    fillRandomBytes(keyBytes);

    auto keyObj = engine.newObject();
    engine.setProperty(keyObj, "type", engine.newString("secret"));
    engine.setProperty(keyObj, "extractable", engine.newBool(engine.extractBool(args[1])));

    auto algoObj = engine.newObject();
    engine.setProperty(algoObj, "name", engine.newString(upperName));

    if (upperName == "HMAC")
    {
        auto hashAlgo = extractHmacHash(engine, args[0]);
        if (hashAlgo !is null)
        {
            auto hashObj = engine.newObject();
            engine.setProperty(hashObj, "name", engine.newString(subtleHashName(hashAlgo)));
            engine.setProperty(algoObj, "hash", hashObj);
        }
        engine.setProperty(algoObj, "length", engine.newFloat(cast(double)(keyLenBytes * 8)));
    }
    else
        engine.setProperty(algoObj, "length", engine.newFloat(cast(double)(keyLenBytes * 8)));

    engine.setProperty(keyObj, "algorithm", algoObj);
    engine.setProperty(keyObj, "_keyData", engine.newUint8Array(keyBytes));
    engine.setProperty(keyObj, "usages", engine.dupValue(args[2]));

    return resolvedPromise(engine, keyObj);
}

// ── subtle.exportKey(format, key) ──
JSHandle jsSubtleExportKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.exportKey");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.exportKey");

    if (args.length < 2)
        return rejectedPromise(engine, "subtle.exportKey requires format and key arguments");

    auto format = engine.extractString(args[0]);
    if (format != "raw")
        return rejectedPromise(engine, "subtle.exportKey: only 'raw' format is supported");

    auto extractable = engine.getProperty(args[1], "extractable");
    bool canExtract = engine.isBool(extractable) ? engine.extractBool(extractable) : false;
    engine.freeValue(extractable);
    if (!canExtract)
        return rejectedPromise(engine, "subtle.exportKey: key is not extractable");

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto keyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (keyBytes is null)
        return rejectedPromise(engine, "subtle.exportKey: key has no data");

    auto result = engine.newUint8Array(keyBytes);
    return resolvedPromise(engine, result);
}

// ── subtle.deriveBits(algorithm, baseKey, length) ──
JSHandle jsSubtleDeriveBits(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.deriveBits");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.deriveBits");

    if (args.length < 3)
        return rejectedPromise(engine, "subtle.deriveBits requires algorithm, baseKey, length");

    auto algoName = extractAlgoName(engine, args[0]);
    if (algoName is null)
        return rejectedPromise(engine, "subtle.deriveBits: algorithm must specify a name");

    char[32] nameBuf = void;
    size_t nameLen = 0;
    foreach (c; algoName)
    {
        if (nameLen >= nameBuf.length) break;
        nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();

    int lengthBits = engine.isNumber(args[2]) ? engine.extractInt(args[2]) : 0;
    if (lengthBits <= 0 || lengthBits % 8 != 0 || lengthBits > 8192)
        return rejectedPromise(engine, "subtle.deriveBits: length must be a positive multiple of 8");
    int lengthBytes = lengthBits / 8;

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto baseKeyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (baseKeyBytes is null || baseKeyBytes.length == 0)
        return rejectedPromise(engine, "subtle.deriveBits: invalid base key");

    if (upperName == "PBKDF2")
    {
        auto hashAlgo = extractHmacHash(engine, args[0]);
        if (hashAlgo is null) hashAlgo = normalizeSubtleAlgo(engine, args[0]);
        if (hashAlgo is null) hashAlgo = "sha256";

        auto md = getEvpMd(hashAlgo);
        if (md is null)
            return rejectedPromise(engine, "subtle.deriveBits: unsupported hash for PBKDF2");

        auto saltProp = engine.getProperty(args[0], "salt");
        auto salt = extractDataArg(engine, saltProp);
        engine.freeValue(saltProp);

        auto iterProp = engine.getProperty(args[0], "iterations");
        int iterations = engine.isNumber(iterProp) ? engine.extractInt(iterProp) : 1;
        engine.freeValue(iterProp);

        if (iterations < 1)
            return rejectedPromise(engine, "subtle.deriveBits: iterations must be >= 1");

        auto outBuf = new ubyte[lengthBytes];
        int ret = PKCS5_PBKDF2_HMAC(
            cast(const(char)*) baseKeyBytes.ptr, cast(int) baseKeyBytes.length,
            salt !is null ? salt.ptr : null, cast(int)(salt !is null ? salt.length : 0),
            iterations, md, lengthBytes, outBuf.ptr);

        if (ret != 1)
            return rejectedPromise(engine, "subtle.deriveBits: PBKDF2 derivation failed");

        return resolvedPromise(engine, engine.newUint8Array(outBuf));
    }
    else if (upperName == "HKDF")
    {
        auto hashName = extractHmacHash(engine, args[0]);
        if (hashName is null)
        {
            auto hashProp = engine.getProperty(args[0], "hash");
            if (engine.isString(hashProp))
                hashName = normalizeSubtleAlgo(engine, hashProp);
            else if (engine.isObject(hashProp))
                hashName = normalizeSubtleAlgo(engine, hashProp);
            engine.freeValue(hashProp);
        }
        if (hashName is null) hashName = "sha256";

        auto md = getEvpMd(hashName);
        if (md is null)
            return rejectedPromise(engine, "subtle.deriveBits: unsupported hash for HKDF");

        auto saltProp = engine.getProperty(args[0], "salt");
        auto salt = extractDataArg(engine, saltProp);
        engine.freeValue(saltProp);

        auto infoProp = engine.getProperty(args[0], "info");
        auto info = extractDataArg(engine, infoProp);
        engine.freeValue(infoProp);

        int hashLen = EVP_MD_get_size(md);
        if (hashLen <= 0) hashLen = 32;

        // HKDF-Extract: PRK = HMAC(salt, IKM)
        ubyte[SUBTLE_MAX_DIGEST_SIZE] prk = void;
        uint prkLen = 0;
        auto hmacResult = HMAC(md,
            salt !is null ? cast(const(void)*) salt.ptr : cast(const(void)*) "".ptr,
            salt !is null ? cast(int) salt.length : 0,
            baseKeyBytes.ptr, baseKeyBytes.length,
            prk.ptr, &prkLen);
        if (hmacResult is null || prkLen == 0)
            return rejectedPromise(engine, "subtle.deriveBits: HKDF extract failed");

        // HKDF-Expand
        auto outBuf = new ubyte[lengthBytes];
        ubyte[SUBTLE_MAX_DIGEST_SIZE] T = void;
        size_t tLen = 0;
        size_t done = 0;
        ubyte counter = 1;

        while (done < lengthBytes)
        {
            // T(n) = HMAC(PRK, T(n-1) || info || counter)
            auto inputBuf = new ubyte[tLen + (info !is null ? info.length : 0) + 1];
            if (tLen > 0) inputBuf[0 .. tLen] = T[0 .. tLen];
            if (info !is null && info.length > 0) inputBuf[tLen .. tLen + info.length] = info[];
            inputBuf[$ - 1] = counter;

            uint tmpLen = 0;
            auto tmpResult = HMAC(md,
                cast(const(void)*) prk.ptr, cast(int) prkLen,
                inputBuf.ptr, inputBuf.length,
                T.ptr, &tmpLen);
            if (tmpResult is null || tmpLen == 0)
                return rejectedPromise(engine, "subtle.deriveBits: HKDF expand failed");
            tLen = tmpLen;

            size_t copyLen = lengthBytes - done;
            if (copyLen > tLen) copyLen = tLen;
            outBuf[done .. done + copyLen] = T[0 .. copyLen];
            done += copyLen;
            counter++;
        }

        return resolvedPromise(engine, engine.newUint8Array(outBuf));
    }
    else
        return rejectedPromise(engine, "subtle.deriveBits: unsupported algorithm '" ~ algoName ~ "'");
}

// ── subtle.deriveKey(algorithm, baseKey, derivedKeyType, extractable, keyUsages) ──
JSHandle jsSubtleDeriveKey(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle.deriveKey");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle.deriveKey");

    if (args.length < 5)
        return rejectedPromise(engine, "subtle.deriveKey requires algorithm, baseKey, derivedKeyType, extractable, keyUsages");

    // Get the desired key length from derivedKeyType
    auto derivedAlgoName = extractAlgoName(engine, args[2]);
    int derivedBits = 256;
    if (derivedAlgoName !is null)
    {
        auto lengthProp = engine.getProperty(args[2], "length");
        if (engine.isNumber(lengthProp))
            derivedBits = engine.extractInt(lengthProp);
        engine.freeValue(lengthProp);
    }

    // Call deriveBits with the computed length
    JSHandle[3] deriveBitsArgs;
    deriveBitsArgs[0] = args[0];
    deriveBitsArgs[1] = args[1];
    deriveBitsArgs[2] = engine.newFloat(cast(double) derivedBits);

    auto bitsResult = jsSubtleDeriveBits(ctx, thisVal, deriveBitsArgs[0 .. 3]);
    engine.freeValue(deriveBitsArgs[2]);

    // The result is a promise — we need to wrap the derived bits into a CryptoKey
    // For simplicity, derive bits synchronously and wrap in a key object
    // Since deriveBits already returns a resolved promise, we build the key from the algorithm
    // Re-derive the bits directly instead of unwrapping the promise
    auto algoName = extractAlgoName(engine, args[0]);
    char[32] nameBuf = void;
    size_t nameLen = 0;
    if (algoName !is null)
    {
        foreach (c; algoName)
        {
            if (nameLen >= nameBuf.length) break;
            nameBuf[nameLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
        }
    }
    auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();
    engine.freeValue(bitsResult);

    if (derivedBits <= 0 || derivedBits % 8 != 0 || derivedBits > 8192)
        return rejectedPromise(engine, "subtle.deriveKey: invalid derived key length");
    int derivedBytes = derivedBits / 8;

    auto keyDataProp = engine.getProperty(args[1], "_keyData");
    auto baseKeyBytes = engine.getTypedArrayBytes(keyDataProp);
    engine.freeValue(keyDataProp);
    if (baseKeyBytes is null || baseKeyBytes.length == 0)
        return rejectedPromise(engine, "subtle.deriveKey: invalid base key");

    ubyte[] derivedKeyBytes;

    if (upperName == "PBKDF2")
    {
        auto hashAlgo = extractHmacHash(engine, args[0]);
        if (hashAlgo is null) hashAlgo = "sha256";
        auto md = getEvpMd(hashAlgo);
        if (md is null)
            return rejectedPromise(engine, "subtle.deriveKey: unsupported hash");

        auto saltProp = engine.getProperty(args[0], "salt");
        auto salt = extractDataArg(engine, saltProp);
        engine.freeValue(saltProp);

        auto iterProp = engine.getProperty(args[0], "iterations");
        int iterations = engine.isNumber(iterProp) ? engine.extractInt(iterProp) : 1;
        engine.freeValue(iterProp);

        derivedKeyBytes = new ubyte[derivedBytes];
        int ret = PKCS5_PBKDF2_HMAC(
            cast(const(char)*) baseKeyBytes.ptr, cast(int) baseKeyBytes.length,
            salt !is null ? salt.ptr : null, cast(int)(salt !is null ? salt.length : 0),
            iterations, md, derivedBytes, derivedKeyBytes.ptr);
        if (ret != 1)
            return rejectedPromise(engine, "subtle.deriveKey: PBKDF2 failed");
    }
    else
        return rejectedPromise(engine, "subtle.deriveKey: unsupported algorithm '" ~ (algoName !is null ? algoName : "null") ~ "'");

    auto keyObj = engine.newObject();
    engine.setProperty(keyObj, "type", engine.newString("secret"));
    engine.setProperty(keyObj, "extractable", engine.newBool(engine.extractBool(args[3])));

    auto derivedAlgo = engine.newObject();
    if (derivedAlgoName !is null)
    {
        char[32] dBuf = void;
        size_t dLen = 0;
        foreach (c; derivedAlgoName)
        {
            if (dLen >= dBuf.length) break;
            dBuf[dLen++] = (c >= 'a' && c <= 'z') ? cast(char)(c - 32) : c;
        }
        engine.setProperty(derivedAlgo, "name", engine.newString((() @trusted => cast(string) dBuf[0 .. dLen])()));
    }
    engine.setProperty(derivedAlgo, "length", engine.newFloat(cast(double) derivedBits));
    engine.setProperty(keyObj, "algorithm", derivedAlgo);
    engine.setProperty(keyObj, "_keyData", engine.newUint8Array(derivedKeyBytes));
    engine.setProperty(keyObj, "usages", engine.dupValue(args[4]));

    return resolvedPromise(engine, keyObj);
}

// ── subtle stub for unimplemented methods ──
JSHandle jsSubtleNotImplemented(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in subtle stub");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in subtle stub");
    return rejectedPromise(engine, "Not implemented");
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
  function createPublicKey(key) {
    var data = typeof key === 'string' ? key : (key && key.key ? (typeof key.key === 'string' ? key.key : key.key.toString()) : '');
    if (typeof data === 'string' && data.indexOf('-----BEGIN') !== 0) throw new TypeError('Invalid key data');
    return new KeyObject('public', typeof key === 'string' ? Buffer.from(key) : (key.key || key));
  }
  function createPrivateKey(key) {
    var data = typeof key === 'string' ? key : (key && key.key ? (typeof key.key === 'string' ? key.key : key.key.toString()) : '');
    if (typeof data === 'string' && data.indexOf('-----BEGIN') !== 0) throw new TypeError('Invalid key data');
    return new KeyObject('private', typeof key === 'string' ? Buffer.from(key) : (key.key || key));
  }

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
    subtle: webcrypto.subtle,
    getRandomValues: function(arr) { return webcrypto.getRandomValues(arr); }
  };
})();`;
}
