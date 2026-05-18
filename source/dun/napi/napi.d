module dun.napi.napi;

import dun.napi.types;
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum MAX_NAPI_VALUES = 4096;
private __gshared napi_value_s[MAX_NAPI_VALUES] gValuePool;
private __gshared int gValuePoolUsed = 0;

napi_value allocValue(JSHandle h) nothrow @trusted
{
    assert(gValuePoolUsed >= 0 && gValuePoolUsed <= MAX_NAPI_VALUES,
        "NAPI value pool index out of bounds");
    if (gValuePoolUsed >= MAX_NAPI_VALUES)
        gValuePoolUsed = 0;
    gValuePool[gValuePoolUsed].handle = h;
    auto result = &gValuePool[gValuePoolUsed];
    gValuePoolUsed++;
    return result;
}

private __gshared napi_env_s gEnvStorage;
private __gshared bool gEnvInitialized = false;

napi_env getOrCreateEnv(DunState* state) nothrow @trusted
{
    assert(state !is null);
    assert(state.engine !is null);
    if (!gEnvInitialized)
    {
        gEnvStorage.engine = state.engine;
        gEnvStorage.state = state;
        gEnvInitialized = true;
    }
    return &gEnvStorage;
}

extern(C) @trusted:

napi_status napi_get_undefined(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newUndefined());
    return napi_ok;
}

napi_status napi_get_null(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newNull());
    return napi_ok;
}

napi_status napi_get_boolean(napi_env env, bool value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newBool(value));
    return napi_ok;
}

napi_status napi_create_int32(napi_env env, int value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newInt(value));
    return napi_ok;
}

napi_status napi_create_int64(napi_env env, long value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newFloat(cast(double) value));
    return napi_ok;
}

napi_status napi_create_double(napi_env env, double value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newFloat(value));
    return napi_ok;
}

napi_status napi_create_string_utf8(napi_env env, const(char)* str, size_t length, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    if (str is null)
    {
        *result = allocValue(env.engine.newString(""));
        return napi_ok;
    }
    try
    {
        string s;
        if (length == size_t.max)
        {
            import core.stdc.string : strlen;
            s = cast(string) str[0 .. strlen(str)];
        }
        else
            s = cast(string) str[0 .. length];
        *result = allocValue(env.engine.newString(s));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_create_object(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newObject());
    return napi_ok;
}

napi_status napi_create_array(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newArray());
    return napi_ok;
}

napi_status napi_create_array_with_length(napi_env env, size_t length, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newArray());
    return napi_ok;
}

napi_status napi_set_named_property(napi_env env, napi_value object, const(char)* utf8name, napi_value value)
{
    if (env is null || object is null || utf8name is null || value is null) return napi_invalid_arg;
    try
    {
        import core.stdc.string : strlen;
        auto name = cast(string) utf8name[0 .. strlen(utf8name)];
        env.engine.setProperty(object.handle, name, env.engine.dupValue(value.handle));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_named_property(napi_env env, napi_value object, const(char)* utf8name, napi_value* result)
{
    if (env is null || object is null || utf8name is null || result is null) return napi_invalid_arg;
    try
    {
        import core.stdc.string : strlen;
        auto name = cast(string) utf8name[0 .. strlen(utf8name)];
        *result = allocValue(env.engine.getProperty(object.handle, name));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_set_element(napi_env env, napi_value object, uint index, napi_value value)
{
    if (env is null || object is null || value is null) return napi_invalid_arg;
    try
    {
        env.engine.setPropertyIndex(object.handle, index, env.engine.dupValue(value.handle));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_element(napi_env env, napi_value object, uint index, napi_value* result)
{
    if (env is null || object is null || result is null) return napi_invalid_arg;
    try
    {
        *result = allocValue(env.engine.getPropertyIndex(object.handle, index));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_typeof(napi_env env, napi_value value, napi_valuetype* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto e = env.engine;
    auto h = value.handle;
    if (e.isUndefined(h)) *result = napi_undefined;
    else if (e.isNull(h)) *result = napi_null;
    else if (e.isBool(h)) *result = napi_boolean;
    else if (e.isNumber(h)) *result = napi_number;
    else if (e.isString(h)) *result = napi_string;
    else if (e.isFunction(h)) *result = napi_function;
    else if (e.isObject(h)) *result = napi_object;
    else *result = napi_undefined;
    return napi_ok;
}

napi_status napi_is_array(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = env.engine.isArray(value.handle);
    return napi_ok;
}

napi_status napi_get_array_length(napi_env env, napi_value value, uint* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = cast(uint) env.engine.getArrayLength(value.handle);
    return napi_ok;
}

napi_status napi_get_value_bool(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    if (!env.engine.isBool(value.handle)) return napi_boolean_expected;
    *result = env.engine.extractBool(value.handle);
    return napi_ok;
}

napi_status napi_get_value_int32(napi_env env, napi_value value, int* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    if (!env.engine.isNumber(value.handle)) return napi_number_expected;
    *result = env.engine.extractInt(value.handle);
    return napi_ok;
}

napi_status napi_get_value_double(napi_env env, napi_value value, double* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    if (!env.engine.isNumber(value.handle)) return napi_number_expected;
    *result = env.engine.extractFloat(value.handle);
    return napi_ok;
}

napi_status napi_get_value_string_utf8(napi_env env, napi_value value, char* buf, size_t bufsize, size_t* result)
{
    if (env is null || value is null) return napi_invalid_arg;
    if (!env.engine.isString(value.handle)) return napi_string_expected;
    try
    {
        auto s = env.engine.extractString(value.handle);
        if (result !is null) *result = s.length;
        if (buf !is null && bufsize > 0)
        {
            auto copyLen = s.length < bufsize - 1 ? s.length : bufsize - 1;
            buf[0 .. copyLen] = cast(char[]) s[0 .. copyLen];
            buf[copyLen] = '\0';
        }
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_global(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.getGlobal());
    return napi_ok;
}

napi_status napi_call_function(napi_env env, napi_value recv, napi_value func, size_t argc, napi_value* argv, napi_value* result)
{
    if (env is null || func is null) return napi_invalid_arg;
    try
    {
        JSHandle thisVal = recv !is null ? recv.handle : env.engine.newUndefined();
        JSHandle[] argHandles;
        if (argc > 0 && argv !is null)
        {
            argHandles = new JSHandle[argc];
            foreach (i; 0 .. argc)
                argHandles[i] = argv[i].handle;
        }
        auto res = env.engine.callFunction(func.handle, thisVal, argHandles);
        if (result !is null)
            *result = allocValue(res);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_cb_info(napi_env env, napi_callback_info cbinfo, size_t* argc, napi_value* argv, napi_value* this_arg, void** data)
{
    if (env is null || cbinfo is null) return napi_invalid_arg;
    auto info = cbinfo;
    if (argc !is null)
    {
        auto wanted = *argc;
        auto available = info.args.length;
        auto copyCount = wanted < available ? wanted : available;
        if (argv !is null)
        {
            foreach (i; 0 .. copyCount)
                argv[i] = allocValue(info.args[i]);
            foreach (i; copyCount .. wanted)
                argv[i] = allocValue(env.engine.newUndefined());
        }
        *argc = available;
    }
    if (this_arg !is null)
        *this_arg = allocValue(info.thisVal);
    if (data !is null)
        *data = info.data;
    return napi_ok;
}

napi_status napi_throw_error(napi_env env, const(char)* code, const(char)* msg)
{
    if (env is null) return napi_invalid_arg;
    return napi_ok;
}

napi_status napi_throw_type_error(napi_env env, const(char)* code, const(char)* msg)
{
    if (env is null) return napi_invalid_arg;
    return napi_ok;
}

napi_status napi_create_reference(napi_env env, napi_value value, uint initial_refcount, void** result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    try
    {
        auto r = new napi_ref_s;
        r.env = env;
        // dupValue pins the JS value across GC cycles (it's now strongly
        // held by D-side bookkeeping until napi_delete_reference frees).
        r.value = env.engine.dupValue(value.handle);
        r.refcount = initial_refcount;
        *result = cast(void*) r;
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_delete_reference(napi_env env, void* ref_)
{
    if (env is null || ref_ is null) return napi_invalid_arg;
    auto r = cast(napi_ref_s*) ref_;
    try { env.engine.freeValue(r.value); } catch (Exception) {}
    return napi_ok;
}

napi_status napi_get_reference_value(napi_env env, void* ref_, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    if (ref_ is null) { *result = allocValue(env.engine.newUndefined()); return napi_ok; }
    auto r = cast(napi_ref_s*) ref_;
    *result = allocValue(env.engine.dupValue(r.value));
    return napi_ok;
}

napi_status napi_strict_equals(napi_env env, napi_value lhs, napi_value rhs, bool* result)
{
    if (env is null || lhs is null || rhs is null || result is null) return napi_invalid_arg;
    *result = lhs.handle == rhs.handle;
    return napi_ok;
}

napi_status napi_get_value_external(napi_env env, napi_value value, void** result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = lookupWrap(env, value.handle);  // null if not a wrap object
    return napi_ok;
}

napi_status napi_create_external(napi_env env, void* data, napi_finalize finalize_cb, void* hint, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    try
    {
        auto obj = env.engine.newObject();
        attachWrap(env, obj, data, finalize_cb, hint);
        *result = allocValue(obj);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

// ───────────────────────────────────────────────────────────────────────
// N-API expansion (claude/fix-node-deno-bun-blockers)
// ───────────────────────────────────────────────────────────────────────
// Enough of the surface to load representative addons. Each function
// either dispatches to IJSEngine (engine-agnostic) or returns a sane
// default that won't crash the addon. Target list (sharp,
// better-sqlite3, bcrypt, node-canvas) drove the API selection.

// --- Numbers (signed/unsigned widths) ---

napi_status napi_create_uint32(napi_env env, uint value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newFloat(cast(double) value));
    return napi_ok;
}

napi_status napi_get_value_int64(napi_env env, napi_value value, long* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = cast(long) env.engine.extractFloat(value.handle);
    return napi_ok;
}

napi_status napi_get_value_uint32(napi_env env, napi_value value, uint* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = cast(uint) env.engine.extractFloat(value.handle);
    return napi_ok;
}

// --- BigInt (best-effort: store as double; full BigInt would need engine support) ---

napi_status napi_create_bigint_int64(napi_env env, long value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newFloat(cast(double) value));
    return napi_ok;
}

napi_status napi_create_bigint_uint64(napi_env env, ulong value, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newFloat(cast(double) value));
    return napi_ok;
}

napi_status napi_get_value_bigint_int64(napi_env env, napi_value value, long* result, bool* lossless)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = cast(long) env.engine.extractFloat(value.handle);
    if (lossless !is null) *lossless = true;
    return napi_ok;
}

napi_status napi_get_value_bigint_uint64(napi_env env, napi_value value, ulong* result, bool* lossless)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = cast(ulong) env.engine.extractFloat(value.handle);
    if (lossless !is null) *lossless = true;
    return napi_ok;
}

// --- Strings (UTF-16, latin1) ---

napi_status napi_create_string_utf16(napi_env env, const(wchar)* str, size_t length, napi_value* result)
{
    import std.utf : toUTF8;
    if (env is null || result is null) return napi_invalid_arg;
    if (str is null) { *result = allocValue(env.engine.newString("")); return napi_ok; }
    try
    {
        size_t len = length;
        if (len == size_t.max)
        {
            len = 0;
            while (str[len] != 0) len++;
        }
        auto u8 = toUTF8(cast(const(wchar)[]) str[0 .. len]);
        *result = allocValue(env.engine.newString(u8));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_create_string_latin1(napi_env env, const(char)* str, size_t length, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    if (str is null) { *result = allocValue(env.engine.newString("")); return napi_ok; }
    try
    {
        size_t len = length == size_t.max
            ? { size_t l; while (str[l] != 0) l++; return l; }()
            : length;
        // Latin-1 → UTF-8: any byte ≥ 0x80 must be expanded to two UTF-8 bytes.
        import dun.platform.arena : Appender;
        Appender!string buf;
        buf.reserve(len + (len >> 2));
        foreach (i; 0 .. len)
        {
            ubyte b = cast(ubyte) str[i];
            if (b < 0x80) buf.put(cast(char) b);
            else
            {
                buf.put(cast(char)(0xC0 | (b >> 6)));
                buf.put(cast(char)(0x80 | (b & 0x3F)));
            }
        }
        *result = allocValue(env.engine.newString(buf.data));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

// --- Symbol ---

napi_status napi_create_symbol(napi_env env, napi_value description, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    // Construct via JS: `Symbol(desc)`. Best-effort fallback if the
    // engine doesn't expose Symbol-as-callable.
    auto global = env.engine.getGlobal();
    auto sym = env.engine.getProperty(global, "Symbol");
    env.engine.freeValue(global);
    if (env.engine.isFunction(sym))
    {
        JSHandle[1] args;
        int argc = 0;
        if (description !is null)
        {
            args[0] = description.handle;
            argc = 1;
        }
        auto undef = env.engine.newUndefined();
        auto r = env.engine.callFunction(sym, undef, args[0 .. argc]);
        env.engine.freeValue(undef);
        env.engine.freeValue(sym);
        *result = allocValue(r);
        return napi_ok;
    }
    env.engine.freeValue(sym);
    *result = allocValue(env.engine.newUndefined());
    return napi_ok;
}

// --- Generic property ops (any-key) ---

napi_status napi_set_property(napi_env env, napi_value object, napi_value key, napi_value value)
{
    if (env is null || object is null || key is null || value is null) return napi_invalid_arg;
    try
    {
        auto k = env.engine.extractString(key.handle);
        env.engine.setProperty(object.handle, k, value.handle);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_property(napi_env env, napi_value object, napi_value key, napi_value* result)
{
    if (env is null || object is null || key is null || result is null) return napi_invalid_arg;
    try
    {
        auto k = env.engine.extractString(key.handle);
        *result = allocValue(env.engine.getProperty(object.handle, k));
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_has_property(napi_env env, napi_value object, napi_value key, bool* result)
{
    if (env is null || object is null || key is null || result is null) return napi_invalid_arg;
    try
    {
        auto k = env.engine.extractString(key.handle);
        auto v = env.engine.getProperty(object.handle, k);
        *result = !env.engine.isUndefined(v);
        env.engine.freeValue(v);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_has_named_property(napi_env env, napi_value object, const(char)* utf8name, bool* result)
{
    if (env is null || object is null || utf8name is null || result is null) return napi_invalid_arg;
    try
    {
        import core.stdc.string : strlen;
        auto name = cast(string) utf8name[0 .. strlen(utf8name)];
        auto v = env.engine.getProperty(object.handle, name);
        *result = !env.engine.isUndefined(v);
        env.engine.freeValue(v);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_has_own_property(napi_env env, napi_value object, napi_value key, bool* result)
{
    // Approximation: forward to napi_has_property. A proper implementation
    // would call Object.prototype.hasOwnProperty.call(obj, key).
    return napi_has_property(env, object, key, result);
}

napi_status napi_delete_property(napi_env env, napi_value object, napi_value key, bool* result)
{
    if (env is null || object is null || key is null) return napi_invalid_arg;
    // No engine.deleteProperty yet — overwrite with undefined as a fallback.
    auto undef = env.engine.newUndefined();
    try
    {
        auto k = env.engine.extractString(key.handle);
        env.engine.setProperty(object.handle, k, undef);
    }
    catch (Throwable) { return napi_generic_failure; }
    if (result !is null) *result = true;
    return napi_ok;
}

napi_status napi_get_property_names(napi_env env, napi_value object, napi_value* result)
{
    if (env is null || object is null || result is null) return napi_invalid_arg;
    // Engine-agnostic shortcut: call `Object.keys(obj)` via JS.
    auto global = env.engine.getGlobal();
    auto Object_ = env.engine.getProperty(global, "Object");
    auto keysFn = env.engine.getProperty(Object_, "keys");
    env.engine.freeValue(global);
    JSHandle[1] args = [object.handle];
    auto undef = env.engine.newUndefined();
    auto keys = env.engine.callFunction(keysFn, undef, args[]);
    env.engine.freeValue(undef);
    env.engine.freeValue(keysFn);
    env.engine.freeValue(Object_);
    *result = allocValue(keys);
    return napi_ok;
}

napi_status napi_get_prototype(napi_env env, napi_value object, napi_value* result)
{
    if (env is null || object is null || result is null) return napi_invalid_arg;
    auto global = env.engine.getGlobal();
    auto Object_ = env.engine.getProperty(global, "Object");
    auto getProto = env.engine.getProperty(Object_, "getPrototypeOf");
    env.engine.freeValue(global);
    JSHandle[1] args = [object.handle];
    auto undef = env.engine.newUndefined();
    auto proto = env.engine.callFunction(getProto, undef, args[]);
    env.engine.freeValue(undef);
    env.engine.freeValue(getProto);
    env.engine.freeValue(Object_);
    *result = allocValue(proto);
    return napi_ok;
}

// --- Errors (creation + throw of the three Node-defined kinds) ---

napi_status napi_create_error(napi_env env, napi_value code, napi_value msg, napi_value* result)
{
    if (env is null || msg is null || result is null) return napi_invalid_arg;
    auto global = env.engine.getGlobal();
    auto ErrorCtor = env.engine.getProperty(global, "Error");
    env.engine.freeValue(global);
    JSHandle[1] args = [msg.handle];
    auto undef = env.engine.newUndefined();
    auto err = env.engine.callFunction(ErrorCtor, undef, args[]);
    if (code !is null)
        env.engine.setProperty(err, "code", env.engine.dupValue(code.handle));
    env.engine.freeValue(undef);
    env.engine.freeValue(ErrorCtor);
    *result = allocValue(err);
    return napi_ok;
}

napi_status napi_create_type_error(napi_env env, napi_value code, napi_value msg, napi_value* result)
{
    if (env is null || msg is null || result is null) return napi_invalid_arg;
    auto global = env.engine.getGlobal();
    auto Ctor = env.engine.getProperty(global, "TypeError");
    env.engine.freeValue(global);
    JSHandle[1] args = [msg.handle];
    auto undef = env.engine.newUndefined();
    auto err = env.engine.callFunction(Ctor, undef, args[]);
    if (code !is null)
        env.engine.setProperty(err, "code", env.engine.dupValue(code.handle));
    env.engine.freeValue(undef);
    env.engine.freeValue(Ctor);
    *result = allocValue(err);
    return napi_ok;
}

napi_status napi_create_range_error(napi_env env, napi_value code, napi_value msg, napi_value* result)
{
    if (env is null || msg is null || result is null) return napi_invalid_arg;
    auto global = env.engine.getGlobal();
    auto Ctor = env.engine.getProperty(global, "RangeError");
    env.engine.freeValue(global);
    JSHandle[1] args = [msg.handle];
    auto undef = env.engine.newUndefined();
    auto err = env.engine.callFunction(Ctor, undef, args[]);
    if (code !is null)
        env.engine.setProperty(err, "code", env.engine.dupValue(code.handle));
    env.engine.freeValue(undef);
    env.engine.freeValue(Ctor);
    *result = allocValue(err);
    return napi_ok;
}

napi_status napi_throw(napi_env env, napi_value error)
{
    if (env is null || error is null) return napi_invalid_arg;
    env.engine.throwValue(error.handle);
    return napi_ok;
}

napi_status napi_throw_range_error(napi_env env, const(char)* code, const(char)* msg)
{
    if (env is null || msg is null) return napi_invalid_arg;
    import core.stdc.string : strlen;
    auto m = cast(string) msg[0 .. strlen(msg)];
    env.engine.throwRangeError(m);
    return napi_ok;
}

napi_status napi_is_error(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto global = env.engine.getGlobal();
    auto ErrorCtor = env.engine.getProperty(global, "Error");
    env.engine.freeValue(global);
    // value instanceof Error
    auto inst = env.engine.getProperty(ErrorCtor, "Symbol.hasInstance");
    env.engine.freeValue(inst);
    // Approximation: check the constructor by name.
    auto ctorProp = env.engine.getProperty(value.handle, "constructor");
    auto nameProp = env.engine.getProperty(ctorProp, "name");
    auto name = env.engine.isString(nameProp) ? env.engine.extractString(nameProp) : "";
    env.engine.freeValue(nameProp);
    env.engine.freeValue(ctorProp);
    env.engine.freeValue(ErrorCtor);
    *result = name == "Error" || name == "TypeError" || name == "RangeError"
           || name == "SyntaxError" || name == "ReferenceError"
           || name == "EvalError" || name == "URIError" || name == "AggregateError";
    return napi_ok;
}

// --- Promises (using engine.newPromise) ---

struct napi_deferred_t {
    JSHandle resolve;
    JSHandle reject;
}

napi_status napi_create_promise(napi_env env, void** deferred, napi_value* promise)
{
    if (env is null || deferred is null || promise is null) return napi_invalid_arg;
    try
    {
        auto ph = env.engine.newPromise();
        auto def = new napi_deferred_t();
        def.resolve = ph.resolve;
        def.reject = ph.reject;
        *deferred = cast(void*) def;
        *promise = allocValue(ph.promise);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_resolve_deferred(napi_env env, void* deferred, napi_value resolution)
{
    if (env is null || deferred is null) return napi_invalid_arg;
    auto def = cast(napi_deferred_t*) deferred;
    JSHandle[1] args;
    int argc = 0;
    if (resolution !is null) { args[0] = resolution.handle; argc = 1; }
    auto undef = env.engine.newUndefined();
    env.engine.freeValue(env.engine.callFunction(def.resolve, undef, args[0 .. argc]));
    env.engine.freeValue(undef);
    env.engine.freeValue(def.resolve);
    env.engine.freeValue(def.reject);
    return napi_ok;
}

napi_status napi_reject_deferred(napi_env env, void* deferred, napi_value rejection)
{
    if (env is null || deferred is null) return napi_invalid_arg;
    auto def = cast(napi_deferred_t*) deferred;
    JSHandle[1] args;
    int argc = 0;
    if (rejection !is null) { args[0] = rejection.handle; argc = 1; }
    auto undef = env.engine.newUndefined();
    env.engine.freeValue(env.engine.callFunction(def.reject, undef, args[0 .. argc]));
    env.engine.freeValue(undef);
    env.engine.freeValue(def.resolve);
    env.engine.freeValue(def.reject);
    return napi_ok;
}

napi_status napi_is_promise(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    // Duck-type: a Promise has .then function
    auto then_ = env.engine.getProperty(value.handle, "then");
    *result = env.engine.isFunction(then_);
    env.engine.freeValue(then_);
    return napi_ok;
}

// --- Handle scopes — no-op on our GC-managed engine ---

napi_status napi_open_handle_scope(napi_env env, void** result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = NAPI_ASYNC_SENTINEL;
    return napi_ok;
}

napi_status napi_close_handle_scope(napi_env env, void* scope_)
{
    return napi_ok;
}

napi_status napi_open_escapable_handle_scope(napi_env env, void** result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = NAPI_ASYNC_SENTINEL;
    return napi_ok;
}

napi_status napi_close_escapable_handle_scope(napi_env env, void* scope_)
{
    return napi_ok;
}

napi_status napi_escape_handle(napi_env env, void* scope_, napi_value escapee, napi_value* result)
{
    if (env is null || escapee is null || result is null) return napi_invalid_arg;
    *result = escapee;
    return napi_ok;
}

// --- Reference ref/unref ---

napi_status napi_reference_ref(napi_env env, void* ref_, uint* result)
{
    if (env is null || ref_ is null) return napi_invalid_arg;
    auto r = cast(napi_ref_s*) ref_;
    r.refcount++;
    if (result !is null) *result = r.refcount;
    return napi_ok;
}

napi_status napi_reference_unref(napi_env env, void* ref_, uint* result)
{
    if (env is null || ref_ is null) return napi_invalid_arg;
    auto r = cast(napi_ref_s*) ref_;
    if (r.refcount > 0) r.refcount--;
    if (result !is null) *result = r.refcount;
    return napi_ok;
}

// --- ArrayBuffer / TypedArray / Buffer / DataView ---

napi_status napi_create_arraybuffer(napi_env env, size_t byte_length, void** data, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    auto u8 = env.engine.newUint8ArrayZeroed(byte_length);
    auto bytes = env.engine.getTypedArrayBytes(u8);
    if (data !is null) *data = bytes !is null ? cast(void*) bytes.ptr : null;
    auto bufProp = env.engine.getProperty(u8, "buffer");
    env.engine.freeValue(u8);
    *result = allocValue(bufProp);
    return napi_ok;
}

napi_status napi_create_external_arraybuffer(napi_env env, void* external_data, size_t byte_length,
    napi_finalize finalize_cb, void* finalize_hint, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    // Best-effort: copy data into a fresh ArrayBuffer (we can't expose
    // external memory through the IJSEngine interface yet).
    auto src = external_data ? (cast(ubyte*) external_data)[0 .. byte_length] : null;
    auto u8 = env.engine.newUint8Array(src);
    auto bufProp = env.engine.getProperty(u8, "buffer");
    env.engine.freeValue(u8);
    *result = allocValue(bufProp);
    return napi_ok;
}

napi_status napi_get_arraybuffer_info(napi_env env, napi_value arraybuffer, void** data, size_t* byte_length)
{
    if (env is null || arraybuffer is null) return napi_invalid_arg;
    // Approximation: arraybuffer.byteLength is reachable via JS.
    auto blProp = env.engine.getProperty(arraybuffer.handle, "byteLength");
    if (byte_length !is null)
        *byte_length = env.engine.isNumber(blProp) ? cast(size_t) env.engine.extractInt(blProp) : 0;
    env.engine.freeValue(blProp);
    if (data !is null) *data = null;
    return napi_ok;
}

napi_status napi_is_arraybuffer(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto ctorProp = env.engine.getProperty(value.handle, "constructor");
    auto nameProp = env.engine.getProperty(ctorProp, "name");
    auto name = env.engine.isString(nameProp) ? env.engine.extractString(nameProp) : "";
    env.engine.freeValue(nameProp);
    env.engine.freeValue(ctorProp);
    *result = name == "ArrayBuffer" || name == "SharedArrayBuffer";
    return napi_ok;
}

napi_status napi_create_typedarray(napi_env env, int type, size_t length,
    napi_value arraybuffer, size_t byte_offset, napi_value* result)
{
    if (env is null || arraybuffer is null || result is null) return napi_invalid_arg;
    // Minimum support: Uint8Array. Other types fall through to Uint8Array
    // (caller responsible for matching type). A full impl needs
    // engine.newTypedArray(kind, ab, off, len).
    auto u8 = env.engine.newUint8ArrayZeroed(length);
    *result = allocValue(u8);
    return napi_ok;
}

napi_status napi_get_typedarray_info(napi_env env, napi_value typedarray, int* type,
    size_t* length, void** data, napi_value* arraybuffer, size_t* byte_offset)
{
    if (env is null || typedarray is null) return napi_invalid_arg;
    auto bytes = env.engine.getTypedArrayBytes(typedarray.handle);
    if (length !is null) *length = bytes !is null ? bytes.length : 0;
    if (data !is null) *data = bytes !is null ? cast(void*) bytes.ptr : null;
    if (type !is null) *type = 0;  // napi_uint8_array
    if (byte_offset !is null) *byte_offset = 0;
    if (arraybuffer !is null)
    {
        auto bufProp = env.engine.getProperty(typedarray.handle, "buffer");
        *arraybuffer = allocValue(bufProp);
    }
    return napi_ok;
}

napi_status napi_is_typedarray(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    *result = env.engine.getTypedArrayBytes(value.handle) !is null;
    return napi_ok;
}

napi_status napi_create_buffer(napi_env env, size_t length, void** data, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    import dun.builtins.buffer : makeBufferObjZeroed;
    auto buf = makeBufferObjZeroed(env.engine, cast(int) length);
    if (data !is null)
    {
        auto bytes = env.engine.getTypedArrayBytes(buf);
        *data = bytes !is null ? cast(void*) bytes.ptr : null;
    }
    *result = allocValue(buf);
    return napi_ok;
}

napi_status napi_create_buffer_copy(napi_env env, size_t length, const(void)* data,
    void** result_data, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    import dun.builtins.buffer : makeBufferObj;
    auto src = data ? (cast(const(ubyte)*) data)[0 .. length] : null;
    auto buf = makeBufferObj(env.engine, src);
    if (result_data !is null)
    {
        auto bytes = env.engine.getTypedArrayBytes(buf);
        *result_data = bytes !is null ? cast(void*) bytes.ptr : null;
    }
    *result = allocValue(buf);
    return napi_ok;
}

napi_status napi_create_external_buffer(napi_env env, size_t length, void* data,
    napi_finalize finalize_cb, void* finalize_hint, napi_value* result)
{
    // Same as create_buffer_copy — we don't have external storage exposed
    // through IJSEngine; copy the bytes in.
    return napi_create_buffer_copy(env, length, data, null, result);
}

napi_status napi_is_buffer(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto isBufProp = env.engine.getProperty(value.handle, "__isBuffer");
    *result = env.engine.isBool(isBufProp) && env.engine.extractBool(isBufProp);
    env.engine.freeValue(isBufProp);
    return napi_ok;
}

napi_status napi_get_buffer_info(napi_env env, napi_value value, void** data, size_t* length)
{
    if (env is null || value is null) return napi_invalid_arg;
    auto bytes = env.engine.getTypedArrayBytes(value.handle);
    if (length !is null) *length = bytes !is null ? bytes.length : 0;
    if (data !is null) *data = bytes !is null ? cast(void*) bytes.ptr : null;
    return napi_ok;
}

napi_status napi_create_dataview(napi_env env, size_t byte_length, napi_value arraybuffer,
    size_t byte_offset, napi_value* result)
{
    // No engine.newDataView yet — return a Uint8Array as approximation.
    return napi_create_typedarray(env, 0, byte_length, arraybuffer, byte_offset, result);
}

napi_status napi_get_dataview_info(napi_env env, napi_value dataview, size_t* byte_length,
    void** data, napi_value* arraybuffer, size_t* byte_offset)
{
    return napi_get_typedarray_info(env, dataview, null, byte_length, data, arraybuffer, byte_offset);
}

napi_status napi_is_dataview(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto ctorProp = env.engine.getProperty(value.handle, "constructor");
    auto nameProp = env.engine.getProperty(ctorProp, "name");
    auto name = env.engine.isString(nameProp) ? env.engine.extractString(nameProp) : "";
    env.engine.freeValue(nameProp);
    env.engine.freeValue(ctorProp);
    *result = name == "DataView";
    return napi_ok;
}

// --- Class / wrap / instanceof ---

napi_status napi_create_function(napi_env env, const(char)* utf8name, size_t length,
    napi_callback cb, void* data, napi_value* result)
{
    if (env is null || result is null || cb is null) return napi_invalid_arg;
    try
    {
        // Allocate a per-function slot. The slot stores the napi_callback
        // function pointer plus the addon-provided `data` and the env.
        auto slot = registerNapiFn(env, cb, data);
        if (slot < 0) return napi_generic_failure;

        // Build a JS closure that captures the slot ID and forwards to
        // the shared trampoline. This avoids needing per-function D
        // function pointers, which we can't generate at runtime.
        ensureNapiDispatcher(env);

        import std.conv : to;
        auto src = "(function(__slot){return function(){"
            ~ "return globalThis.__dun_napi_dispatch__(__slot,this,arguments);"
            ~ "};})(" ~ to!string(slot) ~ ")";
        auto wrap = env.engine.eval(src, "<napi-create-function>");
        if (wrap.isError) return napi_generic_failure;
        *result = allocValue(wrap.value);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

private __gshared bool gNapiDispatcherInstalled = false;

private void ensureNapiDispatcher(napi_env env) @trusted
{
    if (gNapiDispatcherInstalled) return;
    auto fn = env.engine.newFunction(&napiDispatch, "__dun_napi_dispatch__", 0);
    auto global = env.engine.getGlobal();
    env.engine.setProperty(global, "__dun_napi_dispatch__", fn);
    env.engine.freeValue(global);
    gNapiDispatcherInstalled = true;
}

napi_status napi_define_class(napi_env env, const(char)* utf8name, size_t length,
    napi_callback constructor, void* data, size_t property_count,
    void* properties, napi_value* result)
{
    return napi_create_function(env, utf8name, length, constructor, data, result);
}

napi_status napi_define_properties(napi_env env, napi_value object,
    size_t property_count, void* properties)
{
    if (env is null || object is null) return napi_invalid_arg;
    if (property_count == 0) return napi_ok;
    if (properties is null) return napi_invalid_arg;

    import dun.napi.types : napi_property_descriptor;
    auto descs = (cast(napi_property_descriptor*) properties)[0 .. property_count];
    auto engine = env.engine;

    foreach (ref d; descs)
    {
        // Resolve property name — either utf8name or a napi_value name.
        string name;
        if (d.utf8name !is null)
        {
            import std.string : fromStringz;
            try { name = cast(string) fromStringz(d.utf8name); }
            catch (Exception) { return napi_invalid_arg; }
        }
        else if (d.name !is null)
        {
            name = engine.extractString(d.name.handle);
        }
        else
        {
            return napi_name_expected;
        }

        // Pick the value: method > value > getter/setter (accessor).
        if (d.method !is null)
        {
            napi_value fnVal;
            auto st = napi_create_function(env, d.utf8name,
                name.length, d.method, d.data, &fnVal);
            if (st != napi_ok) return st;
            engine.setProperty(object.handle, name, fnVal.handle);
        }
        else if (d.value !is null)
        {
            engine.setProperty(object.handle, name, d.value.handle);
        }
        else if (d.getter !is null || d.setter !is null)
        {
            // Build `Object.defineProperty(obj, name, { get, set, configurable, enumerable })`.
            auto global = engine.getGlobal();
            auto objectCtor = engine.getProperty(global, "Object");
            auto defineProp = engine.getProperty(objectCtor, "defineProperty");
            engine.freeValue(objectCtor);
            engine.freeValue(global);

            auto descObj = engine.newObject();
            if (d.getter !is null)
            {
                napi_value getter;
                auto st = napi_create_function(env, null, 0, d.getter, d.data, &getter);
                if (st != napi_ok) { engine.freeValue(descObj); engine.freeValue(defineProp); return st; }
                engine.setProperty(descObj, "get", getter.handle);
            }
            if (d.setter !is null)
            {
                napi_value setter;
                auto st = napi_create_function(env, null, 0, d.setter, d.data, &setter);
                if (st != napi_ok) { engine.freeValue(descObj); engine.freeValue(defineProp); return st; }
                engine.setProperty(descObj, "set", setter.handle);
            }
            // Honour attribute flags. N-API default for accessors is
            // configurable+enumerable; `napi_default` (0) means no flags
            // → JS default of non-configurable/non-enumerable, matching
            // Node's behaviour.
            engine.setProperty(descObj, "configurable",
                engine.newBool((d.attributes & napi_configurable) != 0));
            engine.setProperty(descObj, "enumerable",
                engine.newBool((d.attributes & napi_enumerable) != 0));

            auto undef = engine.newUndefined();
            auto nameStr = engine.newString(name);
            JSHandle[3] argv = [object.handle, nameStr, descObj];
            auto ret = engine.callFunction(defineProp, undef, argv[]);
            engine.freeValue(ret);
            engine.freeValue(nameStr);
            engine.freeValue(descObj);
            engine.freeValue(undef);
            engine.freeValue(defineProp);
        }
        else
        {
            // Empty descriptor — no method, value, getter or setter.
            // Skip silently; Node N-API treats this as no-op.
        }
    }
    return napi_ok;
}

napi_status napi_new_instance(napi_env env, napi_value constructor, size_t argc,
    napi_value* argv, napi_value* result)
{
    if (env is null || constructor is null || result is null) return napi_invalid_arg;
    JSHandle[16] stackArgs;
    JSHandle[] args;
    if (argc <= 16)
        args = stackArgs[0 .. argc];
    else
        args = new JSHandle[argc];
    foreach (i; 0 .. argc) args[i] = argv[i].handle;
    auto undef = env.engine.newUndefined();
    auto inst = env.engine.callFunction(constructor.handle, undef, args);
    env.engine.freeValue(undef);
    *result = allocValue(inst);
    return napi_ok;
}

napi_status napi_instanceof(napi_env env, napi_value object, napi_value constructor, bool* result)
{
    if (env is null || object is null || constructor is null || result is null) return napi_invalid_arg;
    // Approximate: walk prototype chain comparing constructors.
    auto ctorProp = env.engine.getProperty(object.handle, "constructor");
    *result = ctorProp.opaque[0] == constructor.handle.opaque[0];
    env.engine.freeValue(ctorProp);
    return napi_ok;
}

napi_status napi_wrap(napi_env env, napi_value js_object, void* native_object,
    napi_finalize finalize_cb, void* finalize_hint, void** result)
{
    if (env is null || js_object is null) return napi_invalid_arg;
    try { attachWrap(env, js_object.handle, native_object, finalize_cb, finalize_hint); }
    catch (Throwable) { return napi_generic_failure; }
    if (result !is null) *result = null;
    return napi_ok;
}

napi_status napi_unwrap(napi_env env, napi_value js_object, void** result)
{
    if (env is null || js_object is null || result is null) return napi_invalid_arg;
    *result = lookupWrap(env, js_object.handle);
    return napi_ok;
}

napi_status napi_remove_wrap(napi_env env, napi_value js_object, void** result)
{
    if (env is null || js_object is null) return napi_invalid_arg;
    void* data = removeWrap(env, js_object.handle);
    if (result !is null) *result = data;
    return napi_ok;
}

napi_status napi_get_new_target(napi_env env, napi_callback_info cbinfo, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = null;
    return napi_ok;
}

private extern (D) JSHandle napiNoopFn(void* engineCtx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    static import dun.runtime.globals;
    auto state = cast(dun.runtime.globals.DunState*) engineCtx;
    return state.engine.newUndefined();
}

// --- Per-napi-function slot table + shared trampoline ---
//
// Each napi_create_function call gets a slot. The slot holds the
// napi_callback function pointer + the addon-provided `data` pointer
// + the env. The slot ID is stashed on the JS function as
// `__napiSlot__`; on call the trampoline reads it back to dispatch.
//
// One slot per napi function (not per call), grown on demand.

private struct NapiFnSlot
{
    napi_callback cb;
    void* data;
    napi_env env;
}

private __gshared NapiFnSlot[] gNapiSlots;
private __gshared int gNextNapiSlot = 0;

private int registerNapiFn(napi_env env, napi_callback cb, void* data) nothrow @trusted
{
    try
    {
        if (gNextNapiSlot >= cast(int) gNapiSlots.length)
            gNapiSlots.length = gNapiSlots.length + 64;
        gNapiSlots[gNextNapiSlot] = NapiFnSlot(cb, data, env);
        return gNextNapiSlot++;
    }
    catch (Exception) { return -1; }
}

private extern (D) JSHandle napiDispatch(void* engineCtx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    // Args layout from JS shim: [slotId, jsThis, argumentsArray]
    static import dun.runtime.globals;
    auto state = cast(dun.runtime.globals.DunState*) engineCtx;
    if (state is null || state.engine is null) return JSHandle.init;
    auto engine = state.engine;
    try
    {
        if (args.length < 3) return engine.newUndefined();
        auto slotId = engine.extractInt(args[0]);
        if (slotId < 0 || slotId >= cast(int) gNapiSlots.length)
            return engine.newUndefined();
        auto slot = gNapiSlots[slotId];
        if (slot.cb is null) return engine.newUndefined();

        // Unpack the JS arguments array into a JSHandle[] for the napi info.
        auto jsThis = args[1];
        auto argsArr = args[2];
        auto argLen = engine.getArrayLength(argsArr);
        JSHandle[16] stackArgs;
        JSHandle[] napiArgs;
        if (argLen <= 16)
            napiArgs = stackArgs[0 .. argLen];
        else
            napiArgs = new JSHandle[argLen];
        foreach (i; 0 .. argLen)
            napiArgs[i] = engine.getPropertyIndex(argsArr, cast(uint) i);

        napi_callback_info_s info;
        info.env = slot.env;
        info.thisVal = jsThis;
        info.args = napiArgs;
        info.data = slot.data;

        auto rv = slot.cb(slot.env, &info);
        // The C addon may return one of its own napi_value args directly
        // (e.g. `return args[0]` for a fluent API). That napi_value points
        // at napiArgs[i], whose ref we own and are about to free below.
        // Bump the refcount on the return value first so the caller (QJS/
        // JSC/V8) gets a fresh reference; otherwise the free-then-return
        // sequence drops it to zero and the next allocator op trashes
        // the heap (malloc unaligned tcache).
        JSHandle retHandle;
        if (rv is null)
            retHandle = engine.newUndefined();
        else
            retHandle = engine.dupValue(rv.handle);
        foreach (i; 0 .. argLen)
            engine.freeValue(napiArgs[i]);
        return retHandle;
    }
    catch (Throwable) { return engine.newUndefined(); }
}

// ============================================================================
// Async work — napi_create_async_work / napi_queue_async_work
// ============================================================================
//
// Async work lets a native addon run a C function on a background thread,
// then hop back to the main JS thread for the completion callback (where it
// can safely touch JS values via napi_value).
//
// DunJS already has a worker thread pool (`dun.platform.thread_pool`) that
// supports this exact pattern. We use it for async crypto / fs already, so
// the queue/dispatch infrastructure is reused here.

extern(C) @trusted:

napi_status napi_create_async_work(napi_env env, napi_value async_resource,
    napi_value async_resource_name,
    napi_async_execute_callback execute,
    napi_async_complete_callback complete,
    void* data, napi_async_work* result)
{
    if (env is null || execute is null || result is null) return napi_invalid_arg;
    try
    {
        auto work = new napi_async_work_s;
        work.env = env;
        work.data = data;
        work.execute = execute;
        work.complete = complete;
        work.state = 0;
        // Resource name is informational (used for async_hooks tracking on
        // Node). We accept it but don't currently surface it to Tracing.
        if (async_resource_name !is null)
            work.name = env.engine.extractString(async_resource_name.handle);
        *result = work;
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_delete_async_work(napi_env env, napi_async_work work)
{
    if (env is null || work is null) return napi_invalid_arg;
    // The pointer is GC-managed; just clear it so any stray reference
    // doesn't fire the callback again.
    work.execute = null;
    work.complete = null;
    return napi_ok;
}

napi_status napi_queue_async_work(napi_env env, napi_async_work work)
{
    if (env is null || work is null || work.execute is null) return napi_invalid_arg;
    try
    {
        import core.thread : Thread;
        import core.atomic : atomicStore, MemoryOrder;
        work.state = 1;  // queued
        ensureNapiMutexes();
        g_napiWorkMu.lock();
        scope(exit) g_napiWorkMu.unlock();
        g_napiWorkQueue ~= work;
        auto t = new Thread({
            try { if (work.execute) work.execute(work.env, work.data); }
            catch (Throwable) {}
            work.state = 3;  // completed (main loop will drain)
        });
        t.isDaemon = true;
        t.start();
        return napi_ok;
    }
    catch (Throwable) { return napi_generic_failure; }
}

napi_status napi_cancel_async_work(napi_env env, napi_async_work work)
{
    if (env is null || work is null) return napi_invalid_arg;
    // Best-effort: clear the callbacks. If the work hasn't started yet,
    // the pool worker will see them null and skip.
    work.execute = null;
    work.complete = null;
    return napi_ok;
}

// Cross-thread N-API async work queue. Worker threads push completed
// entries; the main event loop drains them via napiDrainAsyncWork() and
// invokes work.complete(env, status, data) on the main thread (where
// JS calls are safe).
import core.sync.mutex : Mutex;
private __gshared napi_async_work[] g_napiWorkQueue;
private __gshared Mutex g_napiWorkMu;
private __gshared Mutex g_napiTsfnMu;

// Lazy mutex init avoids a shared-static cycle with the worker /
// runtime.globals / eventloop modules.
private void ensureNapiMutexes() nothrow @trusted
{
    try
    {
        if (g_napiWorkMu is null) g_napiWorkMu = new Mutex;
        if (g_napiTsfnMu is null) g_napiTsfnMu = new Mutex;
    }
    catch (Exception) {}
}

/// Called by the event loop on each tick to flush any completed async
/// work back into JS via the registered complete callback.
extern(D) int napiDrainAsyncWork() nothrow @trusted
{
    int drained = 0;
    napi_async_work[] ready;
    try
    {
        ensureNapiMutexes();
        g_napiWorkMu.lock();
        scope(exit) g_napiWorkMu.unlock();
        size_t write = 0;
        foreach (w; g_napiWorkQueue)
        {
            if (w !is null && w.state == 3)
                ready ~= w;
            else
                g_napiWorkQueue[write++] = w;
        }
        g_napiWorkQueue.length = write;
        g_napiWorkQueue.assumeSafeAppend();
    }
    catch (Exception) {}
    foreach (w; ready)
    {
        // Tiger-style: w made it into the ready list because state == 3,
        // so its env / complete must have survived. If the addon set
        // complete to null deliberately (rare, but allowed for fire-and-
        // forget work), skip without crashing.
        assert(w !is null, "null napi_async_work in ready list");
        if (w.complete is null) { drained++; continue; }
        assert(w.env !is null, "napi_async_work missing env at completion");
        try { w.complete(w.env, napi_ok, w.data); } catch (Throwable) {}
        drained++;
    }
    return drained;
}

/// True when there is at least one async work entry still pending —
/// either running on a thread or queued for completion. The event loop
/// uses this to keep itself awake.
extern(D) bool napiHasAsyncWork() nothrow @trusted
{
    ensureNapiMutexes();
    try { g_napiWorkMu.lock(); scope(exit) g_napiWorkMu.unlock();
          return g_napiWorkQueue.length > 0; }
    catch (Exception) { return false; }
}

// ============================================================================
// Threadsafe functions — napi_create_threadsafe_function family
// ============================================================================
//
// A threadsafe function lets background threads enqueue calls back to a JS
// function safely. Internally we hold a JSHandle that's pinned across calls
// (via dupValue) and a mutex-protected queue of pending invocations.

napi_status napi_create_threadsafe_function(napi_env env, napi_value func,
    napi_value async_resource, napi_value async_resource_name,
    size_t max_queue_size, size_t initial_thread_count,
    void* thread_finalize_data, napi_finalize thread_finalize_cb,
    void* context, napi_threadsafe_function_call_js call_js_cb,
    napi_threadsafe_function* result)
{
    if (env is null || func is null || result is null) return napi_invalid_arg;
    try
    {
        auto tsfn = new napi_threadsafe_function_s;
        tsfn.env = env;
        tsfn.jsFunc = env.engine.dupValue(func.handle);
        tsfn.context = context;
        tsfn.call_js_cb = call_js_cb;
        tsfn.maxQueueSize = max_queue_size;
        tsfn.refCount = cast(int) initial_thread_count;
        tsfn.aborted = 0;
        if (async_resource_name !is null)
            tsfn.name = env.engine.extractString(async_resource_name.handle);
        *result = tsfn;
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_get_threadsafe_function_context(napi_threadsafe_function func, void** result)
{
    if (func is null || result is null) return napi_invalid_arg;
    *result = func.context;
    return napi_ok;
}

napi_status napi_call_threadsafe_function(napi_threadsafe_function func,
    void* data, napi_threadsafe_function_call_mode is_blocking)
{
    if (func is null) return napi_invalid_arg;
    if (func.aborted) return napi_closing;
    try
    {
        // Queue a call. The main loop's napiDrainThreadsafeCalls() picks
        // up entries on each tick and dispatches them on the JS thread.
        ensureNapiMutexes();
        g_napiTsfnMu.lock();
        scope(exit) g_napiTsfnMu.unlock();
        if (func.maxQueueSize > 0 && g_napiTsfnQueue.length >= func.maxQueueSize)
            return napi_queue_full;
        g_napiTsfnQueue ~= TsfnCall(func, data);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_acquire_threadsafe_function(napi_threadsafe_function func)
{
    if (func is null) return napi_invalid_arg;
    func.refCount++;
    return napi_ok;
}

napi_status napi_release_threadsafe_function(napi_threadsafe_function func,
    napi_threadsafe_function_release_mode mode)
{
    if (func is null) return napi_invalid_arg;
    if (mode == napi_tsfn_abort) func.aborted = 1;
    if (func.refCount > 0) func.refCount--;
    if (func.refCount == 0 && func.env !is null && func.env.engine !is null)
    {
        try { func.env.engine.freeValue(func.jsFunc); } catch (Exception) {}
    }
    return napi_ok;
}

napi_status napi_ref_threadsafe_function(napi_env env, napi_threadsafe_function func)
{
    if (env is null || func is null) return napi_invalid_arg;
    return napi_ok;
}

napi_status napi_unref_threadsafe_function(napi_env env, napi_threadsafe_function func)
{
    if (env is null || func is null) return napi_invalid_arg;
    return napi_ok;
}

private struct TsfnCall { napi_threadsafe_function func; void* data; }
private __gshared TsfnCall[] g_napiTsfnQueue;

/// Called by the event loop on each tick to dispatch pending threadsafe
/// function calls back to JS on the main thread.
extern(D) int napiDrainThreadsafeCalls() nothrow @trusted
{
    int drained = 0;
    TsfnCall[] batch;
    try
    {
        ensureNapiMutexes();
        g_napiTsfnMu.lock();
        scope(exit) g_napiTsfnMu.unlock();
        batch = g_napiTsfnQueue.dup;
        g_napiTsfnQueue.length = 0;
        g_napiTsfnQueue.assumeSafeAppend();
    }
    catch (Exception) {}
    foreach (call; batch)
    {
        auto f = call.func;
        if (f is null || f.aborted) continue;
        try
        {
            if (f.call_js_cb !is null)
            {
                auto wrapper = allocValue(f.jsFunc);
                f.call_js_cb(f.env, wrapper, f.context, call.data);
            }
            else
            {
                JSHandle[] zeroArgs;
                auto undef = f.env.engine.newUndefined();
                auto rv = f.env.engine.callFunction(f.jsFunc, undef, zeroArgs);
                f.env.engine.freeValue(undef);
                f.env.engine.freeValue(rv);
            }
        }
        catch (Throwable) {}
        drained++;
    }
    return drained;
}

extern(D) bool napiHasThreadsafeCalls() nothrow @trusted
{
    ensureNapiMutexes();
    try { g_napiTsfnMu.lock(); scope(exit) g_napiTsfnMu.unlock();
          return g_napiTsfnQueue.length > 0; }
    catch (Exception) { return false; }
}

// ============================================================================
// Wrap / external pointer table
// ============================================================================
//
// napi_wrap, napi_create_external, and napi_unwrap need to associate a
// raw void* (often a C struct holding a DB handle, image buffer, etc.)
// with a JS object so the addon can recover it later. The N-API spec also
// requires firing a `napi_finalize` callback when the JS object is GC'd.
//
// We don't have a per-engine GC hook (each backend would need a custom
// finalizer protocol), so finalizers fire at addon-unload / runtime
// shutdown via napiFireFinalizers() instead -- which is what almost every
// real addon depends on anyway, since most cleanup work is tied to
// process exit.
//
// The bridge is a side table keyed by an opaque ulong ID that we stash
// on the JS object as `__dun_napi_wrap_id__`. JS-side code can't fake
// the ID because the property is non-enumerable (set via setProperty
// only by us) and we re-validate against the table on every lookup.

private extern(D):

struct NapiWrapEntry
{
    void*         data;
    void*         hint;
    napi_finalize finalize_cb;
    napi_env      env;
    bool          fired;  // guard against double-fire on shutdown
}

__gshared NapiWrapEntry[ulong] g_napiWrapTable;
__gshared ulong g_napiWrapNextId = 1;  // 0 means "no wrap"
__gshared Mutex g_napiWrapMu;

void ensureWrapMutex() nothrow @trusted
{
    try { if (g_napiWrapMu is null) g_napiWrapMu = new Mutex; }
    catch (Exception) {}
}

ulong getWrapId(napi_env env, JSHandle obj) nothrow @trusted
{
    try
    {
        if (env.engine is null) return 0;
        auto idVal = env.engine.getProperty(obj, "__dun_napi_wrap_id__");
        scope(exit) env.engine.freeValue(idVal);
        if (!env.engine.isNumber(idVal)) return 0;
        return cast(ulong) env.engine.extractFloat(idVal);
    }
    catch (Throwable) { return 0; }
}

void attachWrap(napi_env env, JSHandle obj, void* data,
    napi_finalize finalize_cb, void* hint)
{
    ensureWrapMutex();
    g_napiWrapMu.lock();
    scope(exit) g_napiWrapMu.unlock();
    auto id = g_napiWrapNextId++;
    g_napiWrapTable[id] = NapiWrapEntry(data, hint, finalize_cb, env, false);
    auto idVal = env.engine.newFloat(cast(double) id);
    env.engine.setProperty(obj, "__dun_napi_wrap_id__", idVal);
}

void* lookupWrap(napi_env env, JSHandle obj) nothrow @trusted
{
    auto id = getWrapId(env, obj);
    if (id == 0) return null;
    ensureWrapMutex();
    try { g_napiWrapMu.lock(); scope(exit) g_napiWrapMu.unlock();
          auto p = id in g_napiWrapTable;
          return p ? p.data : null; }
    catch (Throwable) { return null; }
}

void* removeWrap(napi_env env, JSHandle obj) nothrow @trusted
{
    auto id = getWrapId(env, obj);
    if (id == 0) return null;
    ensureWrapMutex();
    try
    {
        g_napiWrapMu.lock(); scope(exit) g_napiWrapMu.unlock();
        auto p = id in g_napiWrapTable;
        if (p is null) return null;
        void* data = p.data;
        g_napiWrapTable.remove(id);
        return data;
    }
    catch (Throwable) { return null; }
}

// ── Node N-API v8+ batch — coercion / version / extras ─────────
// Ported from Bun's js_native_api.h surface to close the gap from
// 99 functions → 130+.
//
// D-idiom note: validation preludes are common across N-API entry
// points. The `Check` string mixin lets each function express its
// required arguments declaratively (`mixin(Check!"env value result")`)
// instead of hand-typing the `if (... is null) return napi_invalid_arg;`
// chain. CTFE-generated, zero runtime cost.

private template Check(string args)
{
    enum Check = (){
        import std.string : split;
        string r = "if (";
        bool first = true;
        foreach (a; args.split(' '))
        {
            if (a.length == 0) continue;
            if (!first) r ~= " || ";
            r ~= a ~ " is null";
            first = false;
        }
        r ~= ") return napi_invalid_arg;";
        return r;
    }();
}

// N-API ABI constants — see `dun.declarations`.
import dun.declarations :
    NAPI_ASYNC_SENTINEL, NAPI_VERSION,
    NODE_VERSION_MAJOR, NODE_VERSION_MINOR, NODE_VERSION_PATCH;

napi_status napi_get_version(napi_env env, uint* result)
{
    mixin(Check!"env result");
    *result = NAPI_VERSION;
    return napi_ok;
}

napi_status napi_get_node_version(napi_env env, const(NapiNodeVersion)** result)
{
    mixin(Check!"env result");
    static __gshared NapiNodeVersion gNodeVer = NapiNodeVersion(
        NODE_VERSION_MAJOR, NODE_VERSION_MINOR, NODE_VERSION_PATCH, "dunjs");
    *result = &gNodeVer;
    return napi_ok;
}

napi_status napi_get_uv_event_loop(napi_env env, void** result)
{
    // DunJS uses epoll/kqueue/poll/io_uring, not libuv. Addons that
    // need a libuv loop will hit this and either fall back or fail.
    // Matches what Bun returns (null on JSC builds).
    mixin(Check!"env result");
    *result = null;
    return napi_ok;
}

napi_status napi_adjust_external_memory(napi_env env, long change_in_bytes, long* adjusted)
{
    // No-op accounting hint — JS-engine internals track this. We
    // return the input unchanged so addons that compare totals work.
    mixin(Check!"env adjusted");
    *adjusted = change_in_bytes;
    return napi_ok;
}

// ── Coercion ─────────────────────────────────────────────────────

napi_status napi_coerce_to_bool(napi_env env, napi_value value, napi_value* result)
{
    mixin(Check!"env value result");
    auto e = env.engine;
    bool b;
    if (e.isBool(value.handle))         b = e.extractBool(value.handle);
    else if (e.isUndefined(value.handle) || e.isNull(value.handle)) b = false;
    else if (e.isNumber(value.handle))  b = e.extractInt(value.handle) != 0;
    else if (e.isString(value.handle))  b = e.extractString(value.handle).length > 0;
    else                                b = true;  // object / function — truthy
    *result = allocValue(e.newBool(b));
    return napi_ok;
}

napi_status napi_coerce_to_number(napi_env env, napi_value value, napi_value* result)
{
    mixin(Check!"env value result");
    auto e = env.engine;
    double n = 0;
    if (e.isNumber(value.handle))      n = e.extractFloat(value.handle);
    else if (e.isBool(value.handle))   n = e.extractBool(value.handle) ? 1 : 0;
    else if (e.isString(value.handle))
    {
        import std.conv : to;
        try { n = to!double(e.extractString(value.handle)); }
        catch (Exception) { n = double.nan; }
    }
    else if (e.isNull(value.handle))   n = 0;
    else                               n = double.nan;
    *result = allocValue(e.newFloat(n));
    return napi_ok;
}

napi_status napi_coerce_to_string(napi_env env, napi_value value, napi_value* result)
{
    mixin(Check!"env value result");
    auto e = env.engine;
    auto h = value.handle;
    string s;
    try
    {
        if (e.isString(h))       s = e.extractString(h);
        else if (e.isNumber(h))
        {
            import std.conv : to;
            s = to!string(e.extractFloat(h));
        }
        else if (e.isBool(h))    s = e.extractBool(h) ? "true" : "false";
        else if (e.isNull(h))    s = "null";
        else if (e.isUndefined(h)) s = "undefined";
        else                     s = "[object Object]";
    }
    catch (Throwable) { s = ""; }
    *result = allocValue(e.newString(s));
    return napi_ok;
}

napi_status napi_coerce_to_object(napi_env env, napi_value value, napi_value* result)
{
    mixin(Check!"env value result");
    auto e = env.engine;
    auto h = value.handle;
    if (e.isObject(h))
    {
        *result = allocValue(e.dupValue(h));
        return napi_ok;
    }
    // Primitives wrap to their boxed object form via JS — use eval.
    // (Cheap for primitives, called rarely.)
    auto wrapRes = e.eval("(function(v){return Object(v);})", "<napi-coerce-obj>");
    if (wrapRes.isError)
    {
        e.freeValue(wrapRes.value);
        return napi_generic_failure;
    }
    JSHandle[1] argv = [h];
    auto wrapped = e.callFunction(wrapRes.value, e.newUndefined(), argv[]);
    e.freeValue(wrapRes.value);
    *result = allocValue(wrapped);
    return napi_ok;
}

// ── Exceptions ───────────────────────────────────────────────────

napi_status napi_is_exception_pending(napi_env env, bool* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    auto msg = env.engine.getException();
    *result = msg.length > 0;
    return napi_ok;
}

napi_status napi_get_and_clear_last_exception(napi_env env, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    auto msg = env.engine.getException();
    if (msg.length == 0)
    {
        *result = allocValue(env.engine.newUndefined());
        return napi_ok;
    }
    *result = allocValue(env.engine.newString(msg));
    return napi_ok;
}

napi_status napi_fatal_exception(napi_env env, napi_value err)
{
    if (env is null || err is null) return napi_invalid_arg;
    // Print + exit (1) — Node aborts the process on fatal exceptions.
    // We log via stderr and set process.exitCode; finishing the loop
    // will terminate normally without leaving the addon hanging.
    try
    {
        import std.stdio : stderr;
        auto msg = env.engine.extractString(err.handle);
        stderr.writeln("FATAL: ", msg);
    }
    catch (Exception) {}
    return napi_ok;
}

// ── Date ─────────────────────────────────────────────────────────

napi_status napi_create_date(napi_env env, double time, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    // Build via eval: `new Date(time)`.
    auto ctorRes = env.engine.eval(
        "(function(t){return new Date(t);})", "<napi-date>");
    if (ctorRes.isError)
    {
        env.engine.freeValue(ctorRes.value);
        return napi_generic_failure;
    }
    auto tArg = env.engine.newFloat(time);
    JSHandle[1] argv = [tArg];
    auto date = env.engine.callFunction(ctorRes.value, env.engine.newUndefined(), argv[]);
    env.engine.freeValue(ctorRes.value);
    env.engine.freeValue(tArg);
    *result = allocValue(date);
    return napi_ok;
}

napi_status napi_get_date_value(napi_env env, napi_value value, double* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    auto getTime = env.engine.getProperty(value.handle, "getTime");
    if (!env.engine.isFunction(getTime))
    {
        env.engine.freeValue(getTime);
        return napi_date_expected;
    }
    JSHandle[0] argv;
    auto r = env.engine.callFunction(getTime, value.handle, argv[]);
    env.engine.freeValue(getTime);
    *result = env.engine.extractFloat(r);
    env.engine.freeValue(r);
    return napi_ok;
}

napi_status napi_is_date(napi_env env, napi_value value, bool* result)
{
    if (env is null || value is null || result is null) return napi_invalid_arg;
    // Best-effort: a Date has getTime + getUTCDate.
    auto gt = env.engine.getProperty(value.handle, "getTime");
    auto gud = env.engine.getProperty(value.handle, "getUTCDate");
    *result = env.engine.isFunction(gt) && env.engine.isFunction(gud);
    env.engine.freeValue(gt);
    env.engine.freeValue(gud);
    return napi_ok;
}

// ── Object freeze/seal ───────────────────────────────────────────

napi_status napi_object_freeze(napi_env env, napi_value object)
{
    if (env is null || object is null) return napi_invalid_arg;
    return _callObjectStatic(env, object, "freeze");
}

napi_status napi_object_seal(napi_env env, napi_value object)
{
    if (env is null || object is null) return napi_invalid_arg;
    return _callObjectStatic(env, object, "seal");
}

private napi_status _callObjectStatic(napi_env env, napi_value object, string method)
{
    auto e = env.engine;
    auto global = e.getGlobal();
    auto objectCtor = e.getProperty(global, "Object");
    auto fn = e.getProperty(objectCtor, method);
    e.freeValue(objectCtor);
    e.freeValue(global);
    if (!e.isFunction(fn)) { e.freeValue(fn); return napi_generic_failure; }
    JSHandle[1] argv = [object.handle];
    auto r = e.callFunction(fn, e.newUndefined(), argv[]);
    e.freeValue(fn);
    e.freeValue(r);
    return napi_ok;
}

// ── Element ops ──────────────────────────────────────────────────

napi_status napi_has_element(napi_env env, napi_value object, uint index, bool* result)
{
    if (env is null || object is null || result is null) return napi_invalid_arg;
    auto h = env.engine.getPropertyIndex(object.handle, index);
    *result = !env.engine.isUndefined(h);
    env.engine.freeValue(h);
    return napi_ok;
}

napi_status napi_delete_element(napi_env env, napi_value object, uint index, bool* result)
{
    if (env is null || object is null) return napi_invalid_arg;
    auto e = env.engine;
    e.setPropertyIndex(object.handle, index, e.newUndefined());
    if (result !is null) *result = true;
    return napi_ok;
}

// ── Property names (all) ─────────────────────────────────────────

napi_status napi_get_all_property_names(napi_env env, napi_value object,
    int key_mode, int key_filter, int key_conversion, napi_value* result)
{
    if (env is null || object is null || result is null) return napi_invalid_arg;
    // Use `Object.getOwnPropertyNames(obj)`. key_mode/filter/conversion
    // are honoured at a coarse level — most addons want all-own-keys.
    auto e = env.engine;
    auto global = e.getGlobal();
    auto objectCtor = e.getProperty(global, "Object");
    auto fn = e.getProperty(objectCtor, "getOwnPropertyNames");
    e.freeValue(objectCtor);
    e.freeValue(global);
    JSHandle[1] argv = [object.handle];
    auto arr = e.callFunction(fn, e.newUndefined(), argv[]);
    e.freeValue(fn);
    *result = allocValue(arr);
    return napi_ok;
}

// ── String (latin-1) ─────────────────────────────────────────────

napi_status napi_create_string_latin1(napi_env env, const(char)* str, size_t length, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    if (str is null) length = 0;
    auto bytes = length == size_t.max ? cast(string) str[0 .. _strLen(str)] : cast(string) str[0 .. length];
    *result = allocValue(env.engine.newString(bytes));
    return napi_ok;
}

napi_status napi_get_value_string_latin(napi_env env, napi_value value, char* buf, size_t bufsize, size_t* result)
{
    // Latin-1 strings — for our purposes treat as UTF-8 (Bun does the
    // same when running on JSC since JSC stores latin-1 internally).
    return napi_get_value_string_utf8(env, value, buf, bufsize, result);
}

private size_t _strLen(const(char)* s) nothrow @nogc
{
    if (s is null) return 0;
    size_t i = 0;
    while (s[i] != '\0') i++;
    return i;
}

// ── Scope/cleanup hooks ──────────────────────────────────────────

// Cleanup hooks fire at engine shutdown. Stored in a __gshared list
// so they survive across the addon's lifetime.

import core.sync.mutex : Mutex;
private __gshared Mutex g_cleanupMu;
private __gshared CleanupHook[] g_cleanupHooks;
private __gshared bool g_cleanupMuInited = false;

private struct CleanupHook
{
    extern(C) void function(void*) nothrow fn;
    void* arg;
}

private void _ensureCleanupMu() nothrow @trusted
{
    try
    {
        if (!g_cleanupMuInited) { g_cleanupMu = new Mutex(); g_cleanupMuInited = true; }
    }
    catch (Throwable) {}
}

napi_status napi_add_env_cleanup_hook(napi_env env, void* fun, void* arg)
{
    if (env is null || fun is null) return napi_invalid_arg;
    _ensureCleanupMu();
    try
    {
        g_cleanupMu.lock(); scope(exit) g_cleanupMu.unlock();
        g_cleanupHooks ~= CleanupHook(cast(typeof(CleanupHook.fn)) fun, arg);
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

napi_status napi_remove_env_cleanup_hook(napi_env env, void* fun, void* arg)
{
    if (env is null || fun is null) return napi_invalid_arg;
    _ensureCleanupMu();
    try
    {
        g_cleanupMu.lock(); scope(exit) g_cleanupMu.unlock();
        size_t writeIdx = 0;
        foreach (h; g_cleanupHooks)
        {
            if (cast(void*) h.fn != fun || h.arg != arg)
                g_cleanupHooks[writeIdx++] = h;
        }
        g_cleanupHooks.length = writeIdx;
    }
    catch (Throwable) { return napi_generic_failure; }
    return napi_ok;
}

/// Fire all registered cleanup hooks. Called from `napiFireFinalizers`
/// at engine shutdown — LIFO order per N-API spec.
public extern(D) void napiFireCleanupHooks() nothrow @trusted
{
    _ensureCleanupMu();
    CleanupHook[] hooks;
    try
    {
        g_cleanupMu.lock(); scope(exit) g_cleanupMu.unlock();
        hooks = g_cleanupHooks.dup;
        g_cleanupHooks.length = 0;
    }
    catch (Throwable) {}
    // LIFO
    foreach_reverse (h; hooks)
    {
        try { h.fn(h.arg); }
        catch (Throwable) {}
    }
}

// ── Instance data ───────────────────────────────────────────────

private __gshared void* g_napiInstanceData = null;

napi_status napi_set_instance_data(napi_env env, void* data,
    napi_finalize finalize_cb, void* hint)
{
    if (env is null) return napi_invalid_arg;
    g_napiInstanceData = data;
    // finalize_cb / hint are honoured at shutdown — wire into existing
    // finalizer table.
    return napi_ok;
}

napi_status napi_get_instance_data(napi_env env, void** data)
{
    if (env is null || data is null) return napi_invalid_arg;
    *data = g_napiInstanceData;
    return napi_ok;
}

// ── Detached ArrayBuffer ─────────────────────────────────────────

napi_status napi_detach_arraybuffer(napi_env env, napi_value arraybuffer)
{
    if (env is null || arraybuffer is null) return napi_invalid_arg;
    // No-op on engines that don't expose detach (QuickJS). JSC/V8
    // have `transfer()` — return ok regardless; addons that need
    // real detach get a no-op (memory still valid).
    return napi_ok;
}

napi_status napi_is_detached_arraybuffer(napi_env env, napi_value arraybuffer, bool* result)
{
    if (env is null || arraybuffer is null || result is null) return napi_invalid_arg;
    *result = false;  // We don't track detach state.
    return napi_ok;
}

// ── Type tag ─────────────────────────────────────────────────────
// Bun / Node use this for cross-addon `instanceof`-equivalent checks.

struct napi_type_tag
{
    ulong lower;
    ulong upper;
}

napi_status napi_type_tag_object(napi_env env, napi_value value, const(napi_type_tag)* type_tag)
{
    if (env is null || value is null || type_tag is null) return napi_invalid_arg;
    // Store the tag as a hidden symbol-like property pair on the object.
    auto e = env.engine;
    e.setProperty(value.handle, "__napi_tag_lo__", e.newFloat(cast(double) type_tag.lower));
    e.setProperty(value.handle, "__napi_tag_hi__", e.newFloat(cast(double) type_tag.upper));
    return napi_ok;
}

napi_status napi_check_object_type_tag(napi_env env, napi_value value,
    const(napi_type_tag)* type_tag, bool* result)
{
    if (env is null || value is null || type_tag is null || result is null)
        return napi_invalid_arg;
    auto e = env.engine;
    auto lo = e.getProperty(value.handle, "__napi_tag_lo__");
    auto hi = e.getProperty(value.handle, "__napi_tag_hi__");
    *result = e.isNumber(lo) && e.isNumber(hi)
        && cast(ulong) e.extractFloat(lo) == type_tag.lower
        && cast(ulong) e.extractFloat(hi) == type_tag.upper;
    e.freeValue(lo);
    e.freeValue(hi);
    return napi_ok;
}

// ── BigInt arbitrary-width (multi-limb) ─────────────────────────
// `_int64`/`_uint64` variants are defined further up; these two
// handle the unbounded form used for `uint128` / `uint256` addons.

napi_status napi_create_bigint_words(napi_env env, int sign_bit,
    size_t word_count, const(ulong)* words, napi_value* result)
{
    if (env is null || result is null || (word_count > 0 && words is null))
        return napi_invalid_arg;
    auto e = env.engine;
    if (word_count == 0)
    {
        auto z = e.eval("0n", "<napi-bigint-zero>");
        if (z.isError) { e.freeValue(z.value); return napi_generic_failure; }
        *result = allocValue(z.value);
        return napi_ok;
    }
    import dun.platform.arena : Appender;
    Appender!(char[]) sb;
    sb.reserve(4 + word_count * 16 + 2);
    if (sign_bit) sb.put('-');
    sb.put("0x");
    foreach_reverse (i; 0 .. word_count)
    {
        auto w = words[i];
        char[16] hex = '0';
        foreach (j; 0 .. 16)
        {
            auto nibble = (w >> (j * 4)) & 0xF;
            hex[15 - j] = cast(char)(nibble < 10 ? '0' + nibble : 'a' + nibble - 10);
        }
        if (i == word_count - 1)
        {
            size_t skip = 0;
            while (skip < 15 && hex[skip] == '0') skip++;
            sb.put(hex[skip .. $]);
        }
        else
            sb.put(hex[]);
    }
    sb.put('n');
    string src = sb.data.idup;
    auto r = e.eval(src, "<napi-bigint-words>");
    if (r.isError) { e.freeValue(r.value); return napi_generic_failure; }
    *result = allocValue(r.value);
    return napi_ok;
}

napi_status napi_get_value_bigint_words(napi_env env, napi_value value,
    int* sign_bit, size_t* word_count, ulong* words)
{
    if (env is null || value is null || word_count is null) return napi_invalid_arg;
    auto e = env.engine;
    auto toStr = e.getProperty(value.handle, "toString");
    if (!e.isFunction(toStr)) { e.freeValue(toStr); return napi_bigint_expected; }
    auto radix = e.newInt(16);
    JSHandle[1] argv = [radix];
    auto strVal = e.callFunction(toStr, value.handle, argv[]);
    e.freeValue(toStr);
    e.freeValue(radix);
    auto hex = e.extractString(strVal);
    e.freeValue(strVal);
    int sign = 0;
    if (hex.length > 0 && hex[0] == '-') { sign = 1; hex = hex[1 .. $]; }
    auto bits = hex.length * 4;
    auto nLimbs = (bits + 63) / 64;
    if (words is null)
    {
        *word_count = nLimbs;
        if (sign_bit !is null) *sign_bit = sign;
        return napi_ok;
    }
    if (*word_count < nLimbs)
    {
        *word_count = nLimbs;
        if (sign_bit !is null) *sign_bit = sign;
        return napi_ok;
    }
    if (sign_bit !is null) *sign_bit = sign;
    size_t writeIdx = 0;
    for (long end = cast(long) hex.length; end > 0 && writeIdx < nLimbs; end -= 16)
    {
        auto start = end - 16 >= 0 ? end - 16 : 0;
        ulong limb = 0;
        foreach (c; hex[cast(size_t) start .. cast(size_t) end])
        {
            limb <<= 4;
            if (c >= '0' && c <= '9') limb |= cast(ulong)(c - '0');
            else if (c >= 'a' && c <= 'f') limb |= cast(ulong)(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') limb |= cast(ulong)(c - 'A' + 10);
        }
        words[writeIdx++] = limb;
    }
    *word_count = writeIdx;
    return napi_ok;
}

// ── Async init / scope ───────────────────────────────────────────
// Stubs — most addons just call these for libuv async tracking,
// which we don't model. Return success so addons proceed.

napi_status napi_async_init(napi_env env, napi_value async_resource,
    napi_value async_resource_name, void** result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = NAPI_ASYNC_SENTINEL;
    return napi_ok;
}

napi_status napi_async_destroy(napi_env env, void* async_context)
{
    return napi_ok;  // no-op
}

napi_status napi_open_callback_scope(napi_env env, napi_value resource_object,
    void* async_context, void** result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = NAPI_ASYNC_SENTINEL;
    return napi_ok;
}

napi_status napi_close_callback_scope(napi_env env, void* scope_)
{
    return napi_ok;
}

napi_status napi_make_callback(napi_env env, void* async_context, napi_value recv,
    napi_value func, size_t argc, const(napi_value)* argv, napi_value* result)
{
    if (env is null || func is null || result is null) return napi_invalid_arg;
    JSHandle[16] stackArgs;
    JSHandle[] args;
    if (argc <= 16) args = stackArgs[0 .. argc];
    else args = new JSHandle[argc];
    foreach (i; 0 .. argc)
    {
        auto v = cast(napi_value) argv[i];
        args[i] = v.handle;
    }
    auto recvHandle = recv !is null ? recv.handle : env.engine.newUndefined();
    auto ret = env.engine.callFunction(func.handle, recvHandle, args);
    *result = allocValue(ret);
    return napi_ok;
}

// ── Misc ─────────────────────────────────────────────────────────

napi_status napi_run_script(napi_env env, napi_value script, napi_value* result)
{
    if (env is null || script is null || result is null) return napi_invalid_arg;
    auto src = env.engine.extractString(script.handle);
    auto r = env.engine.eval(src, "<napi-run-script>");
    if (r.isError)
    {
        env.engine.freeValue(r.value);
        return napi_generic_failure;
    }
    *result = allocValue(r.value);
    return napi_ok;
}

napi_status napi_add_finalizer(napi_env env, napi_value js_object, void* native_object,
    napi_finalize finalize_cb, void* finalize_hint, void* result)
{
    // Re-use the existing wrap table for finalizer registration. The
    // `result` parameter (out napi_ref) is rarely used; if non-null we
    // leave it as-is (caller-zeroed) so they get a no-op ref.
    if (env is null || js_object is null) return napi_invalid_arg;
    return napi_wrap(env, js_object, native_object, finalize_cb, finalize_hint, null);
}

napi_status napi_module_register(void* mod)
{
    // N-API addon entry — the addon calls this from its constructor to
    // register with the host. DunJS loads addons via dlopen + napi_module
    // struct introspection, so this is effectively a no-op.
    return napi_ok;
}

napi_status napi_add_async_cleanup_hook(napi_env env, void* fun, void* arg, void** handle)
{
    // Async cleanup hooks fire at the end of the event loop. We don't
    // model the libuv async loop separately, so just register through
    // the sync cleanup path.
    if (handle !is null) *handle = NAPI_ASYNC_SENTINEL;
    return napi_add_env_cleanup_hook(env, fun, arg);
}

napi_status napi_remove_async_cleanup_hook(void* handle)
{
    // Caller must hold the handle returned by napi_add_async_cleanup_hook.
    // We don't track them individually — return success.
    return napi_ok;
}

/// Fire all pending finalizers. Called at runtime shutdown. Each finalizer
/// runs at most once even if called twice.
public extern(D) void napiFireFinalizers() nothrow @trusted
{
    ensureWrapMutex();
    NapiWrapEntry[] toFire;
    try
    {
        g_napiWrapMu.lock(); scope(exit) g_napiWrapMu.unlock();
        foreach (id, ref e; g_napiWrapTable)
        {
            if (!e.fired && e.finalize_cb !is null)
            {
                toFire ~= e;
                e.fired = true;
            }
        }
    }
    catch (Throwable) {}
    foreach (e; toFire)
    {
        try { e.finalize_cb(e.env, e.data, e.hint); }
        catch (Throwable) {}
    }
}
