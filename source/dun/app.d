module dun.app;

version (unittest) {} else
int main(string[] args)
{
    import dun.cli.args : parseArgs, Command;

    auto config = parseArgs(args);

    final switch (config.command)
    {
        case Command.run:
            return runScript(config);
        case Command.repl:
            return runRepl(config);
        case Command.eval_:
            return evalInline(config);
        case Command.install:
            return runInstall(config);
        case Command.audit:
            return runAudit(config);
        case Command.version_:
            printVersion();
            return 0;
        case Command.help:
            printUsage();
            return 0;
    }
}

private:

enum VERSION = "0.1.0-dev";

int runScript(T)(T config)
{
    import dun.engine.iface : createEngine, EngineConfig, JSResult;
    import dun.runtime.globals : DunState, installGlobals;

    if (config.scriptPath.length == 0)
    {
        printUsage();
        return 1;
    }

    string source;
    try
    {
        import std.file : readText;
        source = readText(config.scriptPath);
    }
    catch (Exception e)
    {
        writeStderr("Error: Cannot read '");
        writeStderr(config.scriptPath);
        writeStderr("': ");
        writeStderr(e.msg);
        writeStderr("\n");
        return 1;
    }

    if (isTypeScript(config.scriptPath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
    }

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    version (EngineQuickJS)
    {
        import dun.modules.loader : ModuleLoader;
        import dun.engine.quickjs.bindings : JSRuntime;
        ModuleLoader loader;
        loader.install(cast(JSRuntime*) engine.rawRuntime());
    }

    bool esm = isESM(config.scriptPath, source);

    // Inject __filename / __dirname and seed the CJS require stack so that
    // relative require() calls in the entry script resolve against the
    // script's own directory (not cwd).
    {
        import std.path : absolutePath, dirName;
        import std.string : replace;
        auto abs  = absolutePath(config.scriptPath);
        auto dir  = dirName(abs);
        auto eabs = abs.replace(`\`, `\\`).replace(`"`, `\"`);
        auto edir = dir.replace(`\`, `\\`).replace(`"`, `\"`);
        string initCode = `var __filename="` ~ eabs ~ `";var __dirname="` ~ edir ~ `";`;
        if (!esm)
            initCode ~= `__dunCjsStack__.push("` ~ eabs ~ `");`;
        auto initRes = engine.eval(initCode, "<init>");
        if (!initRes.isError)
            engine.freeValue(initRes.value);
    }

    JSResult result;
    if (esm)
        result = engine.evalModule(source, config.scriptPath);
    else
        result = engine.eval(source, config.scriptPath);

    if (result.isError)
    {
        import dun.runtime.process_api : hasUncaughtExceptionHandler,
            invokeUncaughtExceptionHandler;
        if (hasUncaughtExceptionHandler())
        {
            invokeUncaughtExceptionHandler(engine, result.errorMessage);
        }
        else
        {
            import dun.cli.errors : isColorEnabled, formatUncaughtError;
            writeStderr(formatUncaughtError(result.errorMessage, isColorEnabled()));
            return 1;
        }
    }
    else
    {
        engine.freeValue(result.value);
    }

    state.eventLoop.run();
    state.eventLoop.flushUnhandledRejections();
    return state.eventLoop.exitCode;
}

int runRepl(T)(T config)
{
    import dun.cli.repl : runReplImpl;
    return runReplImpl(config);
}

int evalInline(T)(T config)
{
    if (config.evalSource.length == 0)
    {
        writeStderr("Error: --eval requires a source string\n");
        return 1;
    }

    import dun.engine.iface : createEngine, EngineConfig;
    import dun.runtime.globals : DunState, installGlobals;

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);
    auto result = engine.eval(config.evalSource, "<eval>");
    if (result.isError)
    {
        import dun.cli.errors : isColorEnabled, formatUncaughtError;
        writeStderr(formatUncaughtError(result.errorMessage, isColorEnabled()));
        return 1;
    }

    if (!engine.isUndefined(result.value))
    {
        import std.stdio : writeln;
        writeln(engine.extractString(result.value));
    }
    engine.freeValue(result.value);

    state.eventLoop.run();
    state.eventLoop.flushUnhandledRejections();
    return state.eventLoop.exitCode;
}

void printVersion()
{
    import std.stdio : writeln;
    writeln("dun ", VERSION);
}

int runInstall(T)(T config)
{
    version (Posix)
    {
        import dun.modules.npm : installPackage;
        if (config.installPackages.length == 0)
        {
            writeStderr("Usage: dun install <package> [package...]\n");
            return 1;
        }
        bool allOk = true;
        foreach (pkg; config.installPackages)
        {
            if (!installPackage(pkg, config.auditMode))
                allOk = false;
        }
        return allOk ? 0 : 1;
    }
    else
    {
        writeStderr("dun install is not yet supported on this platform\n");
        return 1;
    }
}

int runAudit(T)(T config)
{
    version (Posix)
    {
        import std.stdio : writeln, writefln;
        import dun.security.cve_db : auditNodeModules, printAuditReport,
            worstSeverity, Severity;
        import dun.modules.npm : AuditMode;

        bool useApi = (config.auditMode == AuditMode.live);
        if (useApi)
            writeln("Auditing node_modules via OSV API (live)...\n");
        else
            writeln("Auditing node_modules for known vulnerabilities...\n");

        auto results = auditNodeModules(useApi);
        printAuditReport(results);

        auto worst = worstSeverity(results);
        return (worst == Severity.critical || worst == Severity.high) ? 1 : 0;
    }
    else
    {
        writeStderr("dun audit is not yet supported on this platform\n");
        return 1;
    }
}

void printUsage()
{
    import std.stdio : write;
    write(
        "Usage: dun <command> [options] [script] [args...]\n\n"
        ~ "Commands:\n"
        ~ "  run <file>       Run a JavaScript/TypeScript file\n"
        ~ "  repl             Start interactive REPL\n"
        ~ "  eval <code>      Evaluate JavaScript code\n"
        ~ "  install <pkg>    Install npm package to node_modules/\n"
        ~ "  audit            Scan node_modules/ for known CVEs\n"
        ~ "  version          Print version\n"
        ~ "  help             Show this help\n\n"
        ~ "Permission flags:\n"
        ~ "  --allow-read[=paths]   Allow file read access\n"
        ~ "  --allow-write[=paths]  Allow file write access\n"
        ~ "  --allow-net[=hosts]    Allow network access\n"
        ~ "  --allow-env[=vars]     Allow env variable access\n"
        ~ "  --allow-run[=cmds]     Allow child process execution\n"
        ~ "  --allow-all / -A       Allow all permissions\n\n"
        ~ "Security options:\n"
        ~ "  --audit=warn           Warn about vulnerable packages (default)\n"
        ~ "  --audit=block          Block install of critical/high severity\n"
        ~ "  --audit=live           Query OSV API for live vulnerability data\n"
        ~ "  --audit=off            Disable CVE checking during install\n\n"
        ~ "Runtime options:\n"
        ~ "  --max-memory=<bytes>   JS heap memory limit (default: 256MB)\n"
        ~ "  --max-stack=<bytes>    Max stack size (default: 8MB)\n"
    );
}

bool isTypeScript(string path) @safe pure nothrow @nogc
{
    if (path.length >= 3 && path[$ - 3 .. $] == ".ts")
        return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".mts")
        return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".cts")
        return true;
    return false;
}

bool isESM(string path, string source) @safe pure nothrow
{
    // Extension-based: .mjs/.mts always ESM; .cjs/.cts always CJS
    if (path.length >= 4 && (path[$ - 4 .. $] == ".mjs" || path[$ - 4 .. $] == ".mts"))
        return true;
    if (path.length >= 4 && (path[$ - 4 .. $] == ".cjs" || path[$ - 4 .. $] == ".cts"))
        return false;

    // Content-based: scan for top-level import/export statements
    for (size_t i = 0; i < source.length; i++)
    {
        if (i == 0 || source[i - 1] == '\n')
        {
            if (source.length - i >= 7 && source[i .. i + 7] == "import ")
                return true;
            if (source.length - i >= 7 && source[i .. i + 7] == "export ")
                return true;
        }
    }
    return false;
}

void writeStderr(const(char)[] msg) @trusted
{
    import std.stdio : stderr;
    stderr.write(msg);
}
