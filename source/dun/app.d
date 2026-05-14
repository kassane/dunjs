module dun.app;

// D runtime GC defaults: larger pool reduces collection frequency (~11x fewer GC cycles)
// Override at runtime via: dun "--DRT-gcopt=minPoolSize:32 profile:1" run script.js
extern(C) __gshared string[] rt_options = ["gcopt=minPoolSize:16"];

version (unittest) {} else
int main(string[] args)
{
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
        case Command.version_:
            printVersion();
            return 0;
        case Command.help:
            printUsage();
            return 0;
    }
}

private:

enum VERSION = "0.2.0";

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

    if (isTypeScript(config.scriptPath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
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
    engine.shutdown();
    return exitCode;
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
    auto result = engine.eval(config.evalSource, "<eval>");
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
        ~ "  --max-memory=<bytes>   JS heap memory limit (default: 256MB)\n"
        ~ "  --max-stack=<bytes>    Max stack size (default: 8MB)\n"
        ~ "  --eval-file=<path>     Execute file before entering REPL\n\n"
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

    if (isTypeScript(filePath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
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

    if (isTypeScript(filePath))
    {
        import dun.ts.strip : stripTypes;
        source = stripTypes(source);
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
        ~ "  \"version\": \"0.2.0\",\n"
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
    foreach (file; files)
    {
        try
        {
            import std.file : readText, write;
            auto content = readText(file);
            auto result = basicFormat(content);
            if (result != content)
            {
                write(file, result);
                writeln("formatted: ", file);
                formatted++;
            }
        }
        catch (Exception e)
        {
            writeStderr("Error formatting " ~ file ~ ": " ~ e.msg ~ "\n");
        }
    }
    writeln(formatted, " file", formatted != 1 ? "s" : "", " formatted");
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

string basicFormat(string source) @safe pure
{
    // Normalize trailing whitespace and ensure final newline
    import std.string : stripRight;
    import std.array : appender;

    auto result = appender!string;
    bool lastWasEmpty = false;

    foreach (line; source.lineSplitter())
    {
        auto stripped = stripRight(line);
        if (stripped.length == 0)
        {
            if (!lastWasEmpty)
            {
                result.put("\n");
                lastWasEmpty = true;
            }
            continue;
        }
        lastWasEmpty = false;
        result.put(stripped);
        result.put("\n");
    }

    auto s = result.data;
    // Ensure exactly one trailing newline
    while (s.length > 1 && s[$ - 1] == '\n' && s[$ - 2] == '\n')
        s = s[0 .. $ - 1];
    if (s.length > 0 && s[$ - 1] != '\n')
        s ~= "\n";
    return s;
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

bool looksLikeFilePath(string arg) @safe pure nothrow @nogc
{
    foreach (c; arg)
        if (c == '.' || c == '/' || c == '\\')
            return true;
    return false;
}

void writeStderr(const(char)[] msg) @trusted
{
    import std.stdio : stderr;
    stderr.write(msg);
}
