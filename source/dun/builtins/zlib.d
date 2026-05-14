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

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:zlib", &zlibModuleInit);
        if (m is null) return;
        foreach (name; ["deflateSync", "inflateSync", "gzipSync",
                        "gunzipSync", "deflateRawSync", "inflateRawSync"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int zlibModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in zlibModuleInit");
        assert(m !is null, "Null JSModuleDef in zlibModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto zlibObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_zlib__");
        foreach (name; ["deflateSync", "inflateSync", "gzipSync",
                        "gunzipSync", "deflateRawSync", "inflateRawSync"])
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

JSHandle jsDeflateSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_DEFLATE_WINDOW);
}

JSHandle jsInflateSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_DEFLATE_WINDOW);
}

JSHandle jsGzipSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_GZIP_WINDOW);
}

JSHandle jsGunzipSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_GZIP_WINDOW);
}

JSHandle jsDeflateRawSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doCompress(ctx, args, ZLIB_RAW_WINDOW);
}

JSHandle jsInflateRawSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    return doDecompress(ctx, args, ZLIB_RAW_WINDOW);
}
