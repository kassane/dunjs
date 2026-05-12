module dun.modules.loader;

struct ModuleLoader
{
    version (EngineQuickJS)
    {
        import dun.engine.quickjs.bindings;

        private JSModuleDef*[string] cache;

        void install(JSRuntime* rt) @trusted
        {
            assert(rt !is null, "Null JSRuntime in ModuleLoader.install");
            JS_SetModuleLoaderFunc(rt, &normalizeModuleFunc, &loadModuleCallback,
                cast(void*) &this);
        }
    }
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private extern (C) char* normalizeModuleFunc(JSContext* ctx,
        const(char)* base_name, const(char)* module_name, void* opaque) nothrow @system
    {
        assert(ctx !is null, "Null JSContext in normalizeModuleFunc");
        assert(module_name !is null, "Null module_name in normalizeModuleFunc");
        try
        {
            import std.algorithm : startsWith;
            import std.string : fromStringz, toStringz;
            import std.path : buildNormalizedPath, dirName, isAbsolute;

            string name = fromStringz(module_name).idup;
            string base = fromStringz(base_name).idup;

            // Rewrite node:X -> dun:X
            if (name.startsWith("node:"))
                name = "dun:" ~ name[5 .. $];

            // Builtins: return canonical name so QuickJS finds the pre-registered C module
            if (name.startsWith("dun:"))
                return js_strdup(ctx, name.toStringz);

            // Relative paths: resolve against importing file's directory
            if (name.startsWith("./") || name.startsWith("../"))
            {
                auto dir = dirName(base);
                name = buildNormalizedPath(dir, name);
            }
            else if (isAbsolute(name))
            {
                name = buildNormalizedPath(name);
            }

            return js_strdup(ctx, name.toStringz);
        }
        catch (Throwable)
        {
            return js_strdup(ctx, module_name);
        }
    }

    private extern (C) JSModuleDef* loadModuleCallback(
        JSContext* ctx, const(char)* module_name, void* opaque) nothrow @system
    {
        assert(ctx !is null, "Null JSContext in loadModuleCallback");
        assert(module_name !is null, "Null module_name in loadModuleCallback");
        assert(opaque !is null, "Null opaque in loadModuleCallback");
        import std.string : fromStringz, toStringz;
        import std.algorithm : endsWith;

        auto loader = cast(ModuleLoader*) opaque;
        auto specifier = fromStringz(module_name).idup;

        // Check cache first
        if (auto cached = specifier in loader.cache)
            return *cached;

        // CJS cross-format guard: .cjs/.cts files cannot be ESM-imported
        if (specifier.endsWith(".cjs") || specifier.endsWith(".cts"))
        {
            JS_ThrowTypeError(ctx,
                "Cannot import a CommonJS module from ESM. Use require() instead.");
            return null;
        }

        // Permission check
        auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
        if (state !is null && state.permissions !is null)
        {
            try
            {
                import dun.security.permissions : Permission;
                if (!state.permissions.check(Permission.read, specifier))
                {
                    JS_ThrowReferenceError(ctx,
                        "Cannot load '%s': requires --allow-read permission",
                        module_name);
                    return null;
                }
            }
            catch (Exception) {}
        }

        // Read source file
        string source;
        try
        {
            import std.file : readText;
            source = readText(specifier);
        }
        catch (Exception)
        {
            JS_ThrowReferenceError(ctx, "Cannot find module '%s'", module_name);
            return null;
        }

        // Strip TypeScript types
        if (specifier.endsWith(".ts") || specifier.endsWith(".mts"))
        {
            try
            {
                import dun.ts.strip : stripTypes;
                source = stripTypes(source);
            }
            catch (Exception) {}
        }

        // Compile as ESM (compile-only; QuickJS links + runs after all deps load)
        auto compiled = JS_Eval(ctx, source.toStringz, source.length, module_name,
            JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);

        if (JS_IsException(compiled) != 0)
            return null;

        // Extract JSModuleDef* from the compiled JSValue, then free the wrapper
        auto mod = cast(JSModuleDef*) compiled.ptr;
        JS_FreeValue(ctx, compiled);

        // Set import.meta.url for the module
        try
        {
            import std.path : absolutePath, dirName;
            auto meta = JS_GetImportMeta(ctx, mod);
            if (JS_IsException(meta) == 0)
            {
                auto absPath = absolutePath(specifier);
                auto urlStr = "file://" ~ absPath;
                JS_SetPropertyStr(ctx, meta, "url",
                    JS_NewStringLen(ctx, urlStr.ptr, urlStr.length));
                JS_SetPropertyStr(ctx, meta, "filename",
                    JS_NewStringLen(ctx, absPath.ptr, absPath.length));
                auto dirStr = dirName(absPath);
                JS_SetPropertyStr(ctx, meta, "dirname",
                    JS_NewStringLen(ctx, dirStr.ptr, dirStr.length));
                JS_SetPropertyStr(ctx, meta, "main",
                    JS_NewBool(ctx, false));
                JS_FreeValue(ctx, meta);
            }
        }
        catch (Throwable) {}

        // Cache by resolved absolute path
        try { loader.cache[specifier] = mod; } catch (Throwable) {}

        return mod;
    }
}

static import dun.runtime.globals;
static import dun.security.permissions;
