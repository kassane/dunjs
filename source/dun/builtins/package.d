/// Layer 4: Built-in modules.
///
/// Native implementations of dun:fs, dun:path, dun:net, dun:http,
/// dun:crypto, dun:os, dun:url. Registered via IJSEngine interface.
module dun.builtins;

public import dun.builtins.fs;
public import dun.builtins.path;
public import dun.builtins.crypto;

version (EngineQuickJS)
{
    public import dun.builtins.net;
    public import dun.builtins.http;
}
