/// Layer 4: Built-in modules.
///
/// Native implementations of dun:fs, dun:path, dun:net, dun:http,
/// dun:crypto, dun:os, dun:url, dun:events, dun:buffer.
/// Registered via IJSEngine interface (engine-agnostic).
module dun.builtins;

public import dun.builtins.fs;
public import dun.builtins.path;
public import dun.builtins.crypto;
public import dun.builtins.net;
public import dun.builtins.http;
public import dun.builtins.buffer;
public import dun.builtins.events;
public import dun.builtins.url;
public import dun.builtins.os;
