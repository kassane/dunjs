/// Layer 4: Built-in modules.
///
/// Native implementations of dun:fs, dun:path, dun:net, dun:http,
/// dun:crypto, dun:os, dun:url, dun:events, dun:buffer, dun:zlib, dun:dns, fetch.
/// Registered via IJSEngine interface (engine-agnostic).
module dun.builtins;

public import dun.builtins.fs;
public import dun.builtins.path;
public import dun.builtins.crypto;
public import dun.builtins.net;
public import dun.builtins.http;
public import dun.builtins.http2;
public import dun.builtins.buffer;
public import dun.builtins.events;
public import dun.builtins.url;
public import dun.builtins.os;
public import dun.builtins.zlib;
public import dun.builtins.dns;
public import dun.builtins.fetch;
public import dun.builtins.child_process;
public import dun.builtins.stream;
public import dun.builtins.ws;
