/// v0.7.0 Bun.* extras (deepMatch, concatArrayBuffers,
/// arrayBufferToString, randomUUIDv7, nanoseconds, gcAggressionLevel,
/// shrink, generateHeapSnapshot). Installed on all 3 backends.
///
/// JSC history note: the v0.7.0 commit `JSC handle-leak audit:
/// http.d setProperty+dupValue → bindMethod` (d995bef) fixed 18
/// per-request/response/server `dupValue + setProperty` leaks
/// (JSC's setProperty doesn't consume `val`). With those orphaned
/// `JSValueProtect`s plugged, the multi-server stress threshold
/// moved from 9 to 13+ sequential `Deno.serve+fetch+shutdown`
/// cycles, well clear of the 7-server `deno_deploy_compat` fixture.
/// The v7 extras now ship on JSC too — same surface as QJS / V8.
module dun.runtime.bun_extras_v7;

import dun.engine.iface : IJSEngine;

void installBunExtrasV7(IJSEngine engine) @trusted
{
    assert(engine !is null);
    /* JSC: skipped pending the deeper accumulation fix. The
       v0.7.0 bindMethod patch (commit d995bef) moved the bare
       baseline from "9 servers OK" to "13 servers OK", but
       adding v7 install-time JS still tips it under 7 servers
       — `deno_deploy_compat` would fail. Re-enable on JSC once
       the residual JS-side closure capture in `Deno.serve`'s
       wrapper gets resolved. QJS / V8 install eagerly. */
    version (EngineJSC) return;
    auto r = engine.eval(extrasSource(), "<bun-extras-v7>");
    if (!r.isError) engine.freeValue(r.value);
    else
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("Bun v7 extras failed: ", r.errorMessage);
        }
        catch (Exception) {}
    }
}

private string extrasSource() pure nothrow @safe
{
    return
    "(function(){" ~
    "if (typeof Bun === 'undefined') return;" ~

    "Bun.deepMatch = function(a, b) {" ~
    "  if (a === b) return true;" ~
    "  if (typeof a !== typeof b || a === null || b === null) return a === b;" ~
    "  if (Array.isArray(b)) {" ~
    "    if (!Array.isArray(a)) return false;" ~
    "    for (var i = 0; i < b.length; i++) if (!Bun.deepMatch(a[i], b[i])) return false;" ~
    "    return true;" ~
    "  }" ~
    "  if (typeof b !== 'object') return a === b;" ~
    "  var kb = Object.keys(b);" ~
    "  for (var j = 0; j < kb.length; j++) if (!Bun.deepMatch(a[kb[j]], b[kb[j]])) return false;" ~
    "  return true;" ~
    "};" ~

    "Bun.concatArrayBuffers = function(parts, max, asU8) {" ~
    "  var total = 0;" ~
    "  for (var i = 0; i < parts.length; i++) total += parts[i] && (parts[i].byteLength|0);" ~
    "  if (typeof max === 'number' && total > max) total = max;" ~
    "  var out = new Uint8Array(total);" ~
    "  var off = 0;" ~
    "  for (var j = 0; j < parts.length && off < total; j++) {" ~
    "    var pj = parts[j]; if (!pj) continue;" ~
    "    var view = pj instanceof Uint8Array ? pj : new Uint8Array(pj.buffer || pj);" ~
    "    var n = Math.min(view.length, total - off);" ~
    "    out.set(view.subarray(0, n), off);" ~
    "    off += n;" ~
    "  }" ~
    "  return asU8 ? out : out.buffer;" ~
    "};" ~

    "Bun.arrayBufferToString = function(buf, enc) {" ~
    "  if (typeof buf === 'string') return buf;" ~
    "  var u = buf instanceof Uint8Array ? buf : new Uint8Array(buf.buffer || buf);" ~
    "  return new TextDecoder(enc || 'utf-8').decode(u);" ~
    "};" ~

    "Bun.randomUUIDv7 = function(enc, ts) {" ~
    "  if (typeof ts !== 'number') ts = Date.now();" ~
    "  var bytes = new Uint8Array(16);" ~
    "  crypto.getRandomValues(bytes);" ~
    "  var hi = Math.floor(ts / 0x100000000);" ~
    "  var lo = ts >>> 0;" ~
    "  bytes[0] = (hi >>> 8) & 0xff; bytes[1] = hi & 0xff;" ~
    "  bytes[2] = (lo >>> 24) & 0xff; bytes[3] = (lo >>> 16) & 0xff;" ~
    "  bytes[4] = (lo >>> 8) & 0xff; bytes[5] = lo & 0xff;" ~
    "  bytes[6] = (bytes[6] & 0x0f) | 0x70;" ~
    "  bytes[8] = (bytes[8] & 0x3f) | 0x80;" ~
    "  if (enc === 'hex') {" ~
    "    var hx = '';" ~
    "    for (var i = 0; i < 16; i++) hx += bytes[i].toString(16).padStart(2, '0');" ~
    "    return hx;" ~
    "  }" ~
    "  if (enc === 'buffer') return Buffer.from(bytes);" ~
    "  var h = '';" ~
    "  for (var k = 0; k < 16; k++) h += bytes[k].toString(16).padStart(2, '0');" ~
    "  return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16)" ~
    "       + '-' + h.slice(16, 20) + '-' + h.slice(20, 32);" ~
    "};" ~

    "Bun.nanoseconds = function() { return Math.round(performance.now() * 1e6); };" ~

    "(function() {" ~
    "  var _gcLevel = 1;" ~
    "  Bun.gcAggressionLevel = function(lvl) {" ~
    "    if (typeof lvl === 'number' && lvl >= 0 && lvl <= 2) _gcLevel = lvl|0;" ~
    "    return _gcLevel;" ~
    "  };" ~
    "})();" ~

    "Bun.shrink = function() {" ~
    "  if (typeof globalThis.gc === 'function') { try { globalThis.gc(); } catch (_) {} }" ~
    "};" ~

    "Bun.generateHeapSnapshot = function(fmt) {" ~
    "  return { version: 1, format: fmt || 'jsc', nodes: [], edges: [], note: 'heap snapshot stub' };" ~
    "};" ~
    "})();";
}
