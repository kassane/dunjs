/// Module loading and caching.
///
/// Caches compiled modules by resolved path to avoid re-evaluation.
/// Registered as the QuickJS module loader via JS_SetModuleLoaderFunc.
module dun.modules.loader;

import dun.engine.bindings;

/// Module loader with caching.
struct ModuleLoader
{
    private JSModuleDef*[string] cache;

    /// Install this loader on the QuickJS runtime.
    void install(JSRuntime* rt) @trusted
    {
        JS_SetModuleLoaderFunc(rt, null, &loadModuleCallback, cast(void*)&this);
    }
}

/// QuickJS callback: load and compile module source.
private extern (C) JSModuleDef* loadModuleCallback(
    JSContext* ctx, const(char)* module_name, void* opaque) nothrow
{
    // TODO: Implement module loading
    // 1. Resolve the module name to an absolute path
    // 2. Check cache
    // 3. Read the file
    // 4. Compile with JS_Eval(JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY)
    // 5. Cache and return
    return null;
}
