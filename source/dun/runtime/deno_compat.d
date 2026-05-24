module dun.runtime.deno_compat;


/++
 + `@trusted policy`: Deno compatibility shim (30+ Deno.* APIs).
 + Every `@trusted` is one of:
 +
 +   1. POSIX syscalls for `Deno.makeTempDir`, `Deno.chmod`,
 +      `Deno.symlink`, etc. — same justification as `fs.d`.
 +   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +   3. Async work submission for `Deno.readTextFile` /
 +      `Deno.writeTextFile` via `asyncSubmit`.
 +   4. JS-side shim install (`Deno.serve`, `Deno.openKv`,
 +      `Deno.test`, …) via `engine.eval` of cached source —
 +      install-time only, the cached eval result is the
 +      permanent function handle.
 +/
import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState, ctxState;
import dun.security.permissions : Permission;

void installDenoCompat(IJSEngine engine) @trusted
{
    auto denoObj = engine.newObject();

    // Deno.version
    auto versionObj = engine.newObject();
    engine.setProperty(versionObj, "deno", engine.newString("1.46.0"));
    engine.setProperty(versionObj, "v8", engine.newString("12.9.202.13"));
    engine.setProperty(versionObj, "typescript", engine.newString("5.6.2"));
    engine.setProperty(denoObj, "version", versionObj);

    // Deno.build
    auto buildObj = engine.newObject();
    version (linux) engine.setProperty(buildObj, "os", engine.newString("linux"));
    else version (OSX) engine.setProperty(buildObj, "os", engine.newString("darwin"));
    else version (Windows) engine.setProperty(buildObj, "os", engine.newString("windows"));
    else engine.setProperty(buildObj, "os", engine.newString("unknown"));
    version (X86_64) engine.setProperty(buildObj, "arch", engine.newString("x86_64"));
    else version (AArch64) engine.setProperty(buildObj, "arch", engine.newString("aarch64"));
    else engine.setProperty(buildObj, "arch", engine.newString("unknown"));
    engine.setProperty(buildObj, "target", engine.newString(buildTarget()));
    engine.setProperty(buildObj, "vendor", engine.newString("dun"));
    engine.setProperty(denoObj, "build", buildObj);

    // Deno.env
    auto envObj = engine.newObject();
    engine.setProperty(envObj, "get", engine.newFunction(&denoEnvGet, "get", 1));
    engine.setProperty(envObj, "set", engine.newFunction(&denoEnvSet, "set", 2));
    engine.setProperty(envObj, "delete", engine.newFunction(&denoEnvDelete, "delete", 1));
    engine.setProperty(envObj, "has", engine.newFunction(&denoEnvHas, "has", 1));
    engine.setProperty(envObj, "toObject", engine.newFunction(&denoEnvToObject, "toObject", 0));
    engine.setProperty(denoObj, "env", envObj);

    // Deno.readTextFileSync / Deno.readTextFile
    engine.setProperty(denoObj, "readTextFileSync",
        engine.newFunction(&denoReadTextFileSync, "readTextFileSync", 1));
    engine.setProperty(denoObj, "readTextFile",
        engine.newFunction(&denoReadTextFile, "readTextFile", 1));

    // Deno.writeTextFileSync / Deno.writeTextFile
    engine.setProperty(denoObj, "writeTextFileSync",
        engine.newFunction(&denoWriteTextFileSync, "writeTextFileSync", 2));
    engine.setProperty(denoObj, "writeTextFile",
        engine.newFunction(&denoWriteTextFile, "writeTextFile", 2));

    // Deno.readFileSync (returns string for now, should be Uint8Array)
    engine.setProperty(denoObj, "readFileSync",
        engine.newFunction(&denoReadTextFileSync, "readFileSync", 1));

    // Deno.statSync / Deno.lstatSync.
    engine.setProperty(denoObj, "statSync",
        engine.newFunction(&denoStatSync, "statSync", 1));
    engine.setProperty(denoObj, "lstatSync",
        engine.newFunction(&denoStatSync, "lstatSync", 1));

    // Deno.mkdirSync + Deno.mkdir (async). The async variant runs the
    // same body and wraps in a resolved Promise -- Deno's real
    // implementation is also synchronous under the hood for the local
    // FS, so the only observable difference is the Promise return.
    engine.setProperty(denoObj, "mkdirSync",
        engine.newFunction(&denoMkdirSync, "mkdirSync", 1));
    // Deno.mkdir (async) is registered via the JS-side shim at the
    // bottom of installDenoCompat (denoAsyncFsShim).

    // Deno.removeSync.
    engine.setProperty(denoObj, "removeSync",
        engine.newFunction(&denoRemoveSync, "removeSync", 1));

    // Deno.renameSync.
    engine.setProperty(denoObj, "renameSync",
        engine.newFunction(&denoRenameSync, "renameSync", 2));

    // Deno.copyFileSync.
    engine.setProperty(denoObj, "copyFileSync",
        engine.newFunction(&denoCopyFileSync, "copyFileSync", 2));

    // Deno.readDirSync.
    engine.setProperty(denoObj, "readDirSync",
        engine.newFunction(&denoReadDirSync, "readDirSync", 1));

    // Deno.realPathSync
    engine.setProperty(denoObj, "realPathSync",
        engine.newFunction(&denoRealPathSync, "realPathSync", 1));

    // Deno.truncateSync
    engine.setProperty(denoObj, "truncateSync",
        engine.newFunction(&denoTruncateSync, "truncateSync", 2));

    // Deno.cwd / Deno.chdir
    engine.setProperty(denoObj, "cwd",
        engine.newFunction(&denoCwd, "cwd", 0));
    engine.setProperty(denoObj, "chdir",
        engine.newFunction(&denoChdir, "chdir", 1));

    // Deno.exit
    engine.setProperty(denoObj, "exit",
        engine.newFunction(&denoExit, "exit", 1));

    // Deno.hostname
    engine.setProperty(denoObj, "hostname",
        engine.newFunction(&denoHostname, "hostname", 0));

    // Deno.args
    engine.setProperty(denoObj, "args", engine.newArray());

    // Deno.pid / Deno.ppid
    version (Posix)
    {
        import core.sys.posix.unistd : getpid, getppid;
        engine.setProperty(denoObj, "pid", engine.newInt(getpid()));
        engine.setProperty(denoObj, "ppid", engine.newInt(getppid()));
    }

    // Deno.noColor
    engine.setProperty(denoObj, "noColor", engine.newBool(noColorEnabled()));

    // Deno.mainModule (set by CLI before script execution)
    engine.setProperty(denoObj, "mainModule", engine.newString(""));

    // Deno.permissions
    auto permsObj = engine.newObject();
    engine.setProperty(permsObj, "query", engine.newFunction(&denoPermissionsQuery, "query", 1));
    engine.setProperty(denoObj, "permissions", permsObj);

    // Deno.inspect
    engine.setProperty(denoObj, "inspect",
        engine.newFunction(&denoInspect, "inspect", 1));

    // Deno.errors -- placeholder; the JS-side shim below replaces each
    // member with a real Error subclass so `instanceof` checks work.
    auto errorsObj = engine.newObject();
    engine.setProperty(denoObj, "errors", errorsObj);

    auto global = engine.getGlobal();
    engine.setProperty(global, "Deno", denoObj);
    engine.freeValue(global);

    // Deno.serve + Deno.openKv ship as a JS-level shim because both are
    // built from existing http / EventTarget primitives. Keeping them
    // here means we can iterate on the wrapper without recompiling.
    auto shimRes = engine.eval(denoServeAndKvSource(), "<deno-serve-kv>");
    if (!shimRes.isError) engine.freeValue(shimRes.value);

    // Async file-system shims. Each delegates to its `*Sync` companion
    // and wraps the result (or thrown error) in a Promise. Deno's real
    // implementations are also synchronous under the hood on local FS,
    // so the only observable difference is the return-type contract.
    // `readDir` returns an AsyncIterable so `for await` works.
    auto asyncShim = engine.eval(denoAsyncFsShim(), "<deno-async-fs>");
    if (!asyncShim.isError) engine.freeValue(asyncShim.value);
}

private string denoAsyncFsShim() pure nothrow @safe
{
    // Same join rules as denoServeAndKvSource -- block comments only.
    return
    "(function(){" ~
    "  /* Promote Deno.errors entries to real Error subclasses so " ~
    "     `e instanceof Deno.errors.NotFound` works. We use the function-" ~
    "     constructor + Object.create(Error.prototype) pattern instead of " ~
    "     `class C extends Error` because QuickJS / JSC have a long-" ~
    "     standing instanceof bug on class-extends-Error (V8 is correct " ~
    "     here, but we want one shim that passes on all three backends). */" ~
    "  function makeErrCls(n) {" ~
    "    function C(m) {" ~
    "      Error.call(this, m);" ~
    "      this.name = n;" ~
    "      this.message = m;" ~
    "      if (Error.captureStackTrace) Error.captureStackTrace(this, C);" ~
    "    }" ~
    "    C.prototype = Object.create(Error.prototype);" ~
    "    C.prototype.constructor = C;" ~
    "    C.prototype.name = n;" ~
    "    Object.defineProperty(C, 'name', { value: n });" ~
    "    return C;" ~
    "  }" ~
    "  var errNames = ['NotFound','PermissionDenied','AlreadyExists'," ~
    "    'InvalidData','TimedOut','ConnectionRefused','ConnectionReset'," ~
    "    'NotConnected','AddrInUse','AddrNotAvailable','BrokenPipe'," ~
    "    'WriteZero','UnexpectedEof','BadResource','Busy','Interrupted'," ~
    "    'WouldBlock','NotSupported','FilesystemLoop','IsADirectory'," ~
    "    'NetworkUnreachable','NotADirectory','NotCapable'];" ~
    "  for (var i = 0; i < errNames.length; i++) {" ~
    "    Deno.errors[errNames[i]] = makeErrCls(errNames[i]);" ~
    "  }" ~
    "  /* Convert TypeError messages that map to a Deno.errors.* class. " ~
    "     The sync impls use engine.throwTypeError for OS-level failures; " ~
    "     this re-wraps them so `e instanceof Deno.errors.NotFound` works. */" ~
    "  function classify(e) {" ~
    "    if (!e || typeof e.message !== 'string') return e;" ~
    "    var m = e.message;" ~
    "    if (m.indexOf('No such file or directory') >= 0) return new Deno.errors.NotFound(m);" ~
    "    if (m.indexOf('Permission denied') >= 0 || m.indexOf('--allow-') >= 0) return new Deno.errors.PermissionDenied(m);" ~
    "    if (m.indexOf('File exists') >= 0 || m.indexOf('already exists') >= 0) return new Deno.errors.AlreadyExists(m);" ~
    "    if (m.indexOf('Connection refused') >= 0) return new Deno.errors.ConnectionRefused(m);" ~
    "    if (m.indexOf('Connection reset') >= 0) return new Deno.errors.ConnectionReset(m);" ~
    "    if (m.indexOf('Address already in use') >= 0) return new Deno.errors.AddrInUse(m);" ~
    "    if (m.indexOf('Operation timed out') >= 0 || m.indexOf('TimedOut') >= 0) return new Deno.errors.TimedOut(m);" ~
    "    return e;" ~
    "  }" ~
    "  /* Wrap every *Sync function so it throws a Deno.errors.* class " ~
    "     instead of a plain TypeError when the underlying OS error matches. */" ~
    "  function wrapSyncClassify(name) {" ~
    "    var orig = Deno[name];" ~
    "    if (typeof orig !== 'function') return;" ~
    "    Deno[name] = function(...args) {" ~
    "      try { return orig.apply(this, args); }" ~
    "      catch (e) { throw classify(e); }" ~
    "    };" ~
    "  }" ~
    "  ['statSync','lstatSync','removeSync','renameSync','copyFileSync'," ~
    "   'readDirSync','readTextFileSync','writeTextFileSync','readFileSync'," ~
    "   'writeFileSync','mkdirSync','realPathSync','truncateSync']" ~
    "    .forEach(wrapSyncClassify);" ~
    "  function wrapAsync(syncName){" ~
    "    return function(...args){" ~
    "      try { return Promise.resolve(Deno[syncName](...args)); }" ~
    "      catch (e) { return Promise.reject(e); }" ~
    "    };" ~
    "  }" ~
    "  Deno.mkdir     = wrapAsync('mkdirSync');" ~
    "  Deno.stat      = wrapAsync('statSync');" ~
    "  Deno.lstat     = wrapAsync('lstatSync');" ~
    "  Deno.remove    = wrapAsync('removeSync');" ~
    "  Deno.rename    = wrapAsync('renameSync');" ~
    "  Deno.copyFile  = wrapAsync('copyFileSync');" ~
    "  Deno.realPath  = wrapAsync('realPathSync');" ~
    "  Deno.truncate  = wrapAsync('truncateSync');" ~
    "  Deno.readTextFile = wrapAsync('readTextFileSync');" ~
    "  Deno.writeTextFile = wrapAsync('writeTextFileSync');" ~
    "  Deno.readFile  = wrapAsync('readFileSync');" ~
    "  Deno.writeFile = wrapAsync('writeFileSync');" ~
    "  /* readDir: returns AsyncIterable so `for await (const e of Deno.readDir(p))` works. */" ~
    "  Deno.readDir = function(path){" ~
    "    return {" ~
    "      [Symbol.asyncIterator]: async function*(){" ~
    "        try {" ~
    "          for (const entry of Deno.readDirSync(path)) yield entry;" ~
    "        } catch (e) { throw e; }" ~
    "      }" ~
    "    };" ~
    "  };" ~
    "})();";
}

private string denoServeAndKvSource() pure nothrow @safe
{
    // NB: all `~` joins => no newlines between chunks at runtime, so the
    // emitted JS must use block comments only — never JS `//` comments.
    return
    "(function() {" ~
    "if (!globalThis.Deno) return;" ~
    /* Deno.serve(opts, handler) — same shape as Bun.serve but matches
       the official Deno API: returns { addr, finished, ref, unref,
       shutdown }. Accepts either Deno.serve(handler) or
       Deno.serve({ port, hostname }, handler) or
       Deno.serve({ port, hostname, handler }). */
    "Deno.serve = function(opts, handler) {" ~
    "  if (typeof opts === 'function') { handler = opts; opts = {}; }" ~
    "  opts = opts || {};" ~
    "  if (!handler && typeof opts.handler === 'function') handler = opts.handler;" ~
    "  if (typeof handler !== 'function')" ~
    "    throw new TypeError('Deno.serve requires a handler function');" ~
    "  var http = require('http');" ~
    "  var port = opts.port == null ? 8000 : +opts.port;" ~
    "  var host = opts.hostname || '0.0.0.0';" ~
    "  var srv = http.createServer(function(req, res) {" ~
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
    "      var info = { remoteAddr: { hostname: req.socket && req.socket.remoteAddress || '', port: req.socket && req.socket.remotePort || 0, transport: 'tcp' } };" ~
    "      Promise.resolve().then(function() { return handler(request, info); }).then(function(resp) {" ~
    "        if (!resp) { res.statusCode = 200; res.end(); return; }" ~
    "        var status = resp.status || 200;" ~
    "        var headers = {};" ~
    "        if (resp.headers && typeof resp.headers.forEach === 'function')" ~
    "          resp.headers.forEach(function(v, k) { headers[k] = v; });" ~
    "        res.writeHead(status, headers);" ~
    /* Body dispatch matches Deno Deploy semantics: Response.body
       can be a ReadableStream (real Deno reads it lazily), and
       arrayBuffer / blob / formData should round-trip without
       string-decoding. Order of checks matters -- stream first
       so we don't accidentally drain a Response via .text(). */
    "        if (resp.body && typeof resp.body.getReader === 'function') {" ~
    "          var reader = resp.body.getReader();" ~
    "          (function pump() {" ~
    "            reader.read().then(function(r) {" ~
    "              if (r.done) { res.end(); return; }" ~
    "              if (r.value) {" ~
    "                if (r.value instanceof Uint8Array) res.write(globalThis.Buffer.from(r.value));" ~
    "                else res.write(String(r.value));" ~
    "              }" ~
    "              pump();" ~
    "            }, function(e) { res.end(String(e)); });" ~
    "          })();" ~
    "        } else if (typeof resp.arrayBuffer === 'function' && resp.headers && resp.headers.get && /^(application\\/octet-stream|image\\/|audio\\/|video\\/|application\\/pdf)/.test(resp.headers.get('content-type') || '')) {" ~
    "          resp.arrayBuffer().then(function(ab) { res.end(globalThis.Buffer.from(ab)); }, function(e) { res.end(String(e)); });" ~
    "        } else if (typeof resp.text === 'function') {" ~
    "          resp.text().then(function(t) { res.end(t); }, function(e) { res.end(String(e)); });" ~
    "        } else if (typeof resp === 'string') {" ~
    "          res.end(resp);" ~
    "        } else {" ~
    "          res.end(JSON.stringify(resp));" ~
    "        }" ~
    "      }).catch(function(err) {" ~
    "        res.statusCode = 500;" ~
    "        var msg = (opts.onError ? opts.onError(err) : String(err && err.stack || err));" ~
    "        if (msg && typeof msg.text === 'function') msg.text().then(function(t) { res.end(t); });" ~
    "        else res.end(String(msg));" ~
    "      });" ~
    "    });" ~
    "  });" ~
    "  srv.listen(port, host);" ~
    /* Read back the actually-bound port from srv.address(). When the
       caller asks for port:0, Node/DunJS picks a random free port --
       the requested 0 isn't the listening port. Real Deno reports
       the real port via server.addr.port; we have to do the same or
       callers fetching `http://127.0.0.1:${server.addr.port}/` hit
       port 0 and never connect. */
    "  var actualPort = port;" ~
    "  try {" ~
    "    var addr = srv.address();" ~
    "    if (addr && typeof addr.port === 'number') actualPort = addr.port;" ~
    "  } catch (e) {}" ~
    "  if (typeof opts.onListen === 'function') {" ~
    "    setTimeout(function() { opts.onListen({ hostname: host, port: actualPort }); }, 0);" ~
    "  }" ~
    "  var finishedResolve;" ~
    "  var finished = new Promise(function(r) { finishedResolve = r; });" ~
    "  srv.on('close', function() { finishedResolve(); });" ~
    "  return {" ~
    "    addr: { hostname: host, port: actualPort, transport: 'tcp' }," ~
    "    finished: finished," ~
    "    ref: function() {}," ~
    "    unref: function() {}," ~
    /* shutdown(): JSC-only GC hint after close — each cycle leaves
       orphaned closure state (the handler, the events map, the
       per-request listener chain) that the JS-side resolved promise
       chain doesn't trigger collection of. Without the hint the
       `deno_deploy_compat` 15-server fixture pushes JSC's
       protected-handle table past the threshold and fetch starts
       timing out at section 7. The `gc()` is exposed by DunJS on
       all backends; on QJS/V8 it's a cheaper no-op-ish call. */
    "    shutdown: function() {" ~
    "      return new Promise(function(r) { srv.close(function() { try { gc(); } catch(_){} r(); }); });" ~
    "    }" ~
    "  };" ~
    "};" ~

    /* Deno.openKv — minimal in-memory key/value store. Real Deno KV is
       persistent + transactional; this shim keeps the data shape so
       scripts can run end-to-end without an external DB. */
    "Deno.openKv = function(path) {" ~
    "  var store = new Map();" ~
    "  function keyToStr(k) { return Array.isArray(k) ? k.map(String).join('\\x00') : String(k); }" ~
    "  return Promise.resolve({" ~
    "    get: function(key) {" ~
    "      var s = keyToStr(key);" ~
    "      return Promise.resolve({" ~
    "        key: key," ~
    "        value: store.has(s) ? store.get(s).value : null," ~
    "        versionstamp: store.has(s) ? store.get(s).versionstamp : null" ~
    "      });" ~
    "    }," ~
    "    set: function(key, value, opts) {" ~
    "      var s = keyToStr(key);" ~
    "      var vs = String(Date.now()) + '_' + Math.random().toString(36).slice(2);" ~
    "      store.set(s, { value: value, versionstamp: vs });" ~
    "      return Promise.resolve({ ok: true, versionstamp: vs });" ~
    "    }," ~
    "    delete: function(key) {" ~
    "      store.delete(keyToStr(key));" ~
    "      return Promise.resolve();" ~
    "    }," ~
    "    list: function(selector) {" ~
    "      var entries = [];" ~
    "      var prefix = selector && selector.prefix ? keyToStr(selector.prefix) : '';" ~
    "      store.forEach(function(v, k) {" ~
    "        if (!prefix || k.indexOf(prefix) === 0) entries.push({ key: k.split('\\x00'), value: v.value, versionstamp: v.versionstamp });" ~
    "      });" ~
    "      var i = 0;" ~
    "      return { [Symbol.asyncIterator]: function() { return {" ~
    "        next: function() {" ~
    "          if (i >= entries.length) return Promise.resolve({ value: undefined, done: true });" ~
    "          return Promise.resolve({ value: entries[i++], done: false });" ~
    "        }" ~
    "      }; } };" ~
    "    }," ~
    "    atomic: function() {" ~
    "      var ops = [];" ~
    "      var api = {" ~
    "        check: function() { return api; }," ~
    "        set: function(k, v) { ops.push(['set', k, v]); return api; }," ~
    "        delete: function(k) { ops.push(['delete', k]); return api; }," ~
    "        commit: function() {" ~
    "          var vs = String(Date.now()) + '_' + Math.random().toString(36).slice(2);" ~
    "          ops.forEach(function(o) {" ~
    "            if (o[0] === 'set') store.set(keyToStr(o[1]), { value: o[2], versionstamp: vs });" ~
    "            else if (o[0] === 'delete') store.delete(keyToStr(o[1]));" ~
    "          });" ~
    "          return Promise.resolve({ ok: true, versionstamp: vs });" ~
    "        }" ~
    "      };" ~
    "      return api;" ~
    "    }," ~
    "    close: function() {}" ~
    "  });" ~
    "};" ~

    /* Deno.cron — schedule a function on a cron expression. Minimal
       parser supporting `* * * * *` (every minute) and `*\/N * * * *`
       (every N minutes). Real Deno cron supports full expressions;
       we cover the common case for scheduled jobs. */
    "Deno.cron = function(name, schedule, handler) {" ~
    "  if (typeof handler !== 'function') throw new TypeError('Deno.cron requires a handler');" ~
    "  var parts = String(schedule).trim().split(/\\s+/);" ~
    "  var minSpec = parts[0] || '*';" ~
    "  var everyMs = 60_000;" ~
    "  var m = /^\\*\\/(\\d+)$/.exec(minSpec);" ~
    "  if (m) everyMs = +m[1] * 60_000;" ~
    "  var id = setInterval(function() {" ~
    "    try { Promise.resolve(handler()).catch(function(){}); }" ~
    "    catch (e) {}" ~
    "  }, everyMs);" ~
    "  return { unref: function() { id.unref && id.unref(); } };" ~
    "};" ~

    /* Deno.Command — modern subprocess API. Wraps node:child_process
       so the surface matches Deno's:
         new Deno.Command(cmd, { args, stdin, stdout, stderr, env, cwd });
         await .output() -> { code, success, stdout, stderr, signal }
         .outputSync() -> same, sync
         .spawn() -> { pid, output, stdin, stdout, stderr, status, kill }
       stdout/stderr default to "piped". This shim covers the common
       `await new Deno.Command("ls").output()` usage; advanced features
       like signal-based termination + streaming pipes are best-effort. */
    "Deno.Command = function Command(cmd, opts) {" ~
    "  opts = opts || {};" ~
    "  this._cmd = cmd; this._opts = opts;" ~
    "  var cp = require('child_process');" ~
    "  var self = this;" ~
    "  this.output = function() {" ~
    "    return new Promise(function(resolve, reject) {" ~
    "      try {" ~
    "        var r = cp.spawnSync(cmd, opts.args || [], {" ~
    "          cwd: opts.cwd, env: opts.env," ~
    "        });" ~
    "        var enc = new TextEncoder();" ~
    "        var stdoutBytes = r.stdout instanceof Uint8Array ? r.stdout : enc.encode(String(r.stdout || ''));" ~
    "        var stderrBytes = r.stderr instanceof Uint8Array ? r.stderr : enc.encode(String(r.stderr || ''));" ~
    "        resolve({" ~
    "          code: r.status == null ? 0 : r.status," ~
    "          success: (r.status == null ? 0 : r.status) === 0," ~
    "          signal: r.signal || null," ~
    "          stdout: stdoutBytes," ~
    "          stderr: stderrBytes" ~
    "        });" ~
    "      } catch (e) { reject(e); }" ~
    "    });" ~
    "  };" ~
    "  this.outputSync = function() {" ~
    "    var r = cp.spawnSync(cmd, opts.args || [], { cwd: opts.cwd, env: opts.env });" ~
    "    var enc = new TextEncoder();" ~
    "    var stdoutBytes = r.stdout instanceof Uint8Array ? r.stdout : enc.encode(String(r.stdout || ''));" ~
    "    var stderrBytes = r.stderr instanceof Uint8Array ? r.stderr : enc.encode(String(r.stderr || ''));" ~
    "    return {" ~
    "      code: r.status == null ? 0 : r.status," ~
    "      success: (r.status == null ? 0 : r.status) === 0," ~
    "      signal: r.signal || null," ~
    "      stdout: stdoutBytes," ~
    "      stderr: stderrBytes" ~
    "    };" ~
    "  };" ~
    "  this.spawn = function() {" ~
    "    var child = cp.spawn(cmd, opts.args || [], { cwd: opts.cwd, env: opts.env });" ~
    "    var stdoutChunks = [], stderrChunks = [];" ~
    "    child.stdout && child.stdout.on('data', function(c) { stdoutChunks.push(c); });" ~
    "    child.stderr && child.stderr.on('data', function(c) { stderrChunks.push(c); });" ~
    "    var statusPromise = new Promise(function(resolve) {" ~
    "      child.on('exit', function(code, signal) {" ~
    "        resolve({ code: code == null ? 0 : code, success: code === 0, signal: signal || null });" ~
    "      });" ~
    "    });" ~
    "    return {" ~
    "      pid: child.pid," ~
    "      stdout: child.stdout," ~
    "      stderr: child.stderr," ~
    "      stdin: child.stdin," ~
    "      status: statusPromise," ~
    "      kill: function(sig) { child.kill(sig); }," ~
    "      output: function() { return statusPromise.then(function(s) {" ~
    "        return Object.assign({" ~
    "          stdout: globalThis.Buffer ? globalThis.Buffer.concat(stdoutChunks) : new Uint8Array()," ~
    "          stderr: globalThis.Buffer ? globalThis.Buffer.concat(stderrChunks) : new Uint8Array()" ~
    "        }, s);" ~
    "      }); }" ~
    "    };" ~
    "  };" ~
    "};" ~

    "})();";
}

private:

string buildTarget() pure @safe nothrow
{
    version (linux)
    {
        version (X86_64) return "x86_64-unknown-linux-gnu";
        else version (AArch64) return "aarch64-unknown-linux-gnu";
        else return "unknown-unknown-linux-gnu";
    }
    else version (OSX)
    {
        version (X86_64) return "x86_64-apple-darwin";
        else version (AArch64) return "aarch64-apple-darwin";
        else return "unknown-apple-darwin";
    }
    else version (Windows)
    {
        return "x86_64-pc-windows-msvc";
    }
    else return "unknown-unknown-unknown";
}

bool noColorEnabled() @trusted nothrow
{
    try
    {
        import std.process : environment;
        return environment.get("NO_COLOR", null) !is null;
    }
    catch (Exception) { return false; }
}

public import dun.security.permissions : checkPerm;

// ── Deno.env ──

JSHandle denoEnvGet(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoEnvGet");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newUndefined();

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    string key = engine.extractString(args[0]);
    try
    {
        import std.process : environment;
        string val = environment.get(key, null);
        if (val is null) return engine.newUndefined();
        return engine.newString(val);
    }
    catch (Exception) { return engine.newUndefined(); }
}

JSHandle denoEnvSet(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoEnvSet");
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("env.set requires (key, value)");

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        environment[engine.extractString(args[0])] = engine.extractString(args[1]);
        return engine.newUndefined();
    }
    catch (Exception e) { return engine.throwTypeError("env.set: " ~ e.msg); }
}

JSHandle denoEnvDelete(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoEnvDelete");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("env.delete requires a key");

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        environment.remove(engine.extractString(args[0]));
        return engine.newUndefined();
    }
    catch (Exception e) { return engine.throwTypeError("env.delete: " ~ e.msg); }
}

JSHandle denoEnvHas(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoEnvHas");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.newBool(false);

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    try
    {
        import std.process : environment;
        return engine.newBool(environment.get(engine.extractString(args[0]), null) !is null);
    }
    catch (Exception) { return engine.newBool(false); }
}

JSHandle denoEnvToObject(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoEnvToObject");
    auto engine = state.engine;

    if (!checkPerm(state, Permission.env))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-env permission");

    auto obj = engine.newObject();
    try
    {
        import std.process : environment;
        foreach (k, v; environment.toAA())
            engine.setProperty(obj, k, engine.newString(v));
    }
    catch (Exception) {}
    return obj;
}

// ── Deno.readTextFileSync / readTextFile ──

JSHandle denoReadTextFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoReadTextFileSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readTextFileSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : readText;
        return engine.newString(readText(path));
    }
    catch (Exception e)
    {
        return engine.throwTypeError("readTextFileSync: " ~ e.msg);
    }
}

JSHandle denoReadTextFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.loop.async : asyncSubmit;

    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoReadTextFile");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readTextFile requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        import std.file : readText;
        return readText(path);
    });

    return ph.promise;
}

// ── Deno.writeTextFileSync / writeTextFile ──

JSHandle denoWriteTextFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoWriteTextFileSync");
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("writeTextFileSync requires (path, data)");

    string path = engine.extractString(args[0]);
    string data = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : write;
        write(path, data);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("writeTextFileSync: " ~ e.msg);
    }
}

JSHandle denoWriteTextFile(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.loop.async : asyncSubmit;

    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoWriteTextFile");
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("writeTextFile requires (path, data)");

    string path = engine.extractString(args[0]);
    string data = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    auto ph = engine.newPromise();
    engine.dupValue(ph.resolve);
    engine.dupValue(ph.reject);

    asyncSubmit(engine, ph.resolve, ph.reject, () @trusted {
        import std.file : write;
        write(path, data);
        return "ok";
    });

    return ph.promise;
}

// ── Deno.statSync ──

JSHandle denoStatSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoStatSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("statSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : exists, isFile, isDir, isSymlink, getSize, timeLastModified;
        if (!exists(path))
            return engine.throwTypeError("No such file or directory: " ~ path);

        bool pathIsFile, pathIsDir, pathIsSym;
        ulong fileSize;
        long mtimeMs;
        try { pathIsFile = isFile(path); } catch (Exception) {}
        try { pathIsDir = isDir(path); } catch (Exception) {}
        try { pathIsSym = isSymlink(path); } catch (Exception) {}
        try { fileSize = getSize(path); } catch (Exception) {}
        try { mtimeMs = timeLastModified(path).toUnixTime!long * 1000L; } catch (Exception) {}

        auto obj = engine.newObject();
        engine.setProperty(obj, "isFile", engine.newBool(pathIsFile));
        engine.setProperty(obj, "isDirectory", engine.newBool(pathIsDir));
        engine.setProperty(obj, "isSymlink", engine.newBool(pathIsSym));
        engine.setProperty(obj, "size", engine.newFloat(cast(double) fileSize));
        engine.setProperty(obj, "mtime", engine.newFloat(cast(double) mtimeMs));
        engine.setProperty(obj, "atime", engine.newNull());
        engine.setProperty(obj, "birthtime", engine.newNull());
        engine.setProperty(obj, "dev", engine.newNull());
        engine.setProperty(obj, "ino", engine.newNull());
        engine.setProperty(obj, "mode", engine.newNull());
        engine.setProperty(obj, "nlink", engine.newNull());
        engine.setProperty(obj, "uid", engine.newNull());
        engine.setProperty(obj, "gid", engine.newNull());
        engine.setProperty(obj, "rdev", engine.newNull());
        engine.setProperty(obj, "blksize", engine.newNull());
        engine.setProperty(obj, "blocks", engine.newNull());
        engine.setProperty(obj, "isBlockDevice", engine.newNull());
        engine.setProperty(obj, "isCharDevice", engine.newNull());
        engine.setProperty(obj, "isFifo", engine.newNull());
        engine.setProperty(obj, "isSocket", engine.newNull());
        return obj;
    }
    catch (Exception e)
    {
        return engine.throwTypeError("statSync: " ~ e.msg);
    }
}

// ── Deno.mkdirSync / Deno.mkdir ──

JSHandle denoMkdirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoMkdirSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("mkdirSync requires a path");

    string path = engine.extractString(args[0]);
    bool recursive = false;

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        if (engine.isBool(rv)) recursive = engine.extractBool(rv);
        engine.freeValue(rv);
    }

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : mkdir, mkdirRecurse;
        if (recursive) mkdirRecurse(path); else mkdir(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("mkdirSync: " ~ e.msg);
    }
}

// ── Deno.removeSync ──

JSHandle denoRemoveSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoRemoveSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("removeSync requires a path");

    string path = engine.extractString(args[0]);
    bool recursive = false;

    if (args.length >= 2 && engine.isObject(args[1]))
    {
        auto rv = engine.getProperty(args[1], "recursive");
        if (engine.isBool(rv)) recursive = engine.extractBool(rv);
        engine.freeValue(rv);
    }

    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : remove, rmdirRecurse, isDir;
        if (recursive && isDir(path))
            rmdirRecurse(path);
        else
            remove(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("removeSync: " ~ e.msg);
    }
}

// ── Deno.renameSync ──

JSHandle denoRenameSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoRenameSync");
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("renameSync requires (oldpath, newpath)");

    string oldpath = engine.extractString(args[0]);
    string newpath = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.read, oldpath))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");
    if (!checkPerm(state, Permission.write, newpath))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : rename;
        rename(oldpath, newpath);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("renameSync: " ~ e.msg);
    }
}

// ── Deno.copyFileSync ──

JSHandle denoCopyFileSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoCopyFileSync");
    auto engine = state.engine;

    if (args.length < 2 || !engine.isString(args[0]) || !engine.isString(args[1]))
        return engine.throwTypeError("copyFileSync requires (src, dest)");

    string src = engine.extractString(args[0]);
    string dest = engine.extractString(args[1]);

    if (!checkPerm(state, Permission.read, src))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");
    if (!checkPerm(state, Permission.write, dest))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : copy;
        copy(src, dest);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("copyFileSync: " ~ e.msg);
    }
}

// ── Deno.readDirSync ──

JSHandle denoReadDirSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoReadDirSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("readDirSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : dirEntries, SpanMode, isFile, isDir, isSymlink;
        import std.path : baseName;
        import std.conv : to;

        auto arr = engine.newArray();
        uint idx = 0;
        foreach (entry; dirEntries(path, SpanMode.shallow))
        {
            auto entryObj = engine.newObject();
            engine.setProperty(entryObj, "name", engine.newString(baseName(entry.name)));
            bool eIsFile, eIsDir, eIsSym;
            try { eIsFile = isFile(entry.name); } catch (Exception) {}
            try { eIsDir = isDir(entry.name); } catch (Exception) {}
            try { eIsSym = isSymlink(entry.name); } catch (Exception) {}
            engine.setProperty(entryObj, "isFile", engine.newBool(eIsFile));
            engine.setProperty(entryObj, "isDirectory", engine.newBool(eIsDir));
            engine.setProperty(entryObj, "isSymlink", engine.newBool(eIsSym));
            engine.setPropertyIndex(arr, idx++, entryObj);
        }
        return arr;
    }
    catch (Exception e)
    {
        return engine.throwTypeError("readDirSync: " ~ e.msg);
    }
}

// ── Deno.realPathSync ──

JSHandle denoRealPathSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoRealPathSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("realPathSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.path : absolutePath;
        import std.file : getcwd;
        return engine.newString(absolutePath(path, getcwd()));
    }
    catch (Exception e)
    {
        return engine.throwTypeError("realPathSync: " ~ e.msg);
    }
}

// ── Deno.truncateSync ──

JSHandle denoTruncateSync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoTruncateSync");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("truncateSync requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.write, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-write permission");

    try
    {
        import std.file : write;
        write(path, "");
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("truncateSync: " ~ e.msg);
    }
}

// ── Deno.cwd / Deno.chdir ──

JSHandle denoCwd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoCwd");
    auto engine = state.engine;

    try
    {
        import std.file : getcwd;
        return engine.newString(getcwd());
    }
    catch (Exception) { return engine.newString("."); }
}

JSHandle denoChdir(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoChdir");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("chdir requires a path");

    string path = engine.extractString(args[0]);
    if (!checkPerm(state, Permission.read, path))
        return engine.throwTypeError("[ERR_PERMISSION_DENIED] Requires --allow-read permission");

    try
    {
        import std.file : chdir;
        chdir(path);
        return engine.newUndefined();
    }
    catch (Exception e)
    {
        return engine.throwTypeError("chdir: " ~ e.msg);
    }
}

// ── Deno.exit ──

JSHandle denoExit(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoExit");
    auto engine = state.engine;

    int code = 0;
    if (args.length >= 1 && engine.isNumber(args[0]))
        code = engine.extractInt(args[0]);

    import core.stdc.stdlib : exit;
    exit(code);
    assert(0);
}

// ── Deno.hostname ──

JSHandle denoHostname(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoHostname");
    auto engine = state.engine;

    try
    {
        version (Posix)
        {
            import core.sys.posix.unistd : gethostname;
            char[256] buf;
            if (gethostname(buf.ptr, buf.length) == 0)
            {
                import std.string : fromStringz;
                return engine.newString(cast(string) fromStringz(buf.ptr));
            }
        }
        version (Windows)
        {
            import std.process : environment;
            auto name = environment.get("COMPUTERNAME", "localhost");
            return engine.newString(name);
        }
        return engine.newString("localhost");
    }
    catch (Exception) { return engine.newString("localhost"); }
}

// ── Deno.permissions.query ──

JSHandle denoPermissionsQuery(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoPermissionsQuery");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isObject(args[0]))
        return engine.throwTypeError("permissions.query requires a descriptor object");

    auto nameVal = engine.getProperty(args[0], "name");
    if (!engine.isString(nameVal))
    {
        engine.freeValue(nameVal);
        return engine.throwTypeError("descriptor.name must be a string");
    }

    string name = engine.extractString(nameVal);
    engine.freeValue(nameVal);
    Permission perm;
    string stateStr;

    if (name == "read") perm = Permission.read;
    else if (name == "write") perm = Permission.write;
    else if (name == "net") perm = Permission.net;
    else if (name == "env") perm = Permission.env;
    else if (name == "run") perm = Permission.run;
    else if (name == "ffi") perm = Permission.ffi;
    else if (name == "hrtime") perm = Permission.hrtime;
    else
    {
        stateStr = "prompt";
        goto makeResult;
    }

    stateStr = checkPerm(state, perm) ? "granted" : "prompt";

makeResult:
    auto ph = engine.newPromise();
    auto resultObj = engine.newObject();
    engine.setProperty(resultObj, "state", engine.newString(stateStr));
    engine.freeValue(engine.callFunction(ph.resolve, engine.newUndefined(), [resultObj]));
    engine.freeValue(ph.resolve);
    engine.freeValue(ph.reject);
    return ph.promise;
}

// ── Deno.inspect ──

JSHandle denoInspect(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in denoInspect");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("undefined");

    auto global = engine.getGlobal();
    auto inspectFn = engine.getProperty(global, "__dun_inspect__");
    engine.freeValue(global);

    if (engine.isFunction(inspectFn))
    {
        auto result = engine.callFunction(inspectFn, engine.newUndefined(), [args[0]]);
        engine.freeValue(inspectFn);
        return result;
    }
    engine.freeValue(inspectFn);

    if (engine.isString(args[0]))
        return engine.newString("\"" ~ engine.extractString(args[0]) ~ "\"");
    if (engine.isNumber(args[0]))
    {
        import std.conv : to;
        return engine.newString(engine.extractFloat(args[0]).to!string);
    }
    if (engine.isBool(args[0]))
        return engine.newString(engine.extractBool(args[0]) ? "true" : "false");
    if (engine.isNull(args[0]))
        return engine.newString("null");
    if (engine.isUndefined(args[0]))
        return engine.newString("undefined");

    return engine.newString("[Object]");
}
