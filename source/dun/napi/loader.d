module dun.napi.loader;


/++
 + `@trusted policy`: N-API native addon loader — `dlopen` the .node
 + file, find the `napi_register_module_v1` export, invoke it with
 + the env/exports. Permission: `Permission.run`. Same surface as
 + `dun.runtime.ffi` for the dlopen call.
 +/
version (Posix):

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;
import dun.napi.types : napi_env, napi_value, napi_value_s, napi_module;
import dun.napi.napi : getOrCreateEnv, allocValue;

JSHandle loadNativeAddon(IJSEngine engine, DunState* state, string path) @trusted
{
    assert(engine !is null);
    assert(state !is null);
    assert(path.length > 0);

    import core.sys.posix.dlfcn : dlopen, dlsym, dlerror, RTLD_NOW, RTLD_LOCAL;
    import std.string : toStringz;

    auto handle = dlopen(path.toStringz, RTLD_NOW | RTLD_LOCAL);
    if (handle is null)
    {
        auto err = dlerror();
        string msg = "Cannot load native addon: ";
        if (err !is null)
        {
            import core.stdc.string : strlen;
            msg ~= cast(string) err[0 .. strlen(err)];
        }
        return engine.throwTypeError(msg);
    }

    auto env = getOrCreateEnv(state);

    // Try napi_register_module_v1 (standard N-API entry point)
    alias RegisterFn = extern(C) napi_value function(napi_env env, napi_value exports) nothrow;
    auto registerFn = cast(RegisterFn) dlsym(handle, "napi_register_module_v1");
    if (registerFn !is null)
    {
        auto exports = engine.newObject();
        napi_value_s exportsVal;
        exportsVal.handle = exports;
        auto result = registerFn(env, &exportsVal);
        if (result !is null)
            return result.handle;
        return exports;
    }

    // Try node_register_module_v1 (older convention)
    auto oldRegister = cast(RegisterFn) dlsym(handle, "node_register_module_v1");
    if (oldRegister !is null)
    {
        auto exports = engine.newObject();
        napi_value_s exportsVal;
        exportsVal.handle = exports;
        auto result = oldRegister(env, &exportsVal);
        if (result !is null)
            return result.handle;
        return exports;
    }

    return engine.throwTypeError("Native addon has no napi_register_module_v1 entry point");
}
