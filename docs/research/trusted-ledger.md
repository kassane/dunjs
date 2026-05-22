# DunJS `@trusted` ledger — public audit

**Auto-generated**: `ldc2 -run tools/gen_trusted_ledger.d`. Do not edit by hand.

This is DunJS's analogue of [bun.com/bun-unsafe-audit](https://bun.com/bun-unsafe-audit) — every `@trusted` block in the source tree, bucketed by reason. Adding new `@trusted` annotations should come with a doc-comment rationale (`/// ...`) on the line above; this ledger surfaces blocks that lack one.

## Summary

- **Total `@trusted` sites**: 1470
- **Categories**: 12
- **Generated**: ledger snapshot of `source/` tree at this commit.

| Category | Count | What it is |
|---|---:|---|
| `SIMD/hot-path` | 16 | `core.simd` + LDC intrinsics. Pointer arithmetic for codec hot paths. |
| `crypto-FFI` | 124 | OpenSSL FFI — `@trusted` is the security signal for crypto code. |
| `engine-FFI` | 252 | Backend bindings (QuickJS / JSC / V8). `extern(C)` + `JSValueRef` value handles. |
| `engine-bridge` | 4 | Helpers that bridge `void* ctx` callbacks to typed `DunState*`. |
| `event-loop` | 42 | Cross-platform I/O poller, timer wheel, async work queue. |
| `fs-IO` | 175 | POSIX file syscalls, child_process spawn / exec. |
| `hot-path` | 7 | `@nogc nothrow` hot paths where `@safe` would block needed operations. |
| `napi-FFI` | 22 | N-API bindings (Node-compatible native addons). |
| `network-IO` | 246 | POSIX socket syscalls, HTTP/HTTP2/WebSocket builtins, fetch. |
| `other` | 549 | Miscellaneous — review for re-categorization opportunities. |
| `quic-FFI` | 13 | lsquic / QUIC + HTTP/3. |
| `sqlite-FFI` | 20 | ImportC bindings to libsqlite3. |

## SIMD/hot-path (16 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/platform/simd.d:20`](../../source/dun/platform/simd.d#L20) | `private ubyte16 simdLoad(const(ubyte)* p) pure nothrow @nogc @trusted` | /// \`@trusted\`: LDC \`loadUnaligned\` is the documented, alignment-safe ///... |
| [`source/dun/platform/simd.d:29`](../../source/dun/platform/simd.d#L29) | `private void simdStore(ubyte* p, ubyte16 v) pure nothrow @nogc @trusted` | /// \`@trusted\`: LDC \`storeUnaligned\` is the documented, alignment-safe //... |
| [`source/dun/platform/simd.d:41`](../../source/dun/platform/simd.d#L41) | `private ubyte16 simdLoad(const(ubyte)* p) pure nothrow @nogc @trusted` | /// \`@trusted\`: pointer-cast SIMD load fallback. Same alignment + /// lengt... |
| [`source/dun/platform/simd.d:49`](../../source/dun/platform/simd.d#L49) | `private void simdStore(ubyte* p, ubyte16 v) pure nothrow @nogc @trusted` | /// \`@trusted\`: pointer-cast SIMD store fallback. Same contract as /// the ... |
| [`source/dun/platform/simd.d:60`](../../source/dun/platform/simd.d#L60) | `private ubyte16 splat(ubyte val) pure nothrow @nogc @trusted` | /// \`@trusted\`: splat scalar to 16-byte vector via stack-array cast. /// \`... |
| [`source/dun/platform/simd.d:70`](../../source/dun/platform/simd.d#L70) | `ubyte16 toLower16(ubyte16 v) pure nothrow @nogc @trusted` | /// \`@trusted\`: pure ALU on a register. The \`cast(ubyte16)\` from a /// bo... |
| [`source/dun/platform/simd.d:78`](../../source/dun/platform/simd.d#L78) | `ubyte16 toUpper16(ubyte16 v) pure nothrow @nogc @trusted` | /// \`@trusted\`: pure ALU on a register; same justification as \`toLower16\`. |
| [`source/dun/platform/simd.d:88`](../../source/dun/platform/simd.d#L88) | `ubyte16 nibblesToHex16(ubyte16 nibbles) pure nothrow @nogc @trusted` | /// \`@trusted\`: pure ALU on a register. Each lane of \`nibbles\` is in /// ... |
| [`source/dun/platform/simd.d:99`](../../source/dun/platform/simd.d#L99) | `void asciiToLowerBuf(char[] buf) pure nothrow @nogc @trusted` | /// \`@trusted\`: 16-byte SIMD lowercase loop + scalar tail. The SIMD /// str... |
| [`source/dun/platform/simd.d:116`](../../source/dun/platform/simd.d#L116) | `void hexEncodeBuf(const(ubyte)[] src, char[] dst) pure nothrow @nogc @trusted` | /// \`@trusted\`: 16-byte SIMD hex encoder + scalar tail. The SIMD stride ///... |
| [`source/dun/platform/simd.d:163`](../../source/dun/platform/simd.d#L163) | `size_t findByte(const(ubyte)[] buf, ubyte needle) pure nothrow @nogc @trusted` | /// \`@trusted\`: SIMD byte search with \`llvm_cttz\` for O(1) first-match //... |
| [`source/dun/platform/simd.d:198`](../../source/dun/platform/simd.d#L198) | `void prefetchRead(const(void)* ptr) pure nothrow @nogc @trusted` | /// \`@trusted\`: LDC \`llvm_prefetch\` is a CPU hint that never reads or ///... |
| [`source/dun/platform/simd.d:217`](../../source/dun/platform/simd.d#L217) | `void hexEncodeBuf(const(ubyte)[] src, char[] dst) pure nothrow @nogc @trusted` | /// \`@trusted\`: scalar hex encode fallback (no D_SIMD support). The /// dst... |
| [`source/dun/platform/simd.d:322`](../../source/dun/platform/simd.d#L322) | `pure nothrow @nogc @trusted` | /// Encode a Latin-1 (ISO-8859-1) byte sequence into a UTF-8 byte /// sequenc... |
| [`source/dun/platform/simd.d:348`](../../source/dun/platform/simd.d#L348) | `pure nothrow @nogc @trusted` | /// Decode a UTF-8 byte sequence (assumed valid for Latin-1 round-trip /// �... |
| [`source/dun/platform/simd.d:400`](../../source/dun/platform/simd.d#L400) | `pure nothrow @nogc @trusted` | /// Compile-time-sized variant: stack-allocates the destination so /// caller... |

## crypto-FFI (124 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/crypto.d:181`](../../source/dun/builtins/crypto.d#L181) | `private const(EVP_MD)* getEvpMd(string algo) @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/crypto.d:206`](../../source/dun/builtins/crypto.d#L206) | `auto lower = (() @trusted => cast(string) buf[0 .. algo.length])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:230`](../../source/dun/builtins/crypto.d#L230) | `void registerCryptoModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:286`](../../source/dun/builtins/crypto.d#L286) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:315`](../../source/dun/builtins/crypto.d#L315) | `private extern (C) int cryptoModuleInit(JSContext* ctx, JSModuleDef* m) nothr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:333`](../../source/dun/builtins/crypto.d#L333) | `JSHandle jsCryptoRandomUUID(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:361`](../../source/dun/builtins/crypto.d#L361) | `JSHandle jsCryptoRandomBytes(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:387`](../../source/dun/builtins/crypto.d#L387) | `void fillRandomBytesPublic(ubyte[] buf) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:400`](../../source/dun/builtins/crypto.d#L400) | `ubyte[16] nextUUIDBytes() @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:416`](../../source/dun/builtins/crypto.d#L416) | `private void fillRandomBytes(ubyte[] buf) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:467`](../../source/dun/builtins/crypto.d#L467) | `JSHandle jsCryptoCreateHash(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:504`](../../source/dun/builtins/crypto.d#L504) | `JSHandle jsHashUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:548`](../../source/dun/builtins/crypto.d#L548) | `JSHandle jsHashDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:581`](../../source/dun/builtins/crypto.d#L581) | `return engine.newString((() @trusted => cast(string) Base64.encode(result))());` | _(missing)_ |
| [`source/dun/builtins/crypto.d:607`](../../source/dun/builtins/crypto.d#L607) | `JSHandle jsCryptoCreateHmac(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:690`](../../source/dun/builtins/crypto.d#L690) | `JSHandle jsHmacUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:726`](../../source/dun/builtins/crypto.d#L726) | `JSHandle jsHmacDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:766`](../../source/dun/builtins/crypto.d#L766) | `return engine.newString((() @trusted => cast(string) Base64.encode(result))());` | _(missing)_ |
| [`source/dun/builtins/crypto.d:782`](../../source/dun/builtins/crypto.d#L782) | `JSHandle jsCryptoTimingSafeEqual(void* ctx, JSHandle thisVal, scope JSHandle[...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:803`](../../source/dun/builtins/crypto.d#L803) | `private const(ubyte)[] extractArgBytes(IJSEngine engine, JSHandle arg) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:824`](../../source/dun/builtins/crypto.d#L824) | `JSHandle jsCryptoRandomInt(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:859`](../../source/dun/builtins/crypto.d#L859) | `JSHandle jsCryptoPbkdf2Sync(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:898`](../../source/dun/builtins/crypto.d#L898) | `JSHandle jsCryptoScryptSync(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:950`](../../source/dun/builtins/crypto.d#L950) | `private const(EVP_CIPHER)* getEvpCipher(string algo) @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/crypto.d:996`](../../source/dun/builtins/crypto.d#L996) | `private void ensureCipherFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1008`](../../source/dun/builtins/crypto.d#L1008) | `JSHandle jsCryptoCreateCipheriv(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1057`](../../source/dun/builtins/crypto.d#L1057) | `JSHandle jsCipherUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1143`](../../source/dun/builtins/crypto.d#L1143) | `JSHandle jsCipherFinal(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1203`](../../source/dun/builtins/crypto.d#L1203) | `JSHandle jsCipherGetAuthTag(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1218`](../../source/dun/builtins/crypto.d#L1218) | `JSHandle jsCryptoCreateDecipheriv(void* ctx, JSHandle thisVal, scope JSHandle...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1267`](../../source/dun/builtins/crypto.d#L1267) | `JSHandle jsDecipherUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1337`](../../source/dun/builtins/crypto.d#L1337) | `JSHandle jsDecipherFinal(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1380`](../../source/dun/builtins/crypto.d#L1380) | `JSHandle jsDecipherSetAuthTag(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1419`](../../source/dun/builtins/crypto.d#L1419) | `private ubyte[] extractCryptoBytes(IJSEngine engine, JSHandle arg) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1447`](../../source/dun/builtins/crypto.d#L1447) | `private void ensureSignFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1457`](../../source/dun/builtins/crypto.d#L1457) | `JSHandle jsCryptoCreateSign(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1477`](../../source/dun/builtins/crypto.d#L1477) | `JSHandle jsSignUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1495`](../../source/dun/builtins/crypto.d#L1495) | `JSHandle jsSignSign(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1540`](../../source/dun/builtins/crypto.d#L1540) | `JSHandle jsCryptoCreateVerify(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1560`](../../source/dun/builtins/crypto.d#L1560) | `JSHandle jsVerifyUpdate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1578`](../../source/dun/builtins/crypto.d#L1578) | `JSHandle jsVerifyVerify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1629`](../../source/dun/builtins/crypto.d#L1629) | `private ubyte[] evpSign(string algo, string pemKey, string data) @trusted not...` | /// Sign data using OpenSSL EVP_DigestSign |
| [`source/dun/builtins/crypto.d:1670`](../../source/dun/builtins/crypto.d#L1670) | `private bool evpVerify(string algo, string pemKey, string data, const(ubyte)[...` | /// Verify signature using OpenSSL EVP_DigestVerify |
| [`source/dun/builtins/crypto.d:1699`](../../source/dun/builtins/crypto.d#L1699) | `private JSHandle encodeOutput(IJSEngine engine, const(ubyte)[] data, string e...` | /// Encode binary data to the requested output encoding |
| [`source/dun/builtins/crypto.d:1720`](../../source/dun/builtins/crypto.d#L1720) | `private ubyte[] decodeInput(string input, string encoding) @trusted` | /// Decode input string from the given encoding to bytes |
| [`source/dun/builtins/crypto.d:1761`](../../source/dun/builtins/crypto.d#L1761) | `JSHandle jsCryptoGetHashes(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1775`](../../source/dun/builtins/crypto.d#L1775) | `JSHandle jsCryptoGetCiphers(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1796`](../../source/dun/builtins/crypto.d#L1796) | `private ubyte[] osRandomBytes(int n) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1820`](../../source/dun/builtins/crypto.d#L1820) | `private ubyte[] computeHashBinary(string algo, const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1855`](../../source/dun/builtins/crypto.d#L1855) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1866`](../../source/dun/builtins/crypto.d#L1866) | `return (() @trusted => cast(string) Base64URLNoPadding.encode(data))();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1869`](../../source/dun/builtins/crypto.d#L1869) | `private ubyte[] computeHmacBinary(string algo, const(ubyte)[] key, const(ubyt...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:1889`](../../source/dun/builtins/crypto.d#L1889) | `private string bioToString(BIO* bio) @trusted nothrow` | /// Read all pending data from a BIO into a D string |
| [`source/dun/builtins/crypto.d:1907`](../../source/dun/builtins/crypto.d#L1907) | `out string publicKeyPEM, out string privateKeyPEM) @trusted nothrow` | /// Generate an RSA or EC key pair via OpenSSL, returns (publicKeyPEM, privat... |
| [`source/dun/builtins/crypto.d:1969`](../../source/dun/builtins/crypto.d#L1969) | `JSHandle jsCryptoGenerateKeyPairSync(void* ctx, JSHandle thisVal, scope JSHan...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2025`](../../source/dun/builtins/crypto.d#L2025) | `private void ensureDHFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2038`](../../source/dun/builtins/crypto.d#L2038) | `private string bnToHex(const(BIGNUM)* bn) @trusted nothrow` | /// Encode a BIGNUM to hex string |
| [`source/dun/builtins/crypto.d:2055`](../../source/dun/builtins/crypto.d#L2055) | `JSHandle jsCryptoCreateDiffieHellman(void* ctx, JSHandle thisVal, scope JSHan...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2092`](../../source/dun/builtins/crypto.d#L2092) | `private DH* extractDH(IJSEngine engine, JSHandle thisVal) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2100`](../../source/dun/builtins/crypto.d#L2100) | `JSHandle jsDHGenerateKeys(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2115`](../../source/dun/builtins/crypto.d#L2115) | `JSHandle jsDHGetPublicKey(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2127`](../../source/dun/builtins/crypto.d#L2127) | `JSHandle jsDHGetPrivateKey(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2139`](../../source/dun/builtins/crypto.d#L2139) | `JSHandle jsDHComputeSecret(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2176`](../../source/dun/builtins/crypto.d#L2176) | `JSHandle jsDHGetPrime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2188`](../../source/dun/builtins/crypto.d#L2188) | `JSHandle jsDHGetGenerator(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2216`](../../source/dun/builtins/crypto.d#L2216) | `private void ensureSubtleFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2233`](../../source/dun/builtins/crypto.d#L2233) | `void installNativeSubtle(IJSEngine engine, JSHandle cryptoObj) @trusted` | /// Install native subtle object on the crypto module and webcrypto property |
| [`source/dun/builtins/crypto.d:2267`](../../source/dun/builtins/crypto.d#L2267) | `public void installSubtleOnGlobalCrypto(IJSEngine engine) @trusted` | /// Install subtle on the global crypto object (called from web_apis.d) |
| [`source/dun/builtins/crypto.d:2301`](../../source/dun/builtins/crypto.d#L2301) | `private string normalizeSubtleAlgo(IJSEngine engine, JSHandle algoArg) @trusted` | /// Normalize WebCrypto algorithm name to OpenSSL-compatible name /// Accepts... |
| [`source/dun/builtins/crypto.d:2328`](../../source/dun/builtins/crypto.d#L2328) | `auto lower = (() @trusted => cast(string) buf[0 .. pos])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2339`](../../source/dun/builtins/crypto.d#L2339) | `private string extractHmacHash(IJSEngine engine, JSHandle algoArg) @trusted` | /// Extract the HMAC hash algorithm from a WebCrypto algorithm descriptor ///... |
| [`source/dun/builtins/crypto.d:2355`](../../source/dun/builtins/crypto.d#L2355) | `private string extractAlgoName(IJSEngine engine, JSHandle algoArg) @trusted` | /// Extract algorithm name from a WebCrypto algorithm descriptor |
| [`source/dun/builtins/crypto.d:2372`](../../source/dun/builtins/crypto.d#L2372) | `private ubyte[] extractDataArg(IJSEngine engine, JSHandle arg) @trusted` | /// Extract data from a JS argument: TypedArray, ArrayBuffer, or string /// R... |
| [`source/dun/builtins/crypto.d:2397`](../../source/dun/builtins/crypto.d#L2397) | `private JSHandle resolvedPromise(IJSEngine engine, JSHandle value) @trusted` | /// Helper: create a resolved promise wrapping a value |
| [`source/dun/builtins/crypto.d:2412`](../../source/dun/builtins/crypto.d#L2412) | `private JSHandle rejectedPromise(IJSEngine engine, string msg) @trusted` | /// Helper: create a rejected promise with an error message |
| [`source/dun/builtins/crypto.d:2448`](../../source/dun/builtins/crypto.d#L2448) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2453`](../../source/dun/builtins/crypto.d#L2453) | `JSHandle jsSubtleDigest(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2493`](../../source/dun/builtins/crypto.d#L2493) | `JSHandle jsSubtleImportKey(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2523`](../../source/dun/builtins/crypto.d#L2523) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2571`](../../source/dun/builtins/crypto.d#L2571) | `JSHandle jsSubtleSign(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2593`](../../source/dun/builtins/crypto.d#L2593) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2645`](../../source/dun/builtins/crypto.d#L2645) | `JSHandle jsSubtleVerify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2667`](../../source/dun/builtins/crypto.d#L2667) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2728`](../../source/dun/builtins/crypto.d#L2728) | `JSHandle jsSubtleEncrypt(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2750`](../../source/dun/builtins/crypto.d#L2750) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2762`](../../source/dun/builtins/crypto.d#L2762) | `JSHandle jsSubtleDecrypt(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2783`](../../source/dun/builtins/crypto.d#L2783) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2794`](../../source/dun/builtins/crypto.d#L2794) | `private JSHandle subtleAesGcmEncrypt(IJSEngine engine, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2869`](../../source/dun/builtins/crypto.d#L2869) | `private JSHandle subtleAesGcmDecrypt(IJSEngine engine, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2936`](../../source/dun/builtins/crypto.d#L2936) | `private JSHandle subtleAesCbcEncrypt(IJSEngine engine, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:2992`](../../source/dun/builtins/crypto.d#L2992) | `private JSHandle subtleAesCbcDecrypt(IJSEngine engine, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3045`](../../source/dun/builtins/crypto.d#L3045) | `JSHandle jsSubtleGenerateKey(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3066`](../../source/dun/builtins/crypto.d#L3066) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3135`](../../source/dun/builtins/crypto.d#L3135) | `JSHandle jsSubtleExportKey(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3166`](../../source/dun/builtins/crypto.d#L3166) | `JSHandle jsSubtleDeriveBits(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3187`](../../source/dun/builtins/crypto.d#L3187) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3310`](../../source/dun/builtins/crypto.d#L3310) | `JSHandle jsSubtleDeriveKey(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3355`](../../source/dun/builtins/crypto.d#L3355) | `auto upperName = (() @trusted => cast(string) nameBuf[0 .. nameLen])();` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3411`](../../source/dun/builtins/crypto.d#L3411) | `engine.setProperty(derivedAlgo, "name", engine.newString((() @trusted => cast...` | _(missing)_ |
| [`source/dun/builtins/crypto.d:3422`](../../source/dun/builtins/crypto.d#L3422) | `JSHandle jsSubtleNotImplemented(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/builtins/tls.d:10`](../../source/dun/builtins/tls.d#L10) | `void ensureTlsInit() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:34`](../../source/dun/builtins/tls.d#L34) | `bool connect(int sockFd, const(char)* hostname) @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:57`](../../source/dun/builtins/tls.d#L57) | `int read(void* buf, int len) @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:63`](../../source/dun/builtins/tls.d#L63) | `int write(const(void)* buf, int len) @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:69`](../../source/dun/builtins/tls.d#L69) | `void close() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:85`](../../source/dun/builtins/tls.d#L85) | `~this() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/tls.d:91`](../../source/dun/builtins/tls.d#L91) | `string tlsLastError() @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/tls.d:116`](../../source/dun/builtins/tls.d#L116) | `void registerTlsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:158`](../../source/dun/builtins/tls.d#L158) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:172`](../../source/dun/builtins/tls.d#L172) | `private extern (C) int tlsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/tls.d:220`](../../source/dun/builtins/tls.d#L220) | `private void ensureTlsPoller() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:226`](../../source/dun/builtins/tls.d#L226) | `void registerTlsForPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:236`](../../source/dun/builtins/tls.d#L236) | `void unregisterTlsFromPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:247`](../../source/dun/builtins/tls.d#L247) | `public void pollTlsIO() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:264`](../../source/dun/builtins/tls.d#L264) | `public bool hasActiveTlsIO() @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/tls.d:273`](../../source/dun/builtins/tls.d#L273) | `void readTlsData(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:310`](../../source/dun/builtins/tls.d#L310) | `void closeTlsConn(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:351`](../../source/dun/builtins/tls.d#L351) | `void freeTlsCallbacks(TlsConnState* conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:371`](../../source/dun/builtins/tls.d#L371) | `JSHandle jsTlsConnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/tls.d:616`](../../source/dun/builtins/tls.d#L616) | `JSHandle jsTlsWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:652`](../../source/dun/builtins/tls.d#L652) | `JSHandle jsTlsEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:667`](../../source/dun/builtins/tls.d#L667) | `JSHandle jsTlsDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/tls.d:701`](../../source/dun/builtins/tls.d#L701) | `JSHandle jsTlsOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/tls.d:733`](../../source/dun/builtins/tls.d#L733) | `JSHandle jsTlsGetCiphers(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |

## engine-FFI (252 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/engine/jsc/backend.d:18`](../../source/dun/engine/jsc/backend.d#L18) | `void initialize(EngineConfig config) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:35`](../../source/dun/engine/jsc/backend.d#L35) | `void shutdown() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:50`](../../source/dun/engine/jsc/backend.d#L50) | `JSResult eval(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:85`](../../source/dun/engine/jsc/backend.d#L85) | `JSHandle newUndefined() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:91`](../../source/dun/engine/jsc/backend.d#L91) | `JSHandle newNull() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:112`](../../source/dun/engine/jsc/backend.d#L112) | `private JSStringRef createJSStringFromD(scope const(char)[] s) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:202`](../../source/dun/engine/jsc/backend.d#L202) | `JSHandle newString(scope const(char)[] s) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:213`](../../source/dun/engine/jsc/backend.d#L213) | `JSHandle newInt(int v) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:219`](../../source/dun/engine/jsc/backend.d#L219) | `JSHandle newFloat(double v) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:225`](../../source/dun/engine/jsc/backend.d#L225) | `JSHandle newBool(bool v) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:231`](../../source/dun/engine/jsc/backend.d#L231) | `JSHandle newObject() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:237`](../../source/dun/engine/jsc/backend.d#L237) | `JSHandle newArray() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:243`](../../source/dun/engine/jsc/backend.d#L243) | `JSHandle newUint8Array(scope const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:263`](../../source/dun/engine/jsc/backend.d#L263) | `JSHandle newUint8ArrayZeroed(size_t length) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:275`](../../source/dun/engine/jsc/backend.d#L275) | `private void ensureUint8ArrayCtor() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:288`](../../source/dun/engine/jsc/backend.d#L288) | `ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:303`](../../source/dun/engine/jsc/backend.d#L303) | `JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:328`](../../source/dun/engine/jsc/backend.d#L328) | `string extractString(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:334`](../../source/dun/engine/jsc/backend.d#L334) | `int extractInt(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:343`](../../source/dun/engine/jsc/backend.d#L343) | `double extractFloat(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:352`](../../source/dun/engine/jsc/backend.d#L352) | `bool extractBool(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:360`](../../source/dun/engine/jsc/backend.d#L360) | `const(char)[] name, return ref char[STACK_TERM_SIZE] buf) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:371`](../../source/dun/engine/jsc/backend.d#L371) | `JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:384`](../../source/dun/engine/jsc/backend.d#L384) | `void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:396`](../../source/dun/engine/jsc/backend.d#L396) | `void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:406`](../../source/dun/engine/jsc/backend.d#L406) | `void setPrototype(JSHandle obj, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:413`](../../source/dun/engine/jsc/backend.d#L413) | `JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool z...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:426`](../../source/dun/engine/jsc/backend.d#L426) | `JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:433`](../../source/dun/engine/jsc/backend.d#L433) | `JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:440`](../../source/dun/engine/jsc/backend.d#L440) | `size_t totalLen, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:448`](../../source/dun/engine/jsc/backend.d#L448) | `void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:456`](../../source/dun/engine/jsc/backend.d#L456) | `JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:465`](../../source/dun/engine/jsc/backend.d#L465) | `bool isArray(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:473`](../../source/dun/engine/jsc/backend.d#L473) | `private static JSStringRef getLengthStr() nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:480`](../../source/dun/engine/jsc/backend.d#L480) | `int getArrayLength(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:493`](../../source/dun/engine/jsc/backend.d#L493) | `JSHandle getGlobal() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:499`](../../source/dun/engine/jsc/backend.d#L499) | `JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:549`](../../source/dun/engine/jsc/backend.d#L549) | `JSHandle dupValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:557`](../../source/dun/engine/jsc/backend.d#L557) | `void freeValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:569`](../../source/dun/engine/jsc/backend.d#L569) | `private bool checkType(JSCTypeTag tag, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:577`](../../source/dun/engine/jsc/backend.d#L577) | `bool isUndefined(JSHandle val) @trusted { return checkType(JSCTypeTag.Undefin...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:578`](../../source/dun/engine/jsc/backend.d#L578) | `bool isNull(JSHandle val) @trusted { return checkType(JSCTypeTag.Null, val); }` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:579`](../../source/dun/engine/jsc/backend.d#L579) | `bool isString(JSHandle val) @trusted { return checkType(JSCTypeTag.String, va...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:580`](../../source/dun/engine/jsc/backend.d#L580) | `bool isObject(JSHandle val) @trusted { return checkType(JSCTypeTag.Object, va...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:581`](../../source/dun/engine/jsc/backend.d#L581) | `bool isFunction(JSHandle val) @trusted { return checkType(JSCTypeTag.Function...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:582`](../../source/dun/engine/jsc/backend.d#L582) | `bool isBool(JSHandle val) @trusted { return checkType(JSCTypeTag.Boolean, val...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:583`](../../source/dun/engine/jsc/backend.d#L583) | `bool isNumber(JSHandle val) @trusted { return checkType(JSCTypeTag.Number, va...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:590`](../../source/dun/engine/jsc/backend.d#L590) | `JSHandle throwTypeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:601`](../../source/dun/engine/jsc/backend.d#L601) | `JSHandle throwRangeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:620`](../../source/dun/engine/jsc/backend.d#L620) | `JSHandle throwValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:627`](../../source/dun/engine/jsc/backend.d#L627) | `PromiseHandles newPromise() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:653`](../../source/dun/engine/jsc/backend.d#L653) | `void setContextOpaque(void* ptr) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:660`](../../source/dun/engine/jsc/backend.d#L660) | `void* getContextOpaque() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:667`](../../source/dun/engine/jsc/backend.d#L667) | `JSResult evalModule(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:687`](../../source/dun/engine/jsc/backend.d#L687) | `void registerNativeModule(string name, void* initFunc) @trusted {}` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:692`](../../source/dun/engine/jsc/backend.d#L692) | `void collectGarbage() @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:699`](../../source/dun/engine/jsc/backend.d#L699) | `void* rawContext() @trusted { return cast(void*) ctx; }` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:703`](../../source/dun/engine/jsc/backend.d#L703) | `void registerJSCFunction(string name, JSObjectCallAsFunctionCallback cb) @tru...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:717`](../../source/dun/engine/jsc/backend.d#L717) | `private string jscStringToD(JSValueRef val) @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:749`](../../source/dun/engine/jsc/backend.d#L749) | `static JSHandle toHandle(void* ptr) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:756`](../../source/dun/engine/jsc/backend.d#L756) | `static void* fromHandle(JSHandle h) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:765`](../../source/dun/engine/jsc/backend.d#L765) | `private JSStringRef getCbSlotStr() nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:775`](../../source/dun/engine/jsc/backend.d#L775) | `JSValueRef* exception) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:867`](../../source/dun/engine/jsc/backend.d#L867) | `package void jscSetContextOpaque(JSGlobalContextRef ctx, void* ptr) nothrow @...` | _(missing)_ |
| [`source/dun/engine/jsc/backend.d:875`](../../source/dun/engine/jsc/backend.d#L875) | `package void* jscGetContextOpaque(JSGlobalContextRef ctx) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/jsc/cppbindings.d:57`](../../source/dun/engine/jsc/cppbindings.d#L57) | `static JSCTypeChecks create() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/engine/jsc/cppbindings.d:73`](../../source/dun/engine/jsc/cppbindings.d#L73) | `bool check(JSCTypeTag tag, JSContextRef ctx, JSValueRef val) @trusted nothrow...` | /// Function tag needs JSObjectIsFunction (not in JSValueGetType). |
| [`source/dun/engine/jsc/cppbindings.d:89`](../../source/dun/engine/jsc/cppbindings.d#L89) | `static JSCTypeTag getType(JSContextRef ctx, JSValueRef val) @trusted nothrow ...` | /// Single JSValueGetType() call — basic types only (not Array/Function/Date). |
| [`source/dun/engine/jsc/cppbindings.d:95`](../../source/dun/engine/jsc/cppbindings.d#L95) | `static string typeofString(JSContextRef ctx, JSValueRef val) @trusted nothrow` | /// JS typeof semantics. |
| [`source/dun/engine/quickjs/backend.d:13`](../../source/dun/engine/quickjs/backend.d#L13) | `void initialize(EngineConfig config) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:29`](../../source/dun/engine/quickjs/backend.d#L29) | `void shutdown() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:43`](../../source/dun/engine/quickjs/backend.d#L43) | `JSResult eval(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:59`](../../source/dun/engine/quickjs/backend.d#L59) | `JSHandle newUndefined() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:65`](../../source/dun/engine/quickjs/backend.d#L65) | `JSHandle newNull() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:71`](../../source/dun/engine/quickjs/backend.d#L71) | `JSHandle newString(scope const(char)[] s) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:77`](../../source/dun/engine/quickjs/backend.d#L77) | `JSHandle newInt(int v) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:83`](../../source/dun/engine/quickjs/backend.d#L83) | `JSHandle newFloat(double v) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:89`](../../source/dun/engine/quickjs/backend.d#L89) | `JSHandle newBool(bool v) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:95`](../../source/dun/engine/quickjs/backend.d#L95) | `JSHandle newObject() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:101`](../../source/dun/engine/quickjs/backend.d#L101) | `JSHandle newArray() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:107`](../../source/dun/engine/quickjs/backend.d#L107) | `JSHandle newUint8Array(scope const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:122`](../../source/dun/engine/quickjs/backend.d#L122) | `JSHandle newUint8ArrayZeroed(size_t length) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:135`](../../source/dun/engine/quickjs/backend.d#L135) | `ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:150`](../../source/dun/engine/quickjs/backend.d#L150) | `JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:161`](../../source/dun/engine/quickjs/backend.d#L161) | `string extractString(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:174`](../../source/dun/engine/quickjs/backend.d#L174) | `int extractInt(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:183`](../../source/dun/engine/quickjs/backend.d#L183) | `double extractFloat(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:192`](../../source/dun/engine/quickjs/backend.d#L192) | `bool extractBool(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:198`](../../source/dun/engine/quickjs/backend.d#L198) | `JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:206`](../../source/dun/engine/quickjs/backend.d#L206) | `void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:214`](../../source/dun/engine/quickjs/backend.d#L214) | `void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:226`](../../source/dun/engine/quickjs/backend.d#L226) | `void setPrototype(JSHandle obj, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:232`](../../source/dun/engine/quickjs/backend.d#L232) | `JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool z...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:245`](../../source/dun/engine/quickjs/backend.d#L245) | `JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:252`](../../source/dun/engine/quickjs/backend.d#L252) | `JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:260`](../../source/dun/engine/quickjs/backend.d#L260) | `size_t totalLen, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:268`](../../source/dun/engine/quickjs/backend.d#L268) | `void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:274`](../../source/dun/engine/quickjs/backend.d#L274) | `JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:280`](../../source/dun/engine/quickjs/backend.d#L280) | `bool isArray(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:285`](../../source/dun/engine/quickjs/backend.d#L285) | `int getArrayLength(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:293`](../../source/dun/engine/quickjs/backend.d#L293) | `JSHandle getGlobal() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:299`](../../source/dun/engine/quickjs/backend.d#L299) | `JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:325`](../../source/dun/engine/quickjs/backend.d#L325) | `JSHandle dupValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:331`](../../source/dun/engine/quickjs/backend.d#L331) | `void freeValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:337`](../../source/dun/engine/quickjs/backend.d#L337) | `bool isException(JSHandle val) @trusted { return JS_IsException(fromHandle(va...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:338`](../../source/dun/engine/quickjs/backend.d#L338) | `bool isUndefined(JSHandle val) @trusted { return JS_IsUndefined(fromHandle(va...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:339`](../../source/dun/engine/quickjs/backend.d#L339) | `bool isNull(JSHandle val) @trusted { return JS_IsNull(fromHandle(val)) != 0; }` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:340`](../../source/dun/engine/quickjs/backend.d#L340) | `bool isString(JSHandle val) @trusted { return JS_IsString(fromHandle(val)) !=...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:341`](../../source/dun/engine/quickjs/backend.d#L341) | `bool isObject(JSHandle val) @trusted { return JS_IsObject(fromHandle(val)) !=...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:342`](../../source/dun/engine/quickjs/backend.d#L342) | `bool isFunction(JSHandle val) @trusted { return JS_IsFunction(ctx, fromHandle...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:343`](../../source/dun/engine/quickjs/backend.d#L343) | `bool isBool(JSHandle val) @trusted { return JS_IsBool(fromHandle(val)) != 0; }` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:344`](../../source/dun/engine/quickjs/backend.d#L344) | `bool isNumber(JSHandle val) @trusted { return JS_IsNumber(fromHandle(val)) !=...` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:346`](../../source/dun/engine/quickjs/backend.d#L346) | `string getException() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:352`](../../source/dun/engine/quickjs/backend.d#L352) | `JSHandle throwTypeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:358`](../../source/dun/engine/quickjs/backend.d#L358) | `JSHandle throwRangeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:364`](../../source/dun/engine/quickjs/backend.d#L364) | `JSHandle throwValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:370`](../../source/dun/engine/quickjs/backend.d#L370) | `PromiseHandles newPromise() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:389`](../../source/dun/engine/quickjs/backend.d#L389) | `bool hasPendingJobs() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:395`](../../source/dun/engine/quickjs/backend.d#L395) | `bool executePendingJob() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:408`](../../source/dun/engine/quickjs/backend.d#L408) | `void setContextOpaque(void* ptr) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:414`](../../source/dun/engine/quickjs/backend.d#L414) | `void* getContextOpaque() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:422`](../../source/dun/engine/quickjs/backend.d#L422) | `JSResult evalModule(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:493`](../../source/dun/engine/quickjs/backend.d#L493) | `void registerNativeModule(string name, void* initFunc) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:500`](../../source/dun/engine/quickjs/backend.d#L500) | `void setMemoryLimit(size_t bytes) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:507`](../../source/dun/engine/quickjs/backend.d#L507) | `void setMaxStackSize(size_t bytes) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:514`](../../source/dun/engine/quickjs/backend.d#L514) | `void collectGarbage() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:520`](../../source/dun/engine/quickjs/backend.d#L520) | `void* rawRuntime() @trusted { return cast(void*) rt; }` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:521`](../../source/dun/engine/quickjs/backend.d#L521) | `void* rawContext() @trusted { return cast(void*) ctx; }` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:525`](../../source/dun/engine/quickjs/backend.d#L525) | `void registerCFunction(string name, JSCFunction func, int argc) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:537`](../../source/dun/engine/quickjs/backend.d#L537) | `const(char)[] name, return ref char[QJS_STACK_STRING_SIZE] buf) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:548`](../../source/dun/engine/quickjs/backend.d#L548) | `static JSHandle toHandle(JSValue v) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:556`](../../source/dun/engine/quickjs/backend.d#L556) | `static JSValue fromHandle(JSHandle h) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/backend.d:564`](../../source/dun/engine/quickjs/backend.d#L564) | `int magic) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/bindings.d:118`](../../source/dun/engine/quickjs/bindings.d#L118) | `const(char)* name, int length) nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/bindings.d:329`](../../source/dun/engine/quickjs/bindings.d#L329) | `int JS_ToUint32(JSContext* ctx, uint* pres, JSValueConst val) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/context.d:16`](../../source/dun/engine/quickjs/context.d#L16) | `static Context create(ref Runtime rt) @trusted` | /// Create a new context bound to the given runtime. |
| [`source/dun/engine/quickjs/context.d:23`](../../source/dun/engine/quickjs/context.d#L23) | `~this() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/context.d:31`](../../source/dun/engine/quickjs/context.d#L31) | `int flags = JS_EVAL_TYPE_GLOBAL) @trusted` | /// Evaluate JavaScript source code. Returns a managed JSVal. |
| [`source/dun/engine/quickjs/context.d:42`](../../source/dun/engine/quickjs/context.d#L42) | `JSVal globalObject() @trusted` | /// Get the global object. |
| [`source/dun/engine/quickjs/context.d:48`](../../source/dun/engine/quickjs/context.d#L48) | `void setGlobalFunction(string name, JSCFunction func, int argCount = 0) @trusted` | /// Register a D function as a global JS function. |
| [`source/dun/engine/quickjs/context.d:59`](../../source/dun/engine/quickjs/context.d#L59) | `string getException() @trusted` | /// Get the last exception as a D string. |
| [`source/dun/engine/quickjs/context.d:75`](../../source/dun/engine/quickjs/context.d#L75) | `void setOpaque(void* ptr) @trusted` | /// Store an opaque pointer in the context. |
| [`source/dun/engine/quickjs/context.d:81`](../../source/dun/engine/quickjs/context.d#L81) | `void* getOpaque() @trusted` | /// Retrieve the opaque pointer from the context. |
| [`source/dun/engine/quickjs/context.d:87`](../../source/dun/engine/quickjs/context.d#L87) | `JSContext* handle() @trusted` | /// Access the raw JSContext pointer. |
| [`source/dun/engine/quickjs/exceptions.d:8`](../../source/dun/engine/quickjs/exceptions.d#L8) | `string extractException(JSContext* ctx) @trusted` | /// Extract the current exception from a context as a D string. /// Clears th... |
| [`source/dun/engine/quickjs/exceptions.d:43`](../../source/dun/engine/quickjs/exceptions.d#L43) | `string extractExceptionWithStack(JSContext* ctx) @trusted` | /// Extract exception with stack trace as a D string. |
| [`source/dun/engine/quickjs/function_bind.d:7`](../../source/dun/engine/quickjs/function_bind.d#L7) | `JSValue toJSValue(JSContext* ctx, string s) @trusted nothrow` | /// Convert a D string to a JS string value. |
| [`source/dun/engine/quickjs/function_bind.d:17`](../../source/dun/engine/quickjs/function_bind.d#L17) | `string jsArgToString(JSContext* ctx, JSValueConst val) nothrow @trusted` | /// Convert a JS value argument to a D string. /// Returns empty string on fa... |
| [`source/dun/engine/quickjs/function_bind.d:30`](../../source/dun/engine/quickjs/function_bind.d#L30) | `int jsArgToInt32(JSContext* ctx, JSValueConst val) @trusted nothrow` | /// Convert a JS value argument to int32. |
| [`source/dun/engine/quickjs/function_bind.d:39`](../../source/dun/engine/quickjs/function_bind.d#L39) | `double jsArgToFloat64(JSContext* ctx, JSValueConst val) @trusted nothrow` | /// Convert a JS value argument to float64. |
| [`source/dun/engine/quickjs/function_bind.d:48`](../../source/dun/engine/quickjs/function_bind.d#L48) | `JSValue toJSInt(JSContext* ctx, int v) @trusted nothrow` | /// Create a JS number from an int. |
| [`source/dun/engine/quickjs/function_bind.d:54`](../../source/dun/engine/quickjs/function_bind.d#L54) | `JSValue toJSFloat(JSContext* ctx, double v) @trusted nothrow` | /// Create a JS number from a double. |
| [`source/dun/engine/quickjs/function_bind.d:60`](../../source/dun/engine/quickjs/function_bind.d#L60) | `JSValue toJSBool(JSContext* ctx, bool v) @trusted nothrow` | /// Create a JS boolean. |
| [`source/dun/engine/quickjs/runtime.d:14`](../../source/dun/engine/quickjs/runtime.d#L14) | `static Runtime create() @trusted` | /// Create a new QuickJS runtime with default allocator. |
| [`source/dun/engine/quickjs/runtime.d:22`](../../source/dun/engine/quickjs/runtime.d#L22) | `static Runtime create(const(JSMallocFunctions)* mf) @trusted` | /// Create a new QuickJS runtime with custom malloc functions. |
| [`source/dun/engine/quickjs/runtime.d:29`](../../source/dun/engine/quickjs/runtime.d#L29) | `~this() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/runtime.d:36`](../../source/dun/engine/quickjs/runtime.d#L36) | `void setMemoryLimit(size_t limit) @trusted` | /// Set the maximum JS heap memory in bytes. |
| [`source/dun/engine/quickjs/runtime.d:43`](../../source/dun/engine/quickjs/runtime.d#L43) | `void setMaxStackSize(size_t stackSize) @trusted` | /// Set the maximum C stack size in bytes. |
| [`source/dun/engine/quickjs/runtime.d:50`](../../source/dun/engine/quickjs/runtime.d#L50) | `void setInterruptHandler(JSInterruptHandler cb, void* opaque = null) @trusted` | /// Set an interrupt handler for execution timeout. |
| [`source/dun/engine/quickjs/runtime.d:56`](../../source/dun/engine/quickjs/runtime.d#L56) | `bool hasPendingJob() @trusted` | /// Check if there are pending Promise jobs. |
| [`source/dun/engine/quickjs/runtime.d:62`](../../source/dun/engine/quickjs/runtime.d#L62) | `bool executePendingJob() @trusted` | /// Execute one pending job. Returns true if a job ran. |
| [`source/dun/engine/quickjs/runtime.d:70`](../../source/dun/engine/quickjs/runtime.d#L70) | `void drainJobs() @trusted` | /// Drain all pending jobs (microtask queue). |
| [`source/dun/engine/quickjs/runtime.d:79`](../../source/dun/engine/quickjs/runtime.d#L79) | `void setOpaque(void* opaque) @trusted` | /// Store opaque data on the runtime. |
| [`source/dun/engine/quickjs/runtime.d:85`](../../source/dun/engine/quickjs/runtime.d#L85) | `void* getOpaque() @trusted` | /// Retrieve opaque data from the runtime. |
| [`source/dun/engine/quickjs/runtime.d:91`](../../source/dun/engine/quickjs/runtime.d#L91) | `JSRuntime* handle() @trusted` | /// Access the raw JSRuntime pointer (for C API calls). |
| [`source/dun/engine/quickjs/value.d:13`](../../source/dun/engine/quickjs/value.d#L13) | `this(JSContext* ctx, JSValue val) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:19`](../../source/dun/engine/quickjs/value.d#L19) | `this(ref return scope JSVal other) @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:26`](../../source/dun/engine/quickjs/value.d#L26) | `~this() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:34`](../../source/dun/engine/quickjs/value.d#L34) | `bool isException() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:39`](../../source/dun/engine/quickjs/value.d#L39) | `bool isUndefined() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:44`](../../source/dun/engine/quickjs/value.d#L44) | `bool isNull() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:49`](../../source/dun/engine/quickjs/value.d#L49) | `bool isString() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:54`](../../source/dun/engine/quickjs/value.d#L54) | `bool isNumber() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:59`](../../source/dun/engine/quickjs/value.d#L59) | `bool isObject() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:64`](../../source/dun/engine/quickjs/value.d#L64) | `bool isBool() const @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:72`](../../source/dun/engine/quickjs/value.d#L72) | `string toString() @trusted` | /// Convert to D string. The returned string is GC-allocated. |
| [`source/dun/engine/quickjs/value.d:83`](../../source/dun/engine/quickjs/value.d#L83) | `int toInt32() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:90`](../../source/dun/engine/quickjs/value.d#L90) | `double toFloat64() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:97`](../../source/dun/engine/quickjs/value.d#L97) | `bool toBool() @trusted` | _(missing)_ |
| [`source/dun/engine/quickjs/value.d:105`](../../source/dun/engine/quickjs/value.d#L105) | `JSVal getProperty(string name) @trusted` | /// Get a property by name. |
| [`source/dun/engine/quickjs/value.d:113`](../../source/dun/engine/quickjs/value.d#L113) | `void setProperty(string name, JSVal value) @trusted` | /// Set a property by name. Transfers ownership of the value to the JS engine. |
| [`source/dun/engine/quickjs/value.d:122`](../../source/dun/engine/quickjs/value.d#L122) | `void setPropertyRaw(string name, JSValue value) @trusted` | /// Set a property with a raw JSValue. |
| [`source/dun/engine/quickjs/value.d:132`](../../source/dun/engine/quickjs/value.d#L132) | `JSValue raw() @trusted` | /// Access the raw JSValue (for passing to C API). |
| [`source/dun/engine/quickjs/value.d:138`](../../source/dun/engine/quickjs/value.d#L138) | `JSContext* context() @trusted` | /// Access the context this value belongs to. |
| [`source/dun/engine/quickjs/value.d:144`](../../source/dun/engine/quickjs/value.d#L144) | `JSValue release() @trusted` | /// Release ownership without freeing (for transferring to C API). |
| [`source/dun/engine/v8/backend.d:16`](../../source/dun/engine/v8/backend.d#L16) | `void initialize(EngineConfig config) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:38`](../../source/dun/engine/v8/backend.d#L38) | `void shutdown() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:52`](../../source/dun/engine/v8/backend.d#L52) | `JSResult eval(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:69`](../../source/dun/engine/v8/backend.d#L69) | `JSHandle newUndefined() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:75`](../../source/dun/engine/v8/backend.d#L75) | `JSHandle newNull() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:81`](../../source/dun/engine/v8/backend.d#L81) | `JSHandle newString(scope const(char)[] s) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:89`](../../source/dun/engine/v8/backend.d#L89) | `JSHandle newInt(int v) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:95`](../../source/dun/engine/v8/backend.d#L95) | `JSHandle newFloat(double v) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:101`](../../source/dun/engine/v8/backend.d#L101) | `JSHandle newBool(bool v) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:107`](../../source/dun/engine/v8/backend.d#L107) | `JSHandle newObject() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:113`](../../source/dun/engine/v8/backend.d#L113) | `JSHandle newArray() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:119`](../../source/dun/engine/v8/backend.d#L119) | `JSHandle newUint8Array(scope const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:125`](../../source/dun/engine/v8/backend.d#L125) | `JSHandle newUint8ArrayZeroed(size_t length) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:131`](../../source/dun/engine/v8/backend.d#L131) | `ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:142`](../../source/dun/engine/v8/backend.d#L142) | `JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:155`](../../source/dun/engine/v8/backend.d#L155) | `string extractString(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:176`](../../source/dun/engine/v8/backend.d#L176) | `int extractInt(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:182`](../../source/dun/engine/v8/backend.d#L182) | `double extractFloat(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:188`](../../source/dun/engine/v8/backend.d#L188) | `bool extractBool(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:194`](../../source/dun/engine/v8/backend.d#L194) | `JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:202`](../../source/dun/engine/v8/backend.d#L202) | `void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:210`](../../source/dun/engine/v8/backend.d#L210) | `void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:219`](../../source/dun/engine/v8/backend.d#L219) | `void setPrototype(JSHandle obj, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:225`](../../source/dun/engine/v8/backend.d#L225) | `JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool z...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:234`](../../source/dun/engine/v8/backend.d#L234) | `JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:245`](../../source/dun/engine/v8/backend.d#L245) | `JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:254`](../../source/dun/engine/v8/backend.d#L254) | `size_t totalLen, JSHandle proto) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:262`](../../source/dun/engine/v8/backend.d#L262) | `void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:268`](../../source/dun/engine/v8/backend.d#L268) | `JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:274`](../../source/dun/engine/v8/backend.d#L274) | `bool isArray(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:279`](../../source/dun/engine/v8/backend.d#L279) | `int getArrayLength(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:289`](../../source/dun/engine/v8/backend.d#L289) | `JSHandle getGlobal() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:295`](../../source/dun/engine/v8/backend.d#L295) | `JSHandle callFunction(JSHandle func, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:328`](../../source/dun/engine/v8/backend.d#L328) | `JSHandle dupValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:337`](../../source/dun/engine/v8/backend.d#L337) | `void freeValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:351`](../../source/dun/engine/v8/backend.d#L351) | `private bool checkType(V8TypeTag tag, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:358`](../../source/dun/engine/v8/backend.d#L358) | `bool isUndefined(JSHandle val) @trusted { return checkType(V8TypeTag.Undefine...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:359`](../../source/dun/engine/v8/backend.d#L359) | `bool isNull(JSHandle val) @trusted { return checkType(V8TypeTag.Null, val); }` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:360`](../../source/dun/engine/v8/backend.d#L360) | `bool isString(JSHandle val) @trusted { return checkType(V8TypeTag.String, val...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:361`](../../source/dun/engine/v8/backend.d#L361) | `bool isObject(JSHandle val) @trusted { return checkType(V8TypeTag.Object, val...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:362`](../../source/dun/engine/v8/backend.d#L362) | `bool isFunction(JSHandle val) @trusted { return checkType(V8TypeTag.Function,...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:363`](../../source/dun/engine/v8/backend.d#L363) | `bool isBool(JSHandle val) @trusted { return checkType(V8TypeTag.Bool, val); }` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:364`](../../source/dun/engine/v8/backend.d#L364) | `bool isNumber(JSHandle val) @trusted { return checkType(V8TypeTag.Number, val...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:366`](../../source/dun/engine/v8/backend.d#L366) | `string getException() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:377`](../../source/dun/engine/v8/backend.d#L377) | `JSHandle throwTypeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:384`](../../source/dun/engine/v8/backend.d#L384) | `JSHandle throwRangeError(scope const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:391`](../../source/dun/engine/v8/backend.d#L391) | `JSHandle throwValue(JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:397`](../../source/dun/engine/v8/backend.d#L397) | `PromiseHandles newPromise() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:418`](../../source/dun/engine/v8/backend.d#L418) | `bool hasPendingJobs() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:424`](../../source/dun/engine/v8/backend.d#L424) | `bool executePendingJob() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:431`](../../source/dun/engine/v8/backend.d#L431) | `void drainJobs() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:437`](../../source/dun/engine/v8/backend.d#L437) | `void setContextOpaque(void* ptr) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:443`](../../source/dun/engine/v8/backend.d#L443) | `void* getContextOpaque() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:451`](../../source/dun/engine/v8/backend.d#L451) | `JSResult evalModule(scope const(char)[] source, string filename) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:470`](../../source/dun/engine/v8/backend.d#L470) | `void registerNativeModule(string name, void* initFunc) @trusted {}` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:472`](../../source/dun/engine/v8/backend.d#L472) | `void setMemoryLimit(size_t bytes) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:479`](../../source/dun/engine/v8/backend.d#L479) | `void setMaxStackSize(size_t bytes) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:486`](../../source/dun/engine/v8/backend.d#L486) | `void collectGarbage() @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:492`](../../source/dun/engine/v8/backend.d#L492) | `void* rawRuntime() @trusted { return cast(void*) isolate; }` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:493`](../../source/dun/engine/v8/backend.d#L493) | `void* rawContext() @trusted { return cast(void*) ctx; }` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:497`](../../source/dun/engine/v8/backend.d#L497) | `void registerV8Function(string name, DunV8NativeCallback cb, void* data = nul...` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:508`](../../source/dun/engine/v8/backend.d#L508) | `const(char)[] name, return ref char[V8_STACK_STRING_SIZE] buf) @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:519`](../../source/dun/engine/v8/backend.d#L519) | `static JSHandle toHandle(DunV8Value* ptr) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:526`](../../source/dun/engine/v8/backend.d#L526) | `static DunV8Value* fromHandle(JSHandle h) pure nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/engine/v8/backend.d:533`](../../source/dun/engine/v8/backend.d#L533) | `DunV8Value* thisVal, int argc, DunV8Value** argv, void* data) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/v8/cppbindings.d:51`](../../source/dun/engine/v8/cppbindings.d#L51) | `static V8TypeChecks init() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/engine/v8/cppbindings.d:66`](../../source/dun/engine/v8/cppbindings.d#L66) | `bool check(V8TypeTag tag, DunV8Value* val) @trusted nothrow @nogc` | _(missing)_ |

## engine-bridge (4 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/buffer.d:290`](../../source/dun/builtins/buffer.d#L290) | `public JSHandle makeBufferObj(IJSEngine engine, const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:300`](../../source/dun/builtins/buffer.d#L300) | `public JSHandle makeBufferObjZeroed(IJSEngine engine, int size) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:358`](../../source/dun/builtins/buffer.d#L358) | `package ubyte[] extractBytes(IJSEngine engine, return scope JSHandle obj) @tr...` | /// Returned slice inherits \`obj\`'s scope (DIP1000 \`return scope\`): /// c... |
| [`source/dun/runtime/globals.d:22`](../../source/dun/runtime/globals.d#L22) | `DunState* ctxState(void* ctx) @trusted nothrow @nogc` | /// Narrow-scope \`@trusted\` for the recurring \`cast(DunState*) ctx\` /// p... |

## event-loop (42 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/loop/async.d:9`](../../source/dun/loop/async.d#L9) | `alias ResultTransform = JSHandle delegate(IJSEngine engine, string result) @t...` | _(missing)_ |
| [`source/dun/loop/async.d:38`](../../source/dun/loop/async.d#L38) | `AsyncResult delegate() @trusted nothrow work;` | _(missing)_ |
| [`source/dun/loop/async.d:60`](../../source/dun/loop/async.d#L60) | `private void initPool() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/async.d:79`](../../source/dun/loop/async.d#L79) | `private void poolWorker() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/async.d:109`](../../source/dun/loop/async.d#L109) | `string delegate() @trusted work,` | _(missing)_ |
| [`source/dun/loop/async.d:110`](../../source/dun/loop/async.d#L110) | `ResultTransform transform = null) @trusted` | _(missing)_ |
| [`source/dun/loop/async.d:112`](../../source/dun/loop/async.d#L112) | `asyncSubmitSafe(engine, resolve, reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/loop/async.d:126`](../../source/dun/loop/async.d#L126) | `AsyncResult delegate() @trusted nothrow work,` | _(missing)_ |
| [`source/dun/loop/async.d:127`](../../source/dun/loop/async.d#L127) | `ResultTransform transform = null) @trusted` | _(missing)_ |
| [`source/dun/loop/async.d:147`](../../source/dun/loop/async.d#L147) | `int asyncDrain() @trusted` | _(missing)_ |
| [`source/dun/loop/async.d:217`](../../source/dun/loop/async.d#L217) | `bool asyncHasWork() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:67`](../../source/dun/loop/iopoller.d#L67) | `void initialize() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:125`](../../source/dun/loop/iopoller.d#L125) | `void shutdown() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:166`](../../source/dun/loop/iopoller.d#L166) | `void watch(int fd, bool forRead = true, bool forWrite = false) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:205`](../../source/dun/loop/iopoller.d#L205) | `void modify(int fd, bool forRead, bool forWrite) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:247`](../../source/dun/loop/iopoller.d#L247) | `void unwatch(int fd) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:289`](../../source/dun/loop/iopoller.d#L289) | `IOEvent[] poll(int timeoutMs, IOEvent[] buf) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:401`](../../source/dun/loop/iopoller.d#L401) | `bool* singleMmap) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:479`](../../source/dun/loop/iopoller.d#L479) | `bool singleMmap) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:490`](../../source/dun/loop/iopoller.d#L490) | `uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @tru...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:512`](../../source/dun/loop/iopoller.d#L512) | `uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @tru...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:522`](../../source/dun/loop/iopoller.d#L522) | `uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @tru...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:562`](../../source/dun/loop/iopoller.d#L562) | `bool forRead, bool forWrite) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:574`](../../source/dun/loop/iopoller.d#L574) | `private void uringUntrackFd(ref FdWatch[MAX_FD_WATCHES] watches, int fd) @tru...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:582`](../../source/dun/loop/iopoller.d#L582) | `private FdWatch uringLookupFd(ref FdWatch[MAX_FD_WATCHES] watches, int fd) @t...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:592`](../../source/dun/loop/iopoller.d#L592) | `FdWatch[] watches) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:642`](../../source/dun/loop/iopoller.d#L642) | `int timeoutMs, IOEvent[] buf) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:719`](../../source/dun/loop/iopoller.d#L719) | `private int kqueueCreate() @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:724`](../../source/dun/loop/iopoller.d#L724) | `private void kqueueShutdown(int kqfd, ref int watchCount) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:732`](../../source/dun/loop/iopoller.d#L732) | `private bool kqueueWatch(int kqfd, int fd, bool forRead, bool forWrite) @trus...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:755`](../../source/dun/loop/iopoller.d#L755) | `private void kqueueModify(int kqfd, int fd, bool forRead, bool forWrite) @tru...` | _(missing)_ |
| [`source/dun/loop/iopoller.d:774`](../../source/dun/loop/iopoller.d#L774) | `private bool kqueueUnwatch(int kqfd, int fd) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:790`](../../source/dun/loop/iopoller.d#L790) | `int timeoutMs, IOEvent[] buf) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:842`](../../source/dun/loop/iopoller.d#L842) | `bool forRead, bool forWrite) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:855`](../../source/dun/loop/iopoller.d#L855) | `bool forRead, bool forWrite) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:869`](../../source/dun/loop/iopoller.d#L869) | `private void pollRemove(ref pollfd[] fds, int fd) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/iopoller.d:889`](../../source/dun/loop/iopoller.d#L889) | `IOEvent[] buf) @trusted nothrow` | _(missing)_ |
| [`source/dun/loop/timers.d:24`](../../source/dun/loop/timers.d#L24) | `Duration interval = Duration.zero) nothrow @trusted` | _(missing)_ |
| [`source/dun/loop/timers.d:45`](../../source/dun/loop/timers.d#L45) | `void cancelTimer(TimerID id) nothrow @trusted` | _(missing)_ |
| [`source/dun/loop/timers.d:57`](../../source/dun/loop/timers.d#L57) | `void processExpired() @trusted` | _(missing)_ |
| [`source/dun/loop/timers.d:101`](../../source/dun/loop/timers.d#L101) | `Duration nextDeadline() @trusted` | _(missing)_ |
| [`source/dun/loop/timers.d:118`](../../source/dun/loop/timers.d#L118) | `private void sortEntries() nothrow @trusted` | _(missing)_ |

## fs-IO (175 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/child_process.d:12`](../../source/dun/builtins/child_process.d#L12) | `string readAllFromPipe(P)(P pipe) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:26`](../../source/dun/builtins/child_process.d#L26) | `void registerChildProcessModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:56`](../../source/dun/builtins/child_process.d#L56) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:68`](../../source/dun/builtins/child_process.d#L68) | `private extern (C) int cpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/child_process.d:87`](../../source/dun/builtins/child_process.d#L87) | `bool hasGlobalRun(DunState* state) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:96`](../../source/dun/builtins/child_process.d#L96) | `JSHandle throwPermError(IJSEngine engine, string cmd) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:129`](../../source/dun/builtins/child_process.d#L129) | `string extractOptString(IJSEngine engine, JSHandle opts, string key) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:138`](../../source/dun/builtins/child_process.d#L138) | `int extractOptInt(IJSEngine engine, JSHandle opts, string key, int def) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:147`](../../source/dun/builtins/child_process.d#L147) | `string[string] extractOptEnv(IJSEngine engine, JSHandle opts) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:186`](../../source/dun/builtins/child_process.d#L186) | `JSHandle jsExecSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:257`](../../source/dun/builtins/child_process.d#L257) | `JSHandle jsSpawnSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/child_process.d:365`](../../source/dun/builtins/child_process.d#L365) | `JSHandle jsExec(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:538`](../../source/dun/builtins/child_process.d#L538) | `JSHandle jsSpawn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:724`](../../source/dun/builtins/child_process.d#L724) | `JSHandle jsExecFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/child_process.d:886`](../../source/dun/builtins/child_process.d#L886) | `JSHandle jsExecFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/child_process.d:933`](../../source/dun/builtins/child_process.d#L933) | `JSHandle jsFork(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:63`](../../source/dun/builtins/fs.d#L63) | `private string safeReadFile(string path, out string errMsg) @trusted nothrow` | /// File read using C stdio — no D exceptions, portable across all platforms. |
| [`source/dun/builtins/fs.d:104`](../../source/dun/builtins/fs.d#L104) | `private ubyte[] safeReadFileBytes(string path, out string errMsg) @trusted no...` | _(missing)_ |
| [`source/dun/builtins/fs.d:144`](../../source/dun/builtins/fs.d#L144) | `private bool safeWriteFile(string path, string data, out string errMsg) @trus...` | /// File write using C stdio — portable across all platforms. |
| [`source/dun/builtins/fs.d:152`](../../source/dun/builtins/fs.d#L152) | `out string errMsg) @trusted nothrow` | /// Raw-byte file write. The string \`safeWriteFile\` delegates here so /// b... |
| [`source/dun/builtins/fs.d:182`](../../source/dun/builtins/fs.d#L182) | `private bool safeExists(string path) @trusted nothrow` | /// Existence check — portable across POSIX and Windows. |
| [`source/dun/builtins/fs.d:201`](../../source/dun/builtins/fs.d#L201) | `void registerFsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:313`](../../source/dun/builtins/fs.d#L313) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:324`](../../source/dun/builtins/fs.d#L324) | `private extern (C) int fsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:365`](../../source/dun/builtins/fs.d#L365) | `void ensureStatFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:376`](../../source/dun/builtins/fs.d#L376) | `private void ensureFsStreamFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:395`](../../source/dun/builtins/fs.d#L395) | `private void ensureDateFactoryCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:425`](../../source/dun/builtins/fs.d#L425) | `private SafeStatResult statToResult(ref stat_t buf) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/fs.d:454`](../../source/dun/builtins/fs.d#L454) | `private int safeStat(const(char)* cpath, out SafeStatResult result) @trusted ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:463`](../../source/dun/builtins/fs.d#L463) | `private int safeLstat(const(char)* cpath, out SafeStatResult result) @trusted...` | _(missing)_ |
| [`source/dun/builtins/fs.d:472`](../../source/dun/builtins/fs.d#L472) | `private int safeFstat(int fd, out SafeStatResult result) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/fs.d:481`](../../source/dun/builtins/fs.d#L481) | `JSHandle buildStatFromPosix(IJSEngine engine, ref stat_t buf) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:489`](../../source/dun/builtins/fs.d#L489) | `private int safeStat(const(char)* cpath, out SafeStatResult result) @trusted ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:504`](../../source/dun/builtins/fs.d#L504) | `private int safeLstat(const(char)* cpath, out SafeStatResult result) @trusted...` | _(missing)_ |
| [`source/dun/builtins/fs.d:509`](../../source/dun/builtins/fs.d#L509) | `private int safeFstat(int fd, out SafeStatResult result) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/fs.d:517`](../../source/dun/builtins/fs.d#L517) | `package JSHandle buildStatObject(IJSEngine engine, ref SafeStatResult r) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:543`](../../source/dun/builtins/fs.d#L543) | `JSHandle makeDate(IJSEngine engine, double ms) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:562`](../../source/dun/builtins/fs.d#L562) | `string detectErrCode(string msg) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/fs.d:603`](../../source/dun/builtins/fs.d#L603) | `string syscall = "", string path = "") @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:628`](../../source/dun/builtins/fs.d#L628) | `JSHandle throwSystemError(IJSEngine engine, string syscall, string path, Exce...` | _(missing)_ |
| [`source/dun/builtins/fs.d:652`](../../source/dun/builtins/fs.d#L652) | `package string intToStr(int n) @trusted pure nothrow` | /// Zero-alloc-on-stack base-10 int formatter. Used by FS error /// messages ... |
| [`source/dun/builtins/fs.d:664`](../../source/dun/builtins/fs.d#L664) | `package JSHandle throwPermError(IJSEngine engine, string perm, string path = ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:673`](../../source/dun/builtins/fs.d#L673) | `package string errnoMsg() @trusted nothrow` | /// Read errno and return the system's localized error message as a /// GC-al... |
| [`source/dun/builtins/fs.d:682`](../../source/dun/builtins/fs.d#L682) | `public string extractEncoding(IJSEngine engine, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:700`](../../source/dun/builtins/fs.d#L700) | `void ensureBufFromCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:711`](../../source/dun/builtins/fs.d#L711) | `public JSHandle createBufferFromBytes(IJSEngine engine, const(ubyte)[] data) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:729`](../../source/dun/builtins/fs.d#L729) | `JSHandle jsReadFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:757`](../../source/dun/builtins/fs.d#L757) | `JSHandle jsWriteFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:791`](../../source/dun/builtins/fs.d#L791) | `JSHandle jsExistsSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:803`](../../source/dun/builtins/fs.d#L803) | `JSHandle jsReaddirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs.d:868`](../../source/dun/builtins/fs.d#L868) | `JSHandle jsStatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:885`](../../source/dun/builtins/fs.d#L885) | `JSHandle jsStatIsFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:895`](../../source/dun/builtins/fs.d#L895) | `JSHandle jsStatIsDirectory(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/fs.d:905`](../../source/dun/builtins/fs.d#L905) | `JSHandle jsMkdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:960`](../../source/dun/builtins/fs.d#L960) | `JSHandle jsUnlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:976`](../../source/dun/builtins/fs.d#L976) | `JSHandle jsReadFileAsync(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1014`](../../source/dun/builtins/fs.d#L1014) | `asyncSubmitSafe(engine, resolve, reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs.d:1034`](../../source/dun/builtins/fs.d#L1034) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs.d:1051`](../../source/dun/builtins/fs.d#L1051) | `JSHandle jsWriteFileAsync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1082`](../../source/dun/builtins/fs.d#L1082) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs.d:1101`](../../source/dun/builtins/fs.d#L1101) | `JSHandle jsAppendFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1133`](../../source/dun/builtins/fs.d#L1133) | `JSHandle jsCopyFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1154`](../../source/dun/builtins/fs.d#L1154) | `JSHandle jsRenameSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1175`](../../source/dun/builtins/fs.d#L1175) | `JSHandle jsRmdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1193`](../../source/dun/builtins/fs.d#L1193) | `JSHandle jsRmSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1221`](../../source/dun/builtins/fs.d#L1221) | `JSHandle jsAccessSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1240`](../../source/dun/builtins/fs.d#L1240) | `JSHandle jsRealpathSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1255`](../../source/dun/builtins/fs.d#L1255) | `auto result = (() @trusted => realpath(cast(const(char)*)(path ~ "\0").ptr, n...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1264`](../../source/dun/builtins/fs.d#L1264) | `(() @trusted => cast(const(char)[]) fromStringz(result))());` | _(missing)_ |
| [`source/dun/builtins/fs.d:1266`](../../source/dun/builtins/fs.d#L1266) | `(() @trusted => free(result))();` | _(missing)_ |
| [`source/dun/builtins/fs.d:1281`](../../source/dun/builtins/fs.d#L1281) | `JSHandle jsChmodSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1300`](../../source/dun/builtins/fs.d#L1300) | `JSHandle jsStatIsSymbolicLink(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1312`](../../source/dun/builtins/fs.d#L1312) | `JSHandle jsLstatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1334`](../../source/dun/builtins/fs.d#L1334) | `JSHandle jsLinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1366`](../../source/dun/builtins/fs.d#L1366) | `JSHandle jsSymlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1396`](../../source/dun/builtins/fs.d#L1396) | `JSHandle jsReadlinkSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1427`](../../source/dun/builtins/fs.d#L1427) | `JSHandle jsTruncateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1467`](../../source/dun/builtins/fs.d#L1467) | `JSHandle jsFtruncateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1489`](../../source/dun/builtins/fs.d#L1489) | `JSHandle jsFutimesSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1515`](../../source/dun/builtins/fs.d#L1515) | `JSHandle jsChownSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1546`](../../source/dun/builtins/fs.d#L1546) | `int parseFsFlags(string flags) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1567`](../../source/dun/builtins/fs.d#L1567) | `JSHandle jsOpenSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1606`](../../source/dun/builtins/fs.d#L1606) | `JSHandle jsCloseSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1625`](../../source/dun/builtins/fs.d#L1625) | `JSHandle jsReadSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1706`](../../source/dun/builtins/fs.d#L1706) | `JSHandle jsWriteSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1738`](../../source/dun/builtins/fs.d#L1738) | `JSHandle jsFstatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1758`](../../source/dun/builtins/fs.d#L1758) | `JSHandle jsFsyncSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1780`](../../source/dun/builtins/fs.d#L1780) | `JSHandle jsFdatasyncSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1814`](../../source/dun/builtins/fs.d#L1814) | `JSHandle jsCreateReadStream(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1896`](../../source/dun/builtins/fs.d#L1896) | `JSHandle jsCreateWriteStream(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1926`](../../source/dun/builtins/fs.d#L1926) | `JSHandle jsStreamOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:1939`](../../source/dun/builtins/fs.d#L1939) | `JSHandle jsStreamDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1945`](../../source/dun/builtins/fs.d#L1945) | `JSHandle jsReadStreamDestroy(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1970`](../../source/dun/builtins/fs.d#L1970) | `JSHandle jsReadStreamResume(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/fs.d:1976`](../../source/dun/builtins/fs.d#L1976) | `JSHandle jsReadStreamRead(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2039`](../../source/dun/builtins/fs.d#L2039) | `JSHandle jsReadStreamPipe(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2063`](../../source/dun/builtins/fs.d#L2063) | `JSHandle jsWriteStreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2097`](../../source/dun/builtins/fs.d#L2097) | `JSHandle jsWriteStreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2164`](../../source/dun/builtins/fs.d#L2164) | `JSHandle jsWatch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:2276`](../../source/dun/builtins/fs.d#L2276) | `JSHandle jsWatcherPoll(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2357`](../../source/dun/builtins/fs.d#L2357) | `JSHandle jsWatcherClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2377`](../../source/dun/builtins/fs.d#L2377) | `JSHandle jsWatcherOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2391`](../../source/dun/builtins/fs.d#L2391) | `JSHandle jsWatcherRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2398`](../../source/dun/builtins/fs.d#L2398) | `JSHandle jsWatcherUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2407`](../../source/dun/builtins/fs.d#L2407) | `JSHandle jsMkdtempSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2435`](../../source/dun/builtins/fs.d#L2435) | `JSHandle jsCpSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:2490`](../../source/dun/builtins/fs.d#L2490) | `JSHandle jsUtimesSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs.d:2657`](../../source/dun/builtins/fs.d#L2657) | `int dtypeToDirent(ubyte dtype, string dirPath, string name) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs.d:2688`](../../source/dun/builtins/fs.d#L2688) | `package JSHandle createDirentObject(IJSEngine engine, string name, int dtype)...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:9`](../../source/dun/builtins/fs_promises.d#L9) | `void registerFsPromisesModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:77`](../../source/dun/builtins/fs_promises.d#L77) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:89`](../../source/dun/builtins/fs_promises.d#L89) | `private extern (C) int fspModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:116`](../../source/dun/builtins/fs_promises.d#L116) | `string safeFileOp(string delegate() op) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:122`](../../source/dun/builtins/fs_promises.d#L122) | `string safeExMsg(string delegate() op) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:134`](../../source/dun/builtins/fs_promises.d#L134) | `int parseFsOpenFlags(string flags) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:155`](../../source/dun/builtins/fs_promises.d#L155) | `JSHandle jsFspReadFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:178`](../../source/dun/builtins/fs_promises.d#L178) | `auto work = () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:199`](../../source/dun/builtins/fs_promises.d#L199) | `ResultTransform bytesTransform = (IJSEngine e, string s) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:208`](../../source/dun/builtins/fs_promises.d#L208) | `JSHandle jsFspWriteFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:239`](../../source/dun/builtins/fs_promises.d#L239) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:253`](../../source/dun/builtins/fs_promises.d#L253) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:258`](../../source/dun/builtins/fs_promises.d#L258) | `JSHandle jsFspAppendFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:284`](../../source/dun/builtins/fs_promises.d#L284) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:298`](../../source/dun/builtins/fs_promises.d#L298) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:303`](../../source/dun/builtins/fs_promises.d#L303) | `JSHandle jsFspCopyFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:320`](../../source/dun/builtins/fs_promises.d#L320) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:333`](../../source/dun/builtins/fs_promises.d#L333) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:338`](../../source/dun/builtins/fs_promises.d#L338) | `JSHandle jsFspRename(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:355`](../../source/dun/builtins/fs_promises.d#L355) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:368`](../../source/dun/builtins/fs_promises.d#L368) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:373`](../../source/dun/builtins/fs_promises.d#L373) | `JSHandle jsFspUnlink(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:387`](../../source/dun/builtins/fs_promises.d#L387) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:400`](../../source/dun/builtins/fs_promises.d#L400) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:405`](../../source/dun/builtins/fs_promises.d#L405) | `JSHandle jsFspRmdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:419`](../../source/dun/builtins/fs_promises.d#L419) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:432`](../../source/dun/builtins/fs_promises.d#L432) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:437`](../../source/dun/builtins/fs_promises.d#L437) | `JSHandle jsFspRm(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:462`](../../source/dun/builtins/fs_promises.d#L462) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:482`](../../source/dun/builtins/fs_promises.d#L482) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:487`](../../source/dun/builtins/fs_promises.d#L487) | `JSHandle jsFspMkdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:508`](../../source/dun/builtins/fs_promises.d#L508) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:529`](../../source/dun/builtins/fs_promises.d#L529) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:534`](../../source/dun/builtins/fs_promises.d#L534) | `JSHandle jsFspReaddir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:558`](../../source/dun/builtins/fs_promises.d#L558) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:586`](../../source/dun/builtins/fs_promises.d#L586) | `}, (IJSEngine e, string result) @trusted {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:594`](../../source/dun/builtins/fs_promises.d#L594) | `void emit(string entry) @trusted {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:635`](../../source/dun/builtins/fs_promises.d#L635) | `JSHandle jsFspStat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:649`](../../source/dun/builtins/fs_promises.d#L649) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:651`](../../source/dun/builtins/fs_promises.d#L651) | `}, (IJSEngine e, string result) @trusted => deserializeStatObj(e, result));` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:656`](../../source/dun/builtins/fs_promises.d#L656) | `JSHandle jsFspLstat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:670`](../../source/dun/builtins/fs_promises.d#L670) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:672`](../../source/dun/builtins/fs_promises.d#L672) | `}, (IJSEngine e, string result) @trusted => deserializeStatObj(e, result));` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:677`](../../source/dun/builtins/fs_promises.d#L677) | `JSHandle jsFspAccess(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:691`](../../source/dun/builtins/fs_promises.d#L691) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:709`](../../source/dun/builtins/fs_promises.d#L709) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:714`](../../source/dun/builtins/fs_promises.d#L714) | `JSHandle jsFspRealpath(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:728`](../../source/dun/builtins/fs_promises.d#L728) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:764`](../../source/dun/builtins/fs_promises.d#L764) | `JSHandle jsFspChmod(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:779`](../../source/dun/builtins/fs_promises.d#L779) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:792`](../../source/dun/builtins/fs_promises.d#L792) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:797`](../../source/dun/builtins/fs_promises.d#L797) | `JSHandle jsFspChown(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:813`](../../source/dun/builtins/fs_promises.d#L813) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:823`](../../source/dun/builtins/fs_promises.d#L823) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:828`](../../source/dun/builtins/fs_promises.d#L828) | `JSHandle jsFspTruncate(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:844`](../../source/dun/builtins/fs_promises.d#L844) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:867`](../../source/dun/builtins/fs_promises.d#L867) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:874`](../../source/dun/builtins/fs_promises.d#L874) | `JSHandle jsFspSymlink(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:889`](../../source/dun/builtins/fs_promises.d#L889) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:903`](../../source/dun/builtins/fs_promises.d#L903) | `}, (IJSEngine e, string _) @trusted => e.newUndefined());` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:910`](../../source/dun/builtins/fs_promises.d#L910) | `JSHandle jsFspOpen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:935`](../../source/dun/builtins/fs_promises.d#L935) | `asyncSubmitSafe(engine, ph.resolve, ph.reject, () @trusted nothrow {` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:956`](../../source/dun/builtins/fs_promises.d#L956) | `}, (IJSEngine e, string fdStr) @trusted => buildFileHandle(e, fdStr, path));` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:961`](../../source/dun/builtins/fs_promises.d#L961) | `JSHandle buildFileHandle(IJSEngine engine, string fdStr, string path) @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:1066`](../../source/dun/builtins/fs_promises.d#L1066) | `AsyncResult serializeStatSafe(string path, bool useLstat) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/fs_promises.d:1143`](../../source/dun/builtins/fs_promises.d#L1143) | `JSHandle deserializeStatObj(IJSEngine engine, string data) @trusted` | _(missing)_ |

## hot-path (7 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/engine/callbacks.d:49`](../../source/dun/engine/callbacks.d#L49) | `NativeCallback get(int id) nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/platform/arena.d:12`](../../source/dun/platform/arena.d#L12) | `BumpRegion makeBumpRegion(size_t capacity) @trusted pure nothrow @nogc` | _(missing)_ |
| [`source/dun/platform/arena.d:18`](../../source/dun/platform/arena.d#L18) | `T[] regionAlloc(T, Alloc)(ref Alloc alloc, size_t count) @trusted pure nothro...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:21`](../../source/dun/runtime/process_api.d#L21) | `bool hasUncaughtExceptionHandler() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/runtime/process_api.d:77`](../../source/dun/runtime/process_api.d#L77) | `bool hasUnhandledRejectionHandler() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/workers/worker.d:20`](../../source/dun/workers/worker.d#L20) | `private WorkerStatus loadStatus(WorkerState wst) @trusted nothrow @nogc` | /// Lockfree accessors for \`WorkerState.status_\`. Writes from the /// worke... |
| [`source/dun/workers/worker.d:26`](../../source/dun/workers/worker.d#L26) | `private void storeStatus(WorkerState wst, WorkerStatus s) @trusted nothrow @nogc` | _(missing)_ |

## napi-FFI (22 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/napi/loader.d:10`](../../source/dun/napi/loader.d#L10) | `JSHandle loadNativeAddon(IJSEngine engine, DunState* state, string path) @tru...` | _(missing)_ |
| [`source/dun/napi/napi.d:11`](../../source/dun/napi/napi.d#L11) | `napi_value allocValue(JSHandle h) nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:37`](../../source/dun/napi/napi.d#L37) | `napi_env getOrCreateEnv(DunState* state) nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:50`](../../source/dun/napi/napi.d#L50) | `extern(C) @trusted:` | _(missing)_ |
| [`source/dun/napi/napi.d:1091`](../../source/dun/napi/napi.d#L1091) | `private void ensureNapiDispatcher(napi_env env) @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1263`](../../source/dun/napi/napi.d#L1263) | `private extern (D) JSHandle napiNoopFn(void* engineCtx, JSHandle thisVal, sco...` | _(missing)_ |
| [`source/dun/napi/napi.d:1289`](../../source/dun/napi/napi.d#L1289) | `private int registerNapiFn(napi_env env, napi_callback cb, void* data) nothro...` | _(missing)_ |
| [`source/dun/napi/napi.d:1301`](../../source/dun/napi/napi.d#L1301) | `private extern (D) JSHandle napiDispatch(void* engineCtx, JSHandle thisVal, s...` | _(missing)_ |
| [`source/dun/napi/napi.d:1368`](../../source/dun/napi/napi.d#L1368) | `extern(C) @trusted:` | _(missing)_ |
| [`source/dun/napi/napi.d:1450`](../../source/dun/napi/napi.d#L1450) | `private void ensureNapiMutexes() nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1462`](../../source/dun/napi/napi.d#L1462) | `extern(D) int napiDrainAsyncWork() nothrow @trusted` | /// Called by the event loop on each tick to flush any completed async /// wo... |
| [`source/dun/napi/napi.d:1501`](../../source/dun/napi/napi.d#L1501) | `extern(D) bool napiHasAsyncWork() nothrow @trusted` | /// True when there is at least one async work entry still pending — /// ei... |
| [`source/dun/napi/napi.d:1607`](../../source/dun/napi/napi.d#L1607) | `extern(D) int napiDrainThreadsafeCalls() nothrow @trusted` | /// Called by the event loop on each tick to dispatch pending threadsafe /// ... |
| [`source/dun/napi/napi.d:1647`](../../source/dun/napi/napi.d#L1647) | `extern(D) bool napiHasThreadsafeCalls() nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1690`](../../source/dun/napi/napi.d#L1690) | `void ensureWrapMutex() nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1696`](../../source/dun/napi/napi.d#L1696) | `ulong getWrapId(napi_env env, JSHandle obj) nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1721`](../../source/dun/napi/napi.d#L1721) | `void* lookupWrap(napi_env env, JSHandle obj) nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1732`](../../source/dun/napi/napi.d#L1732) | `void* removeWrap(napi_env env, JSHandle obj) nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:1787`](../../source/dun/napi/napi.d#L1787) | `extern(C) @trusted:` | _(missing)_ |
| [`source/dun/napi/napi.d:2105`](../../source/dun/napi/napi.d#L2105) | `private void _ensureCleanupMu() nothrow @trusted` | _(missing)_ |
| [`source/dun/napi/napi.d:2148`](../../source/dun/napi/napi.d#L2148) | `public extern(D) void napiFireCleanupHooks() nothrow @trusted` | /// Fire all registered cleanup hooks. Called from \`napiFireFinalizers\` ///... |
| [`source/dun/napi/napi.d:2439`](../../source/dun/napi/napi.d#L2439) | `public extern(D) void napiFireFinalizers() nothrow @trusted` | /// Fire all pending finalizers. Called at runtime shutdown. Each finalizer /... |

## network-IO (246 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/dgram.d:16`](../../source/dun/builtins/dgram.d#L16) | `private void ensureUdpFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:36`](../../source/dun/builtins/dgram.d#L36) | `void registerDgramModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:60`](../../source/dun/builtins/dgram.d#L60) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:72`](../../source/dun/builtins/dgram.d#L72) | `private extern (C) int dgramModuleInit(JSContext* ctx, JSModuleDef* m) nothro...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:125`](../../source/dun/builtins/dgram.d#L125) | `int allocUdpSocket() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:139`](../../source/dun/builtins/dgram.d#L139) | `JSHandle jsCreateSocket(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:231`](../../source/dun/builtins/dgram.d#L231) | `int getSocketId(IJSEngine engine, JSHandle thisVal) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:240`](../../source/dun/builtins/dgram.d#L240) | `JSHandle jsUdpBind(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:325`](../../source/dun/builtins/dgram.d#L325) | `JSHandle jsUdpSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:431`](../../source/dun/builtins/dgram.d#L431) | `JSHandle jsUdpClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:474`](../../source/dun/builtins/dgram.d#L474) | `JSHandle jsUdpAddress(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:547`](../../source/dun/builtins/dgram.d#L547) | `JSHandle jsUdpSetBroadcast(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:568`](../../source/dun/builtins/dgram.d#L568) | `JSHandle jsUdpSetTTL(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:593`](../../source/dun/builtins/dgram.d#L593) | `JSHandle jsUdpAddMembership(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:606`](../../source/dun/builtins/dgram.d#L606) | `JSHandle jsUdpDropMembership(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:613`](../../source/dun/builtins/dgram.d#L613) | `JSHandle jsUdpOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:657`](../../source/dun/builtins/dgram.d#L657) | `JSHandle jsUdpRemoveListeners(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/dgram.d:676`](../../source/dun/builtins/dgram.d#L676) | `JSHandle jsUdpRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dgram.d:683`](../../source/dun/builtins/dgram.d#L683) | `JSHandle jsUdpUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:7`](../../source/dun/builtins/dns.d#L7) | `void registerDnsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:36`](../../source/dun/builtins/dns.d#L36) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:59`](../../source/dun/builtins/dns.d#L59) | `private extern (C) int dnsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/dns.d:75`](../../source/dun/builtins/dns.d#L75) | `private extern (C) int dnsPromisesModuleInit(JSContext* ctx, JSModuleDef* m) ...` | _(missing)_ |
| [`source/dun/builtins/dns.d:94`](../../source/dun/builtins/dns.d#L94) | `bool checkNetPerm(DunState* state, string hostname) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:115`](../../source/dun/builtins/dns.d#L115) | `DnsResult[] resolveHostname(string hostname, int afFamily) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:160`](../../source/dun/builtins/dns.d#L160) | `JSHandle jsLookupSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/dns.d:192`](../../source/dun/builtins/dns.d#L192) | `JSHandle jsLookup(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:241`](../../source/dun/builtins/dns.d#L241) | `JSHandle jsResolve4(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:288`](../../source/dun/builtins/dns.d#L288) | `JSHandle jsResolve6(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:335`](../../source/dun/builtins/dns.d#L335) | `JSHandle jsResolve(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/dns.d:447`](../../source/dun/builtins/dns.d#L447) | `JSHandle jsGetServers(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/dns.d:481`](../../source/dun/builtins/dns.d#L481) | `string[] parseResolvConf() @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:17`](../../source/dun/builtins/fetch.d#L17) | `void registerFetchGlobal(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:26`](../../source/dun/builtins/fetch.d#L26) | `private JSHandle jsFetch(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/fetch.d:122`](../../source/dun/builtins/fetch.d#L122) | `ResultTransform transform = (IJSEngine eng, string serialized) @trusted {` | _(missing)_ |
| [`source/dun/builtins/fetch.d:127`](../../source/dun/builtins/fetch.d#L127) | `asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {` | _(missing)_ |
| [`source/dun/builtins/fetch.d:149`](../../source/dun/builtins/fetch.d#L149) | `auto hdrSlice = (() @trusted => hdrs[])();` | _(missing)_ |
| [`source/dun/builtins/fetch.d:153`](../../source/dun/builtins/fetch.d#L153) | `return (() @trusted => cast(string) s[])();` | _(missing)_ |
| [`source/dun/builtins/fetch.d:222`](../../source/dun/builtins/fetch.d#L222) | `string redirectMode = "follow") @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:281`](../../source/dun/builtins/fetch.d#L281) | `(ubyte[] buf) @trusted {` | _(missing)_ |
| [`source/dun/builtins/fetch.d:329`](../../source/dun/builtins/fetch.d#L329) | `(ubyte[] buf) @trusted {` | _(missing)_ |
| [`source/dun/builtins/fetch.d:433`](../../source/dun/builtins/fetch.d#L433) | `return (() @trusted => cast(string) r[])();` | _(missing)_ |
| [`source/dun/builtins/fetch.d:436`](../../source/dun/builtins/fetch.d#L436) | `FetchResult readHttpResponse(scope int delegate(ubyte[]) @trusted reader) @tr...` | _(missing)_ |
| [`source/dun/builtins/fetch.d:610`](../../source/dun/builtins/fetch.d#L610) | `int tcpConnect(string host, ushort port) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:646`](../../source/dun/builtins/fetch.d#L646) | `int tcpConnect(string, ushort) @trusted { return -1; }` | _(missing)_ |
| [`source/dun/builtins/fetch.d:665`](../../source/dun/builtins/fetch.d#L665) | `private void ensureHeadersFlattener(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:695`](../../source/dun/builtins/fetch.d#L695) | `private void ensureResponseBuilder(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:721`](../../source/dun/builtins/fetch.d#L721) | `JSHandle makeResponse(IJSEngine engine, FetchResult r) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:795`](../../source/dun/builtins/fetch.d#L795) | `JSHandle makeResponseFallback(IJSEngine engine, FetchResult r) @trusted` | _(missing)_ |
| [`source/dun/builtins/fetch.d:859`](../../source/dun/builtins/fetch.d#L859) | `return (() @trusted => cast(string) r[])();` | _(missing)_ |
| [`source/dun/builtins/http.d:31`](../../source/dun/builtins/http.d#L31) | `private string sizeToStr(size_t n) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:58`](../../source/dun/builtins/http.d#L58) | `private string internHeaderName(const(char)[] raw) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:92`](../../source/dun/builtins/http.d#L92) | `void registerHttpModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:152`](../../source/dun/builtins/http.d#L152) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:167`](../../source/dun/builtins/http.d#L167) | `private extern (C) int httpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/builtins/http.d:193`](../../source/dun/builtins/http.d#L193) | `private void ensureHttpPoller() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:215`](../../source/dun/builtins/http.d#L215) | `void ensureWriteHeadFlattener(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:238`](../../source/dun/builtins/http.d#L238) | `void ensureHttpFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:386`](../../source/dun/builtins/http.d#L386) | `void ensureBufCapacity(size_t needed) nothrow @trusted {` | _(missing)_ |
| [`source/dun/builtins/http.d:401`](../../source/dun/builtins/http.d#L401) | `void ensureRespCapacity(size_t needed) nothrow @trusted {` | _(missing)_ |
| [`source/dun/builtins/http.d:412`](../../source/dun/builtins/http.d#L412) | `void initBuffers() nothrow @trusted {` | _(missing)_ |
| [`source/dun/builtins/http.d:421`](../../source/dun/builtins/http.d#L421) | `void resetForKeepAlive() nothrow @trusted {` | _(missing)_ |
| [`source/dun/builtins/http.d:457`](../../source/dun/builtins/http.d#L457) | `int allocServerSlot() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:472`](../../source/dun/builtins/http.d#L472) | `void freeServerSlot(int slot) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:482`](../../source/dun/builtins/http.d#L482) | `void closeConnFd(HttpConnState* conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:503`](../../source/dun/builtins/http.d#L503) | `int allocConnSlot() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:522`](../../source/dun/builtins/http.d#L522) | `void freeConnSlot(int slot) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:537`](../../source/dun/builtins/http.d#L537) | `void* sslCtx = null) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:564`](../../source/dun/builtins/http.d#L564) | `JSHandle jsHttpCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/http.d:581`](../../source/dun/builtins/http.d#L581) | `JSHandle makeHttpServerObj(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:618`](../../source/dun/builtins/http.d#L618) | `JSHandle jsHttpServerSetTimeout(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/builtins/http.d:634`](../../source/dun/builtins/http.d#L634) | `JSHandle jsHttpServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/http.d:743`](../../source/dun/builtins/http.d#L743) | `JSHandle jsHttpServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/http.d:842`](../../source/dun/builtins/http.d#L842) | `JSHandle jsHttpServerAddress(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/http.d:867`](../../source/dun/builtins/http.d#L867) | `JSHandle jsHttpServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:915`](../../source/dun/builtins/http.d#L915) | `JSHandle makeReqObj(IJSEngine engine, int connId) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:963`](../../source/dun/builtins/http.d#L963) | `JSHandle jsGetConnHeaders(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http.d:982`](../../source/dun/builtins/http.d#L982) | `JSHandle jsReqOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1026`](../../source/dun/builtins/http.d#L1026) | `JSHandle makeResObj(IJSEngine engine, int connId) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1058`](../../source/dun/builtins/http.d#L1058) | `JSHandle jsResSetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:1096`](../../source/dun/builtins/http.d#L1096) | `JSHandle jsResGetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:1135`](../../source/dun/builtins/http.d#L1135) | `JSHandle jsResGetHeaders(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http.d:1163`](../../source/dun/builtins/http.d#L1163) | `JSHandle jsResHasHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:1185`](../../source/dun/builtins/http.d#L1185) | `JSHandle jsResRemoveHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/http.d:1203`](../../source/dun/builtins/http.d#L1203) | `private string toLowerSimple(string s) @trusted pure nothrow` | _(missing)_ |
| [`source/dun/builtins/http.d:1222`](../../source/dun/builtins/http.d#L1222) | `JSHandle jsResWriteHead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:1293`](../../source/dun/builtins/http.d#L1293) | `void syncStatusCode(IJSEngine engine, JSHandle thisVal, HttpConnState* conn) ...` | _(missing)_ |
| [`source/dun/builtins/http.d:1301`](../../source/dun/builtins/http.d#L1301) | `void syncJsHeaders(IJSEngine engine, JSHandle thisVal, HttpConnState* conn) @...` | _(missing)_ |
| [`source/dun/builtins/http.d:1330`](../../source/dun/builtins/http.d#L1330) | `JSHandle jsResWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1368`](../../source/dun/builtins/http.d#L1368) | `JSHandle jsResEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1600`](../../source/dun/builtins/http.d#L1600) | `void bufferStatusLine(HttpConnState* conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1608`](../../source/dun/builtins/http.d#L1608) | `void bufAppend(const(char)[] s) nothrow @trusted {` | _(missing)_ |
| [`source/dun/builtins/http.d:1642`](../../source/dun/builtins/http.d#L1642) | `void bufferData(HttpConnState* conn, const(char)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1656`](../../source/dun/builtins/http.d#L1656) | `void flushResponse(HttpConnState* conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1689`](../../source/dun/builtins/http.d#L1689) | `void sendError(HttpConnState* conn, int status, string text, int connSlot = -...` | _(missing)_ |
| [`source/dun/builtins/http.d:1706`](../../source/dun/builtins/http.d#L1706) | `void sendChunk(HttpConnState* conn, string data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1723`](../../source/dun/builtins/http.d#L1723) | `void sendRaw(HttpConnState* conn, string data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1755`](../../source/dun/builtins/http.d#L1755) | `public void pollHttpIO() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1810`](../../source/dun/builtins/http.d#L1810) | `public bool hasActiveHttpIO() nothrow @nogc @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1816`](../../source/dun/builtins/http.d#L1816) | `public void dispatchHttpCallbacks() @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1866`](../../source/dun/builtins/http.d#L1866) | `void acceptHttpConnection(int srvId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:1968`](../../source/dun/builtins/http.d#L1968) | `void readHttpData(int cid) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:2043`](../../source/dun/builtins/http.d#L2043) | `void tryParseHeaders(HttpConnState* conn, int cid) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http.d:2105`](../../source/dun/builtins/http.d#L2105) | `void parseRequestHeaders(HttpConnState* conn, const(char)[] text) nothrow @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:9`](../../source/dun/builtins/http2.d#L9) | `void registerHttp2Module(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:30`](../../source/dun/builtins/http2.d#L30) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:42`](../../source/dun/builtins/http2.d#L42) | `private extern (C) int http2ModuleInit(JSContext* ctx, JSModuleDef* m) nothro...` | _(missing)_ |
| [`source/dun/builtins/http2.d:258`](../../source/dun/builtins/http2.d#L258) | `HeaderField[] decode(scope const(ubyte)[] block) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/http2.d:340`](../../source/dun/builtins/http2.d#L340) | `private void addToDynamicTable(HeaderField entry) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:356`](../../source/dun/builtins/http2.d#L356) | `private void evictDynamicTable() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:389`](../../source/dun/builtins/http2.d#L389) | `bool decodeString(scope const(ubyte)[] data, ref size_t pos, out string resul...` | _(missing)_ |
| [`source/dun/builtins/http2.d:680`](../../source/dun/builtins/http2.d#L680) | `string huffmanDecode(const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:753`](../../source/dun/builtins/http2.d#L753) | `ubyte[] hpackEncode(HeaderField[] headers) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:782`](../../source/dun/builtins/http2.d#L782) | `return (() @trusted => result[])();` | _(missing)_ |
| [`source/dun/builtins/http2.d:801`](../../source/dun/builtins/http2.d#L801) | `nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:819`](../../source/dun/builtins/http2.d#L819) | `ubyte[] encodeIntHpack(uint value, int prefix, ubyte pattern) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:823`](../../source/dun/builtins/http2.d#L823) | `return (() @trusted => result[])();` | _(missing)_ |
| [`source/dun/builtins/http2.d:826`](../../source/dun/builtins/http2.d#L826) | `void encodeLiteralStringTo(ref Appender!(ubyte[]) result, string s) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/http2.d:834`](../../source/dun/builtins/http2.d#L834) | `ubyte[] encodeLiteralString(string s) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:838`](../../source/dun/builtins/http2.d#L838) | `return (() @trusted => result[])();` | _(missing)_ |
| [`source/dun/builtins/http2.d:902`](../../source/dun/builtins/http2.d#L902) | `void sendConnectionPreface() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:928`](../../source/dun/builtins/http2.d#L928) | `void processReceivedData(const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:967`](../../source/dun/builtins/http2.d#L967) | `void processFrame(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:999`](../../source/dun/builtins/http2.d#L999) | `void processSettings(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1057`](../../source/dun/builtins/http2.d#L1057) | `void processHeaders(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1107`](../../source/dun/builtins/http2.d#L1107) | `void processData(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1148`](../../source/dun/builtins/http2.d#L1148) | `void processWindowUpdate(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1171`](../../source/dun/builtins/http2.d#L1171) | `void processPing(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1184`](../../source/dun/builtins/http2.d#L1184) | `void processRstStream(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1191`](../../source/dun/builtins/http2.d#L1191) | `void processGoaway(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1198`](../../source/dun/builtins/http2.d#L1198) | `void sendHeaders(uint streamId, HeaderField[] headers, bool endStream) nothro...` | _(missing)_ |
| [`source/dun/builtins/http2.d:1212`](../../source/dun/builtins/http2.d#L1212) | `void sendData(uint streamId, const(ubyte)[] data, bool endStream) nothrow @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:1236`](../../source/dun/builtins/http2.d#L1236) | `void sendGoaway(H2Error errorCode) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1253`](../../source/dun/builtins/http2.d#L1253) | `void sendRstStream(uint streamId, H2Error errorCode) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1267`](../../source/dun/builtins/http2.d#L1267) | `void sendWindowUpdate(uint streamId, int increment) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1280`](../../source/dun/builtins/http2.d#L1280) | `void sendRawBytes(const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1313`](../../source/dun/builtins/http2.d#L1313) | `void sendRawBytes(const(char)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1320`](../../source/dun/builtins/http2.d#L1320) | `void dispatchStreamRequest(uint streamId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1357`](../../source/dun/builtins/http2.d#L1357) | `ubyte[] encodeSettings(ref H2Settings s) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1390`](../../source/dun/builtins/http2.d#L1390) | `void ensureH2FnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1464`](../../source/dun/builtins/http2.d#L1464) | `void sendConnectionPreface() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1487`](../../source/dun/builtins/http2.d#L1487) | `void sendHeaders(uint streamId, HeaderField[] headers, bool endStream) nothro...` | _(missing)_ |
| [`source/dun/builtins/http2.d:1501`](../../source/dun/builtins/http2.d#L1501) | `void sendData(uint streamId, const(ubyte)[] data, bool endStream) nothrow @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:1525`](../../source/dun/builtins/http2.d#L1525) | `void sendGoaway(H2Error errorCode) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1542`](../../source/dun/builtins/http2.d#L1542) | `void sendWindowUpdate(uint streamId, int increment) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1555`](../../source/dun/builtins/http2.d#L1555) | `void processReceivedData(const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1575`](../../source/dun/builtins/http2.d#L1575) | `void processFrame(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1602`](../../source/dun/builtins/http2.d#L1602) | `void processSettings(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1652`](../../source/dun/builtins/http2.d#L1652) | `void processResponseHeaders(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1714`](../../source/dun/builtins/http2.d#L1714) | `void processResponseData(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1750`](../../source/dun/builtins/http2.d#L1750) | `void processWindowUpdate(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1763`](../../source/dun/builtins/http2.d#L1763) | `void processPing(ref H2Frame frame) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1772`](../../source/dun/builtins/http2.d#L1772) | `void dispatchEndCallback(uint streamId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1786`](../../source/dun/builtins/http2.d#L1786) | `void sendRawBytes(const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1819`](../../source/dun/builtins/http2.d#L1819) | `void sendRawBytes(const(char)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1824`](../../source/dun/builtins/http2.d#L1824) | `void closeConnection() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1857`](../../source/dun/builtins/http2.d#L1857) | `private void ensureH2Poller() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1863`](../../source/dun/builtins/http2.d#L1863) | `JSHandle makeHttp2Constants(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:1883`](../../source/dun/builtins/http2.d#L1883) | `JSHandle jsHttp2CreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/http2.d:1916`](../../source/dun/builtins/http2.d#L1916) | `JSHandle jsHttp2CreateSecureServer(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2008`](../../source/dun/builtins/http2.d#L2008) | `void ensureTlsServerInit() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2025`](../../source/dun/builtins/http2.d#L2025) | `void parseH2Url(string url, out string host, out ushort port, out bool useTls...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2089`](../../source/dun/builtins/http2.d#L2089) | `JSHandle jsHttp2Connect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2257`](../../source/dun/builtins/http2.d#L2257) | `JSHandle jsH2ClientSessionOn(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2289`](../../source/dun/builtins/http2.d#L2289) | `JSHandle jsH2ClientRequest(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2383`](../../source/dun/builtins/http2.d#L2383) | `JSHandle jsH2ClientClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2410`](../../source/dun/builtins/http2.d#L2410) | `JSHandle jsH2StreamOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2454`](../../source/dun/builtins/http2.d#L2454) | `JSHandle jsH2StreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2488`](../../source/dun/builtins/http2.d#L2488) | `JSHandle jsH2StreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2516`](../../source/dun/builtins/http2.d#L2516) | `JSHandle makeH2ServerObj(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2527`](../../source/dun/builtins/http2.d#L2527) | `JSHandle jsH2ServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2618`](../../source/dun/builtins/http2.d#L2618) | `JSHandle jsH2ServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2650`](../../source/dun/builtins/http2.d#L2650) | `JSHandle jsH2ServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2675`](../../source/dun/builtins/http2.d#L2675) | `JSHandle makeH2ResponseObj(IJSEngine engine, ref H2Connection conn, uint stre...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2699`](../../source/dun/builtins/http2.d#L2699) | `int findOrCreateResponseState(uint streamId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2713`](../../source/dun/builtins/http2.d#L2713) | `JSHandle jsH2ResWriteHead(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2732`](../../source/dun/builtins/http2.d#L2732) | `JSHandle jsH2ResSetHeader(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2755`](../../source/dun/builtins/http2.d#L2755) | `JSHandle jsH2ResWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/http2.d:2787`](../../source/dun/builtins/http2.d#L2787) | `JSHandle jsH2ResEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2825`](../../source/dun/builtins/http2.d#L2825) | `void sendH2ResponseHeaders(uint streamId, H2ResponseState* rs) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2854`](../../source/dun/builtins/http2.d#L2854) | `public void pollHttp2IO() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2890`](../../source/dun/builtins/http2.d#L2890) | `void acceptH2Connection(int srvId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2953`](../../source/dun/builtins/http2.d#L2953) | `void completeH2ClientConnect(ref ClientH2Session session) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:2991`](../../source/dun/builtins/http2.d#L2991) | `void readH2Data(ref H2Connection conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/http2.d:3015`](../../source/dun/builtins/http2.d#L3015) | `void readH2ClientData(ref ClientH2Session session) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/https.d:6`](../../source/dun/builtins/https.d#L6) | `void registerHttpsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/https.d:36`](../../source/dun/builtins/https.d#L36) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/https.d:49`](../../source/dun/builtins/https.d#L49) | `private extern (C) int httpsModuleInit(JSContext* ctx, JSModuleDef* m) nothro...` | _(missing)_ |
| [`source/dun/builtins/https.d:69`](../../source/dun/builtins/https.d#L69) | `JSHandle jsHttpsCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/https.d:141`](../../source/dun/builtins/https.d#L141) | `void ensureTlsServerInit() @trusted nothrow @nogc` | _(missing)_ |
| [`source/dun/builtins/net.d:14`](../../source/dun/builtins/net.d#L14) | `void registerNetModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:84`](../../source/dun/builtins/net.d#L84) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:97`](../../source/dun/builtins/net.d#L97) | `private extern (C) int netModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/net.d:121`](../../source/dun/builtins/net.d#L121) | `private void ensurePoller() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:129`](../../source/dun/builtins/net.d#L129) | `string formatIPv4(uint ip) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:190`](../../source/dun/builtins/net.d#L190) | `JSHandle jsCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/net.d:226`](../../source/dun/builtins/net.d#L226) | `JSHandle jsCreateConnection(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/net.d:377`](../../source/dun/builtins/net.d#L377) | `void ensureNetFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:390`](../../source/dun/builtins/net.d#L390) | `JSHandle makeServerObject(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:405`](../../source/dun/builtins/net.d#L405) | `JSHandle makeSocketObject(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:437`](../../source/dun/builtins/net.d#L437) | `JSHandle jsServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/net.d:532`](../../source/dun/builtins/net.d#L532) | `JSHandle jsServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/net.d:565`](../../source/dun/builtins/net.d#L565) | `JSHandle jsServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:589`](../../source/dun/builtins/net.d#L589) | `JSHandle jsSocketOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:619`](../../source/dun/builtins/net.d#L619) | `JSHandle jsSocketWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/net.d:659`](../../source/dun/builtins/net.d#L659) | `JSHandle jsSocketEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/net.d:719`](../../source/dun/builtins/net.d#L719) | `public void pollNetIO() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:738`](../../source/dun/builtins/net.d#L738) | `void registerServerForPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:748`](../../source/dun/builtins/net.d#L748) | `void unregisterServerFromPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:757`](../../source/dun/builtins/net.d#L757) | `void registerSocketForPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:767`](../../source/dun/builtins/net.d#L767) | `void unregisterSocketFromPolling(int id) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:776`](../../source/dun/builtins/net.d#L776) | `void acceptPendingConnections(int srvId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:861`](../../source/dun/builtins/net.d#L861) | `void readSocketData(int sockId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:919`](../../source/dun/builtins/net.d#L919) | `JSHandle jsNetIsIP(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/net.d:931`](../../source/dun/builtins/net.d#L931) | `JSHandle jsNetIsIPv4(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/net.d:940`](../../source/dun/builtins/net.d#L940) | `JSHandle jsNetIsIPv6(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/ws.d:27`](../../source/dun/builtins/ws.d#L27) | `void registerWsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:80`](../../source/dun/builtins/ws.d#L80) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:90`](../../source/dun/builtins/ws.d#L90) | `private extern (C) int wsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/ws.d:113`](../../source/dun/builtins/ws.d#L113) | `private void ensureWsPoller() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:126`](../../source/dun/builtins/ws.d#L126) | `void ensureWsFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:212`](../../source/dun/builtins/ws.d#L212) | `ubyte[] buildWsFrame(WsOpcode opcode, const(ubyte)[] payload, bool mask) @tru...` | _(missing)_ |
| [`source/dun/builtins/ws.d:269`](../../source/dun/builtins/ws.d#L269) | `ParseResult parseWsFrame(const(ubyte)[] data) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/ws.d:322`](../../source/dun/builtins/ws.d#L322) | `string computeAcceptKey(string clientKey) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:335`](../../source/dun/builtins/ws.d#L335) | `JSHandle jsWsCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/ws.d:376`](../../source/dun/builtins/ws.d#L376) | `JSHandle makeWsServerObj(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:392`](../../source/dun/builtins/ws.d#L392) | `JSHandle jsWsServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/ws.d:494`](../../source/dun/builtins/ws.d#L494) | `JSHandle jsWsServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/ws.d:517`](../../source/dun/builtins/ws.d#L517) | `JSHandle jsWsServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/ws.d:552`](../../source/dun/builtins/ws.d#L552) | `JSHandle jsWsConnect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/ws.d:651`](../../source/dun/builtins/ws.d#L651) | `JSHandle makeWsClientObj(IJSEngine engine, int cid) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:667`](../../source/dun/builtins/ws.d#L667) | `JSHandle jsWsClientOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/ws.d:709`](../../source/dun/builtins/ws.d#L709) | `JSHandle jsWsClientSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/ws.d:742`](../../source/dun/builtins/ws.d#L742) | `JSHandle jsWsClientClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/ws.d:788`](../../source/dun/builtins/ws.d#L788) | `JSHandle makeWsServerConnObj(IJSEngine engine, int cid) @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:805`](../../source/dun/builtins/ws.d#L805) | `public void pollWsIO() nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:833`](../../source/dun/builtins/ws.d#L833) | `void acceptWsConnection(int srvId) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:886`](../../source/dun/builtins/ws.d#L886) | `void readWsData(int cid) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:913`](../../source/dun/builtins/ws.d#L913) | `void handleHandshake(WsConnState* conn, int cid) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:1025`](../../source/dun/builtins/ws.d#L1025) | `void processFrames(WsConnState* conn, int cid) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:1110`](../../source/dun/builtins/ws.d#L1110) | `void closeConn(WsConnState* conn) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:1152`](../../source/dun/builtins/ws.d#L1152) | `void sendRawBytes(int fd, const(ubyte)[] data) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:1168`](../../source/dun/builtins/ws.d#L1168) | `void sendClientHandshake(int fd, string host, ushort port, string path) nothr...` | _(missing)_ |
| [`source/dun/builtins/ws.d:1196`](../../source/dun/builtins/ws.d#L1196) | `string extractHeader(const(char)[] text, string name) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/ws.d:1221`](../../source/dun/builtins/ws.d#L1221) | `bool parseWsUrl(string url, out string host, out ushort port, out string path...` | _(missing)_ |
| [`source/dun/builtins/ws.d:1268`](../../source/dun/builtins/ws.d#L1268) | `uint resolveHost(string host) nothrow @trusted` | _(missing)_ |

## other (549 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/app.d:46`](../../source/dun/app.d#L46) | `auto bundleStr = () @trusted { return cast(string) bundle; }();` | _(missing)_ |
| [`source/dun/app.d:112`](../../source/dun/app.d#L112) | `int runEmbeddedBundle(string[] args, string bundle) @trusted` | /// Entry point when the running executable was produced by /// \`dun bundle ... |
| [`source/dun/app.d:393`](../../source/dun/app.d#L393) | `int runWatchMode(T)(T config) @trusted` | _(missing)_ |
| [`source/dun/app.d:515`](../../source/dun/app.d#L515) | `void printVersion() @trusted` | _(missing)_ |
| [`source/dun/app.d:721`](../../source/dun/app.d#L721) | `int runSingleTest(T)(T config, string filePath) @trusted` | _(missing)_ |
| [`source/dun/app.d:918`](../../source/dun/app.d#L918) | `int runSingleBench(T)(T config, string filePath) @trusted` | _(missing)_ |
| [`source/dun/app.d:1297`](../../source/dun/app.d#L1297) | `string[] discoverFiles(string[] patterns) @trusted` | _(missing)_ |
| [`source/dun/app.d:1751`](../../source/dun/app.d#L1751) | `bool findTypescriptInstall(string scriptPath) @trusted` | /// Walk ancestors of \`scriptPath\` for \`node_modules/typescript\`, /// the... |
| [`source/dun/app.d:1778`](../../source/dun/app.d#L1778) | `string runTranspile(string source, string filename) @trusted` | /// Transpile via \`ts.transpileModule()\` — full TS-spec correctness /// (... |
| [`source/dun/app.d:1950`](../../source/dun/app.d#L1950) | `private string readTscVersion(string scriptPath) @trusted` | /// Read the installed typescript package version. Used as a cache-key /// co... |
| [`source/dun/app.d:1986`](../../source/dun/app.d#L1986) | `string runTypecheck(string source, string filename, out int rc) @trusted` | /// Run user's installed \`typescript\` with diagnostics and emit JS. /// \`r... |
| [`source/dun/app.d:2326`](../../source/dun/app.d#L2326) | `void loadDotEnv() @trusted` | _(missing)_ |
| [`source/dun/app.d:2391`](../../source/dun/app.d#L2391) | `void writeStderr(const(char)[] msg) @trusted` | _(missing)_ |
| [`source/dun/builtins/assert_.d:7`](../../source/dun/builtins/assert_.d#L7) | `void registerAssertModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/assert_.d:19`](../../source/dun/builtins/assert_.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/assert_.d:48`](../../source/dun/builtins/assert_.d#L48) | `private extern(C) int assertModuleInit(JSContext* ctx, JSModuleDef* m) nothro...` | _(missing)_ |
| [`source/dun/builtins/async_hooks.d:12`](../../source/dun/builtins/async_hooks.d#L12) | `void registerAsyncHooksModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/async_hooks.d:49`](../../source/dun/builtins/async_hooks.d#L49) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/async_hooks.d:60`](../../source/dun/builtins/async_hooks.d#L60) | `private extern (C) int asyncHooksModuleInit(JSContext* ctx, JSModuleDef* m) n...` | _(missing)_ |
| [`source/dun/builtins/async_hooks.d:118`](../../source/dun/builtins/async_hooks.d#L118) | `JSHandle jsAlsRun(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | /// als.run(store, callback): push store, call callback, pop store |
| [`source/dun/builtins/async_hooks.d:170`](../../source/dun/builtins/async_hooks.d#L170) | `JSHandle jsAlsGetStore(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | /// als.getStore(): return top of stack (or undefined if empty) |
| [`source/dun/builtins/async_hooks.d:184`](../../source/dun/builtins/async_hooks.d#L184) | `JSHandle jsAlsEnterWith(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | /// als.enterWith(store): push store (doesn't auto-pop) |
| [`source/dun/builtins/async_hooks.d:202`](../../source/dun/builtins/async_hooks.d#L202) | `JSHandle jsAlsDisable(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | /// als.disable(): clear entire stack |
| [`source/dun/builtins/buffer.d:8`](../../source/dun/builtins/buffer.d#L8) | `void registerBufferModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:65`](../../source/dun/builtins/buffer.d#L65) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:75`](../../source/dun/builtins/buffer.d#L75) | `private extern (C) int bufferModuleInit(JSContext* ctx, JSModuleDef* m) nothr...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:111`](../../source/dun/builtins/buffer.d#L111) | `void ensureBufferFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:318`](../../source/dun/builtins/buffer.d#L318) | `string bytesToHex(const(ubyte)[] data) @trusted nothrow` | _(missing)_ |
| [`source/dun/builtins/buffer.d:331`](../../source/dun/builtins/buffer.d#L331) | `ubyte[] hexToBytes(string hex) @trusted` | _(missing)_ |
| [`source/dun/builtins/buffer.d:378`](../../source/dun/builtins/buffer.d#L378) | `JSHandle jsBufferFrom(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:548`](../../source/dun/builtins/buffer.d#L548) | `JSHandle jsBufferAlloc(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:615`](../../source/dun/builtins/buffer.d#L615) | `JSHandle jsBufferAllocUnsafe(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:630`](../../source/dun/builtins/buffer.d#L630) | `JSHandle jsBufferIsBuffer(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:644`](../../source/dun/builtins/buffer.d#L644) | `JSHandle jsBufferConcat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:776`](../../source/dun/builtins/buffer.d#L776) | `JSHandle jsBufferToString(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:817`](../../source/dun/builtins/buffer.d#L817) | `auto b64 = (() @trusted => cast(string) Base64.encode(slice))();` | _(missing)_ |
| [`source/dun/builtins/buffer.d:859`](../../source/dun/builtins/buffer.d#L859) | `JSHandle jsBufferToJSON(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:875`](../../source/dun/builtins/buffer.d#L875) | `JSHandle jsBufferSlice(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:898`](../../source/dun/builtins/buffer.d#L898) | `JSHandle jsBufferCopy(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:966`](../../source/dun/builtins/buffer.d#L966) | `JSHandle jsBufferEquals(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:979`](../../source/dun/builtins/buffer.d#L979) | `JSHandle jsBufferIndexOf(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1008`](../../source/dun/builtins/buffer.d#L1008) | `JSHandle jsBufferFill(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1039`](../../source/dun/builtins/buffer.d#L1039) | `JSHandle jsBufferWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1121`](../../source/dun/builtins/buffer.d#L1121) | `JSHandle jsBufferReadUInt8(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1136`](../../source/dun/builtins/buffer.d#L1136) | `JSHandle jsBufferWriteUInt8(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1157`](../../source/dun/builtins/buffer.d#L1157) | `JSHandle jsBufferIsEncoding(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1176`](../../source/dun/builtins/buffer.d#L1176) | `JSHandle jsBufferStaticCompare(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1196`](../../source/dun/builtins/buffer.d#L1196) | `JSHandle jsBufferReadUInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1209`](../../source/dun/builtins/buffer.d#L1209) | `JSHandle jsBufferReadUInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1223`](../../source/dun/builtins/buffer.d#L1223) | `JSHandle jsBufferReadUInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1236`](../../source/dun/builtins/buffer.d#L1236) | `JSHandle jsBufferReadUInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1250`](../../source/dun/builtins/buffer.d#L1250) | `JSHandle jsBufferReadInt8(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1262`](../../source/dun/builtins/buffer.d#L1262) | `JSHandle jsBufferReadInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1275`](../../source/dun/builtins/buffer.d#L1275) | `JSHandle jsBufferReadInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1289`](../../source/dun/builtins/buffer.d#L1289) | `JSHandle jsBufferReadInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1302`](../../source/dun/builtins/buffer.d#L1302) | `JSHandle jsBufferReadInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1316`](../../source/dun/builtins/buffer.d#L1316) | `JSHandle jsBufferReadFloatLE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1330`](../../source/dun/builtins/buffer.d#L1330) | `JSHandle jsBufferReadFloatBE(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1346`](../../source/dun/builtins/buffer.d#L1346) | `JSHandle jsBufferReadDoubleLE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1361`](../../source/dun/builtins/buffer.d#L1361) | `JSHandle jsBufferReadDoubleBE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1377`](../../source/dun/builtins/buffer.d#L1377) | `JSHandle jsBufferWriteUInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1393`](../../source/dun/builtins/buffer.d#L1393) | `JSHandle jsBufferWriteUInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1409`](../../source/dun/builtins/buffer.d#L1409) | `JSHandle jsBufferWriteUInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1427`](../../source/dun/builtins/buffer.d#L1427) | `JSHandle jsBufferWriteUInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1443`](../../source/dun/builtins/buffer.d#L1443) | `JSHandle jsBufferWriteInt16LE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1459`](../../source/dun/builtins/buffer.d#L1459) | `JSHandle jsBufferWriteInt16BE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1475`](../../source/dun/builtins/buffer.d#L1475) | `JSHandle jsBufferWriteInt32LE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1493`](../../source/dun/builtins/buffer.d#L1493) | `JSHandle jsBufferWriteInt32BE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1509`](../../source/dun/builtins/buffer.d#L1509) | `JSHandle jsBufferWriteFloatLE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1525`](../../source/dun/builtins/buffer.d#L1525) | `JSHandle jsBufferWriteFloatBE(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1542`](../../source/dun/builtins/buffer.d#L1542) | `JSHandle jsBufferWriteDoubleLE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1558`](../../source/dun/builtins/buffer.d#L1558) | `JSHandle jsBufferWriteDoubleBE(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1575`](../../source/dun/builtins/buffer.d#L1575) | `JSHandle jsBufferCompare(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1594`](../../source/dun/builtins/buffer.d#L1594) | `JSHandle jsBufferIncludes(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1619`](../../source/dun/builtins/buffer.d#L1619) | `JSHandle jsBufferSubarray(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1650`](../../source/dun/builtins/buffer.d#L1650) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/builtins/buffer.d:1665`](../../source/dun/builtins/buffer.d#L1665) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/builtins/cluster.d:20`](../../source/dun/builtins/cluster.d#L20) | `private void ensureWorkerFnsCached(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:47`](../../source/dun/builtins/cluster.d#L47) | `void registerClusterModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:85`](../../source/dun/builtins/cluster.d#L85) | `public bool hasActiveClusterWorkers() nothrow @trusted` | /// Returns true if there are active cluster worker processes being tracked. |
| [`source/dun/builtins/cluster.d:92`](../../source/dun/builtins/cluster.d#L92) | `public void pollClusterWorkers() nothrow @trusted` | /// Poll for exited worker processes (called from event loop tick). /// Uses ... |
| [`source/dun/builtins/cluster.d:166`](../../source/dun/builtins/cluster.d#L166) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:178`](../../source/dun/builtins/cluster.d#L178) | `private extern (C) int clusterModuleInit(JSContext* ctx, JSModuleDef* m) noth...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:197`](../../source/dun/builtins/cluster.d#L197) | `bool checkRunPerm(DunState* state) nothrow @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:204`](../../source/dun/builtins/cluster.d#L204) | `JSHandle jsClusterFork(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:293`](../../source/dun/builtins/cluster.d#L293) | `JSHandle jsClusterOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:328`](../../source/dun/builtins/cluster.d#L328) | `JSHandle jsClusterSetupPrimary(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:342`](../../source/dun/builtins/cluster.d#L342) | `JSHandle jsClusterDisconnect(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:349`](../../source/dun/builtins/cluster.d#L349) | `JSHandle makeWorkerSelf(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:368`](../../source/dun/builtins/cluster.d#L368) | `JSHandle jsWorkerSend(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:375`](../../source/dun/builtins/cluster.d#L375) | `JSHandle jsWorkerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/cluster.d:382`](../../source/dun/builtins/cluster.d#L382) | `JSHandle jsWorkerDisconnect(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:389`](../../source/dun/builtins/cluster.d#L389) | `JSHandle jsWorkerKill(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:396`](../../source/dun/builtins/cluster.d#L396) | `JSHandle jsWorkerIsConnected(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/cluster.d:403`](../../source/dun/builtins/cluster.d#L403) | `JSHandle jsWorkerIsDead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/events.d:7`](../../source/dun/builtins/events.d#L7) | `void registerEventsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/events.d:21`](../../source/dun/builtins/events.d#L21) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/events.d:40`](../../source/dun/builtins/events.d#L40) | `private extern (C) int eventsModuleInit(JSContext* ctx, JSModuleDef* m) nothr...` | _(missing)_ |
| [`source/dun/builtins/helpers.d:16`](../../source/dun/builtins/helpers.d#L16) | `string filename, string what) @trusted` | /// Eval a JS module-init blob and log to stderr on failure. Replaces /// the... |
| [`source/dun/builtins/node_test.d:6`](../../source/dun/builtins/node_test.d#L6) | `void registerNodeTestModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/node_test.d:31`](../../source/dun/builtins/node_test.d#L31) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/node_test.d:48`](../../source/dun/builtins/node_test.d#L48) | `private extern (C) int nodeTestModuleInit(JSContext* ctx, JSModuleDef* m) not...` | _(missing)_ |
| [`source/dun/builtins/os.d:12`](../../source/dun/builtins/os.d#L12) | `private JSHandle throwSysPerm(IJSEngine engine, string resource) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:19`](../../source/dun/builtins/os.d#L19) | `void registerOsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:67`](../../source/dun/builtins/os.d#L67) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:88`](../../source/dun/builtins/os.d#L88) | `private extern (C) int osModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/os.d:105`](../../source/dun/builtins/os.d#L105) | `IJSEngine getEngine(void* ctx) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:143`](../../source/dun/builtins/os.d#L143) | `JSHandle jsOsPlatform(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/os.d:149`](../../source/dun/builtins/os.d#L149) | `JSHandle jsOsArch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:155`](../../source/dun/builtins/os.d#L155) | `JSHandle jsOsType(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:164`](../../source/dun/builtins/os.d#L164) | `JSHandle jsOsHostname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/os.d:196`](../../source/dun/builtins/os.d#L196) | `JSHandle jsOsHomedir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:211`](../../source/dun/builtins/os.d#L211) | `JSHandle jsOsTmpdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:225`](../../source/dun/builtins/os.d#L225) | `JSHandle jsOsCpus(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:256`](../../source/dun/builtins/os.d#L256) | `JSHandle jsOsTotalmem(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/os.d:288`](../../source/dun/builtins/os.d#L288) | `JSHandle jsOsFreemem(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:319`](../../source/dun/builtins/os.d#L319) | `JSHandle jsOsUptime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/os.d:339`](../../source/dun/builtins/os.d#L339) | `JSHandle jsOsRelease(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:360`](../../source/dun/builtins/os.d#L360) | `JSHandle jsOsEndianness(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/os.d:369`](../../source/dun/builtins/os.d#L369) | `JSHandle jsOsNetworkInterfaces(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/os.d:379`](../../source/dun/builtins/os.d#L379) | `JSHandle jsOsUserInfo(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/os.d:440`](../../source/dun/builtins/os.d#L440) | `JSHandle jsOsLoadavg(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:472`](../../source/dun/builtins/os.d#L472) | `JSHandle jsOsVersion(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:493`](../../source/dun/builtins/os.d#L493) | `JSHandle jsOsMachine(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/os.d:516`](../../source/dun/builtins/os.d#L516) | `JSHandle jsOsAvailableParallelism(void* ctx, JSHandle thisVal, scope JSHandle...` | _(missing)_ |
| [`source/dun/builtins/os.d:527`](../../source/dun/builtins/os.d#L527) | `JSHandle jsOsSetPriority(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/os.d:557`](../../source/dun/builtins/os.d#L557) | `JSHandle jsOsGetPriority(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/path.d:6`](../../source/dun/builtins/path.d#L6) | `void registerPathModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/path.d:91`](../../source/dun/builtins/path.d#L91) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/path.d:105`](../../source/dun/builtins/path.d#L105) | `private extern (C) int pathModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/builtins/path.d:127`](../../source/dun/builtins/path.d#L127) | `JSHandle jsPathJoin(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/path.d:145`](../../source/dun/builtins/path.d#L145) | `JSHandle jsPathBasename(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/path.d:162`](../../source/dun/builtins/path.d#L162) | `JSHandle jsPathDirname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/path.d:176`](../../source/dun/builtins/path.d#L176) | `JSHandle jsPathExtname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/path.d:190`](../../source/dun/builtins/path.d#L190) | `JSHandle jsPathIsAbsolute(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/path.d:204`](../../source/dun/builtins/path.d#L204) | `JSHandle jsPathResolve(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/path.d:228`](../../source/dun/builtins/path.d#L228) | `JSHandle jsPathNormalize(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/path.d:242`](../../source/dun/builtins/path.d#L242) | `JSHandle jsPathRelative(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/builtins/path.d:257`](../../source/dun/builtins/path.d#L257) | `JSHandle jsPathParse(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/path.d:283`](../../source/dun/builtins/path.d#L283) | `JSHandle jsPathFormat(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/path.d:319`](../../source/dun/builtins/path.d#L319) | `JSHandle jsPathToNamespacedPath(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/builtins/perf_hooks.d:5`](../../source/dun/builtins/perf_hooks.d#L5) | `void registerPerfHooksModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/perf_hooks.d:30`](../../source/dun/builtins/perf_hooks.d#L30) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/perf_hooks.d:42`](../../source/dun/builtins/perf_hooks.d#L42) | `private extern (C) int perfHooksModuleInit(JSContext* ctx, JSModuleDef* m) no...` | _(missing)_ |
| [`source/dun/builtins/querystring.d:7`](../../source/dun/builtins/querystring.d#L7) | `void registerQuerystringModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/querystring.d:19`](../../source/dun/builtins/querystring.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/querystring.d:35`](../../source/dun/builtins/querystring.d#L35) | `private extern (C) int querystringModuleInit(JSContext* ctx, JSModuleDef* m) ...` | _(missing)_ |
| [`source/dun/builtins/readline.d:7`](../../source/dun/builtins/readline.d#L7) | `void registerReadlineModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/readline.d:19`](../../source/dun/builtins/readline.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/readline.d:30`](../../source/dun/builtins/readline.d#L30) | `private extern (C) int readlineModuleInit(JSContext* ctx, JSModuleDef* m) not...` | _(missing)_ |
| [`source/dun/builtins/stream.d:5`](../../source/dun/builtins/stream.d#L5) | `void registerStreamModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/stream.d:33`](../../source/dun/builtins/stream.d#L33) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/stream.d:46`](../../source/dun/builtins/stream.d#L46) | `private extern (C) int streamModuleInit(JSContext* ctx, JSModuleDef* m) nothr...` | _(missing)_ |
| [`source/dun/builtins/string_decoder.d:7`](../../source/dun/builtins/string_decoder.d#L7) | `void registerStringDecoderModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/string_decoder.d:19`](../../source/dun/builtins/string_decoder.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/string_decoder.d:30`](../../source/dun/builtins/string_decoder.d#L30) | `private extern (C) int stringDecoderModuleInit(JSContext* ctx, JSModuleDef* m...` | _(missing)_ |
| [`source/dun/builtins/timers_promises.d:7`](../../source/dun/builtins/timers_promises.d#L7) | `void registerTimersPromisesModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/timers_promises.d:19`](../../source/dun/builtins/timers_promises.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/timers_promises.d:32`](../../source/dun/builtins/timers_promises.d#L32) | `private extern (C) int timersPromisesModuleInit(JSContext* ctx, JSModuleDef* ...` | _(missing)_ |
| [`source/dun/builtins/tty.d:6`](../../source/dun/builtins/tty.d#L6) | `void registerTtyModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/tty.d:31`](../../source/dun/builtins/tty.d#L31) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/tty.d:41`](../../source/dun/builtins/tty.d#L41) | `private extern (C) int ttyModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/url.d:7`](../../source/dun/builtins/url.d#L7) | `void registerUrlModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/url.d:20`](../../source/dun/builtins/url.d#L20) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/url.d:38`](../../source/dun/builtins/url.d#L38) | `private extern (C) int urlModuleInit(JSContext* ctx, JSModuleDef* m) nothrow ...` | _(missing)_ |
| [`source/dun/builtins/util.d:7`](../../source/dun/builtins/util.d#L7) | `void registerUtilModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/util.d:19`](../../source/dun/builtins/util.d#L19) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/util.d:37`](../../source/dun/builtins/util.d#L37) | `private extern (C) int utilModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/builtins/v8.d:13`](../../source/dun/builtins/v8.d#L13) | `void registerV8Module(IJSEngine engine) @trusted` | /// \`node:v8\` compat — \`writeHeapSnapshot\` + \`getHeapStatistics\` + //... |
| [`source/dun/builtins/v8.d:66`](../../source/dun/builtins/v8.d#L66) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/v8.d:82`](../../source/dun/builtins/v8.d#L82) | `private extern (C) int v8ModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/v8.d:108`](../../source/dun/builtins/v8.d#L108) | `private JSHandle jsWriteHeapSnapshot(void* ctx, JSHandle thisVal, scope JSHan...` | /// Synthetic v8 heap-snapshot — engine name + \`core.memory.GC\` stats ///... |
| [`source/dun/builtins/v8.d:156`](../../source/dun/builtins/v8.d#L156) | `private JSHandle jsGetHeapSnapshot(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/builtins/v8.d:165`](../../source/dun/builtins/v8.d#L165) | `private JSHandle jsGetHeapStatistics(void* ctx, JSHandle thisVal, scope JSHan...` | _(missing)_ |
| [`source/dun/builtins/v8.d:207`](../../source/dun/builtins/v8.d#L207) | `private JSHandle jsGetHeapSpaceStatistics(void* ctx, JSHandle thisVal, scope ...` | _(missing)_ |
| [`source/dun/builtins/v8.d:213`](../../source/dun/builtins/v8.d#L213) | `private JSHandle jsGetHeapCodeStatistics(void* ctx, JSHandle thisVal, scope J...` | _(missing)_ |
| [`source/dun/builtins/v8.d:224`](../../source/dun/builtins/v8.d#L224) | `private JSHandle jsCachedDataVersionTag(void* ctx, JSHandle thisVal, scope JS...` | _(missing)_ |
| [`source/dun/builtins/v8.d:230`](../../source/dun/builtins/v8.d#L230) | `private JSHandle jsSetFlagsFromString(void* ctx, JSHandle thisVal, scope JSHa...` | _(missing)_ |
| [`source/dun/builtins/v8.d:236`](../../source/dun/builtins/v8.d#L236) | `private JSHandle jsSerialize(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/v8.d:256`](../../source/dun/builtins/v8.d#L256) | `private JSHandle jsDeserialize(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/builtins/vm.d:10`](../../source/dun/builtins/vm.d#L10) | `void registerVmModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/vm.d:22`](../../source/dun/builtins/vm.d#L22) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/vm.d:38`](../../source/dun/builtins/vm.d#L38) | `private extern (C) int vmModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @...` | _(missing)_ |
| [`source/dun/builtins/wasi.d:10`](../../source/dun/builtins/wasi.d#L10) | `void registerWasiModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/wasi.d:22`](../../source/dun/builtins/wasi.d#L22) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/wasi.d:33`](../../source/dun/builtins/wasi.d#L33) | `private extern (C) int wasiModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/builtins/worker_threads.d:6`](../../source/dun/builtins/worker_threads.d#L6) | `void registerWorkerThreadsModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/worker_threads.d:49`](../../source/dun/builtins/worker_threads.d#L49) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/worker_threads.d:62`](../../source/dun/builtins/worker_threads.d#L62) | `private extern (C) int workerThreadsModuleInit(JSContext* ctx, JSModuleDef* m...` | _(missing)_ |
| [`source/dun/builtins/yaml.d:31`](../../source/dun/builtins/yaml.d#L31) | `void registerYamlModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/yaml.d:45`](../../source/dun/builtins/yaml.d#L45) | `private JSHandle jsYamlParse(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/builtins/yaml.d:67`](../../source/dun/builtins/yaml.d#L67) | `private JSHandle jsYamlStringify(void* ctx, JSHandle thisVal, scope JSHandle[...` | _(missing)_ |
| [`source/dun/builtins/yaml.d:646`](../../source/dun/builtins/yaml.d#L646) | `private JSHandle nodeToJs(IJSEngine engine, Node n) @trusted` | _(missing)_ |
| [`source/dun/builtins/yaml.d:697`](../../source/dun/builtins/yaml.d#L697) | `ref Appender!string out_) @trusted` | _(missing)_ |
| [`source/dun/builtins/yaml.d:770`](../../source/dun/builtins/yaml.d#L770) | `ref Appender!string out_) @trusted` | _(missing)_ |
| [`source/dun/builtins/yaml.d:861`](../../source/dun/builtins/yaml.d#L861) | `private JSHandle lookupKeysFn(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:12`](../../source/dun/builtins/zlib.d#L12) | `void registerZlibModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:58`](../../source/dun/builtins/zlib.d#L58) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:70`](../../source/dun/builtins/zlib.d#L70) | `private extern (C) int zlibModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:89`](../../source/dun/builtins/zlib.d#L89) | `ubyte[] extractInputBytes(IJSEngine engine, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:115`](../../source/dun/builtins/zlib.d#L115) | `JSHandle returnBytes(IJSEngine engine, const(ubyte)[] data) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:138`](../../source/dun/builtins/zlib.d#L138) | `JSHandle doCompress(void* ctx, JSHandle[] args, int windowBits) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:174`](../../source/dun/builtins/zlib.d#L174) | `JSHandle doDecompress(void* ctx, JSHandle[] args, int windowBits) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:221`](../../source/dun/builtins/zlib.d#L221) | `JSHandle jsDeflateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:226`](../../source/dun/builtins/zlib.d#L226) | `JSHandle jsInflateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:231`](../../source/dun/builtins/zlib.d#L231) | `JSHandle jsGzipSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/builtins/zlib.d:236`](../../source/dun/builtins/zlib.d#L236) | `JSHandle jsGunzipSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:241`](../../source/dun/builtins/zlib.d#L241) | `JSHandle jsDeflateRawSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:246`](../../source/dun/builtins/zlib.d#L246) | `JSHandle jsInflateRawSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:251`](../../source/dun/builtins/zlib.d#L251) | `JSHandle jsBrotliCompressSync(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/builtins/zlib.d:301`](../../source/dun/builtins/zlib.d#L301) | `JSHandle jsBrotliDecompressSync(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/cli/embed.d:37`](../../source/dun/cli/embed.d#L37) | `int writeCompiledExe(string srcExe, string outPath, const(ubyte)[] bundle) @t...` | /// Append \`bundle\` to a copy of \`srcExe\` at \`outPath\`, then mark /// t... |
| [`source/dun/cli/embed.d:86`](../../source/dun/cli/embed.d#L86) | `const(ubyte)[] readEmbeddedBundle(string exePath) @trusted nothrow` | /// Extract the embedded bundle from \`exePath\` if one is present. /// Retur... |
| [`source/dun/cli/errors.d:5`](../../source/dun/cli/errors.d#L5) | `bool isColorEnabled() @trusted nothrow` | _(missing)_ |
| [`source/dun/cli/inspector.d:20`](../../source/dun/cli/inspector.d#L20) | `bool isInspectorActive() nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:25`](../../source/dun/cli/inspector.d#L25) | `void startInspector(IJSEngine engine, ushort port = DEFAULT_INSPECTOR_PORT) @...` | _(missing)_ |
| [`source/dun/cli/inspector.d:74`](../../source/dun/cli/inspector.d#L74) | `void pollInspector() nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:113`](../../source/dun/cli/inspector.d#L113) | `void stopInspector() nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:123`](../../source/dun/cli/inspector.d#L123) | `void handleHttpUpgrade(int fd) nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:159`](../../source/dun/cli/inspector.d#L159) | `string[] splitLines(string s) nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:181`](../../source/dun/cli/inspector.d#L181) | `void processWebSocketFrame(ubyte[] data) @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:221`](../../source/dun/cli/inspector.d#L221) | `void handleCDPMessage(string msg) @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:436`](../../source/dun/cli/inspector.d#L436) | `public void emitConsoleAPICalled(string level, string text) nothrow @trusted` | /// Forward a \`console.*\` call to attached DevTools via /// \`Runtime.conso... |
| [`source/dun/cli/inspector.d:458`](../../source/dun/cli/inspector.d#L458) | `private long gMonotonicMs() nothrow @trusted` | /// Monotonic milliseconds for CDP event timestamps. nothrow so the /// conso... |
| [`source/dun/cli/inspector.d:468`](../../source/dun/cli/inspector.d#L468) | `void sendCDPResponse(int id, string resultJson) nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/inspector.d:480`](../../source/dun/cli/inspector.d#L480) | `void sendWebSocketFrame(ubyte[] payload) nothrow @trusted` | _(missing)_ |
| [`source/dun/cli/lint.d:42`](../../source/dun/cli/lint.d#L42) | `tiny @trusted shim so the rest of this module stays @safe. */` | _(missing)_ |
| [`source/dun/cli/lint.d:43`](../../source/dun/cli/lint.d#L43) | `private void writeErr(string s) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:225`](../../source/dun/cli/repl.d#L225) | `private void printHelp(bool color) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:257`](../../source/dun/cli/repl.d#L257) | `private void doLoad(IJSEngine engine, DunState* state, string path, bool colo...` | _(missing)_ |
| [`source/dun/cli/repl.d:289`](../../source/dun/cli/repl.d#L289) | `private void doSave(string[] sessionLines, string path, bool color) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:304`](../../source/dun/cli/repl.d#L304) | `private void doCopy(IJSEngine engine, string expr, bool color) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:388`](../../source/dun/cli/repl.d#L388) | `LineEditor* lineEd, ref string[] sessionLines, bool color) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:458`](../../source/dun/cli/repl.d#L458) | `private bool isTtyStdin() @trusted nothrow` | _(missing)_ |
| [`source/dun/cli/repl.d:509`](../../source/dun/cli/repl.d#L509) | `this(bool color) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:518`](../../source/dun/cli/repl.d#L518) | `string readLine(string prompt) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:783`](../../source/dun/cli/repl.d#L783) | `void loadHistory() @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:802`](../../source/dun/cli/repl.d#L802) | `void saveHistory() @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:816`](../../source/dun/cli/repl.d#L816) | `private void doTabComplete(ref char[] buf, ref size_t cursor, string prompt) ...` | _(missing)_ |
| [`source/dun/cli/repl.d:925`](../../source/dun/cli/repl.d#L925) | `private static void writeStr(const(char)[] s) @trusted nothrow` | _(missing)_ |
| [`source/dun/cli/repl.d:932`](../../source/dun/cli/repl.d#L932) | `private static void refreshLine(string prompt, const(char)[] buf, size_t curs...` | _(missing)_ |
| [`source/dun/cli/repl.d:1009`](../../source/dun/cli/repl.d#L1009) | `private string readFallback(string prompt) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:1057`](../../source/dun/cli/repl.d#L1057) | `string readLine(string prompt) @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:1074`](../../source/dun/cli/repl.d#L1074) | `private string historyFilePath() @trusted` | _(missing)_ |
| [`source/dun/cli/repl.d:1098`](../../source/dun/cli/repl.d#L1098) | `private size_t historySize() @trusted` | _(missing)_ |
| [`source/dun/engine/callbacks.d:23`](../../source/dun/engine/callbacks.d#L23) | `shared static this() @trusted` | _(missing)_ |
| [`source/dun/engine/callbacks.d:28`](../../source/dun/engine/callbacks.d#L28) | `int register(NativeCallback cb) nothrow @trusted` | _(missing)_ |
| [`source/dun/engine/iface.d:69`](../../source/dun/engine/iface.d#L69) | `void initialize(EngineConfig config) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:70`](../../source/dun/engine/iface.d#L70) | `void shutdown() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:73`](../../source/dun/engine/iface.d#L73) | `JSResult eval(scope const(char)[] source, string filename) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:76`](../../source/dun/engine/iface.d#L76) | `JSHandle newUndefined() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:77`](../../source/dun/engine/iface.d#L77) | `JSHandle newNull() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:78`](../../source/dun/engine/iface.d#L78) | `JSHandle newString(scope const(char)[] s) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:79`](../../source/dun/engine/iface.d#L79) | `JSHandle newInt(int v) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:80`](../../source/dun/engine/iface.d#L80) | `JSHandle newFloat(double v) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:81`](../../source/dun/engine/iface.d#L81) | `JSHandle newBool(bool v) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:82`](../../source/dun/engine/iface.d#L82) | `JSHandle newObject() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:83`](../../source/dun/engine/iface.d#L83) | `JSHandle newArray() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:84`](../../source/dun/engine/iface.d#L84) | `JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:87`](../../source/dun/engine/iface.d#L87) | `string extractString(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:88`](../../source/dun/engine/iface.d#L88) | `int extractInt(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:89`](../../source/dun/engine/iface.d#L89) | `double extractFloat(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:90`](../../source/dun/engine/iface.d#L90) | `bool extractBool(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:93`](../../source/dun/engine/iface.d#L93) | `JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:94`](../../source/dun/engine/iface.d#L94) | `void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:95`](../../source/dun/engine/iface.d#L95) | `JSHandle getGlobal() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:100`](../../source/dun/engine/iface.d#L100) | `void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted;` | /// Set \`obj.name = fn\` without consuming \`fn\` — backends that /// woul... |
| [`source/dun/engine/iface.d:104`](../../source/dun/engine/iface.d#L104) | `void setPrototype(JSHandle obj, JSHandle proto) @trusted;` | /// \`Object.setPrototypeOf(obj, proto)\`. Hot-path replacement for /// the J... |
| [`source/dun/engine/iface.d:109`](../../source/dun/engine/iface.d#L109) | `JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool z...` | /// Fused \`new Uint8Array(data) + setPrototypeOf(_, proto)\` — /// one bac... |
| [`source/dun/engine/iface.d:115`](../../source/dun/engine/iface.d#L115) | `JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted;` | /// Fused \`new Uint8Array(size) + setPrototypeOf(_, proto)\` for /// \`Buffe... |
| [`source/dun/engine/iface.d:119`](../../source/dun/engine/iface.d#L119) | `JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted;` | /// Fused \`Buffer.from(jsString, "utf8")\` — V8 writes UTF-8 directly; ///... |
| [`source/dun/engine/iface.d:128`](../../source/dun/engine/iface.d#L128) | `size_t totalLen, JSHandle proto) @trusted;` | /// Fused \`Buffer.concat(list, totalLen)\` — V8 iterates the array of /// ... |
| [`source/dun/engine/iface.d:131`](../../source/dun/engine/iface.d#L131) | `JSHandle dupValue(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:132`](../../source/dun/engine/iface.d#L132) | `void freeValue(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:135`](../../source/dun/engine/iface.d#L135) | `JSHandle newUint8Array(scope const(ubyte)[] data) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:136`](../../source/dun/engine/iface.d#L136) | `JSHandle newUint8ArrayZeroed(size_t length) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:140`](../../source/dun/engine/iface.d#L140) | `ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted;` | /// Engine-owned slice tied to \`val\`'s lifetime — \`.dup\` if you /// nee... |
| [`source/dun/engine/iface.d:143`](../../source/dun/engine/iface.d#L143) | `void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:144`](../../source/dun/engine/iface.d#L144) | `JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:147`](../../source/dun/engine/iface.d#L147) | `bool isArray(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:148`](../../source/dun/engine/iface.d#L148) | `int getArrayLength(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:151`](../../source/dun/engine/iface.d#L151) | `bool isException(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:152`](../../source/dun/engine/iface.d#L152) | `bool isUndefined(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:153`](../../source/dun/engine/iface.d#L153) | `bool isNull(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:154`](../../source/dun/engine/iface.d#L154) | `bool isString(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:155`](../../source/dun/engine/iface.d#L155) | `bool isObject(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:156`](../../source/dun/engine/iface.d#L156) | `bool isFunction(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:157`](../../source/dun/engine/iface.d#L157) | `bool isBool(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:158`](../../source/dun/engine/iface.d#L158) | `bool isNumber(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:161`](../../source/dun/engine/iface.d#L161) | `JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args) @trus...` | _(missing)_ |
| [`source/dun/engine/iface.d:164`](../../source/dun/engine/iface.d#L164) | `string getException() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:165`](../../source/dun/engine/iface.d#L165) | `JSHandle throwTypeError(scope const(char)[] msg) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:166`](../../source/dun/engine/iface.d#L166) | `JSHandle throwRangeError(scope const(char)[] msg) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:167`](../../source/dun/engine/iface.d#L167) | `JSHandle throwValue(JSHandle val) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:170`](../../source/dun/engine/iface.d#L170) | `PromiseHandles newPromise() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:173`](../../source/dun/engine/iface.d#L173) | `bool hasPendingJobs() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:174`](../../source/dun/engine/iface.d#L174) | `bool executePendingJob() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:175`](../../source/dun/engine/iface.d#L175) | `void drainJobs() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:178`](../../source/dun/engine/iface.d#L178) | `void setContextOpaque(void* ptr) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:179`](../../source/dun/engine/iface.d#L179) | `void* getContextOpaque() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:182`](../../source/dun/engine/iface.d#L182) | `void setModuleLoader(ModuleLoaderCallback loader) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:183`](../../source/dun/engine/iface.d#L183) | `JSResult evalModule(scope const(char)[] source, string filename) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:184`](../../source/dun/engine/iface.d#L184) | `void registerNativeModule(string name, void* initFunc) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:187`](../../source/dun/engine/iface.d#L187) | `void setMemoryLimit(size_t bytes) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:188`](../../source/dun/engine/iface.d#L188) | `void setMaxStackSize(size_t bytes) @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:191`](../../source/dun/engine/iface.d#L191) | `void collectGarbage() @trusted;` | _(missing)_ |
| [`source/dun/engine/iface.d:233`](../../source/dun/engine/iface.d#L233) | `string filename, string what) @trusted` | /// Eval closed-world inline JS and assert success — the canonical /// drop... |
| [`source/dun/engine/test.d:664`](../../source/dun/engine/test.d#L664) | `void testContextOpaque(IJSEngine e) @trusted` | _(missing)_ |
| [`source/dun/loop/agnostic_pending.d:17`](../../source/dun/loop/agnostic_pending.d#L17) | `void pushAgnosticPending(IJSEngine engine, JSHandle func, JSHandle[] args) no...` | _(missing)_ |
| [`source/dun/loop/agnostic_pending.d:34`](../../source/dun/loop/agnostic_pending.d#L34) | `void drainAgnosticPending() @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:29`](../../source/dun/loop/eventloop.d#L29) | `void initialize(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:35`](../../source/dun/loop/eventloop.d#L35) | `void run() @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:43`](../../source/dun/loop/eventloop.d#L43) | `void tick() @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:130`](../../source/dun/loop/eventloop.d#L130) | `bool hasWork() @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:192`](../../source/dun/loop/eventloop.d#L192) | `void drainMicrotasks() @trusted { drainNextTicksAndMicrotasks(); }` | _(missing)_ |
| [`source/dun/loop/eventloop.d:194`](../../source/dun/loop/eventloop.d#L194) | `private void drainNextTicksAndMicrotasks() @trusted` | _(missing)_ |
| [`source/dun/loop/eventloop.d:203`](../../source/dun/loop/eventloop.d#L203) | `public void flushUnhandledRejections() @trusted` | _(missing)_ |
| [`source/dun/loop/microtasks.d:25`](../../source/dun/loop/microtasks.d#L25) | `void enqueue(IJSEngine engine, JSHandle func) nothrow @trusted` | _(missing)_ |
| [`source/dun/loop/microtasks.d:32`](../../source/dun/loop/microtasks.d#L32) | `void drain() @trusted` | _(missing)_ |
| [`source/dun/loop/pending.d:27`](../../source/dun/loop/pending.d#L27) | `void pushPending(JSContext* ctx, JSValue func, JSValue[] args) nothrow @trusted` | _(missing)_ |
| [`source/dun/loop/pending.d:42`](../../source/dun/loop/pending.d#L42) | `void drainPending() @trusted` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:216`](../../source/dun/modules/esm_shim.d#L216) | `auto body_ = (() @trusted => cast(string) result[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:329`](../../source/dun/modules/esm_shim.d#L329) | `auto transpiled = (() @trusted => cast(string) output[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:600`](../../source/dun/modules/esm_shim.d#L600) | `return (() @trusted => cast(string) out_[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:613`](../../source/dun/modules/esm_shim.d#L613) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:724`](../../source/dun/modules/esm_shim.d#L724) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:742`](../../source/dun/modules/esm_shim.d#L742) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:912`](../../source/dun/modules/esm_shim.d#L912) | `return (() @trusted => cast(string) buf[])();` | _(missing)_ |
| [`source/dun/modules/esm_shim.d:962`](../../source/dun/modules/esm_shim.d#L962) | `return (() @trusted => cast(string) output[])();` | _(missing)_ |
| [`source/dun/modules/loader.d:15`](../../source/dun/modules/loader.d#L15) | `void install(JSRuntime* rt) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:21`](../../source/dun/modules/npm.d#L21) | `string installRoot = ".") @trusted` | /// Install a package into \`installRoot/node_modules/<name>\`. The default /... |
| [`source/dun/modules/npm.d:168`](../../source/dun/modules/npm.d#L168) | `private void recordLockEntry(string name, string version_, string resolved) @...` | /// Append \`{ name, version, resolved }\` to dun.lock + package-lock.json. /... |
| [`source/dun/modules/npm.d:219`](../../source/dun/modules/npm.d#L219) | `bool runPackageScript(string scriptName) @trusted` | /// Run a named script from the project's package.json. /// Returns true if t... |
| [`source/dun/modules/npm.d:264`](../../source/dun/modules/npm.d#L264) | `void runLifecycleScripts(string pkgDir, string pkgName) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:297`](../../source/dun/modules/npm.d#L297) | `void createBinLinks(string pkgDir, string pkgName) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:336`](../../source/dun/modules/npm.d#L336) | `private void createSymlinkAndChmod(string linkPath, string targetPath) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:361`](../../source/dun/modules/npm.d#L361) | `PackageMeta fetchPackageMeta(string name) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:401`](../../source/dun/modules/npm.d#L401) | `auto versions = (() @trusted => j["versions"].object)();` | _(missing)_ |
| [`source/dun/modules/npm.d:520`](../../source/dun/modules/npm.d#L520) | `ubyte[] downloadTarball(string url) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:533`](../../source/dun/modules/npm.d#L533) | `bool extractTarGz(ubyte[] data, string destDir) @trusted` | _(missing)_ |
| [`source/dun/modules/npm.d:575`](../../source/dun/modules/npm.d#L575) | `private void cleanup(string tmpFile) @trusted nothrow` | _(missing)_ |
| [`source/dun/modules/require.d:11`](../../source/dun/modules/require.d#L11) | `void installRequire(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:34`](../../source/dun/modules/require.d#L34) | `JSHandle jsRequireResolve(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/modules/require.d:118`](../../source/dun/modules/require.d#L118) | `JSHandle jsRequire(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:633`](../../source/dun/modules/require.d#L633) | `string getCjsStackDir(IJSEngine engine, JSHandle global) nothrow @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:661`](../../source/dun/modules/require.d#L661) | `private bool isEsmPackage(string filePath) @trusted nothrow` | _(missing)_ |
| [`source/dun/modules/require.d:692`](../../source/dun/modules/require.d#L692) | `private string resolvePackageImports(string specifier, string fromDir) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:740`](../../source/dun/modules/require.d#L740) | `public string findNodeModule(string specifier, string fromDir, bool esm = fal...` | _(missing)_ |
| [`source/dun/modules/require.d:882`](../../source/dun/modules/require.d#L882) | `bool esm = false) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:888`](../../source/dun/modules/require.d#L888) | `bool esm = false) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:959`](../../source/dun/modules/require.d#L959) | `string wildcardMatch = null, bool esm = false) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:1021`](../../source/dun/modules/require.d#L1021) | `JSHandle throwModuleNotFound(IJSEngine engine, string specifier) @trusted` | _(missing)_ |
| [`source/dun/modules/require.d:1038`](../../source/dun/modules/require.d#L1038) | `private string escapeForJs(string s) @trusted nothrow` | _(missing)_ |
| [`source/dun/modules/require.d:1052`](../../source/dun/modules/require.d#L1052) | `private string resolveMainEntry(JSONValue j, string pkgDir) @trusted` | _(missing)_ |
| [`source/dun/platform/arena.d:76`](../../source/dun/platform/arena.d#L76) | `void[] allocate(size_t bytes) @trusted nothrow` | /// Returns a slice of \`bytes\` from the stack region when it /// fits, othe... |
| [`source/dun/platform/arena.d:87`](../../source/dun/platform/arena.d#L87) | `void deallocateAll() @trusted nothrow` | /// Reset the stack region. GC-spilled blocks fall out of scope /// naturally... |
| [`source/dun/platform/arena.d:100`](../../source/dun/platform/arena.d#L100) | `auto a = (() @trusted => sfb.allocate(64))();` | _(missing)_ |
| [`source/dun/platform/arena.d:103`](../../source/dun/platform/arena.d#L103) | `auto b = (() @trusted => sfb.allocate(4096))();` | _(missing)_ |
| [`source/dun/platform/arena.d:106`](../../source/dun/platform/arena.d#L106) | `(() @trusted => sfb.deallocateAll())();` | _(missing)_ |
| [`source/dun/platform/paths.d:7`](../../source/dun/platform/paths.d#L7) | `string dunGlobalRoot() @trusted` | /// User-global DunJS store (npm packages, transpile cache). /// Posix \`$HOM... |
| [`source/dun/runtime/bun_compat.d:7`](../../source/dun/runtime/bun_compat.d#L7) | `void installBunCompat(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/bun_extras_v7.d:17`](../../source/dun/runtime/bun_extras_v7.d#L17) | `void installBunExtrasV7(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/console.d:6`](../../source/dun/runtime/console.d#L6) | `void installConsole(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/console.d:60`](../../source/dun/runtime/console.d#L60) | `private void forwardToInspector(IJSEngine engine, string level, scope JSHandl...` | /// Forward a console.* call to an attached Chrome DevTools session as /// a ... |
| [`source/dun/runtime/console.d:81`](../../source/dun/runtime/console.d#L81) | `JSHandle consoleAssert(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/console.d:105`](../../source/dun/runtime/console.d#L105) | `void writeArgs(IJSEngine engine, scope JSHandle[] args, bool useStderr) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:7`](../../source/dun/runtime/deno_compat.d#L7) | `void installDenoCompat(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:545`](../../source/dun/runtime/deno_compat.d#L545) | `bool noColorEnabled() @trusted nothrow` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:559`](../../source/dun/runtime/deno_compat.d#L559) | `JSHandle denoEnvGet(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:582`](../../source/dun/runtime/deno_compat.d#L582) | `JSHandle denoEnvSet(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:603`](../../source/dun/runtime/deno_compat.d#L603) | `JSHandle denoEnvDelete(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:624`](../../source/dun/runtime/deno_compat.d#L624) | `JSHandle denoEnvHas(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:644`](../../source/dun/runtime/deno_compat.d#L644) | `JSHandle denoEnvToObject(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:666`](../../source/dun/runtime/deno_compat.d#L666) | `JSHandle denoReadTextFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:690`](../../source/dun/runtime/deno_compat.d#L690) | `JSHandle denoReadTextFile(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:709`](../../source/dun/runtime/deno_compat.d#L709) | `asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:719`](../../source/dun/runtime/deno_compat.d#L719) | `JSHandle denoWriteTextFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:746`](../../source/dun/runtime/deno_compat.d#L746) | `JSHandle denoWriteTextFile(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:767`](../../source/dun/runtime/deno_compat.d#L767) | `asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:778`](../../source/dun/runtime/deno_compat.d#L778) | `JSHandle denoStatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:837`](../../source/dun/runtime/deno_compat.d#L837) | `JSHandle denoMkdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:873`](../../source/dun/runtime/deno_compat.d#L873) | `JSHandle denoRemoveSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:912`](../../source/dun/runtime/deno_compat.d#L912) | `JSHandle denoRenameSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:943`](../../source/dun/runtime/deno_compat.d#L943) | `JSHandle denoCopyFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:974`](../../source/dun/runtime/deno_compat.d#L974) | `JSHandle denoReadDirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1018`](../../source/dun/runtime/deno_compat.d#L1018) | `JSHandle denoRealPathSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1045`](../../source/dun/runtime/deno_compat.d#L1045) | `JSHandle denoTruncateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1072`](../../source/dun/runtime/deno_compat.d#L1072) | `JSHandle denoCwd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1086`](../../source/dun/runtime/deno_compat.d#L1086) | `JSHandle denoChdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1113`](../../source/dun/runtime/deno_compat.d#L1113) | `JSHandle denoExit(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1130`](../../source/dun/runtime/deno_compat.d#L1130) | `JSHandle denoHostname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1161`](../../source/dun/runtime/deno_compat.d#L1161) | `JSHandle denoPermissionsQuery(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/runtime/deno_compat.d:1209`](../../source/dun/runtime/deno_compat.d#L1209) | `JSHandle denoInspect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:38`](../../source/dun/runtime/ffi.d#L38) | `void installFfiCompat(IJSEngine engine, DunState* state) @trusted` | _(missing)_ |
| [`source/dun/runtime/ffi.d:91`](../../source/dun/runtime/ffi.d#L91) | `private JSHandle jsDenoDlopen(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:180`](../../source/dun/runtime/ffi.d#L180) | `private string[] _getOwnKeys(IJSEngine engine, JSHandle obj) @trusted` | _(missing)_ |
| [`source/dun/runtime/ffi.d:202`](../../source/dun/runtime/ffi.d#L202) | `private string _buildSignature(IJSEngine engine, JSHandle spec) @trusted` | _(missing)_ |
| [`source/dun/runtime/ffi.d:253`](../../source/dun/runtime/ffi.d#L253) | `private void _ensureFfiMu() nothrow @trusted` | _(missing)_ |
| [`source/dun/runtime/ffi.d:260`](../../source/dun/runtime/ffi.d#L260) | `private JSHandle _makeWrapper(IJSEngine engine, DunState* state, void* fnptr,...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:326`](../../source/dun/runtime/ffi.d#L326) | `private JSHandle jsFfiDispatchById(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:354`](../../source/dun/runtime/ffi.d#L354) | `private JSHandle _dispatchSignature(IJSEngine engine, FfiSlot slot, scope JSH...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:428`](../../source/dun/runtime/ffi.d#L428) | `private void* _arg2ptr(IJSEngine engine, scope JSHandle[] args, size_t idx) @...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:440`](../../source/dun/runtime/ffi.d#L440) | `private const(char)* _arg2cstr(IJSEngine engine, scope JSHandle[] args, size_...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:453`](../../source/dun/runtime/ffi.d#L453) | `private JSHandle jsDlopenClose(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/runtime/ffi.d:472`](../../source/dun/runtime/ffi.d#L472) | `private JSHandle jsUnsafePointer(void* ctx, JSHandle thisVal, scope JSHandle[...` | _(missing)_ |
| [`source/dun/runtime/globals.d:28`](../../source/dun/runtime/globals.d#L28) | `void installGlobals(IJSEngine engine, DunState* state) @trusted` | _(missing)_ |
| [`source/dun/runtime/globals.d:260`](../../source/dun/runtime/globals.d#L260) | `private void registerStubModules(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/globals.d:474`](../../source/dun/runtime/globals.d#L474) | `private void registerStubModulesQuickJS(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/globals.d:497`](../../source/dun/runtime/globals.d#L497) | `private void registerStubModuleQuickJS(JSContext* ctx, string name, string gl...` | _(missing)_ |
| [`source/dun/runtime/globals.d:549`](../../source/dun/runtime/globals.d#L549) | `private extern (C) int stubModuleInit(JSContext* ctx, JSModuleDef* m) nothrow...` | _(missing)_ |
| [`source/dun/runtime/globals.d:998`](../../source/dun/runtime/globals.d#L998) | `private JSHandle jsGlobalGC(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/runtime/intl.d:5`](../../source/dun/runtime/intl.d#L5) | `void installIntl(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/microtask_api.d:6`](../../source/dun/runtime/microtask_api.d#L6) | `void installMicrotask(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:26`](../../source/dun/runtime/process_api.d#L26) | `bool invokeUncaughtExceptionHandler(IJSEngine engine, string errorMsg) @trust...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:82`](../../source/dun/runtime/process_api.d#L82) | `bool invokeUnhandledRejectionHandler(IJSEngine engine, JSHandle reason, JSHan...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:96`](../../source/dun/runtime/process_api.d#L96) | `void fireExitHandlers(int code) @trusted nothrow` | _(missing)_ |
| [`source/dun/runtime/process_api.d:111`](../../source/dun/runtime/process_api.d#L111) | `void fireBeforeExitHandlers(int code) @trusted nothrow` | _(missing)_ |
| [`source/dun/runtime/process_api.d:130`](../../source/dun/runtime/process_api.d#L130) | `private void ensureStartTime() @trusted nothrow` | _(missing)_ |
| [`source/dun/runtime/process_api.d:142`](../../source/dun/runtime/process_api.d#L142) | `private bool isattyFd(int fd) @trusted nothrow` | _(missing)_ |
| [`source/dun/runtime/process_api.d:153`](../../source/dun/runtime/process_api.d#L153) | `void installProcess(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:516`](../../source/dun/runtime/process_api.d#L516) | `JSHandle jsNoop(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:523`](../../source/dun/runtime/process_api.d#L523) | `JSHandle jsGetWindowSize(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:534`](../../source/dun/runtime/process_api.d#L534) | `JSHandle jsCwd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:547`](../../source/dun/runtime/process_api.d#L547) | `JSHandle jsExit(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:561`](../../source/dun/runtime/process_api.d#L561) | `JSHandle jsProcessOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:600`](../../source/dun/runtime/process_api.d#L600) | `JSHandle jsNextTick(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:640`](../../source/dun/runtime/process_api.d#L640) | `JSHandle jsStdoutWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:675`](../../source/dun/runtime/process_api.d#L675) | `JSHandle jsStderrWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:706`](../../source/dun/runtime/process_api.d#L706) | `JSHandle jsHrtime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:739`](../../source/dun/runtime/process_api.d#L739) | `public JSHandle jsPerformanceNow(void* ctx, JSHandle thisVal, scope JSHandle[...` | /// \`performance.now()\` via MonoTime — sub-ms precision. Overrides /// JS... |
| [`source/dun/runtime/process_api.d:755`](../../source/dun/runtime/process_api.d#L755) | `JSHandle jsHrtimeBigint(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:774`](../../source/dun/runtime/process_api.d#L774) | `JSHandle jsUptime(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:791`](../../source/dun/runtime/process_api.d#L791) | `JSHandle jsMemoryUsage(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:820`](../../source/dun/runtime/process_api.d#L820) | `JSHandle jsAvailableMemory(void* ctx, JSHandle thisVal, scope JSHandle[] args...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:853`](../../source/dun/runtime/process_api.d#L853) | `JSHandle jsCpuUsage(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:876`](../../source/dun/runtime/process_api.d#L876) | `JSHandle jsChdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/process_api.d:895`](../../source/dun/runtime/process_api.d#L895) | `JSHandle jsEmitWarning(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:924`](../../source/dun/runtime/process_api.d#L924) | `JSHandle jsProcessKill(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:951`](../../source/dun/runtime/process_api.d#L951) | `JSHandle jsProcessAbort(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:959`](../../source/dun/runtime/process_api.d#L959) | `JSHandle jsProcessUmask(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:987`](../../source/dun/runtime/process_api.d#L987) | `return state.engine.newInt(cast(int) (() @trusted => getuid())());` | _(missing)_ |
| [`source/dun/runtime/process_api.d:995`](../../source/dun/runtime/process_api.d#L995) | `return state.engine.newInt(cast(int) (() @trusted => getgid())());` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1003`](../../source/dun/runtime/process_api.d#L1003) | `return state.engine.newInt(cast(int) (() @trusted => geteuid())());` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1011`](../../source/dun/runtime/process_api.d#L1011) | `return state.engine.newInt(cast(int) (() @trusted => getegid())());` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1014`](../../source/dun/runtime/process_api.d#L1014) | `JSHandle jsProcessGetgroups(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1046`](../../source/dun/runtime/process_api.d#L1046) | `JSHandle jsProcessResourceUsage(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1119`](../../source/dun/runtime/process_api.d#L1119) | `JSHandle jsNativeSetEnv(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1135`](../../source/dun/runtime/process_api.d#L1135) | `JSHandle jsNativeUnsetEnv(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1150`](../../source/dun/runtime/process_api.d#L1150) | `JSHandle jsStdinRead(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1169`](../../source/dun/runtime/process_api.d#L1169) | `return engine.newString((() @trusted => cast(string) buf[0 .. n])());` | _(missing)_ |
| [`source/dun/runtime/process_api.d:1175`](../../source/dun/runtime/process_api.d#L1175) | `JSHandle jsStdinSetEncoding(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/runtime/rejection_tracker.d:7`](../../source/dun/runtime/rejection_tracker.d#L7) | `void installRejectionTracker(IJSEngine engine, DunState* state) @trusted` | _(missing)_ |
| [`source/dun/runtime/rejection_tracker.d:41`](../../source/dun/runtime/rejection_tracker.d#L41) | `bool is_handled, void* opaque) nothrow @trusted` | _(missing)_ |
| [`source/dun/runtime/rejection_tracker.d:114`](../../source/dun/runtime/rejection_tracker.d#L114) | `private void installJSRejectionTracker(IJSEngine engine, DunState* state) @tr...` | _(missing)_ |
| [`source/dun/runtime/rejection_tracker.d:157`](../../source/dun/runtime/rejection_tracker.d#L157) | `private JSHandle jsReportRejection(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/runtime/signals.d:30`](../../source/dun/runtime/signals.d#L30) | `void installSignalHandlers() nothrow @trusted` | /// Install POSIX signal handlers (idempotent). |
| [`source/dun/runtime/signals.d:65`](../../source/dun/runtime/signals.d#L65) | `void registerSignalHandler(IJSEngine engine, SignalType sig, JSHandle handler...` | /// Register a JS callback for a signal type. |
| [`source/dun/runtime/signals.d:90`](../../source/dun/runtime/signals.d#L90) | `bool checkSignals() nothrow @trusted` | /// Check if any signals have been received (non-blocking). |
| [`source/dun/runtime/signals.d:96`](../../source/dun/runtime/signals.d#L96) | `bool hasSignalHandlers() nothrow @trusted` | /// Returns true if any signal handlers are registered. |
| [`source/dun/runtime/signals.d:102`](../../source/dun/runtime/signals.d#L102) | `void drainSignals() nothrow @trusted` | /// Drain received signals and invoke JS callbacks. |
| [`source/dun/runtime/timers_api.d:8`](../../source/dun/runtime/timers_api.d#L8) | `void installTimers(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/timers_api.d:102`](../../source/dun/runtime/timers_api.d#L102) | `JSHandle makeTimerObject(IJSEngine engine, int id) @trusted` | _(missing)_ |
| [`source/dun/runtime/timers_api.d:135`](../../source/dun/runtime/timers_api.d#L135) | `JSHandle jsTimerRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted` | _(missing)_ |
| [`source/dun/runtime/timers_api.d:142`](../../source/dun/runtime/timers_api.d#L142) | `JSHandle jsTimerUnref(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/runtime/timers_api.d:149`](../../source/dun/runtime/timers_api.d#L149) | `JSHandle jsTimerHasRef(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/runtime/timers_api.d:158`](../../source/dun/runtime/timers_api.d#L158) | `JSHandle jsTimerValueOf(void* ctx, JSHandle thisVal, scope JSHandle[] args) @...` | /// \`+timer\` → reads \`this._id\` via a native fast path. Replaces the //... |
| [`source/dun/runtime/web_apis.d:6`](../../source/dun/runtime/web_apis.d#L6) | `void installWebAPIs(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/web_apis.d:35`](../../source/dun/runtime/web_apis.d#L35) | `private void installLazyExtras(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/web_apis.d:349`](../../source/dun/runtime/web_apis.d#L349) | `private void bindNativeCryptoOnGlobal(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/web_apis.d:369`](../../source/dun/runtime/web_apis.d#L369) | `private JSHandle jsNativeGetRandomValues(void* ctx, JSHandle thisVal, scope J...` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:6`](../../source/dun/runtime/web_compat.d#L6) | `void installWebCompat(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:207`](../../source/dun/runtime/web_compat.d#L207) | `JSHandle jsNativeBtoa(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:264`](../../source/dun/runtime/web_compat.d#L264) | `JSHandle jsNativeAtob(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:315`](../../source/dun/runtime/web_compat.d#L315) | `JSHandle jsNativeTextEncoderEncode(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:330`](../../source/dun/runtime/web_compat.d#L330) | `JSHandle jsNativeTextEncoderEncodeInto(void* ctx, JSHandle thisVal, scope JSH...` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:366`](../../source/dun/runtime/web_compat.d#L366) | `private JSHandle _getCachedU8Wrap(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/runtime/web_compat.d:387`](../../source/dun/runtime/web_compat.d#L387) | `JSHandle jsNativeTextDecoderDecode(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:42`](../../source/dun/runtime/worker_api.d#L42) | `shared static this() @trusted` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:48`](../../source/dun/runtime/worker_api.d#L48) | `void installWorkerAPI(IJSEngine engine, DunState* state) @trusted` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:157`](../../source/dun/runtime/worker_api.d#L157) | `private JSHandle _workerCtor(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:203`](../../source/dun/runtime/worker_api.d#L203) | `private JSHandle _workerPostMessage(void* ctx, JSHandle thisVal, scope JSHand...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:240`](../../source/dun/runtime/worker_api.d#L240) | `private JSHandle _sabCtor(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:265`](../../source/dun/runtime/worker_api.d#L265) | `private JSHandle _int32ArrayCtor(void* ctx, JSHandle thisVal, scope JSHandle[...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:325`](../../source/dun/runtime/worker_api.d#L325) | `private int* _getAtomicPtr(IJSEngine engine, JSHandle ta, int idx) @trusted` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:355`](../../source/dun/runtime/worker_api.d#L355) | `private JSHandle _atomicsLoad(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:366`](../../source/dun/runtime/worker_api.d#L366) | `private JSHandle _atomicsStore(void* ctx, JSHandle thisVal, scope JSHandle[] ...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:379`](../../source/dun/runtime/worker_api.d#L379) | `private JSHandle _atomicsAdd(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:391`](../../source/dun/runtime/worker_api.d#L391) | `private JSHandle _atomicsSub(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:403`](../../source/dun/runtime/worker_api.d#L403) | `private JSHandle _atomicsAnd(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:419`](../../source/dun/runtime/worker_api.d#L419) | `private JSHandle _atomicsOr(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:435`](../../source/dun/runtime/worker_api.d#L435) | `private JSHandle _atomicsXor(void* ctx, JSHandle thisVal, scope JSHandle[] ar...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:451`](../../source/dun/runtime/worker_api.d#L451) | `private JSHandle _atomicsExchange(void* ctx, JSHandle thisVal, scope JSHandle...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:467`](../../source/dun/runtime/worker_api.d#L467) | `private JSHandle _atomicsIsLockFree(void* ctx, JSHandle thisVal, scope JSHand...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:476`](../../source/dun/runtime/worker_api.d#L476) | `private JSHandle _atomicsCmpXch(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:492`](../../source/dun/runtime/worker_api.d#L492) | `private JSHandle _atomicsWait(void* ctx, JSHandle thisVal, scope JSHandle[] a...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:580`](../../source/dun/runtime/worker_api.d#L580) | `private JSHandle _atomicsNotify(void* ctx, JSHandle thisVal, scope JSHandle[]...` | _(missing)_ |
| [`source/dun/runtime/worker_api.d:616`](../../source/dun/runtime/worker_api.d#L616) | `private JSHandle _atomicsWaitAsync(void* ctx, JSHandle thisVal, scope JSHandl...` | _(missing)_ |
| [`source/dun/runtime/worker_self.d:7`](../../source/dun/runtime/worker_self.d#L7) | `void installWorkerSelf(IJSEngine engine, DunState* state, WorkerState wst) @t...` | _(missing)_ |
| [`source/dun/runtime/worker_self.d:64`](../../source/dun/runtime/worker_self.d#L64) | `private WorkerState _getWst(IJSEngine engine) nothrow @trusted` | _(missing)_ |
| [`source/dun/runtime/worker_self.d:88`](../../source/dun/runtime/worker_self.d#L88) | `private JSHandle _selfPostMessage(void* ctx, JSHandle thisVal, scope JSHandle...` | _(missing)_ |
| [`source/dun/runtime/worker_self.d:111`](../../source/dun/runtime/worker_self.d#L111) | `private JSHandle _selfClose(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/security/cve_db.d:70`](../../source/dun/security/cve_db.d#L70) | `AuditResult[] checkPackage(string name, string version_) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:83`](../../source/dun/security/cve_db.d#L83) | `AuditResult[] auditNodeModules() @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:122`](../../source/dun/security/cve_db.d#L122) | `void printAuditReport(AuditResult[] results) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:188`](../../source/dun/security/cve_db.d#L188) | `private CveEntry[] queryOsvApi(string packageName, string version_) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:251`](../../source/dun/security/cve_db.d#L251) | `private CveEntry[] parseOsvResponse(T)(T j, string packageName) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:281`](../../source/dun/security/cve_db.d#L281) | `private Severity extractSeverity(T)(ref T vuln) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:302`](../../source/dun/security/cve_db.d#L302) | `private string extractFixedVersion(T)(ref T vuln) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:323`](../../source/dun/security/cve_db.d#L323) | `private string extractCveId(T)(ref T vuln, string defaultId) @trusted` | _(missing)_ |
| [`source/dun/security/cve_db.d:347`](../../source/dun/security/cve_db.d#L347) | `private CacheResult loadFromCache(string key, bool ignoreExpiry = false) @tru...` | _(missing)_ |
| [`source/dun/security/cve_db.d:397`](../../source/dun/security/cve_db.d#L397) | `private void saveToCache(string key, CveEntry[] entries) @trusted nothrow` | _(missing)_ |
| [`source/dun/security/cve_db.d:451`](../../source/dun/security/cve_db.d#L451) | `long currentUnixTime() @trusted nothrow` | _(missing)_ |
| [`source/dun/security/permissions.d:362`](../../source/dun/security/permissions.d#L362) | `bool checkPerm(StateT)(StateT* state, Permission perm, string resource = "") ...` | /// \`extern(C)\`-safe permission check — nothrow, defaults to deny on /// ... |
| [`source/dun/ts/dynamic_import.d:59`](../../source/dun/ts/dynamic_import.d#L59) | `string rewriteDynamicImport(string src) @trusted` | /// Rewrite all dynamic \`import(...)\` calls in \`src\` to /// \`__dunImport... |
| [`source/dun/ts/dynamic_import.d:157`](../../source/dun/ts/dynamic_import.d#L157) | `return (() @trusted => cast(string) out_[])();` | _(missing)_ |
| [`source/dun/ts/jsx.d:111`](../../source/dun/ts/jsx.d#L111) | `return (() @trusted => cast(string) out_.data)();` | _(missing)_ |
| [`source/dun/ts/jsx.d:240`](../../source/dun/ts/jsx.d#L240) | `return (() @trusted => cast(string) frag.data)();` | _(missing)_ |
| [`source/dun/ts/jsx.d:391`](../../source/dun/ts/jsx.d#L391) | `return (() @trusted => cast(string) el.data)();` | _(missing)_ |
| [`source/dun/ts/jsx.d:408`](../../source/dun/ts/jsx.d#L408) | `return (() @trusted => cast(string) el.data)();` | _(missing)_ |
| [`source/dun/ts/jsx.d:506`](../../source/dun/ts/jsx.d#L506) | `return (() @trusted => cast(string) sb.data)();` | _(missing)_ |
| [`source/dun/ts/jsx.d:523`](../../source/dun/ts/jsx.d#L523) | `return (() @trusted => cast(string) sb.data)();` | _(missing)_ |
| [`source/dun/ts/strip.d:1056`](../../source/dun/ts/strip.d#L1056) | `return (() @trusted {` | _(missing)_ |
| [`source/dun/ts/strip.d:1080`](../../source/dun/ts/strip.d#L1080) | `size_t afterEnumKw, out string decl) @trusted pure nothrow` | /// Rewrite \`enum Name { … }\` to an equivalent JS object in place. /// Nu... |
| [`source/dun/ts/strip.d:1243`](../../source/dun/ts/strip.d#L1243) | `size_t nsKwStart, out string decl) @trusted` | /// Rewrite \`namespace\|module Name { body }\` to an IIFE emitted /// via \`... |
| [`source/dun/ts/strip.d:1440`](../../source/dun/ts/strip.d#L1440) | `out size_t injectAt, out string injectText) @trusted pure nothrow` | /// Erase \`constructor(public/private/protected x)\` modifiers in place /// ... |
| [`source/dun/ts/transpile_cache.d:15`](../../source/dun/ts/transpile_cache.d#L15) | `private string cacheRoot() @trusted` | _(missing)_ |
| [`source/dun/ts/transpile_cache.d:46`](../../source/dun/ts/transpile_cache.d#L46) | `string lookup(string key) @trusted` | /// Read a cached transpile result. Returns the cached JS or null on miss. |
| [`source/dun/ts/transpile_cache.d:60`](../../source/dun/ts/transpile_cache.d#L60) | `void store(string key, string output) @trusted` | /// Store a transpile result under the given key. Best-effort: if the /// dis... |
| [`source/dun/ts/transpile_cache.d:90`](../../source/dun/ts/transpile_cache.d#L90) | `void maybeTrim() @trusted` | /// Best-effort cache trim. Called once per \`store()\` but rate-limited /// ... |
| [`source/dun/ts/transpile_cache.d:150`](../../source/dun/ts/transpile_cache.d#L150) | `void clear() @trusted` | /// Manual cache clear -- exposed for \`dun clean\` later if wired. |
| [`source/dun/workers/channel.d:19`](../../source/dun/workers/channel.d#L19) | `void send(T item) nothrow @trusted` | _(missing)_ |
| [`source/dun/workers/channel.d:35`](../../source/dun/workers/channel.d#L35) | `bool tryRecv(out T item) nothrow @trusted` | _(missing)_ |
| [`source/dun/workers/channel.d:51`](../../source/dun/workers/channel.d#L51) | `void close() nothrow @trusted` | _(missing)_ |
| [`source/dun/workers/channel.d:57`](../../source/dun/workers/channel.d#L57) | `bool isClosed() nothrow @trusted` | _(missing)_ |
| [`source/dun/workers/channel.d:61`](../../source/dun/workers/channel.d#L61) | `bool empty() nothrow @trusted` | _(missing)_ |
| [`source/dun/workers/shared_memory.d:38`](../../source/dun/workers/shared_memory.d#L38) | `int sabAlloc(size_t len) @trusted` | _(missing)_ |
| [`source/dun/workers/shared_memory.d:65`](../../source/dun/workers/shared_memory.d#L65) | `bool sabGet(int id, out void* ptr, out size_t len) @trusted` | _(missing)_ |
| [`source/dun/workers/shared_memory.d:77`](../../source/dun/workers/shared_memory.d#L77) | `void sabRef(int id) @trusted` | _(missing)_ |
| [`source/dun/workers/shared_memory.d:92`](../../source/dun/workers/shared_memory.d#L92) | `void sabUnref(int id) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:46`](../../source/dun/workers/worker.d#L46) | `this(string path, IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:67`](../../source/dun/workers/worker.d#L67) | `void registerWorker(WorkerState wst) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:73`](../../source/dun/workers/worker.d#L73) | `bool hasActiveWorkers() @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:88`](../../source/dun/workers/worker.d#L88) | `void pollWorkerMessages(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:122`](../../source/dun/workers/worker.d#L122) | `void spawnWorker(WorkerState wst) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:136`](../../source/dun/workers/worker.d#L136) | `private void _runWorker(WorkerState wst) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:200`](../../source/dun/workers/worker.d#L200) | `private void _drainIncoming(IJSEngine engine, DunState* state, WorkerState ws...` | _(missing)_ |
| [`source/dun/workers/worker.d:230`](../../source/dun/workers/worker.d#L230) | `JSHandle makeMessageEvent(IJSEngine engine, string jsonMsg) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:257`](../../source/dun/workers/worker.d#L257) | `string jsonStringify(IJSEngine engine, JSHandle val) @trusted` | _(missing)_ |
| [`source/dun/workers/worker.d:293`](../../source/dun/workers/worker.d#L293) | `private void _installGlobals(IJSEngine engine, DunState* state) @trusted` | _(missing)_ |

## quic-FFI (13 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/http3.d:54`](../../source/dun/builtins/http3.d#L54) | `void registerHttp3Module(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http3.d:74`](../../source/dun/builtins/http3.d#L74) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http3.d:85`](../../source/dun/builtins/http3.d#L85) | `private extern (C) int http3ModuleInit(JSContext* ctx, JSModuleDef* m) nothro...` | _(missing)_ |
| [`source/dun/builtins/http3.d:104`](../../source/dun/builtins/http3.d#L104) | `JSHandle makeH3Constants(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/http3.d:227`](../../source/dun/builtins/http3.d#L227) | `JSHandle jsH3CreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http3.d:243`](../../source/dun/builtins/http3.d#L243) | `JSHandle jsH3ServerListen(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http3.d:331`](../../source/dun/builtins/http3.d#L331) | `JSHandle jsH3ServerClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http3.d:360`](../../source/dun/builtins/http3.d#L360) | `JSHandle jsH3ServerOn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/http3.d:367`](../../source/dun/builtins/http3.d#L367) | `JSHandle jsH3Connect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/http3.d:382`](../../source/dun/builtins/http3.d#L382) | `JSHandle jsH3SessionClose(void* ctx, JSHandle thisVal, scope JSHandle[] args)...` | _(missing)_ |
| [`source/dun/builtins/http3.d:390`](../../source/dun/builtins/http3.d#L390) | `JSHandle jsH3SessionRequest(void* ctx, JSHandle thisVal, scope JSHandle[] arg...` | _(missing)_ |
| [`source/dun/builtins/http3.d:406`](../../source/dun/builtins/http3.d#L406) | `JSHandle jsH3StreamWrite(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/http3.d:414`](../../source/dun/builtins/http3.d#L414) | `JSHandle jsH3StreamEnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |

## sqlite-FFI (20 sites)

| File:Line | Declaration | Rationale |
|---|---|---|
| [`source/dun/builtins/sqlite.d:7`](../../source/dun/builtins/sqlite.d#L7) | `void registerSqliteModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:27`](../../source/dun/builtins/sqlite.d#L27) | `private void registerQuickJSModule(IJSEngine engine) @trusted` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:40`](../../source/dun/builtins/sqlite.d#L40) | `private extern (C) int sqliteModuleInit(JSContext* ctx, JSModuleDef* m) nothr...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:74`](../../source/dun/builtins/sqlite.d#L74) | `sqlite3* getDbHandle(IJSEngine engine, JSHandle thisVal) @trusted` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:87`](../../source/dun/builtins/sqlite.d#L87) | `JSHandle jsSqliteOpen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:134`](../../source/dun/builtins/sqlite.d#L134) | `JSHandle jsSqliteExec(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tr...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:153`](../../source/dun/builtins/sqlite.d#L153) | `? (() @trusted { import std.string : fromStringz; return fromStringz(errmsg)....` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:162`](../../source/dun/builtins/sqlite.d#L162) | `JSHandle jsSqliteRun(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:199`](../../source/dun/builtins/sqlite.d#L199) | `JSHandle jsSqliteGet(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:237`](../../source/dun/builtins/sqlite.d#L237) | `JSHandle jsSqliteAll(void* ctx, JSHandle thisVal, scope JSHandle[] args) @tru...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:275`](../../source/dun/builtins/sqlite.d#L275) | `JSHandle jsSqliteClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:293`](../../source/dun/builtins/sqlite.d#L293) | `JSHandle jsSqliteVersion(void* ctx, JSHandle thisVal, scope JSHandle[] args) ...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:311`](../../source/dun/builtins/sqlite.d#L311) | `void bindArgs(IJSEngine engine, sqlite3_stmt* stmt, scope JSHandle[] args) @t...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:334`](../../source/dun/builtins/sqlite.d#L334) | `void bindSingle(IJSEngine engine, sqlite3_stmt* stmt, int idx, JSHandle arg) ...` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:361`](../../source/dun/builtins/sqlite.d#L361) | `JSHandle extractRow(IJSEngine engine, sqlite3_stmt* stmt) @trusted` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:411`](../../source/dun/builtins/sqlite.d#L411) | `string sqliteErrMsg(sqlite3* db) @trusted` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:425`](../../source/dun/builtins/sqlite.d#L425) | `@trusted unittest` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:435`](../../source/dun/builtins/sqlite.d#L435) | `@trusted unittest` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:446`](../../source/dun/builtins/sqlite.d#L446) | `@trusted unittest` | _(missing)_ |
| [`source/dun/builtins/sqlite.d:483`](../../source/dun/builtins/sqlite.d#L483) | `@trusted unittest` | _(missing)_ |

## Missing-rationale audit

- **Sites without an inline rationale comment**: 1338 / 1470 (91.0%)
- Goal: every `@trusted` block has a `///` doc comment on the preceding line explaining why the trust is justified. Use this ledger to find the gaps.
- Process: when adding a new `@trusted` annotation, add a `///` line above it with the form `/// <why this @trusted is safe — invariant being asserted by the programmer>`.

## Regenerating

```sh
ldc2 -run tools/gen_trusted_ledger.d
```

Re-run after any change that adds, removes, or moves a `@trusted` annotation. The script walks `source/`, groups by category (derived from the file path + signature), and writes this file.
