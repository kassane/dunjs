module dun.builtins.fs;

import dun.engine.quickjs.bindings;
import dun.engine.quickjs.function_bind;

void registerFsModule(JSContext* ctx) @trusted
{
    auto m = JS_NewCModule(ctx, "dun:fs", &fsModuleInit);
    if (m is null)
        return;
    JS_AddModuleExport(ctx, m, "readFileSync");
    JS_AddModuleExport(ctx, m, "writeFileSync");
    JS_AddModuleExport(ctx, m, "existsSync");
}

private:

extern (C) int fsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow
{
    JS_SetModuleExport(ctx, m, "readFileSync",
        JS_NewCFunction(ctx, &jsReadFileSync, "readFileSync", 1));
    JS_SetModuleExport(ctx, m, "writeFileSync",
        JS_NewCFunction(ctx, &jsWriteFileSync, "writeFileSync", 2));
    JS_SetModuleExport(ctx, m, "existsSync",
        JS_NewCFunction(ctx, &jsExistsSync, "existsSync", 1));
    return 0;
}

extern (C) JSValue jsReadFileSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "readFileSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (state !is null && state.permissions !is null)
    {
        if (!checkPermission(state, dun.security.permissions.Permission.read, path))
            return JS_ThrowTypeError(ctx, "Requires --allow-read permission");
    }

    try
    {
        import std.file : readText;

        auto content = readText(path);
        return toJSValue(ctx, content);
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to read file");
    }
}

extern (C) JSValue jsWriteFileSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 2)
        return JS_ThrowTypeError(ctx, "writeFileSync requires path and data arguments");

    auto path = jsArgToString(ctx, argv[0]);
    auto data = jsArgToString(ctx, argv[1]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (state !is null && state.permissions !is null)
    {
        if (!checkPermission(state, dun.security.permissions.Permission.write, path))
            return JS_ThrowTypeError(ctx, "Requires --allow-write permission");
    }

    try
    {
        import std.file : write;

        write(path, data);
        return JS_UNDEFINED();
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to write file");
    }
}

extern (C) JSValue jsExistsSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "existsSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (state !is null && state.permissions !is null)
    {
        if (!checkPermission(state, dun.security.permissions.Permission.read, path))
            return JS_ThrowTypeError(ctx, "Requires --allow-read permission");
    }

    try
    {
        import std.file : exists;

        return JS_NewBool(ctx, exists(path) ? 1 : 0);
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

private bool checkPermission(dun.runtime.globals.DunState* state,
    dun.security.permissions.Permission perm, string resource) nothrow @trusted
{
    try
    {
        return state.permissions.check(perm, resource);
    }
    catch (Exception)
    {
        return false;
    }
}

static import dun.runtime.globals;
static import dun.security.permissions;
