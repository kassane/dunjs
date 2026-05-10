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
    import dun.engine.iface : createEngine, EngineConfig;
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
        import core.stdc.stdio : fprintf, stderr;
        fprintf(stderr, "Error: Cannot read '%.*s': %.*s\n",
            cast(int) config.scriptPath.length, config.scriptPath.ptr,
            cast(int) e.msg.length, e.msg.ptr);
        return 1;
    }

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    installGlobals(engine, &state);

    auto result = engine.eval(source, config.scriptPath);
    if (result.isError)
    {
        import core.stdc.stdio : fprintf, stderr;
        fprintf(stderr, "Uncaught %.*s\n",
            cast(int) result.errorMessage.length, result.errorMessage.ptr);
        return 1;
    }
    else
    {
        engine.freeValue(result.value);
    }

    engine.drainJobs();
    return 0;
}

int runRepl(T)(T)
{
    import core.stdc.stdio : printf;
    printf("dun %.*s\n", cast(int) VERSION.length, VERSION.ptr);
    printf("REPL not yet implemented. Use 'dun run <file>' instead.\n");
    return 0;
}

int evalInline(T)(T config)
{
    if (config.evalSource.length == 0)
    {
        import core.stdc.stdio : fprintf, stderr;
        fprintf(stderr, "Error: --eval requires a source string\n");
        return 1;
    }

    import dun.engine.iface : createEngine, EngineConfig;
    import dun.runtime.globals : DunState, installGlobals;

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    installGlobals(engine, &state);

    auto result = engine.eval(config.evalSource, "<eval>");
    if (result.isError)
    {
        import core.stdc.stdio : fprintf, stderr;
        fprintf(stderr, "Uncaught %.*s\n",
            cast(int) result.errorMessage.length, result.errorMessage.ptr);
        return 1;
    }

    if (!engine.isUndefined(result.value))
    {
        import core.stdc.stdio : printf;
        auto s = engine.extractString(result.value);
        printf("%.*s\n", cast(int) s.length, s.ptr);
    }
    engine.freeValue(result.value);

    engine.drainJobs();
    return 0;
}

void printVersion()
{
    import core.stdc.stdio : printf;
    printf("dun %.*s\n", cast(int) VERSION.length, VERSION.ptr);
}

void printUsage()
{
    import core.stdc.stdio : printf;
    printf("Usage: dun <command> [options] [script] [args...]\n\n");
    printf("Commands:\n");
    printf("  run <file>       Run a JavaScript file\n");
    printf("  repl             Start interactive REPL\n");
    printf("  eval <code>      Evaluate JavaScript code\n");
    printf("  version          Print version\n");
    printf("  help             Show this help\n\n");
    printf("Permission flags:\n");
    printf("  --allow-read[=paths]   Allow file read access\n");
    printf("  --allow-write[=paths]  Allow file write access\n");
    printf("  --allow-net[=hosts]    Allow network access\n");
    printf("  --allow-env[=vars]     Allow env variable access\n");
    printf("  --allow-run[=cmds]     Allow child process execution\n");
    printf("  --allow-all / -A       Allow all permissions\n\n");
    printf("Runtime options:\n");
    printf("  --max-memory=<bytes>   JS heap memory limit (default: 256MB)\n");
    printf("  --max-stack=<bytes>    Max stack size (default: 8MB)\n");
}
