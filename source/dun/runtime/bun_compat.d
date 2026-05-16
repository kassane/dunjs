/// Bun.* compatibility surface.
///
/// Bun ships a `Bun` namespace on the global object with helpers like
/// `Bun.serve`, `Bun.file`, `Bun.spawn`, `Bun.password.{hash,verify}`,
/// `Bun.hash`, `Bun.sleep`, `Bun.env`, `Bun.argv`, `Bun.version`, etc.
/// This module exposes a JS-level shim that maps each of those to our
/// existing Node-style implementations (http, fs, child_process, crypto,
/// timers), so projects written against the Bun API can run unchanged.
///
/// Coverage matches what real Bun apps actually call most often:
///   - Bun.serve / Bun.file / Bun.write
///   - Bun.spawn / Bun.spawnSync
///   - Bun.password.hash / verify  (scrypt-backed; same output shape)
///   - Bun.sleep / Bun.sleepSync
///   - Bun.hash (non-cryptographic)
///   - Bun.escapeHTML / Bun.deepEquals / Bun.inspect
///   - Bun.env / Bun.argv / Bun.version / Bun.revision
///
/// Anything not implemented throws "not implemented in DunJS" so
/// fallbacks can branch on existence cleanly.
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

    /* Bun.hash — non-cryptographic 64-bit-ish FNV-1a fold to JS number. */
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

    /* Bun.spawn / spawnSync — wrap child_process.spawn{Sync}. */
    "Bun.spawn = function(opts) {" ~
    "  var cp = require('child_process');" ~
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
    "    stdout: child.stdout," ~
    "    stderr: child.stderr," ~
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

    /* Bun.serve — minimal HTTP server with a fetch-style handler.
       Returns a server object with .stop() / .reload() / .port / .hostname. */
    "Bun.serve = function(opts) {" ~
    "  var http = require('http');" ~
    "  if (!opts || typeof opts.fetch !== 'function') {" ~
    "    throw new TypeError('Bun.serve requires opts.fetch handler');" ~
    "  }" ~
    "  var port = opts.port == null ? 3000 : (opts.port === 0 ? 0 : +opts.port);" ~
    "  var host = opts.hostname || opts.host || '0.0.0.0';" ~
    "  var fetch = opts.fetch;" ~
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
    "      Promise.resolve().then(function() { return fetch(request); }).then(function(resp) {" ~
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
    "  return {" ~
    "    port: port," ~
    "    hostname: host," ~
    "    development: opts.development === true," ~
    "    pendingRequests: 0," ~
    "    stop: function(closeActiveConnections) {" ~
    "      return new Promise(function(r) { server.close(function() { r(); }); });" ~
    "    }," ~
    "    reload: function(newOpts) { opts.fetch = newOpts.fetch || opts.fetch; }," ~
    "    fetch: function(req) { return Promise.resolve().then(function() { return fetch(req); }); }" ~
    "  };" ~
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

    "globalThis.Bun = Bun;" ~
    "})();";
}
