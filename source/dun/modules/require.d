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

JSHandle jsRequireResolve(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
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

    string[35] builtins = ["fs", "path", "crypto", "net", "http", "https",
        "http2", "http3", "os", "buffer", "events", "url", "child_process",
        "stream", "zlib", "dns", "ws", "sqlite", "util", "assert",
        "querystring", "string_decoder", "timers/promises", "tls", "dgram",
        "vm", "cluster", "async_hooks", "worker_threads", "perf_hooks",
        "fs/promises", "readline", "punycode", "diagnostics_channel", "domain"];
    foreach (b; builtins)
        if (specifier == b) return engine.newString(specifier);

    auto global = engine.getGlobal();
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
        else
        {
            string curDir = getCjsStackDir(engine, global);
            resolved = findNodeModule(specifier, curDir);
            if (resolved.length == 0)
                return engine.throwTypeError("Cannot find module '" ~ specifier ~ "'");
            return engine.newString(resolved);
        }

        if (exists(resolved) && isFile(resolved))
            return engine.newString(resolved);

        static immutable exts = [".js", ".ts", ".cjs", ".cts", ".json"];
        foreach (ext; exts)
            if (exists(resolved ~ ext) && isFile(resolved ~ ext))
                return engine.newString(resolved ~ ext);

        static immutable idxExts = ["/index.js", "/index.ts", "/index.cjs"];
        foreach (ext; idxExts)
            if (exists(resolved ~ ext) && isFile(resolved ~ ext))
                return engine.newString(resolved ~ ext);

        return engine.throwTypeError("Cannot find module '" ~ specifier ~ "'");
    }
    catch (Exception)
    {
        return engine.throwTypeError("Cannot find module '" ~ specifier ~ "'");
    }
}

JSHandle jsRequire(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
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

    if (specifier.endsWith(".mjs") || specifier.endsWith(".mts"))
        return engine.throwTypeError("Cannot require() an ES module (.mjs/.mts). Use import instead.");

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
    else if (specifier == "readline") specifier = "dun:readline";
    else if (specifier == "punycode") specifier = "dun:punycode";
    else if (specifier == "diagnostics_channel") specifier = "dun:diagnostics_channel";
    else if (specifier == "domain") specifier = "dun:domain";

    auto global = engine.getGlobal();

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
        else if (specifier == "dun:readline") propName = "__dun_cjs_readline__";
        else if (specifier == "dun:punycode") propName = "__dun_cjs_punycode__";
        else if (specifier == "dun:diagnostics_channel") propName = "__dun_cjs_diagnostics_channel__";
        else if (specifier == "dun:domain") propName = "__dun_cjs_domain__";

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
                return engine.throwTypeError("Cannot find module");
        }
    }
    catch (Exception) { return engine.throwTypeError("Failed to resolve module path"); }

    try
    {
        import std.file : exists, isDir, isFile;
        if (!exists(resolved))
        {
            static immutable exts = [".js", ".ts", ".cjs", ".cts", ".json"];
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
                engine.setProperty(cache, resolved, engine.dupValue(parseResult.value));
                engine.freeValue(cache);
                return parseResult.value;
            }
        }
        catch (Exception) {}
        return engine.throwTypeError("Failed to parse JSON module");
    }

    string source;
    try
    {
        import std.file : readText;
        source = readText(resolved);
    }
    catch (Exception) { return engine.throwTypeError("Cannot find module"); }

    try
    {
        if (resolved.endsWith(".ts") || resolved.endsWith(".cts"))
        {
            import dun.ts.strip : stripTypes;
            source = stripTypes(source);
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

    JSHandle result;
    try
    {
        import std.string : replace;
        string escPath = resolved.replace("\\", "\\\\").replace("\"", "\\\"");
        string escDir = dirname_.replace("\\", "\\\\").replace("\"", "\\\"");

        auto wrapped =
            "(function() {\n"
            ~ "var __m = {exports: {}};\n"
            ~ "(function(module, exports, require, __filename, __dirname) {\n"
            ~ source ~ "\n"
            ~ "})(__m, __m.exports, require, \""
            ~ escPath ~ "\", \""
            ~ escDir ~ "\");\n"
            ~ "return __m.exports;\n"
            ~ "})()";

        auto evalResult = engine.eval(wrapped, resolved);
        if (evalResult.isError)
        {
            engine.setProperty(stack, "length", engine.newInt(stackLen));
            engine.freeValue(stack);
            engine.freeValue(cache);
            return engine.throwTypeError("Failed to evaluate module");
        }
        result = evalResult.value;
    }
    catch (Exception)
    {
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

    // Cache
    engine.setProperty(cache, resolved, engine.dupValue(result));
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

bool checkPerm(DunState* state, Permission perm, string resource) nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

public string findNodeModule(string specifier, string fromDir) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile, isDir, readText;
    import std.json : parseJSON, JSONException, JSONType;
    import std.algorithm : startsWith;

    string pkg = specifier, sub = "";
    {
        size_t start = specifier.startsWith("@") ? 1u : 0u;
        auto slash = specifier.length;
        foreach (i, c; specifier)
        {
            if (i > start && c == '/') { slash = i; break; }
        }
        if (slash < specifier.length)
        {
            pkg = specifier[0 .. slash];
            sub = specifier[slash + 1 .. $];
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
                    ".json", "/index.js", "/index.cjs"];
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
                    "index.js", "index.cjs", "index.mjs", "index.json"];
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

    return "";
}

private string resolveExportTarget(JSONValue target, string pkgDir) @trusted
{
    import std.path : buildNormalizedPath;
    import std.file : exists, isFile;
    import std.json : JSONType;

    if (target.type == JSONType.string)
    {
        auto p = buildNormalizedPath(pkgDir, target.str);
        if (exists(p) && isFile(p)) return p;
        return "";
    }

    if (target.type == JSONType.object)
    {
        auto obj = target.object;
        static immutable conditions = ["require", "default", "node", "import"];
        foreach (cond; conditions)
        {
            if (cond in obj)
            {
                auto resolved = resolveExportTarget(obj[cond], pkgDir);
                if (resolved.length > 0) return resolved;
            }
        }
    }

    if (target.type == JSONType.array)
    {
        foreach (ref alt; target.array)
        {
            auto resolved = resolveExportTarget(alt, pkgDir);
            if (resolved.length > 0) return resolved;
        }
    }

    return "";
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
