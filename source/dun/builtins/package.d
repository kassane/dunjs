/// Layer 4: Built-in modules.
///
/// Native implementations of dun:fs, dun:path, dun:net, dun:http,
/// dun:crypto, dun:os, dun:url. Each module is registered via
/// JS_NewCModule and exposes extern(C) callbacks with permission checks.
module dun.builtins;

version (EngineQuickJS)
{
    public import dun.builtins.fs;
    public import dun.builtins.path;
    public import dun.builtins.crypto;
}
