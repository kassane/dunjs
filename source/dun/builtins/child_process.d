module dun.builtins.child_process;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.security.permissions : Permission;
// Project convention (CLAUDE.md): allocator helpers go via
// `dun.platform.arena`, not `std.array` directly.
import dun.platform.arena : Appender;

enum MAX_BUFFER = 1024 * 1024;

string readAllFromPipe(P)(P pipe) @trusted
{
    Appender!(ubyte[]) buf;
    enum CHUNK = 4096;
    ubyte[CHUNK] tmp;
    while (true)
    {
        auto chunk = pipe.rawRead(tmp[]);
        if (chunk.length == 0) break;
        buf.put(chunk);
    }
    return cast(string) buf[];
}

void registerChildProcessModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerChildProcessModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "execSync", engine.newFunction(&jsExecSync, "execSync", 1));
    engine.setProperty(obj, "spawnSync", engine.newFunction(&jsSpawnSync, "spawnSync", 2));
    engine.setProperty(obj, "exec", engine.newFunction(&jsExec, "exec", 2));
    engine.setProperty(obj, "spawn", engine.newFunction(&jsSpawn, "spawn", 2));
    engine.setProperty(obj, "execFile", engine.newFunction(&jsExecFile, "execFile", 3));
    engine.setProperty(obj, "execFileSync", engine.newFunction(&jsExecFileSync, "execFileSync", 2));
    engine.setProperty(obj, "fork", engine.newFunction(&jsFork, "fork", 2));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_child_process__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private static immutable cpExportNames = [
        "execSync", "spawnSync", "exec", "spawn", "execFile",
        "execFileSync", "fork"
    ];

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:child_process", &cpModuleInit);
        if (m is null) return;
        foreach (name; cpExportNames)
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int cpModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in cpModuleInit");
        assert(m !is null, "Null JSModuleDef in cpModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto cpObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_child_process__");
        foreach (name; cpExportNames)
        {
            auto fn = JS_GetPropertyStr(ctx, cpObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", cpObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

bool hasGlobalRun(DunState* state) nothrow @trusted
{
    if (state is null || state.permissions is null) return false;
    try { return state.permissions.isGlobalGrant(Permission.run); }
    catch (Exception) { return false; }
}

public import dun.security.permissions : checkPerm;

JSHandle throwPermError(IJSEngine engine, string cmd) @trusted
{
    return engine.throwTypeError(
        "[ERR_PERMISSION_DENIED] Requires --allow-run permission, command '" ~ cmd ~ "'");
}

string extractCommand(string fullCmd) @safe
{
    import std.algorithm : splitter;
    import std.uni : isWhite;
    foreach (part; fullCmd.splitter!isWhite)
    {
        if (part.length > 0) return part;
    }
    return fullCmd;
}

bool hasShellMetaChars(string cmd) @safe pure nothrow
{
    foreach (ch; cmd)
    {
        switch (ch)
        {
            case ';': case '&': case '|': case '$':
            case '`': case '(': case ')': case '{':
            case '}': case '<': case '>': case '\n':
                return true;
            default: break;
        }
    }
    return false;
}

string extractOptString(IJSEngine engine, JSHandle opts, string key) @trusted
{
    auto val = engine.getProperty(opts, key);
    scope(exit) engine.freeValue(val);
    if (!engine.isUndefined(val) && !engine.isNull(val) && engine.isString(val))
        return engine.extractString(val);
    return "";
}

int extractOptInt(IJSEngine engine, JSHandle opts, string key, int def) @trusted
{
    auto val = engine.getProperty(opts, key);
    scope(exit) engine.freeValue(val);
    if (!engine.isUndefined(val) && !engine.isNull(val) && engine.isNumber(val))
        return engine.extractInt(val);
    return def;
}

string[string] extractOptEnv(IJSEngine engine, JSHandle opts) @trusted
{
    string[string] result;
    auto envVal = engine.getProperty(opts, "env");
    scope(exit) engine.freeValue(envVal);
    if (engine.isUndefined(envVal) || engine.isNull(envVal) || !engine.isObject(envVal))
        return result;
    auto keysResult = engine.eval(
        `(function(o) { return Object.keys(o); })`, "<env-keys>");
    if (keysResult.isError) { engine.freeValue(keysResult.value); return result; }
    auto undef = engine.newUndefined();
    JSHandle[1] callArgs = [envVal];
    auto keysArr = engine.callFunction(keysResult.value, undef, callArgs[]);
    engine.freeValue(keysResult.value);
    engine.freeValue(undef);
    if (engine.isArray(keysArr))
    {
        int len = engine.getArrayLength(keysArr);
        for (int i = 0; i < len; i++)
        {
            auto keyH = engine.getPropertyIndex(keysArr, cast(uint) i);
            auto key = engine.extractString(keyH);
            engine.freeValue(keyH);
            auto valH = engine.getProperty(envVal, key);
            result[key] = engine.extractString(valH);
            engine.freeValue(valH);
        }
    }
    engine.freeValue(keysArr);
    return result;
}

string truncateToMaxBuffer(string s, int maxBuffer) @safe pure nothrow
{
    if (s.length > cast(size_t) maxBuffer)
        return s[0 .. cast(size_t) maxBuffer];
    return s;
}

JSHandle jsExecSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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

    if (hasShellMetaChars(command) && !hasGlobalRun(state))
        return engine.throwTypeError(
            "execSync: shell metacharacters require --allow-run (global)");

    string cwd = "";
    int maxBuffer = MAX_BUFFER;
    string encoding = "";
    if (args.length >= 2 && engine.isObject(args[1]))
    {
        cwd = extractOptString(engine, args[1], "cwd");
        maxBuffer = extractOptInt(engine, args[1], "maxBuffer", MAX_BUFFER);
        encoding = extractOptString(engine, args[1], "encoding");
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

        if (encoding.length > 0)
            return engine.newString(output);
        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, cast(const(ubyte)[]) output);
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}
        return engine.throwTypeError("execSync failed: " ~ msg);
    }
}

JSHandle jsSpawnSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
            engine.freeValue(elem);
        }
    }

    string cwd = "";
    int maxBuffer = MAX_BUFFER;
    string[string] envMap;
    bool hasEnv = false;
    string encoding = "";
    if (args.length >= 3 && engine.isObject(args[2]))
    {
        cwd = extractOptString(engine, args[2], "cwd");
        maxBuffer = extractOptInt(engine, args[2], "maxBuffer", MAX_BUFFER);
        envMap = extractOptEnv(engine, args[2]);
        hasEnv = envMap.length > 0;
        encoding = extractOptString(engine, args[2], "encoding");
    }

    auto resultObj = engine.newObject();

    JSHandle makeOutput(string s)
    {
        if (encoding.length > 0)
            return engine.newString(s);
        import dun.builtins.buffer : makeBufferObj;
        return makeBufferObj(engine, cast(const(ubyte)[]) s);
    }

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
        auto pipes = hasEnv
            ? pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr, envMap)
            : pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr);

        string stdoutStr = "";
        string stderrStr = "";

        try { stdoutStr = readAllFromPipe(pipes.stdout); }
        catch (Exception) {}

        try { stderrStr = readAllFromPipe(pipes.stderr); }
        catch (Exception) {}

        int status = wait(pipes.pid);

        stdoutStr = truncateToMaxBuffer(stdoutStr, maxBuffer);
        stderrStr = truncateToMaxBuffer(stderrStr, maxBuffer);

        if (origDir.length > 0)
            chdir(origDir);

        engine.setProperty(resultObj, "status", engine.newInt(status));
        engine.setProperty(resultObj, "stdout", makeOutput(stdoutStr));
        engine.setProperty(resultObj, "stderr", makeOutput(stderrStr));
        engine.setProperty(resultObj, "error", engine.newNull());
        return resultObj;
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}
        engine.setProperty(resultObj, "status", engine.newNull());
        engine.setProperty(resultObj, "stdout", makeOutput(""));
        engine.setProperty(resultObj, "stderr", makeOutput(""));
        auto errObj = engine.newObject();
        engine.setProperty(errObj, "message", engine.newString(msg));
        engine.setProperty(errObj, "code", engine.newString("ENOENT"));
        engine.setProperty(resultObj, "error", errObj);
        return resultObj;
    }
}

JSHandle jsExec(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
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
                engine.freeValue(engine.callFunction(cb, engine.newUndefined(), cbArgs));
            }
            else
            {
                JSHandle[] cbArgs = [engine.newNull(), engine.newString(stdout_), engine.newString("")];
                engine.freeValue(engine.callFunction(cb, engine.newUndefined(), cbArgs));
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
            engine.freeValue(engine.callFunction(ph.reject, engine.newUndefined(), rejArgs));
        }
        else
        {
            auto resObj = engine.newObject();
            engine.setProperty(resObj, "stdout", engine.newString(stdout_));
            engine.setProperty(resObj, "stderr", engine.newString(""));
            JSHandle[] resArgs = [resObj];
            engine.freeValue(engine.callFunction(ph.resolve, engine.newUndefined(), resArgs));
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
            engine.freeValue(engine.callFunction(args[1], engine.newUndefined(), cbArgs));
            return engine.newUndefined();
        }
        return engine.throwTypeError("exec failed: " ~ msg);
    }
}

/// JS helper source for creating ChildProcess objects with EventEmitter-like behavior.
/// Evaluated once per engine context, returns the ChildProcess constructor.
private immutable string childProcessHelperSource = `(function() {
  function mkEmitter() {
    /* Closure-captured events; emit/on don't rely on this so the
       D-side pushAgnosticPending (which invokes with undefined this)
       still works. Without this, emit's this._events is undefined
       and the listener never fires. */
    var events = {};
    var e = { _events: events };
    e.on = function(ev, cb) { (events[ev] = events[ev] || []).push(cb); return this; };
    e.once = function(ev, cb) {
      function w() { e.removeListener(ev, w); cb.apply(null, arguments); }
      w._orig = cb; e.on(ev, w); return this;
    };
    e.emit = function(ev) {
      var cbs = events[ev]; if (!cbs) return;
      var a = Array.prototype.slice.call(arguments, 1);
      var c = cbs.slice();
      for (var i = 0; i < c.length; i++) c[i].apply(null, a);
    };
    e.removeListener = function(ev, cb) {
      var cbs = events[ev]; if (!cbs) return e;
      for (var i = cbs.length - 1; i >= 0; i--) {
        if (cbs[i] === cb || cbs[i]._orig === cb) cbs.splice(i, 1);
      }
      return e;
    };
    e.removeAllListeners = function(ev) {
      if (ev) events[ev] = []; else for (var k in events) events[k] = [];
      return e;
    };
    return e;
  }
  function ChildProcess() {
    /* Closure-captured events so cp.emit('exit', ...) works when
       called via pushAgnosticPending with this=undefined. */
    var events = {};
    this._events = events;
    this.pid = 0;
    this.exitCode = null;
    this.signalCode = null;
    this.killed = false;
    this.connected = false;
    this.stdout = mkEmitter();
    this.stderr = mkEmitter();
    this.stdin = { write: function() {}, end: function() {} };
    var self = this;
    this.on = function(ev, cb) { (events[ev] = events[ev] || []).push(cb); return self; };
    this.once = function(ev, cb) {
      function w() { self.removeListener(ev, w); cb.apply(self, arguments); }
      w._orig = cb; self.on(ev, w); return self;
    };
    this.emit = function(ev) {
      var cbs = events[ev]; if (!cbs) return;
      var a = Array.prototype.slice.call(arguments, 1);
      var c = cbs.slice();
      for (var i = 0; i < c.length; i++) c[i].apply(self, a);
    };
    this.removeListener = function(ev, cb) {
      var cbs = events[ev]; if (!cbs) return self;
      for (var i = cbs.length - 1; i >= 0; i--) {
        if (cbs[i] === cb || cbs[i]._orig === cb) cbs.splice(i, 1);
      }
      return self;
    };
    this.removeAllListeners = function(ev) {
      if (ev) events[ev] = []; else for (var k in events) events[k] = [];
      return self;
    };
  }
  /* on / once / emit / removeListener / removeAllListeners are
     installed per-instance in the ctor (closure-captured events). */
  ChildProcess.prototype.kill = function(sig) { this.killed = true; return true; };
  return new ChildProcess();
})()`;

JSHandle jsSpawn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.loop.agnostic_pending : pushAgnosticPending;

    assert(ctx !is null, "Null ctx in jsSpawn");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsSpawn");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsSpawn");

    if (args.length < 1)
        return engine.throwTypeError("spawn requires a command argument");

    auto command = engine.extractString(args[0]);
    if (command.length == 0)
        return engine.throwTypeError("spawn: command must be a non-empty string");

    if (!checkPerm(state, Permission.run, command))
        return throwPermError(engine, command);

    // Parse args array (optional second argument)
    string[] cmdArgs;
    int optsIdx = 1;
    if (args.length >= 2 && engine.isArray(args[1]))
    {
        int len = engine.getArrayLength(args[1]);
        for (int i = 0; i < len; i++)
        {
            auto elem = engine.getPropertyIndex(args[1], cast(uint) i);
            cmdArgs ~= engine.extractString(elem);
            engine.freeValue(elem);
        }
        optsIdx = 2;
    }

    // Parse options (optional)
    string cwd = "";
    string[string] envMap;
    bool hasEnv = false;
    if (args.length > optsIdx && engine.isObject(args[optsIdx]))
    {
        cwd = extractOptString(engine, args[optsIdx], "cwd");
        envMap = extractOptEnv(engine, args[optsIdx]);
        hasEnv = envMap.length > 0;
    }

    // Create ChildProcess object via JS helper
    auto cpResult = engine.eval(childProcessHelperSource, "<spawn>");
    if (cpResult.isError)
    {
        engine.freeValue(cpResult.value);
        return engine.throwTypeError("spawn: failed to create ChildProcess object");
    }
    auto cp = cpResult.value;

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
        auto pipes = hasEnv
            ? pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr, envMap)
            : pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr);

        if (origDir.length > 0)
            chdir(origDir);

        // Set the real PID on the ChildProcess object
        int pid = 0;
        version (Posix)
        {
            import core.sys.posix.unistd;
            pid = pipes.pid.osHandle;
        }
        engine.setProperty(cp, "pid", engine.newInt(pid));

        string stdoutStr = "";
        try { stdoutStr = readAllFromPipe(pipes.stdout); }
        catch (Exception) {}

        string stderrStr = "";
        try { stderrStr = readAllFromPipe(pipes.stderr); }
        catch (Exception) {}

        int status = wait(pipes.pid);

        // Set exitCode
        engine.setProperty(cp, "exitCode", engine.newInt(status));

        // Schedule async delivery of stdout data, stderr data, and close/exit events
        // via pushAgnosticPending so callbacks registered after spawn() returns are invoked.

        // Get stdout.emit and stderr.emit
        auto cpStdout = engine.getProperty(cp, "stdout");
        auto cpStderr = engine.getProperty(cp, "stderr");
        auto stdoutEmit = engine.getProperty(cpStdout, "emit");
        auto stderrEmit = engine.getProperty(cpStderr, "emit");
        auto cpEmit = engine.getProperty(cp, "emit");

        // Schedule: stdout.emit('data', data)
        if (stdoutStr.length > 0)
        {
            JSHandle[3] sdArgs = [engine.newString("data"), engine.newString(stdoutStr), engine.newUndefined()];
            pushAgnosticPending(engine, stdoutEmit, sdArgs[0 .. 2]);
            // pushAgnosticPending dupValue()s its args; we own the
            // originals and must free them.
            foreach (h; sdArgs) engine.freeValue(h);
        }

        // Schedule: stdout.emit('end')
        {
            JSHandle[2] seArgs = [engine.newString("end"), engine.newUndefined()];
            pushAgnosticPending(engine, stdoutEmit, seArgs[0 .. 1]);
            foreach (h; seArgs) engine.freeValue(h);
        }

        // Schedule: stderr.emit('data', data)
        if (stderrStr.length > 0)
        {
            JSHandle[3] edArgs = [engine.newString("data"), engine.newString(stderrStr), engine.newUndefined()];
            pushAgnosticPending(engine, stderrEmit, edArgs[0 .. 2]);
            foreach (h; edArgs) engine.freeValue(h);
        }

        // Schedule: stderr.emit('end')
        {
            JSHandle[2] eeArgs = [engine.newString("end"), engine.newUndefined()];
            pushAgnosticPending(engine, stderrEmit, eeArgs[0 .. 1]);
            foreach (h; eeArgs) engine.freeValue(h);
        }

        // Schedule: cp.emit('exit', code)
        {
            JSHandle[3] exArgs = [engine.newString("exit"), engine.newInt(status), engine.newUndefined()];
            pushAgnosticPending(engine, cpEmit, exArgs[0 .. 2]);
            foreach (h; exArgs) engine.freeValue(h);
        }

        // Schedule: cp.emit('close', code)
        {
            JSHandle[3] clArgs = [engine.newString("close"), engine.newInt(status), engine.newUndefined()];
            pushAgnosticPending(engine, cpEmit, clArgs[0 .. 2]);
            foreach (h; clArgs) engine.freeValue(h);
        }

        engine.freeValue(stdoutEmit);
        engine.freeValue(stderrEmit);
        engine.freeValue(cpEmit);
        engine.freeValue(cpStdout);
        engine.freeValue(cpStderr);

        return cp;
    }
    catch (Exception e)
    {
        string msg = "";
        try { msg = e.msg; } catch (Exception) {}

        // Set error state on the ChildProcess object
        engine.setProperty(cp, "exitCode", engine.newNull());

        // Schedule: cp.emit('error', errObj)
        auto cpEmit = engine.getProperty(cp, "emit");
        auto errObj = engine.newObject();
        engine.setProperty(errObj, "message", engine.newString(msg));
        engine.setProperty(errObj, "code", engine.newString("ENOENT"));
        engine.setProperty(errObj, "errno", engine.newString("ENOENT"));
        engine.setProperty(errObj, "syscall", engine.newString("spawn " ~ command));
        engine.setProperty(errObj, "path", engine.newString(command));
        {
            JSHandle[3] errArgs = [engine.newString("error"), errObj, engine.newUndefined()];
            pushAgnosticPending(engine, cpEmit, errArgs[0 .. 2]);
        }
        engine.freeValue(cpEmit);

        return cp;
    }
}

JSHandle jsExecFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.engine.iface : PromiseHandles;

    assert(ctx !is null, "Null ctx in jsExecFile");
    auto state = cast(DunState*) ctx;
    assert(state !is null, "Null DunState in jsExecFile");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsExecFile");

    if (args.length < 1)
        return engine.throwTypeError("execFile requires a file argument");

    auto file = engine.extractString(args[0]);
    if (file.length == 0)
        return engine.throwTypeError("execFile: file must be a non-empty string");

    if (!checkPerm(state, Permission.run, file))
        return throwPermError(engine, file);

    // Parse: execFile(file, args?, options?, callback?)
    string[] cmdArgs;
    int nextIdx = 1;

    // Second argument can be args array, options object, or callback function
    if (args.length >= 2 && engine.isArray(args[1]))
    {
        int len = engine.getArrayLength(args[1]);
        for (int i = 0; i < len; i++)
        {
            auto elem = engine.getPropertyIndex(args[1], cast(uint) i);
            cmdArgs ~= engine.extractString(elem);
            engine.freeValue(elem);
        }
        nextIdx = 2;
    }

    // Options object (optional)
    string cwd = "";
    int maxBuffer = MAX_BUFFER;
    if (args.length > nextIdx && engine.isObject(args[nextIdx]) && !engine.isFunction(args[nextIdx]))
    {
        cwd = extractOptString(engine, args[nextIdx], "cwd");
        maxBuffer = extractOptInt(engine, args[nextIdx], "maxBuffer", MAX_BUFFER);
        nextIdx++;
    }

    // Callback (optional, last argument)
    bool hasCallback = args.length > nextIdx && engine.isFunction(args[nextIdx]);
    JSHandle callbackFn;
    if (hasCallback)
        callbackFn = args[nextIdx];

    // Also check if the second arg is a function (execFile(file, callback) form)
    if (!hasCallback && args.length >= 2 && engine.isFunction(args[1]))
    {
        hasCallback = true;
        callbackFn = args[1];
    }

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

        string[] fullCmd = [file] ~ cmdArgs;
        auto pipes = pipeProcess(fullCmd, Redirect.stdout | Redirect.stderr);

        string stdoutStr = "";
        try { stdoutStr = readAllFromPipe(pipes.stdout); }
        catch (Exception) {}

        string stderrStr = "";
        try { stderrStr = readAllFromPipe(pipes.stderr); }
        catch (Exception) {}

        int status = wait(pipes.pid);

        if (origDir.length > 0)
            chdir(origDir);

        stdoutStr = truncateToMaxBuffer(stdoutStr, maxBuffer);
        stderrStr = truncateToMaxBuffer(stderrStr, maxBuffer);

        if (hasCallback)
        {
            if (status != 0)
            {
                import std.conv : to;
                auto errObj = engine.newObject();
                engine.setProperty(errObj, "message",
                    engine.newString("Command failed: " ~ file));
                engine.setProperty(errObj, "code", engine.newInt(status));
                engine.setProperty(errObj, "killed", engine.newBool(false));
                engine.setProperty(errObj, "cmd", engine.newString(file));
                JSHandle[] cbArgs = [errObj, engine.newString(stdoutStr), engine.newString(stderrStr)];
                engine.freeValue(engine.callFunction(callbackFn, engine.newUndefined(), cbArgs));
            }
            else
            {
                JSHandle[] cbArgs = [engine.newNull(), engine.newString(stdoutStr), engine.newString(stderrStr)];
                engine.freeValue(engine.callFunction(callbackFn, engine.newUndefined(), cbArgs));
            }
            return engine.newUndefined();
        }

        // No callback — return a Promise
        auto ph = engine.newPromise();
        engine.dupValue(ph.resolve);
        engine.dupValue(ph.reject);

        if (status != 0)
        {
            import std.conv : to;
            auto errObj = engine.newObject();
            engine.setProperty(errObj, "message",
                engine.newString("Command failed: " ~ file));
            engine.setProperty(errObj, "code", engine.newInt(status));
            engine.setProperty(errObj, "stdout", engine.newString(stdoutStr));
            engine.setProperty(errObj, "stderr", engine.newString(stderrStr));
            engine.setProperty(errObj, "cmd", engine.newString(file));
            JSHandle[] rejArgs = [errObj];
            engine.freeValue(engine.callFunction(ph.reject, engine.newUndefined(), rejArgs));
        }
        else
        {
            auto resObj = engine.newObject();
            engine.setProperty(resObj, "stdout", engine.newString(stdoutStr));
            engine.setProperty(resObj, "stderr", engine.newString(stderrStr));
            JSHandle[] resArgs = [resObj];
            engine.freeValue(engine.callFunction(ph.resolve, engine.newUndefined(), resArgs));
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
            engine.setProperty(errObj, "errno", engine.newString("ENOENT"));
            engine.setProperty(errObj, "syscall", engine.newString("spawn"));
            engine.setProperty(errObj, "path", engine.newString(file));
            JSHandle[] cbArgs = [errObj, engine.newString(""), engine.newString("")];
            engine.freeValue(engine.callFunction(callbackFn, engine.newUndefined(), cbArgs));
            return engine.newUndefined();
        }
        return engine.throwTypeError("execFile failed: " ~ msg);
    }
}

JSHandle jsExecFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null);
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("execFileSync requires a file argument");

    auto file = engine.extractString(args[0]);
    if (file.length == 0)
        return engine.throwTypeError("execFileSync: file must be a non-empty string");

    string[] cmdArgs;
    if (args.length >= 2 && engine.isArray(args[1]))
    {
        auto len = engine.getArrayLength(args[1]);
        for (uint i = 0; i < len; i++)
        {
            auto elem = engine.getPropertyIndex(args[1], i);
            if (engine.isString(elem))
                cmdArgs ~= engine.extractString(elem);
            engine.freeValue(elem);
        }
    }

    if (!hasGlobalRun(state))
        return engine.throwTypeError("Requires --allow-run permission");

    version (Posix)
    {
        try
        {
            import std.process : execute;
            auto result = execute([file] ~ cmdArgs);
            if (result.status != 0)
                return engine.throwTypeError("Command failed with code " ~ intToStr(result.status));
            return engine.newString(result.output);
        }
        catch (Exception e)
            return engine.throwTypeError("execFileSync: " ~ e.msg);
    }
    else
        return engine.throwTypeError("execFileSync not available on this platform");
}

JSHandle jsFork(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null);
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null);
    return state.engine.throwTypeError("fork() is not supported; use worker_threads instead");
}

public import dun.builtins.fs : intToStr;
