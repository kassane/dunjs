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

            // Map bare Node.js builtin names to dun: prefix
            if (!name.startsWith("dun:") && !name.startsWith("./") &&
                !name.startsWith("../") && !isAbsolute(name) &&
                isBareBuiltin(name))
                name = "dun:" ~ name;

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
            else
            {
                // Bare specifier that didn't match a builtin: try
                // node_modules lookup the same way require() does.
                import dun.modules.require : findNodeModule;
                auto fromDir = base.length > 0 ? dirName(base) : ".";
                auto resolved = findNodeModule(name, fromDir);
                if (resolved.length > 0)
                    name = resolved;
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

        // Comment out a leading shebang line so the JS parser doesn't
        // choke on `#!/usr/bin/env -S deno run ...`.
        if (source.length >= 2 && source[0] == '#' && source[1] == '!')
            source = "//" ~ source[2 .. $];

        // V8 prebuilt lacks ICU; rewrite Unicode property escapes in
        // regex LITERALS to expanded character classes so source like
        // `/\p{ID_Start}/u` parses. Same path used in require.d for CJS.
        version (EngineV8)
        {
            import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
            source = expandUnicodePropertyEscapes(source);
        }

        // JSON modules: wrap as `export default <content>`
        if (specifier.endsWith(".json"))
        {
            import std.string : replace;
            source = "export default JSON.parse('" ~
                source.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "\\r") ~
                "');\n";
        }
        // CJS-from-ESM interop: if the imported file uses `module.exports`
        // or `exports.xyz =` and is not an ESM module file (.mjs / has top-level
        // `export`/`import`), wrap it with a tiny ESM shim that goes through
        // require() and re-exports the resulting object as default + named.
        else if ((specifier.endsWith(".js") || specifier.endsWith(".cjs"))
              && looksLikeCommonJS(source))
        {
            try
            {
                import std.string : replace;
                import std.path : absolutePath;
                auto absSpec = absolutePath(specifier).replace(`\`, `\\`).replace(`"`, `\"`);
                source =
                    `const __dun_cjs_mod = require("` ~ absSpec ~ `");` ~
                    `export default __dun_cjs_mod;`;
                // Named-import support for CJS is best-effort — consumers
                // using `import { x } from "pkg"` get `default` only.
            }
            catch (Exception) {}
        }

        // Strip TypeScript types
        if (specifier.endsWith(".ts") || specifier.endsWith(".mts"))
        {
            try
            {
                import dun.ts.strip : stripTypes, generateSourceMap;
                import std.base64 : Base64;

                string sourceMap;
                source = stripTypes(source, true, sourceMap);

                // Append inline source map
                if (sourceMap.length > 0)
                {
                    auto encoded = Base64.encode(cast(const(ubyte)[]) sourceMap);
                    source ~= "\n//# sourceMappingURL=data:application/json;base64,"
                        ~ cast(string) encoded;
                }
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

private bool looksLikeCommonJS(string source) @safe pure nothrow
{
    import std.algorithm : canFind;
    // Quick heuristic: file contains `module.exports` / `exports.` /
    // top-level `require(...)` AND has no top-level `import`/`export`
    // statement. Misses some pathological cases but matches the bulk
    // of the npm ecosystem.
    bool hasCJS = source.canFind("module.exports") || source.canFind("exports.");
    if (!hasCJS) return false;
    // Look for line-start `export ` / `import ` to rule out true ESM
    // modules that happen to also reference `exports.foo`.
    for (size_t i = 0; i < source.length; i++)
    {
        if (i == 0 || source[i - 1] == '\n')
        {
            if (source.length - i >= 7 && source[i .. i + 7] == "export ")
                return false;
            if (source.length - i >= 7 && source[i .. i + 7] == "import ")
                return false;
        }
    }
    return true;
}

private bool isBareBuiltin(string name) @safe pure nothrow @nogc
{
    static immutable builtins = [
        "fs", "path", "crypto", "os", "events", "buffer", "url", "util",
        "http", "https", "http2", "http3", "net", "dns", "tls", "dgram",
        "stream", "zlib", "child_process", "worker_threads", "cluster",
        "vm", "assert", "querystring", "string_decoder", "readline",
        "perf_hooks", "async_hooks", "timers/promises", "fs/promises",
        "ws", "sqlite", "tty", "module",
    ];
    foreach (b; builtins)
        if (name == b)
            return true;
    return false;
}
