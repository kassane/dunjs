module dun.modules.require;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind;

/// Installs the global require() function and supporting state.
void installRequire(JSContext* ctx) @trusted
{
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "require",
        JS_NewCFunction(ctx, &jsRequire, "require", 1));
    JS_SetPropertyStr(ctx, global, "__dunCjsCache__", JS_NewObject(ctx));
    // Stack of currently-loading file paths (for relative require resolution)
    JS_SetPropertyStr(ctx, global, "__dunCjsStack__", JS_NewArray(ctx));
    JS_FreeValue(ctx, global);
}

private:

extern (C) JSValue jsRequire(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    import std.algorithm : startsWith, endsWith;
    import std.string : toStringz;
    import std.path : buildNormalizedPath, isAbsolute, dirName;

    if (argc < 1)
        return JS_ThrowTypeError(ctx, "require() needs at least 1 argument");

    string specifier;
    try
    {
        specifier = jsArgToString(ctx, argv[0]);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "require() argument must be a string");
    }

    // ESM guard: .mjs / .mts cannot be require()'d
    if (specifier.endsWith(".mjs") || specifier.endsWith(".mts"))
    {
        return JS_ThrowTypeError(ctx,
            "Cannot require() an ES module (.mjs/.mts). Use import instead.");
    }

    // Normalise node:/bare builtin names -> dun: namespace
    if (specifier.startsWith("node:"))
        specifier = "dun:" ~ specifier[5 .. $];
    else if (specifier == "fs")
        specifier = "dun:fs";
    else if (specifier == "path")
        specifier = "dun:path";
    else if (specifier == "crypto")
        specifier = "dun:crypto";
    else if (specifier == "net")
        specifier = "dun:net";
    else if (specifier == "http")
        specifier = "dun:http";

    auto global = JS_GetGlobalObject(ctx);

    // --- Built-in lookup via pre-stored globals ---
    if (specifier.startsWith("dun:"))
    {
        string propName;
        if (specifier == "dun:fs")      propName = "__dun_cjs_fs__";
        else if (specifier == "dun:path")   propName = "__dun_cjs_path__";
        else if (specifier == "dun:crypto") propName = "__dun_cjs_crypto__";
        else if (specifier == "dun:net")    propName = "__dun_cjs_net__";
        else if (specifier == "dun:http")   propName = "__dun_cjs_http__";

        if (propName.length > 0)
        {
            auto builtin = JS_GetPropertyStr(ctx, global, propName.toStringz);
            JS_FreeValue(ctx, global);
            if (!JS_IsUndefined(builtin))
                return builtin;
            JS_FreeValue(ctx, builtin);
        }
        JS_FreeValue(ctx, global);
        return JS_ThrowTypeError(ctx, "Unknown built-in module");
    }

    // --- Resolve path relative to current loading file ---
    string resolved;
    try
    {
        if (isAbsolute(specifier))
        {
            resolved = buildNormalizedPath(specifier);
        }
        else if (specifier.startsWith("./") || specifier.startsWith("../"))
        {
            // Read current directory from the stack top
            auto stack = JS_GetPropertyStr(ctx, global, "__dunCjsStack__");
            int len;
            auto lenVal = JS_GetPropertyStr(ctx, stack, "length");
            JS_ToInt32(ctx, &len, lenVal);
            JS_FreeValue(ctx, lenVal);

            string curDir;
            if (len > 0)
            {
                auto topVal = JS_GetPropertyUint32(ctx, stack, cast(uint)(len - 1));
                curDir = jsArgToString(ctx, topVal);
                JS_FreeValue(ctx, topVal);
                curDir = dirName(curDir);
            }
            else
            {
                import std.file : getcwd;
                try { curDir = getcwd(); } catch (Exception) { curDir = "."; }
            }
            JS_FreeValue(ctx, stack);
            resolved = buildNormalizedPath(curDir, specifier);
        }
        else
        {
            // node_modules resolution: walk up directory tree
            string curDir;
            try
            {
                auto stack = JS_GetPropertyStr(ctx, global, "__dunCjsStack__");
                int len;
                auto lenVal = JS_GetPropertyStr(ctx, stack, "length");
                JS_ToInt32(ctx, &len, lenVal);
                JS_FreeValue(ctx, lenVal);
                if (len > 0)
                {
                    auto topVal = JS_GetPropertyUint32(ctx, stack, cast(uint)(len - 1));
                    string top = jsArgToString(ctx, topVal);
                    JS_FreeValue(ctx, topVal);
                    curDir = dirName(top);
                }
                else
                {
                    import std.file : getcwd;
                    try { curDir = getcwd(); } catch (Exception) { curDir = "."; }
                }
                JS_FreeValue(ctx, stack);
            }
            catch (Exception)
            {
                import std.file : getcwd;
                try { curDir = getcwd(); } catch (Exception) { curDir = "."; }
            }

            resolved = findNodeModule(specifier, curDir);
            if (resolved.length == 0)
            {
                JS_FreeValue(ctx, global);
                return JS_ThrowTypeError(ctx, "Cannot find module");
            }
        }
    }
    catch (Exception)
    {
        JS_FreeValue(ctx, global);
        return JS_ThrowTypeError(ctx, "Failed to resolve module path");
    }

    // --- Extension resolution (try .js / .ts / .cjs / .cts if no match) ---
    try
    {
        import std.file : exists;
        if (!exists(resolved))
        {
            static immutable exts = [".js", ".ts", ".cjs", ".cts"];
            foreach (ext; exts)
            {
                if (exists(resolved ~ ext))
                {
                    resolved ~= ext;
                    break;
                }
            }
        }
    }
    catch (Exception) {}

    // --- Cache check ---
    auto cache = JS_GetPropertyStr(ctx, global, "__dunCjsCache__");
    auto cached = JS_GetPropertyStr(ctx, cache, resolved.toStringz);
    if (!JS_IsUndefined(cached))
    {
        JS_FreeValue(ctx, cache);
        JS_FreeValue(ctx, global);
        return cached;
    }
    JS_FreeValue(ctx, cached);

    // --- Permission check ---
    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    {
        bool allowed = false;
        if (state !is null && state.permissions !is null)
        {
            try { allowed = state.permissions.check(dun.security.permissions.Permission.read, resolved); }
            catch (Exception) { allowed = false; }
        }
        if (!allowed)
        {
            JS_FreeValue(ctx, cache);
            JS_FreeValue(ctx, global);
            return JS_ThrowTypeError(ctx, "require() denied: requires --allow-read");
        }
    }

    // --- Read source ---
    string source;
    try
    {
        import std.file : readText;
        source = readText(resolved);
    }
    catch (Exception)
    {
        JS_FreeValue(ctx, cache);
        JS_FreeValue(ctx, global);
        return JS_ThrowTypeError(ctx, "Cannot find module");
    }

    // --- Strip TypeScript types for .ts / .cts ---
    try
    {
        import std.algorithm : endsWith;
        if (resolved.endsWith(".ts") || resolved.endsWith(".cts"))
        {
            import dun.ts.strip : stripTypes;
            source = stripTypes(source);
        }
    }
    catch (Exception) {}

    // --- Push current path onto require stack ---
    auto stack = JS_GetPropertyStr(ctx, global, "__dunCjsStack__");
    int stackLen;
    auto lenVal = JS_GetPropertyStr(ctx, stack, "length");
    JS_ToInt32(ctx, &stackLen, lenVal);
    JS_FreeValue(ctx, lenVal);
    JS_SetPropertyUint32(ctx, stack, cast(uint) stackLen, toJSValue(ctx, resolved));
    JS_FreeValue(ctx, stack);

    // --- Wrap in CJS module pattern and eval ---
    // Returns module.exports as last expression
    string dirname_;
    try { dirname_ = dirName(resolved); } catch (Exception) { dirname_ = "."; }

    JSValue result;
    try
    {
        import std.string : replace;
        import std.conv : text;

        // Escape backslashes and quotes in paths for embedding in JS string literal
        string escPath = resolved.replace("\\", "\\\\").replace("\"", "\\\"");
        string escDir  = dirname_.replace("\\", "\\\\").replace("\"", "\\\"");

        auto wrapped =
            "(function() {\n"
            ~ "var __m = {exports: {}};\n"
            ~ "(function(module, exports, require, __filename, __dirname) {\n"
            ~ source ~ "\n"
            ~ "})(__m, __m.exports, require, \""
            ~ escPath ~ "\", \""
            ~ escDir  ~ "\");\n"
            ~ "return __m.exports;\n"
            ~ "})()";

        result = JS_Eval(ctx, wrapped.toStringz, wrapped.length,
            resolved.toStringz, JS_EVAL_TYPE_GLOBAL);
    }
    catch (Exception)
    {
        // Pop stack on error
        auto s2 = JS_GetPropertyStr(ctx, global, "__dunCjsStack__");
        JS_SetPropertyStr(ctx, s2, "length", JS_NewInt32(ctx, stackLen));
        JS_FreeValue(ctx, s2);
        JS_FreeValue(ctx, cache);
        JS_FreeValue(ctx, global);
        return JS_ThrowTypeError(ctx, "Failed to evaluate module");
    }

    // --- Pop require stack ---
    auto s2 = JS_GetPropertyStr(ctx, global, "__dunCjsStack__");
    int newLen;
    auto nlenVal = JS_GetPropertyStr(ctx, s2, "length");
    JS_ToInt32(ctx, &newLen, nlenVal);
    JS_FreeValue(ctx, nlenVal);
    if (newLen > 0)
        JS_SetPropertyStr(ctx, s2, "length", JS_NewInt32(ctx, newLen - 1));
    JS_FreeValue(ctx, s2);

    if (JS_IsException(result) != 0)
    {
        JS_FreeValue(ctx, cache);
        JS_FreeValue(ctx, global);
        return result;
    }

    // Cache and return
    JS_SetPropertyStr(ctx, cache, resolved.toStringz, JS_DupValue(ctx, result));
    JS_FreeValue(ctx, cache);
    JS_FreeValue(ctx, global);
    return result;
}

// Walk up directory tree looking for node_modules/specifier/index.js
// (or package.json "main" field). Returns resolved path or empty string.
public string findNodeModule(string specifier, string fromDir) @trusted
{
    import std.path : buildNormalizedPath, isAbsolute;
    import std.file : exists, isFile, isDir, readText;
    import std.json : parseJSON, JSONException;
    import std.algorithm : startsWith;

    // Split off subpath (e.g. "lodash/fp" → pkg="lodash", sub="fp")
    string pkg = specifier, sub = "";
    {
        // scoped packages: @scope/name
        size_t start = specifier.startsWith("@") ? 1u : 0u;
        auto slash = specifier.length;
        foreach (i, c; specifier)
        {
            if (i > start && c == '/')
            {
                slash = i;
                break;
            }
        }
        if (slash < specifier.length)
        {
            pkg = specifier[0 .. slash];
            sub = specifier[slash + 1 .. $];
        }
    }

    // Walk up from fromDir
    string dir = fromDir;
    while (true)
    {
        auto nmDir = buildNormalizedPath(dir, "node_modules", pkg);
        if (exists(nmDir) && isDir(nmDir))
        {
            if (sub.length > 0)
            {
                // Explicit subpath
                static immutable exts2 = ["", ".js", ".cjs", "/index.js"];
                foreach (ext; exts2)
                {
                    auto p = buildNormalizedPath(nmDir, sub ~ ext);
                    if (exists(p) && isFile(p)) return p;
                }
            }
            else
            {
                // Check package.json "main"
                auto pkgJson = buildNormalizedPath(nmDir, "package.json");
                if (exists(pkgJson))
                {
                    try
                    {
                        auto j = parseJSON(readText(pkgJson));
                        if ("main" in j)
                        {
                            auto main = j["main"].str;
                            auto mp = buildNormalizedPath(nmDir, main);
                            if (exists(mp) && isFile(mp)) return mp;
                            // try adding .js
                            if (exists(mp ~ ".js") && isFile(mp ~ ".js"))
                                return mp ~ ".js";
                        }
                    }
                    catch (JSONException) {}
                    catch (Exception) {}
                }
                // Fall back to index.js
                static immutable idxCandidates = ["index.js", "index.cjs"];
                foreach (idx; idxCandidates)
                {
                    auto p = buildNormalizedPath(nmDir, idx);
                    if (exists(p) && isFile(p)) return p;
                }
            }
        }

        // Move up one level
        auto parent = buildNormalizedPath(dir, "..");
        if (parent == dir) break; // filesystem root
        dir = parent;
    }
    return "";
}

static import dun.runtime.globals;
static import dun.security.permissions;
