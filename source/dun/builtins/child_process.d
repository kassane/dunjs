module dun.builtins.child_process;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;

enum MAX_BUFFER = 1024 * 1024;

void registerChildProcessModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerChildProcessModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "execSync", engine.newFunction(&jsExecSync, "execSync", 1));
    engine.setProperty(obj, "spawnSync", engine.newFunction(&jsSpawnSync, "spawnSync", 2));
    engine.setProperty(obj, "exec", engine.newFunction(&jsExec, "exec", 2));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_child_process__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:child_process", &cpModuleInit);
        if (m is null) return;
        foreach (name; ["execSync", "spawnSync", "exec"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int cpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in cpModuleInit");
        assert(m !is null, "Null JSModuleDef in cpModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto cpObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_child_process__");
        foreach (name; ["execSync", "spawnSync", "exec"])
        {
            auto fn = JS_GetPropertyStr(ctx, cpObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, cpObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

bool checkPerm(DunState* state, Permission perm, string resource = "") nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.check(perm, resource); }
    catch (Exception) { return false; }
}

JSHandle throwPermError(IJSEngine engine, string cmd) @trusted
{
    return engine.throwTypeError(
        "[ERR_PERMISSION_DENIED] Requires --allow-run permission, command '" ~ cmd ~ "'");
}

string extractCommand(string fullCmd) @trusted
{
    import std.algorithm : splitter;
    import std.uni : isWhite;
    foreach (part; fullCmd.splitter!isWhite)
    {
        if (part.length > 0) return part;
    }
    return fullCmd;
}

string extractOptString(IJSEngine engine, JSHandle opts, string key) @trusted
{
    auto val = engine.getProperty(opts, key);
    if (!engine.isUndefined(val) && !engine.isNull(val) && engine.isString(val))
        return engine.extractString(val);
    return "";
}

int extractOptInt(IJSEngine engine, JSHandle opts, string key, int def) @trusted
{
    auto val = engine.getProperty(opts, key);
    if (!engine.isUndefined(val) && !engine.isNull(val) && engine.isNumber(val))
        return engine.extractInt(val);
    return def;
}

string truncateToMaxBuffer(string s, int maxBuffer) @safe pure nothrow
{
    if (s.length > cast(size_t) maxBuffer)
        return s[0 .. cast(size_t) maxBuffer];
    return s;
}

JSHandle jsExecSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsExecSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsExecSync");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsExecSync");

    if (args.length < 1)
        return engine.throwTypeError("execSync requires a command argument");

    auto command = engine.extractString(args[0]);
    if (command.length == 0)
        return engine.throwTypeError("execSync: command must be a non-empty string");

    auto cmd = extractCommand(command);
    if (!checkPerm(state, Permission.run, cmd))
        return throwPermError(engine, cmd);

    string cwd = "";
    int maxBuffer = MAX_BUFFER;
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        cwd = extractOptString(engine, args[1], "cwd");
        maxBuffer = extractOptInt(engine, args[1], "maxBuffer", MAX_BUFFER);
    }

    try
    {
        import std.process : executeShell, Config;
        import std.file : getcwd, chdir;

        string origDir;
        if (cwd.length > 0)
        {
            origDir = getcwd();
            chdir(cwd);
        }

        auto result = executeShell(command);

        if (origDir.length > 0)
            chdir(origDir);
        auto output = truncateToMaxBuffer(result.output, maxBuffer);

        if (result.status != 0)
        {
            import std.conv : to;
            return engine.throwTypeError(
                "Command failed: " ~ command ~ "\nExit code: " ~ result.status.to!string
                ~ "\n" ~ output);
        }

        return engine.newString(output);
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}
        return engine.throwTypeError("execSync failed: " ~ msg);
    }
}

JSHandle jsSpawnSync(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSpawnSync");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSpawnSync");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsSpawnSync");

    if (args.length < 1)
        return engine.throwTypeError("spawnSync requires a command argument");

    auto command = engine.extractString(args[0]);
    if (command.length == 0)
        return engine.throwTypeError("spawnSync: command must be a non-empty string");

    if (!checkPerm(state, Permission.run, command))
        return throwPermError(engine, command);

    string[] cmdArgs;
    if (args.length >= 2 && engine.isArray(args[1]))
    {
        int len = engine.getArrayLength(args[1]);
        for (int i = 0; i < len; i++)
        {
            auto elem = engine.getPropertyIndex(args[1], cast(uint) i);
            cmdArgs ~= engine.extractString(elem);
        }
    }

    string cwd = "";
    int maxBuffer = MAX_BUFFER;
    if (args.length >= 3 && engine.isObject(args[2]))
    {
        cwd = extractOptString(engine, args[2], "cwd");
        maxBuffer = extractOptInt(engine, args[2], "maxBuffer", MAX_BUFFER);
    }

    auto resultObj = engine.newObject();

    try
    {
        import std.process : pipeProcess, Redirect, wait, Config;
        import std.file : getcwd, chdir;

        string origDir;
        if (cwd.length > 0)
        {
            origDir = getcwd();
            chdir(cwd);
        }

        string[] fullCmd = [command] ~ cmdArgs;
        auto pipes = pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr);

        string stdoutStr = "";
        string stderrStr = "";

        try
        {
            foreach (line; pipes.stdout.byLineCopy)
            {
                if (stdoutStr.length > 0) stdoutStr ~= "\n";
                stdoutStr ~= line;
            }
        }
        catch (Exception) {}

        try
        {
            foreach (line; pipes.stderr.byLineCopy)
            {
                if (stderrStr.length > 0) stderrStr ~= "\n";
                stderrStr ~= line;
            }
        }
        catch (Exception) {}

        int status = wait(pipes.pid);

        stdoutStr = truncateToMaxBuffer(stdoutStr, maxBuffer);
        stderrStr = truncateToMaxBuffer(stderrStr, maxBuffer);

        if (origDir.length > 0)
            chdir(origDir);

        engine.setProperty(resultObj, "status", engine.newInt(status));
        engine.setProperty(resultObj, "stdout", engine.newString(stdoutStr));
        engine.setProperty(resultObj, "stderr", engine.newString(stderrStr));
        engine.setProperty(resultObj, "error", engine.newNull());
        return resultObj;
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}
        engine.setProperty(resultObj, "status", engine.newNull());
        engine.setProperty(resultObj, "stdout", engine.newString(""));
        engine.setProperty(resultObj, "stderr", engine.newString(""));
        auto errObj = engine.newObject();
        engine.setProperty(errObj, "message", engine.newString(msg));
        engine.setProperty(errObj, "code", engine.newString("ENOENT"));
        engine.setProperty(resultObj, "error", errObj);
        return resultObj;
    }
}

JSHandle jsExec(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;

    assert(ctx !is null, "Null ctx in jsExec");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsExec");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsExec");

    if (args.length < 1)
        return engine.throwTypeError("exec requires a command argument");

    auto command = engine.extractString(args[0]);
    if (command.length == 0)
        return engine.throwTypeError("exec: command must be a non-empty string");

    auto cmd = extractCommand(command);
    if (!checkPerm(state, Permission.run, cmd))
        return throwPermError(engine, cmd);

    bool hasCallback = args.length >= 2 && engine.isFunction(args[1]);

    try
    {
        import std.process : executeShell;

        auto result = executeShell(command);
        auto stdout_ = truncateToMaxBuffer(result.output, MAX_BUFFER);

        if (hasCallback)
        {
            auto cb = args[1];
            if (result.status != 0)
            {
                auto errObj = engine.newObject();
                import std.conv : to;
                engine.setProperty(errObj, "message",
                    engine.newString("Command failed: " ~ command));
                engine.setProperty(errObj, "code", engine.newInt(result.status));
                engine.setProperty(errObj, "killed", engine.newBool(false));
                JSHandle[] cbArgs = [errObj, engine.newString(stdout_), engine.newString("")];
                engine.callFunction(cb, engine.newUndefined(), cbArgs);
            }
            else
            {
                JSHandle[] cbArgs = [engine.newNull(), engine.newString(stdout_), engine.newString("")];
                engine.callFunction(cb, engine.newUndefined(), cbArgs);
            }
            return engine.newUndefined();
        }

        auto ph = engine.newPromise();
        engine.dupValue(ph.resolve);
        engine.dupValue(ph.reject);

        if (result.status != 0)
        {
            auto errObj = engine.newObject();
            import std.conv : to;
            engine.setProperty(errObj, "message",
                engine.newString("Command failed: " ~ command));
            engine.setProperty(errObj, "code", engine.newInt(result.status));
            engine.setProperty(errObj, "stdout", engine.newString(stdout_));
            engine.setProperty(errObj, "stderr", engine.newString(""));
            JSHandle[] rejArgs = [errObj];
            engine.callFunction(ph.reject, engine.newUndefined(), rejArgs);
        }
        else
        {
            auto resObj = engine.newObject();
            engine.setProperty(resObj, "stdout", engine.newString(stdout_));
            engine.setProperty(resObj, "stderr", engine.newString(""));
            JSHandle[] resArgs = [resObj];
            engine.callFunction(ph.resolve, engine.newUndefined(), resArgs);
        }

        return ph.promise;
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}

        if (hasCallback)
        {
            auto errObj = engine.newObject();
            engine.setProperty(errObj, "message", engine.newString(msg));
            engine.setProperty(errObj, "code", engine.newString("ENOENT"));
            JSHandle[] cbArgs = [errObj, engine.newString(""), engine.newString("")];
            engine.callFunction(args[1], engine.newUndefined(), cbArgs);
            return engine.newUndefined();
        }
        return engine.throwTypeError("exec failed: " ~ msg);
    }
}
