module dun.builtins.path;

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
}

private:

extern (C) int pathModuleInit(JSContext* ctx, JSModuleDef* m) nothrow
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
    return 0;
}

extern (C) JSValue jsPathJoin(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return toJSValue(ctx, ".");

    try
    {
        import std.path : buildPath;

        string[] parts;
        for (int i = 0; i < argc; i++)
            parts ~= jsArgToString(ctx, argv[i]);

        auto result = buildPath(parts);
        return toJSValue(ctx, result);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to join paths");
    }
}

extern (C) JSValue jsPathBasename(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return toJSValue(ctx, "");

    try
    {
        import std.path : baseName;

        auto path = jsArgToString(ctx, argv[0]);
        return toJSValue(ctx, baseName(path));
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}

extern (C) JSValue jsPathDirname(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return toJSValue(ctx, ".");

    try
    {
        import std.path : dirName;

        auto path = jsArgToString(ctx, argv[0]);
        return toJSValue(ctx, dirName(path));
    }
    catch (Exception)
    {
        return toJSValue(ctx, ".");
    }
}

extern (C) JSValue jsPathExtname(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return toJSValue(ctx, "");

    try
    {
        import std.path : extension;

        auto path = jsArgToString(ctx, argv[0]);
        return toJSValue(ctx, extension(path));
    }
    catch (Exception)
    {
        return toJSValue(ctx, "");
    }
}

extern (C) JSValue jsPathIsAbsolute(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return JS_NewBool(ctx, 0);

    try
    {
        import std.path : isAbsolute;

        auto path = jsArgToString(ctx, argv[0]);
        return JS_NewBool(ctx, isAbsolute(path) ? 1 : 0);
    }
    catch (Exception)
    {
        return JS_NewBool(ctx, 0);
    }
}

private string jsArgToString(JSContext* ctx, JSValueConst val) nothrow @trusted
{
    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, val, 0);
    if (cstr is null)
        return "";
    auto result = cstr[0 .. len].idup;
    JS_FreeCString(ctx, cstr);
    return result;
}
