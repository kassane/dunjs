module dun.cli.repl;

import dun.engine.iface : IJSEngine, EngineConfig;
import dun.runtime.globals : DunState, installGlobals;
import dun.cli.errors : isColorEnabled, formatUncaughtError;

// Bootstrap JS injected once at REPL startup for value inspection.
private enum INSPECTOR_INIT = `
globalThis.__dun_repl_inspect__ = function(v) {
    if (v === undefined) return undefined;
    if (v === null) return 'null';
    if (typeof v === 'string') return JSON.stringify(v);
    if (typeof v === 'function')
        return '[Function: ' + (v.name || '(anonymous)') + ']';
    if (typeof v === 'symbol') return v.toString();
    if (typeof v === 'bigint') return String(v) + 'n';
    if (typeof v === 'object') {
        try { return JSON.stringify(v, null, 2); } catch(e) { return '[Object]'; }
    }
    return String(v);
};
`;

int runReplImpl(T)(T config)
{
    import std.stdio : write, writeln, readln, stdout, stderr;
    import dun.engine.iface : createEngine;

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    // Install the REPL value inspector on globalThis.
    auto initResult = engine.eval(INSPECTOR_INIT, "<repl:init>");
    if (!initResult.isError) engine.freeValue(initResult.value);

    bool color = isColorEnabled();
    string accumulator;

    writeln("dun 0.1.0-dev  (type .help for commands, .exit or Ctrl-D to quit)");

    while (true)
    {
        write(accumulator.length == 0
            ? (color ? "\x1b[32m> \x1b[0m" : "> ")
            : (color ? "\x1b[90m... \x1b[0m" : "... "));
        try { stdout.flush(); } catch (Exception) {}

        string line = readln();
        if (line is null) { writeln(); break; }   // EOF / Ctrl-D

        while (line.length > 0 && (line[$-1] == '\n' || line[$-1] == '\r'))
            line = line[0 .. $-1];

        if (accumulator.length == 0)
        {
            import std.string : strip;
            auto cmd = line.strip();
            if (cmd == ".exit" || cmd == ".quit") break;
            if (cmd == ".help")
            {
                writeln("  .exit    Exit the REPL (also .quit)");
                writeln("  .help    Show this help");
                writeln("  _        Last evaluated value");
                continue;
            }
            if (cmd.length == 0) continue;
        }

        accumulator ~= (accumulator.length > 0 ? "\n" : "") ~ line;

        if (!isComplete(accumulator)) continue;

        string code = accumulator;
        accumulator = "";

        auto result = engine.eval(code, "<repl>");
        state.eventLoop.drainMicrotasks();

        if (result.isError)
        {
            try
            {
                stderr.write(formatUncaughtError(result.errorMessage, color));
                stderr.flush();
            }
            catch (Exception) {}
        }
        else
        {
            if (!engine.isUndefined(result.value))
            {
                engine.setProperty(engine.getGlobal(), "_",         engine.dupValue(result.value));
                engine.setProperty(engine.getGlobal(), "__dun_v__", engine.dupValue(result.value));
                auto inspR = engine.eval("__dun_repl_inspect__(__dun_v__)", "<repl:inspect>");
                if (!inspR.isError && !engine.isUndefined(inspR.value))
                {
                    auto s = engine.extractString(inspR.value);
                    writeln(color ? "\x1b[36m" ~ s ~ "\x1b[0m" : s);
                    engine.freeValue(inspR.value);
                }
            }
            engine.freeValue(result.value);
        }

        state.eventLoop.flushUnhandledRejections();
    }

    return 0;
}

// Returns false when brackets/parens/braces are still open — triggers "..." prompt.
private bool isComplete(string code) @safe pure nothrow
{
    int braces, brackets, parens;
    bool inSQ, inDQ, inTpl, escape;

    foreach (char c; code)
    {
        if (escape) { escape = false; continue; }
        if (c == '\\') { escape = true; continue; }

        if (!inSQ && !inDQ && !inTpl)
        {
            switch (c)
            {
                case '\'': inSQ = true;   break;
                case '"':  inDQ = true;   break;
                case '`':  inTpl = true;  break;
                case '{':  braces++;      break;
                case '}':  braces--;      break;
                case '[':  brackets++;    break;
                case ']':  brackets--;    break;
                case '(':  parens++;      break;
                case ')':  parens--;      break;
                default: break;
            }
        }
        else if (inSQ && c == '\'') inSQ = false;
        else if (inDQ && c == '"')  inDQ = false;
        else if (inTpl && c == '`') inTpl = false;
    }

    return braces <= 0 && brackets <= 0 && parens <= 0;
}

unittest
{
    assert(isComplete("1 + 2"));
    assert(isComplete("let x = { a: 1 }"));
    assert(!isComplete("let x = {"));
    assert(!isComplete("foo("));
    assert(isComplete("'hello'"));
}
