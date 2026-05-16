module dun.modules.require;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;
import std.json : JSONValue;

void installRequire(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installRequire");
    auto global = engine.getGlobal();
    auto requireFn = engine.newFunction(&jsRequire, "require", 1);
    engine.setProperty(global, "require", requireFn);
    engine.setProperty(global, "__dunCjsCache__", engine.newObject());
    engine.setProperty(global, "__dunCjsStack__", engine.newArray());

    // require.resolve()
    auto resolveFn = engine.newFunction(&jsRequireResolve, "resolve", 1);
    engine.setProperty(requireFn, "resolve", resolveFn);

    // require.cache (alias to __dunCjsCache__)
    auto cacheRef = engine.getProperty(global, "__dunCjsCache__");
    engine.setProperty(requireFn, "cache", cacheRef);
}

private:

JSHandle jsRequireResolve(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import std.algorithm : startsWith, endsWith;
    import std.path : buildNormalizedPath, isAbsolute, dirName, absolutePath;
    import std.file : exists, isFile, isDir, getcwd;

    assert(ctx !is null, "Null ctx in require.resolve");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("require.resolve() needs at least 1 argument");

    string specifier = engine.extractString(args[0]);
    if (specifier.length == 0)
        return engine.throwTypeError("require.resolve() argument must be a string");

    // Built-in modules resolve to themselves
    if (specifier.startsWith("node:") || specifier.startsWith("dun:"))
        return engine.newString(specifier);

    string[41] builtins = ["fs", "path", "crypto", "net", "http", "https",
        "http2", "http3", "os", "buffer", "events", "url", "child_process",
        "stream", "zlib", "dns", "ws", "sqlite", "util", "assert",
        "querystring", "string_decoder", "timers/promises", "tls", "dgram",
        "vm", "cluster", "async_hooks", "worker_threads", "perf_hooks",
        "fs/promises", "readline", "punycode", "diagnostics_channel", "domain",
        "tty", "constants", "module", "timers", "process", "console"];
    foreach (b; builtins)
        if (specifier == b) return engine.newString(specifier);

    auto global = engine.getGlobal();
    scope(exit) engine.freeValue(global);
    string resolved;

    try
    {
        if (isAbsolute(specifier))
            resolved = buildNormalizedPath(specifier);
        else if (specifier.startsWith("./") || specifier.startsWith("../"))
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = buildNormalizedPath(curDir, specifier);
        }
        else if (specifier.startsWith("#"))
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = resolvePackageImports(specifier, curDir);
            if (resolved.length == 0)
                return throwModuleNotFound(engine, specifier);
            return engine.newString(resolved);
        }
        else
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = findNodeModule(specifier, curDir);
            if (resolved.length == 0)
                return throwModuleNotFound(engine, specifier);
            return engine.newString(resolved);
        }

        if (exists(resolved) && isFile(resolved))
            return engine.newString(resolved);

        static immutable exts = [".js", ".ts", ".cjs", ".cts", ".json", ".node"];
        foreach (ext; exts)
            if (exists(resolved ~ ext) && isFile(resolved ~ ext))
                return engine.newString(resolved ~ ext);

        static immutable idxExts = ["/index.js", "/index.ts", "/index.cjs"];
        foreach (ext; idxExts)
            if (exists(resolved ~ ext) && isFile(resolved ~ ext))
                return engine.newString(resolved ~ ext);

        return throwModuleNotFound(engine, specifier);
    }
    catch (Exception)
    {
        return throwModuleNotFound(engine, specifier);
    }
}

JSHandle jsRequire(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import std.algorithm : startsWith, endsWith;
    import std.path : buildNormalizedPath, isAbsolute, dirName;

    assert(ctx !is null, "Null ctx in jsRequire");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsRequire");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("require() needs at least 1 argument");

    string specifier = engine.extractString(args[0]);
    if (specifier.length == 0)
        return engine.throwTypeError("require() argument must be a string");

    // .mjs/.mts files are handled via ESM shim transpilation (Node 22+ compat)

    if (specifier.startsWith("node:"))
        specifier = "dun:" ~ specifier[5 .. $];
    else if (specifier == "fs") specifier = "dun:fs";
    else if (specifier == "path") specifier = "dun:path";
    else if (specifier == "crypto") specifier = "dun:crypto";
    else if (specifier == "net") specifier = "dun:net";
    else if (specifier == "http") specifier = "dun:http";
    else if (specifier == "https") specifier = "dun:https";
    else if (specifier == "http2") specifier = "dun:http2";
    else if (specifier == "http3") specifier = "dun:http3";
    else if (specifier == "os") specifier = "dun:os";
    else if (specifier == "buffer") specifier = "dun:buffer";
    else if (specifier == "events") specifier = "dun:events";
    else if (specifier == "url") specifier = "dun:url";
    else if (specifier == "child_process") specifier = "dun:child_process";
    else if (specifier == "stream") specifier = "dun:stream";
    else if (specifier == "zlib") specifier = "dun:zlib";
    else if (specifier == "dns") specifier = "dun:dns";
    else if (specifier == "ws") specifier = "dun:ws";
    else if (specifier == "sqlite") specifier = "dun:sqlite";
    else if (specifier == "util") specifier = "dun:util";
    else if (specifier == "assert") specifier = "dun:assert";
    else if (specifier == "querystring") specifier = "dun:querystring";
    else if (specifier == "string_decoder") specifier = "dun:string_decoder";
    else if (specifier == "timers/promises") specifier = "dun:timers/promises";
    else if (specifier == "fs/promises") specifier = "dun:fs/promises";
    else if (specifier == "vm") specifier = "dun:vm";
    else if (specifier == "cluster") specifier = "dun:cluster";
    else if (specifier == "async_hooks") specifier = "dun:async_hooks";
    else if (specifier == "worker_threads") specifier = "dun:worker_threads";
    else if (specifier == "tls") specifier = "dun:tls";
    else if (specifier == "dgram") specifier = "dun:dgram";
    else if (specifier == "perf_hooks") specifier = "dun:perf_hooks";
    else if (specifier == "wasi") specifier = "dun:wasi";
    else if (specifier == "readline") specifier = "dun:readline";
    else if (specifier == "punycode") specifier = "dun:punycode";
    else if (specifier == "diagnostics_channel") specifier = "dun:diagnostics_channel";
    else if (specifier == "domain") specifier = "dun:domain";
    else if (specifier == "tty") specifier = "dun:tty";
    else if (specifier == "constants") specifier = "dun:constants";
    else if (specifier == "module") specifier = "dun:module";
    else if (specifier == "timers") specifier = "dun:timers";
    else if (specifier == "process") specifier = "dun:process";
    else if (specifier == "console") specifier = "dun:console";

    // Handle #imports (package.json "imports" field)
    if (specifier.startsWith("#"))
    {
        auto global2 = engine.getGlobal();
        string curDir = getCjsStackDir(engine, global2);
        engine.freeValue(global2);
        string resolved2 = resolvePackageImports(specifier, curDir);
        if (resolved2.length == 0)
            return throwModuleNotFound(engine, specifier);
        specifier = resolved2;
    }

    auto global = engine.getGlobal();
    scope(exit) engine.freeValue(global);

    if (specifier.startsWith("dun:"))
    {
        string propName;
        if (specifier == "dun:fs") propName = "__dun_cjs_fs__";
        else if (specifier == "dun:path") propName = "__dun_cjs_path__";
        else if (specifier == "dun:crypto") propName = "__dun_cjs_crypto__";
        else if (specifier == "dun:net") propName = "__dun_cjs_net__";
        else if (specifier == "dun:http") propName = "__dun_cjs_http__";
        else if (specifier == "dun:https") propName = "__dun_cjs_https__";
        else if (specifier == "dun:http2") propName = "__dun_cjs_http2__";
        else if (specifier == "dun:http3") propName = "__dun_cjs_http3__";
        else if (specifier == "dun:os") propName = "__dun_cjs_os__";
        else if (specifier == "dun:buffer") propName = "__dun_cjs_buffer__";
        else if (specifier == "dun:events") propName = "__dun_cjs_events__";
        else if (specifier == "dun:url") propName = "__dun_cjs_url__";
        else if (specifier == "dun:child_process") propName = "__dun_cjs_child_process__";
        else if (specifier == "dun:stream") propName = "__dun_cjs_stream__";
        else if (specifier == "dun:zlib") propName = "__dun_cjs_zlib__";
        else if (specifier == "dun:dns") propName = "__dun_cjs_dns__";
        else if (specifier == "dun:ws") propName = "__dun_cjs_ws__";
        else if (specifier == "dun:sqlite") propName = "__dun_cjs_sqlite__";
        else if (specifier == "dun:util") propName = "__dun_cjs_util__";
        else if (specifier == "dun:assert") propName = "__dun_cjs_assert__";
        else if (specifier == "dun:querystring") propName = "__dun_cjs_querystring__";
        else if (specifier == "dun:string_decoder") propName = "__dun_cjs_string_decoder__";
        else if (specifier == "dun:timers/promises") propName = "__dun_cjs_timers_promises__";
        else if (specifier == "dun:fs/promises") propName = "__dun_cjs_fs_promises__";
        else if (specifier == "dun:vm") propName = "__dun_cjs_vm__";
        else if (specifier == "dun:cluster") propName = "__dun_cjs_cluster__";
        else if (specifier == "dun:async_hooks") propName = "__dun_cjs_async_hooks__";
        else if (specifier == "dun:worker_threads") propName = "__dun_cjs_worker_threads__";
        else if (specifier == "dun:tls") propName = "__dun_cjs_tls__";
        else if (specifier == "dun:dgram") propName = "__dun_cjs_dgram__";
        else if (specifier == "dun:perf_hooks") propName = "__dun_cjs_perf_hooks__";
        else if (specifier == "dun:wasi") propName = "__dun_cjs_wasi__";
        else if (specifier == "dun:readline") propName = "__dun_cjs_readline__";
        else if (specifier == "dun:punycode") propName = "__dun_cjs_punycode__";
        else if (specifier == "dun:diagnostics_channel") propName = "__dun_cjs_diagnostics_channel__";
        else if (specifier == "dun:domain") propName = "__dun_cjs_domain__";
        else if (specifier == "dun:tty") propName = "__dun_cjs_tty__";
        else if (specifier == "dun:constants") propName = "__dun_cjs_constants__";
        else if (specifier == "dun:module") propName = "__dun_cjs_module__";
        else if (specifier == "dun:timers") propName = "__dun_cjs_timers__";
        else if (specifier == "dun:process") propName = "__dun_cjs_process__";
        else if (specifier == "dun:console") propName = "__dun_cjs_console__";

        if (propName.length > 0)
        {
            auto builtin = engine.getProperty(global, propName);
            if (!engine.isUndefined(builtin))
                return builtin;
        }
        return engine.throwTypeError("Unknown built-in module");
    }

    string resolved;
    try
    {
        if (isAbsolute(specifier))
        {
            resolved = buildNormalizedPath(specifier);
        }
        else if (specifier.startsWith("./") || specifier.startsWith("../"))
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = buildNormalizedPath(curDir, specifier);
        }
        else
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = findNodeModule(specifier, curDir);
            if (resolved.length == 0)
                return throwModuleNotFound(engine, specifier);
        }
    }
    catch (Exception) { return throwModuleNotFound(engine, specifier); }

    try
    {
        import std.file : exists, isDir, isFile;
        if (!exists(resolved))
        {
            static immutable exts = [".js", ".ts", ".cjs", ".cts", ".json", ".node"];
            bool found = false;
            foreach (ext; exts)
            {
                if (exists(resolved ~ ext)) { resolved ~= ext; found = true; break; }
            }
            if (!found)
            {
                static immutable idxExts = ["/index.js", "/index.ts", "/index.cjs"];
                foreach (ext; idxExts)
                {
                    if (exists(resolved ~ ext)) { resolved ~= ext; break; }
                }
            }
        }
        else if (isDir(resolved))
        {
            import std.path : buildNormalizedPath;
            import std.json : parseJSON;
            import std.file : readText;
            auto pkgJson = buildNormalizedPath(resolved, "package.json");
            bool foundEntry = false;
            if (exists(pkgJson))
            {
                try
                {
                    auto j = parseJSON(readText(pkgJson));
                    auto entry = resolveMainEntry(j, resolved);
                    if (entry.length > 0) { resolved = entry; foundEntry = true; }
                }
                catch (Exception) {}
            }
            if (!foundEntry)
            {
                static immutable dirIdx = ["index.js", "index.ts", "index.cjs"];
                foreach (idx; dirIdx)
                {
                    auto p = buildNormalizedPath(resolved, idx);
                    if (exists(p) && isFile(p)) { resolved = p; break; }
                }
            }
        }
    }
    catch (Exception) {}

    auto cache = engine.getProperty(global, "__dunCjsCache__");
    auto cached = engine.getProperty(cache, resolved);
    if (!engine.isUndefined(cached))
    {
        // Cache stores module wrapper {exports: ...}, extract .exports
        if (engine.isObject(cached))
        {
            auto exportsVal = engine.getProperty(cached, "exports");
            engine.freeValue(cached);
            engine.freeValue(cache);
            return exportsVal;
        }
        engine.freeValue(cache);
        return cached;
    }
    engine.freeValue(cached);

    if (!checkPerm(state, Permission.read, resolved))
    {
        engine.freeValue(cache);
        return engine.throwTypeError("require() denied: requires --allow-read");
    }

    // JSON files: parse and return directly
    import std.algorithm : endsWith;
    if (resolved.endsWith(".json"))
    {
        try
        {
            import std.file : readText;
            auto jsonSource = readText(resolved);
            auto parseResult = engine.eval("(" ~ jsonSource ~ ")", resolved);
            if (!parseResult.isError)
            {
                auto wrapper = engine.newObject();
                engine.setProperty(wrapper, "exports", engine.dupValue(parseResult.value));
                engine.setProperty(cache, resolved, wrapper);
                engine.freeValue(cache);
                return parseResult.value;
            }
        }
        catch (Exception) {}
        return engine.throwTypeError("Failed to parse JSON module");
    }

    // Native .node addons (N-API)
    if (resolved.endsWith(".node"))
    {
        version (Posix)
        {
            if (!checkPerm(state, Permission.run, resolved))
            {
                engine.freeValue(cache);
                return engine.throwTypeError("require() denied: loading .node addons requires --allow-run");
            }
            import dun.napi.loader : loadNativeAddon;
            auto addonResult = loadNativeAddon(engine, state, resolved);
            auto wrapper = engine.newObject();
            engine.setProperty(wrapper, "exports", engine.dupValue(addonResult));
            engine.setProperty(cache, resolved, wrapper);
            engine.freeValue(cache);
            return addonResult;
        }
        else
        {
            engine.freeValue(cache);
            return engine.throwTypeError("Native addons not supported on this platform");
        }
    }

    string source;
    try
    {
        import std.file : readText;
        source = readText(resolved);
    }
    catch (Exception) { return throwModuleNotFound(engine, specifier); }

    // Comment out a leading shebang so the JS parser doesn't choke on
    // `#!/usr/bin/env node` style entry-point scripts loaded via require().
    if (source.length >= 2 && source[0] == '#' && source[1] == '!')
        source = "//" ~ source[2 .. $];

    // V8 prebuilt ships without ICU, so any `/\p{X}/u` regex LITERAL
    // throws at parse time before the runtime polyfill can wrap it.
    // Substitute Unicode property escapes with bare character classes
    // at source level. Heuristic: only run when source contains \p{ or
    // \P{; the substitution is identity inside string/comment contexts
    // because we only replace the exact escape sequence.
    version (EngineV8)
    {
        import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
        source = expandUnicodePropertyEscapes(source);
    }

    bool esmTranspiled = false;
    try
    {
        if (resolved.endsWith(".ts") || resolved.endsWith(".cts"))
        {
            import dun.ts.strip : stripTypes, generateSourceMap;
            import std.base64 : Base64;

            string sourceMap;
            source = stripTypes(source, true, sourceMap);

            if (sourceMap.length > 0)
            {
                auto encoded = Base64.encode(cast(const(ubyte)[]) sourceMap);
                source ~= "\n//# sourceMappingURL=data:application/json;base64,"
                    ~ cast(string) encoded;
            }
        }
        else if (resolved.endsWith(".mjs") || resolved.endsWith(".mts"))
        {
            import dun.modules.esm_shim : transpileESM;
            if (resolved.endsWith(".mts"))
            {
                import dun.ts.strip : stripTypes, generateSourceMap;
                string sourceMap;
                source = stripTypes(source, true, sourceMap);
            }
            source = transpileESM(source, resolved);
            esmTranspiled = true;
        }
        else if (resolved.endsWith(".js") && isEsmPackage(resolved))
        {
            import dun.modules.esm_shim : transpileESM;
            source = transpileESM(source, resolved);
            esmTranspiled = true;
        }
    }
    catch (Exception) {}

    // Push current path onto stack
    auto stack = engine.getProperty(global, "__dunCjsStack__");
    auto stackLenVal = engine.getProperty(stack, "length");
    int stackLen = engine.extractInt(stackLenVal);
    engine.freeValue(stackLenVal);
    engine.setPropertyIndex(stack, cast(uint) stackLen, engine.newString(resolved));

    string dirname_;
    try { dirname_ = dirName(resolved); } catch (Exception) { dirname_ = "."; }

    // Pre-cache a module wrapper {exports: {}} before evaluation.
    // This enables circular require: when module A is mid-evaluation and
    // module B requires A, B gets A's current module.exports (partial state).
    // The wrapper object stays in cache; module.exports mutations are visible
    // to all subsequent require() calls for this path.
    auto wrapperResult = engine.eval("({exports:{}})", "<module-wrapper>");
    assert(!wrapperResult.isError);
    engine.setProperty(cache, resolved, engine.dupValue(wrapperResult.value));

    JSHandle result;
    try
    {
        import std.string : replace;
        string escPath = resolved.replace("\\", "\\\\").replace("\"", "\\\"");
        string escDir = dirname_.replace("\\", "\\\\").replace("\"", "\\\"");

        string wrapped;
        if (esmTranspiled)
        {
            // ESM-transpiled: don't pass require as parameter (avoids conflict
            // with `const require = createRequire(...)` in transpiled source).
            // But globalThis.require used by preamble needs module context too.
            wrapped =
                "(function() {\n"
                ~ "var __m = __dunCjsCache__[\"" ~ escPath ~ "\"];\n"
                ~ "__dunCjsStack__.push(\"" ~ escPath ~ "\");\n"
                ~ "try {\n"
                ~ "(function(module, exports, __filename, __dirname) {\n"
                ~ source ~ "\n"
                ~ "})(__m, __m.exports, \""
                ~ escPath ~ "\", \""
                ~ escDir ~ "\");\n"
                ~ "} finally { __dunCjsStack__.pop(); }\n"
                ~ "return __m.exports;\n"
                ~ "})()";
        }
        else
        {
            // Create module-local require that resolves relative paths from this module's directory.
            // Reference globalThis.require (not bare `require`) so this code is
            // safe to evaluate inside an ESM module that does
            // `const require = createRequire(import.meta.url)` — bare `require`
            // hits TDZ there, since `const` declarations hoist but stay
            // uninitialized until their textual position.
            wrapped =
                "(function() {\n"
                ~ "var __m = __dunCjsCache__[\"" ~ escPath ~ "\"];\n"
                ~ "var __gReq = globalThis.require;\n"
                ~ "var __modRequire = function(id) {\n"
                ~   "__dunCjsStack__.push(\"" ~ escPath ~ "\");\n"
                ~   "try { var r = __gReq(id); __dunCjsStack__.pop(); return r; }\n"
                ~   "catch(e) { __dunCjsStack__.pop(); throw e; }\n"
                ~ "};\n"
                ~ "__modRequire.resolve = __gReq.resolve;\n"
                ~ "__modRequire.cache = __gReq.cache;\n"
                ~ "__modRequire.main = __gReq.main;\n"
                ~ "(function(module, exports, require, __filename, __dirname) {\n"
                ~ source ~ "\n"
                ~ "})(__m, __m.exports, __modRequire, \""
                ~ escPath ~ "\", \""
                ~ escDir ~ "\");\n"
                ~ "return __m.exports;\n"
                ~ "})()";
        }

        auto evalResult = engine.eval(wrapped, resolved);
        engine.freeValue(wrapperResult.value);
        if (evalResult.isError)
        {
            auto errMsg = evalResult.errorMessage;
            engine.setProperty(stack, "length", engine.newInt(stackLen));
            engine.freeValue(stack);
            engine.freeValue(cache);
            if (errMsg.length > 0)
                return engine.throwTypeError("Failed to evaluate module: " ~ errMsg);
            return engine.throwTypeError("Failed to evaluate module");
        }
        result = evalResult.value;
    }
    catch (Exception)
    {
        engine.freeValue(wrapperResult.value);
        engine.setProperty(stack, "length", engine.newInt(stackLen));
        engine.freeValue(stack);
        engine.freeValue(cache);
        return engine.throwTypeError("Failed to evaluate module");
    }

    // Pop stack
    auto newLenVal = engine.getProperty(stack, "length");
    int newLen = engine.extractInt(newLenVal);
    engine.freeValue(newLenVal);
    if (newLen > 0)
        engine.setProperty(stack, "length", engine.newInt(newLen - 1));

    engine.freeValue(stack);

    // Update wrapper's exports with final value (handles module.exports = X reassignment)
    auto wrapperCached = engine.getProperty(cache, resolved);
    engine.setProperty(wrapperCached, "exports", engine.dupValue(result));
    engine.freeValue(wrapperCached);
    engine.freeValue(cache);
    return result;
}

string getCjsStackDir(IJSEngine engine, JSHandle global) nothrow @trusted
{
    import std.path : dirName;
    try
    {
        auto stack = engine.getProperty(global, "__dunCjsStack__");
        auto lenVal = engine.getProperty(stack, "length");
        int len = engine.extractInt(lenVal);
        engine.freeValue(lenVal);
        if (len > 0)
        {
            auto topVal = engine.getPropertyIndex(stack, cast(uint)(len - 1));
            auto result = dirName(engine.extractString(topVal));
            engine.freeValue(topVal);
            engine.freeValue(stack);
            return result;
        }
        engine.freeValue(stack);
    }
    catch (Exception) {}
    try
    {
        import std.file : getcwd;
        return getcwd();
    }
    catch (Exception) { return "."; }
}

private bool isEsmPackage(string filePath) @trusted nothrow
{
    import std.path : dirName, buildNormalizedPath;
    try
    {
        auto dir = dirName(filePath);
        // Walk up looking for package.json with "type": "module"
        while (dir.length > 1)
        {
            auto pkgPath = buildNormalizedPath(dir, "package.json");
            import std.file : exists, readText;
            if (exists(pkgPath))
            {
                auto content = readText(pkgPath);
                // Simple check for "type": "module" or "type":"module"
                import std.algorithm : canFind;
                if (content.canFind(`"type":"module"`) || content.canFind(`"type": "module"`))
                    return true;
                return false;
            }
            auto parent = dirName(dir);
            if (parent == dir) break;
            dir = parent;
        }
    }
    catch (Exception) {}
    return false;
}

bool checkPerm(DunState* state, Permission perm, string resource) nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

private string resolvePackageImports(string specifier, string fromDir) @trusted
{
    import std.path : buildNormalizedPath, dirName;
    import std.file : exists, isFile, readText;
    import std.json : parseJSON, JSONType;

    string dir = fromDir;
    while (true)
    {
        auto pkgJson = buildNormalizedPath(dir, "package.json");
        if (exists(pkgJson))
        {
            try
            {
                auto j = parseJSON(readText(pkgJson));
                if ("imports" in j && j["imports"].type == JSONType.object)
                {
                    auto imports = j["imports"].object;
                    if (specifier in imports)
                        return resolveExportTarget(imports[specifier], dir);
                    foreach (key, val; imports)
                    {
                        import std.string : indexOf;
                        auto starIdx = indexOf(key, '*');
                        if (starIdx < 0) continue;
                        auto prefix = key[0 .. starIdx];
                        auto suffix = key[starIdx + 1 .. $];
                        if (specifier.length >= prefix.length + suffix.length
                            && specifier[0 .. prefix.length] == prefix
                            && (suffix.length == 0
                                || specifier[$ - suffix.length .. $] == suffix))
                        {
                            auto matched = specifier[prefix.length .. $ - suffix.length];
                            auto resolved = resolveExportTarget(val, dir, matched);
                            if (resolved.length > 0) return resolved;
                        }
                    }
                }
            }
            catch (Exception) {}
        }
        auto parent = dirName(dir);
        if (parent == dir) break;
        dir = parent;
    }
    return "";
}

public string findNodeModule(string specifier, string fromDir) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile, isDir, readText;
    import std.json : parseJSON, JSONException, JSONType;
    import std.algorithm : startsWith;

    string pkg = specifier, sub = "";
    {
        if (specifier.startsWith("@"))
        {
            // Scoped: @scope/pkg or @scope/pkg/subpath
            size_t firstSlash = specifier.length;
            foreach (i, c; specifier)
                if (i > 0 && c == '/') { firstSlash = i; break; }
            if (firstSlash < specifier.length)
            {
                size_t secondSlash = specifier.length;
                foreach (i, c; specifier)
                    if (i > firstSlash && c == '/') { secondSlash = i; break; }
                pkg = specifier[0 .. secondSlash];
                if (secondSlash < specifier.length)
                    sub = specifier[secondSlash + 1 .. $];
            }
        }
        else
        {
            auto slash = specifier.length;
            foreach (i, c; specifier)
                if (c == '/') { slash = i; break; }
            if (slash < specifier.length)
            {
                pkg = specifier[0 .. slash];
                sub = specifier[slash + 1 .. $];
            }
        }
    }

    string dir = fromDir;
    while (true)
    {
        auto nmDir = buildNormalizedPath(dir, "node_modules", pkg);
        if (exists(nmDir) && isDir(nmDir))
        {
            auto pkgJson = buildNormalizedPath(nmDir, "package.json");
            JSONValue j;
            bool hasPkgJson = false;
            if (exists(pkgJson))
            {
                try { j = parseJSON(readText(pkgJson)); hasPkgJson = true; }
                catch (Exception) {}
            }

            if (sub.length > 0)
            {
                if (hasPkgJson)
                {
                    auto exported = resolveExports(j, "./" ~ sub, nmDir);
                    if (exported.length > 0) return exported;
                }
                static immutable subExts = ["", ".js", ".cjs", ".mjs",
                    ".ts", ".cts", ".mts", ".json",
                    "/index.js", "/index.cjs", "/index.ts"];
                foreach (ext; subExts)
                {
                    auto p = buildNormalizedPath(nmDir, sub ~ ext);
                    if (exists(p) && isFile(p)) return p;
                }
            }
            else
            {
                if (hasPkgJson)
                {
                    auto exported = resolveExports(j, ".", nmDir);
                    if (exported.length > 0) return exported;

                    auto entry = resolveMainEntry(j, nmDir);
                    if (entry.length > 0) return entry;
                }
                static immutable idxCandidates = [
                    "index.js", "index.cjs", "index.mjs", "index.ts",
                    "index.json"];
                foreach (idx; idxCandidates)
                {
                    auto p = buildNormalizedPath(nmDir, idx);
                    if (exists(p) && isFile(p)) return p;
                }
            }
        }

        auto parent = buildNormalizedPath(dir, "..");
        if (parent == dir) break;
        dir = parent;
    }
    return "";
}

private string resolveExports(JSONValue j, string subpath, string pkgDir) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile;
    import std.json : JSONType;

    if ("exports" !in j) return "";
    auto exports = j["exports"];

    if (exports.type == JSONType.string)
    {
        if (subpath == ".")
        {
            auto p = buildNormalizedPath(pkgDir, exports.str);
            if (exists(p) && isFile(p)) return p;
        }
        return "";
    }

    if (exports.type != JSONType.object) return "";
    auto obj = exports.object;

    // Node.js sugar: when the exports object has no subpath keys (no "."
    // or "./..." key), treat the whole object as a condition map for ".".
    bool hasSubpathKey = false;
    foreach (key, _; obj)
    {
        if (key == "." || (key.length >= 2 && key[0 .. 2] == "./"))
        {
            hasSubpathKey = true;
            break;
        }
    }
    if (!hasSubpathKey && subpath == ".")
        return resolveExportTarget(exports, pkgDir);

    if (subpath in obj)
    {
        auto target = obj[subpath];
        return resolveExportTarget(target, pkgDir);
    }

    if ("." in obj)
    {
        auto dotExport = obj["."];
        if (subpath == ".")
            return resolveExportTarget(dotExport, pkgDir);
    }

    // Wildcard pattern matching: "./*" -> "./dist/*.js"
    foreach (key, val; obj)
    {
        import std.string : indexOf;
        auto starIdx = indexOf(key, '*');
        if (starIdx < 0) continue;
        auto prefix = key[0 .. starIdx];
        auto suffix = key[starIdx + 1 .. $];
        if (subpath.length >= prefix.length + suffix.length
            && subpath[0 .. prefix.length] == prefix
            && (suffix.length == 0 || subpath[$ - suffix.length .. $] == suffix))
        {
            auto matched = subpath[prefix.length .. $ - suffix.length];
            auto resolved = resolveExportTarget(val, pkgDir, matched);
            if (resolved.length > 0) return resolved;
        }
    }

    return "";
}

private string resolveExportTarget(JSONValue target, string pkgDir,
    string wildcardMatch = null) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile;
    import std.json : JSONType;
    import std.string : indexOf;
    import std.array : replace;

    if (target.type == JSONType.string)
    {
        string targetStr = target.str;
        if (wildcardMatch.length > 0 && indexOf(targetStr, '*') >= 0)
            targetStr = replace(targetStr, "*", wildcardMatch);
        auto p = buildNormalizedPath(pkgDir, targetStr);
        if (exists(p) && isFile(p)) return p;
        return "";
    }

    if (target.type == JSONType.object)
    {
        auto obj = target.object;
        static immutable conditions = ["dun", "require", "node", "import", "default"];
        foreach (cond; conditions)
        {
            if (cond in obj)
            {
                auto resolved = resolveExportTarget(obj[cond], pkgDir, wildcardMatch);
                if (resolved.length > 0) return resolved;
            }
        }
    }

    if (target.type == JSONType.array)
    {
        foreach (ref alt; target.array)
        {
            auto resolved = resolveExportTarget(alt, pkgDir, wildcardMatch);
            if (resolved.length > 0) return resolved;
        }
    }

    return "";
}

JSHandle throwModuleNotFound(IJSEngine engine, string specifier) @trusted
{
    auto msg = "Cannot find module '" ~ specifier ~ "'";
    auto errResult = engine.eval(
        "(function(){var e=new Error('" ~ escapeForJs(msg) ~ "');"
        ~ "e.code='MODULE_NOT_FOUND';"
        ~ "e.requireStack=[];return e;})()", "<require-error>");
    if (!errResult.isError)
    {
        auto thrown = engine.throwValue(errResult.value);
        engine.freeValue(errResult.value);
        return thrown;
    }
    engine.freeValue(errResult.value);
    return engine.throwTypeError(msg);
}

private string escapeForJs(string s) @trusted nothrow
{
    import std.array : Appender;
    Appender!(char[]) buf;
    try { buf.reserve(s.length + 10); } catch (Exception) {}
    foreach (c; s)
    {
        if (c == '\'') { try { buf.put("\\'"); } catch (Exception) {} }
        else if (c == '\\') { try { buf.put("\\\\"); } catch (Exception) {} }
        else if (c == '\n') { try { buf.put("\\n"); } catch (Exception) {} }
        else { try { buf.put(c); } catch (Exception) {} }
    }
    try { return cast(string) buf[]; } catch (Exception) { return s; }
}

private string resolveMainEntry(JSONValue j, string pkgDir) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile;

    static immutable fields = ["main", "module"];
    foreach (field; fields)
    {
        if (field in j)
        {
            try
            {
                auto entry = j[field].str;
                auto mp = buildNormalizedPath(pkgDir, entry);
                if (exists(mp) && isFile(mp)) return mp;
                if (exists(mp ~ ".js") && isFile(mp ~ ".js")) return mp ~ ".js";
                if (exists(mp ~ "/index.js") && isFile(mp ~ "/index.js"))
                    return mp ~ "/index.js";
            }
            catch (Exception) {}
        }
    }
    return "";
}
