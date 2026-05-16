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
        case Command.version_:
            printVersion();
            return 0;
        case Command.help:
            printUsage();
            return 0;
    }
}

private:

enum VERSION = "0.3.0";

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

    // Strip TS for .ts/.mts/.cts/.tsx files AND for stdin (where we
    // have no extension to dispatch on). Stripper is a whitespace-
    // preserving no-op for plain JS, so the false-positive cost is zero.
    if (isTypeScript(config.scriptPath) || isStdinPath(config.scriptPath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
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
        ~ "  bundle <entry>   Bundle JS/TS modules (--outdir DIR)\n"
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
        ~ "  --watch / -w           Restart script on file changes\n\n"
        ~ "REPL environment variables:\n"
        ~ "  DUN_REPL_HISTORY       Path to history file (~/.dun_repl_history)\n"
        ~ "  DUN_REPL_HISTORY_SIZE  Max history entries (default: 1000)\n\n"
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

    // Inject test harness preamble
    string harness =
        `var __dunTests=[];var __dunTestFail=0;`
        ~ `Deno.test=function(a,b){`
        ~ `if(typeof a==="string")__dunTests.push({name:a,fn:b});`
        ~ `else __dunTests.push({name:a.name,fn:a.fn||b});};`
        ~ `globalThis.test=Deno.test;`
        ~ `globalThis.assertEquals=function(a,b){`
        ~ `if(a!==b)throw new Error("Expected "+JSON.stringify(b)+", got "+JSON.stringify(a));};`
        ~ `globalThis.assertThrows=function(fn){`
        ~ `var threw=false;try{fn();}catch(e){threw=true;}if(!threw)throw new Error("Expected function to throw");};`
        ~ `globalThis.assertNotEquals=function(a,b){`
        ~ `if(a===b)throw new Error("Expected values to differ, got "+JSON.stringify(a));};`;

    string postamble =
        `setTimeout(async function(){`
        ~ `var filter=typeof __dunTestFilter!=="undefined"?__dunTestFilter:"";`
        ~ `for(var i=0;i<__dunTests.length;i++){`
        ~ `var t=__dunTests[i];`
        ~ `if(filter&&t.name.indexOf(filter)===-1)continue;`
        ~ `try{var r=t.fn();if(r&&typeof r.then==="function")await r;`
        ~ `console.log("  ok:",t.name);`
        ~ `}catch(e){__dunTestFail++;console.log("  FAIL:",t.name);console.log("    Error:",e.message);}}`
        ~ `if(__dunTestFail>0)process.exitCode=1;},0);`;

    string filterDecl = "";
    if (config.testFilter.length > 0)
    {
        import std.array : replace;
        filterDecl = `var __dunTestFilter="` ~ config.testFilter.replace(`"`, `\"`) ~ `";`;
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
    auto initRes = engine.eval(harness ~ filterDecl, "<test-harness>");
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
        ~ "  \"version\": \"0.3.0\",\n"
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
    string src =
        "Bun.build({ entrypoints: " ~ entriesJs ~
        ", outdir: \"" ~ outDir.replace(`\`, `\\`).replace(`"`, `\"`) ~ "\"" ~
        " }).then(function(r) {" ~
        "  if (!r.success) { console.error('bundle failed'); process.exit(1); }" ~
        "  console.log('bundle ok →', r.outputs[0].path, '(' + r.outputs[0].size + ' bytes)');" ~
        "}).catch(function(e) { console.error(String(e)); process.exit(1); });";

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
    import std.array : appender;
    auto buf = appender!string;
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
    import std.array : appender;

    auto result = appender!string;
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
    import std.array : appender;
    if (line.length == 0) return line;

    auto buf = appender!string;
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
