/// DunJS - A secure JavaScript runtime written in D.
///
/// Embeds QuickJS-NG via extern(C) FFI with an eventcore-based event loop
/// and a Deno-inspired default-deny permission system.
module dun;

public import dun.engine;
public import dun.loop;
public import dun.runtime;
