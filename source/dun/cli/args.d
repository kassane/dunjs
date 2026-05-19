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
    bundle,
    lint,
    version_,
    help,
}

static assert(__traits(allMembers, Command).length == 14,
    "Command enum member count changed -- update parseArgs and main dispatch");

/// Default `--max-concurrency` cap for `dun test --concurrent`.
/// Matches Bun's documented default (`bun test --max-concurrency 20`).
enum DEFAULT_TEST_MAX_CONCURRENCY = 20;

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
    string evalFile;
    string errorMessage;

    import dun.modules.npm : AuditMode;
    AuditMode auditMode = AuditMode.warn;

    string[] testFiles;
    string testFilter;
    // `dun test --concurrent` — Bun parity. When set, every `test(...)`
    // call without an explicit `.serial` marker behaves as if it were
    // declared via `test.concurrent(...)`. Batches run up to
    // `testMaxConcurrency` in parallel.
    bool testConcurrent;
    // `dun test --max-concurrency=N` — caps the parallel batch size.
    // Default matches Bun.
    int testMaxConcurrency = DEFAULT_TEST_MAX_CONCURRENCY;
    string initName;
    string[] fmtFiles;
    // `dun fmt --quotes=single|double` — when non-empty, rewrites
    // string literals to use the chosen quote style. Matches Prettier's
    // singleQuote / quoteProps default.
    string fmtQuotes;
    // `dun fmt --check` — exit non-zero if any file is not already
    // formatted. CI gate (Prettier's --check).
    bool fmtCheck;
    string[] bundleEntries;
    string bundleOutDir;
    bool bundleMinify;
    // `dun bundle --sourcemap[=inline|external|none]` — emit a v3 source
    // map alongside the bundle (or inline base64 data URI).
    string bundleSourcemap;
    // `dun lint` — paths (files or directories) to scan. Defaults to "."
    // when empty.
    string[] lintPaths;
    // `dun lint --fix` — auto-apply safe rewrites in-place
    // (eqeqeq → strict equality, no-debugger removes the statement).
    bool lintFix;
    bool inspect;
    bool inspectBrk;
    ushort inspectPort = 9229;
    bool watchMode;
    // `dun run --typecheck file.ts` -- run the file through tsc
    // (loaded from node_modules) and refuse to execute if there are
    // type errors. Opt-in; default `dun run` keeps the fast scanner.
    bool typecheck;
}

/// Parse command-line arguments into a CliConfig.
CliConfig parseArgs(string[] args) @safe
{
    import std.algorithm : startsWith;
    import std.conv : to;

    CliConfig config;

    if (args.length < 2)
    {
        config.command = Command.repl;
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
            i++;
            if (i < args.length)
            {
                config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after '" ~ args[i-1] ~ "'";
                return config;
            }
            return config;
        }
        else if (args[i] == "--help" || args[i] == "-h")
        {
            config.command = Command.help;
            i++;
            if (i < args.length)
            {
                config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after '" ~ args[i-1] ~ "'";
                return config;
            }
            return config;
        }
        else if (args[i] == "-e" || args[i] == "--eval")
        {
            config.command = Command.eval_;
            i++;
            if (i < args.length)
            {
                config.evalSource = args[i];
                i++;
            }
            break;
        }
        else if (isKnownFlag(args[i]))
        {
            break; // Permission/runtime flags handled after command detection
        }
        else
        {
            config.errorMessage = "unknown flag '" ~ args[i] ~ "'";
            return config;
        }
    }

    if (i >= args.length)
    {
        if (config.command == Command.help)
            config.command = Command.repl;
        return config;
    }

    // Parse command keyword (skip if already determined by pre-scan flags like -e)
    if (config.command == Command.eval_)
    {
        // Already set by -e/--eval; skip to flag parsing
    }
    else if (args[i] == "run")
    {
        config.command = Command.run;
        i++;
    }
    else if (args[i] == "repl")
    {
        config.command = Command.repl;
        i++;
        if (i < args.length && !args[i].startsWith("-"))
        {
            config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'repl'";
            return config;
        }
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
        while (i < args.length)
        {
            if (args[i].startsWith("--audit="))
            {
                i++;
            }
            else if (args[i].startsWith("-"))
            {
                config.permissions.parseFlag(args[i]);
                i++;
            }
            else
            {
                config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'audit'";
                return config;
            }
        }
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
            else if (args[i] == "--concurrent")
            {
                config.testConcurrent = true;
            }
            else if (args[i].startsWith("--max-concurrency="))
            {
                try
                    config.testMaxConcurrency =
                        to!int(args[i]["--max-concurrency=".length .. $]);
                catch (Exception)
                {
                    config.errorMessage = "invalid --max-concurrency value";
                    return config;
                }
                if (config.testMaxConcurrency < 1)
                    config.testMaxConcurrency = 1;
            }
            else if (!args[i].startsWith("-"))
            {
                config.testFiles ~= args[i];
            }
            else if (isKnownFlag(args[i]))
            {
                config.permissions.parseFlag(args[i]);
            }
            else
            {
                config.errorMessage = "unknown flag '" ~ args[i] ~ "' for 'test'";
                return config;
            }
            i++;
        }
        return config;
    }
    else if (args[i] == "bench")
    {
        config.command = Command.bench;
        i++;
        while (i < args.length)
        {
            if (!args[i].startsWith("-"))
            {
                config.testFiles ~= args[i];
            }
            else if (isKnownFlag(args[i]))
            {
                config.permissions.parseFlag(args[i]);
            }
            else
            {
                config.errorMessage = "unknown flag '" ~ args[i] ~ "' for 'bench'";
                return config;
            }
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
        if (i < args.length)
        {
            config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'init'";
            return config;
        }
        return config;
    }
    else if (args[i] == "fmt" || args[i] == "format")
    {
        config.command = Command.fmt;
        i++;
        while (i < args.length)
        {
            if (args[i].startsWith("--quotes="))
                config.fmtQuotes = args[i]["--quotes=".length .. $];
            else if (args[i] == "--check")
                config.fmtCheck = true;
            else if (!args[i].startsWith("-"))
                config.fmtFiles ~= args[i];
            else
            {
                config.errorMessage = "unknown flag '" ~ args[i] ~ "' for 'fmt'";
                return config;
            }
            i++;
        }
        return config;
    }
    else if (args[i] == "bundle" || args[i] == "build")
    {
        config.command = Command.bundle;
        i++;
        while (i < args.length)
        {
            if (args[i] == "--outdir" && i + 1 < args.length)
            {
                config.bundleOutDir = args[i + 1];
                i += 2;
            }
            else if (args[i] == "--minify")
            {
                config.bundleMinify = true;
                i++;
            }
            else if (args[i] == "--sourcemap")
            {
                config.bundleSourcemap = "external";
                i++;
            }
            else if (args[i].startsWith("--sourcemap="))
            {
                config.bundleSourcemap = args[i]["--sourcemap=".length .. $];
                i++;
            }
            else if (!args[i].startsWith("-"))
            {
                config.bundleEntries ~= args[i];
                i++;
            }
            else
            {
                config.errorMessage = "unknown flag '" ~ args[i] ~ "' for 'bundle'";
                return config;
            }
        }
        return config;
    }
    else if (args[i] == "lint")
    {
        config.command = Command.lint;
        i++;
        while (i < args.length)
        {
            if (args[i] == "--fix")
            {
                config.lintFix = true;
                i++;
            }
            else if (!args[i].startsWith("-"))
            {
                config.lintPaths ~= args[i];
                i++;
            }
            else
            {
                config.errorMessage = "unknown flag '" ~ args[i] ~ "' for 'lint'";
                return config;
            }
        }
        return config;
    }
    else if (args[i] == "clean")
    {
        config.command = Command.clean;
        i++;
        if (i < args.length)
        {
            config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'clean'";
            return config;
        }
        return config;
    }
    else if (args[i] == "version")
    {
        config.command = Command.version_;
        i++;
        if (i < args.length)
        {
            config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'version'";
            return config;
        }
        return config;
    }
    else if (args[i] == "help")
    {
        config.command = Command.help;
        i++;
        if (i < args.length)
        {
            config.errorMessage = "unexpected argument '" ~ args[i] ~ "' after 'help'";
            return config;
        }
        return config;
    }
    else if (args[i].startsWith("-"))
    {
        if (isKnownFlag(args[i]))
        {
            config.command = Command.run;
        }
        else
        {
            config.errorMessage = "unknown flag '" ~ args[i] ~ "'";
            return config;
        }
    }
    else if (looksLikeFile(args[i]))
    {
        config.command = Command.run;
        config.scriptPath = args[i];
        i++;
    }
    else
    {
        config.errorMessage = "unknown command '" ~ args[i] ~ "'. Run 'dun help' for usage.";
        return config;
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
            // Default unit is MB (so `--max-memory=64` = 64 MiB, not 64 B).
            // Explicit suffixes B/KB/MB/GB are honored.
            try
            {
                config.memoryLimit = parseMemorySize(arg["--max-memory=".length .. $]);
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

        if (arg.startsWith("--eval-file="))
        {
            config.evalFile = arg["--eval-file=".length .. $];
            i++;
            continue;
        }
        // Also accept the space-separated form `--eval-file <path>` for
        // parity with shells that resolve globs before quoting reaches us.
        if (arg == "--eval-file" && i + 1 < args.length)
        {
            config.evalFile = args[i + 1];
            i += 2;
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

        if (arg == "--watch" || arg == "-w")
        {
            config.watchMode = true;
            i++;
            continue;
        }

        if (arg == "--typecheck")
        {
            config.typecheck = true;
            i++;
            continue;
        }

        if (arg == "--inspect" || arg.startsWith("--inspect="))
        {
            config.inspect = true;
            if (arg.startsWith("--inspect="))
            {
                try { config.inspectPort = arg["--inspect=".length .. $].to!ushort; }
                catch (Exception) {}
            }
            i++;
            continue;
        }

        if (arg == "--inspect-brk" || arg.startsWith("--inspect-brk="))
        {
            config.inspect = true;
            config.inspectBrk = true;
            if (arg.startsWith("--inspect-brk="))
            {
                try { config.inspectPort = arg["--inspect-brk=".length .. $].to!ushort; }
                catch (Exception) {}
            }
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

        // Unknown flag before script path
        if (arg.startsWith("-") && config.scriptPath.length == 0)
        {
            config.errorMessage = "unknown flag '" ~ arg ~ "'";
            return config;
        }

        // Script path (if not yet set)
        if (config.command == Command.run && config.scriptPath.length == 0)
        {
            config.scriptPath = arg;
            i++;
            continue;
        }

        // Reject unexpected positional args for commands that don't accept them
        if (config.command == Command.eval_ || config.command == Command.version_
            || config.command == Command.help || config.command == Command.audit
            || config.command == Command.clean || config.command == Command.repl)
        {
            import std.conv : to;
            string cmdName;
            final switch (config.command) {
                case Command.eval_: cmdName = "eval"; break;
                case Command.version_: cmdName = "version"; break;
                case Command.help: cmdName = "help"; break;
                case Command.audit: cmdName = "audit"; break;
                case Command.clean: cmdName = "clean"; break;
                case Command.repl: cmdName = "repl"; break;
                case Command.run: case Command.install: case Command.test_:
                case Command.bench: case Command.init_: case Command.fmt:
                case Command.bundle: case Command.lint:
                    break;
            }
            if (cmdName.length > 0)
            {
                config.errorMessage = "unexpected argument '" ~ arg ~ "' after '" ~ cmdName ~ "'";
                return config;
            }
        }

        // Script arguments (after script path, flags are passed to the script)
        config.scriptArgs ~= arg;
        i++;
    }

    return config;
}

private bool isKnownFlag(string arg) @safe pure nothrow @nogc
{
    import std.algorithm : startsWith;

    return arg == "--verbose" || arg == "-V"
        || arg == "--version" || arg == "-v"
        || arg == "--help" || arg == "-h"
        || arg == "-A"
        || arg.startsWith("--allow-")
        || arg.startsWith("--deny-")
        || arg.startsWith("--max-memory=")
        || arg.startsWith("--max-stack=")
        || arg.startsWith("--eval-file=") || arg == "--eval-file"
        || arg.startsWith("--audit=")
        || arg.startsWith("--filter=")
        || arg.startsWith("--inspect")
        || arg.startsWith("--inspect-brk")
        || arg == "--watch" || arg == "-w"
        || arg == "--typecheck";
}

private bool looksLikeFile(string arg) @safe pure nothrow @nogc
{
    foreach (c; arg)
        if (c == '.' || c == '/')
            return true;
    return false;
}

/// Parse a memory-size argument with optional B/KB/MB/GB suffix.
/// Bare numbers are MiB (so `--max-memory=64` means 64 MiB), matching
/// the convention used by --max-old-space-size / -Xmx.
private size_t parseMemorySize(string s) @safe pure
{
    import std.uni : toLower;
    import std.string : strip;
    import std.conv : to;
    auto t = s.strip;
    if (t.length == 0) return 0;
    size_t digits = 0;
    while (digits < t.length && t[digits] >= '0' && t[digits] <= '9') digits++;
    if (digits == 0) return 0;
    auto numStr = t[0 .. digits];
    auto unit = t[digits .. $].toLower;
    size_t n = numStr.to!size_t;
    size_t mul;
    switch (unit)
    {
        case "":   mul = 1024 * 1024; break; // bare = MiB
        case "b":  mul = 1; break;
        case "k": case "kb": case "kib": mul = 1024; break;
        case "m": case "mb": case "mib": mul = 1024 * 1024; break;
        case "g": case "gb": case "gib": mul = 1024 * 1024 * 1024; break;
        default: return 0;
    }
    return n * mul;
}
