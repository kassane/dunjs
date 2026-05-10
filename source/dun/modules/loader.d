module dun.modules.loader;

import dun.engine.quickjs.bindings;

struct ModuleLoader
{
    private JSModuleDef*[string] cache;

    void install(JSRuntime* rt) @trusted
    {
        JS_SetModuleLoaderFunc(rt, null, &loadModuleCallback, cast(void*)&this);
    }
}

private extern (C) JSModuleDef* loadModuleCallback(
    JSContext* ctx, const(char)* module_name, void* opaque) nothrow
{
    // TODO: Implement module loading
    return null;
}
