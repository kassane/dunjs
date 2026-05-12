/// CLI argument parsing into CliConfig.
module dun.cli.args;

import dun.security.permissions : PermissionRegistry;

/// Available CLI commands.
enum Command
{
    run,
    repl,
    eval_,
    install,
    audit,
    test_,
    bench,
    init_,
    fmt,
    clean,
    version_,
    help,
}

static assert(__traits(allMembers, Command).length == 12,
    "Command enum member count changed -- update parseArgs and main dispatch");

/// Parsed CLI configuration.
struct CliConfig
{
    Command command = Command.help;
    string scriptPath;
    string evalSource;
    string[] installPackages;
    string[] scriptArgs;
    PermissionRegistry permissions;
    import dun.engine.iface : DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK;
    size_t memoryLimit = DEFAULT_MEMORY_LIMIT;
    size_t stackSize = DEFAULT_MAX_STACK;
    bool verbose;

    import dun.modules.npm : AuditMode;
    AuditMode auditMode = AuditMode.warn;

    string[] testFiles;
    string testFilter;
    string initName;
    string[] fmtFiles;
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

    // Pre-scan: handle global flags that can appear before command keyword
    while (i < args.length && args[i].startsWith("-"))
    {
        if (args[i] == "--verbose" || args[i] == "-V")
        {
            config.verbose = true;
            i++;
        }
        else if (args[i] == "--version" || args[i] == "-v")
        {
            config.command = Command.version_;
            return config;
        }
        else if (args[i] == "--help" || args[i] == "-h")
        {
            config.command = Command.help;
            return config;
        }
        else
            break; // Other flags handled after command detection
    }

    if (i >= args.length)
    {
        config.command = Command.repl;
        return config;
    }

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
    else if (args[i] == "install" || args[i] == "i" || args[i] == "add")
    {
        config.command = Command.install;
        i++;
        while (i < args.length && !args[i].startsWith("-"))
        {
            config.installPackages ~= args[i];
            i++;
        }
    }
    else if (args[i] == "audit")
    {
        config.command = Command.audit;
        i++;
    }
    else if (args[i] == "test")
    {
        config.command = Command.test_;
        i++;
        while (i < args.length)
        {
            if (args[i].startsWith("--filter="))
            {
                config.testFilter = args[i]["--filter=".length .. $];
            }
            else if (!args[i].startsWith("-"))
            {
                config.testFiles ~= args[i];
            }
            else
            {
                config.permissions.parseFlag(args[i]);
            }
            i++;
        }
        return config;
    }
    else if (args[i] == "bench")
    {
        config.command = Command.bench;
        i++;
        while (i < args.length && !args[i].startsWith("-"))
        {
            config.testFiles ~= args[i];
            i++;
        }
        return config;
    }
    else if (args[i] == "init")
    {
        config.command = Command.init_;
        i++;
        if (i < args.length && !args[i].startsWith("-"))
        {
            config.initName = args[i];
            i++;
        }
        return config;
    }
    else if (args[i] == "fmt" || args[i] == "format")
    {
        config.command = Command.fmt;
        i++;
        while (i < args.length && !args[i].startsWith("-"))
        {
            config.fmtFiles ~= args[i];
            i++;
        }
        return config;
    }
    else if (args[i] == "clean")
    {
        config.command = Command.clean;
        return config;
    }
    else if (args[i] == "version")
    {
        config.command = Command.version_;
        return config;
    }
    else if (args[i] == "help")
    {
        config.command = Command.help;
        return config;
    }
    else if (args[i].startsWith("-"))
    {
        // Unrecognized leading flag — default to run, let remaining loop process it
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

        if (arg.startsWith("--audit="))
        {
            import dun.modules.npm : AuditMode;
            auto mode = arg["--audit=".length .. $];
            if (mode == "block")
                config.auditMode = AuditMode.block;
            else if (mode == "off")
                config.auditMode = AuditMode.off;
            else
                config.auditMode = AuditMode.warn;
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
