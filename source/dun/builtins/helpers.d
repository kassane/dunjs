module dun.builtins.helpers;

import dun.engine.iface : IJSEngine;

/// Eval a JS module-init blob and log to stderr on failure. Replaces
/// the boilerplate that every `registerXxxModule` for a pure-JS builtin
/// (url, util, querystring, string_decoder, timers_promises, readline,
/// vm, assert, async_hooks, wasi, events ...) was duplicating verbatim
/// — `getGlobal` + `eval(src)` + `if (isError) stderr.writeln(...)` +
/// `freeValue(global)`. The getGlobal was unused; the eval is the only
/// observable effect, and the error path is identical across modules.
///
/// `what` is the human-readable module name printed in the error
/// message (matches Node's `<module> init failed:` convention).
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
