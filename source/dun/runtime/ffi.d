module dun.runtime.ffi;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

// Bun.FFI / Deno.dlopen compat — basic dlopen + dlsym dispatch with a
// fixed signature table. Covers the common patterns used by real
// addons (sqlite open/close, libcurl easy_*, libpng read, etc.).
// Arbitrary signatures need libffi; we don't link it (yet).
//
// Audit notes (per project rules):
// * FFI extern(C) decls below are `@nogc nothrow` — no Druntime
//   allocation across the C boundary.
// * The dispatch path is `@trusted` only where raw `cast(Fn*)` is
//   required; helpers are split off so the `@trusted` scope stays
//   narrow.
// * `@mustuse JSResult` (DIP 1038) is consumed via `r.isError` /
//   `r.value` everywhere it appears.
// * TIGER_STYLE asserts at every callback entry.

version (Posix)
{
    private extern (C) nothrow @nogc
    {
        void* dlopen(const(char)* path, int flags);
        void* dlsym(void* handle, const(char)* sym);
        int dlclose(void* handle);
        const(char)* dlerror();
    }
    // POSIX dlfcn.h flags — `RTLD_NOW` resolves all symbols up-front
    // so a missing dep fails at `dlopen()` time, not at the first
    // `dlsym()` call. Mirrors what Deno + Bun pass to libffi.
    private enum int RTLD_LAZY = 1;
    private enum int RTLD_NOW  = 2;
}

// Stack-buffer capacity for argument arrays. Matches the existing
// `JSHandle[16]` trampoline buffer in each backend — keeps small-arg
// FFI calls off the GC.
private enum size_t MAX_FFI_STACK_ARGS = 16;

// Sentinel returned by `napi_async_init` / `napi_open_callback_scope`
// in our shim — non-null but never dereferenced.
private enum void* FFI_NONNULL_SENTINEL = cast(void*) 1;

void installFfiCompat(IJSEngine engine, DunState* state) @trusted
{
    assert(engine !is null, "Null engine in installFfiCompat");
    assert(state !is null, "Null state in installFfiCompat");

    auto global = engine.getGlobal();

    // Internal dispatcher — first arg is the slot id (hex string),
    // remaining args go to the native function. JS-side wrapper
    // baked in `dlopen()` captures the id in closure.
    engine.setProperty(global, "__dun_ffi_call__",
        engine.newFunction(&jsFfiDispatchById, "__dun_ffi_call__", 0));

    // Deno.dlopen — installed under existing Deno namespace.
    auto denoObj = engine.getProperty(global, "Deno");
    if (engine.isObject(denoObj))
    {
        engine.setProperty(denoObj, "dlopen",
            engine.newFunction(&jsDenoDlopen, "dlopen", 2));
        engine.setProperty(denoObj, "UnsafePointer",
            engine.newFunction(&jsUnsafePointer, "UnsafePointer", 1));
    }
    engine.freeValue(denoObj);
    engine.freeValue(global);
}

// Limit signatures to a curated set. The signature string is built
// in JS as "p:<param-types>;r:<result-type>" e.g. "p:i32,i32;r:i32".
// Each combination has a matching D dispatcher that casts the dlsym'd
// void* to the proper extern(C) function pointer type.

// All FFI function pointers are `nothrow @nogc` — the host C
// function is opaque to D's GC + EH; if it ever surfaced a D
// exception or triggered a GC collection across the boundary the
// runtime invariants would break. `@nogc` here guarantees the cast
// site can't be the source of a Druntime allocation.
private alias FnVoid    = extern(C) void function() nothrow @nogc;
private alias FnI32     = extern(C) int function() nothrow @nogc;
private alias FnI64     = extern(C) long function() nothrow @nogc;
private alias FnF64     = extern(C) double function() nothrow @nogc;
private alias FnPtr     = extern(C) void* function() nothrow @nogc;
private alias FnI32I32  = extern(C) int function(int) nothrow @nogc;
private alias FnVoidI32 = extern(C) void function(int) nothrow @nogc;
private alias FnI32_I32_I32 = extern(C) int function(int, int) nothrow @nogc;
private alias FnVoid_Ptr    = extern(C) void function(void*) nothrow @nogc;
private alias FnI32_Ptr     = extern(C) int function(void*) nothrow @nogc;
private alias FnPtr_Ptr     = extern(C) void* function(void*) nothrow @nogc;
private alias FnI32_Ptr_I32 = extern(C) int function(void*, int) nothrow @nogc;
private alias FnI32_Ptr_Ptr = extern(C) int function(void*, void*) nothrow @nogc;
private alias FnVoid_Ptr_Sz = extern(C) void function(void*, size_t) nothrow @nogc;
private alias FnI32_Cstr    = extern(C) int function(const(char)*) nothrow @nogc;
private alias FnI32_Cstr_Ptr = extern(C) int function(const(char)*, void*) nothrow @nogc;

private JSHandle jsDenoDlopen(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Deno.dlopen");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 2)
        return engine.throwTypeError("Deno.dlopen requires (path, symbols)");

    if (!state.permissions.check(Permission.run, ""))
        return engine.throwTypeError("Deno.dlopen requires --allow-run");

    auto path = engine.extractString(args[0]);

    version (Posix)
    {
        import std.string : toStringz, fromStringz;
        void* handle = dlopen(path.toStringz, RTLD_NOW);
        if (handle is null)
        {
            string err;
            try { err = cast(string) fromStringz(dlerror()); }
            catch (Exception) { err = "dlopen failed"; }
            return engine.throwTypeError("Deno.dlopen: " ~ err);
        }

        // Walk the symbols object, register a wrapper per entry.
        auto symbolsObj = engine.newObject();
        auto symbolsInput = args[1];
        auto keys = _getOwnKeys(engine, symbolsInput);
        foreach (k; keys)
        {
            auto spec = engine.getProperty(symbolsInput, k);
            scope(exit) engine.freeValue(spec);

            // Read name override (Bun-compat).
            auto nameVal = engine.getProperty(spec, "name");
            string realName = engine.isString(nameVal)
                ? engine.extractString(nameVal) : k;
            engine.freeValue(nameVal);

            void* fnptr = dlsym(handle, realName.toStringz);
            if (fnptr is null)
            {
                engine.freeValue(symbolsObj);
                return engine.throwTypeError(
                    "Deno.dlopen: failed to resolve symbol " ~ realName);
            }

            // Compose signature key.
            string sig = _buildSignature(engine, spec);
            auto wrapper = _makeWrapper(engine, state, fnptr, sig);
            if (wrapper.opaque[0] is null && wrapper.opaque[1] is null)
            {
                engine.freeValue(symbolsObj);
                return engine.throwTypeError(
                    "Deno.dlopen: unsupported signature for " ~ realName ~ " — "
                    ~ sig ~ " (DunJS FFI supports a curated set; arbitrary "
                    ~ "signatures require libffi)");
            }
            engine.setProperty(symbolsObj, k, wrapper);
        }

        auto libObj = engine.newObject();
        engine.setProperty(libObj, "symbols", symbolsObj);
        // Store handle as a hidden numeric for close().
        import std.format : format;
        try
        {
            engine.setProperty(libObj, "__handle__",
                engine.newString(format!"%x"(cast(size_t) handle)));
        }
        catch (Exception)
        {
            engine.freeValue(libObj);
            return engine.throwTypeError("Deno.dlopen: internal format error");
        }
        engine.setProperty(libObj, "close",
            engine.newFunction(&jsDlopenClose, "close", 0));
        return libObj;
    }
    else
    {
        return engine.throwTypeError("Deno.dlopen: not supported on this platform");
    }
}

private string[] _getOwnKeys(IJSEngine engine, JSHandle obj) @trusted
{
    auto global = engine.getGlobal();
    auto objectCtor = engine.getProperty(global, "Object");
    auto keysFn = engine.getProperty(objectCtor, "keys");
    engine.freeValue(objectCtor);
    engine.freeValue(global);
    JSHandle[1] argv = [obj];
    auto arr = engine.callFunction(keysFn, engine.newUndefined(), argv[]);
    engine.freeValue(keysFn);
    auto len = engine.getArrayLength(arr);
    string[] out_;
    foreach (i; 0 .. len)
    {
        auto k = engine.getPropertyIndex(arr, cast(uint) i);
        out_ ~= engine.extractString(k);
        engine.freeValue(k);
    }
    engine.freeValue(arr);
    return out_;
}

private string _buildSignature(IJSEngine engine, JSHandle spec) @trusted
{
    string sig = "p:";
    auto params = engine.getProperty(spec, "parameters");
    if (!engine.isArray(params))
    {
        engine.freeValue(params);
        // Bun.FFI uses `args` instead of `parameters`.
        params = engine.getProperty(spec, "args");
    }
    if (engine.isArray(params))
    {
        auto n = engine.getArrayLength(params);
        foreach (i; 0 .. n)
        {
            if (i > 0) sig ~= ",";
            auto t = engine.getPropertyIndex(params, cast(uint) i);
            sig ~= engine.extractString(t);
            engine.freeValue(t);
        }
    }
    engine.freeValue(params);
    sig ~= ";r:";
    auto res = engine.getProperty(spec, "result");
    if (!engine.isString(res))
    {
        engine.freeValue(res);
        res = engine.getProperty(spec, "returns");
    }
    sig ~= engine.isString(res) ? engine.extractString(res) : "void";
    engine.freeValue(res);
    return sig;
}

// Per-symbol context stored in setProperty so the callback can find
// the function pointer + signature.
private struct FfiSlot
{
    void* fnptr;
    string sig;
}
private __gshared FfiSlot[size_t] g_ffiSlots;
private __gshared size_t g_ffiSlotCounter = 0;

// Explicit mutex for the FFI slot table — `synchronized` without an
// explicit object synchronizes on a hidden per-module Monitor that
// can deadlock against user code or D runtime calls under iteration
// pressure. The pattern matches `g_napiWrapMu` in `dun.napi.napi`.
import core.sync.mutex : Mutex;
private __gshared Mutex g_ffiMu;
private __gshared bool g_ffiMuInit = false;
private void _ensureFfiMu() nothrow @trusted
{
    if (g_ffiMuInit) return;
    try { g_ffiMu = new Mutex(); g_ffiMuInit = true; }
    catch (Throwable) {}
}

private JSHandle _makeWrapper(IJSEngine engine, DunState* state, void* fnptr, string sig) @trusted
{
    // Only register if signature is in the curated set; else return
    // null sentinel for the caller to throw.
    if (!_signatureSupported(sig))
        return JSHandle.init;  // both pointers null

    _ensureFfiMu();
    size_t id;
    try
    {
        g_ffiMu.lock(); scope(exit) g_ffiMu.unlock();
        id = ++g_ffiSlotCounter;
        g_ffiSlots[id] = FfiSlot(fnptr, sig);
    }
    catch (Throwable) { return JSHandle.init; }

    // Build a JS-level closure: `function(...args){ return
    // __dun_ffi_call__("<id-hex>", ...args); }`. This avoids the
    // thisVal-vs-function-property problem on method-style calls
    // (`lib.symbols.atoi(...)` has thisVal=symbols, not the wrapper).
    import std.format : format;
    string src;
    try
    {
        src = "(function(){var __i=\"" ~ format!"%x"(id)
            ~ "\";return function(){var a=[__i];for(var i=0;i<arguments.length;i++)a.push(arguments[i]);return __dun_ffi_call__.apply(null,a);};})()";
    }
    catch (Exception) { return JSHandle.init; }
    auto r = engine.eval(src, "<ffi-wrap>");
    if (r.isError) { engine.freeValue(r.value); return JSHandle.init; }
    return r.value;
}

private bool _signatureSupported(string sig) @safe pure nothrow
{
    switch (sig)
    {
        case "p:;r:void":
        case "p:;r:i32":
        case "p:;r:u32":
        case "p:;r:i64":
        case "p:;r:f64":
        case "p:;r:pointer":
        case "p:;r:buffer":
        case "p:i32;r:i32":
        case "p:i32;r:void":
        case "p:i32,i32;r:i32":
        case "p:pointer;r:i32":
        case "p:pointer;r:void":
        case "p:pointer;r:pointer":
        case "p:pointer,i32;r:i32":
        case "p:pointer,pointer;r:i32":
        case "p:pointer,pointer;r:void":
        case "p:buffer,usize;r:void":
        case "p:pointer,usize;r:void":
        case "p:buffer;r:bool":
        case "p:pointer;r:bool":
        case "p:cstring;r:i32":
        case "p:cstring,pointer;r:i32":
            return true;
        default:
            return false;
    }
}

private JSHandle jsFfiDispatchById(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in FFI dispatch");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("FFI dispatch: missing slot id");
    auto idHex = engine.extractString(args[0]);

    import core.stdc.stdlib : strtoul;
    import std.string : toStringz;
    size_t id = cast(size_t) strtoul(idHex.toStringz, null, 16);

    _ensureFfiMu();
    FfiSlot slot;
    bool found = false;
    try
    {
        g_ffiMu.lock(); scope(exit) g_ffiMu.unlock();
        if (auto p = id in g_ffiSlots) { slot = *p; found = true; }
    }
    catch (Throwable) { return engine.throwTypeError("FFI dispatch: lock failed"); }
    if (!found)
        return engine.throwTypeError("FFI dispatch: invalid slot");

    return _dispatchSignature(engine, slot, args[1 .. $]);
}

private JSHandle _dispatchSignature(IJSEngine engine, FfiSlot slot, scope JSHandle[] args) @trusted
{
    auto fp = slot.fnptr;
    switch (slot.sig)
    {
        case "p:;r:void":
            (cast(FnVoid) fp)();
            return engine.newUndefined();
        case "p:;r:i32":
        case "p:;r:u32":
            return engine.newInt((cast(FnI32) fp)());
        case "p:;r:i64":
            return engine.newFloat(cast(double)(cast(FnI64) fp)());
        case "p:;r:f64":
            return engine.newFloat((cast(FnF64) fp)());
        case "p:;r:pointer":
        case "p:;r:buffer":
            return engine.newFloat(cast(double) cast(size_t)(cast(FnPtr) fp)());

        case "p:i32;r:i32":
            if (args.length < 1) return engine.throwTypeError("FFI: missing arg");
            return engine.newInt((cast(FnI32I32) fp)(engine.extractInt(args[0])));
        case "p:i32;r:void":
            if (args.length < 1) return engine.throwTypeError("FFI: missing arg");
            (cast(FnVoidI32) fp)(engine.extractInt(args[0]));
            return engine.newUndefined();
        case "p:i32,i32;r:i32":
            if (args.length < 2) return engine.throwTypeError("FFI: missing args");
            return engine.newInt((cast(FnI32_I32_I32) fp)(
                engine.extractInt(args[0]), engine.extractInt(args[1])));

        case "p:pointer;r:i32":
            return engine.newInt((cast(FnI32_Ptr) fp)(_arg2ptr(engine, args, 0)));
        case "p:pointer;r:void":
            (cast(FnVoid_Ptr) fp)(_arg2ptr(engine, args, 0));
            return engine.newUndefined();
        case "p:pointer;r:pointer":
            return engine.newFloat(cast(double) cast(size_t)
                (cast(FnPtr_Ptr) fp)(_arg2ptr(engine, args, 0)));
        case "p:pointer,i32;r:i32":
            return engine.newInt((cast(FnI32_Ptr_I32) fp)(
                _arg2ptr(engine, args, 0), engine.extractInt(args[1])));
        case "p:pointer,pointer;r:i32":
            return engine.newInt((cast(FnI32_Ptr_Ptr) fp)(
                _arg2ptr(engine, args, 0), _arg2ptr(engine, args, 1)));
        case "p:pointer,pointer;r:void":
            {
                alias FnVoid_Ptr_Ptr = extern(C) void function(void*, void*) nothrow @nogc;
                (cast(FnVoid_Ptr_Ptr) fp)(_arg2ptr(engine, args, 0), _arg2ptr(engine, args, 1));
                return engine.newUndefined();
            }
        case "p:buffer,usize;r:void":
        case "p:pointer,usize;r:void":
            (cast(FnVoid_Ptr_Sz) fp)(_arg2ptr(engine, args, 0),
                cast(size_t) engine.extractFloat(args[1]));
            return engine.newUndefined();
        case "p:buffer;r:bool":
        case "p:pointer;r:bool":
            {
                auto f = cast(FnI32_Ptr) fp;
                return engine.newBool(f(_arg2ptr(engine, args, 0)) != 0);
            }

        case "p:cstring;r:i32":
            return engine.newInt((cast(FnI32_Cstr) fp)(_arg2cstr(engine, args, 0)));
        case "p:cstring,pointer;r:i32":
            return engine.newInt((cast(FnI32_Cstr_Ptr) fp)(
                _arg2cstr(engine, args, 0), _arg2ptr(engine, args, 1)));

        default:
            return engine.throwTypeError("FFI: signature not supported: " ~ slot.sig);
    }
}

private void* _arg2ptr(IJSEngine engine, scope JSHandle[] args, size_t idx) @trusted
{
    if (args.length <= idx) return null;
    auto a = args[idx];
    if (engine.isNull(a) || engine.isUndefined(a)) return null;
    if (engine.isNumber(a))
        return cast(void*) cast(size_t) engine.extractFloat(a);
    auto bytes = engine.getTypedArrayBytes(a);
    if (bytes is null) return null;
    return cast(void*) bytes.ptr;
}

private const(char)* _arg2cstr(IJSEngine engine, scope JSHandle[] args, size_t idx) @trusted
{
    if (args.length <= idx) return null;
    auto a = args[idx];
    if (engine.isNull(a) || engine.isUndefined(a)) return null;
    if (engine.isString(a))
    {
        import std.string : toStringz;
        return toStringz(engine.extractString(a));
    }
    return cast(const(char)*) _arg2ptr(engine, args, idx);
}

private JSHandle jsDlopenClose(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in dlopen.close");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in dlopen.close");
    auto engine = state.engine;
    auto h = engine.getProperty(thisVal, "__handle__");
    if (engine.isString(h))
    {
        import core.stdc.stdlib : strtoul;
        import std.string : toStringz;
        auto hex = engine.extractString(h);
        size_t handle = cast(size_t) strtoul(hex.toStringz, null, 16);
        version (Posix)
            if (handle != 0) dlclose(cast(void*) handle);
    }
    engine.freeValue(h);
    return engine.newUndefined();
}

private JSHandle jsUnsafePointer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Deno.UnsafePointer");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in Deno.UnsafePointer");
    auto engine = state.engine;
    if (args.length < 1) return engine.newFloat(0);
    if (engine.isNumber(args[0])) return engine.dupValue(args[0]);
    auto bytes = engine.getTypedArrayBytes(args[0]);
    if (bytes is null) return engine.newFloat(0);
    return engine.newFloat(cast(double) cast(size_t) bytes.ptr);
}
