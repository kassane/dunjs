module dun.builtins.v8;


/// `@trusted policy`: V8-specific JS API (`v8.getHeapStatistics`,
/// `v8.serialize`, `v8.deserialize`, etc.). Wraps engine-only V8
/// methods that aren't on `IJSEngine`. Every `@trusted` is one of:
///   1. `engine.rawContext()` cast to the V8 context handle, then
///      bridged through `vendor/v8shim/` (same surface as
///      `engine/v8/backend.d`).
///   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;

// Default heap limit we report to JS callers. Real DunJS heap usage is
// gated by `--max-memory`; this is just the "what would V8 say" number
// expected by `v8.getHeapStatistics().heap_size_limit`.
private enum DEFAULT_HEAP_LIMIT_BYTES = 2L * 1024 * 1024 * 1024;  // 2 GiB

/// `node:v8` compat — `writeHeapSnapshot` + `getHeapStatistics` +
/// serializer constants. Snapshot is a minimal-but-valid v8 JSON.
void registerV8Module(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerV8Module");

    // Register the exported functions in one table-driven sweep -- one
    // entry per (name, native impl, formal arity).
    struct V8Fn { string name; void* fn; int argc; }
    static V8Fn[] funcs = [
        V8Fn("writeHeapSnapshot",    cast(void*) &jsWriteHeapSnapshot,    1),
        V8Fn("getHeapStatistics",    cast(void*) &jsGetHeapStatistics,    0),
        V8Fn("getHeapSpaceStatistics", cast(void*) &jsGetHeapSpaceStatistics, 0),
        V8Fn("getHeapCodeStatistics", cast(void*) &jsGetHeapCodeStatistics,  0),
        V8Fn("cachedDataVersionTag", cast(void*) &jsCachedDataVersionTag, 0),
        V8Fn("setFlagsFromString",   cast(void*) &jsSetFlagsFromString,   1),
        V8Fn("getHeapSnapshot",      cast(void*) &jsGetHeapSnapshot,      0),
    ];
    auto obj = engine.newObject();
    import dun.engine.iface : NativeCallback;
    foreach (f; funcs)
        engine.setProperty(obj, f.name,
            engine.newFunction(cast(NativeCallback) f.fn, f.name, f.argc));

    // Serializer / Deserializer stubs (npm pkgs probe for class shapes).
    // setProperty consumes the value ref on QuickJS, so we have to dup
    // the handle for every alias except the last one. Same trap caught
    // by the Phase 19h JSHandle leak sweep.
    auto serObj = engine.newObject();
    auto desObj = engine.newObject();
    static immutable serAliases = ["Serializer", "DefaultSerializer"];
    static immutable desAliases = ["Deserializer", "DefaultDeserializer"];
    foreach (i, alias_; serAliases)
        engine.setProperty(obj, alias_,
            i + 1 < serAliases.length ? engine.dupValue(serObj) : serObj);
    foreach (i, alias_; desAliases)
        engine.setProperty(obj, alias_,
            i + 1 < desAliases.length ? engine.dupValue(desObj) : desObj);
    engine.setProperty(obj, "serialize",
        engine.newFunction(&jsSerialize, "serialize", 1));
    engine.setProperty(obj, "deserialize",
        engine.newFunction(&jsDeserialize, "deserialize", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_v8__", obj);
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
        if (ctx is null) return;
        auto m = JS_NewCModule(ctx, "dun:v8", &v8ModuleInit);
        if (m is null) return;
        foreach (name; ["writeHeapSnapshot", "getHeapStatistics",
                "getHeapSpaceStatistics", "getHeapCodeStatistics",
                "cachedDataVersionTag", "setFlagsFromString",
                "Serializer", "Deserializer",
                "DefaultSerializer", "DefaultDeserializer",
                "serialize", "deserialize", "getHeapSnapshot"])
            JS_AddModuleExport(ctx, m, name.ptr);
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int v8ModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in v8ModuleInit");
        assert(m !is null, "Null module def in v8ModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        scope(exit) JS_FreeValue(ctx, global);
        auto v8Obj = JS_GetPropertyStr(ctx, global, "__dun_cjs_v8__");
        if (JS_IsUndefined(v8Obj)) return -1;
        scope(exit) JS_FreeValue(ctx, v8Obj);
        foreach (name; ["writeHeapSnapshot", "getHeapStatistics",
                "getHeapSpaceStatistics", "getHeapCodeStatistics",
                "cachedDataVersionTag", "setFlagsFromString",
                "Serializer", "Deserializer",
                "DefaultSerializer", "DefaultDeserializer",
                "serialize", "deserialize", "getHeapSnapshot"])
        {
            auto p = JS_GetPropertyStr(ctx, v8Obj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, p);
        }
        JS_SetModuleExport(ctx, m, "default", JS_DupValue(ctx, v8Obj));
        return 0;
    }
}

/// Synthetic v8 heap-snapshot — engine name + `core.memory.GC` stats
/// + one root node. Doesn't walk the JS heap.
private JSHandle jsWriteHeapSnapshot(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;

    string path;
    if (args.length >= 1 && engine.isString(args[0]))
        path = engine.extractString(args[0]);
    else
    {
        // Match Node's autogenerated `Heap.<date>.<time>.<pid>.0.001.heapsnapshot`
        import core.sys.posix.unistd : getpid;
        import std.datetime : Clock;
        import std.format : format;
        auto now = Clock.currTime();
        path = format!"Heap.%04d%02d%02d.%02d%02d%02d.%d.0.001.heapsnapshot"(
            now.year, now.month, now.day,
            now.hour, now.minute, now.second, getpid());
    }

    // Synthesize a minimal-valid heap snapshot JSON. The format is
    // documented at v8.dev/blog/heap-snapshots. Node tools that just
    // probe for the file open without erroring.
    string body_ =
        `{"snapshot":{"meta":{"node_fields":["type","name","id","self_size","edge_count","trace_node_id","detachedness"],`
        ~ `"node_types":[["hidden","array","string","object","code","closure","regexp","number","native","synthetic","concatenated string","sliced string"],"string","number","number","number","number","number"],`
        ~ `"edge_fields":["type","name_or_index","to_node"],`
        ~ `"edge_types":[["context","element","property","internal","hidden","shortcut","weak"],"string_or_number","node"],`
        ~ `"trace_function_info_fields":["function_id","name","script_name","script_id","line","column"],`
        ~ `"trace_node_fields":["id","function_info_index","count","size","children"],`
        ~ `"sample_fields":["timestamp_us","last_assigned_id"],`
        ~ `"location_fields":["object_index","script_id","line","column"]},`
        ~ `"node_count":1,"edge_count":0,"trace_function_count":0},`
        ~ `"nodes":[9,0,1,0,0,0,0],"edges":[],"trace_function_infos":[],"trace_tree":[],"samples":[],"locations":[],`
        ~ `"strings":["(root)"]}`;

    try
    {
        import std.file : write;
        write(path, body_);
    }
    catch (Exception)
    {
        return engine.throwTypeError("writeHeapSnapshot: failed to write file");
    }
    return engine.newString(path);
}

private JSHandle jsGetHeapSnapshot(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    // Returns a Readable stream in Node; we expose a fake object with
    // .read() returning the snapshot bytes once, then null.
    return state.engine.throwTypeError(
        "v8.getHeapSnapshot() is not yet supported; use v8.writeHeapSnapshot() instead");
}

private JSHandle jsGetHeapStatistics(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    import core.memory : GC;
    auto stats = GC.stats;
    auto totalSize = cast(double)(stats.usedSize + stats.freeSize);
    auto usedSize  = cast(double) stats.usedSize;
    auto freeSize  = cast(double) stats.freeSize;
    auto obj = engine.newObject();
    // DunJS always presents as a single isolate / no executable heap.
    enum V8_NATIVE_CONTEXTS = 1;
    // Floats (byte counts that can exceed int32 range)
    static immutable doubleFields = [
        "total_heap_size", "total_heap_size_executable",
        "total_physical_size", "total_available_size",
        "used_heap_size", "heap_size_limit",
        "malloced_memory", "peak_malloced_memory",
    ];
    double[doubleFields.length] doubleValues = [
        totalSize, 0,
        totalSize, freeSize,
        usedSize,  cast(double) DEFAULT_HEAP_LIMIT_BYTES,
        usedSize,  usedSize,
    ];
    static assert(doubleValues.length == doubleFields.length);
    foreach (i, name; doubleFields)
        engine.setProperty(obj, name, engine.newFloat(doubleValues[i]));
    // Ints (counters small enough to fit in int32)
    static immutable intFields = [
        "does_zap_garbage", "number_of_native_contexts",
        "number_of_detached_contexts", "total_global_handles_size",
        "used_global_handles_size", "external_memory",
    ];
    int[intFields.length] intValues =
        [0, V8_NATIVE_CONTEXTS, 0, 0, 0, 0];
    static assert(intValues.length == intFields.length);
    foreach (i, name; intFields)
        engine.setProperty(obj, name, engine.newInt(intValues[i]));
    return obj;
}

private JSHandle jsGetHeapSpaceStatistics(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    return state.engine.newArray();  // Node returns a per-space array; empty is acceptable.
}

private JSHandle jsGetHeapCodeStatistics(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    auto engine = state.engine;
    auto obj = engine.newObject();
    engine.setProperty(obj, "code_and_metadata_size", engine.newInt(0));
    engine.setProperty(obj, "bytecode_and_metadata_size", engine.newInt(0));
    engine.setProperty(obj, "external_script_source_size", engine.newInt(0));
    return obj;
}

private JSHandle jsCachedDataVersionTag(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    return state.engine.newInt(0);
}

private JSHandle jsSetFlagsFromString(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    return state.engine.newUndefined();  // no-op; we don't expose V8 flags.
}

private JSHandle jsSerialize(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    // Fallback: JSON-encode the value into a Buffer-like Uint8Array.
    if (args.length < 1) return engine.throwTypeError("serialize requires a value");
    auto res = engine.eval(
        "(function(v){return new TextEncoder().encode(JSON.stringify(v));})",
        "<v8-serialize>");
    if (res.isError) return res.value;
    auto undef = engine.newUndefined();
    scope(exit) engine.freeValue(undef);
    JSHandle[1] callArgs;
    callArgs[0] = args[0];
    auto out_ = engine.callFunction(res.value, undef, callArgs[]);
    engine.freeValue(res.value);
    return out_;
}

private JSHandle jsDeserialize(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = ctxState(ctx);
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("deserialize requires a buffer");
    auto res = engine.eval(
        "(function(b){return JSON.parse(new TextDecoder().decode(b));})",
        "<v8-deserialize>");
    if (res.isError) return res.value;
    auto undef = engine.newUndefined();
    scope(exit) engine.freeValue(undef);
    JSHandle[1] callArgs;
    callArgs[0] = args[0];
    auto out_ = engine.callFunction(res.value, undef, callArgs[]);
    engine.freeValue(res.value);
    return out_;
}
