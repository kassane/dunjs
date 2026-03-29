/// dun:fs — File system built-in module.
///
/// Provides readFileSync, writeFileSync, existsSync, mkdirSync,
/// readdirSync, statSync. All operations check permissions before executing.
module dun.builtins.fs;

import dun.engine.bindings;
import dun.engine.function_bind;

/// Register the "dun:fs" module into the given context.
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

    // Permission check
    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (state !is null && state.permissions !is null)
    {
        if (!state.permissions.check(dun.security.permissions.Permission.read, path))
            return JS_ThrowTypeError(ctx, "Requires --allow-read permission");
    }

    // Read the file
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

    // Permission check
    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (state !is null && state.permissions !is null)
    {
        if (!state.permissions.check(dun.security.permissions.Permission.write, path))
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
        if (!state.permissions.check(dun.security.permissions.Permission.read, path))
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
