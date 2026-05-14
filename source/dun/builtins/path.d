module dun.builtins.path;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerPathModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerPathModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "join", engine.newFunction(&jsPathJoin, "join", 2));
    engine.setProperty(obj, "basename", engine.newFunction(&jsPathBasename, "basename", 1));
    engine.setProperty(obj, "dirname", engine.newFunction(&jsPathDirname, "dirname", 1));
    engine.setProperty(obj, "extname", engine.newFunction(&jsPathExtname, "extname", 1));
    engine.setProperty(obj, "isAbsolute", engine.newFunction(&jsPathIsAbsolute, "isAbsolute", 1));
    engine.setProperty(obj, "resolve", engine.newFunction(&jsPathResolve, "resolve", 1));
    engine.setProperty(obj, "normalize", engine.newFunction(&jsPathNormalize, "normalize", 1));
    engine.setProperty(obj, "relative", engine.newFunction(&jsPathRelative, "relative", 2));
    engine.setProperty(obj, "parse", engine.newFunction(&jsPathParse, "parse", 1));
    engine.setProperty(obj, "format", engine.newFunction(&jsPathFormat, "format", 1));

    version (Windows)
    {
        engine.setProperty(obj, "sep", engine.newString("\\"));
        engine.setProperty(obj, "delimiter", engine.newString(";"));
    }
    else
    {
        engine.setProperty(obj, "sep", engine.newString("/"));
        engine.setProperty(obj, "delimiter", engine.newString(":"));
    }

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_path__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:path", &pathModuleInit);
        if (m is null) return;
        foreach (name; ["join", "basename", "dirname", "extname", "isAbsolute",
                        "resolve", "normalize", "relative", "parse", "format", "sep", "delimiter"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int pathModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in pathModuleInit");
        assert(m !is null, "Null JSModuleDef in pathModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto pathObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_path__");
        foreach (name; ["join", "basename", "dirname", "extname", "isAbsolute",
                        "resolve", "normalize", "relative", "parse", "format", "sep", "delimiter"])
        {
            auto fn = JS_GetPropertyStr(ctx, pathObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, pathObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

JSHandle jsPathJoin(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathJoin");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathJoin");
    auto engine = state.engine;
    if (args.length < 1) return engine.newString(".");
    try
    {
        import std.path : buildNormalizedPath;
        string[] parts;
        foreach (arg; args)
            parts ~= engine.extractString(arg);
        return engine.newString(buildNormalizedPath(parts));
    }
    catch (Exception) { return engine.throwTypeError("Failed to join paths"); }
}

JSHandle jsPathBasename(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathBasename");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathBasename");
    auto engine = state.engine;
    if (args.length < 1) return engine.newString("");
    try
    {
        import std.path : baseName;
        auto p = engine.extractString(args[0]);
        if (args.length >= 2)
            return engine.newString(baseName(p, engine.extractString(args[1])));
        return engine.newString(baseName(p));
    }
    catch (Exception) { return engine.newString(""); }
}

JSHandle jsPathDirname(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathDirname");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathDirname");
    auto engine = state.engine;
    if (args.length < 1) return engine.newString(".");
    try
    {
        import std.path : dirName;
        return engine.newString(dirName(engine.extractString(args[0])));
    }
    catch (Exception) { return engine.newString("."); }
}

JSHandle jsPathExtname(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathExtname");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathExtname");
    auto engine = state.engine;
    if (args.length < 1) return engine.newString("");
    try
    {
        import std.path : extension;
        return engine.newString(extension(engine.extractString(args[0])));
    }
    catch (Exception) { return engine.newString(""); }
}

JSHandle jsPathIsAbsolute(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathIsAbsolute");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathIsAbsolute");
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    try
    {
        import std.path : isAbsolute;
        return engine.newBool(isAbsolute(engine.extractString(args[0])));
    }
    catch (Exception) { return engine.newBool(false); }
}

JSHandle jsPathResolve(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathResolve");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathResolve");
    auto engine = state.engine;
    try
    {
        import std.path : buildNormalizedPath, isAbsolute;
        import std.file : getcwd;
        string[] parts;
        for (int i = cast(int) args.length - 1; i >= 0; i--)
        {
            auto p = engine.extractString(args[i]);
            parts = p ~ parts;
            if (isAbsolute(p)) break;
        }
        string result = buildNormalizedPath(parts);
        if (!isAbsolute(result))
            result = buildNormalizedPath(getcwd(), result);
        return engine.newString(result);
    }
    catch (Exception) { return engine.throwTypeError("Failed to resolve path"); }
}

JSHandle jsPathNormalize(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathNormalize");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathNormalize");
    auto engine = state.engine;
    if (args.length < 1) return engine.newString(".");
    try
    {
        import std.path : buildNormalizedPath;
        return engine.newString(buildNormalizedPath(engine.extractString(args[0])));
    }
    catch (Exception) { return engine.newString("."); }
}

JSHandle jsPathRelative(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathRelative");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathRelative");
    auto engine = state.engine;
    if (args.length < 2) return engine.newString("");
    try
    {
        import std.path : relativePath;
        return engine.newString(relativePath(engine.extractString(args[1]), engine.extractString(args[0])));
    }
    catch (Exception) { return engine.newString(""); }
}

JSHandle jsPathParse(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathParse");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathParse");
    auto engine = state.engine;
    if (args.length < 1) return engine.throwTypeError("parse requires a path argument");
    try
    {
        import std.path : driveName, rootName, dirName, baseName, extension, stripExtension;
        auto p = engine.extractString(args[0]);
        auto root = driveName(p) ~ rootName(p);
        auto dir = dirName(p);
        auto base = baseName(p);
        auto ext = extension(p);
        auto name = stripExtension(base);
        auto obj = engine.newObject();
        engine.setProperty(obj, "root", engine.newString(root));
        engine.setProperty(obj, "dir", engine.newString(dir));
        engine.setProperty(obj, "base", engine.newString(base));
        engine.setProperty(obj, "ext", engine.newString(ext));
        engine.setProperty(obj, "name", engine.newString(name));
        return obj;
    }
    catch (Exception) { return engine.throwTypeError("Failed to parse path"); }
}

JSHandle jsPathFormat(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsPathFormat");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsPathFormat");
    auto engine = state.engine;
    if (args.length < 1 || !engine.isObject(args[0])) return engine.newString("");
    try
    {
        import std.path : buildPath;
        auto dir = engine.extractString(engine.getProperty(args[0], "dir"));
        auto root = engine.extractString(engine.getProperty(args[0], "root"));
        auto base = engine.extractString(engine.getProperty(args[0], "base"));
        auto name = engine.extractString(engine.getProperty(args[0], "name"));
        auto ext = engine.extractString(engine.getProperty(args[0], "ext"));
        string filename = base.length > 0 ? base : name ~ ext;
        string result;
        if (dir.length > 0) result = buildPath(dir, filename);
        else if (root.length > 0) result = root ~ filename;
        else result = filename;
        return engine.newString(result);
    }
    catch (Exception) { return engine.newString(""); }
}
