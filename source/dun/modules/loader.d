module dun.modules.loader;

struct ModuleLoader
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings;

        private JSModuleDef*[string] cache;

        void install(JSRuntime* rt) @trusted
        {
            JS_SetModuleLoaderFunc(rt, null, &loadModuleCallback, cast(void*)&this);
        }
    }
}

version (EngineQuickJS)
{
    private extern (C) JSModuleDef* loadModuleCallback(
        JSContext* ctx, const(char)* module_name, void* opaque) nothrow
    {
        return null;
    }
}
