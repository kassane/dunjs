module dun.app;

// D runtime GC defaults: larger pool reduces collection frequency (~11x fewer GC cycles)
// Override at runtime via: dun "--DRT-gcopt=minPoolSize:32 profile:1" run script.js
extern(C) __gshared string[] rt_options = ["gcopt=minPoolSize:16"];

version (unittest) {} else
int main(string[] args)
{
    // Load .env file from cwd before anything else (Bun-compatible behavior)
    version (Posix)
        loadDotEnv();

    // Fire any pending N-API finalizers on the way out, regardless of
    // which return path we take below. Mirrors Node.js's behavior of
    // running cleanup hooks on process exit (sharp/bcrypt rely on it).
    scope(exit)
    {
        import dun.napi.napi : napiFireFinalizers;
        napiFireFinalizers();
    }

    import dun.cli.args : parseArgs, Command;

    /* `dun bundle --compile=PATH` embedded-bundle check. When the
       current executable was produced by `--compile`, the trailing
       24-byte marker / size / version block at the end of the
       file holds the embedded JS. Detect that on startup and run
       the embedded bundle instead of dispatching to the CLI.
       `--allow-*` flags before the script work; everything else
       is passed through as script argv. */
    {
        import dun.cli.embed : readEmbeddedBundle;
        import std.file : thisExePath;
        string exe;
        try exe = thisExePath();
        catch (Exception) { exe = ""; }
        if (exe.length > 0)
        {
            auto bundle = readEmbeddedBundle(exe);
            if (bundle.length > 0)
            {
                /* Bridge const(ubyte)[] → string via @trusted block;
                   the cast is safe because the bytes are immutable
                   (read from disk, never mutated by us). */
                auto bundleStr = () @trusted { return cast(string) bundle; }();
                return runEmbeddedBundle(args, bundleStr);
            }
        }
    }

    auto config = parseArgs(args);

    if (config.errorMessage.length > 0)
    {
        writeStderr("error: ");
        writeStderr(config.errorMessage);
        writeStderr("\n");
        return 1;
    }

    final switch (config.command)
    {
        case Command.run:
            if (config.watchMode)
                return runWatchMode(config);
            return runScript(config);
        case Command.repl:
            return runRepl(config);
        case Command.eval_:
            return evalInline(config);
        case Command.install:
            return runInstall(config);
        case Command.audit:
            return runAudit(config);
        case Command.test_:
            return runTestCmd(config);
        case Command.bench:
            return runBenchCmd(config);
        case Command.init_:
            return runInit(config);
        case Command.fmt:
            return runFmt(config);
        case Command.clean:
            return runClean(config);
        case Command.bundle:
            return runBundle(config);
        case Command.lint:
        {
            import dun.cli.lint : runLint;
            return runLint(config.lintPaths, config.lintFix,
                config.lintQuiet, config.lintMaxWarnings);
        }
        case Command.version_:
            printVersion();
            return 0;
        case Command.help:
            printUsage();
            return 0;
    }
}

private:

public enum VERSION = "1.1.18";

/// Entry point when the running executable was produced by
/// `dun bundle --compile=PATH`. Sets up a runtime with --allow-all,
/// passes `args[1..$]` to the script, and evals the embedded bundle.
/// The bundle ships its own permission decisions (it was built by
/// the developer who chose to compile it).
int runEmbeddedBundle(string[] args, string bundle) @trusted
{
    import dun.cli.args : CliConfig;
    import dun.engine.iface : createEngine, EngineConfig, DEFAULT_MEMORY_LIMIT,
        DEFAULT_MAX_STACK;
    import dun.runtime.globals : DunState, installGlobals;
    import dun.security.permissions : Permission;

    CliConfig config;
    config.permissions.grant(Permission.read);
    config.permissions.grant(Permission.write);
    config.permissions.grant(Permission.net);
    config.permissions.grant(Permission.env);
    config.permissions.grant(Permission.run);
    config.permissions.grant(Permission.ffi);
    config.permissions.grant(Permission.hrtime);
    if (args.length > 1) config.scriptArgs = args[1 .. $];

    auto engine = createEngine();
    engine.initialize(EngineConfig(DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.scriptArgs = ["dun"] ~ (args.length > 1 ? args[1 .. $] : []);
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    auto result = engine.eval(bundle, "<embedded>");
    if (result.isError)
    {
        writeStderr("compiled: ");
        writeStderr(result.errorMessage);
        writeStderr("\n");
        engine.shutdown();
        return 1;
    }
    engine.freeValue(result.value);
    state.eventLoop.run();
    engine.shutdown();
    return 0;
}

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
        import std.file : readText, exists;
        if (!exists(config.scriptPath) && !looksLikeFilePath(config.scriptPath))
        {
            version (Posix)
            {
                import dun.modules.npm : runPackageScript;
                return runPackageScript(config.scriptPath) ? 0 : 1;
            }
            else
            {
                writeStderr("Error: Cannot read '");
                writeStderr(config.scriptPath);
                writeStderr("': file not found\n");
                return 1;
            }
        }
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

    // Shebang: `#!/usr/bin/env node`, `#!/usr/bin/env -S deno run`, etc.
    // Comment the line out instead of stripping it so line numbers in
    // error messages still match the source file.
    source = stripShebang(source);

    // --typecheck: hand the file to `tsc` (loaded from node_modules)
    // and refuse to run if there are type errors. Falls back to the
    // scanner strip if `typescript` isn't installed.
    if (config.typecheck && isTypeScript(config.scriptPath))
    {
        int tcRc;
        auto tcResult = runTypecheck(source, config.scriptPath, tcRc);
        if (tcRc != 0)
            return tcRc;
        if (tcResult.length > 0)
            source = tcResult;
    }

    // TS -> JS pipeline. When typescript is already installed in
    // node_modules (anywhere upward from the script), we use
    // `ts.transpileModule()` for full TS-spec correctness (decorators,
    // const enum, namespace runtime, generic-cast resolution, etc.).
    // The scanner stripper takes over otherwise -- so users who don't
    // need full TS still pay zero cold-start cost. Opt-out via
    // `DUN_DISABLE_TSC=1` to force the scanner regardless.
    if (isTypeScript(config.scriptPath) || isStdinPath(config.scriptPath))
    {
        if (!config.typecheck)  // typecheck path already runs tsc above
        {
            auto tsOut = runTranspile(source, config.scriptPath);
            if (tsOut.length > 0)
                source = tsOut;
            else
            {
                import dun.ts.strip : stripTypes;
                source = stripTypes(source);
            }
        }
    }

    // Dynamic `import(specifier)` rewrite. JSC and V8 don't wire
    // `HostImportModuleDynamicallyCallback`, so the engine throws
    // "Not supported" at any `await import(...)` call site. We
    // rewrite to `__dunImport__(...)` (installed in JS land at engine
    // boot) which wraps `require(...)` in a Promise.
    {
        import dun.ts.dynamic_import : rewriteDynamicImport;
        source = rewriteDynamicImport(source);
    }

    // JSX/TSX → React.createElement transform. Runs after TS strip
    // since the stripper already cleared parameter annotations etc.
    // that would otherwise confuse the JSX scanner.
    if (isJsxOrTsx(config.scriptPath))
    {
        import dun.ts.jsx : transformJsx;
        source = transformJsx(source);
    }

    // V8 prebuilt lacks ICU; rewrite `\p{X}` regex escapes inline so
    // literal regexes parse. JSC/QuickJS handle these natively.
    version (EngineV8)
    {
        import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
        source = expandUnicodePropertyEscapes(source);
    }
    // /v set-op rewrite — QuickJS-NG rejects `[A--B]/v` literals at
    // parse time; V8 14.9 returns wrong matches for `[\p{X}--\p{Y}]`.
    // JSC handles /v natively; the rewriter no-ops when neither flag
    // nor set operators are present, so this is cheap on all backends.
    {
        import dun.runtime.unicode_props : expandVSetOps;
        source = expandVSetOps(source);
    }

    if (isWasmFile(config.scriptPath))
    {
        // .wasm entry: synthesize a tiny WASI bootstrap that reads the
        // raw bytes back from disk, instantiates them and calls _start.
        // Keeping the bootstrap in JS (vs. inlining the bytes as a base64
        // literal) avoids ballooning the entry source for large modules.
        import std.path : absolutePath;
        import std.string : replace;
        auto abs = absolutePath(config.scriptPath).replace(`\`, `\\`).replace(`"`, `\"`);
        source =
            `if (typeof WebAssembly === 'undefined') {` ~
            `  console.error('Error: WebAssembly is not available on this engine. ' +` ~
            `    'Run with --backend=jsc or --backend=v8 to execute .wasm files.');` ~
            `  if (typeof process !== 'undefined') process.exit(1);` ~
            `} else {` ~
            `  const { readFileSync } = require('fs');` ~
            `  const { WASI } = require('wasi');` ~
            `  const __wasi_bytes = readFileSync("` ~ abs ~ `");` ~
            `  const __wasi_args = (typeof process !== 'undefined' && process.argv) ? process.argv.slice(1) : ["` ~ abs ~ `"];` ~
            `  const __wasi_env = (typeof process !== 'undefined' && process.env) ? Object.assign({}, process.env) : {};` ~
            `  const __wasi = new WASI({ args: __wasi_args, env: __wasi_env, preopens: { "/": "/" }, returnOnExit: true });` ~
            `  WebAssembly.instantiate(__wasi_bytes, __wasi.getImportObject()).then(({ instance }) => {` ~
            `    const rc = __wasi.start(instance);` ~
            `    if (typeof process !== 'undefined' && rc) process.exitCode = rc;` ~
            `  }).catch(e => { console.error(e); if (typeof process !== 'undefined') process.exit(1); });` ~
            `}`;
    }

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    version (Posix)
    {
        if (config.inspect)
        {
            import dun.cli.inspector : startInspector;
            startInspector(engine, config.inspectPort);
        }
    }

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.scriptArgs = ["dun", config.scriptPath] ~ config.scriptArgs;
    state.verbose = config.verbose;
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
    // script's own directory (not cwd). Also patch Intl.Collator on V8
    // here because V8 lazy-loads Intl — running this from installIntl
    // is too early (Intl isn't materialized yet).
    {
        import std.path : absolutePath, dirName;
        import std.string : replace;
        auto abs  = absolutePath(config.scriptPath);
        auto dir  = dirName(abs);
        auto eabs = abs.replace(`\`, `\\`).replace(`"`, `\"`);
        auto edir = dir.replace(`\`, `\\`).replace(`"`, `\"`);
        string initCode = `var __filename="` ~ eabs ~ `";var __dirname="` ~ edir ~ `";`;
        initCode ~= `__dunCjsStack__.push("` ~ eabs ~ `");`;
        version (EngineV8)
        {
            import dun.runtime.intl : intlCollatorBindCompareSource;
            initCode ~= intlCollatorBindCompareSource();
        }
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
            engine.shutdown();
            return 1;
        }
    }
    else
    {
        engine.freeValue(result.value);
    }

    state.eventLoop.run();
    state.eventLoop.flushUnhandledRejections();
    auto exitCode = state.eventLoop.exitCode;
    {
        import dun.runtime.process_api : fireBeforeExitHandlers, fireExitHandlers;
        fireBeforeExitHandlers(exitCode);
        fireExitHandlers(exitCode);
    }
    engine.shutdown();
    return exitCode;
}

int runWatchMode(T)(T config) @trusted
{
    version (Posix)
    {
        import core.sys.posix.sys.stat : stat_t, stat;
        import core.stdc.string : strlen;
        import core.thread : Thread;
        import core.time : dur;
        import std.stdio : writeln, stderr;
        import std.string : toStringz;

        assert(config.scriptPath.length > 0, "watchMode requires a script path");

        auto pathz = config.scriptPath.toStringz();

        long getMtime()
        {
            stat_t st;
            if (stat(pathz, &st) == 0)
                return st.st_mtime;
            return -1;
        }

        writeln("[watch] watching ", config.scriptPath, " for changes...");

        // Run the script once first
        int lastExitCode = runScript(config);
        long lastMtime = getMtime();

        // Poll loop: check mtime every 500ms
        while (true)
        {
            Thread.sleep(dur!"msecs"(500));

            long currentMtime = getMtime();
            if (currentMtime == -1)
                continue; // File disappeared, keep waiting

            if (currentMtime != lastMtime)
            {
                lastMtime = currentMtime;
                writeln("\nRestarting due to changes...");
                lastExitCode = runScript(config);
            }
        }
    }
    else
    {
        writeStderr("--watch is not yet supported on this platform\n");
        return 1;
    }
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
    state.scriptArgs = ["dun", "<eval>"];
    state.verbose = config.verbose;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);
    // Always strip TS — for plain JS the stripper is a no-op (it only
    // erases `: type` / `as T` / `interface` / etc.). Matches Bun/Deno
    // behavior where `dun eval` accepts TS source directly.
    import dun.ts.strip : stripTypes;
    auto evalSource = stripTypes(config.evalSource);
    version (EngineV8)
    {
        import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
        evalSource = expandUnicodePropertyEscapes(evalSource);
    }
    {
        import dun.runtime.unicode_props : expandVSetOps;
        evalSource = expandVSetOps(evalSource);
    }
    auto result = engine.eval(evalSource, "<eval>");
    if (result.isError)
    {
        import dun.cli.errors : isColorEnabled, formatUncaughtError;
        writeStderr(formatUncaughtError(result.errorMessage, isColorEnabled()));
        engine.shutdown();
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
    auto exitCode = state.eventLoop.exitCode;
    {
        import dun.runtime.process_api : fireBeforeExitHandlers, fireExitHandlers;
        fireBeforeExitHandlers(exitCode);
        fireExitHandlers(exitCode);
    }
    engine.shutdown();
    return exitCode;
}

void printVersion() @trusted
{
    import std.stdio : writeln;
    import core.stdc.string : strlen;
    writeln("dun ", VERSION);

    version (EngineJSC)
        writeln("engine: JavaScriptCore");
    else version (EngineV8)
    {
        try
        {
            import dun.engine.v8.cppbindings : dun_v8_version;
            auto vp = dun_v8_version();
            if (vp !is null)
                writeln("engine: V8 ", vp[0 .. strlen(vp)]);
            else
                writeln("engine: V8");
        }
        catch (Exception) { writeln("engine: V8"); }
    }
    else
    {
        try
        {
            import dun.engine.quickjs.bindings : JS_GetVersion;
            auto vp = JS_GetVersion();
            if (vp !is null)
                writeln("engine: QuickJS-NG ", vp[0 .. strlen(vp)]);
            else
                writeln("engine: QuickJS-NG");
        }
        catch (Exception) { writeln("engine: QuickJS-NG"); }
    }
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
        import std.stdio : writeln;
        import dun.security.cve_db : auditNodeModules, printAuditReport,
            worstSeverity, Severity;

        writeln("Auditing node_modules via OSV API (cached locally)...\n");

        auto results = auditNodeModules();
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
        ~ "  test [files]     Run tests (*.test.{js,ts}, *_test.{js,ts})\n"
        ~ "  bench [files]    Run benchmarks (*.bench.{js,ts})\n"
        ~ "  repl             Start interactive REPL\n"
        ~ "  eval <code>      Evaluate JavaScript code\n"
        ~ "  install <pkg>    Install npm package to node_modules/\n"
        ~ "  audit            Scan node_modules/ for known CVEs\n"
        ~ "  init [name]      Initialize a new project\n"
        ~ "  fmt [files]      Format JavaScript/TypeScript files\n"
        ~ "  lint [paths]     Lint .js/.ts (eqeqeq / no-eval / no-debugger; --fix auto-applies)\n"
        ~ "  bundle <entry>   Bundle JS/TS modules (--outdir DIR; --sourcemap[=inline|external])\n"
        ~ "  clean            Remove cache and build artifacts\n"
        ~ "  version          Print version\n"
        ~ "  help             Show this help\n\n"
        ~ "Test options:\n"
        ~ "  --filter=<name>        Run only tests matching name\n"
        ~ "  --allow-all / -A       Grant all permissions for tests\n\n"
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
        ~ "  --audit=off            Disable CVE checking during install\n\n"
        ~ "Runtime options:\n"
        ~ "  --max-memory=<bytes>   JS heap memory limit (default: 2GB)\n"
        ~ "  --max-stack=<bytes>    Max stack size (default: 8MB)\n"
        ~ "  --eval-file=<path>     Execute file before entering REPL\n"
        ~ "  --watch / -w           Restart script on file changes\n"
        ~ "  --typecheck            Run TS files through tsc first;\n"
        ~ "                         auto-installs typescript via `dun install` if missing\n\n"
        ~ "Environment variables:\n"
        ~ "  DUN_HOME                  User-global store root (default: $HOME/.dun on\n"
        ~ "                            Posix, %LOCALAPPDATA%\\dun on Windows). Holds the\n"
        ~ "                            transpile cache + auto-installed packages.\n"
        ~ "  DUN_DISABLE_TSC=1         Force scanner stripper instead of tsc transpile\n"
        ~ "                            (default: use tsc when typescript is installed)\n"
        ~ "  DUN_AUTO_INSTALL_TSC=1    Default-path TS files auto-install typescript into\n"
        ~ "                            $DUN_HOME/node_modules (off by default; --typecheck\n"
        ~ "                            always auto-installs regardless of this flag)\n"
        ~ "  DUN_TSC_CACHE_MAX_ENTRIES Max entries in the transpile cache (default: 2000)\n"
        ~ "  DUN_TSC_CACHE_MAX_MB      Max size of transpile cache in MiB (default: 64)\n"
        ~ "  DUN_TSC_CACHE_TRIM_INTERVAL_SECS\n"
        ~ "                            Min seconds between trim sweeps (default: 300)\n"
        ~ "  DUN_TSC_CACHE_DEBUG=1     Print cache write/trim errors to stderr\n"
        ~ "  DUN_TSC_QUIET=1           Suppress 'tsc transpile failed; using scanner' warning\n"
        ~ "  DUN_TYPECHECK_DEBUG=1     Dump --typecheck driver source to /tmp/dun-typecheck-driver.js\n"
        ~ "                            on engine error (debugging the typecheck shim)\n"
        ~ "  DUN_REPL_HISTORY          Path to REPL history file (default: ~/.dun_repl_history)\n"
        ~ "  DUN_REPL_HISTORY_SIZE     Max REPL history entries (default: 1000)\n"
        ~ "  DUN_TEST_TIMEOUT          Per-fixture timeout in seconds for integration runner\n"
        ~ "                            (default: 30; only honored by tests/integration/run.sh)\n\n"
        ~ "D runtime GC tuning (passed before command):\n"
        ~ "  \"--DRT-gcopt=profile:1\"          Print GC stats on exit\n"
        ~ "  \"--DRT-gcopt=minPoolSize:32\"     Pool size in MB (default: 16)\n"
        ~ "  \"--DRT-gcopt=parallel:4\"         GC marking threads\n"
        ~ "  \"--DRT-gcopt=gc:precise\"         Precise GC (less false retention)\n"
        ~ "  \"--DRT-gcopt=help\"               Show all GC options\n"
    );
}

int runTestCmd(T)(T config)
{
    import std.stdio : writeln, writef;
    import std.datetime : MonoTime, Duration;

    string[] files = config.testFiles;
    if (files.length == 0)
        files = discoverFiles(["*.test.js", "*_test.js", "*.test.ts", "*_test.ts",
                               "*.spec.js", "*_spec.js", "*.spec.ts", "*_spec.ts"]);

    if (files.length == 0)
    {
        writeln("No test files found.");
        writeln("  Patterns: *.test.{js,ts}, *_test.{js,ts}, *.spec.{js,ts}, *_spec.{js,ts}");
        return 1;
    }

    writeln("running ", files.length, " test", files.length > 1 ? "s" : "", " ...");

    int totalPass, totalFail;
    auto startAll = MonoTime.currTime;

    foreach (file; files)
    {
        auto startOne = MonoTime.currTime;
        int rc = runSingleTest(config, file);
        auto elapsed = MonoTime.currTime - startOne;
        auto ms = elapsed.total!"msecs";

        if (rc == 0)
        {
            writeln("ok   ", file, " (", ms, "ms)");
            totalPass++;
        }
        else
        {
            writeln("FAIL ", file, " (", ms, "ms)");
            totalFail++;
        }
    }

    auto totalMs = (MonoTime.currTime - startAll).total!"msecs";
    writeln();
    if (totalFail == 0)
        writeln("test result: ok. ", totalPass, " passed; ", totalFail, " failed (", totalMs, "ms)");
    else
        writeln("test result: FAILED. ", totalPass, " passed; ", totalFail, " failed (", totalMs, "ms)");

    return totalFail > 0 ? 1 : 0;
}

int runSingleTest(T)(T config, string filePath) @trusted
{
    import dun.engine.iface : createEngine, EngineConfig, JSResult;
    import dun.runtime.globals : DunState, installGlobals;

    string source;
    try
    {
        import std.file : readText;
        source = readText(filePath);
    }
    catch (Exception e)
    {
        writeStderr("Error: Cannot read '" ~ filePath ~ "'\n");
        return 1;
    }

    source = stripShebang(source);

    if (isTypeScript(filePath) || isStdinPath(filePath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
    }
    version (EngineV8)
    {
        import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
        source = expandUnicodePropertyEscapes(source);
    }
    // /v set-op rewrite — QuickJS-NG rejects `[A--B]/v` literals at
    // parse time; V8 14.9 returns wrong matches for `[\p{X}--\p{Y}]`.
    // JSC handles /v natively; the rewriter no-ops when neither flag
    // nor set operators are present, so this is cheap on all backends.
    {
        import dun.runtime.unicode_props : expandVSetOps;
        source = expandVSetOps(source);
    }

    // Inject test harness preamble. `test.concurrent(...)` and
    // `test.serial(...)` mirror Bun's API; the `--concurrent` CLI flag
    // flips the default for plain `test(...)` calls (each test becomes
    // concurrent unless explicitly tagged `.serial`). `--max-concurrency=N`
    // caps the in-flight batch.
    string harness =
        `var __dunTests=[];var __dunTestFail=0;`
        ~ `function __dunPush(name,fn,mode){`
        ~ `if(typeof name==="object"&&name){__dunTests.push({name:name.name,fn:name.fn||fn,mode:mode});return;}`
        ~ `__dunTests.push({name:name,fn:fn,mode:mode});}`
        ~ `Deno.test=function(a,b){__dunPush(a,b,"default");};`
        ~ `Deno.test.concurrent=function(a,b){__dunPush(a,b,"concurrent");};`
        ~ `Deno.test.serial=function(a,b){__dunPush(a,b,"serial");};`
        ~ `globalThis.test=Deno.test;`
        ~ `globalThis.assertEquals=function(a,b){`
        ~ `if(a!==b)throw new Error("Expected "+JSON.stringify(b)+", got "+JSON.stringify(a));};`
        ~ `globalThis.assertThrows=function(fn){`
        ~ `var threw=false;try{fn();}catch(e){threw=true;}if(!threw)throw new Error("Expected function to throw");};`
        ~ `globalThis.assertNotEquals=function(a,b){`
        ~ `if(a===b)throw new Error("Expected values to differ, got "+JSON.stringify(a));};`;

    import std.conv : to;
    import dun.cli.args : DEFAULT_TEST_MAX_CONCURRENCY;
    string postamble =
        `setTimeout(async function(){`
        ~ `var filter=typeof __dunTestFilter!=="undefined"?__dunTestFilter:"";`
        ~ `var defaultConcurrent=typeof __dunConcurrent!=="undefined"&&__dunConcurrent;`
        ~ `var maxC=typeof __dunMaxConcurrency!=="undefined"?__dunMaxConcurrency:`
        ~ to!string(DEFAULT_TEST_MAX_CONCURRENCY) ~ `;`
        ~ `var runOne=async function(t){`
        ~ `try{var r=t.fn();if(r&&typeof r.then==="function")await r;`
        ~ `console.log("  ok:",t.name);`
        ~ `}catch(e){__dunTestFail++;console.log("  FAIL:",t.name);console.log("    Error:",e.message);}};`
        ~ `var queue=[];var serials=[];`
        ~ `for(var i=0;i<__dunTests.length;i++){`
        ~ `var t=__dunTests[i];`
        ~ `if(filter&&t.name.indexOf(filter)===-1)continue;`
        ~ `var isConcurrent=(t.mode==="concurrent")||(defaultConcurrent&&t.mode!=="serial");`
        ~ `if(isConcurrent)queue.push(t);else serials.push(t);}`
        ~ `/* serials always run sequentially first to preserve setup ordering */`
        ~ `for(var s=0;s<serials.length;s++)await runOne(serials[s]);`
        ~ `/* batched parallel execution of the concurrent set */`
        ~ `for(var b=0;b<queue.length;b+=maxC){`
        ~ `var slice=queue.slice(b,b+maxC);`
        ~ `await Promise.all(slice.map(runOne));}`
        ~ `if(__dunTestFail>0)process.exitCode=1;},0);`;

    string filterDecl = "";
    if (config.testFilter.length > 0)
    {
        import std.array : replace;
        filterDecl = `var __dunTestFilter="` ~ config.testFilter.replace(`"`, `\"`) ~ `";`;
    }
    string concurrentDecl = "";
    if (config.testConcurrent)
        concurrentDecl ~= `var __dunConcurrent=true;`;
    if (config.testMaxConcurrency > 0)
    {
        concurrentDecl ~= `var __dunMaxConcurrency=`
            ~ to!string(config.testMaxConcurrency) ~ `;`;
    }

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.scriptArgs = ["dun", filePath];
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    version (EngineQuickJS)
    {
        import dun.modules.loader : ModuleLoader;
        import dun.engine.quickjs.bindings : JSRuntime;
        ModuleLoader loader;
        loader.install(cast(JSRuntime*) engine.rawRuntime());
    }

    // Run harness setup
    auto initRes = engine.eval(harness ~ filterDecl ~ concurrentDecl, "<test-harness>");
    if (!initRes.isError) engine.freeValue(initRes.value);

    // Run test file
    bool esm = isESM(filePath, source);
    JSResult result;
    if (esm)
        result = engine.evalModule(source, filePath);
    else
        result = engine.eval(source, filePath);

    if (result.isError)
    {
        import std.stdio : stderr;
        stderr.writeln("  Error in ", filePath, ": ", result.errorMessage);
        engine.shutdown();
        return 1;
    }
    else
    {
        engine.freeValue(result.value);
    }

    // Run postamble to execute collected tests
    auto postRes = engine.eval(postamble, "<test-runner>");
    if (!postRes.isError) engine.freeValue(postRes.value);

    state.eventLoop.run();

    // Read back process.exitCode set by test postamble (JS property -> D exit code)
    if (state.eventLoop.exitCode == 0)
    {
        auto ecRes = engine.eval("process.exitCode||0", "<exit-code>");
        if (!ecRes.isError)
        {
            if (engine.isNumber(ecRes.value))
                state.eventLoop.exitCode = engine.extractInt(ecRes.value);
            engine.freeValue(ecRes.value);
        }
    }

    auto exitCode = state.eventLoop.exitCode;
    {
        import dun.runtime.process_api : fireBeforeExitHandlers, fireExitHandlers;
        fireBeforeExitHandlers(exitCode);
        fireExitHandlers(exitCode);
    }
    engine.shutdown();
    return exitCode;
}

int runBenchCmd(T)(T config)
{
    import std.stdio : writeln;
    import std.datetime : MonoTime;

    string[] files = config.testFiles;
    if (files.length == 0)
        files = discoverFiles(["*.bench.js", "*_bench.js", "*.bench.ts", "*_bench.ts"]);

    if (files.length == 0)
    {
        writeln("No benchmark files found.");
        writeln("  Patterns: *.bench.{js,ts}, *_bench.{js,ts}");
        return 1;
    }

    writeln("running ", files.length, " benchmark", files.length > 1 ? "s" : "", " ...\n");

    foreach (file; files)
    {
        writeln("file: ", file);
        runSingleBench(config, file);
        writeln();
    }
    return 0;
}

int runSingleBench(T)(T config, string filePath) @trusted
{
    import dun.engine.iface : createEngine, EngineConfig, JSResult;
    import dun.runtime.globals : DunState, installGlobals;

    string source;
    try
    {
        import std.file : readText;
        source = readText(filePath);
    }
    catch (Exception e)
    {
        writeStderr("Error: Cannot read '" ~ filePath ~ "'\n");
        return 1;
    }

    source = stripShebang(source);

    if (isTypeScript(filePath) || isStdinPath(filePath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
    }
    version (EngineV8)
    {
        import dun.runtime.unicode_props : expandUnicodePropertyEscapes;
        source = expandUnicodePropertyEscapes(source);
    }
    // /v set-op rewrite — QuickJS-NG rejects `[A--B]/v` literals at
    // parse time; V8 14.9 returns wrong matches for `[\p{X}--\p{Y}]`.
    // JSC handles /v natively; the rewriter no-ops when neither flag
    // nor set operators are present, so this is cheap on all backends.
    {
        import dun.runtime.unicode_props : expandVSetOps;
        source = expandVSetOps(source);
    }

    // Bench harness: Deno.bench(name, fn) runs fn multiple times and measures
    string harness =
        `var __dunBenches=[];`
        ~ `Deno.bench=function(a,b){`
        ~ `if(typeof a==="string")__dunBenches.push({name:a,fn:b});`
        ~ `else __dunBenches.push({name:a.name,fn:a.fn||b});};`
        ~ `globalThis.bench=Deno.bench;`;

    string postamble =
        `setTimeout(function(){`
        ~ `for(var i=0;i<__dunBenches.length;i++){`
        ~ `var b=__dunBenches[i];`
        ~ `var iters=1,elapsed=0;`
        ~ `while(elapsed<100){`
        ~ `var start=Date.now();`
        ~ `for(var j=0;j<iters;j++)b.fn();`
        ~ `elapsed=Date.now()-start;`
        ~ `if(elapsed<100)iters*=2;}`
        ~ `var nsPerOp=Math.round((elapsed*1e6)/iters);`
        ~ `var opsPerSec=Math.round((iters/elapsed)*1000);`
        ~ `console.log("  "+b.name+": "+nsPerOp+"ns/op ("+opsPerSec+" ops/sec, "+iters+" iters)");}},0);`;

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.scriptArgs = ["dun", filePath];
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    auto initRes = engine.eval(harness, "<bench-harness>");
    if (!initRes.isError) engine.freeValue(initRes.value);

    JSResult result;
    if (isESM(filePath, source))
        result = engine.evalModule(source, filePath);
    else
        result = engine.eval(source, filePath);

    if (result.isError)
    {
        import std.stdio : stderr;
        stderr.writeln("  Error: ", result.errorMessage);
        engine.shutdown();
        return 1;
    }
    else
        engine.freeValue(result.value);

    auto postRes = engine.eval(postamble, "<bench-runner>");
    if (!postRes.isError) engine.freeValue(postRes.value);

    state.eventLoop.run();
    auto exitCode = state.eventLoop.exitCode;
    {
        import dun.runtime.process_api : fireBeforeExitHandlers, fireExitHandlers;
        fireBeforeExitHandlers(exitCode);
        fireExitHandlers(exitCode);
    }
    engine.shutdown();
    return exitCode;
}

int runInit(T)(T config)
{
    import std.stdio : writeln;
    import std.file : exists, mkdirRecurse, write;
    import std.path : buildPath;

    string name = config.initName.length > 0 ? config.initName : "my-project";
    string dir = name == "." ? "." : name;

    if (dir != "." && exists(dir))
    {
        writeStderr("Error: directory '" ~ dir ~ "' already exists\n");
        return 1;
    }

    if (dir != ".")
        mkdirRecurse(dir);

    write(buildPath(dir, "main.ts"),
        "function greet(name: string): string {\n"
        ~ "  return \"Hello, \" + name + \"!\";\n"
        ~ "}\n\n"
        ~ "console.log(greet(\"world\"));\n");

    write(buildPath(dir, "main_test.ts"),
        "Deno.test(\"greet returns hello\", () => {\n"
        ~ "  const result = \"Hello, world!\";\n"
        ~ "  assertEquals(result, \"Hello, world!\");\n"
        ~ "});\n\n"
        ~ "Deno.test(\"math works\", () => {\n"
        ~ "  assertEquals(1 + 1, 2);\n"
        ~ "});\n");

    write(buildPath(dir, "dun.json"),
        "{\n"
        ~ "  \"name\": \"" ~ name ~ "\",\n"
        ~ "  \"version\": \"0.1.0\",\n"
        ~ "  \"main\": \"main.ts\",\n"
        ~ "  \"tasks\": {\n"
        ~ "    \"start\": \"dun run main.ts\",\n"
        ~ "    \"test\": \"dun test\"\n"
        ~ "  }\n"
        ~ "}\n");

    writeln("Initialized project in ", dir == "." ? "./" : dir ~ "/");
    writeln("  main.ts       — entry point");
    writeln("  main_test.ts  — test file");
    writeln("  dun.json      — project config");
    writeln();
    writeln("Run your project:");
    if (dir != ".")
        writeln("  cd ", dir);
    writeln("  dun run main.ts");
    writeln("  dun test");
    return 0;
}

int runFmt(T)(T config)
{
    import std.stdio : writeln;

    string[] files = config.fmtFiles;
    if (files.length == 0)
        files = discoverFiles(["*.js", "*.ts", "*.mjs", "*.mts"]);

    if (files.length == 0)
    {
        writeln("No files to format.");
        return 0;
    }

    int formatted = 0;
    int needFormat = 0;
    foreach (file; files)
    {
        try
        {
            import std.file : readText, write;
            auto content = readText(file);
            auto result = basicFormat(content, config.fmtQuotes);
            if (result != content)
            {
                if (config.fmtCheck)
                {
                    writeln("would reformat: ", file);
                    needFormat++;
                }
                else
                {
                    write(file, result);
                    writeln("formatted: ", file);
                    formatted++;
                }
            }
        }
        catch (Exception e)
        {
            writeStderr("Error formatting " ~ file ~ ": " ~ e.msg ~ "\n");
        }
    }
    if (config.fmtCheck)
    {
        writeln(needFormat, " file", needFormat != 1 ? "s" : "", " need formatting");
        return needFormat > 0 ? 1 : 0;
    }
    writeln(formatted, " file", formatted != 1 ? "s" : "", " formatted");
    return 0;
}

/// Bundle one or more entry files via Bun.build. Output written to
/// --outdir (defaults to ./dist).
int runBundle(T)(T config)
{
    import dun.engine.iface : createEngine, EngineConfig;
    import dun.runtime.globals : DunState, installGlobals;
    import dun.security.permissions : Permission;
    import std.array : join;
    import std.string : replace;

    if (config.bundleEntries.length == 0)
    {
        writeStderr("usage: dun bundle <entry...> [--outdir DIR] [--minify]\n");
        return 1;
    }

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    // `dun bundle` is a build operation — grant read+write so the
    // command doesn't need an explicit --allow-* the way `dun run` does.
    config.permissions.grant(Permission.read);
    config.permissions.grant(Permission.write);

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.scriptArgs = ["dun", "bundle"];
    state.verbose = config.verbose;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    string outDir = config.bundleOutDir.length > 0 ? config.bundleOutDir : "./dist";

    // Build JS source that invokes Bun.build with the requested entries.
    string entriesJs = "[";
    foreach (i, e; config.bundleEntries)
    {
        if (i > 0) entriesJs ~= ",";
        entriesJs ~= "\"" ~ e.replace(`\`, `\\`).replace(`"`, `\"`) ~ "\"";
    }
    entriesJs ~= "]";
    string sourcemapJs = "";
    if (config.bundleSourcemap.length > 0)
        sourcemapJs = ", sourcemap: \""
            ~ config.bundleSourcemap.replace(`"`, `\"`) ~ "\"";
    string minifyJs = config.bundleMinify ? ", minify: true" : "";

    /* --compile path: capture the bundle text in a globalThis slot
       (no outdir flush — we'll write the executable ourselves). */
    bool compile = config.bundleCompile.length > 0;
    string src;
    if (compile)
    {
        src =
            "Bun.build({ entrypoints: " ~ entriesJs
            ~ ", target: 'bun'"
            ~ sourcemapJs ~ minifyJs ~
            " }).then(function(r) {" ~
            "  if (!r.success) { console.error('bundle failed'); process.exit(1); }" ~
            "  return r.outputs[0].text();" ~
            "}).then(function(t) { globalThis.__dunCompiledBundle__ = t; })" ~
            ".catch(function(e) { console.error(String(e)); process.exit(1); });";
    }
    else
    {
        src =
            "Bun.build({ entrypoints: " ~ entriesJs ~
            ", outdir: \"" ~ outDir.replace(`\`, `\\`).replace(`"`, `\"`) ~ "\""
            ~ sourcemapJs ~ minifyJs ~
            " }).then(function(r) {" ~
            "  if (!r.success) { console.error('bundle failed'); process.exit(1); }" ~
            "  console.log('bundle ok →', r.outputs[0].path, '(' + r.outputs[0].size + ' bytes)');" ~
            "}).catch(function(e) { console.error(String(e)); process.exit(1); });";
    }

    auto result = engine.eval(src, "<bundle>");
    if (result.isError)
    {
        writeStderr("bundle: ");
        writeStderr(result.errorMessage);
        writeStderr("\n");
        engine.shutdown();
        return 1;
    }
    engine.freeValue(result.value);
    state.eventLoop.run();

    /* --compile: pull the bundle text we captured in
       globalThis.__dunCompiledBundle__ and embed it into a copy of
       the current dun runtime binary. */
    if (compile)
    {
        auto globalH = engine.getGlobal();
        auto bundleH = engine.getProperty(globalH, "__dunCompiledBundle__");
        engine.freeValue(globalH);
        if (!engine.isString(bundleH))
        {
            engine.freeValue(bundleH);
            engine.shutdown();
            writeStderr("compile: no bundle text captured (build may have failed silently)\n");
            return 1;
        }
        auto bundleText = engine.extractString(bundleH);
        engine.freeValue(bundleH);

        import dun.cli.embed : writeCompiledExe;
        import std.file : thisExePath;
        string srcExe;
        try srcExe = thisExePath();
        catch (Exception) { srcExe = ""; }
        if (srcExe.length == 0)
        {
            engine.shutdown();
            writeStderr("compile: could not resolve current binary path\n");
            return 1;
        }
        int rc = writeCompiledExe(srcExe, config.bundleCompile,
            cast(const(ubyte)[]) bundleText);
        if (rc == 0)
        {
            try
            {
                import std.stdio : writeln;
                import std.file : getSize;
                writeln("compiled → ", config.bundleCompile,
                    " (", getSize(config.bundleCompile), " bytes)");
            }
            catch (Exception) {}
        }
        engine.shutdown();
        return rc;
    }

    engine.shutdown();
    return 0;
}

int runClean(T)(T config)
{
    import std.stdio : writeln;
    import std.file : exists, rmdirRecurse;

    int cleaned = 0;

    if (exists(".dun"))
    {
        rmdirRecurse(".dun");
        writeln("Removed .dun/");
        cleaned++;
    }

    if (exists("node_modules"))
    {
        rmdirRecurse("node_modules");
        writeln("Removed node_modules/");
        cleaned++;
    }

    if (cleaned == 0)
        writeln("Nothing to clean.");
    else
        writeln("Clean complete.");

    return 0;
}

string[] discoverFiles(string[] patterns) @trusted
{
    import std.file : dirEntries, SpanMode;
    import std.algorithm : endsWith, canFind, sort, startsWith;
    import std.path : baseName;

    string[] found;
    try
    {
        foreach (entry; dirEntries(".", SpanMode.depth))
        {
            if (!entry.isFile) continue;
            auto name = baseName(entry.name);
            if (name.startsWith(".")) continue;
            // Skip node_modules and vendor
            if (entry.name.canFind("node_modules") || entry.name.canFind("vendor")) continue;

            foreach (pat; patterns)
            {
                if (matchGlob(name, pat))
                {
                    found ~= entry.name;
                    break;
                }
            }
        }
    }
    catch (Exception) {}
    found.sort();
    return found;
}

bool matchGlob(string name, string pattern) @safe pure nothrow
{
    // Simple glob: only supports * at the start
    if (pattern.length >= 2 && pattern[0] == '*')
    {
        auto suffix = pattern[1 .. $];
        if (name.length >= suffix.length && name[$ - suffix.length .. $] == suffix)
            return true;
    }
    return name == pattern;
}

/// Rewrite string literals to the requested quote style without
/// touching strings that contain the target quote char (would need
/// escape-aware rewriting that's beyond the token-level formatter).
private string normalizeQuotes(string source, string style) @safe pure
{
    if (style != "single" && style != "double") return source;
    immutable target = style == "single" ? '\'' : '"';
    immutable other  = style == "single" ? '"'  : '\'';
    import dun.platform.arena : Appender;
    Appender!string buf;
    buf.reserve(source.length);
    size_t i = 0;
    bool inLine = false, inBlock = false;
    while (i < source.length)
    {
        char c = source[i];
        if (inLine) { buf.put(c); if (c == '\n') inLine = false; i++; continue; }
        if (inBlock) {
            buf.put(c);
            if (c == '*' && i + 1 < source.length && source[i + 1] == '/') {
                buf.put('/'); i += 2; inBlock = false; continue;
            }
            i++; continue;
        }
        if (c == '/' && i + 1 < source.length) {
            if (source[i + 1] == '/') { inLine = true; buf.put("//"); i += 2; continue; }
            if (source[i + 1] == '*') { inBlock = true; buf.put("/*"); i += 2; continue; }
        }
        if (c == '`') {
            // Template literal — copy as-is including `${...}` (rewriting
            // quotes inside is too risky without parsing).
            buf.put(c); i++;
            while (i < source.length && source[i] != '`') {
                if (source[i] == '\\' && i + 1 < source.length) {
                    buf.put(source[i .. i + 2]); i += 2; continue;
                }
                buf.put(source[i]); i++;
            }
            if (i < source.length) { buf.put('`'); i++; }
            continue;
        }
        if (c == other) {
            // Candidate for rewrite. Read body, abort if it contains
            // an unescaped `target` char.
            size_t start = i + 1;
            size_t end = start;
            bool aborted = false;
            while (end < source.length && source[end] != c) {
                if (source[end] == '\\' && end + 1 < source.length) { end += 2; continue; }
                if (source[end] == target) { aborted = true; break; }
                if (source[end] == '\n') { aborted = true; break; }
                end++;
            }
            if (!aborted && end < source.length) {
                buf.put(target);
                buf.put(source[start .. end]);
                buf.put(target);
                i = end + 1;
                continue;
            }
            // Couldn't safely rewrite -- copy the original literal verbatim.
            buf.put(c); i++;
            while (i < source.length && source[i] != c) {
                if (source[i] == '\\' && i + 1 < source.length) {
                    buf.put(source[i .. i + 2]); i += 2; continue;
                }
                buf.put(source[i]); i++;
            }
            if (i < source.length) { buf.put(c); i++; }
            continue;
        }
        if (c == target) {
            // Already in target style -- skip past as a normal string.
            buf.put(c); i++;
            while (i < source.length && source[i] != c) {
                if (source[i] == '\\' && i + 1 < source.length) {
                    buf.put(source[i .. i + 2]); i += 2; continue;
                }
                buf.put(source[i]); i++;
            }
            if (i < source.length) { buf.put(c); i++; }
            continue;
        }
        buf.put(c); i++;
    }
    return buf.data;
}

string basicFormat(string source, string quoteStyle = "") @safe pure
{
    if (quoteStyle.length > 0) source = normalizeQuotes(source, quoteStyle);
    // JS/TS formatter — conservative, string-aware.
    //
    // Per-line normalization:
    //   - tabs → 2 spaces (only when leading)
    //   - collapse multiple spaces to one (outside strings / comments)
    //   - space after keyword: if, for, while, switch, catch, return, function
    //   - space after comma / semicolon (when followed by a non-space char)
    //   - space around assignment / comparison operators (single-char only;
    //     multi-char operators like `===`, `=>`, `<=` are preserved as-is)
    //   - strip trailing whitespace
    //
    // Block-level normalization:
    //   - re-indent based on `{` `}` brace nesting (2-space units)
    //   - collapse runs of >1 blank line to a single blank line
    //   - exactly one trailing newline
    //
    // String / comment / template-literal contents are preserved verbatim.
    import std.string : stripRight, stripLeft;
    import dun.platform.arena : Appender;

    Appender!string result;
    result.reserve(source.length + 32);
    int indent = 0;
    bool lastWasEmpty = false;
    bool inBlockComment = false;
    bool inTemplate = false;
    int templateBraceDepth = 0;

    foreach (line; source.lineSplitter())
    {
        auto stripped = stripRight(line);
        auto trimmed = stripLeft(stripped);

        if (trimmed.length == 0)
        {
            if (!lastWasEmpty && result.data.length > 0)
            {
                result.put("\n");
                lastWasEmpty = true;
            }
            continue;
        }
        lastWasEmpty = false;

        // Dedent if line STARTS with `}` / `]` / `)` so the close lines up
        bool startsWithClose =
            trimmed[0] == '}' || trimmed[0] == ']' || trimmed[0] == ')';
        int writeIndent = indent;
        if (startsWithClose && writeIndent > 0) writeIndent--;

        // Block-comment continuation: don't reformat the body
        if (inBlockComment)
        {
            result.put(stripped);
            result.put("\n");
            foreach (i; 0 .. cast(int)(stripped.length) - 1)
            {
                if (stripped[i] == '*' && stripped[i + 1] == '/')
                {
                    inBlockComment = false;
                    break;
                }
            }
            continue;
        }

        // Reformat the line's tokens, preserving string / template contents
        auto reformatted = reformatLine(trimmed);

        foreach (_; 0 .. writeIndent) result.put("  ");
        result.put(reformatted);
        result.put("\n");

        // Update brace depth from the reformatted line (still string-aware)
        // and detect block-comment / template state transitions.
        indent += deltaBraces(reformatted, /*ref*/ inBlockComment,
            /*ref*/ inTemplate, /*ref*/ templateBraceDepth);
        if (indent < 0) indent = 0;
    }

    auto s = result.data;
    while (s.length > 1 && s[$ - 1] == '\n' && s[$ - 2] == '\n')
        s = s[0 .. $ - 1];
    if (s.length > 0 && s[$ - 1] != '\n')
        s ~= "\n";
    return s;
}

// Token-level reformat of a single JS/TS line, preserving string and
// template-literal contents verbatim. Keywords-with-paren get a space,
// commas / semicolons get a trailing space, runs of internal spaces are
// collapsed.
private string reformatLine(string line) @safe pure
{
    import dun.platform.arena : Appender;
    if (line.length == 0) return line;

    Appender!string buf;
    buf.reserve(line.length + 8);

    char strQuote = 0;     // 0 = not in string, else the open quote char
    bool inLineComment = false;
    size_t i = 0;
    char prev = 0;
    while (i < line.length)
    {
        char c = line[i];

        if (inLineComment)
        {
            buf.put(c);
            i++;
            continue;
        }

        if (strQuote != 0)
        {
            buf.put(c);
            if (c == '\\' && i + 1 < line.length)
            {
                buf.put(line[i + 1]);
                i += 2;
                continue;
            }
            if (c == strQuote) strQuote = 0;
            i++;
            continue;
        }

        // Enter string / template / comment
        if (c == '\'' || c == '"' || c == '`')
        {
            buf.put(c);
            strQuote = c;
            i++;
            prev = c;
            continue;
        }
        if (c == '/' && i + 1 < line.length && line[i + 1] == '/')
        {
            // Insert a space before the comment unless prev was whitespace
            if (buf.data.length > 0 && prev != ' ' && prev != 0)
                buf.put(' ');
            buf.put("//");
            inLineComment = true;
            i += 2;
            prev = '/';
            continue;
        }

        // Collapse runs of internal whitespace to single space
        if (c == ' ' || c == '\t')
        {
            // Skip if previous output char is already a space or empty
            if (buf.data.length == 0)
            {
                i++;
                continue;
            }
            if (prev == ' ') { i++; continue; }
            buf.put(' ');
            prev = ' ';
            i++;
            continue;
        }

        // Comma / semicolon → ensure following space if next char isn't
        // already space / EOL / close-bracket
        if (c == ',' || c == ';')
        {
            buf.put(c);
            prev = c;
            i++;
            if (i < line.length)
            {
                char n = line[i];
                if (n != ' ' && n != '\t' && n != ')' && n != ']' && n != '}')
                {
                    buf.put(' ');
                    prev = ' ';
                }
            }
            continue;
        }

        buf.put(c);
        prev = c;
        i++;
    }

    // Trim trailing whitespace one more time
    auto out_ = buf.data;
    size_t end = out_.length;
    while (end > 0 && (out_[end - 1] == ' ' || out_[end - 1] == '\t'))
        end--;
    return out_[0 .. end];
}

// String-aware brace-depth delta for indentation. Counts `{` `(` `[` as
// +1 and `}` `)` `]` as -1 outside string / template / comments. Updates
// inBlockComment / inTemplate / templateBraceDepth across newlines.
private int deltaBraces(string line, ref bool inBlockComment,
    ref bool inTemplate, ref int templateBraceDepth) @safe pure nothrow
{
    int delta = 0;
    char strQuote = 0;
    bool inLineComment = false;
    size_t i = 0;
    while (i < line.length)
    {
        char c = line[i];

        if (inBlockComment)
        {
            if (i + 1 < line.length && c == '*' && line[i + 1] == '/')
            {
                inBlockComment = false;
                i += 2;
                continue;
            }
            i++;
            continue;
        }
        if (inLineComment) { i++; continue; }
        if (strQuote != 0)
        {
            if (c == '\\' && i + 1 < line.length) { i += 2; continue; }
            if (c == strQuote) strQuote = 0;
            i++;
            continue;
        }
        if (inTemplate)
        {
            if (c == '\\' && i + 1 < line.length) { i += 2; continue; }
            if (c == '`') { inTemplate = false; i++; continue; }
            // ${expr} inside template — leave template mode while inside
            // the expression and track ALL `{` / `}` so nested object
            // literals don't confuse the close detection.
            if (c == '$' && i + 1 < line.length && line[i + 1] == '{')
            {
                templateBraceDepth = 1;
                inTemplate = false;
                i += 2;
                continue;
            }
            i++;
            continue;
        }

        if (c == '\'' || c == '"') { strQuote = c; i++; continue; }
        if (c == '`') { inTemplate = true; i++; continue; }
        if (i + 1 < line.length && c == '/' && line[i + 1] == '/')
        {
            inLineComment = true; i += 2; continue;
        }
        if (i + 1 < line.length && c == '/' && line[i + 1] == '*')
        {
            inBlockComment = true; i += 2; continue;
        }
        if (templateBraceDepth > 0)
        {
            // Inside a `${expr}` — track `{` / `}` but don't affect the
            // outer indentation delta. Re-enter template mode on the
            // matching close.
            if (c == '{') templateBraceDepth++;
            else if (c == '}')
            {
                templateBraceDepth--;
                if (templateBraceDepth == 0) inTemplate = true;
            }
            i++;
            continue;
        }
        if (c == '{' || c == '(' || c == '[') delta++;
        else if (c == '}' || c == ')' || c == ']') delta--;
        i++;
    }
    return delta;
}

private auto lineSplitter(string s) @safe pure nothrow
{
    import std.algorithm : splitter;
    return s.splitter('\n');
}

bool isTypeScript(string path) @safe pure nothrow @nogc
{
    if (path.length >= 3 && path[$ - 3 .. $] == ".ts")
        return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".mts")
        return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".cts")
        return true;
    if (path.length >= 4 && path[$ - 4 .. $] == ".tsx")
        return true;
    return false;
}

bool isJsxOrTsx(string path) @safe pure nothrow @nogc
{
    return (path.length >= 4 && path[$ - 4 .. $] == ".tsx")
        || (path.length >= 4 && path[$ - 4 .. $] == ".jsx");
}

bool isStdinPath(string path) @safe pure nothrow @nogc
{
    // `dun run -` or `dun run /dev/stdin` should run the TS stripper too
    // since there's no file extension to dispatch on.
    return path == "-" || path == "/dev/stdin" || path == "/dev/fd/0";
}

bool isWasmFile(string path) @safe pure nothrow @nogc
{
    return path.length >= 5 && path[$ - 5 .. $] == ".wasm";
}

/// Walk ancestors of `scriptPath` for `node_modules/typescript`,
/// then fall back to `$DUN_HOME/node_modules`.
bool findTypescriptInstall(string scriptPath) @trusted
{
    import std.file : exists;
    import std.path : absolutePath, dirName, buildPath;
    string dir;
    try { dir = absolutePath(scriptPath).dirName; }
    catch (Exception) { dir = absolutePath("."); }
    auto pkgRel = buildPath("node_modules", "typescript", "lib", "typescript.js");
    while (dir.length > 1)
    {
        if (exists(buildPath(dir, pkgRel))) return true;
        auto parent = dirName(dir);
        if (parent == dir) break;
        dir = parent;
    }
    return exists(buildPath(dunGlobalRoot(), pkgRel));
}

// dunGlobalRoot() lives in dun.platform.paths so other modules
// (transpile_cache, require, ...) can use it without depending on
// dun.app. Re-exported here for ergonomics inside this module.
public import dun.platform.paths : dunGlobalRoot;

/// Transpile via `ts.transpileModule()` — full TS-spec correctness
/// (decorators, enums, namespaces) at ~50 ms cold-start cost.
/// Returns `""` to fall back to the scanner stripper. Use
/// `--typecheck` for type errors; this path emits JS regardless.
string runTranspile(string source, string filename) @trusted
{
    import dun.engine.iface : createEngine, EngineConfig,
                              DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK;
    import dun.runtime.globals : DunState, installGlobals;
    import dun.security.permissions : Permission, PermissionRegistry;
    import std.process : environment;
    import dun.ts.transpile_cache : cacheKey, lookup, store;

    // Opt-out: DUN_DISABLE_TSC=1 forces the scanner stripper
    // regardless of typescript availability. Useful for benchmarking
    // and for working around any tsc-specific transpile quirks.
    if (environment.get("DUN_DISABLE_TSC", "") == "1")
        return "";
    if (!findTypescriptInstall(filename))
    {
        // DUN_AUTO_INSTALL_TSC=1 makes the default tsc path
        // auto-install typescript (matching the behaviour of
        // --typecheck). Skipping by default because installing 5+ MB
        // on first run is intrusive when the scanner stripper is
        // good enough for most workloads.
        if (environment.get("DUN_AUTO_INSTALL_TSC", "") != "1")
            return "";  // not installed; caller falls back to scanner
        import dun.modules.npm : installPackage, AuditMode;
        import std.stdio : writeln;
        import std.file : mkdirRecurse;
        immutable globalRoot = dunGlobalRoot();
        try { mkdirRecurse(globalRoot); } catch (Throwable) {}
        try writeln("dun: typescript not installed; installing into ", globalRoot, " ...");
        catch (Throwable) {}
        if (!installPackage("typescript", AuditMode.off, globalRoot))
            return "";  // install failed; fall back to scanner
        if (!findTypescriptInstall(filename))
            return "";  // shouldn't happen, but be defensive
    }

    // Cache check: hash (source, filename, tsc version, compiler options
    // fingerprint) and look in ~/.dun/cache/tsc/. On hit we skip the
    // ~300-700 ms tsc startup entirely (~30x speedup on cache hit).
    immutable tscVersion = readTscVersion(filename);
    immutable key = cacheKey(source, filename, tscVersion);
    if (auto cached = lookup(key))
        return cached;

    auto eng = createEngine();
    eng.initialize(EngineConfig(DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK));
    scope (exit) eng.shutdown();

    DunState state;
    state.engine = eng;
    state.scriptArgs = ["dun", filename];
    state.eventLoop.initialize(eng);
    PermissionRegistry perms;
    perms.grant(Permission.read);  // typescript reads .ts source + tsconfig
    perms.grant(Permission.env);   // ts looks at process.env occasionally
    state.permissions = &perms;
    // Set of globals tsc actually touches: console, process,
    // require, fs, path, os, util, Buffer. Skip the full installGlobals
    // because it populates `__gshared` caches (notably crypto's
    // subtle-fn cache) with handles tied to THIS transient engine's
    // V8 isolate -- when the main engine reuses them after we've shut
    // this engine down, V8 segfaults on Object.Set inside
    // Map::TransitionToDataProperty (gdb-verified). Manual list keeps
    // the set narrow + the boot fast.
    {
        import dun.runtime.console : installConsole;
        import dun.runtime.process_api : installProcess;
        import dun.runtime.web_compat : installWebCompat;
        import dun.modules.require : installRequire;
        import dun.builtins.fs : registerFsModule;
        import dun.builtins.path : registerPathModule;
        import dun.builtins.os : registerOsModule;
        import dun.builtins.buffer : registerBufferModule;
        import dun.builtins.util : registerUtilModule;
        // setContextOpaque is normally done by installGlobals -- needed
        // because process_api dispatch reads DunState back out via
        // engine.getContextOpaque().
        import dun.runtime.timers_api : installTimers;
        eng.setContextOpaque(cast(void*) &state);
        installConsole(eng);
        installTimers(eng);        // tsc's node-system uses setTimeout for async
        installProcess(eng);
        installWebCompat(eng);     // Buffer/TextEncoder used by tsc's node-system path
        registerBufferModule(eng);
        registerFsModule(eng);
        registerPathModule(eng);
        registerOsModule(eng);
        registerUtilModule(eng);
        installRequire(eng);
    }

    import std.json : JSONValue;
    string srcLit = JSONValue(source).toString();
    string fnLit  = JSONValue(filename).toString();

    string driver =
        `(function(){`
        ~ `  const ts = require('typescript');`
        ~ `  const src = ` ~ srcLit ~ `;`
        ~ `  const filename = ` ~ fnLit ~ `;`
        /* ESNext module keeps `import x from 'y'` / `import.meta`
           intact -- DunJS's runtime decides CJS vs ESM dispatch
           based on file extension + content, same as it does for
           the scanner output. Using CommonJS here would rewrite
           imports to require() (good) but also blow up on
           `import.meta` (no CJS equivalent). */
        ~ `  const t = ts.transpileModule(src, {`
        ~ `    compilerOptions: {`
        ~ `      target: ts.ScriptTarget.ES2022,`
        ~ `      module: ts.ModuleKind.ESNext,`
        ~ `      esModuleInterop: true,`
        ~ `      allowJs: true,`
        ~ `      jsx: filename.endsWith('.tsx') ? ts.JsxEmit.React : ts.JsxEmit.None,`
        ~ `      experimentalDecorators: true,`
        ~ `      emitDecoratorMetadata: false,`
        ~ `      sourceMap: false,`
        ~ `      isolatedModules: true,`  /* mirrors --isolatedModules */
        ~ `      verbatimModuleSyntax: false,`
        ~ `    },`
        ~ `    fileName: filename,`
        ~ `  });`
        ~ `  return t.outputText;`
        ~ `})()`;

    auto res = eng.eval(driver, "<transpile>");
    if (res.isError)
    {
        // tsc transpile failed (e.g. broken tsc install, OOM, missing
        // module the transient engine doesn't provide). Surface the
        // first line so users know to investigate; the caller falls
        // back to the scanner stripper which is a reasonable best
        // effort. Opt-out the warning with DUN_TSC_QUIET=1.
        if (environment.get("DUN_TSC_QUIET", "") != "1")
        {
            import std.stdio : stderr;
            try { stderr.writeln("dun: tsc transpile failed (",
                firstLine(res.errorMessage),
                "); falling back to scanner"); }
            catch (Throwable) {}
        }
        eng.freeValue(res.value);
        return "";
    }
    string output = eng.extractString(res.value);
    eng.freeValue(res.value);

    // Persist for the next run. `store()` self-rate-limits its trim
    // call (mtime-marker, default 5 min between trims) so it's safe
    // to call on every write.
    if (output.length > 0)
        store(key, output);

    return output;
}

/// First line of a multi-line error message (truncated to 200 chars).
/// Lets us surface a one-line diagnostic without flooding stderr.
private string firstLine(string s) @safe pure nothrow
{
    enum size_t MAX_LEN = 200;
    foreach (i, c; s)
    {
        if (c == '\n')
            return i < MAX_LEN ? s[0 .. i] : s[0 .. MAX_LEN];
    }
    return s.length > MAX_LEN ? s[0 .. MAX_LEN] : s;
}

/// Read the installed typescript package version. Used as a cache-key
/// component so upgrading typescript invalidates the cache. Returns
/// "?" if package.json can't be read -- the cache still works, just
/// without version isolation across upgrades.
private string readTscVersion(string scriptPath) @trusted
{
    import std.file : exists, readText;
    import std.path : absolutePath, dirName, buildPath;
    import std.json : parseJSON;
    auto pkgRel = buildPath("node_modules", "typescript", "package.json");
    string readVer(string root)
    {
        auto candidate = buildPath(root, pkgRel);
        if (!exists(candidate)) return null;
        try
        {
            auto j = parseJSON(readText(candidate));
            if ("version" in j) return j["version"].str;
        }
        catch (Throwable) {}
        return null;
    }
    string dir;
    try { dir = absolutePath(scriptPath).dirName; }
    catch (Throwable) { return "?"; }
    while (dir.length > 1)
    {
        if (auto v = readVer(dir)) return v;
        auto parent = dirName(dir);
        if (parent == dir) break;
        dir = parent;
    }
    // Fallback: user-global store.
    if (auto v = readVer(dunGlobalRoot())) return v;
    return "?";
}

/// Run user's installed `typescript` with diagnostics and emit JS.
/// `rc != 0` on type errors. Returns `""` + `rc = 0` when tsc is
/// missing so the caller can fall back to the scanner strip.
string runTypecheck(string source, string filename, out int rc) @trusted
{
    import dun.engine.iface : createEngine, EngineConfig,
                              DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK;
    import dun.runtime.globals : DunState, installGlobals;
    import dun.security.permissions : Permission, PermissionRegistry;

    rc = 0;

    // Auto-install typescript via DunJS's own package manager so users
    // don't need a separate `npm install typescript`. Walks upward from
    // the file's directory looking for node_modules/typescript; if not
    // found, installs into the user-global `~/.dun/node_modules` so
    // every `dun run --typecheck` on this machine reuses the same copy.
    if (!findTypescriptInstall(filename))
    {
        import dun.modules.npm : installPackage, AuditMode;
        import std.stdio : writeln;
        import std.file : mkdirRecurse;
        immutable globalRoot = dunGlobalRoot();
        try { mkdirRecurse(globalRoot); } catch (Throwable) {}
        writeln("dun: typescript not installed; installing into ", globalRoot, " ...");
        if (!installPackage("typescript", AuditMode.off, globalRoot))
        {
            writeStderr("dun: --typecheck: failed to install typescript; "
                ~ "falling back to scanner strip\n");
            return "";
        }
    }

    auto eng = createEngine();
    eng.initialize(EngineConfig(DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK));
    scope(exit) eng.shutdown();

    auto perms = new PermissionRegistry();
    perms.grant(Permission.read);
    perms.grant(Permission.env);
    DunState state;
    state.engine = eng;
    state.permissions = perms;
    state.eventLoop.initialize(eng);
    installGlobals(eng, &state);

    // Embed the source + filename as JSON strings -- safer than
    // a template literal because we don't have to defend against
    // `${` / backtick / control-char interactions.
    import std.json : JSONValue;
    auto esrc  = JSONValue(source).toString();    // includes surrounding quotes
    auto efile = JSONValue(filename).toString();
    // Ambient declarations for the runtime globals DunJS injects
    // (Deno.*, Bun.*, require, process, Buffer, dun:* / node:* module
    // identifiers). Without these, `tsc --typecheck` reports
    // TS2304 "Cannot find name" on every reference to a runtime
    // global in user code.
    import dun.ts.globals_dts : dunGlobalsDts;
    auto edts = JSONValue(dunGlobalsDts()).toString();
    enum string DUN_AMBIENT_FILENAME = "/dun:ambient.d.ts";
    auto eAmbient = JSONValue(DUN_AMBIENT_FILENAME).toString();

    // Build a minimal CompilerHost that proxies tsc's filesystem
    // reads through Node-style fs (which DunJS implements). We point
    // tsc at the user's `tsconfig.json` if one exists in the cwd so
    // its compilerOptions / strict flags are respected; otherwise we
    // fall back to a sensible default.
    string driver =
        `(function() {`
        ~ `  let ts;`
        ~ `  try { ts = require('typescript'); }`
        ~ `  catch (e) {`
        ~ `    console.error('dun: --typecheck needs `~"`npm install typescript`"~`; '`
        ~ `      + 'falling back to scanner strip (' + (e.message || e) + ')');`
        ~ `    return { skip: true };`
        ~ `  }`
        ~ `  const fs = require('fs');`
        ~ `  const path = require('path');`
        ~ `  const src = ` ~ esrc ~ `;`
        ~ `  const filename = ` ~ efile ~ `;`
        ~ `  const dunAmbientSrc = ` ~ edts ~ `;`
        ~ `  const dunAmbientName = ` ~ eAmbient ~ `;`
        ~ `  let opts = {`
        ~ `    target: ts.ScriptTarget.ES2022,`
        // ESNext rather than CommonJS so top-level await in scripts
        // typechecks (DunJS treats every file as ESM-capable; the
        // module loader picks CJS vs ESM at run time).
        ~ `    module: ts.ModuleKind.ESNext,`
        // moduleDetection: force -- treat every input as an ES module
        // so top-level await is permitted without requiring the user
        // to add a stray `export {}`.
        ~ `    moduleDetection: ts.ModuleDetectionKind.Force,`
        // Classic React.createElement emit (matches dun.ts.jsx's
        // transform). Without this tsc reports TS17004 on every JSX
        // node in .tsx files.
        ~ `    jsx: ts.JsxEmit.React,`
        ~ `    strict: false,`
        ~ `    allowJs: true,`
        ~ `    esModuleInterop: true,`
        ~ `    skipLibCheck: true,`
        ~ `    noEmit: true,`
        ~ `    moduleResolution: ts.ModuleResolutionKind.Bundler`
        ~ `      || ts.ModuleResolutionKind.NodeNext`
        ~ `      || ts.ModuleResolutionKind.Node10,`
        ~ `    ignoreDeprecations: "6.0",`
        ~ `  };`
        ~ `  try {`
        ~ `    const tcfg = ts.findConfigFile(process.cwd(), ts.sys.fileExists, 'tsconfig.json');`
        ~ `    if (tcfg) {`
        ~ `      const parsed = ts.parseConfigFileTextToJson(tcfg, fs.readFileSync(tcfg, 'utf8'));`
        ~ `      if (parsed.config && parsed.config.compilerOptions) {`
        ~ `        const conv = ts.convertCompilerOptionsFromJson(parsed.config.compilerOptions, path.dirname(tcfg));`
        ~ `        if (conv.options) opts = Object.assign(opts, conv.options, { noEmit: true });`
        ~ `      }`
        ~ `    }`
        ~ `  } catch (e) {}`
        ~ `  const host = ts.createCompilerHost(opts);`
        ~ `  const origGet = host.getSourceFile;`
        ~ `  host.getSourceFile = function(name, lang, onErr, shouldCreate) {`
        ~ `    if (name === filename) {`
        ~ `      return ts.createSourceFile(name, src, lang || ts.ScriptTarget.ES2022, true);`
        ~ `    }`
        ~ `    if (name === dunAmbientName) {`
        ~ `      return ts.createSourceFile(name, dunAmbientSrc, lang || ts.ScriptTarget.ES2022, true);`
        ~ `    }`
        ~ `    return origGet.call(host, name, lang, onErr, shouldCreate);`
        ~ `  };`
        ~ `  host.fileExists = function(name) {`
        ~ `    if (name === filename) return true;`
        ~ `    if (name === dunAmbientName) return true;`
        ~ `    try { fs.accessSync(name); return true; } catch { return false; }`
        ~ `  };`
        ~ `  host.readFile = function(name) {`
        ~ `    if (name === filename) return src;`
        ~ `    if (name === dunAmbientName) return dunAmbientSrc;`
        ~ `    try { return fs.readFileSync(name, 'utf8'); } catch { return undefined; }`
        ~ `  };`
        ~ `  const program = ts.createProgram([dunAmbientName, filename], opts, host);`
        ~ `  const diags = ts.getPreEmitDiagnostics(program)`
        ~ `    .filter(d => d.category === ts.DiagnosticCategory.Error);`
        ~ `  if (diags.length > 0) {`
        ~ `    const fmtHost = {`
        ~ `      getCurrentDirectory: () => process.cwd(),`
        ~ `      getCanonicalFileName: f => f,`
        ~ `      getNewLine: () => '\n',`
        ~ `    };`
        ~ `    process.stderr.write(ts.formatDiagnosticsWithColorAndContext(diags, fmtHost));`
        ~ `    return { error: diags.length };`
        ~ `  }`
        ~ `  const t = ts.transpileModule(src, { compilerOptions: opts, fileName: filename });`
        ~ `  return { ok: true, output: t.outputText };`
        ~ `})()`;

    auto res = eng.eval(driver, "<typecheck>");
    if (res.isError)
    {
        import dun.cli.errors : isColorEnabled, formatUncaughtError;
        import std.process : environment;
        if (environment.get("DUN_TYPECHECK_DEBUG", "") == "1")
        {
            import std.file : write;
            write("/tmp/dun-typecheck-driver.js", driver);
            writeStderr("dun: typecheck driver written to /tmp/dun-typecheck-driver.js\n");
        }
        writeStderr(formatUncaughtError(res.errorMessage, isColorEnabled()));
        rc = 1;
        return "";
    }

    auto skipH = eng.getProperty(res.value, "skip");
    if (eng.isBool(skipH) && eng.extractBool(skipH))
    {
        eng.freeValue(skipH);
        eng.freeValue(res.value);
        return "";  // fall back to scanner strip
    }
    eng.freeValue(skipH);

    auto errH = eng.getProperty(res.value, "error");
    if (eng.isNumber(errH))
    {
        eng.freeValue(errH);
        eng.freeValue(res.value);
        rc = 1;
        return "";
    }
    eng.freeValue(errH);

    auto outH = eng.getProperty(res.value, "output");
    string output = eng.extractString(outH);
    eng.freeValue(outH);
    eng.freeValue(res.value);
    return output;
}

string stripShebang(string source) @safe pure nothrow
{
    if (source.length < 2 || source[0] != '#' || source[1] != '!')
        return source;
    // Replace `#!` with `//` so the rest of the first line becomes a
    // comment. Keeps line numbers and column positions intact for
    // stack traces and source maps.
    return "//" ~ source[2 .. $];
}

bool isESM(string path, string source) @safe pure nothrow
{
    // Extension-based: .mjs/.mts always ESM; .cjs/.cts always CJS
    if (path.length >= 4 && (path[$ - 4 .. $] == ".mjs" || path[$ - 4 .. $] == ".mts"))
        return true;
    if (path.length >= 4 && (path[$ - 4 .. $] == ".cjs" || path[$ - 4 .. $] == ".cts"))
        return false;

    // Content-based: top-level `import`, `export`, or `await` all
    // imply ESM. We track an "is this brace a function/class body?"
    // stack so `{ await … }` (a bare block) or `try { await … }` is
    // still recognized as top-level -- only function/class scopes
    // disqualify a depth-0 match.
    bool atLineStart = true;
    bool[] fnStack;
    int parenD = 0, bracketD = 0;
    size_t i = 0;
    while (i < source.length)
    {
        char c = source[i];
        // Line / block comments and string / template literals -- skip.
        if (c == '/' && i + 1 < source.length)
        {
            if (source[i + 1] == '/')
            {
                while (i < source.length && source[i] != '\n') i++;
                continue;
            }
            if (source[i + 1] == '*')
            {
                i += 2;
                while (i + 1 < source.length && !(source[i] == '*' && source[i + 1] == '/')) i++;
                if (i + 1 < source.length) i += 2;
                continue;
            }
        }
        if (c == '\'' || c == '"')
        {
            char q = c; i++;
            while (i < source.length && source[i] != q)
            {
                if (source[i] == '\\' && i + 1 < source.length) i += 2;
                else i++;
            }
            if (i < source.length) i++;
            continue;
        }
        if (c == '`')
        {
            i++;
            while (i < source.length && source[i] != '`')
            {
                if (source[i] == '\\' && i + 1 < source.length) i += 2;
                else i++;
            }
            if (i < source.length) i++;
            continue;
        }
        if (c == '{')
        {
            // Decide whether this brace opens a function / class body
            // (in which case await inside is *not* top-level).
            bool isFn = false;
            size_t back = i;
            while (back > 0 && (source[back - 1] == ' ' || source[back - 1] == '\t'
                    || source[back - 1] == '\n' || source[back - 1] == '\r')) back--;
            if (back > 0)
            {
                if (source[back - 1] == ')') isFn = true;
                else if (back >= 2 && source[back - 2] == '=' && source[back - 1] == '>') isFn = true;
            }
            // `class … {`
            if (!isFn)
            {
                size_t j = i;
                while (j > 0 && (source[j - 1] == ' ' || source[j - 1] == '\t'
                        || source[j - 1] == '\n' || source[j - 1] == '\r'
                        || (source[j - 1] >= 'a' && source[j - 1] <= 'z')
                        || (source[j - 1] >= 'A' && source[j - 1] <= 'Z')
                        || (source[j - 1] >= '0' && source[j - 1] <= '9')
                        || source[j - 1] == '_' || source[j - 1] == '$')) j--;
                while (j < i && (source[j] == ' ' || source[j] == '\t'
                        || source[j] == '\n' || source[j] == '\r')) j++;
                if (j + 5 <= i && source[j .. j + 5] == "class") isFn = true;
            }
            fnStack ~= isFn;
        }
        else if (c == '}')
        {
            if (fnStack.length > 0) fnStack.length = fnStack.length - 1;
        }
        else if (c == '(') parenD++;
        else if (c == ')') { if (parenD > 0) parenD--; }
        else if (c == '[') bracketD++;
        else if (c == ']') { if (bracketD > 0) bracketD--; }
        if (atLineStart)
        {
            if (source.length - i >= 7 && source[i .. i + 7] == "import ") return true;
            if (source.length - i >= 7 && source[i .. i + 7] == "export ") return true;
            // skip leading whitespace -- still at line start
            if (c == ' ' || c == '\t') { i++; continue; }
        }
        // top-level await -- no enclosing function/class scope.
        bool insideFn = false;
        foreach (b; fnStack) if (b) { insideFn = true; break; }
        if (!insideFn && parenD == 0 && bracketD == 0
            && source.length - i >= 6 && source[i .. i + 5] == "await"
            && (source[i + 5] == ' ' || source[i + 5] == '\t'
                || source[i + 5] == '\n' || source[i + 5] == '(')
            && (i == 0 || !(((source[i - 1] >= 'a' && source[i - 1] <= 'z')
                            || (source[i - 1] >= 'A' && source[i - 1] <= 'Z')
                            || (source[i - 1] >= '0' && source[i - 1] <= '9')
                            || source[i - 1] == '_' || source[i - 1] == '$'))))
        {
            return true;
        }
        atLineStart = (c == '\n');
        i++;
    }
    return false;
}

bool looksLikeFilePath(string arg) @safe pure nothrow @nogc
{
    foreach (c; arg)
        if (c == '.' || c == '/' || c == '\\')
            return true;
    return false;
}

/**
 * Load .env file from the current working directory, injecting variables into
 * the process environment BEFORE engine initialization.  Follows Bun semantics:
 *   - Skips blank lines and `# comment` lines
 *   - Parses KEY=VALUE, KEY="VALUE", KEY='VALUE'
 *   - Strips surrounding quotes from values
 *   - Does NOT override already-set environment variables
 */
void loadDotEnv() @trusted
{
    import std.file : exists, readText;
    import std.process : environment;
    import std.string : strip, indexOf;

    enum DOT_ENV_FILENAME = ".env";
    enum COMMENT_CHAR = '#';
    enum MAX_LINE_LENGTH = 8192; // Defensive: skip unreasonably long lines

    if (!exists(DOT_ENV_FILENAME))
        return;

    string content;
    try
        content = readText(DOT_ENV_FILENAME);
    catch (Exception)
        return; // Silently skip unreadable .env files

    foreach (rawLine; content.lineSplitter())
    {
        auto line = strip(rawLine);

        // Skip empty lines and comments
        if (line.length == 0)
            continue;
        if (line[0] == COMMENT_CHAR)
            continue;

        // Defensive: skip absurdly long lines
        if (line.length > MAX_LINE_LENGTH)
            continue;

        // Find the first '=' separator
        auto eqPos = indexOf(line, '=');
        if (eqPos < 1) // No '=' found, or '=' at position 0
            continue;

        auto key = strip(line[0 .. eqPos]);
        if (key.length == 0)
            continue;

        auto value = strip(line[eqPos + 1 .. $]);

        // Strip surrounding quotes (single or double)
        if (value.length >= 2)
        {
            if ((value[0] == '"' && value[$ - 1] == '"') ||
                (value[0] == '\'' && value[$ - 1] == '\''))
            {
                value = value[1 .. $ - 1];
            }
        }

        // Do not override existing environment variables
        if (environment.get(key, null) !is null)
            continue;

        try
            environment[key] = value;
        catch (Exception)
            continue; // Skip vars that cannot be set
    }
}

void writeStderr(const(char)[] msg) @trusted
{
    import std.stdio : stderr;
    stderr.write(msg);
}
