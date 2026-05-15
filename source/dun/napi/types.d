module dun.napi.types;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;

alias napi_status = int;
enum : napi_status
{
    napi_ok = 0,
    napi_invalid_arg = 1,
    napi_object_expected = 2,
    napi_string_expected = 3,
    napi_name_expected = 4,
    napi_function_expected = 5,
    napi_number_expected = 6,
    napi_boolean_expected = 7,
    napi_array_expected = 8,
    napi_generic_failure = 9,
    napi_pending_exception = 10,
    napi_cancelled = 11,
    napi_escape_called_twice = 12,
    napi_handle_scope_mismatch = 13,
    napi_callback_scope_mismatch = 14,
    napi_queue_full = 15,
    napi_closing = 16,
    napi_bigint_expected = 17,
    napi_date_expected = 18,
    napi_arraybuffer_expected = 19,
    napi_detachable_arraybuffer_expected = 20,
    napi_would_deadlock = 21,
}

alias napi_valuetype = int;
enum : napi_valuetype
{
    napi_undefined = 0,
    napi_null = 1,
    napi_boolean = 2,
    napi_number = 3,
    napi_string = 4,
    napi_symbol = 5,
    napi_object = 6,
    napi_function = 7,
    napi_external = 8,
    napi_bigint = 9,
}

struct napi_env_s
{
    IJSEngine engine;
    DunState* state;
}

alias napi_env = napi_env_s*;

struct napi_value_s
{
    JSHandle handle;
}

alias napi_value = napi_value_s*;

struct napi_callback_info_s
{
    napi_env env;
    JSHandle thisVal;
    JSHandle[] args;
    void* data;
}

alias napi_callback_info = napi_callback_info_s*;
alias napi_callback = extern(C) napi_value function(napi_env env, napi_callback_info info) nothrow;

struct napi_module
{
    int nm_version;
    uint nm_flags;
    const(char)* nm_filename;
    extern(C) napi_value function(napi_env env, napi_value exports) nothrow nm_register_func;
    const(char)* nm_modname;
    void*[4] nm_priv;
}

alias napi_finalize = extern(C) void function(napi_env env, void* data, void* hint) nothrow;
