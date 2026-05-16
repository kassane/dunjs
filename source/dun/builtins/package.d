/// Layer 4 built-ins. Engine-agnostic implementations of the `dun:*`
/// modules (fs, path, net, http, crypto, etc.), all registered through
/// the IJSEngine interface.
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
public import dun.builtins.sqlite;
public import dun.builtins.util;
public import dun.builtins.assert_;
public import dun.builtins.querystring;
public import dun.builtins.string_decoder;
public import dun.builtins.timers_promises;
public import dun.builtins.http3;
public import dun.builtins.vm;
public import dun.builtins.cluster;
public import dun.builtins.async_hooks;
public import dun.builtins.worker_threads;
public import dun.builtins.dgram;
public import dun.builtins.perf_hooks;
public import dun.builtins.wasi;
