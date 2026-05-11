module dun.builtins.fs;

version (EngineQuickJS):

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
    JS_AddModuleExport(ctx, m, "readdirSync");
    JS_AddModuleExport(ctx, m, "statSync");
    JS_AddModuleExport(ctx, m, "mkdirSync");
    JS_AddModuleExport(ctx, m, "unlinkSync");
    JS_AddModuleExport(ctx, m, "readFile");
    JS_AddModuleExport(ctx, m, "writeFile");

    // CJS-compatible object stored on globalThis for require('dun:fs') / require('fs')
    auto obj = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, obj, "readFileSync",  JS_NewCFunction(ctx, &jsReadFileSync,  "readFileSync",  1));
    JS_SetPropertyStr(ctx, obj, "writeFileSync", JS_NewCFunction(ctx, &jsWriteFileSync, "writeFileSync", 2));
    JS_SetPropertyStr(ctx, obj, "existsSync",    JS_NewCFunction(ctx, &jsExistsSync,    "existsSync",    1));
    JS_SetPropertyStr(ctx, obj, "readdirSync",   JS_NewCFunction(ctx, &jsReaddirSync,   "readdirSync",   1));
    JS_SetPropertyStr(ctx, obj, "statSync",      JS_NewCFunction(ctx, &jsStatSync,      "statSync",      1));
    JS_SetPropertyStr(ctx, obj, "mkdirSync",     JS_NewCFunction(ctx, &jsMkdirSync,     "mkdirSync",     1));
    JS_SetPropertyStr(ctx, obj, "unlinkSync",    JS_NewCFunction(ctx, &jsUnlinkSync,    "unlinkSync",    1));
    JS_SetPropertyStr(ctx, obj, "readFile",      JS_NewCFunction(ctx, &jsReadFile,      "readFile",      1));
    JS_SetPropertyStr(ctx, obj, "writeFile",     JS_NewCFunction(ctx, &jsWriteFile,     "writeFile",     2));
    auto global = JS_GetGlobalObject(ctx);
    JS_SetPropertyStr(ctx, global, "__dun_cjs_fs__", obj);
    JS_FreeValue(ctx, global);
}

private:

extern (C) int fsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
{
    JS_SetModuleExport(ctx, m, "readFileSync",
        JS_NewCFunction(ctx, &jsReadFileSync, "readFileSync", 1));
    JS_SetModuleExport(ctx, m, "writeFileSync",
        JS_NewCFunction(ctx, &jsWriteFileSync, "writeFileSync", 2));
    JS_SetModuleExport(ctx, m, "existsSync",
        JS_NewCFunction(ctx, &jsExistsSync, "existsSync", 1));
    JS_SetModuleExport(ctx, m, "readdirSync",
        JS_NewCFunction(ctx, &jsReaddirSync, "readdirSync", 1));
    JS_SetModuleExport(ctx, m, "statSync",
        JS_NewCFunction(ctx, &jsStatSync, "statSync", 1));
    JS_SetModuleExport(ctx, m, "mkdirSync",
        JS_NewCFunction(ctx, &jsMkdirSync, "mkdirSync", 1));
    JS_SetModuleExport(ctx, m, "unlinkSync",
        JS_NewCFunction(ctx, &jsUnlinkSync, "unlinkSync", 1));
    JS_SetModuleExport(ctx, m, "readFile",
        JS_NewCFunction(ctx, &jsReadFile, "readFile", 1));
    JS_SetModuleExport(ctx, m, "writeFile",
        JS_NewCFunction(ctx, &jsWriteFile, "writeFile", 2));
    return 0;
}

// --- Sync functions ---

extern (C) JSValue jsReadFileSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "readFileSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.read, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-read permission");

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
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2)
        return JS_ThrowTypeError(ctx, "writeFileSync requires path and data arguments");

    auto path = jsArgToString(ctx, argv[0]);
    auto data = jsArgToString(ctx, argv[1]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.write, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-write permission");

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
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "existsSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.read, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-read permission");

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

extern (C) JSValue jsReaddirSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "readdirSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.read, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-read permission");

    try
    {
        import std.file : dirEntries, SpanMode;
        import std.path : baseName;
        auto arr = JS_NewArray(ctx);
        uint idx = 0;
        foreach (entry; dirEntries(path, SpanMode.shallow))
        {
            auto name = toJSValue(ctx, baseName(entry.name));
            JS_SetPropertyUint32(ctx, arr, idx++, name);
        }
        return arr;
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to read directory");
    }
}

// isFile/isDirectory read the hidden _type field from `this` (set by statSync)
extern (C) JSValue jsStatIsFile(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    auto typeVal = JS_GetPropertyStr(ctx, this_val, "_type");
    int t;
    JS_ToInt32(ctx, &t, typeVal);
    JS_FreeValue(ctx, typeVal);
    return JS_NewBool(ctx, t == 1 ? 1 : 0);
}

extern (C) JSValue jsStatIsDirectory(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    auto typeVal = JS_GetPropertyStr(ctx, this_val, "_type");
    int t;
    JS_ToInt32(ctx, &t, typeVal);
    JS_FreeValue(ctx, typeVal);
    return JS_NewBool(ctx, t == 2 ? 1 : 0);
}

extern (C) JSValue jsStatSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "statSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.read, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-read permission");

    try
    {
        import std.file : exists, isFile, isDir, getSize, timeLastModified;

        bool fileExists;
        try { fileExists = exists(path); } catch (Exception) {}
        if (!fileExists)
            return JS_ThrowTypeError(ctx, "No such file or directory");

        bool pathIsFile;
        bool pathIsDir;
        ulong fileSize;
        long mtimeMs;
        try { pathIsFile = isFile(path); } catch (Exception) {}
        try { pathIsDir = isDir(path); } catch (Exception) {}
        try { fileSize = getSize(path); } catch (Exception) {}
        try
        {
            auto mt = timeLastModified(path);
            mtimeMs = mt.toUnixTime!long * 1000L;
        }
        catch (Exception) {}

        auto obj = JS_NewObject(ctx);
        JS_SetPropertyStr(ctx, obj, "_type",
            JS_NewInt32(ctx, pathIsFile ? 1 : pathIsDir ? 2 : 0));
        JS_SetPropertyStr(ctx, obj, "size",
            JS_NewFloat64(ctx, cast(double) fileSize));
        JS_SetPropertyStr(ctx, obj, "mtimeMs",
            JS_NewFloat64(ctx, cast(double) mtimeMs));
        JS_SetPropertyStr(ctx, obj, "isFile",
            JS_NewCFunction(ctx, &jsStatIsFile, "isFile", 0));
        JS_SetPropertyStr(ctx, obj, "isDirectory",
            JS_NewCFunction(ctx, &jsStatIsDirectory, "isDirectory", 0));
        return obj;
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to stat path");
    }
}

extern (C) JSValue jsMkdirSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "mkdirSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);
    bool recursive = false;

    if (argc >= 2 && JS_IsObject(argv[1]) != 0)
    {
        auto recursiveVal = JS_GetPropertyStr(ctx, argv[1], "recursive");
        recursive = JS_ToBool(ctx, recursiveVal) != 0;
        JS_FreeValue(ctx, recursiveVal);
    }

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.write, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-write permission");

    try
    {
        import std.file : mkdir, mkdirRecurse;
        if (recursive)
            mkdirRecurse(path);
        else
            mkdir(path);
        return JS_UNDEFINED();
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to create directory");
    }
}

extern (C) JSValue jsUnlinkSync(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "unlinkSync requires a path argument");

    auto path = jsArgToString(ctx, argv[0]);

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.write, path))
        return JS_ThrowTypeError(ctx, "Requires --allow-write permission");

    try
    {
        import std.file : remove;
        remove(path);
        return JS_UNDEFINED();
    }
    catch (Exception)
    {
        return JS_ThrowTypeError(ctx, "Failed to remove file");
    }
}

// --- Promise-shaped (sync-internally) ---

extern (C) JSValue jsReadFile(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "readFile requires a path argument");

    JSValue[2] resolving_funcs;
    auto promise = JS_NewPromiseCapability(ctx, resolving_funcs.ptr);
    if (JS_IsException(promise) != 0)
        return promise;

    auto path = jsArgToString(ctx, argv[0]);
    auto undef = JS_UNDEFINED();

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.read, path))
    {
        auto err = toJSValue(ctx, "Requires --allow-read permission");
        auto r = JS_Call(ctx, resolving_funcs[1], undef, 1, &err);
        JS_FreeValue(ctx, r);
        JS_FreeValue(ctx, err);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        return promise;
    }

    try
    {
        import std.file : readText;
        auto content = readText(path);
        auto jsContent = toJSValue(ctx, content);
        auto r = JS_Call(ctx, resolving_funcs[0], undef, 1, &jsContent);
        JS_FreeValue(ctx, r);
        JS_FreeValue(ctx, jsContent);
    }
    catch (Exception)
    {
        auto err = toJSValue(ctx, "Failed to read file");
        auto r = JS_Call(ctx, resolving_funcs[1], undef, 1, &err);
        JS_FreeValue(ctx, r);
        JS_FreeValue(ctx, err);
    }
    JS_FreeValue(ctx, resolving_funcs[0]);
    JS_FreeValue(ctx, resolving_funcs[1]);
    return promise;
}

extern (C) JSValue jsWriteFile(JSContext* ctx, JSValueConst this_val,
    int argc, JSValueConst* argv) nothrow @trusted
{
    if (argc < 2)
        return JS_ThrowTypeError(ctx, "writeFile requires path and data arguments");

    JSValue[2] resolving_funcs;
    auto promise = JS_NewPromiseCapability(ctx, resolving_funcs.ptr);
    if (JS_IsException(promise) != 0)
        return promise;

    auto path = jsArgToString(ctx, argv[0]);
    auto data = jsArgToString(ctx, argv[1]);
    auto undef = JS_UNDEFINED();

    auto state = cast(dun.runtime.globals.DunState*) JS_GetContextOpaque(ctx);
    if (!checkPermission(state, dun.security.permissions.Permission.write, path))
    {
        auto err = toJSValue(ctx, "Requires --allow-write permission");
        auto r = JS_Call(ctx, resolving_funcs[1], undef, 1, &err);
        JS_FreeValue(ctx, r);
        JS_FreeValue(ctx, err);
        JS_FreeValue(ctx, resolving_funcs[0]);
        JS_FreeValue(ctx, resolving_funcs[1]);
        return promise;
    }

    try
    {
        import std.file : write;
        write(path, data);
        auto r = JS_Call(ctx, resolving_funcs[0], undef, 1, &undef);
        JS_FreeValue(ctx, r);
    }
    catch (Exception)
    {
        auto err = toJSValue(ctx, "Failed to write file");
        auto r = JS_Call(ctx, resolving_funcs[1], undef, 1, &err);
        JS_FreeValue(ctx, r);
        JS_FreeValue(ctx, err);
    }
    JS_FreeValue(ctx, resolving_funcs[0]);
    JS_FreeValue(ctx, resolving_funcs[1]);
    return promise;
}

private bool checkPermission(dun.runtime.globals.DunState* state,
    dun.security.permissions.Permission perm, string resource) nothrow @trusted
{
    if (state is null || state.permissions is null)
        return false;
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
