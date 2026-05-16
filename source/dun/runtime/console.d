module dun.runtime.console;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void installConsole(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine");

    auto initResult = engine.eval(inspectSource(), "<console:inspect>");
    if (initResult.isError)
        engine.freeValue(initResult.value);

    auto console = engine.newObject();
    auto global = engine.getGlobal();

    engine.setProperty(console, "log", engine.newFunction(&consoleLog, "log", 1));
    engine.setProperty(console, "info", engine.newFunction(&consoleLog, "info", 1));
    engine.setProperty(console, "debug", engine.newFunction(&consoleLog, "debug", 1));
    engine.setProperty(console, "warn", engine.newFunction(&consoleWarn, "warn", 1));
    engine.setProperty(console, "error", engine.newFunction(&consoleError, "error", 1));
    engine.setProperty(console, "assert", engine.newFunction(&consoleAssert, "assert", 2));

    engine.setProperty(global, "console", console);
    engine.freeValue(global);
}

private:

JSHandle consoleLog(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.log");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in console.log");
    writeArgs(state.engine, args, false);
    forwardToInspector(state.engine, "log", args);
    return state.engine.newUndefined();
}

JSHandle consoleWarn(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.warn");
    auto state = cast(DunState*) ctx;
    writeArgs(state.engine, args, true);
    forwardToInspector(state.engine, "warning", args);
    return state.engine.newUndefined();
}

JSHandle consoleError(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.error");
    auto state = cast(DunState*) ctx;
    writeArgs(state.engine, args, true);
    forwardToInspector(state.engine, "error", args);
    return state.engine.newUndefined();
}

/// Forward a console.* call to an attached Chrome DevTools session as
/// a Runtime.consoleAPICalled event. No-op if `--inspect` wasn't set
/// or no client has connected.
version (Posix) import dun.cli.inspector : emitConsoleAPICalled;

private void forwardToInspector(IJSEngine engine, string level, scope JSHandle[] args) @trusted nothrow
{
    version (Posix)
    {
        try
        {
            // Format args the same way writeArgs would render them, so
            // DevTools sees the same string the terminal did.
            string formatted;
            foreach (i, arg; args)
            {
                if (i > 0) formatted ~= " ";
                try { formatted ~= engine.extractString(arg); }
                catch (Exception) {}
            }
            emitConsoleAPICalled(level, formatted);
        }
        catch (Throwable) {}
    }
}

JSHandle consoleAssert(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in console.assert");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length > 0 && engine.extractBool(args[0]))
        return engine.newUndefined();

    try
    {
        import std.stdio : stderr;
        stderr.write("Assertion failed: ");
        if (args.length > 1)
            writeArgs(engine, args[1 .. $], true);
        else
        {
            stderr.writeln("console.assert");
            stderr.flush();
        }
    }
    catch (Exception) {}
    return engine.newUndefined();
}

void writeArgs(IJSEngine engine, scope JSHandle[] args, bool useStderr) @trusted
{
    try
    {
        import std.stdio : stdout, stderr;
        auto output = useStderr ? stderr : stdout;

        auto global = engine.getGlobal();
        auto fmtFn = engine.getProperty(global, "__dun_format_console__");
        engine.freeValue(global);

        if (engine.isFunction(fmtFn))
        {
            auto argsArr = engine.newArray();
            foreach (i, arg; args)
                engine.setPropertyIndex(argsArr, cast(uint) i, engine.dupValue(arg));

            auto result = engine.callFunction(fmtFn, engine.newUndefined(), [argsArr]);
            output.writeln(engine.extractString(result));
            engine.freeValue(result);
            engine.freeValue(argsArr);
            engine.freeValue(fmtFn);
        }
        else
        {
            engine.freeValue(fmtFn);
            foreach (i, arg; args)
            {
                if (i > 0)
                    output.write(' ');
                output.write(engine.extractString(arg));
            }
            output.writeln();
        }
        output.flush();
    }
    catch (Exception) {}
}

private string inspectSource() @safe pure nothrow
{
    enum src =
    "globalThis.__dun_inspect__ = (function() {"
    ~ "var seen = [];"
    ~ "function inspect(v, depth) {"
    ~   "if (depth === undefined) depth = 2;"
    ~   "if (v === null) return 'null';"
    ~   "if (v === undefined) return 'undefined';"
    ~   "var t = typeof v;"
    ~   "if (t === 'string') return \"'\" + v.replace(/\\\\/g,'\\\\\\\\').replace(/'/g,\"\\\\'\") + \"'\";"
    ~   "if (t === 'number') {"
    ~     "if (Object.is(v, -0)) return '-0';"
    ~     "return String(v);"
    ~   "}"
    ~   "if (t === 'boolean') return String(v);"
    ~   "if (t === 'symbol') return v.toString();"
    ~   "if (t === 'bigint') return v.toString() + 'n';"
    ~   "if (t === 'function') return '[Function: ' + (v.name || 'anonymous') + ']';"
    ~   "if (v instanceof Error) {"
    ~     "var msg = (v.name || 'Error') + ': ' + (v.message || '');"
    ~     "if (v.stack) {"
    ~       "if (v.stack.indexOf(msg) === 0) return v.stack;"
    ~       "return msg + '\\n' + v.stack;"
    ~     "}"
    ~     "return msg;"
    ~   "}"
    ~   "if (v instanceof Date) return v.toISOString();"
    ~   "if (v instanceof RegExp) return v.toString();"
    ~   "if (typeof Promise !== 'undefined' && v instanceof Promise) return 'Promise {}';"
    ~   "if (seen.indexOf(v) !== -1) return '[Circular]';"
    ~   "seen.push(v);"
    ~   "try {"
    ~     "if (v instanceof ArrayBuffer) {"
    ~       "return 'ArrayBuffer { byteLength: ' + v.byteLength + ' }';"
    ~     "}"
    ~     "var taTypes = ['Int8Array','Uint8Array','Uint8ClampedArray','Int16Array','Uint16Array','Int32Array','Uint32Array','Float32Array','Float64Array','BigInt64Array','BigUint64Array'];"
    ~     "for (var ti = 0; ti < taTypes.length; ti++) {"
    ~       "var C = globalThis[taTypes[ti]];"
    ~       "if (C && v instanceof C) {"
    ~         "if (v.length === 0) return taTypes[ti] + '(0) []';"
    ~         "var items = [];"
    ~         "for (var i = 0; i < v.length && i < 100; i++) items.push(String(v[i]));"
    ~         "if (v.length > 100) items.push('... ' + (v.length - 100) + ' more items');"
    ~         "return taTypes[ti] + '(' + v.length + ') [ ' + items.join(', ') + ' ]';"
    ~       "}"
    ~     "}"
    ~     "if (typeof Map !== 'undefined' && v instanceof Map) {"
    ~       "if (depth < 0) return '[Map]';"
    ~       "if (v.size === 0) return 'Map(0) {}';"
    ~       "var entries = [];"
    ~       "v.forEach(function(val, key) {"
    ~         "entries.push(inspect(key, depth - 1) + ' => ' + inspect(val, depth - 1));"
    ~       "});"
    ~       "return 'Map(' + v.size + ') { ' + entries.join(', ') + ' }';"
    ~     "}"
    ~     "if (typeof Set !== 'undefined' && v instanceof Set) {"
    ~       "if (depth < 0) return '[Set]';"
    ~       "if (v.size === 0) return 'Set(0) {}';"
    ~       "var items = [];"
    ~       "v.forEach(function(val) { items.push(inspect(val, depth - 1)); });"
    ~       "return 'Set(' + v.size + ') { ' + items.join(', ') + ' }';"
    ~     "}"
    ~     "if (typeof WeakMap !== 'undefined' && v instanceof WeakMap) return 'WeakMap { <items unknown> }';"
    ~     "if (typeof WeakSet !== 'undefined' && v instanceof WeakSet) return 'WeakSet { <items unknown> }';"
    ~     "if (typeof WeakRef !== 'undefined' && v instanceof WeakRef) return 'WeakRef {}';"
    ~     "if (Array.isArray(v)) {"
    ~       "if (depth < 0) return '[Array]';"
    ~       "if (v.length === 0) return '[]';"
    ~       "var items = [];"
    ~       "for (var i = 0; i < v.length && i < 100; i++) {"
    ~         "items.push(i in v ? inspect(v[i], depth - 1) : '<empty>');"
    ~       "}"
    ~       "if (v.length > 100) items.push('... ' + (v.length - 100) + ' more items');"
    ~       "return '[ ' + items.join(', ') + ' ]';"
    ~     "}"
    ~     "if (depth < 0) return '[Object]';"
    ~     "var keys = Object.keys(v);"
    ~     "if (keys.length === 0) return '{}';"
    ~     "var items = [];"
    ~     "for (var i = 0; i < keys.length && i < 50; i++) {"
    ~       "items.push(keys[i] + ': ' + inspect(v[keys[i]], depth - 1));"
    ~     "}"
    ~     "if (keys.length > 50) items.push('... ' + (keys.length - 50) + ' more');"
    ~     "return '{ ' + items.join(', ') + ' }';"
    ~   "} finally {"
    ~     "seen.pop();"
    ~   "}"
    ~ "}"
    ~ "return function(v, d) {"
    ~   "seen = [];"
    ~   "return inspect(v, d !== undefined ? d : 2);"
    ~ "};"
    ~ "})();"

    // __dun_format_console__: format string support (%s %d %i %f %o %O %j %%)
    ~ "globalThis.__dun_format_console__ = function(args) {"
    ~   "if (args.length === 0) return '';"
    ~   "var inspect = globalThis.__dun_inspect__;"
    ~   "if (args.length === 1) {"
    ~     "return typeof args[0] === 'string' ? args[0] : inspect(args[0]);"
    ~   "}"
    ~   "if (typeof args[0] !== 'string') {"
    ~     "var parts = [];"
    ~     "for (var i = 0; i < args.length; i++) {"
    ~       "parts.push(typeof args[i] === 'string' ? args[i] : inspect(args[i]));"
    ~     "}"
    ~     "return parts.join(' ');"
    ~   "}"
    ~   "var fmt = args[0], out = '', ai = 1;"
    ~   "for (var ci = 0; ci < fmt.length; ci++) {"
    ~     "if (fmt[ci] === '%' && ci + 1 < fmt.length) {"
    ~       "var ch = fmt[ci + 1];"
    ~       "if (ch === '%') { out += '%'; ci++; continue; }"
    ~       "if (ai < args.length) {"
    ~         "if (ch === 's') { out += String(args[ai++]); ci++; continue; }"
    ~         "if (ch === 'd' || ch === 'f') { out += Number(args[ai++]); ci++; continue; }"
    ~         "if (ch === 'i') { out += Math.trunc(Number(args[ai++])); ci++; continue; }"
    ~         "if (ch === 'o' || ch === 'O') { out += inspect(args[ai++]); ci++; continue; }"
    ~         "if (ch === 'j') {"
    ~           "try { out += JSON.stringify(args[ai++]); } catch(e) { out += '[Circular]'; ai++; }"
    ~           "ci++; continue;"
    ~         "}"
    ~         "if (ch === 'c') { ai++; ci++; continue; }"
    ~       "}"
    ~     "}"
    ~     "out += fmt[ci];"
    ~   "}"
    ~   "for (; ai < args.length; ai++) {"
    ~     "out += ' ' + (typeof args[ai] === 'string' ? args[ai] : inspect(args[ai]));"
    ~   "}"
    ~   "return out;"
    ~ "};";
    static assert(src.length > 0, "inspect source must not be empty");
    return src;
}
