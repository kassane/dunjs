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

// --- Async work (`napi_create_async_work` family) ---
alias napi_async_execute_callback =
    extern(C) void function(napi_env env, void* data) nothrow;
alias napi_async_complete_callback =
    extern(C) void function(napi_env env, napi_status status, void* data) nothrow;

// Opaque handle returned by `napi_create_async_work`.
struct napi_async_work_s
{
    napi_env env;
    string name;
    void* data;
    napi_async_execute_callback execute;
    napi_async_complete_callback complete;
    int state;  // 0 = idle, 1 = queued, 2 = running, 3 = completed
}
alias napi_async_work = napi_async_work_s*;

// --- Threadsafe function (`napi_create_threadsafe_function` family) ---
alias napi_threadsafe_function_call_js = extern(C) void function(
    napi_env env, napi_value js_callback, void* context, void* data) nothrow;

enum : int
{
    napi_tsfn_release = 0,
    napi_tsfn_abort = 1,
}
alias napi_threadsafe_function_release_mode = int;

enum : int
{
    napi_tsfn_nonblocking = 0,
    napi_tsfn_blocking = 1,
}
alias napi_threadsafe_function_call_mode = int;

struct napi_threadsafe_function_s
{
    napi_env env;
    JSHandle jsFunc;        // pinned JS callable
    void* context;
    napi_threadsafe_function_call_js call_js_cb;
    string name;
    size_t maxQueueSize;
    int refCount;
    int aborted;
    // Queue lives in env's dispatch loop; protected by a mutex on the D side.
}
alias napi_threadsafe_function = napi_threadsafe_function_s*;

// --- Reference (`napi_create_reference` returns a handle ID) ---
struct napi_ref_s
{
    napi_env env;
    JSHandle value;
    uint refcount;
}
alias napi_ref = napi_ref_s*;
