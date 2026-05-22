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
    /* JSC gate (kept as of v1.1.26): v1.1.26 cached
       `_writeHeadFlattener` and replaced three more per-call
       `engine.eval("[]")` sites with `engine.newArray()`, plus
       added an isException fallback in `makeResponse`. The
       resulting heap-pressure reduction made `deno_deploy_compat`
       pass standalone ~80% (up from ~40%), but the v7 extras'
       install-time JS bytecode still tips the 15-server cycle
       enough to push the JSC sweep flake rate back up. v7
       extras stay gated on JSC until the residual leak is
       found — likely in the response.body streaming reader or
       the req.on('data'/'end') listener chain. See CHANGELOG
       #43a for the gdb investigation notes. */
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
    /* Lazy install: each Bun.* extra is a getter that on first access
       new-Function's its body source, calls it, replaces the getter
       with the resulting function (so subsequent accesses are direct
       reads), and returns the function. Apps that don't touch any of
       these (deno_deploy_compat, most HTTP servers) pay only the
       getter-install cost (~10 properties × ~50B JS bytecode each).
       Same lazy-load pattern as diagnostics_channel (v1.1.10). */
    return
    "(function(){" ~
    "if (typeof Bun === 'undefined') return;" ~
    "var _src = {" ~

    "deepMatch:" ~
    "'return function(a, b) {" ~
    "  if (a === b) return true;" ~
    "  if (typeof a !== typeof b || a === null || b === null) return a === b;" ~
    "  if (Array.isArray(b)) {" ~
    "    if (!Array.isArray(a)) return false;" ~
    "    for (var i = 0; i < b.length; i++) if (!Bun.deepMatch(a[i], b[i])) return false;" ~
    "    return true;" ~
    "  }" ~
    "  if (typeof b !== \"object\") return a === b;" ~
    "  var kb = Object.keys(b);" ~
    "  for (var j = 0; j < kb.length; j++) if (!Bun.deepMatch(a[kb[j]], b[kb[j]])) return false;" ~
    "  return true;" ~
    "};'," ~

    "concatArrayBuffers:" ~
    "'return function(parts, max, asU8) {" ~
    "  var total = 0;" ~
    "  for (var i = 0; i < parts.length; i++) total += parts[i] && (parts[i].byteLength|0);" ~
    "  if (typeof max === \"number\" && total > max) total = max;" ~
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
    "};'," ~

    "arrayBufferToString:" ~
    "'return function(buf, enc) {" ~
    "  if (typeof buf === \"string\") return buf;" ~
    "  var u = buf instanceof Uint8Array ? buf : new Uint8Array(buf.buffer || buf);" ~
    "  return new TextDecoder(enc || \"utf-8\").decode(u);" ~
    "};'," ~

    "randomUUIDv7:" ~
    "'return function(enc, ts) {" ~
    "  if (typeof ts !== \"number\") ts = Date.now();" ~
    "  var bytes = new Uint8Array(16);" ~
    "  crypto.getRandomValues(bytes);" ~
    "  var hi = Math.floor(ts / 0x100000000);" ~
    "  var lo = ts >>> 0;" ~
    "  bytes[0] = (hi >>> 8) & 0xff; bytes[1] = hi & 0xff;" ~
    "  bytes[2] = (lo >>> 24) & 0xff; bytes[3] = (lo >>> 16) & 0xff;" ~
    "  bytes[4] = (lo >>> 8) & 0xff; bytes[5] = lo & 0xff;" ~
    "  bytes[6] = (bytes[6] & 0x0f) | 0x70;" ~
    "  bytes[8] = (bytes[8] & 0x3f) | 0x80;" ~
    "  if (enc === \"hex\") {" ~
    "    var hx = \"\";" ~
    "    for (var i = 0; i < 16; i++) hx += bytes[i].toString(16).padStart(2, \"0\");" ~
    "    return hx;" ~
    "  }" ~
    "  if (enc === \"buffer\") return Buffer.from(bytes);" ~
    "  var h = \"\";" ~
    "  for (var k = 0; k < 16; k++) h += bytes[k].toString(16).padStart(2, \"0\");" ~
    "  return h.slice(0, 8) + \"-\" + h.slice(8, 12) + \"-\" + h.slice(12, 16)" ~
    "       + \"-\" + h.slice(16, 20) + \"-\" + h.slice(20, 32);" ~
    "};'," ~

    "nanoseconds:" ~
    "'return function() { return Math.round(performance.now() * 1e6); };'," ~

    "gcAggressionLevel:" ~
    "'var _gcLevel = 1;" ~
    "return function(lvl) {" ~
    "  if (typeof lvl === \"number\" && lvl >= 0 && lvl <= 2) _gcLevel = lvl|0;" ~
    "  return _gcLevel;" ~
    "};'," ~

    "shrink:" ~
    "'return function() {" ~
    "  if (typeof globalThis.gc === \"function\") { try { globalThis.gc(); } catch (_) {} }" ~
    "};'," ~

    "generateHeapSnapshot:" ~
    "'return function(fmt) {" ~
    "  return { version: 1, format: fmt || \"jsc\", nodes: [], edges: [], note: \"heap snapshot stub\" };" ~
    "};'" ~

    "};" ~

    /* Install each as a self-promoting getter: first access triggers
       eval, replaces the property with the real function, returns it. */
    "Object.keys(_src).forEach(function(k) {" ~
    "  Object.defineProperty(Bun, k, {" ~
    "    configurable: true," ~
    "    get: function() {" ~
    "      var fn = (new Function(_src[k]))();" ~
    "      Object.defineProperty(Bun, k, { configurable: true, writable: true, enumerable: true, value: fn });" ~
    "      return fn;" ~
    "    }" ~
    "  });" ~
    "});" ~
    "})();";
}
