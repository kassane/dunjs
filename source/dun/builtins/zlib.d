module dun.builtins.zlib;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;

private enum {
    ZLIB_DEFLATE_WINDOW = 15,
    ZLIB_GZIP_WINDOW    = 31,
    ZLIB_RAW_WINDOW     = -15,
}

void registerZlibModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerZlibModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "deflateSync", engine.newFunction(&jsDeflateSync, "deflateSync", 1));
    engine.setProperty(obj, "inflateSync", engine.newFunction(&jsInflateSync, "inflateSync", 1));
    engine.setProperty(obj, "gzipSync", engine.newFunction(&jsGzipSync, "gzipSync", 1));
    engine.setProperty(obj, "gunzipSync", engine.newFunction(&jsGunzipSync, "gunzipSync", 1));
    engine.setProperty(obj, "deflateRawSync", engine.newFunction(&jsDeflateRawSync, "deflateRawSync", 1));
    engine.setProperty(obj, "inflateRawSync", engine.newFunction(&jsInflateRawSync, "inflateRawSync", 1));
    engine.setProperty(obj, "__brotliCompressSync", engine.newFunction(&jsBrotliCompressSync, "brotliCompressSync", 2));
    engine.setProperty(obj, "__brotliDecompressSync", engine.newFunction(&jsBrotliDecompressSync, "brotliDecompressSync", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_zlib__", obj);
    engine.freeValue(global);

    // Evaluate JS extension for async wrappers, stream classes, and constants
    auto extResult = engine.eval(zlibExtensionSource(), "<zlib-ext>");
    if (!extResult.isError)
        engine.freeValue(extResult.value);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private enum zlibExportNames = [
        "deflateSync", "inflateSync", "gzipSync",
        "gunzipSync", "deflateRawSync", "inflateRawSync",
        "deflate", "inflate", "gzip", "gunzip",
        "deflateRaw", "inflateRaw",
        "brotliCompress", "brotliDecompress",
        "brotliCompressSync", "brotliDecompressSync",
        "unzipSync",
        "createDeflate", "createInflate",
        "createGzip", "createGunzip",
        "createDeflateRaw", "createInflateRaw",
        "createBrotliCompress", "createBrotliDecompress",
        "constants",
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:zlib", &zlibModuleInit);
        if (m is null) return;
        foreach (name; zlibExportNames)
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int zlibModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in zlibModuleInit");
        assert(m !is null, "Null JSModuleDef in zlibModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto zlibObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_zlib__");
        foreach (name; zlibExportNames)
        {
            auto fn = JS_GetPropertyStr(ctx, zlibObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", zlibObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

ubyte[] extractInputBytes(IJSEngine engine, JSHandle val) @trusted
{
    if (engine.isString(val))
    {
        auto s = engine.extractString(val);
        return cast(ubyte[]) s.dup;
    }
    auto taBytes = engine.getTypedArrayBytes(val);
    if (taBytes !is null)
        return taBytes.dup;
    if (engine.isArray(val) || engine.isObject(val))
    {
        int len = engine.getArrayLength(val);
        if (len <= 0) return null;
        auto buf = new ubyte[len];
        foreach (i; 0 .. cast(uint) len)
        {
            auto elem = engine.getPropertyIndex(val, i);
            buf[i] = cast(ubyte) engine.extractInt(elem);
            engine.freeValue(elem);
        }
        return buf;
    }
    return null;
}

JSHandle returnBytes(IJSEngine engine, const(ubyte)[] data) @trusted
{
    auto global = engine.getGlobal();
    auto bufCtor = engine.getProperty(global, "Buffer");
    engine.freeValue(global);
    if (engine.isObject(bufCtor) || engine.isFunction(bufCtor))
    {
        auto fromFn = engine.getProperty(bufCtor, "from");
        if (engine.isFunction(fromFn))
        {
            auto u8 = engine.newUint8Array(data);
            auto result = engine.callFunction(fromFn, bufCtor, [u8]);
            engine.freeValue(u8);
            engine.freeValue(fromFn);
            engine.freeValue(bufCtor);
            return result;
        }
        engine.freeValue(fromFn);
    }
    engine.freeValue(bufCtor);
    return engine.newUint8Array(data);
}

JSHandle doCompress(void* ctx, JSHandle[] args, int windowBits) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in doCompress");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("Expected data argument");

    try
    {
        auto input = extractInputBytes(engine, args[0]);
        if (input is null) return engine.throwTypeError("Expected string or array input");

        import std.zlib : Compress, HeaderFormat;

        HeaderFormat hf;
        if (windowBits == ZLIB_GZIP_WINDOW)
            hf = HeaderFormat.gzip;
        else if (windowBits == ZLIB_RAW_WINDOW)
            hf = HeaderFormat.deflate;
        else
            hf = HeaderFormat.deflate;

        auto c = new Compress(hf);
        auto chunk = cast(ubyte[]) c.compress(input);
        auto flushed = cast(ubyte[]) c.flush();
        ubyte[] result = chunk ~ flushed;

        // For raw deflate, strip the 2-byte zlib header and 4-byte checksum
        if (windowBits == ZLIB_RAW_WINDOW && result.length > 6)
            result = result[2 .. $ - 4];

        return returnBytes(engine, result);
    }
    catch (Exception) { return engine.throwTypeError("Compression failed"); }
}

JSHandle doDecompress(void* ctx, JSHandle[] args, int windowBits) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in doDecompress");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("Expected data argument");

    try
    {
        auto input = extractInputBytes(engine, args[0]);
        if (input is null) return engine.throwTypeError("Expected string or array input");

        import std.zlib : UnCompress, HeaderFormat;

        HeaderFormat hf;
        if (windowBits == ZLIB_GZIP_WINDOW)
            hf = HeaderFormat.gzip;
        else if (windowBits == ZLIB_RAW_WINDOW)
            hf = HeaderFormat.deflate;
        else
            hf = HeaderFormat.deflate;

        // For raw inflate, wrap with zlib header so std.zlib can handle it
        ubyte[] toDecompress = input;
        if (windowBits == ZLIB_RAW_WINDOW)
        {
            // Add minimal zlib header (CMF=0x78, FLG=0x01) and recompute
            toDecompress = [cast(ubyte) 0x78, cast(ubyte) 0x01] ~ input;
            import std.zlib : adler32;
            uint checksum = adler32(0, toDecompress[2 .. $]);
            toDecompress ~= [
                cast(ubyte)((checksum >> 24) & 0xFF),
                cast(ubyte)((checksum >> 16) & 0xFF),
                cast(ubyte)((checksum >> 8) & 0xFF),
                cast(ubyte)(checksum & 0xFF),
            ];
        }

        auto uc = new UnCompress(hf);
        auto chunk = cast(ubyte[]) uc.uncompress(toDecompress);
        auto flushed = cast(ubyte[]) uc.flush();
        ubyte[] result = chunk ~ flushed;
        return returnBytes(engine, result);
    }
    catch (Exception) { return engine.throwTypeError("Decompression failed"); }
}

JSHandle jsDeflateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_DEFLATE_WINDOW);
}

JSHandle jsInflateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_DEFLATE_WINDOW);
}

JSHandle jsGzipSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_GZIP_WINDOW);
}

JSHandle jsGunzipSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_GZIP_WINDOW);
}

JSHandle jsDeflateRawSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_RAW_WINDOW);
}

JSHandle jsInflateRawSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_RAW_WINDOW);
}

JSHandle jsBrotliCompressSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.brotli;
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in jsBrotliCompressSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("Expected data argument");

    auto input = extractInputBytes(engine, args[0]);
    if (input is null) return engine.throwTypeError("Expected string or array input");

    int quality = BROTLI_DEFAULT_QUALITY;
    int lgwin = BROTLI_DEFAULT_WINDOW;
    BrotliEncoderMode mode = BROTLI_MODE_GENERIC;

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto qVal = engine.getProperty(args[1], "quality");
        if (engine.isNumber(qVal))
        {
            auto q = engine.extractInt(qVal);
            if (q >= BROTLI_MIN_QUALITY && q <= BROTLI_MAX_QUALITY) quality = q;
        }
        engine.freeValue(qVal);
        auto lgVal = engine.getProperty(args[1], "lgwin");
        if (engine.isNumber(lgVal))
        {
            auto lg = engine.extractInt(lgVal);
            if (lg >= BROTLI_MIN_WINDOW_BITS && lg <= BROTLI_MAX_WINDOW_BITS) lgwin = lg;
        }
        engine.freeValue(lgVal);
        auto mVal = engine.getProperty(args[1], "mode");
        if (engine.isNumber(mVal))
        {
            auto m = engine.extractInt(mVal);
            if (m >= 0 && m <= 2) mode = cast(BrotliEncoderMode) m;
        }
        engine.freeValue(mVal);
    }

    size_t maxLen = BrotliEncoderMaxCompressedSize(input.length);
    if (maxLen == 0) maxLen = input.length + 64;
    auto outBuf = new ubyte[maxLen];
    size_t outLen = maxLen;
    const(ubyte)* inPtr = input.length ? input.ptr : null;
    auto ok = BrotliEncoderCompress(quality, lgwin, mode, input.length, inPtr, &outLen, outBuf.ptr);
    if (!ok) return engine.throwTypeError("Brotli compression failed");
    return returnBytes(engine, outBuf[0 .. outLen]);
}

JSHandle jsBrotliDecompressSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.platform.brotli;
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in jsBrotliDecompressSync");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("Expected data argument");

    auto input = extractInputBytes(engine, args[0]);
    if (input is null) return engine.throwTypeError("Expected string or array input");
    if (input.length == 0) return returnBytes(engine, cast(const(ubyte)[]) null);

    // Streaming decoder for unknown output size
    auto brState = BrotliDecoderCreateInstance(null, null, null);
    if (brState is null) return engine.throwTypeError("Brotli decoder allocation failed");
    scope (exit) BrotliDecoderDestroyInstance(brState);

    enum CHUNK = 64 * 1024;
    import dun.platform.arena : Appender;
    Appender!(ubyte[]) out_;
    out_.reserve(input.length * 4);

    size_t availIn = input.length;
    const(ubyte)* nextIn = input.ptr;
    ubyte[CHUNK] outBuf;

    while (true)
    {
        ubyte* nextOut = outBuf.ptr;
        size_t availOut = outBuf.length;
        size_t totalOut;
        auto result = BrotliDecoderDecompressStream(brState, &availIn, &nextIn, &availOut, &nextOut, &totalOut);
        // bytes written = chunk - availOut
        size_t written = outBuf.length - availOut;
        if (written > 0)
            out_.put(outBuf[0 .. written]);
        if (result == BROTLI_DECODER_RESULT_SUCCESS)
            return returnBytes(engine, out_.data);
        if (result == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT)
            continue;
        if (result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT)
            return engine.throwTypeError("Brotli decompression failed: truncated input");
        return engine.throwTypeError("Brotli decompression failed: corrupt input");
    }
}

string zlibExtensionSource() pure @safe nothrow
{
    return `(function() {
    var zlib = globalThis.__dun_cjs_zlib__;
    if (!zlib) return;

    // --- Async wrapper helper ---
    function asyncWrap(syncFn) {
        return function(input, opts, callback) {
            if (typeof opts === 'function') { callback = opts; opts = {}; }
            Promise.resolve().then(function() {
                try {
                    var result = syncFn(input, opts);
                    if (callback) callback(null, result);
                } catch(e) {
                    if (callback) callback(e);
                }
            });
        };
    }

    // --- Async callback versions ---
    zlib.deflate = asyncWrap(zlib.deflateSync);
    zlib.inflate = asyncWrap(zlib.inflateSync);
    zlib.gzip = asyncWrap(zlib.gzipSync);
    zlib.gunzip = asyncWrap(zlib.gunzipSync);
    zlib.deflateRaw = asyncWrap(zlib.deflateRawSync);
    zlib.inflateRaw = asyncWrap(zlib.inflateRawSync);

    // Brotli (real impl via libbrotli)
    zlib.brotliCompressSync = function(input, opts) {
        return zlib.__brotliCompressSync(input, opts || {});
    };
    zlib.brotliDecompressSync = function(input) {
        return zlib.__brotliDecompressSync(input);
    };
    zlib.brotliCompress = function(input, opts, callback) {
        if (typeof opts === 'function') { callback = opts; opts = {}; }
        Promise.resolve().then(function() {
            try {
                var out = zlib.__brotliCompressSync(input, opts || {});
                if (callback) callback(null, out);
            } catch(e) { if (callback) callback(e); }
        });
    };
    zlib.brotliDecompress = function(input, opts, callback) {
        if (typeof opts === 'function') { callback = opts; opts = {}; }
        Promise.resolve().then(function() {
            try {
                var out = zlib.__brotliDecompressSync(input);
                if (callback) callback(null, out);
            } catch(e) { if (callback) callback(e); }
        });
    };

    zlib.unzipSync = function(input) {
        // Node behavior: unzip auto-detects gzip vs deflate by magic bytes
        if (input && input.length >= 2 && input[0] === 0x1f && input[1] === 0x8b)
            return zlib.gunzipSync(input);
        return zlib.inflateSync(input);
    };

    // --- Stream classes ---
    var Transform;
    try {
        var streamMod = globalThis.__dun_cjs_stream__;
        if (streamMod && streamMod.Transform) Transform = streamMod.Transform;
    } catch(e) {}

    if (Transform) {
        zlib.createDeflate = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.deflateSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createInflate = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.inflateSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createGzip = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.gzipSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createGunzip = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.gunzipSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createDeflateRaw = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.deflateRawSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createInflateRaw = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    try { cb(null, zlib.inflateRawSync(chunk, opts)); }
                    catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createBrotliCompress = function(opts) {
            // Accumulate chunks then encode at flush; brotli has no stream/one-shot interop.
            var chunks = [];
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    chunks.push(chunk);
                    cb();
                },
                flush: function(cb) {
                    try {
                        var total = 0;
                        for (var i = 0; i < chunks.length; i++) total += chunks[i].length;
                        var merged = new Uint8Array(total);
                        var off = 0;
                        for (var j = 0; j < chunks.length; j++) {
                            merged.set(chunks[j], off);
                            off += chunks[j].length;
                        }
                        cb(null, zlib.__brotliCompressSync(merged, opts || {}));
                    } catch(e) { cb(e); }
                }
            });
            return t;
        };
        zlib.createBrotliDecompress = function(opts) {
            var chunks = [];
            var t = new Transform({
                transform: function(chunk, enc, cb) {
                    chunks.push(chunk);
                    cb();
                },
                flush: function(cb) {
                    try {
                        var total = 0;
                        for (var i = 0; i < chunks.length; i++) total += chunks[i].length;
                        var merged = new Uint8Array(total);
                        var off = 0;
                        for (var j = 0; j < chunks.length; j++) {
                            merged.set(chunks[j], off);
                            off += chunks[j].length;
                        }
                        cb(null, zlib.__brotliDecompressSync(merged));
                    } catch(e) { cb(e); }
                }
            });
            return t;
        };
    } else {
        // Minimal stubs if Transform is not available
        zlib.createDeflate = function() { return {}; };
        zlib.createInflate = function() { return {}; };
        zlib.createGzip = function() { return {}; };
        zlib.createGunzip = function() { return {}; };
        zlib.createDeflateRaw = function() { return {}; };
        zlib.createInflateRaw = function() { return {}; };
        zlib.createBrotliCompress = function() { return {}; };
        zlib.createBrotliDecompress = function() { return {}; };
    }

    // --- zlib.constants ---
    zlib.constants = {
        Z_NO_FLUSH: 0,
        Z_PARTIAL_FLUSH: 1,
        Z_SYNC_FLUSH: 2,
        Z_FULL_FLUSH: 3,
        Z_FINISH: 4,
        Z_BLOCK: 5,
        Z_OK: 0,
        Z_STREAM_END: 1,
        Z_NEED_DICT: 2,
        Z_ERRNO: -1,
        Z_STREAM_ERROR: -2,
        Z_DATA_ERROR: -3,
        Z_MEM_ERROR: -4,
        Z_BUF_ERROR: -5,
        Z_VERSION_ERROR: -6,
        Z_NO_COMPRESSION: 0,
        Z_BEST_SPEED: 1,
        Z_BEST_COMPRESSION: 9,
        Z_DEFAULT_COMPRESSION: -1,
        Z_FILTERED: 1,
        Z_HUFFMAN_ONLY: 2,
        Z_RLE: 3,
        Z_FIXED: 4,
        Z_DEFAULT_STRATEGY: 0,
        Z_DEFAULT_WINDOWBITS: 15,
        Z_MIN_WINDOWBITS: 8,
        Z_MAX_WINDOWBITS: 15,
        Z_MIN_CHUNK: 64,
        Z_MAX_CHUNK: Infinity,
        Z_DEFAULT_CHUNK: 16384,
        Z_MIN_MEMLEVEL: 1,
        Z_MAX_MEMLEVEL: 9,
        Z_DEFAULT_MEMLEVEL: 8,
        Z_MIN_LEVEL: -1,
        Z_MAX_LEVEL: 9,
        BROTLI_OPERATION_PROCESS: 0,
        BROTLI_OPERATION_FLUSH: 1,
        BROTLI_OPERATION_FINISH: 2,
        BROTLI_OPERATION_EMIT_METADATA: 3
    };
})()`;
}
