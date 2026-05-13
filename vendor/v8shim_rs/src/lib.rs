//! dun_v8shim — Rust reimplementation of vendor/v8shim/v8shim.cpp
//!
//! Exposes the same `extern "C"` API as v8shim.h so D's bindings.d works unchanged.
//! Uses denoland/rusty_v8 (crate `v8`) instead of raw V8 C++ API.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_void};
use std::ptr;
use std::sync::Once;

// --- Opaque wrapper types (match v8shim.h) ---

/// Wraps a v8::OwnedIsolate + CreateParams.
pub struct DunV8Isolate {
    isolate: v8::OwnedIsolate,
}

/// Wraps a v8::Global<v8::Context> + back-pointer to isolate.
pub struct DunV8Context {
    context: v8::Global<v8::Context>,
    isolate: *mut DunV8Isolate,
    user_data: *mut c_void,
}

/// Wraps a v8::Global<v8::Value> with manual ref-counting.
pub struct DunV8Value {
    value: v8::Global<v8::Value>,
    isolate: *mut DunV8Isolate,
    ref_count: u32,
}

/// D-side native callback signature (must match v8shim.h exactly).
type DunV8NativeCallback = Option<
    unsafe extern "C" fn(
        ctx: *mut DunV8Context,
        this_val: *mut DunV8Value,
        argc: c_int,
        argv: *mut *mut DunV8Value,
        data: *mut c_void,
    ) -> *mut DunV8Value,
>;

/// Data attached to native functions for the trampoline.
struct FunctionData {
    callback: DunV8NativeCallback,
    user_data: *mut c_void,
}

// --- Platform initialization ---

static V8_INIT: Once = Once::new();

fn ensure_v8_initialized() {
    V8_INIT.call_once(|| {
        let platform = v8::new_default_platform(0, false).make_shared();
        v8::V8::initialize_platform(platform);
        v8::V8::initialize();
    });
}

// --- Helper: run code with HandleScope + Context::Scope ---

unsafe fn with_context<F, R>(ctx: *mut DunV8Context, f: F) -> R
where
    F: FnOnce(&mut v8::HandleScope<'_>) -> R,
{
    let ctx_ref = &mut *ctx;
    let isolate_ref = &mut *ctx_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut handle_scope = v8::HandleScope::new(isolate);
    let context = v8::Local::new(&mut handle_scope, &ctx_ref.context);
    let mut context_scope = v8::ContextScope::new(&mut handle_scope, context);
    f(&mut context_scope)
}

unsafe fn wrap_value(isolate_ptr: *mut DunV8Isolate, scope: &mut v8::HandleScope<'_>, val: v8::Local<'_, v8::Value>) -> *mut DunV8Value {
    let global = v8::Global::new(scope, val);
    Box::into_raw(Box::new(DunV8Value {
        value: global,
        isolate: isolate_ptr,
        ref_count: 1,
    }))
}

// --- Isolate ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_isolate_new() -> *mut DunV8Isolate {
    ensure_v8_initialized();
    let params = v8::CreateParams::default();
    let isolate = v8::Isolate::new(params);
    Box::into_raw(Box::new(DunV8Isolate { isolate }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_isolate_dispose(isolate: *mut DunV8Isolate) {
    if !isolate.is_null() {
        drop(unsafe { Box::from_raw(isolate) });
    }
}

// --- Context ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_context_new(isolate_ptr: *mut DunV8Isolate) -> *mut DunV8Context {
    if isolate_ptr.is_null() {
        return ptr::null_mut();
    }
    let isolate_ref = &mut *isolate_ptr;
    let isolate = isolate_ref.isolate.as_mut();
    let mut handle_scope = v8::HandleScope::new(isolate);
    let context = v8::Context::new(&mut handle_scope, Default::default());
    let global_context = v8::Global::new(&mut handle_scope, context);
    Box::into_raw(Box::new(DunV8Context {
        context: global_context,
        isolate: isolate_ptr,
        user_data: ptr::null_mut(),
    }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_context_free(ctx: *mut DunV8Context) {
    if !ctx.is_null() {
        drop(unsafe { Box::from_raw(ctx) });
    }
}

// --- Evaluation ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_eval(
    ctx: *mut DunV8Context,
    source: *const c_char,
    source_len: usize,
    filename: *const c_char,
    is_error: *mut c_int,
) -> *mut DunV8Value {
    if ctx.is_null() || source.is_null() {
        if !is_error.is_null() { *is_error = 1; }
        return ptr::null_mut();
    }

    with_context(ctx, |scope| {
        let src_bytes = std::slice::from_raw_parts(source as *const u8, source_len);
        let src_str = match std::str::from_utf8(src_bytes) {
            Ok(s) => s,
            Err(_) => {
                if !is_error.is_null() { *is_error = 1; }
                return ptr::null_mut();
            }
        };

        let v8_source = v8::String::new(scope, src_str).unwrap();

        let fname = if !filename.is_null() {
            let cstr = CStr::from_ptr(filename);
            v8::String::new(scope, cstr.to_str().unwrap_or("<eval>"))
        } else {
            v8::String::new(scope, "<eval>")
        };

        let origin = v8::ScriptOrigin::new(scope, fname.unwrap().into(), 0, 0, false, 0,
            None, false, false, false, None);

        let script = match v8::Script::compile(scope, v8_source, Some(&origin)) {
            Some(s) => s,
            None => {
                if !is_error.is_null() { *is_error = 1; }
                return ptr::null_mut();
            }
        };

        let try_catch = &mut v8::TryCatch::new(scope);
        match script.run(try_catch) {
            Some(result) => {
                if !is_error.is_null() { *is_error = 0; }
                wrap_value((*ctx).isolate, try_catch, result)
            }
            None => {
                if !is_error.is_null() { *is_error = 1; }
                if let Some(exception) = try_catch.exception() {
                    wrap_value((*ctx).isolate, try_catch, exception)
                } else {
                    ptr::null_mut()
                }
            }
        }
    })
}

// --- Value creation ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_undefined(ctx: *mut DunV8Context) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let val = v8::undefined(scope).into();
        wrap_value((*ctx).isolate, scope, val)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_null(ctx: *mut DunV8Context) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let val = v8::null(scope).into();
        wrap_value((*ctx).isolate, scope, val)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_bool(ctx: *mut DunV8Context, val: c_int) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let v = v8::Boolean::new(scope, val != 0).into();
        wrap_value((*ctx).isolate, scope, v)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_int(ctx: *mut DunV8Context, val: c_int) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let v = v8::Integer::new(scope, val).into();
        wrap_value((*ctx).isolate, scope, v)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_number(ctx: *mut DunV8Context, val: f64) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let v = v8::Number::new(scope, val).into();
        wrap_value((*ctx).isolate, scope, v)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_string(
    ctx: *mut DunV8Context,
    str_ptr: *const c_char,
    len: usize,
) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let bytes = std::slice::from_raw_parts(str_ptr as *const u8, len);
        let s = std::str::from_utf8(bytes).unwrap_or("");
        let v8_str = v8::String::new(scope, s).unwrap();
        wrap_value((*ctx).isolate, scope, v8_str.into())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_object(ctx: *mut DunV8Context) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let obj = v8::Object::new(scope);
        wrap_value((*ctx).isolate, scope, obj.into())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_array(ctx: *mut DunV8Context, length: c_int) -> *mut DunV8Value {
    with_context(ctx, |scope| {
        let arr = v8::Array::new(scope, length);
        wrap_value((*ctx).isolate, scope, arr.into())
    })
}

// --- Native function with callback trampoline ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_function(
    ctx: *mut DunV8Context,
    cb: DunV8NativeCallback,
    name: *const c_char,
    data: *mut c_void,
) -> *mut DunV8Value {
    let cb_fn = match cb {
        Some(f) => f,
        None => return ptr::null_mut(),
    };

    with_context(ctx, |scope| {
        let func_data = Box::new(FunctionData {
            callback: Some(cb_fn),
            user_data: data,
        });
        let raw_data = Box::into_raw(func_data);

        let external = v8::External::new(scope, raw_data as *mut c_void);

        let func = v8::Function::builder(
            |scope: &mut v8::HandleScope<'_>,
             args: v8::FunctionCallbackArguments<'_>,
             mut rv: v8::ReturnValue<'_>| {
                let external = args.data();
                let ext = v8::Local::<v8::External>::try_from(external).unwrap();
                let fd = &*(ext.value() as *const FunctionData);

                let cb = fd.callback.unwrap();
                let argc = args.length();

                // Stack-allocate for small arg counts
                let mut stack_argv: [*mut DunV8Value; 16] = [ptr::null_mut(); 16];
                let argv_slice = if argc as usize <= 16 {
                    &mut stack_argv[..argc as usize]
                } else {
                    // Heap fallback for large arg counts
                    let v: Vec<*mut DunV8Value> = vec![ptr::null_mut(); argc as usize];
                    Box::leak(v.into_boxed_slice())
                };

                // Retrieve DunV8Context from scope's context
                let context = scope.get_current_context();
                let ctx_slot = context.get_slot::<*mut DunV8Context>(scope);
                let ctx_ptr = match ctx_slot {
                    Some(p) => *p,
                    None => return,
                };

                let isolate_ptr = (*ctx_ptr).isolate;

                for i in 0..argc {
                    let arg = args.get(i);
                    argv_slice[i as usize] = wrap_value(isolate_ptr, scope, arg);
                }

                let this_val = args.this();
                let this_wrapped = wrap_value(isolate_ptr, scope, this_val.into());

                let result = cb(
                    ctx_ptr,
                    this_wrapped,
                    argc,
                    argv_slice.as_mut_ptr(),
                    fd.user_data,
                );

                // Clean up arg wrappers
                dun_v8_value_unref(this_wrapped);
                for i in 0..argc as usize {
                    if !argv_slice[i].is_null() {
                        dun_v8_value_unref(argv_slice[i]);
                    }
                }

                if !result.is_null() {
                    let result_ref = &*result;
                    let local = v8::Local::new(scope, &result_ref.value);
                    rv.set(local);
                    dun_v8_value_unref(result);
                }
            },
        )
        .data(external.into())
        .build(scope)
        .unwrap();

        if !name.is_null() {
            let cstr = CStr::from_ptr(name);
            if let Ok(n) = cstr.to_str() {
                let v8_name = v8::String::new(scope, n).unwrap();
                func.set_name(v8_name);
            }
        }

        wrap_value((*ctx).isolate, scope, func.into())
    })
}

// --- Value extraction ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_to_string(
    ctx: *mut DunV8Context,
    val: *mut DunV8Value,
    len: *mut usize,
) -> *const c_char {
    if ctx.is_null() || val.is_null() {
        if !len.is_null() { *len = 0; }
        return ptr::null();
    }
    with_context(ctx, |scope| {
        let val_ref = &*val;
        let local = v8::Local::new(scope, &val_ref.value);
        let s = local.to_rust_string_lossy(scope);
        let cstr = CString::new(s).unwrap_or_else(|_| CString::new("").unwrap());
        if !len.is_null() {
            *len = cstr.as_bytes().len();
        }
        let ptr = cstr.into_raw();
        ptr as *const c_char
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_free_string(str_ptr: *const c_char) {
    if !str_ptr.is_null() {
        drop(unsafe { CString::from_raw(str_ptr as *mut c_char) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_to_int(ctx: *mut DunV8Context, val: *mut DunV8Value) -> c_int {
    if ctx.is_null() || val.is_null() { return 0; }
    with_context(ctx, |scope| {
        let val_ref = &*val;
        let local = v8::Local::new(scope, &val_ref.value);
        local.int32_value(scope).unwrap_or(0)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_to_number(ctx: *mut DunV8Context, val: *mut DunV8Value) -> f64 {
    if ctx.is_null() || val.is_null() { return 0.0; }
    with_context(ctx, |scope| {
        let val_ref = &*val;
        let local = v8::Local::new(scope, &val_ref.value);
        local.number_value(scope).unwrap_or(0.0)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_to_bool(ctx: *mut DunV8Context, val: *mut DunV8Value) -> c_int {
    if ctx.is_null() || val.is_null() { return 0; }
    with_context(ctx, |scope| {
        let val_ref = &*val;
        let local = v8::Local::new(scope, &val_ref.value);
        local.boolean_value(scope) as c_int
    })
}

// --- Type checks ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_undefined(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_undefined() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_null(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_null() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_bool(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_boolean() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_int(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_int32() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_number(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_number() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_string(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_string() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_object(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_object() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_function(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_function() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_is_array(val: *mut DunV8Value) -> c_int {
    if val.is_null() { return 0; }
    let val_ref = &*val;
    let isolate_ref = &mut *val_ref.isolate;
    let isolate = isolate_ref.isolate.as_mut();
    let mut scope = v8::HandleScope::new(isolate);
    let local = v8::Local::new(&mut scope, &val_ref.value);
    local.is_array() as c_int
}

// --- Properties ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_get_property(
    ctx: *mut DunV8Context,
    obj: *mut DunV8Value,
    name: *const c_char,
) -> *mut DunV8Value {
    if ctx.is_null() || obj.is_null() || name.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let obj_ref = &*obj;
        let local_obj = v8::Local::new(scope, &obj_ref.value);
        let v8_obj = match v8::Local::<v8::Object>::try_from(local_obj) {
            Ok(o) => o,
            Err(_) => return ptr::null_mut(),
        };
        let cstr = CStr::from_ptr(name);
        let key = v8::String::new(scope, cstr.to_str().unwrap_or("")).unwrap();
        match v8_obj.get(scope, key.into()) {
            Some(val) => wrap_value((*ctx).isolate, scope, val),
            None => dun_v8_new_undefined(ctx),
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_set_property(
    ctx: *mut DunV8Context,
    obj: *mut DunV8Value,
    name: *const c_char,
    val: *mut DunV8Value,
) {
    if ctx.is_null() || obj.is_null() || name.is_null() || val.is_null() { return; }
    with_context(ctx, |scope| {
        let obj_ref = &*obj;
        let local_obj = v8::Local::new(scope, &obj_ref.value);
        let v8_obj = match v8::Local::<v8::Object>::try_from(local_obj) {
            Ok(o) => o,
            Err(_) => return,
        };
        let cstr = CStr::from_ptr(name);
        let key = v8::String::new(scope, cstr.to_str().unwrap_or("")).unwrap();
        let val_ref = &*val;
        let local_val = v8::Local::new(scope, &val_ref.value);
        v8_obj.set(scope, key.into(), local_val);
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_get_property_index(
    ctx: *mut DunV8Context,
    obj: *mut DunV8Value,
    idx: c_uint,
) -> *mut DunV8Value {
    if ctx.is_null() || obj.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let obj_ref = &*obj;
        let local_obj = v8::Local::new(scope, &obj_ref.value);
        let v8_obj = match v8::Local::<v8::Object>::try_from(local_obj) {
            Ok(o) => o,
            Err(_) => return ptr::null_mut(),
        };
        match v8_obj.get_index(scope, idx) {
            Some(val) => wrap_value((*ctx).isolate, scope, val),
            None => dun_v8_new_undefined(ctx),
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_set_property_index(
    ctx: *mut DunV8Context,
    obj: *mut DunV8Value,
    idx: c_uint,
    val: *mut DunV8Value,
) {
    if ctx.is_null() || obj.is_null() || val.is_null() { return; }
    with_context(ctx, |scope| {
        let obj_ref = &*obj;
        let local_obj = v8::Local::new(scope, &obj_ref.value);
        let v8_obj = match v8::Local::<v8::Object>::try_from(local_obj) {
            Ok(o) => o,
            Err(_) => return,
        };
        let val_ref = &*val;
        let local_val = v8::Local::new(scope, &val_ref.value);
        v8_obj.set_index(scope, idx, local_val);
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_global(ctx: *mut DunV8Context) -> *mut DunV8Value {
    if ctx.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let context = scope.get_current_context();
        let global = context.global(scope);
        wrap_value((*ctx).isolate, scope, global.into())
    })
}

// --- Typed arrays ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_uint8array(
    ctx: *mut DunV8Context,
    data: *const u8,
    len: usize,
) -> *mut DunV8Value {
    if ctx.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let ab = v8::ArrayBuffer::new(scope, len);
        if !data.is_null() && len > 0 {
            let store = ab.get_backing_store();
            let dest = &store[..len];
            let src = std::slice::from_raw_parts(data, len);
            // Copy data into ArrayBuffer
            for (i, byte) in src.iter().enumerate() {
                let cell = &dest[i];
                cell.set(*byte);
            }
        }
        let arr = v8::Uint8Array::new(scope, ab, 0, len).unwrap();
        wrap_value((*ctx).isolate, scope, arr.into())
    })
}

// --- Reference management ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_ref(val: *mut DunV8Value) {
    if !val.is_null() {
        (*val).ref_count += 1;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_value_unref(val: *mut DunV8Value) {
    if !val.is_null() {
        (*val).ref_count -= 1;
        if (*val).ref_count == 0 {
            drop(Box::from_raw(val));
        }
    }
}

// --- Exceptions ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_get_exception(
    ctx: *mut DunV8Context,
    len: *mut usize,
) -> *const c_char {
    // Return last exception message — simplified implementation
    if !len.is_null() { *len = 0; }
    ptr::null()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_throw_error(
    ctx: *mut DunV8Context,
    msg: *const c_char,
) -> *mut DunV8Value {
    if ctx.is_null() || msg.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let cstr = CStr::from_ptr(msg);
        let s = v8::String::new(scope, cstr.to_str().unwrap_or("Error")).unwrap();
        let err = v8::Exception::error(scope, s);
        scope.throw_exception(err);
        wrap_value((*ctx).isolate, scope, err)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_throw_type_error(
    ctx: *mut DunV8Context,
    msg: *const c_char,
) -> *mut DunV8Value {
    if ctx.is_null() || msg.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let cstr = CStr::from_ptr(msg);
        let s = v8::String::new(scope, cstr.to_str().unwrap_or("TypeError")).unwrap();
        let err = v8::Exception::type_error(scope, s);
        scope.throw_exception(err);
        wrap_value((*ctx).isolate, scope, err)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_throw_range_error(
    ctx: *mut DunV8Context,
    msg: *const c_char,
) -> *mut DunV8Value {
    if ctx.is_null() || msg.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let cstr = CStr::from_ptr(msg);
        let s = v8::String::new(scope, cstr.to_str().unwrap_or("RangeError")).unwrap();
        let err = v8::Exception::range_error(scope, s);
        scope.throw_exception(err);
        wrap_value((*ctx).isolate, scope, err)
    })
}

// --- Function call ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_call(
    ctx: *mut DunV8Context,
    func: *mut DunV8Value,
    this_obj: *mut DunV8Value,
    argc: c_int,
    argv: *mut *mut DunV8Value,
    is_error: *mut c_int,
) -> *mut DunV8Value {
    if ctx.is_null() || func.is_null() {
        if !is_error.is_null() { *is_error = 1; }
        return ptr::null_mut();
    }
    with_context(ctx, |scope| {
        let func_ref = &*func;
        let local_func = v8::Local::new(scope, &func_ref.value);
        let v8_func = match v8::Local::<v8::Function>::try_from(local_func) {
            Ok(f) => f,
            Err(_) => {
                if !is_error.is_null() { *is_error = 1; }
                return ptr::null_mut();
            }
        };

        let recv = if !this_obj.is_null() {
            let this_ref = &*this_obj;
            v8::Local::new(scope, &this_ref.value)
        } else {
            v8::undefined(scope).into()
        };

        let mut args_vec: Vec<v8::Local<'_, v8::Value>> = Vec::with_capacity(argc as usize);
        for i in 0..argc as usize {
            let arg_ptr = *argv.add(i);
            if !arg_ptr.is_null() {
                let arg_ref = &*arg_ptr;
                args_vec.push(v8::Local::new(scope, &arg_ref.value));
            } else {
                args_vec.push(v8::undefined(scope).into());
            }
        }

        let try_catch = &mut v8::TryCatch::new(scope);
        match v8_func.call(try_catch, recv, &args_vec) {
            Some(result) => {
                if !is_error.is_null() { *is_error = 0; }
                wrap_value((*ctx).isolate, try_catch, result)
            }
            None => {
                if !is_error.is_null() { *is_error = 1; }
                if let Some(exc) = try_catch.exception() {
                    wrap_value((*ctx).isolate, try_catch, exc)
                } else {
                    ptr::null_mut()
                }
            }
        }
    })
}

// --- Promises ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_new_promise(
    ctx: *mut DunV8Context,
    resolve_out: *mut *mut DunV8Value,
    reject_out: *mut *mut DunV8Value,
) -> *mut DunV8Value {
    if ctx.is_null() { return ptr::null_mut(); }
    with_context(ctx, |scope| {
        let resolver = v8::PromiseResolver::new(scope).unwrap();
        let promise = resolver.get_promise(scope);

        if !resolve_out.is_null() {
            *resolve_out = wrap_value((*ctx).isolate, scope, resolver.into());
        }
        if !reject_out.is_null() {
            // Resolver is used for both resolve and reject
            dun_v8_value_ref(*resolve_out);
            *reject_out = *resolve_out;
        }

        wrap_value((*ctx).isolate, scope, promise.into())
    })
}

// --- Microtasks ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_has_pending_microtasks(isolate_ptr: *mut DunV8Isolate) -> c_int {
    if isolate_ptr.is_null() { return 0; }
    let isolate_ref = &mut *isolate_ptr;
    let isolate = isolate_ref.isolate.as_mut();
    isolate.has_pending_background_tasks() as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_drain_microtasks(isolate_ptr: *mut DunV8Isolate) {
    if isolate_ptr.is_null() { return; }
    let isolate_ref = &mut *isolate_ptr;
    let isolate = isolate_ref.isolate.as_mut();
    isolate.perform_microtask_checkpoint();
}

// --- Context data ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_set_context_data(ctx: *mut DunV8Context, data: *mut c_void) {
    if !ctx.is_null() {
        (*ctx).user_data = data;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_get_context_data(ctx: *mut DunV8Context) -> *mut c_void {
    if ctx.is_null() { return ptr::null_mut(); }
    (*ctx).user_data
}

// --- Limits ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_set_memory_limit(isolate_ptr: *mut DunV8Isolate, bytes: usize) {
    if isolate_ptr.is_null() { return; }
    let isolate_ref = &mut *isolate_ptr;
    let isolate = isolate_ref.isolate.as_mut();
    let mut heap_stats = v8::HeapStatistics::default();
    isolate.get_heap_statistics(&mut heap_stats);
    // V8's heap limit is set via create params or isolate methods
    // This is a simplified version
    let _ = bytes; // TODO: apply via Isolate::set_heap_limit or similar
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_set_stack_limit(isolate_ptr: *mut DunV8Isolate, bytes: usize) {
    if isolate_ptr.is_null() { return; }
    // V8 stack limit is typically set via CreateParams
    let _ = bytes;
}

// --- Garbage collection ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_collect_garbage(isolate_ptr: *mut DunV8Isolate) {
    if isolate_ptr.is_null() { return; }
    let isolate_ref = &mut *isolate_ptr;
    let isolate = isolate_ref.isolate.as_mut();
    isolate.low_memory_notification();
}

// --- Version ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn dun_v8_version() -> *const c_char {
    let version = v8::V8::get_version();
    // Return static string pointer — v8::V8::get_version returns &'static str
    version.as_ptr() as *const c_char
}
