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
                // Scrape `module.exports.X = ...`, `exports.X = ...`, and
                // `module.exports = { X: ..., Y: ... }` patterns out of
                // the CJS source so we can emit static `export` bindings
                // for each name. Without this, `import { X } from "pkg"`
                // fails at link time because ESM requires statically-
                // declared exports.
                auto namedExports = extractCjsExports(source);
                import std.array : Appender;
                Appender!(char[]) sb;
                sb.reserve(256 + namedExports.length * 32);
                sb.put(`const __dun_cjs_mod = require("`);
                sb.put(absSpec);
                sb.put(`");`);
                sb.put(`export default __dun_cjs_mod;`);
                foreach (n; namedExports)
                {
                    sb.put(`export const `);
                    sb.put(n);
                    sb.put(` = __dun_cjs_mod[`);
                    sb.put(`"`);
                    sb.put(n);
                    sb.put(`"];`);
                }
                source = cast(string) sb.data;
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

/// Extract identifiers that appear to be named CJS exports.
///
/// Recognized patterns:
///   - `module.exports.NAME =`
///   - `exports.NAME =`
///   - `module.exports = { NAME: ..., ... }`
///   - `Object.defineProperty(exports, "NAME", ...)`
///
/// Heuristic — does no AST work, so it can miss exports built via
/// computed property names or weird control flow. Good enough for the
/// vast majority of npm packages.
private string[] extractCjsExports(string source) @safe pure
{
    import std.algorithm : canFind;
    import std.array : Appender;
    string[] result;
    bool[string] seen;
    void add(string name)
    {
        if (name.length == 0) return;
        // Filter JS keywords / illegal export names — anything that
        // isn't a plain identifier we can't emit as `export const X`.
        if (!isValidIdent(name)) return;
        if (name == "default" || name == "import" || name == "export"
         || name == "var" || name == "let" || name == "const"
         || name == "function" || name == "class" || name == "return")
            return;
        if (name in seen) return;
        seen[name] = true;
        result ~= name;
    }
    size_t i = 0;
    while (i < source.length)
    {
        // skip strings/templates/comments
        char c = source[i];
        if (c == '\'' || c == '"')
        {
            i = scanStringLitLoader(source, i);
            continue;
        }
        if (c == '`')
        {
            i = scanTemplateLitLoader(source, i);
            continue;
        }
        if (c == '/' && i + 1 < source.length)
        {
            if (source[i + 1] == '/') { while (i < source.length && source[i] != '\n') i++; continue; }
            if (source[i + 1] == '*')
            {
                i += 2;
                while (i + 1 < source.length && !(source[i] == '*' && source[i + 1] == '/')) i++;
                if (i + 1 < source.length) i += 2;
                continue;
            }
        }

        // module.exports.NAME =
        if (matches(source, i, "module.exports."))
        {
            size_t j = i + 15;
            auto name = readIdentLoader(source, j);
            if (name.length > 0)
            {
                size_t after = j + name.length;
                auto k = skipWSLoader(source, after);
                if (k < source.length && source[k] == '=' && (k + 1 >= source.length || source[k + 1] != '='))
                    add(name);
            }
            i = j + (name.length > 0 ? name.length : 1);
            continue;
        }
        // exports.NAME =  (not preceded by ident or `.`)
        if (matches(source, i, "exports."))
        {
            // Make sure we're not inside `module.exports.` or some other compound.
            bool isBareExports = (i == 0)
                || (!isIdentCharLoader(source[i - 1]) && source[i - 1] != '.');
            if (isBareExports)
            {
                size_t j = i + 8;
                auto name = readIdentLoader(source, j);
                if (name.length > 0)
                {
                    size_t after = j + name.length;
                    auto k = skipWSLoader(source, after);
                    if (k < source.length && source[k] == '=' && (k + 1 >= source.length || source[k + 1] != '='))
                        add(name);
                }
                i = j + (name.length > 0 ? name.length : 1);
                continue;
            }
        }
        // module.exports = { name: ... , name2: ... } — pick keys naively
        if (matches(source, i, "module.exports") || matches(source, i, "exports = "))
        {
            // Find the `=` then look for an opening `{`.
            size_t j = i;
            while (j < source.length && source[j] != '=' && source[j] != ';' && source[j] != '\n') j++;
            if (j < source.length && source[j] == '=')
            {
                size_t k = skipWSLoader(source, j + 1);
                if (k < source.length && source[k] == '{')
                {
                    size_t end = k + 1;
                    int depth = 1;
                    while (end < source.length && depth > 0)
                    {
                        char ec = source[end];
                        if (ec == '{') depth++;
                        else if (ec == '}') depth--;
                        else if (ec == '\'' || ec == '"') end = scanStringLitLoader(source, end) - 1;
                        else if (ec == '`') end = scanTemplateLitLoader(source, end) - 1;
                        end++;
                    }
                    // Scan keys in [k+1 .. end-1].
                    size_t p = k + 1;
                    while (p < end)
                    {
                        char pc = source[p];
                        if (pc == '\'' || pc == '"')
                        {
                            size_t strEnd = scanStringLitLoader(source, p);
                            string keyName = source[p + 1 .. strEnd - 1];
                            // Look for `:` after.
                            size_t q = skipWSLoader(source, strEnd);
                            if (q < source.length && source[q] == ':') add(keyName);
                            p = strEnd;
                            continue;
                        }
                        if (isIdentStartLoader(pc))
                        {
                            string keyName = readIdentLoader(source, p);
                            size_t q = skipWSLoader(source, p + keyName.length);
                            // KEY: ...  or  KEY,  (shorthand: same name)
                            // or  KEY }  (shorthand at end)
                            if (q < source.length
                                && (source[q] == ':' || source[q] == ',' || source[q] == '}'))
                                add(keyName);
                            p += keyName.length;
                            continue;
                        }
                        p++;
                    }
                    i = end;
                    continue;
                }
            }
            i = j + 1;
            continue;
        }
        i++;
    }
    return result;
}

private bool matches(string s, size_t i, string needle) @safe pure nothrow @nogc
{
    if (i + needle.length > s.length) return false;
    return s[i .. i + needle.length] == needle;
}

private bool isIdentStartLoader(char c) @safe pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
}

private bool isIdentCharLoader(char c) @safe pure nothrow @nogc
{
    return isIdentStartLoader(c) || (c >= '0' && c <= '9');
}

private string readIdentLoader(string s, size_t start) @safe pure nothrow @nogc
{
    if (start >= s.length || !isIdentStartLoader(s[start])) return "";
    size_t end = start;
    while (end < s.length && isIdentCharLoader(s[end])) end++;
    return s[start .. end];
}

private size_t skipWSLoader(string s, size_t i) @safe pure nothrow @nogc
{
    while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
        i++;
    return i;
}

private size_t scanStringLitLoader(string s, size_t start) @safe pure nothrow @nogc
{
    char quote = s[start];
    size_t i = start + 1;
    while (i < s.length)
    {
        if (s[i] == '\\' && i + 1 < s.length) { i += 2; continue; }
        if (s[i] == quote) return i + 1;
        i++;
    }
    return s.length;
}

private size_t scanTemplateLitLoader(string s, size_t start) @safe pure nothrow @nogc
{
    size_t i = start + 1;
    while (i < s.length)
    {
        if (s[i] == '\\' && i + 1 < s.length) { i += 2; continue; }
        if (s[i] == '`') return i + 1;
        i++;
    }
    return s.length;
}

private bool isValidIdent(string s) @safe pure nothrow @nogc
{
    if (s.length == 0) return false;
    if (!isIdentStartLoader(s[0])) return false;
    foreach (c; s[1 .. $])
        if (!isIdentCharLoader(c)) return false;
    return true;
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
