/// `Bun.*` namespace shim — maps Bun-specific APIs onto our Node-style
/// implementations so apps written for Bun run unchanged.
module dun.runtime.bun_compat;

import dun.engine.iface : IJSEngine;

void installBunCompat(IJSEngine engine) @trusted
{
    assert(engine !is null);
    auto result = engine.eval(bunCompatSource(), "<bun-compat>");
    if (!result.isError) engine.freeValue(result.value);
    else
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("Bun compat init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
}

private string bunCompatSource() pure nothrow @safe
{
    // CAUTION: this string is built with `~` joins, no newlines between
    // chunks. Don't use JS `//` line comments — they swallow the rest.
    // Use `/* ... */` block comments only.
    return
    "(function() {" ~
    "if (typeof globalThis.Bun !== 'undefined') return;" ~
    "var Bun = {};" ~

    /* Constants — version/revision so feature-detect code passes. */
    "Bun.version = '1.3.0';" ~
    "Bun.revision = 'dunjs-compat';" ~

    /* Bun.env / Bun.argv mirror the runtime's process.*. */
    "Object.defineProperty(Bun, 'env', { get: function() { return process.env; } });" ~
    "Object.defineProperty(Bun, 'argv', { get: function() { return process.argv; } });" ~

    /* Bun.main — absolute path to the entry script (argv[1] when run via dun run). */
    "Object.defineProperty(Bun, 'main', { get: function() {" ~
    "  if (typeof process === 'undefined' || !process.argv) return '';" ~
    "  return process.argv[1] || '';" ~
    "} });" ~

    /* Bun.sleep — Promise<void> that resolves after `ms`. */
    "Bun.sleep = function(ms) {" ~
    "  return new Promise(function(r) { setTimeout(r, ms); });" ~
    "};" ~
    "Bun.sleepSync = function(ms) {" ~
    "  var d = Date.now() + ms;" ~
    "  while (Date.now() < d) {}" ~
    "};" ~

    /* Bun.escapeHTML — escapes &<>\"' for safe HTML embedding. */
    "Bun.escapeHTML = function(s) {" ~
    "  if (typeof s !== 'string') s = String(s);" ~
    "  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;')" ~
    "          .replace(/>/g, '&gt;').replace(/\"/g, '&quot;')" ~
    "          .replace(/'/g, '&#39;');" ~
    "};" ~

    /* Bun.deepEquals — structural equality. Bun's checks deep arrays,
       objects, Maps, Sets, typed arrays. We cover the common cases. */
    "Bun.deepEquals = function(a, b) {" ~
    "  if (a === b) return true;" ~
    "  if (typeof a !== typeof b) return false;" ~
    "  if (a === null || b === null) return a === b;" ~
    "  if (typeof a !== 'object') return false;" ~
    "  if (Array.isArray(a)) {" ~
    "    if (!Array.isArray(b) || a.length !== b.length) return false;" ~
    "    for (var i = 0; i < a.length; i++) if (!Bun.deepEquals(a[i], b[i])) return false;" ~
    "    return true;" ~
    "  }" ~
    "  if (Array.isArray(b)) return false;" ~
    "  var ka = Object.keys(a), kb = Object.keys(b);" ~
    "  if (ka.length !== kb.length) return false;" ~
    "  for (var j = 0; j < ka.length; j++) {" ~
    "    if (!b.hasOwnProperty(ka[j])) return false;" ~
    "    if (!Bun.deepEquals(a[ka[j]], b[ka[j]])) return false;" ~
    "  }" ~
    "  return true;" ~
    "};" ~

    /* Bun.inspect — delegates to util.inspect if available. */
    "Bun.inspect = function(v, opts) {" ~
    "  try {" ~
    "    var util = require('util');" ~
    "    return util.inspect(v, opts || { depth: 4 });" ~
    "  } catch (e) {" ~
    "    return String(v);" ~
    "  }" ~
    "};" ~

    /* Bun.hash — non-cryptographic 32-bit FNV-1a fold to JS number.
       Bun's real API also has .crc32 / .adler32 / .xxh32 / .xxh64
       sub-methods on the function object; the bodies below mirror the
       reference algorithms (the goal is API compatibility on hot
       hashing paths, not byte-exact Bun output). */
    "Bun.hash = function(input) {" ~
    "  if (typeof input === 'string') {" ~
    "    var h = 0x811c9dc5;" ~
    "    for (var i = 0; i < input.length; i++) {" ~
    "      h = (h ^ input.charCodeAt(i)) >>> 0;" ~
    "      h = Math.imul(h, 0x01000193) >>> 0;" ~
    "    }" ~
    "    return h;" ~
    "  }" ~
    "  if (input && input.byteLength !== undefined) {" ~
    "    var b = input instanceof Uint8Array ? input : new Uint8Array(input.buffer || input);" ~
    "    var hh = 0x811c9dc5;" ~
    "    for (var k = 0; k < b.length; k++) {" ~
    "      hh = (hh ^ b[k]) >>> 0;" ~
    "      hh = Math.imul(hh, 0x01000193) >>> 0;" ~
    "    }" ~
    "    return hh;" ~
    "  }" ~
    "  return Bun.hash(String(input));" ~
    "};" ~

    /* Normalize any input (string / Uint8Array / ArrayBuffer) to a
       Uint8Array view for the sub-hash impls. */
    "Bun.hash.__toBytes = function(input) {" ~
    "  if (typeof input === 'string') {" ~
    "    return new TextEncoder().encode(input);" ~
    "  }" ~
    "  if (input instanceof Uint8Array) return input;" ~
    "  if (input && input.buffer instanceof ArrayBuffer) return new Uint8Array(input.buffer, input.byteOffset || 0, input.byteLength);" ~
    "  if (input instanceof ArrayBuffer) return new Uint8Array(input);" ~
    "  return new TextEncoder().encode(String(input));" ~
    "};" ~

    /* CRC32 (IEEE polynomial 0xEDB88320). Single-byte table built once. */
    "(function(){" ~
    "  var t = new Uint32Array(256);" ~
    "  for (var n = 0; n < 256; n++) {" ~
    "    var c = n;" ~
    "    for (var k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);" ~
    "    t[n] = c;" ~
    "  }" ~
    "  Bun.hash.crc32 = function(input) {" ~
    "    var b = Bun.hash.__toBytes(input);" ~
    "    var crc = 0xFFFFFFFF;" ~
    "    for (var i = 0; i < b.length; i++) crc = (t[(crc ^ b[i]) & 0xFF] ^ (crc >>> 8)) >>> 0;" ~
    "    return (crc ^ 0xFFFFFFFF) >>> 0;" ~
    "  };" ~
    "})();" ~

    /* Adler-32. */
    "Bun.hash.adler32 = function(input) {" ~
    "  var b = Bun.hash.__toBytes(input);" ~
    "  var a = 1, c = 0;" ~
    "  for (var i = 0; i < b.length; i++) {" ~
    "    a = (a + b[i]) % 65521;" ~
    "    c = (c + a) % 65521;" ~
    "  }" ~
    "  return ((c << 16) | a) >>> 0;" ~
    "};" ~

    /* xxHash32 (reference). Optional seed (defaults to 0). */
    "Bun.hash.xxh32 = function(input, seed) {" ~
    "  var b = Bun.hash.__toBytes(input);" ~
    "  seed = (seed >>> 0) || 0;" ~
    "  var P1 = 0x9E3779B1, P2 = 0x85EBCA77, P3 = 0xC2B2AE3D, P4 = 0x27D4EB2F, P5 = 0x165667B1;" ~
    "  var len = b.length, i = 0, h32;" ~
    "  var rotl = function(x, r) { return ((x << r) | (x >>> (32 - r))) >>> 0; };" ~
    "  if (len >= 16) {" ~
    "    var v1 = (seed + P1 + P2) >>> 0;" ~
    "    var v2 = (seed + P2) >>> 0;" ~
    "    var v3 = (seed + 0) >>> 0;" ~
    "    var v4 = (seed - P1) >>> 0;" ~
    "    while (i <= len - 16) {" ~
    "      var k1 = (b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) >>> 0;" ~
    "      v1 = Math.imul(rotl((v1 + Math.imul(k1, P2)) >>> 0, 13), P1) >>> 0; i += 4;" ~
    "      var k2 = (b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) >>> 0;" ~
    "      v2 = Math.imul(rotl((v2 + Math.imul(k2, P2)) >>> 0, 13), P1) >>> 0; i += 4;" ~
    "      var k3 = (b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) >>> 0;" ~
    "      v3 = Math.imul(rotl((v3 + Math.imul(k3, P2)) >>> 0, 13), P1) >>> 0; i += 4;" ~
    "      var k4 = (b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) >>> 0;" ~
    "      v4 = Math.imul(rotl((v4 + Math.imul(k4, P2)) >>> 0, 13), P1) >>> 0; i += 4;" ~
    "    }" ~
    "    h32 = (rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18)) >>> 0;" ~
    "  } else {" ~
    "    h32 = (seed + P5) >>> 0;" ~
    "  }" ~
    "  h32 = (h32 + len) >>> 0;" ~
    "  while (i <= len - 4) {" ~
    "    var kk = (b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) >>> 0;" ~
    "    h32 = Math.imul(rotl((h32 + Math.imul(kk, P3)) >>> 0, 17), P4) >>> 0;" ~
    "    i += 4;" ~
    "  }" ~
    "  while (i < len) {" ~
    "    h32 = Math.imul(rotl((h32 + Math.imul(b[i], P5)) >>> 0, 11), P1) >>> 0;" ~
    "    i++;" ~
    "  }" ~
    "  h32 = Math.imul(h32 ^ (h32 >>> 15), P2) >>> 0;" ~
    "  h32 = Math.imul(h32 ^ (h32 >>> 13), P3) >>> 0;" ~
    "  return (h32 ^ (h32 >>> 16)) >>> 0;" ~
    "};" ~

    /* xxh64: returns a BigInt because the real value doesn't fit in a
       JS number. Same skeleton as xxh32 but the full 64-bit constants
       require BigInt math throughout. We use a streamlined variant
       (BigInt arithmetic is ~10x slower than 32-bit, but it's a
       compat shim, not a hot path). */
    "(function(){" ~
    "  var P1 = 11400714785074694791n;" ~
    "  var P2 = 14029467366897019727n;" ~
    "  var P3 = 1609587929392839161n;" ~
    "  var P4 = 9650029242287828579n;" ~
    "  var P5 = 2870177450012600261n;" ~
    "  var M = (1n << 64n) - 1n;" ~
    "  function rotl(x, r) { return (((x << r) | (x >> (64n - r))) & M); }" ~
    "  function read64(b, i) {" ~
    "    var lo = BigInt(b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24));" ~
    "    var hi = BigInt(b[i+4] | (b[i+5] << 8) | (b[i+6] << 16) | (b[i+7] << 24));" ~
    "    return (lo & 0xFFFFFFFFn) | ((hi & 0xFFFFFFFFn) << 32n);" ~
    "  }" ~
    "  function read32(b, i) {" ~
    "    return BigInt(b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24)) & 0xFFFFFFFFn;" ~
    "  }" ~
    "  Bun.hash.xxh64 = function(input, seed) {" ~
    "    var b = Bun.hash.__toBytes(input);" ~
    "    var s = BigInt(seed || 0) & M;" ~
    "    var len = b.length, i = 0, h;" ~
    "    if (len >= 32) {" ~
    "      var v1 = (s + P1 + P2) & M;" ~
    "      var v2 = (s + P2) & M;" ~
    "      var v3 = s;" ~
    "      var v4 = (s - P1) & M;" ~
    "      while (i + 32 <= len) {" ~
    "        v1 = (rotl((v1 + ((read64(b,i) * P2) & M)) & M, 31n) * P1) & M; i += 8;" ~
    "        v2 = (rotl((v2 + ((read64(b,i) * P2) & M)) & M, 31n) * P1) & M; i += 8;" ~
    "        v3 = (rotl((v3 + ((read64(b,i) * P2) & M)) & M, 31n) * P1) & M; i += 8;" ~
    "        v4 = (rotl((v4 + ((read64(b,i) * P2) & M)) & M, 31n) * P1) & M; i += 8;" ~
    "      }" ~
    "      h = (rotl(v1, 1n) + rotl(v2, 7n) + rotl(v3, 12n) + rotl(v4, 18n)) & M;" ~
    "      function merge(h, v) {" ~
    "        v = (rotl((v * P2) & M, 31n) * P1) & M;" ~
    "        h = ((h ^ v) * P1 + P4) & M;" ~
    "        return h;" ~
    "      }" ~
    "      h = merge(h, v1); h = merge(h, v2); h = merge(h, v3); h = merge(h, v4);" ~
    "    } else {" ~
    "      h = (s + P5) & M;" ~
    "    }" ~
    "    h = (h + BigInt(len)) & M;" ~
    "    while (i + 8 <= len) {" ~
    "      var k = (read64(b,i) * P2) & M;" ~
    "      k = (rotl(k, 31n) * P1) & M;" ~
    "      h = ((rotl(h ^ k, 27n) * P1 + P4)) & M;" ~
    "      i += 8;" ~
    "    }" ~
    "    if (i + 4 <= len) {" ~
    "      h = ((rotl((h ^ ((read32(b,i) * P1) & M)) & M, 23n) * P2 + P3)) & M;" ~
    "      i += 4;" ~
    "    }" ~
    "    while (i < len) {" ~
    "      h = ((rotl((h ^ ((BigInt(b[i]) * P5) & M)) & M, 11n) * P1)) & M;" ~
    "      i++;" ~
    "    }" ~
    "    h = (h ^ (h >> 33n)) & M;" ~
    "    h = ((h * P2) & M);" ~
    "    h = (h ^ (h >> 29n)) & M;" ~
    "    h = ((h * P3) & M);" ~
    "    h = (h ^ (h >> 32n)) & M;" ~
    "    return h;" ~
    "  };" ~
    "})();" ~

    /* Bun.file(path) returns a BunFile-like with text() / json() /
       arrayBuffer() / stream() / size / type / writer(). */
    "Bun.file = function(path) {" ~
    "  var fs = require('fs');" ~
    "  var pathMod = require('path');" ~
    "  var absPath = pathMod.resolve(path);" ~
    "  var lazyStat = null;" ~
    "  function statSync() { if (!lazyStat) lazyStat = fs.statSync(absPath); return lazyStat; }" ~
    "  function guessType(p) {" ~
    "    var ext = (p.split('.').pop() || '').toLowerCase();" ~
    "    var m = {" ~
    "      js:'text/javascript',mjs:'text/javascript',ts:'text/typescript'," ~
    "      json:'application/json',html:'text/html',htm:'text/html'," ~
    "      css:'text/css',txt:'text/plain',md:'text/markdown'," ~
    "      png:'image/png',jpg:'image/jpeg',jpeg:'image/jpeg'," ~
    "      gif:'image/gif',webp:'image/webp',svg:'image/svg+xml'," ~
    "      wasm:'application/wasm',pdf:'application/pdf'" ~
    "    };" ~
    "    return m[ext] || 'application/octet-stream';" ~
    "  }" ~
    "  return {" ~
    "    name: absPath," ~
    "    get size() { try { return statSync().size; } catch (e) { return 0; } }," ~
    "    get type() { return guessType(absPath); }," ~
    "    exists: function() {" ~
    "      try { fs.accessSync(absPath); return Promise.resolve(true); }" ~
    "      catch (e) { return Promise.resolve(false); }" ~
    "    }," ~
    "    text: function() {" ~
    "      return new Promise(function(res, rej) {" ~
    "        try { res(fs.readFileSync(absPath, 'utf8')); }" ~
    "        catch (e) { rej(e); }" ~
    "      });" ~
    "    }," ~
    "    json: function() {" ~
    "      return this.text().then(function(t) { return JSON.parse(t); });" ~
    "    }," ~
    "    arrayBuffer: function() {" ~
    "      return new Promise(function(res, rej) {" ~
    "        try {" ~
    "          var buf = fs.readFileSync(absPath);" ~
    "          var ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);" ~
    "          res(ab);" ~
    "        } catch (e) { rej(e); }" ~
    "      });" ~
    "    }," ~
    "    bytes: function() {" ~
    "      return new Promise(function(res, rej) {" ~
    "        try {" ~
    "          var buf = fs.readFileSync(absPath);" ~
    "          res(new Uint8Array(buf));" ~
    "        } catch (e) { rej(e); }" ~
    "      });" ~
    "    }," ~
    "    stream: function() {" ~
    "      if (typeof ReadableStream === 'undefined') throw new Error('ReadableStream unavailable');" ~
    "      var buf = fs.readFileSync(absPath);" ~
    "      return new ReadableStream({" ~
    "        start: function(controller) {" ~
    "          controller.enqueue(new Uint8Array(buf));" ~
    "          controller.close();" ~
    "        }" ~
    "      });" ~
    "    }," ~
    "    writer: function() {" ~
    "      var chunks = [];" ~
    "      return {" ~
    "        write: function(chunk) { chunks.push(chunk); return chunk.length || 0; }," ~
    "        end: function() {" ~
    "          var Buffer2 = globalThis.Buffer;" ~
    "          var bufs = chunks.map(function(c) {" ~
    "            return typeof c === 'string' ? Buffer2.from(c) : Buffer2.from(c);" ~
    "          });" ~
    "          fs.writeFileSync(absPath, Buffer2.concat(bufs));" ~
    "        }," ~
    "        flush: function() {}" ~
    "      };" ~
    "    }" ~
    "  };" ~
    "};" ~

    /* Bun.write(path, data) — like fs.writeFileSync but returns the
       number of bytes written. Accepts string | Uint8Array | BunFile. */
    "Bun.write = function(dest, data) {" ~
    "  var fs = require('fs');" ~
    "  return new Promise(function(res, rej) {" ~
    "    try {" ~
    "      var out;" ~
    "      if (typeof data === 'string') out = data;" ~
    "      else if (data instanceof Uint8Array) out = globalThis.Buffer.from(data);" ~
    "      else if (data && typeof data.arrayBuffer === 'function') {" ~
    "        return data.arrayBuffer().then(function(ab) {" ~
    "          var b = globalThis.Buffer.from(new Uint8Array(ab));" ~
    "          fs.writeFileSync(typeof dest === 'string' ? dest : dest.name, b);" ~
    "          res(b.length);" ~
    "        }, rej);" ~
    "      }" ~
    "      else out = String(data);" ~
    "      var path = typeof dest === 'string' ? dest : dest.name;" ~
    "      fs.writeFileSync(path, out);" ~
    "      res(typeof out === 'string' ? globalThis.Buffer.byteLength(out) : out.length);" ~
    "    } catch (e) { rej(e); }" ~
    "  });" ~
    "};" ~

    /* Bun.spawn / spawnSync — wrap child_process.spawn{Sync}.
       Bun's `p.stdout` is a Web ReadableStream<Uint8Array>, not a
       Node Readable, so `new Response(p.stdout).text()` works. We
       use Readable.toWeb() (from `stream`) to bridge. */
    "Bun.spawn = function(opts) {" ~
    "  var cp = require('child_process');" ~
    "  var Readable = require('stream').Readable;" ~
    "  var cmd = Array.isArray(opts) ? opts : opts.cmd;" ~
    "  var args = cmd.slice(1);" ~
    "  var child = cp.spawn(cmd[0], args, {" ~
    "    cwd: opts.cwd, env: opts.env || process.env," ~
    "    stdio: ['pipe', 'pipe', 'pipe']" ~
    "  });" ~
    "  var exitResolve;" ~
    "  var exited = new Promise(function(r) { exitResolve = r; });" ~
    "  var code = null;" ~
    "  child.on('exit', function(c) { code = c; exitResolve(c); });" ~
    "  return {" ~
    "    pid: child.pid," ~
    "    stdin: child.stdin," ~
    "    stdout: child.stdout ? Readable.toWeb(child.stdout) : null," ~
    "    stderr: child.stderr ? Readable.toWeb(child.stderr) : null," ~
    "    get exitCode() { return code; }," ~
    "    exited: exited," ~
    "    kill: function(sig) { child.kill(sig); }" ~
    "  };" ~
    "};" ~
    "Bun.spawnSync = function(opts) {" ~
    "  var cp = require('child_process');" ~
    "  var cmd = Array.isArray(opts) ? opts : opts.cmd;" ~
    "  var args = cmd.slice(1);" ~
    "  var res = cp.spawnSync(cmd[0], args, {" ~
    "    cwd: opts && opts.cwd, env: (opts && opts.env) || process.env" ~
    "  });" ~
    "  return {" ~
    "    success: res.status === 0," ~
    "    exitCode: res.status," ~
    "    stdout: res.stdout || globalThis.Buffer.alloc(0)," ~
    "    stderr: res.stderr || globalThis.Buffer.alloc(0)," ~
    "    signalCode: res.signal" ~
    "  };" ~
    "};" ~

    /* Bun.password.hash / verify — scrypt-based to keep things stdlib. */
    "Bun.password = {" ~
    "  hashSync: function(password, opts) {" ~
    "    var crypto = require('crypto');" ~
    "    var algo = (opts && opts.algorithm) || 'argon2id';" ~
    "    var salt = crypto.randomBytes(16);" ~
    "    var hash = crypto.scryptSync(password, salt, 64);" ~
    "    return '$dun-scrypt$' + salt.toString('hex') + '$' + hash.toString('hex');" ~
    "  }," ~
    "  hash: function(password, opts) {" ~
    "    return Promise.resolve(Bun.password.hashSync(password, opts));" ~
    "  }," ~
    "  verifySync: function(password, stored) {" ~
    "    var crypto = require('crypto');" ~
    "    var parts = String(stored).split('$');" ~
    "    if (parts.length !== 4 || parts[1] !== 'dun-scrypt') return false;" ~
    "    var salt = globalThis.Buffer.from(parts[2], 'hex');" ~
    "    var want = globalThis.Buffer.from(parts[3], 'hex');" ~
    "    var got = crypto.scryptSync(password, salt, want.length);" ~
    "    return crypto.timingSafeEqual(got, want);" ~
    "  }," ~
    "  verify: function(password, stored) {" ~
    "    return Promise.resolve(Bun.password.verifySync(password, stored));" ~
    "  }" ~
    "};" ~

    /* Bun.serve — HTTP server + optional WebSocket upgrade. Returns
       { port, hostname, stop, reload, fetch, upgrade, publish }. The
       fetch handler receives (request, server) — call server.upgrade(req)
       to convert a pending request into a WebSocket connection routed
       through opts.websocket.{open,message,close}. */
    "Bun.serve = function(opts) {" ~
    "  var http = require('http');" ~
    "  if (!opts || typeof opts.fetch !== 'function') {" ~
    "    throw new TypeError('Bun.serve requires opts.fetch handler');" ~
    "  }" ~
    "  var port = opts.port == null ? 3000 : (opts.port === 0 ? 0 : +opts.port);" ~
    "  var host = opts.hostname || opts.host || '0.0.0.0';" ~
    "  var fetch = opts.fetch;" ~
    "  var wsHandlers = opts.websocket || null;" ~
    "  /* Per-request state used by server.upgrade(req) */" ~
    "  var pendingUpgrade = new WeakMap();" ~
    "  var server = http.createServer(function(req, res) {" ~
    "    var chunks = [];" ~
    "    req.on('data', function(c) { chunks.push(c); });" ~
    "    req.on('end', function() {" ~
    "      var body = chunks.length ? globalThis.Buffer.concat(chunks) : undefined;" ~
    "      var url = (req.headers.host ? 'http://' + req.headers.host : 'http://localhost') + req.url;" ~
    "      var request;" ~
    "      try {" ~
    "        request = new Request(url, {" ~
    "          method: req.method," ~
    "          headers: req.headers," ~
    "          body: (req.method === 'GET' || req.method === 'HEAD') ? null : body" ~
    "        });" ~
    "      } catch (e) {" ~
    "        request = { method: req.method, url: url, headers: req.headers, body: body };" ~
    "      }" ~
    "      pendingUpgrade.set(request, { req: req, res: res, upgraded: false });" ~
    "      Promise.resolve().then(function() { return fetch(request, instance); }).then(function(resp) {" ~
    "        var pu = pendingUpgrade.get(request);" ~
    "        if (pu && pu.upgraded) return;  /* WebSocket took over */" ~
    "        if (!resp) { res.statusCode = 200; res.end(); return; }" ~
    "        var status = resp.status || 200;" ~
    "        var headers = {};" ~
    "        if (resp.headers && typeof resp.headers.forEach === 'function') {" ~
    "          resp.headers.forEach(function(v, k) { headers[k] = v; });" ~
    "        }" ~
    "        res.writeHead(status, headers);" ~
    "        if (typeof resp.text === 'function') {" ~
    "          resp.text().then(function(t) { res.end(t); }, function(e) { res.end(String(e)); });" ~
    "        } else if (typeof resp === 'string') {" ~
    "          res.end(resp);" ~
    "        } else {" ~
    "          res.end(JSON.stringify(resp));" ~
    "        }" ~
    "      }).catch(function(err) {" ~
    "        res.statusCode = 500;" ~
    "        res.end((opts.error ? opts.error(err) : String(err && err.stack || err)));" ~
    "      });" ~
    "    });" ~
    "  });" ~
    "  server.listen(port, host);" ~
    "  /* Per-server set of live WebSocket connections, used by .publish() */" ~
    "  var liveSockets = new Set();" ~
    "  var instance = {" ~
    "    port: port," ~
    "    hostname: host," ~
    "    development: opts.development === true," ~
    "    pendingRequests: 0," ~
    "    stop: function(closeActiveConnections) {" ~
    "      return new Promise(function(r) { server.close(function() { r(); }); });" ~
    "    }," ~
    "    reload: function(newOpts) { opts.fetch = newOpts.fetch || opts.fetch; }," ~
    "    fetch: function(req) { return Promise.resolve().then(function() { return fetch(req, instance); }); }," ~
    "    upgrade: function(request, attachedData) {" ~
    "      if (!wsHandlers) return false;" ~
    "      var pu = pendingUpgrade.get(request);" ~
    "      if (!pu || pu.upgraded) return false;" ~
    "      pu.upgraded = true;" ~
    "      var req = pu.req;" ~
    "      var res = pu.res;" ~
    "      /* Do the WebSocket handshake on the underlying TCP socket. */" ~
    "      var crypto = require('crypto');" ~
    "      var key = req.headers['sec-websocket-key'] || '';" ~
    "      var acceptKey = crypto.createHash('sha1')" ~
    "        .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')" ~
    "        .digest('base64');" ~
    "      var sock = req.socket || res.socket;" ~
    "      if (!sock) return false;" ~
    "      try {" ~
    "        sock.write(" ~
    "          'HTTP/1.1 101 Switching Protocols\\r\\n' +" ~
    "          'Upgrade: websocket\\r\\n' +" ~
    "          'Connection: Upgrade\\r\\n' +" ~
    "          'Sec-WebSocket-Accept: ' + acceptKey + '\\r\\n\\r\\n'" ~
    "        );" ~
    "      } catch (e) { return false; }" ~
    "      /* Build a small ws-like object that the user code receives. */" ~
    "      var ws = {" ~
    "        data: (attachedData && attachedData.data) || null," ~
    "        readyState: 1," ~
    "        send: function(msg) {" ~
    "          var payload = typeof msg === 'string' ? globalThis.Buffer.from(msg) : globalThis.Buffer.from(msg);" ~
    "          var opcode = typeof msg === 'string' ? 0x81 : 0x82;" ~
    "          var len = payload.length;" ~
    "          var header;" ~
    "          if (len < 126) header = globalThis.Buffer.from([opcode, len]);" ~
    "          else if (len < 65536) {" ~
    "            header = globalThis.Buffer.alloc(4);" ~
    "            header[0] = opcode; header[1] = 126;" ~
    "            header.writeUInt16BE(len, 2);" ~
    "          } else {" ~
    "            header = globalThis.Buffer.alloc(10);" ~
    "            header[0] = opcode; header[1] = 127;" ~
    "            header.writeUInt32BE(0, 2);" ~
    "            header.writeUInt32BE(len, 6);" ~
    "          }" ~
    "          try { sock.write(globalThis.Buffer.concat([header, payload])); }" ~
    "          catch (e) {}" ~
    "          return len;" ~
    "        }," ~
    "        close: function(code, reason) {" ~
    "          try { sock.write(globalThis.Buffer.from([0x88, 0])); sock.end(); }" ~
    "          catch (e) {}" ~
    "          ws.readyState = 3;" ~
    "          liveSockets.delete(ws);" ~
    "          if (wsHandlers.close) try { wsHandlers.close(ws, code || 1000, reason || ''); } catch (e) {}" ~
    "        }," ~
    "        ping: function() {" ~
    "          try { sock.write(globalThis.Buffer.from([0x89, 0])); } catch (e) {}" ~
    "        }," ~
    "        publish: function(topic, msg) { return instance.publish(topic, msg); }," ~
    "        subscribe: function(topic) { (ws._topics = ws._topics || new Set()).add(topic); }," ~
    "        unsubscribe: function(topic) { if (ws._topics) ws._topics.delete(topic); }," ~
    "        isSubscribed: function(topic) { return !!(ws._topics && ws._topics.has(topic)); }" ~
    "      };" ~
    "      liveSockets.add(ws);" ~
    "      /* Parse incoming WebSocket frames. */" ~
    "      var rxBuf = globalThis.Buffer.alloc(0);" ~
    "      sock.on('data', function(chunk) {" ~
    "        rxBuf = globalThis.Buffer.concat([rxBuf, chunk]);" ~
    "        while (rxBuf.length >= 2) {" ~
    "          var b0 = rxBuf[0]; var b1 = rxBuf[1];" ~
    "          var opcode = b0 & 0x0F;" ~
    "          var masked = (b1 & 0x80) !== 0;" ~
    "          var len = b1 & 0x7F;" ~
    "          var off = 2;" ~
    "          if (len === 126) {" ~
    "            if (rxBuf.length < 4) return;" ~
    "            len = rxBuf.readUInt16BE(2); off = 4;" ~
    "          } else if (len === 127) {" ~
    "            if (rxBuf.length < 10) return;" ~
    "            len = rxBuf.readUInt32BE(6); off = 10;" ~
    "          }" ~
    "          if (masked) {" ~
    "            if (rxBuf.length < off + 4 + len) return;" ~
    "            var mask = rxBuf.slice(off, off + 4); off += 4;" ~
    "            var payload = globalThis.Buffer.alloc(len);" ~
    "            for (var i = 0; i < len; i++) payload[i] = rxBuf[off + i] ^ mask[i % 4];" ~
    "            rxBuf = rxBuf.slice(off + len);" ~
    "            if (opcode === 0x1) {" ~
    "              if (wsHandlers.message) try { wsHandlers.message(ws, payload.toString('utf8')); } catch (e) {}" ~
    "            } else if (opcode === 0x2) {" ~
    "              if (wsHandlers.message) try { wsHandlers.message(ws, payload); } catch (e) {}" ~
    "            } else if (opcode === 0x8) {" ~
    "              ws.close(1000);" ~
    "              return;" ~
    "            } else if (opcode === 0x9 && wsHandlers.ping) {" ~
    "              try { wsHandlers.ping(ws, payload); } catch (e) {}" ~
    "            }" ~
    "          } else {" ~
    "            if (rxBuf.length < off + len) return;" ~
    "            rxBuf = rxBuf.slice(off + len);" ~
    "          }" ~
    "        }" ~
    "      });" ~
    "      sock.on('close', function() {" ~
    "        ws.readyState = 3;" ~
    "        liveSockets.delete(ws);" ~
    "        if (wsHandlers.close) try { wsHandlers.close(ws, 1006, ''); } catch (e) {}" ~
    "      });" ~
    "      if (wsHandlers.open) try { wsHandlers.open(ws); } catch (e) {}" ~
    "      return true;" ~
    "    }," ~
    "    publish: function(topic, msg) {" ~
    "      var sent = 0;" ~
    "      liveSockets.forEach(function(w) {" ~
    "        if (w._topics && w._topics.has(topic)) { w.send(msg); sent++; }" ~
    "      });" ~
    "      return sent;" ~
    "    }" ~
    "  };" ~
    "  return instance;" ~
    "};" ~

    /* Bun.which(cmd) — like which(1). */
    "Bun.which = function(cmd) {" ~
    "  if (!cmd || cmd.indexOf('/') >= 0) return cmd;" ~
    "  var fs = require('fs');" ~
    "  var path = require('path');" ~
    "  var pathDirs = (process.env.PATH || '').split(':');" ~
    "  for (var i = 0; i < pathDirs.length; i++) {" ~
    "    if (!pathDirs[i]) continue;" ~
    "    var p = path.join(pathDirs[i], cmd);" ~
    "    try { fs.accessSync(p, fs.constants.X_OK); return p; } catch (e) {}" ~
    "  }" ~
    "  return null;" ~
    "};" ~

    /* Bun.gc(force) — best-effort garbage collection hint. */
    "Bun.gc = function(force) { if (typeof gc === 'function') gc(); return 0; };" ~

    /* Bun.build — minimal bundler. Reads entrypoints, follows local
       imports, concatenates into a single output file (or returns the
       JS source as a string when outdir is omitted). Cross-module
       deduplication via a Set keyed by absolute path.

       Supported opts: entrypoints, outdir, target ('node'|'bun'|
       'browser'), define ({ 'KEY': 'value-as-source-literal' }),
       external (string[] -- skip these specifiers), minify (bool
       or { whitespace, syntax, identifiers }), naming, root.
       Returns Bun's BuildOutput shape: { success, outputs[], logs[] }. */
    "Bun.build = function(opts) {" ~
    "  var fs = require('fs');" ~
    "  var path = require('path');" ~
    "  if (!opts || !opts.entrypoints || !opts.entrypoints.length) {" ~
    "    return Promise.reject(new TypeError('Bun.build requires opts.entrypoints'));" ~
    "  }" ~
    "  var target = opts.target || 'bun';" ~
    "  var define = opts.define || {};" ~
    "  var external = new Set(opts.external || []);" ~
    "  var minify = opts.minify === true ? { whitespace: true, syntax: false, identifiers: false }" ~
    "             : (typeof opts.minify === 'object' && opts.minify) ? opts.minify : null;" ~
    "  var seen = new Set();" ~
    "  var out = [];" ~
    "  var logs = [];" ~
    /* Apply opts.define before bundling so compile-time constants
       collapse (e.g. process.env.NODE_ENV -> 'production' lets dead
       branches drop). define keys can be dotted paths -- escape the
       dots for the regex but match the dotted identifier literally. */
    "  function applyDefine(src) {" ~
    "    for (var k in define) {" ~
    "      if (!Object.prototype.hasOwnProperty.call(define, k)) continue;" ~
    "      var pat = k.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');" ~
    "      src = src.replace(new RegExp('\\\\b' + pat + '\\\\b', 'g'), define[k]);" ~
    "    }" ~
    "    return src;" ~
    "  }" ~
    // Cheap minify: strip block/line comments outside strings,
    // collapse runs of whitespace. No identifier renaming (needs AST).
    // The JS-side stripComments tracks string context so it doesn t
    // eat // inside string literals (D apostrophe avoided in this
    // comment; this is a D-level note, not part of the JS payload).
    "  function stripComments(src) {" ~
    "    var o = '', i = 0, n = src.length;" ~
    "    while (i < n) {" ~
    "      var c = src[i];" ~
    "      if (c === '\"' || c === \"'\" || c === '`') {" ~
    "        var q = c; o += c; i++;" ~
    "        while (i < n) {" ~
    "          if (src[i] === '\\\\') { o += src[i] + src[i+1]; i += 2; continue; }" ~
    "          o += src[i];" ~
    "          if (src[i] === q) { i++; break; }" ~
    "          i++;" ~
    "        }" ~
    "        continue;" ~
    "      }" ~
    "      if (c === '/' && src[i+1] === '/') {" ~
    "        while (i < n && src[i] !== '\\n') i++;" ~
    "        continue;" ~
    "      }" ~
    "      if (c === '/' && src[i+1] === '*') {" ~
    "        i += 2;" ~
    "        while (i+1 < n && !(src[i] === '*' && src[i+1] === '/')) i++;" ~
    "        i += 2;" ~
    "        continue;" ~
    "      }" ~
    "      o += c; i++;" ~
    "    }" ~
    "    return o;" ~
    "  }" ~
    "  function applyMinify(src) {" ~
    "    if (!minify) return src;" ~
    "    if (minify.whitespace !== false) {" ~
    "      src = stripComments(src);" ~
    "      src = src.replace(/[ \\t]+/g, ' ').replace(/\\n+/g, '\\n').replace(/\\s+;/g, ';');" ~
    "    }" ~
    "    return src.trim();" ~
    "  }" ~
    "  function emitModule(absPath) {" ~
    "    if (seen.has(absPath)) return;" ~
    "    seen.add(absPath);" ~
    "    var src;" ~
    "    try { src = fs.readFileSync(absPath, 'utf8'); }" ~
    "    catch (e) { logs.push({ level: 'error', message: 'read failed: ' + absPath }); return; }" ~
    "    var dir = path.dirname(absPath);" ~
    "    /* Relative imports get inlined; bare specifiers stay (unless
       'external' explicitly lists them, in which case they remain
       as runtime require/import). */" ~
    "    var importRe = /(?:^|\\n)\\s*import\\s+(?:[^'\"\\n]+\\s+from\\s+)?['\"]([^'\"]+)['\"];?/g;" ~
    "    var m;" ~
    "    while ((m = importRe.exec(src)) !== null) {" ~
    "      var spec = m[1];" ~
    "      var isRel = spec.charAt(0) === '.';" ~
    "      if (!isRel) {" ~
    "        if (!external.has(spec)) logs.push({ level: 'warn', message: 'bare specifier kept as runtime require: ' + spec });" ~
    "        continue;" ~
    "      }" ~
    "      var ref = path.resolve(dir, spec);" ~
    "      var candidates = [ref, ref+'.js', ref+'.mjs', ref+'.ts', ref+'.tsx', path.join(ref, 'index.js')];" ~
    "      var resolved = null;" ~
    "      for (var i = 0; i < candidates.length; i++) {" ~
    "        try { fs.accessSync(candidates[i]); resolved = candidates[i]; break; } catch(_){}" ~
    "      }" ~
    "      if (resolved) emitModule(resolved);" ~
    "      else logs.push({ level: 'error', message: 'unresolved: ' + spec + ' from ' + absPath });" ~
    "    }" ~
    "    /* Strip the import lines from the source so the concatenated
       output doesn't re-execute imports — bundled deps run inline. */" ~
    "    var stripped = src.replace(importRe, '');" ~
    "    stripped = applyDefine(stripped);" ~
    "    stripped = applyMinify(stripped);" ~
    "    if (!minify) out.push('// ===== ' + absPath + ' =====');" ~
    "    out.push(stripped);" ~
    "  }" ~
    "  for (var k = 0; k < opts.entrypoints.length; k++) {" ~
    "    emitModule(path.resolve(opts.entrypoints[k]));" ~
    "  }" ~
    "  var bundled = out.join(minify ? ';' : '\\n');" ~
    "  /* Banner per target so consumers can grep the build target. */" ~
    "  var banner = minify ? '' : '/* Bun.build target=' + target + ' */\\n';" ~
    "  bundled = banner + bundled;" ~
    "  var outName = (opts.naming && opts.naming.entry) || 'bundle.js';" ~
    "  var artifacts = [{" ~
    "    path: opts.outdir ? path.join(opts.outdir, outName) : '<inline>'," ~
    "    text: function() { return Promise.resolve(bundled); }," ~
    "    arrayBuffer: function() { return Promise.resolve(new TextEncoder().encode(bundled).buffer); }," ~
    "    kind: 'entry-point'," ~
    "    loader: 'js'," ~
    "    hash: null," ~
    "    size: bundled.length," ~
    "    type: 'application/javascript'" ~
    "  }];" ~
    "  if (opts.outdir) {" ~
    "    try { fs.mkdirSync(opts.outdir, { recursive: true }); } catch (_) {}" ~
    "    fs.writeFileSync(path.join(opts.outdir, outName), bundled);" ~
    "  }" ~
    "  return Promise.resolve({ success: logs.filter(function(l){return l.level==='error';}).length === 0, outputs: artifacts, logs: logs });" ~
    "};" ~

    /* Bun.FileSystemRouter — given a directory and a style, builds
       a route table that maps URL paths to filesystem entries. Used
       by Bun.serve-style apps to wire up file-based routing. */
    "Bun.FileSystemRouter = function(opts) {" ~
    "  if (!opts || !opts.dir) throw new TypeError('FileSystemRouter requires { dir }');" ~
    "  var fs = require('fs');" ~
    "  var path = require('path');" ~
    "  var dir = path.resolve(opts.dir);" ~
    "  var style = opts.style || 'nextjs';" ~
    "  var assetPrefix = opts.assetPrefix || '';" ~
    "  var origin = opts.origin || '';" ~
    "  var routes = {};" ~
    "  function walk(d) {" ~
    "    var entries;" ~
    "    try { entries = fs.readdirSync(d, { withFileTypes: true }); }" ~
    "    catch (e) { return; }" ~
    "    for (var i = 0; i < entries.length; i++) {" ~
    "      var entry = entries[i];" ~
    "      var p = path.join(d, entry.name);" ~
    "      if (entry.isDirectory()) { walk(p); continue; }" ~
    "      var ext = path.extname(entry.name);" ~
    "      if (!/^\\.(js|jsx|ts|tsx|mjs)$/.test(ext)) continue;" ~
    "      var rel = path.relative(dir, p);" ~
    "      var routePath = '/' + rel.slice(0, -ext.length).replace(/\\\\/g, '/');" ~
    "      /* /index → /  ;  /users/index → /users */" ~
    "      if (routePath === '/index') routePath = '/';" ~
    "      else routePath = routePath.replace(/\\/index$/, '');" ~
    "      /* [param] → :param  (Next.js style) */" ~
    "      routePath = routePath.replace(/\\[([^\\]]+)\\]/g, ':$1');" ~
    "      routes[routePath] = p;" ~
    "    }" ~
    "  }" ~
    "  walk(dir);" ~
    "  var instance = {" ~
    "    routes: routes," ~
    "    style: style," ~
    "    assetPrefix: assetPrefix," ~
    "    origin: origin," ~
    "    match: function(input) {" ~
    "      var url = typeof input === 'string' ? input : input.url;" ~
    "      var u; try { u = new URL(url, 'http://x/'); } catch (e) { u = { pathname: url }; }" ~
    "      var pathname = u.pathname;" ~
    "      /* exact match first */" ~
    "      if (routes[pathname]) {" ~
    "        return { name: pathname, filePath: routes[pathname], pathname: pathname, params: {}, query: queryToObj(u.search), kind: 'exact-route', src: routes[pathname] };" ~
    "      }" ~
    "      /* parameterized */" ~
    "      var keys = Object.keys(routes);" ~
    "      for (var i = 0; i < keys.length; i++) {" ~
    "        var pat = keys[i];" ~
    "        var re = new RegExp('^' + pat.replace(/:[^/]+/g, '([^/]+)') + '$');" ~
    "        var m = re.exec(pathname);" ~
    "        if (m) {" ~
    "          var params = {};" ~
    "          var paramNames = (pat.match(/:[^/]+/g) || []).map(function(s) { return s.slice(1); });" ~
    "          for (var p = 0; p < paramNames.length; p++) params[paramNames[p]] = m[p + 1];" ~
    "          return { name: pat, filePath: routes[pat], pathname: pathname, params: params, query: queryToObj(u.search), kind: 'dynamic', src: routes[pat] };" ~
    "        }" ~
    "      }" ~
    "      return null;" ~
    "    }," ~
    "    reload: function() { routes = {}; walk(dir); instance.routes = routes; }" ~
    "  };" ~
    "  function queryToObj(s) {" ~
    "    if (!s || s.length < 2) return {};" ~
    "    var o = {};" ~
    "    var parts = s.slice(1).split('&');" ~
    "    for (var i = 0; i < parts.length; i++) {" ~
    "      var kv = parts[i].split('=');" ~
    "      o[decodeURIComponent(kv[0])] = kv[1] ? decodeURIComponent(kv[1]) : '';" ~
    "    }" ~
    "    return o;" ~
    "  }" ~
    "  return instance;" ~
    "};" ~

    /* Bun.peek — synchronously read the resolved value of an already-
       settled Promise (without await). Returns the promise itself if
       still pending. Bun ships this as a debugging aid. */
    "Bun.peek = function(p) {" ~
    "  if (!p || typeof p.then !== 'function') return p;" ~
    "  var state = { done: false, value: undefined, err: undefined };" ~
    "  p.then(function(v) { state.done = true; state.value = v; }," ~
    "         function(e) { state.done = true; state.err = e; });" ~
    "  return state.done ? (state.err ? state.err : state.value) : p;" ~
    "};" ~
    "Bun.peek.status = function(p) {" ~
    "  if (!p || typeof p.then !== 'function') return 'fulfilled';" ~
    "  var s = 'pending';" ~
    "  p.then(function() { s = 'fulfilled'; }, function() { s = 'rejected'; });" ~
    "  return s;" ~
    "};" ~

    /* Bun.nanoseconds() — high-resolution time since process start,
       in nanoseconds. process.hrtime.bigint() returns ns since boot,
       so we subtract the value captured at module init. */
    "(function(){" ~
    "  var t0 = (typeof process !== 'undefined' && process.hrtime && process.hrtime.bigint)" ~
    "         ? process.hrtime.bigint() : BigInt(Date.now()) * 1000000n;" ~
    "  Bun.nanoseconds = function() {" ~
    "    var now = (process.hrtime && process.hrtime.bigint)" ~
    "            ? process.hrtime.bigint() : BigInt(Date.now()) * 1000000n;" ~
    "    return Number(now - t0);" ~
    "  };" ~
    "})();" ~

    /* Bun.resolveSync — resolve a specifier from a base directory
       (equivalent of require.resolve). */
    "Bun.resolveSync = function(specifier, parent) {" ~
    "  try {" ~
    "    if (typeof require !== 'undefined' && require.resolve) return require.resolve(specifier);" ~
    "  } catch (e) {}" ~
    "  return specifier;" ~
    "};" ~

    /* Bun.color(input, output) — minimal pass-through. Bun's real
       implementation converts hex/rgb/hsl/etc. to other forms. */
    "Bun.color = function(input, output) {" ~
    "  if (input == null) return null;" ~
    "  /* If input is already a hex, return as-is when output === 'hex'. */" ~
    "  return String(input);" ~
    "};" ~

    /* Bun.s / Bun.ms timer aliases used by tests. */
    "Bun.ms = function() { return Date.now(); };" ~

    /* Bun.fileURLToPath / Bun.pathToFileURL — same semantics as the
       node:url helpers; Bun re-exports them on the Bun namespace too. */
    "Bun.fileURLToPath = function(url) {" ~
    "  var u = require('url');" ~
    "  return u.fileURLToPath ? u.fileURLToPath(url)" ~
    "    : (typeof url === 'string' && url.indexOf('file://') === 0)" ~
    "      ? decodeURIComponent(url.slice(7)) : String(url);" ~
    "};" ~
    "Bun.pathToFileURL = function(p) {" ~
    "  var u = require('url');" ~
    "  if (u.pathToFileURL) return u.pathToFileURL(p);" ~
    "  return new URL('file://' + encodeURI(String(p).replace(/\\\\/g, '/')));" ~
    "};" ~

    /* Bun.indexOfLine(buf, offset) — find the next newline; mostly used
       by log parsers. We give it a straight loop fallback. */
    "Bun.indexOfLine = function(buf, off) {" ~
    "  off = off | 0;" ~
    "  for (var i = off; i < buf.length; i++) {" ~
    "    if (buf[i] === 0x0A) return i;" ~
    "  }" ~
    "  return -1;" ~
    "};" ~

    /* Bun.deflateSync / inflateSync / gzipSync / gunzipSync — aliases
       to node:zlib. Use a getter so the `require('zlib')` only fires
       when the function is actually called (the CJS shim isn't
       installed at bun-compat init time). */
    "Bun.deflateSync=function(d,o){return require('zlib').deflateSync(d,o);};" ~
    "Bun.inflateSync=function(d,o){return require('zlib').inflateSync(d,o);};" ~
    "Bun.gzipSync=function(d,o){return require('zlib').gzipSync(d,o);};" ~
    "Bun.gunzipSync=function(d,o){return require('zlib').gunzipSync(d,o);};" ~

    /* Bun.SHA256 / SHA1 / SHA512 / MD5 — class-style hash constructors.
       Built lazily on first construction so the underlying
       `require('crypto')` doesn't fire at install time. */
    "function _mkBunHash(name){" ~
    "var alg=name.toLowerCase();" ~
    "var C=function BunHash(){" ~
    "if(!(this instanceof C))return new C();" ~
    "this._h=require('crypto').createHash(alg);" ~
    "};" ~
    "C.prototype.update=function(d){this._h.update(d);return this;};" ~
    "C.prototype.digest=function(enc){return this._h.digest(enc||'buffer');};" ~
    "C.hash=function(input,enc){return require('crypto').createHash(alg).update(input).digest(enc||'buffer');};" ~
    "Bun[name]=C;" ~
    "}" ~
    "['SHA256','SHA1','SHA512','MD5'].forEach(_mkBunHash);" ~

    /* Bun.connect({hostname,port,socket}) / Bun.listen({hostname,port,socket})
       — TCP sockets wrapped around node:net. The `socket` handlers
       (`data`/`open`/`close`/`error`) map onto net.Socket events. */
    "Bun.connect = function(opts) {" ~
    "  var net = require('net');" ~
    "  return new Promise(function(resolve, reject) {" ~
    "    var s = net.createConnection({ host: opts.hostname, port: opts.port }, function() {" ~
    "      var h = opts.socket || {};" ~
    "      if (h.open) try { h.open(s); } catch (e) {}" ~
    "      s.on('data', function(d) { if (h.data) h.data(s, d); });" ~
    "      s.on('close', function() { if (h.close) h.close(s); });" ~
    "      s.on('error', function(e) { if (h.error) h.error(s, e); });" ~
    "      s.write = s.write.bind(s);" ~
    "      s.end   = s.end.bind(s);" ~
    "      resolve(s);" ~
    "    });" ~
    "    s.once('error', reject);" ~
    "  });" ~
    "};" ~
    "Bun.listen = function(opts) {" ~
    "  var net = require('net');" ~
    "  var h = opts.socket || {};" ~
    "  var srv = net.createServer(function(s) {" ~
    "    if (h.open) try { h.open(s); } catch (e) {}" ~
    "    s.on('data', function(d) { if (h.data) h.data(s, d); });" ~
    "    s.on('close', function() { if (h.close) h.close(s); });" ~
    "    s.on('error', function(e) { if (h.error) h.error(s, e); });" ~
    "  });" ~
    "  srv.listen(opts.port, opts.hostname || '0.0.0.0');" ~
    "  return { stop: function() { srv.close(); }, hostname: opts.hostname, port: opts.port };" ~
    "};" ~

    /* Bun.udpSocket({port,socket}) — UDP datagram wrapper around
       node:dgram. Returns the socket with `.send()` + `.close()`. */
    "Bun.udpSocket = function(opts) {" ~
    "  var dgram = require('dgram');" ~
    "  var sock = dgram.createSocket('udp4');" ~
    "  var h = opts.socket || {};" ~
    "  sock.on('message', function(msg, rinfo) { if (h.data) h.data(sock, msg, rinfo); });" ~
    "  sock.on('error',   function(err)        { if (h.error) h.error(sock, err); });" ~
    "  if (opts.port) sock.bind(opts.port, opts.hostname);" ~
    "  return Promise.resolve(sock);" ~
    "};" ~


    /* Bun.allocUnsafe(n) — non-zeroed Buffer; Node's Buffer.allocUnsafe. */
    "Bun.allocUnsafe = function(size) {" ~
    "  return globalThis.Buffer.allocUnsafe(size);" ~
    "};" ~

    /* Bun.semver — minimal subset (satisfies / order / sort). Bun's
       full API has many more methods; this covers the common
       npm-package-version-check usage. */
    "Bun.semver = {" ~
    "  satisfies: function(version, range) {" ~
    "    /* very minimal — supports `1.2.3`, `^1.2.3`, `~1.2.3`, `>=1.2.3`, `*` */" ~
    "    if (!version || !range) return false;" ~
    "    if (range === '*' || range === '') return true;" ~
    "    var v = String(version).replace(/^v/, '').split('.').map(Number);" ~
    "    var op = '';" ~
    "    var r = String(range).trim();" ~
    "    if (r[0] === '^') { op = '^'; r = r.slice(1); }" ~
    "    else if (r[0] === '~') { op = '~'; r = r.slice(1); }" ~
    "    else if (r.slice(0,2) === '>=') { op = '>='; r = r.slice(2).trim(); }" ~
    "    else if (r.slice(0,2) === '<=') { op = '<='; r = r.slice(2).trim(); }" ~
    "    else if (r[0] === '>') { op = '>'; r = r.slice(1).trim(); }" ~
    "    else if (r[0] === '<') { op = '<'; r = r.slice(1).trim(); }" ~
    "    var t = r.replace(/^v/, '').split('.').map(Number);" ~
    "    var cmp = (v[0]-t[0]) || (v[1]-t[1]) || (v[2]-t[2]);" ~
    "    if (op === '' || op === '=') return cmp === 0;" ~
    "    if (op === '^') return v[0] === t[0] && (cmp >= 0);" ~
    "    if (op === '~') return v[0] === t[0] && v[1] === t[1] && (v[2] >= t[2]);" ~
    "    if (op === '>=') return cmp >= 0;" ~
    "    if (op === '<=') return cmp <= 0;" ~
    "    if (op === '>')  return cmp > 0;" ~
    "    if (op === '<')  return cmp < 0;" ~
    "    return false;" ~
    "  }," ~
    "  order: function(a, b) {" ~
    "    var pa = String(a).replace(/^v/, '').split('.').map(Number);" ~
    "    var pb = String(b).replace(/^v/, '').split('.').map(Number);" ~
    "    return (pa[0]-pb[0]) || (pa[1]-pb[1]) || ((pa[2]||0)-(pb[2]||0));" ~
    "  }," ~
    "};" ~

    /* Bun.openInEditor(file) — invoke $EDITOR / $VISUAL on the given
       path. No-op (returns false) when neither var is set. */
    "Bun.openInEditor = function(file, opts) {" ~
    "  opts = opts || {};" ~
    "  var ed = (typeof process !== 'undefined' && process.env) ?" ~
    "    (process.env.VISUAL || process.env.EDITOR) : null;" ~
    "  if (!ed) return false;" ~
    "  try {" ~
    "    var cp = require('child_process');" ~
    "    cp.spawnSync(ed, [file], { stdio: 'inherit' });" ~
    "    return true;" ~
    "  } catch (e) { return false; }" ~
    "};" ~

    /* Bun.stringWidth(s) — Node-compatible string-width estimator that
       only counts visible chars (ANSI escapes stripped). */
    "Bun.stringWidth = function(s) {" ~
    "  if (s == null) return 0;" ~
    "  s = String(s);" ~
    "  /* Drop ANSI CSI sequences (ESC + [ + params + letter). */" ~
    "  s = s.replace(/\\x1B\\[[0-9;]*[A-Za-z]/g, '');" ~
    "  return s.length;" ~
    "};" ~

    /* Bun.readableStreamTo* — drain a ReadableStream into the named
       form. All four follow the same shape: getReader().read() loop,
       concat chunks at the end. The Buffer versions need Buffer
       available (always true on DunJS since global Buffer is wired
       in via dun:buffer). */
    "Bun.readableStreamToArrayBuffer = async function(stream) {" ~
    "  var reader = stream.getReader();" ~
    "  var chunks = [], total = 0;" ~
    "  while (true) {" ~
    "    var r = await reader.read();" ~
    "    if (r.done) break;" ~
    "    var chunk = r.value instanceof Uint8Array ? r.value : new TextEncoder().encode(String(r.value));" ~
    "    chunks.push(chunk); total += chunk.byteLength;" ~
    "  }" ~
    "  var out = new Uint8Array(total), off = 0;" ~
    "  for (var i = 0; i < chunks.length; i++) { out.set(chunks[i], off); off += chunks[i].byteLength; }" ~
    "  return out.buffer;" ~
    "};" ~
    "Bun.readableStreamToBytes = async function(stream) {" ~
    "  return new Uint8Array(await Bun.readableStreamToArrayBuffer(stream));" ~
    "};" ~
    "Bun.readableStreamToText = async function(stream) {" ~
    "  var ab = await Bun.readableStreamToArrayBuffer(stream);" ~
    /* TextDecoder accepts BufferSource per spec, but engines vary on
       ArrayBuffer-vs-view handling; wrap to be safe. */
    "  return new TextDecoder().decode(new Uint8Array(ab));" ~
    "};" ~
    "Bun.readableStreamToJSON = async function(stream) {" ~
    "  return JSON.parse(await Bun.readableStreamToText(stream));" ~
    "};" ~
    "Bun.readableStreamToBlob = async function(stream) {" ~
    "  var ab = await Bun.readableStreamToArrayBuffer(stream);" ~
    "  return new Blob([ab]);" ~
    "};" ~
    "Bun.readableStreamToFormData = async function(stream, boundary) {" ~
    "  var txt = await Bun.readableStreamToText(stream);" ~
    "  var fd = new FormData();" ~
    "  /* minimal multipart parse — splits on boundary, extracts name + body */" ~
    "  if (!boundary) return fd;" ~
    "  var parts = txt.split('--' + boundary);" ~
    "  for (var i = 1; i < parts.length - 1; i++) {" ~
    "    var p = parts[i];" ~
    "    var m = /name=\"([^\"]+)\"/.exec(p);" ~
    "    if (!m) continue;" ~
    "    var bodyStart = p.indexOf('\\r\\n\\r\\n');" ~
    "    if (bodyStart === -1) continue;" ~
    "    fd.append(m[1], p.slice(bodyStart + 4).replace(/\\r\\n$/, ''));" ~
    "  }" ~
    "  return fd;" ~
    "};" ~
    "Bun.readableStreamToArray = async function(stream) {" ~
    "  var reader = stream.getReader();" ~
    "  var arr = [];" ~
    "  while (true) { var r = await reader.read(); if (r.done) break; arr.push(r.value); }" ~
    "  return arr;" ~
    "};" ~

    /* Bun.Glob — minimal glob-pattern matcher. Real Bun has a Rust
       impl with full POSIX glob semantics; this JS shim covers the
       common patterns: * (any chars except /), ** (any chars including
       /), ? (single char), [abc] (char class), {a,b} (alternation). */
    "Bun.Glob = function Glob(pattern) {" ~
    "  if (!(this instanceof Glob)) return new Glob(pattern);" ~
    "  this.pattern = pattern;" ~
    "  /* Translate glob → regex once at construction. */" ~
    "  var re = '';" ~
    "  var inClass = false;" ~
    "  for (var i = 0; i < pattern.length; i++) {" ~
    "    var c = pattern[i];" ~
    "    if (inClass) {" ~
    "      if (c === ']') { inClass = false; re += ']'; } else re += c;" ~
    "      continue;" ~
    "    }" ~
    "    if (c === '*' && pattern[i+1] === '*') { re += '.*'; i++; }" ~
    "    else if (c === '*') re += '[^/]*';" ~
    "    else if (c === '?') re += '[^/]';" ~
    "    else if (c === '[') { inClass = true; re += '['; }" ~
    "    else if (c === '{') {" ~
    "      /* alternation — find matching brace, split on commas */" ~
    "      var end = pattern.indexOf('}', i);" ~
    "      if (end === -1) { re += '\\\\{'; continue; }" ~
    "      var alts = pattern.slice(i+1, end).split(',');" ~
    "      re += '(' + alts.map(function(a) { return a.replace(/[.+^${}()|[\\]\\\\]/g, '\\\\$&'); }).join('|') + ')';" ~
    "      i = end;" ~
    "    }" ~
    "    else if ('.+^${}()|\\\\'.indexOf(c) !== -1) re += '\\\\' + c;" ~
    "    else re += c;" ~
    "  }" ~
    "  this._regex = new RegExp('^' + re + '$');" ~
    "};" ~
    "Bun.Glob.prototype.match = function(input) {" ~
    "  return this._regex.test(input);" ~
    "};" ~
    "Bun.Glob.prototype.scan = function(opts) {" ~
    "  /* Async iterator over matching files in `opts.cwd` (or '.'). */" ~
    "  var self = this;" ~
    "  var fs = require('fs');" ~
    "  var path = require('path');" ~
    "  var root = (opts && opts.cwd) || '.';" ~
    "  var results = [];" ~
    "  function walk(dir, prefix) {" ~
    "    var entries;" ~
    "    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }" ~
    "    for (var i = 0; i < entries.length; i++) {" ~
    "      var e = entries[i];" ~
    "      var rel = prefix ? prefix + '/' + e.name : e.name;" ~
    "      if (e.isDirectory()) walk(path.join(dir, e.name), rel);" ~
    "      else if (self.match(rel)) results.push(rel);" ~
    "    }" ~
    "  }" ~
    "  walk(root, '');" ~
    "  return (async function*() { for (var i = 0; i < results.length; i++) yield results[i]; })();" ~
    "};" ~
    "Bun.Glob.prototype.scanSync = function(opts) {" ~
    "  /* Sync variant returning an array directly. */" ~
    "  var self = this;" ~
    "  var fs = require('fs');" ~
    "  var path = require('path');" ~
    "  var root = (opts && opts.cwd) || '.';" ~
    "  var results = [];" ~
    "  function walk(dir, prefix) {" ~
    "    var entries;" ~
    "    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }" ~
    "    for (var i = 0; i < entries.length; i++) {" ~
    "      var e = entries[i];" ~
    "      var rel = prefix ? prefix + '/' + e.name : e.name;" ~
    "      if (e.isDirectory()) walk(path.join(dir, e.name), rel);" ~
    "      else if (self.match(rel)) results.push(rel);" ~
    "    }" ~
    "  }" ~
    "  walk(root, '');" ~
    "  return results;" ~
    "};" ~

    /* Bun.dns — wrap node:dns. Real Bun has resolver tuning and
       per-instance caching; this shim is enough for code that just
       calls `Bun.dns.lookup(host)`. */
    "Bun.dns = {" ~
    "  lookup: function(host, opts) {" ~
    "    var dns = require('dns').promises || require('dns');" ~
    "    return dns.lookup ? dns.lookup(host, opts) : Promise.reject(new Error('dns.lookup unavailable'));" ~
    "  }" ~
    "};" ~

    "globalThis.Bun = Bun;" ~
    "})();";
}
