module dun.builtins.helpers;

import dun.engine.iface : IJSEngine;
import dun.platform.arena : Appender;

/++
 + Escape a D string for safe embedding inside a single-quoted JS
 + string literal. Handles `\`, the chosen quote, control chars
 + (`\n`, `\r`, `\t`, `\b`, `\f`, `\0`), and `<` (so the result
 + can also be embedded in HTML / inline scripts without surprises).
 +
 + Was duplicated across 5 sites pre-consolidation: `fs.d:escapeJs`,
 + `crypto.d:escapeJsStr`, `esm_shim.d:escapeJsString`,
 + `require.d:escapeForJs`, `web_apis.d:escapeJsLit`. Three were
 + using `~=` (slow + GC pressure). One canonical Appender-backed
 + implementation here; every caller delegates. (`async.d` no longer
 + needs an escaper — its drain loop uses a cached `(msg) => new
 + Error(msg)` factory and passes the message as a JS value.)
 +
 + `quote` defaults to `'`; pass `"` for double-quoted contexts.
 +/
string escapeJsString(string s, char quote = '\'') @safe pure
{
    Appender!string r;
    r.reserve(s.length + s.length / 8 + 2);
    foreach (c; s)
    {
        if (c == '\\') { r ~= `\\`; continue; }
        if (c == quote) { r ~= '\\'; r ~= c; continue; }
        switch (c)
        {
            case '\n': r ~= `\n`; break;
            case '\r': r ~= `\r`; break;
            case '\t': r ~= `\t`; break;
            case '\b': r ~= `\b`; break;
            case '\f': r ~= `\f`; break;
            case '\0': r ~= `\0`; break;
            case '<':  r ~= `<`; break;  // inline-script-safe
            default:   r ~= c; break;
        }
    }
    return r.data.idup;
}

unittest
{
    assert(escapeJsString("hello") == "hello");
    assert(escapeJsString("it's") == `it\'s`);
    assert(escapeJsString(`a\b`) == `a\\b`);
    assert(escapeJsString("line\n") == `line\n`);
    assert(escapeJsString("</script>") == `</script>`);
    assert(escapeJsString(`he said "hi"`, '"') == `he said \"hi\"`);
}

/++
 + Eval a JS module-init blob and log to stderr on failure. Replaces
 + the boilerplate that every `registerXxxModule` for a pure-JS builtin
 + (url, util, querystring, string_decoder, timers_promises, readline,
 + vm, assert, async_hooks, wasi, events ...) was duplicating verbatim
 + — `getGlobal` + `eval(src)` + `if (isError) stderr.writeln(...)` +
 + `freeValue(global)`. The getGlobal was unused; the eval is the only
 + observable effect, and the error path is identical across modules.
 +
 + `what` is the human-readable module name printed in the error
 + message (matches Node's `<module> init failed:` convention).
 +/
void installPureJsModule(IJSEngine engine, scope const(char)[] source,
    string filename, string what) @trusted
{
    assert(engine !is null, "Null engine in installPureJsModule");
    auto result = engine.eval(source, filename);
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln(what, " init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
}
