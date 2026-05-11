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
    installGlobals(engine, &state);

    auto result = engine.eval(source, config.scriptPath);
    if (result.isError)
    {
        writeStderr("Uncaught ");
        writeStderr(result.errorMessage);
        writeStderr("\n");
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
    import std.stdio : writeln;
    writeln("dun ", VERSION);
    writeln("REPL not yet implemented. Use 'dun run <file>' instead.");
    return 0;
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
    installGlobals(engine, &state);
    auto result = engine.eval(config.evalSource, "<eval>");
    if (result.isError)
    {
        writeStderr("Uncaught ");
        writeStderr(result.errorMessage);
        writeStderr("\n");
        return 1;
    }

    if (!engine.isUndefined(result.value))
    {
        import std.stdio : writeln;
        writeln(engine.extractString(result.value));
    }
    engine.freeValue(result.value);

    engine.drainJobs();
    return 0;
}

void printVersion()
{
    import std.stdio : writeln;
    writeln("dun ", VERSION);
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
        ~ "  version          Print version\n"
        ~ "  help             Show this help\n\n"
        ~ "Permission flags:\n"
        ~ "  --allow-read[=paths]   Allow file read access\n"
        ~ "  --allow-write[=paths]  Allow file write access\n"
        ~ "  --allow-net[=hosts]    Allow network access\n"
        ~ "  --allow-env[=vars]     Allow env variable access\n"
        ~ "  --allow-run[=cmds]     Allow child process execution\n"
        ~ "  --allow-all / -A       Allow all permissions\n\n"
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

void writeStderr(const(char)[] msg) @trusted
{
    import std.stdio : stderr;
    stderr.write(msg);
}
