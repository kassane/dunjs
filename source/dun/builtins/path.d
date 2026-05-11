module dun.builtins.path;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind;

void registerPathModule(JSContext* ctx) @trusted
{
    auto m = JS_NewCModule(ctx, "dun:path", &pathModuleInit);
    if (m is null)
        return;
    JS_AddModuleExport(ctx, m, "join");
    JS_AddModuleExport(ctx, m, "basename");
    JS_AddModuleExport(ctx, m, "dirname");
    JS_AddModuleExport(ctx, m, "extname");
    JS_AddModuleExport(ctx, m, "isAbsolute");
    JS_AddModuleExport(ctx, m, "resolve");
    JS_AddModuleExport(ctx, m, "normalize");
    JS_AddModuleExport(ctx, m, "relative");
    JS_AddModuleExport(ctx, m, "parse");
    JS_AddModuleExport(ctx, m, "format");
    JS_AddModuleExport(ctx, m, "sep");
    JS_AddModuleExport(ctx, m, "delimiter");

    // CJS-compatible object stored on globalThis for require('dun:path') / require('path')
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "join",       JS_NewCFunction(ctx, &jsPathJoin,       "join",       2));
    JS_SetPropertyStr(ctx, obj, "basename",   JS_NewCFunction(ctx, &jsPathBasename,   "basename",   1));
    JS_SetPropertyStr(ctx, obj, "dirname",    JS_NewCFunction(ctx, &jsPathDirname,    "dirname",    1));
    JS_SetPropertyStr(ctx, obj, "extname",    JS_NewCFunction(ctx, &jsPathExtname,    "extname",    1));
    JS_SetPropertyStr(ctx, obj, "isAbsolute", JS_NewCFunction(ctx, &jsPathIsAbsolute, "isAbsolute", 1));
    JS_SetPropertyStr(ctx, obj, "resolve",    JS_NewCFunction(ctx, &jsPathResolve,    "resolve",    1));
    JS_SetPropertyStr(ctx, obj, "normalize",  JS_NewCFunction(ctx, &jsPathNormalize,  "normalize",  1));
    JS_SetPropertyStr(ctx, obj, "relative",   JS_NewCFunction(ctx, &jsPathRelative,   "relative",   2));
    JS_SetPropertyStr(ctx, obj, "parse",      JS_NewCFunction(ctx, &jsPathParse,      "parse",      1));
    JS_SetPropertyStr(ctx, obj, "format",     JS_NewCFunction(ctx, &jsPathFormat,     "format",     1));
    version (Windows)
    {
        JS_SetPropertyStr(ctx, obj, "sep",       JS_NewStringLen(ctx, "\\", 1));
        JS_SetPropertyStr(ctx, obj, "delimiter", JS_NewStringLen(ctx, ";",  1));
    }
    else
    {
        JS_SetPropertyStr(ctx, obj, "sep",       JS_NewStringLen(ctx, "/", 1));
        JS_SetPropertyStr(ctx, obj, "delimiter", JS_NewStringLen(ctx, ":", 1));
    }
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__dun_cjs_path__", obj);
    JS_FreeValue(ctx, global);
}

private:

extern (C) int pathModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
{
    JS_SetModuleExport(ctx, m, "join",
        JS_NewCFunction(ctx, &jsPathJoin, "join", 2));
    JS_SetModuleExport(ctx, m, "basename",
        JS_NewCFunction(ctx, &jsPathBasename, "basename", 1));
    JS_SetModuleExport(ctx, m, "dirname",
        JS_NewCFunction(ctx, &jsPathDirname, "dirname", 1));
    JS_SetModuleExport(ctx, m, "extname",
        JS_NewCFunction(ctx, &jsPathExtname, "extname", 1));
    JS_SetModuleExport(ctx, m, "isAbsolute",
        JS_NewCFunction(ctx, &jsPathIsAbsolute, "isAbsolute", 1));
    JS_SetModuleExport(ctx, m, "resolve",
        JS_NewCFunction(ctx, &jsPathResolve, "resolve", 1));
    JS_SetModuleExport(ctx, m, "normalize",
        JS_NewCFunction(ctx, &jsPathNormalize, "normalize", 1));
    JS_SetModuleExport(ctx, m, "relative",
        JS_NewCFunction(ctx, &jsPathRelative, "relative", 2));
    JS_SetModuleExport(ctx, m, "parse",
        JS_NewCFunction(ctx, &jsPathParse, "parse", 1));
    JS_SetModuleExport(ctx, m, "format",
        JS_NewCFunction(ctx, &jsPathFormat, "format", 1));

    version (Windows)
    {
        JS_SetModuleExport(ctx, m, "sep",
            JS_NewStringLen(ctx, "\\", 1));
        JS_SetModuleExport(ctx, m, "delimiter",
            JS_NewStringLen(ctx, ";", 1));
    }
    else
    {
        JS_SetModuleExport(ctx, m, "sep",
            JS_NewStringLen(ctx, "/", 1));
        JS_SetModuleExport(ctx, m, "delimiter",
            JS_NewStringLen(ctx, ":", 1));
    }
    return 0;
}

extern (C) JSValue jsPathJoin(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return toJSValue(ctx, ".");

    try
    {
        import std.path : buildNormalizedPath;

        string[] parts;
        for (int i = 0; i < argc; i++)
            parts ~= jsArgToString(ctx, argv[i]);

        auto result = buildNormalizedPath(parts);
        return toJSValue(ctx, result);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to join paths");
    }
}

extern (C) JSValue jsPathBasename(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return toJSValue(ctx, "");

    try
    {
        import std.path : baseName;
        auto p = jsArgToString(ctx, argv[0]);
        // Optional second arg: suffix to strip
        if (argc >= 2)
        {
            auto suffix = jsArgToString(ctx, argv[1]);
            return toJSValue(ctx, baseName(p, suffix));
        }
        return toJSValue(ctx, baseName(p));
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}

extern (C) JSValue jsPathDirname(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return toJSValue(ctx, ".");

    try
    {
        import std.path : dirName;
        return toJSValue(ctx, dirName(jsArgToString(ctx, argv[0])));
    }
    catch (Exception)
    {
        return toJSValue(ctx, ".");
    }
}

extern (C) JSValue jsPathExtname(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return toJSValue(ctx, "");

    try
    {
        import std.path : extension;
        return toJSValue(ctx, extension(jsArgToString(ctx, argv[0])));
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}

extern (C) JSValue jsPathIsAbsolute(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_NewBool(ctx, 0);

    try
    {
        import std.path : isAbsolute;
        return JS_NewBool(ctx, isAbsolute(jsArgToString(ctx, argv[0])) ? 1 : 0);
    }
    catch (Exception)
    {
        return JS_NewBool(ctx, 0);
    }
}

extern (C) JSValue jsPathResolve(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    try
    {
        import std.path : buildNormalizedPath, isAbsolute;
        import std.file : getcwd;

        // Process args right-to-left; stop when an absolute path is found
        string[] parts;
        for (int i = argc - 1; i >= 0; i--)
        {
            auto p = jsArgToString(ctx, argv[i]);
            parts = p ~ parts;
            if (isAbsolute(p))
                break;
        }

        // Prepend cwd if result is still relative
        string result = buildNormalizedPath(parts);
        if (!isAbsolute(result))
            result = buildNormalizedPath(getcwd(), result);

        return toJSValue(ctx, result);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to resolve path");
    }
}

extern (C) JSValue jsPathNormalize(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return toJSValue(ctx, ".");

    try
    {
        import std.path : buildNormalizedPath;
        return toJSValue(ctx, buildNormalizedPath(jsArgToString(ctx, argv[0])));
    }
    catch (Exception)
    {
        return toJSValue(ctx, ".");
    }
}

extern (C) JSValue jsPathRelative(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2)
        return toJSValue(ctx, "");

    try
    {
        import std.path : relativePath;
        // Node.js: relative(from, to); D: relativePath(path=to, base=from)
        auto from_ = jsArgToString(ctx, argv[0]);
        auto to_ = jsArgToString(ctx, argv[1]);
        return toJSValue(ctx, relativePath(to_, from_));
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}

extern (C) JSValue jsPathParse(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "parse requires a path argument");

    try
    {
        import std.path : driveName, rootName, dirName, baseName,
            extension, stripExtension;

        auto p = jsArgToString(ctx, argv[0]);
        auto root = driveName(p) ~ rootName(p);
        auto dir = dirName(p);
        auto base = baseName(p);
        auto ext = extension(p);
        auto name = stripExtension(base);

        auto obj = JS_NewObject(ctx);
        JS_SetPropertyStr(ctx, obj, "root", toJSValue(ctx, root));
        JS_SetPropertyStr(ctx, obj, "dir",  toJSValue(ctx, dir));
        JS_SetPropertyStr(ctx, obj, "base", toJSValue(ctx, base));
        JS_SetPropertyStr(ctx, obj, "ext",  toJSValue(ctx, ext));
        JS_SetPropertyStr(ctx, obj, "name", toJSValue(ctx, name));
        return obj;
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to parse path");
    }
}

extern (C) JSValue jsPathFormat(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1 || JS_IsObject(argv[0]) == 0)
        return toJSValue(ctx, "");

    try
    {
        import std.path : buildPath;

        auto getProp = (const(char)* key) nothrow @trusted {
            auto val = JS_GetPropertyStr(ctx, argv[0], key);
            auto s = jsArgToString(ctx, val);
            JS_FreeValue(ctx, val);
            return s;
        };

        auto dir  = getProp("dir");
        auto root = getProp("root");
        auto base = getProp("base");
        auto name = getProp("name");
        auto ext  = getProp("ext");

        string filename = base.length > 0 ? base : name ~ ext;

        string result;
        if (dir.length > 0)
            result = buildPath(dir, filename);
        else if (root.length > 0)
            result = root ~ filename;
        else
            result = filename;

        return toJSValue(ctx, result);
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}
