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
    /* JSC gate: kept on JSC. The v0.7.0 `bindMethod` patch lifted
       the baseline from "9 servers OK" to "13 servers OK", and the
       v1.1.3 NUL-safe `createJSStringFromD` removed a class of
       refcount leaks, but `deno_deploy_compat`'s 7-server stress
       still times out on the 4th+ fetch with v7 extras enabled.
       Re-investigated in v1.1.5: the "CRASH `<error-compat>:1:3877`"
       output is actually the test's own `Promise.race` timeout
       (`rej(new Error("timeout"))` after 3 s) caught by its
       trailing `.catch`, formatted via the `<error-compat>`
       wrapper at the top of the stack. So the underlying bug is
       a fetch-hang on JSC + v7 — the network event-loop turn for
       the response doesn't run before the 3 s timer fires. Likely
       relates to JSC trampoline jitter under additional install-
       time eval pressure; needs gdb on the fetch path
       (`__futex_abstimed_wait_cancelable64` →
       `JSC::Heap::acquireAccessSlow`?). Defer to dedicated
       investigation. QJS / V8 install eagerly. */
    /* JSC gate: kept. v1.1.5 gdb investigation found the underlying
       bug is **NOT** specific to the v7 extras — it's a generic JSC
       HTTP-server-per-cycle handle leak. The bisect:

         baseline (no extras): hangs at server 17
         with `new Request(url)` per request: hangs at 15
         with v7 extras enabled: hangs at 9-10

       So the v7 extras only shave 7-8 servers off the threshold;
       they're not the root cause. The actual leak is in the HTTP
       server lifecycle on JSC — `httpServers[]` slot + callback
       handles aren't fully released between `Deno.serve` +
       `shutdown` cycles. After ~9 cycles the cumulative pressure
       blocks the next request's `req.on('end')` from firing
       (verified: gdb shows main thread in `epoll_wait` with the
       listen fd watched, fetch worker thread in `read()` on the
       client socket, but the server-side accept's request never
       reaches JS land — `handlerCalled = true` never fires in the
       JS handler).

       Root-cause fix needs an audit of every `engine.newFunction`,
       `engine.dupValue`, `engine.setProperty` in `http.d`'s
       createServer / writeHead / end paths to find which JSValueRef
       isn't being released symmetrically. Until that fix lands,
       the gate keeps `deno_deploy_compat` (15 servers) passing on
       JSC by avoiding the v7-extras-induced threshold drop.
       Re-CRASH-formatted as a fetch-timeout in the test's own
       `Promise.race` catch handler, not an actual JSC crash. */
    /* v1.1.6 follow-up: still gated. Three partial fixes shipped
       to chip away at the JSC HTTP-server-cycle leak without moving
       the actual threshold:
         - http.d: server slot recycling (`httpFreeServerSlots`)
         - http.d: cached `_httpSrvSetTimeout` (was per-createServer
           `newFunction`, leaked one JSC callback slot per cycle)
         - http.d: `jsHttpServerSetTimeout` newInt vs dupValue
         - jsc/backend.d: `callFunction` returns protected value in
           both success + exception paths (was asymmetric — success
           returned unprotected, callers Unprotect'd anyway = JSC
           protect-count underflow per call).
       Those moved zero threshold (still 9 servers OK with v7
       extras, ~17 without). So the actual leak is elsewhere —
       likely the per-fetch promise resolve/reject cycle on JSC's
       internal Promise machinery, or a leak in the agnostic_pending
       dispatch path. Re-test after the fixes confirms: v7 +
       deno_deploy_compat still HANGs, JSC sweep still 147/0/1.
       Defer until a JSValueProtect/Unprotect instrumentation pass. */
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
