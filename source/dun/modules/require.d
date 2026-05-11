module dun.modules.require;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

void installRequire(IJSEngine engine) @trusted
{
    auto global = engine.getGlobal();
    engine.setProperty(global, "require", engine.newFunction(&jsRequire, "require", 1));
    engine.setProperty(global, "__dunCjsCache__", engine.newObject());
    engine.setProperty(global, "__dunCjsStack__", engine.newArray());
}

private:

JSHandle jsRequire(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import std.algorithm : startsWith, endsWith;
    import std.path : buildNormalizedPath, isAbsolute, dirName;

    auto state = cast(DunState*) ctx;
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

    auto global = engine.getGlobal();

    if (specifier.startsWith("dun:"))
    {
        string propName;
        if (specifier == "dun:fs") propName = "__dun_cjs_fs__";
        else if (specifier == "dun:path") propName = "__dun_cjs_path__";
        else if (specifier == "dun:crypto") propName = "__dun_cjs_crypto__";
        else if (specifier == "dun:net") propName = "__dun_cjs_net__";
        else if (specifier == "dun:http") propName = "__dun_cjs_http__";

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
        import std.file : exists;
        if (!exists(resolved))
        {
            static immutable exts = [".js", ".ts", ".cjs", ".cts"];
            foreach (ext; exts)
            {
                if (exists(resolved ~ ext)) { resolved ~= ext; break; }
            }
        }
    }
    catch (Exception) {}

    auto cache = engine.getProperty(global, "__dunCjsCache__");
    auto cached = engine.getProperty(cache, resolved);
    if (!engine.isUndefined(cached))
        return cached;

    if (!checkPerm(state, Permission.read, resolved))
        return engine.throwTypeError("require() denied: requires --allow-read");

    string source;
    try
    {
        import std.file : readText;
        source = readText(resolved);
    }
    catch (Exception) { return engine.throwTypeError("Cannot find module"); }

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

    // Push current path onto stack
    auto stack = engine.getProperty(global, "__dunCjsStack__");
    auto stackLenVal = engine.getProperty(stack, "length");
    int stackLen = engine.extractInt(stackLenVal);
    import std.conv : to;
    engine.setProperty(stack, stackLen.to!string, engine.newString(resolved));

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
            return engine.throwTypeError("Failed to evaluate module");
        }
        result = evalResult.value;
    }
    catch (Exception)
    {
        engine.setProperty(stack, "length", engine.newInt(stackLen));
        return engine.throwTypeError("Failed to evaluate module");
    }

    // Pop stack
    auto newLenVal = engine.getProperty(stack, "length");
    int newLen = engine.extractInt(newLenVal);
    if (newLen > 0)
        engine.setProperty(stack, "length", engine.newInt(newLen - 1));

    // Cache
    engine.setProperty(cache, resolved, engine.dupValue(result));
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
        if (len > 0)
        {
            import std.conv : to;
            auto topVal = engine.getProperty(stack, (len - 1).to!string);
            return dirName(engine.extractString(topVal));
        }
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
    import std.json : parseJSON, JSONException;
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
            if (sub.length > 0)
            {
                static immutable exts2 = ["", ".js", ".cjs", "/index.js"];
                foreach (ext; exts2)
                {
                    auto p = buildNormalizedPath(nmDir, sub ~ ext);
                    if (exists(p) && isFile(p)) return p;
                }
            }
            else
            {
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
                            if (exists(mp ~ ".js") && isFile(mp ~ ".js")) return mp ~ ".js";
                        }
                    }
                    catch (JSONException) {}
                    catch (Exception) {}
                }
                static immutable idxCandidates = ["index.js", "index.cjs"];
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
