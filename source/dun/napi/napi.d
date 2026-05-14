module dun.napi.napi;

import dun.napi.types;
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

private enum MAX_NAPI_VALUES = 4096;
private __gshared napi_value_s[MAX_NAPI_VALUES] gValuePool;
private __gshared int gValuePoolUsed = 0;

napi_value allocValue(JSHandle h) nothrow @trusted
{
    if (gValuePoolUsed >= MAX_NAPI_VALUES)
    {
        gValuePoolUsed = 0;
    }
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
    *result = null;
    return napi_ok;
}

napi_status napi_delete_reference(napi_env env, void* ref_)
{
    return napi_ok;
}

napi_status napi_get_reference_value(napi_env env, void* ref_, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newUndefined());
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
    if (env is null || result is null) return napi_invalid_arg;
    *result = null;
    return napi_ok;
}

napi_status napi_create_external(napi_env env, void* data, napi_finalize finalize_cb, void* hint, napi_value* result)
{
    if (env is null || result is null) return napi_invalid_arg;
    *result = allocValue(env.engine.newObject());
    return napi_ok;
}
