module dun.builtins.zlib;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

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
        JS_FreeValue(ctx, zlibObj);
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
    assert(ctx !is null, "Null ctx in doCompress");
    auto state = cast(DunState*) ctx;
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
    assert(ctx !is null, "Null ctx in doDecompress");
    auto state = cast(DunState*) ctx;
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

    // Brotli stubs (passthrough, brotli not available)
    zlib.brotliCompress = function(input, opts, callback) {
        if (typeof opts === 'function') { callback = opts; opts = {}; }
        Promise.resolve().then(function() {
            try {
                var buf;
                if (typeof input === 'string') {
                    buf = new Uint8Array(input.length);
                    for (var i = 0; i < input.length; i++) buf[i] = input.charCodeAt(i);
                } else {
                    buf = input;
                }
                if (callback) callback(null, buf);
            } catch(e) {
                if (callback) callback(e);
            }
        });
    };
    zlib.brotliDecompress = function(input, opts, callback) {
        if (typeof opts === 'function') { callback = opts; opts = {}; }
        Promise.resolve().then(function() {
            try {
                var buf;
                if (typeof input === 'string') {
                    buf = new Uint8Array(input.length);
                    for (var i = 0; i < input.length; i++) buf[i] = input.charCodeAt(i);
                } else {
                    buf = input;
                }
                if (callback) callback(null, buf);
            } catch(e) {
                if (callback) callback(e);
            }
        });
    };

    zlib.brotliCompressSync = function(input) {
        if (typeof input === 'string') {
            var buf = new Uint8Array(input.length);
            for (var i = 0; i < input.length; i++) buf[i] = input.charCodeAt(i);
            return buf;
        }
        return input;
    };
    zlib.brotliDecompressSync = function(input) {
        if (typeof input === 'string') {
            var buf = new Uint8Array(input.length);
            for (var i = 0; i < input.length; i++) buf[i] = input.charCodeAt(i);
            return buf;
        }
        return input;
    };
    zlib.unzipSync = function(input) { return zlib.inflateSync(input); };
    zlib.createBrotliCompress = function(opts) { return zlib.createDeflate ? zlib.createDeflate(opts) : null; };
    zlib.createBrotliDecompress = function(opts) { return zlib.createInflate ? zlib.createInflate(opts) : null; };

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
            var t = new Transform({
                transform: function(chunk, enc, cb) { cb(null, chunk); }
            });
            return t;
        };
        zlib.createBrotliDecompress = function(opts) {
            var t = new Transform({
                transform: function(chunk, enc, cb) { cb(null, chunk); }
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
