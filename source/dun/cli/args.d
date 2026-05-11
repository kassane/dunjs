/// Command-line argument parsing.
///
/// Parses CLI arguments into a CliConfig struct including
/// command, script path, permission flags, and runtime options.
module dun.cli.args;

import dun.security.permissions : PermissionRegistry;

/// Available CLI commands.
enum Command
{
    run,
    repl,
    eval_,
    version_,
    help,
}

/// Parsed CLI configuration.
struct CliConfig
{
    Command command = Command.help;
    string scriptPath;
    string evalSource;
    string[] scriptArgs;
    PermissionRegistry permissions;
    import dun.engine.iface : DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK;
    size_t memoryLimit = DEFAULT_MEMORY_LIMIT;
    size_t stackSize = DEFAULT_MAX_STACK;
    bool verbose;
}

/// Parse command-line arguments into a CliConfig.
CliConfig parseArgs(string[] args) @safe
{
    import std.algorithm : startsWith;
    import std.conv : to;

    CliConfig config;

    if (args.length < 2)
    {
        config.command = Command.help;
        return config;
    }

    size_t i = 1; // Skip program name

    // Parse command
    if (args[i] == "run")
    {
        config.command = Command.run;
        i++;
    }
    else if (args[i] == "repl")
    {
        config.command = Command.repl;
        i++;
    }
    else if (args[i] == "eval")
    {
        config.command = Command.eval_;
        i++;
    }
    else if (args[i] == "version" || args[i] == "--version" || args[i] == "-v")
    {
        config.command = Command.version_;
        return config;
    }
    else if (args[i] == "help" || args[i] == "--help" || args[i] == "-h")
    {
        config.command = Command.help;
        return config;
    }
    else if (args[i].startsWith("-"))
    {
        // Flags before command — default to run
        config.command = Command.run;
    }
    else
    {
        // Bare filename — implicit run
        config.command = Command.run;
        config.scriptPath = args[i];
        i++;
    }

    // Parse remaining arguments
    bool seenDoubleDash = false;
    while (i < args.length)
    {
        auto arg = args[i];

        if (seenDoubleDash)
        {
            config.scriptArgs ~= arg;
            i++;
            continue;
        }

        if (arg == "--")
        {
            seenDoubleDash = true;
            i++;
            continue;
        }

        // Permission flags
        if (arg.startsWith("--allow-") || arg.startsWith("--deny-") || arg == "-A")
        {
            config.permissions.parseFlag(arg);
            i++;
            continue;
        }

        // Runtime options
        if (arg.startsWith("--max-memory="))
        {
            try
            {
                config.memoryLimit = arg["--max-memory=".length .. $].to!size_t;
            }
            catch (Exception)
            {
            }
            i++;
            continue;
        }

        if (arg.startsWith("--max-stack="))
        {
            try
            {
                config.stackSize = arg["--max-stack=".length .. $].to!size_t;
            }
            catch (Exception)
            {
            }
            i++;
            continue;
        }

        if (arg == "--verbose" || arg == "-V")
        {
            config.verbose = true;
            i++;
            continue;
        }

        // Eval source
        if (config.command == Command.eval_ && config.evalSource.length == 0)
        {
            config.evalSource = arg;
            i++;
            continue;
        }

        // Script path (if not yet set)
        if (config.command == Command.run && config.scriptPath.length == 0)
        {
            config.scriptPath = arg;
            i++;
            continue;
        }

        // Script arguments
        config.scriptArgs ~= arg;
        i++;
    }

    return config;
}
