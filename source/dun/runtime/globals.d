module dun.runtime.globals;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.loop.eventloop : EventLoop;
import dun.security.permissions : PermissionRegistry;

struct DunState
{
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}

void installGlobals(IJSEngine engine, DunState* state) @trusted
{
    assert(engine !is null, "Null engine");
    assert(state !is null, "Null state");
    assert(state.engine is engine, "State engine mismatch");

    engine.setContextOpaque(cast(void*) state);

    import dun.runtime.console : installConsole;
    import dun.runtime.timers_api : installTimers;
    import dun.runtime.microtask_api : installMicrotask;
    import dun.runtime.process_api : installProcess;
    import dun.builtins.fs : registerFsModule;
    import dun.builtins.path : registerPathModule;
    import dun.builtins.crypto : registerCryptoModule;
    import dun.builtins.net : registerNetModule;
    import dun.builtins.http : registerHttpModule;
    import dun.builtins.https : registerHttpsModule;
    import dun.builtins.http2 : registerHttp2Module;
    import dun.builtins.buffer : registerBufferModule;
    import dun.builtins.events : registerEventsModule;
    import dun.builtins.url : registerUrlModule;
    import dun.builtins.os : registerOsModule;
    import dun.builtins.zlib : registerZlibModule;
    import dun.builtins.dns : registerDnsModule;
    import dun.builtins.fetch : registerFetchGlobal;
    import dun.builtins.child_process : registerChildProcessModule;
    import dun.builtins.stream : registerStreamModule;
    import dun.builtins.ws : registerWsModule;
    import dun.builtins.sqlite : registerSqliteModule;
    import dun.builtins.util : registerUtilModule;
    import dun.builtins.assert_ : registerAssertModule;
    import dun.builtins.node_test : registerNodeTestModule;
    import dun.builtins.querystring : registerQuerystringModule;
    import dun.builtins.string_decoder : registerStringDecoderModule;
    import dun.builtins.timers_promises : registerTimersPromisesModule;
    import dun.builtins.fs_promises : registerFsPromisesModule;
    import dun.builtins.http3 : registerHttp3Module;
    import dun.builtins.vm : registerVmModule;
    import dun.builtins.async_hooks : registerAsyncHooksModule;
    import dun.builtins.cluster : registerClusterModule;
    import dun.builtins.worker_threads : registerWorkerThreadsModule;
    import dun.builtins.readline : registerReadlineModule;
    import dun.builtins.tty : registerTtyModule;
    import dun.builtins.dgram : registerDgramModule;
    import dun.builtins.perf_hooks : registerPerfHooksModule;
    import dun.builtins.wasi : registerWasiModule;
    import dun.builtins.v8 : registerV8Module;
    import dun.builtins.yaml : registerYamlModule;
    import dun.modules.require : installRequire;

    version (Posix)
        import dun.builtins.tls : registerTlsModule;

    installConsole(engine);
    installTimers(engine);
    installMicrotask(engine);
    installProcess(engine);
    registerEventsModule(engine);
    registerBufferModule(engine);
    registerFsModule(engine);
    registerPathModule(engine);
    registerCryptoModule(engine);
    registerNetModule(engine);
    registerHttpModule(engine);
    registerHttpsModule(engine);
    registerHttp2Module(engine);
    registerUrlModule(engine);
    registerOsModule(engine);
    registerZlibModule(engine);
    registerDnsModule(engine);
    registerChildProcessModule(engine);
    registerStreamModule(engine);
    registerWsModule(engine);
    registerSqliteModule(engine);
    registerYamlModule(engine);
    registerUtilModule(engine);
    registerAssertModule(engine);
    registerNodeTestModule(engine);
    registerQuerystringModule(engine);
    registerStringDecoderModule(engine);
    registerTimersPromisesModule(engine);
    registerFsPromisesModule(engine);
    registerHttp3Module(engine);
    registerVmModule(engine);
    registerAsyncHooksModule(engine);
    registerClusterModule(engine);
    registerWorkerThreadsModule(engine);
    registerReadlineModule(engine);
    registerTtyModule(engine);
    registerDgramModule(engine);
    registerWasiModule(engine);
    registerV8Module(engine);

    version (Posix)
        registerTlsModule(engine);

    registerStubModules(engine);

    version (Posix)
        registerFetchGlobal(engine);

    import dun.runtime.web_compat : installWebCompat;
    installWebCompat(engine);

    import dun.runtime.web_apis : installWebAPIs;
    installWebAPIs(engine);

    // Tiny React shim so JSX-emitted React.createElement calls work
    // without an explicit `import React from 'react'`. Match Bun's
    // implicit-React behavior; if the user does `import React`, the
    // import overrides this. Returns a plain { type, props, children }
    // tree — sufficient for serialization-only consumers (e.g. server-
    // side render to HTML / JSON). Real DOM rendering still needs a
    // real React build.
    auto reactRes = engine.eval(
        "(function() {" ~
        "if (typeof globalThis.React !== 'undefined') return;" ~
        "globalThis.React = {" ~
        "  Fragment: Symbol('React.Fragment')," ~
        "  createElement: function(type, props /*, ...children */) {" ~
        "    var children = [];" ~
        "    for (var i = 2; i < arguments.length; i++) children.push(arguments[i]);" ~
        "    var node = { type: type, props: props || {}, children: children };" ~
        "    Object.defineProperty(node, '$$typeof', { value: Symbol.for('react.element') });" ~
        "    return node;" ~
        "  }" ~
        "};" ~
        "})();", "<react-shim>");
    if (!reactRes.isError) engine.freeValue(reactRes.value);

    // WebAssembly: JSC and V8 ship the constructors but their async
    // `instantiate` / `compile` / streaming variants schedule onto the
    // engine's internal task queue, which our event loop doesn't drain.
    // Replace them with microtask-resolved sync wrappers so callbacks
    // actually fire. QuickJS lacks WebAssembly entirely; the polyfill
    // gracefully no-ops there.
    auto wasmRes = engine.eval(
        "(function(){"
        ~ "if (typeof WebAssembly === 'undefined') return;"
        ~ "const M = WebAssembly.Module, I = WebAssembly.Instance;"
        ~ "WebAssembly.compile = function(bytes) {"
        ~   "return Promise.resolve().then(() => new M(bytes));"
        ~ "};"
        ~ "WebAssembly.instantiate = function(bytesOrModule, importObject) {"
        ~   "return Promise.resolve().then(() => {"
        ~     "if (bytesOrModule instanceof M) {"
        ~       "return new I(bytesOrModule, importObject);"
        ~     "}"
        ~     "const mod = new M(bytesOrModule);"
        ~     "return { module: mod, instance: new I(mod, importObject) };"
        ~   "});"
        ~ "};"
        ~ "if (typeof Response !== 'undefined') {"
        ~   "WebAssembly.compileStreaming = function(source) {"
        ~     "return Promise.resolve(source).then(r => r.arrayBuffer()).then(b => new M(b));"
        ~   "};"
        ~   "WebAssembly.instantiateStreaming = function(source, importObject) {"
        ~     "return Promise.resolve(source).then(r => r.arrayBuffer()).then(b => {"
        ~       "const mod = new M(b);"
        ~       "return { module: mod, instance: new I(mod, importObject) };"
        ~     "});"
        ~   "};"
        ~ "}"
        ~ "})();",
        "<wasm-polyfill>");
    if (!wasmRes.isError) engine.freeValue(wasmRes.value);

    // Unicode property escapes polyfill: V8's prebuilt monolith ships
    // without ICU data (`v8_enable_i18n_support=false`), so any regex
    // using `\p{Property}` throws at parse time. Detect that and wrap
    // the RegExp constructor so common property escapes get expanded
    // to pre-baked character classes. JSC and QuickJS handle these
    // natively, so the polyfill no-ops there.
    auto upRes = engine.eval(unicodePropPolyfillSource(), "<unicode-prop-polyfill>");
    if (!upRes.isError) engine.freeValue(upRes.value);

    // perf_hooks must come after installWebAPIs so global performance object exists
    registerPerfHooksModule(engine);

    import dun.runtime.intl : installIntl;
    installIntl(engine);

    import dun.runtime.deno_compat : installDenoCompat;
    installDenoCompat(engine);

    import dun.runtime.ffi : installFfiCompat;
    installFfiCompat(engine, state);

    import dun.runtime.bun_compat : installBunCompat;
    installBunCompat(engine);

    installRequire(engine);

    // Dynamic `import(...)` shim. The source pipeline rewrites
    // `import(specifier)` -> `__dunImport__(specifier)` so JSC and V8
    // (which don't wire HostImportModuleDynamicallyCallback) can
    // service `await import("fs")`. Has to come after installRequire
    // so the shim can resolve `require`.
    {
        import dun.ts.dynamic_import : dunImportShimSource;
        auto res = engine.eval(dunImportShimSource(), "<dun-import-shim>");
        if (!res.isError) engine.freeValue(res.value);
    }

    import dun.runtime.rejection_tracker : installRejectionTracker;
    installRejectionTracker(engine, state);

    auto global = engine.getGlobal();
    engine.setProperty(global, "gc", engine.newFunction(&jsGlobalGC, "gc", 0));

    // High-resolution performance.now() across all backends. JSC and
    // V8 ship a native one that rounds to integer milliseconds; ours
    // uses MonoTime for sub-millisecond precision so benchmarks that
    // measure a few-hundred-iteration loop produce meaningful timings
    // (instead of always-zero diffs).
    {
        import dun.runtime.process_api : jsPerformanceNow;
        auto perfObj = engine.getProperty(global, "performance");
        if (engine.isObject(perfObj))
        {
            engine.setProperty(perfObj, "now",
                engine.newFunction(&jsPerformanceNow, "now", 0));
        }
        engine.freeValue(perfObj);
    }
    engine.freeValue(global);

    import dun.runtime.worker_api : installWorkerAPI;
    installWorkerAPI(engine, state);
}

private void registerStubModules(IJSEngine engine) @trusted
{
    auto result = engine.eval(`(function() {
  var punycode = {
    encode: function(input) {
      var output = [];
      for (var i = 0; i < input.length; i++) {
        var c = input.charCodeAt(i);
        if (c < 0x80) output.push(String.fromCharCode(c));
      }
      return output.join('');
    },
    decode: function(s) { return s; },
    toASCII: function(domain) {
      return domain.split('.').map(function(label) {
        var hasNonASCII = false;
        for (var i = 0; i < label.length; i++) {
          if (label.charCodeAt(i) >= 0x80) { hasNonASCII = true; break; }
        }
        return hasNonASCII ? 'xn--' + punycode.encode(label) : label;
      }).join('.');
    },
    toUnicode: function(domain) {
      return domain.split('.').map(function(label) {
        if (label.indexOf('xn--') === 0) return punycode.decode(label.slice(4));
        return label;
      }).join('.');
    },
    ucs2: {
      decode: function(s) { var r=[]; for(var i=0;i<s.length;i++) r.push(s.charCodeAt(i)); return r; },
      encode: function(a) { var r=''; for(var i=0;i<a.length;i++) r+=String.fromCharCode(a[i]); return r; }
    },
    version: '2.3.1'
  };
  /* diagnostics_channel — lazy. The compact (~30 line) install-time
     version we tried in v1.1.10 tipped JSC deno_deploy_compat over
     the heap budget threshold every sweep (3/3 fail). Placeholder
     here returns no-ops; first call to a non-no-op method triggers
     the real impl via lazy eval inside the function. This way the
     install-time eval pressure stays at ~1 KB instead of ~5 KB on JSC. */
  var diagnostics_channel = {
    _real: null,
    _load: function() {
      if (this._real) return this._real;
      this._real = (new Function(
        "var ch=Object.create(null);" +
        "function C(n){this.name=n;this._ls=[];}" +
        "Object.defineProperty(C.prototype,'hasSubscribers'," +
        "  {get:function(){return this._ls.length>0;}});" +
        "C.prototype.subscribe=function(l){" +
        "  if(typeof l!=='function')throw new TypeError('listener must be a function');" +
        "  this._ls.push(l);};" +
        "C.prototype.unsubscribe=function(l){" +
        "  var i=this._ls.indexOf(l);if(i<0)return false;" +
        "  this._ls.splice(i,1);return true;};" +
        "C.prototype.publish=function(m){" +
        "  var ls=this._ls.slice();" +
        "  for(var i=0;i<ls.length;i++){try{ls[i](m,this.name);}catch(e){}}};" +
        "function k(n){if(ch[n])return ch[n];return ch[n]=new C(n);}" +
        "return {channel:k,Channel:C," +
        "  hasSubscribers:function(n){var c=ch[n];return c?c.hasSubscribers:false;}," +
        "  subscribe:function(n,l){k(n).subscribe(l);}," +
        "  unsubscribe:function(n,l){var c=ch[n];return c?c.unsubscribe(l):false;}};"
      ))();
      return this._real;
    },
    channel: function(n) { return this._load().channel(n); },
    hasSubscribers: function(n) { return this._load().hasSubscribers(n); },
    subscribe: function(n, l) { return this._load().subscribe(n, l); },
    unsubscribe: function(n, l) { return this._load().unsubscribe(n, l); },
    get Channel() { return this._load().Channel; },
    /* tracingChannel: Node v15+. pino tools.js calls
       diagChan.tracingChannel("pino_asJson") at module-load AND
       invokes traceSync/tracePromise at every log call with the
       receiver-bound state. Without the stub, require("pino")
       crashes immediately; with a broken stub (e.g. forgetting
       to thread thisArg through to fn.apply), the first log call
       fails with "cannot read property of null" because pino
       _asJson reads this[stringifySym]. Node API contracts:
         traceSync(fn, ctx, thisArg, ...args)
           -> fn.apply(thisArg, args)
         tracePromise(fn, ctx, thisArg, ...args)
           -> same, wrapped in Promise.resolve().then
         traceCallback(fn, position, ctx, thisArg, ...args)
           -> injects callback at position
       No subscribers attached -> just invoke fn; events do
       not fire. */
    tracingChannel: function(name) {
      var dc = this;
      var prefix = typeof name === 'string' ? name : 'tc';
      return {
        start:           dc.channel(prefix + ':start'),
        end:             dc.channel(prefix + ':end'),
        asyncStart:      dc.channel(prefix + ':asyncStart'),
        asyncEnd:        dc.channel(prefix + ':asyncEnd'),
        error:           dc.channel(prefix + ':error'),
        subscribe:   function(handlers) { /* stub: no events fire */ },
        unsubscribe: function(handlers) { return true; },
        traceSync: function(fn, ctx, thisArg) {
          var args = Array.prototype.slice.call(arguments, 3);
          if (typeof fn === 'function') return fn.apply(thisArg, args);
        },
        tracePromise: function(fn, ctx, thisArg) {
          var args = Array.prototype.slice.call(arguments, 3);
          if (typeof fn !== 'function') return Promise.resolve();
          return Promise.resolve().then(function() { return fn.apply(thisArg, args); });
        },
        traceCallback: function(fn, position, ctx, thisArg) {
          var args = Array.prototype.slice.call(arguments, 4);
          if (typeof fn === 'function') return fn.apply(thisArg, args);
        }
      };
    }
  };
  var domain = {
    create: function() {
      return { run: function(fn) { fn(); }, on: function(){}, add: function(){},
        remove: function(){}, bind: function(fn) { return fn; },
        intercept: function(fn) { return fn; }, enter: function(){}, exit: function(){} };
    },
    active: null
  };
  var constants = {
    fs: {
      F_OK: 0, R_OK: 4, W_OK: 2, X_OK: 1,
      COPYFILE_EXCL: 1, COPYFILE_FICLONE: 2, COPYFILE_FICLONE_FORCE: 4,
      O_RDONLY: 0, O_WRONLY: 1, O_RDWR: 2, O_CREAT: 64, O_EXCL: 128,
      O_TRUNC: 512, O_APPEND: 1024, O_SYNC: 1052672,
      S_IFMT: 61440, S_IFREG: 32768, S_IFDIR: 16384, S_IFLNK: 40960,
      S_IFBLK: 24576, S_IFCHR: 8192, S_IFIFO: 4096, S_IFSOCK: 49152
    },
    crypto: {
      SSL_OP_ALL: 0x80000BFF,
      SSL_OP_NO_SSLv2: 0x01000000,
      SSL_OP_NO_SSLv3: 0x02000000,
      SSL_OP_NO_TLSv1: 0x04000000,
      SSL_OP_NO_TLSv1_1: 0x10000000,
      SSL_OP_NO_TLSv1_2: 0x08000000,
      POINT_CONVERSION_COMPRESSED: 2,
      POINT_CONVERSION_UNCOMPRESSED: 4,
      defaultCoreCipherList: 'TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256',
      RSA_PKCS1_PADDING: 1,
      RSA_SSLV23_PADDING: 2,
      RSA_NO_PADDING: 3,
      RSA_PKCS1_OAEP_PADDING: 4,
      RSA_X931_PADDING: 5,
      RSA_PKCS1_PSS_PADDING: 6
    },
    os: {
      UV_UDP_REUSEADDR: 4,
      SIGTERM: 15, SIGINT: 2, SIGHUP: 1, SIGKILL: 9,
      SIGPIPE: 13, SIGUSR1: 10, SIGUSR2: 12
    }
  };
  try {
    var fsMod = globalThis.__dun_cjs_fs__;
    if (fsMod && fsMod.constants) {
      var fsConst = fsMod.constants;
      for (var k in fsConst) constants.fs[k] = fsConst[k];
    }
  } catch(e) {}

  var moduleMod = {
    builtinModules: ['fs','path','crypto','net','http','https','os','buffer',
      'events','url','stream','util','assert','querystring','string_decoder',
      'child_process','zlib','dns','readline','vm','tls','dgram','perf_hooks',
      'punycode','domain','diagnostics_channel','cluster','async_hooks',
      'worker_threads','tty','constants','module','timers','process','console'],
    Module: function() {},
    createRequire: function() {
      // Use globalThis.require, not bare require, so the common
      // pattern (const require = createRequire(import.meta.url))
      // doesn't TDZ-fail on the call site's own const require binding.
      var r = globalThis.require;
      return (typeof r === 'function') ? r : function(){};
    },
    isBuiltin: function(name) { return moduleMod.builtinModules.indexOf(name) !== -1; },
    _cache: {},
    _resolveFilename: function(request) { return request; }
  };

  var timersMod = {
    setTimeout: typeof setTimeout !== 'undefined' ? setTimeout : function(){},
    setInterval: typeof setInterval !== 'undefined' ? setInterval : function(){},
    clearTimeout: typeof clearTimeout !== 'undefined' ? clearTimeout : function(){},
    clearInterval: typeof clearInterval !== 'undefined' ? clearInterval : function(){},
    setImmediate: typeof setImmediate !== 'undefined' ? setImmediate : function(fn){fn();},
    clearImmediate: typeof clearImmediate !== 'undefined' ? clearImmediate : function(){}
  };

  var processMod = typeof process !== 'undefined' ? process : {};
  var consoleMod = typeof console !== 'undefined' ? console : {};

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_punycode__ = punycode;
    globalThis.__dun_cjs_diagnostics_channel__ = diagnostics_channel;
    globalThis.__dun_cjs_domain__ = domain;
    globalThis.__dun_cjs_constants__ = constants;
    globalThis.__dun_cjs_module__ = moduleMod;
    globalThis.__dun_cjs_timers__ = timersMod;
    globalThis.__dun_cjs_process__ = processMod;
    globalThis.__dun_cjs_console__ = consoleMod;
  }
})()`, "<stubs>");
    engine.freeValue(result.value);

    version (EngineQuickJS)
        registerStubModulesQuickJS(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerStubModulesQuickJS(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerStubModulesQuickJS");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null ctx in registerStubModulesQuickJS");

        // Each stub module is exposed via globalThis.__dun_cjs_<name>__.
        // Register a matching `dun:<name>` C module so ESM-style
        // `import x from 'node:<name>'` works as well as `require()`.
        static immutable string[2][] stubs = [
            ["punycode",            "__dun_cjs_punycode__"],
            ["diagnostics_channel", "__dun_cjs_diagnostics_channel__"],
            ["domain",              "__dun_cjs_domain__"],
            ["constants",           "__dun_cjs_constants__"],
            ["module",              "__dun_cjs_module__"],
            ["timers",              "__dun_cjs_timers__"],
            ["process",             "__dun_cjs_process__"],
            ["console",             "__dun_cjs_console__"],
        ];
        foreach (s; stubs)
            registerStubModuleQuickJS(ctx, s[0], s[1]);
    }

    private void registerStubModuleQuickJS(JSContext* ctx, string name, string globalKey) @trusted
    {
        import std.string : toStringz;
        assert(ctx !is null, "Null ctx in registerStubModuleQuickJS");

        auto fullName = "dun:" ~ name;
        auto m = JS_NewCModule(ctx, fullName.toStringz, &stubModuleInit);
        if (m is null) return;
        // Key the per-module global-key lookup on the JSModuleDef pointer,
        // since QuickJS doesn't expose JS_GetModuleName in our bindings.
        g_stubKeys[cast(size_t) m] = globalKey;
        JS_AddModuleExport(ctx, m, "default");
        // Expose named exports for keys we know exist on the stub object
        // so `import { createRequire } from 'node:module'` resolves. We
        // pre-declare a fixed set per-module rather than introspecting at
        // registration time (the global isn't installed yet).
        foreach (export_; namedExportsFor(name))
            JS_AddModuleExport(ctx, m, export_.ptr);
    }

    private string[] namedExportsFor(string moduleName) @safe pure nothrow
    {
        switch (moduleName)
        {
            case "module":
                return ["createRequire", "Module", "isBuiltin",
                        "builtinModules", "_cache", "_resolveFilename"];
            case "process":
                return ["env", "argv", "platform", "arch", "version",
                        "versions", "pid", "cwd", "exit", "stdout",
                        "stderr", "stdin", "nextTick"];
            case "console":
                return ["log", "error", "warn", "info", "debug",
                        "trace", "dir", "table", "time", "timeEnd"];
            case "timers":
                return ["setTimeout", "setInterval", "clearTimeout",
                        "clearInterval", "setImmediate", "clearImmediate"];
            case "constants":
                return ["fs", "crypto", "os"];
            case "punycode":
                return ["encode", "decode", "toASCII", "toUnicode"];
            case "domain":
                return ["create", "active"];
            case "diagnostics_channel":
                return ["channel", "subscribe", "unsubscribe", "hasSubscribers"];
            default:
                return [];
        }
    }

    private __gshared string[size_t] g_stubKeys;

    private extern (C) int stubModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in stubModuleInit");
        assert(m !is null, "Null m in stubModuleInit");
        import std.string : toStringz;
        try
        {
            auto p = cast(size_t) m in g_stubKeys;
            if (p is null) return -1;
            auto global = JS_GetGlobalObject(ctx);
            auto modVal = JS_GetPropertyStr(ctx, global, (*p).toStringz);
            JS_FreeValue(ctx, global);
            // Named exports: read each property off the stub object and
            // expose it. Default export is the whole object.
            JS_SetModuleExport(ctx, m, "default", JS_DupValue(ctx, modVal));
            // Find the original name by walking g_stubKeys' parallel data.
            // Since the lookup table is keyed by JSModuleDef* and the
            // moduleName isn't stored, derive the named-export list from
            // the global key prefix.
            string globalKey = *p;
            string moduleName = "";
            // globalKey looks like "__dun_cjs_<name>__".
            if (globalKey.length > 12 && globalKey[0 .. 10] == "__dun_cjs_"
                && globalKey[$ - 2 .. $] == "__")
                moduleName = globalKey[10 .. $ - 2];
            foreach (name; namedExportsFor(moduleName))
            {
                auto val = JS_GetPropertyStr(ctx, modVal, name.ptr);
                JS_SetModuleExport(ctx, m, name.ptr, val);
            }
            JS_FreeValue(ctx, modVal);
        }
        catch (Exception) { return -1; }
        return 0;
    }
}

// Compact map from Unicode property escape names to pre-computed
// character class strings. Covers the common categories (Letter,
// Number, Punctuation, Symbol, Mark, Separator, ASCII) that npm
// packages reach for. Less common scripts/blocks fall back to a
// "match nothing" empty class so the regex still parses.
//
// Letter ranges follow Unicode 16 General_Category=Letter (truncated
// to BMP + a few important supplementary blocks; suffices for the
// `safe_features.js` acceptance check and for npm packages that just
// need `\p{ID_Start}` / `\p{L}` to compile).
private string unicodePropPolyfillSource() pure @safe nothrow
{
    return `(function(){
  'use strict';
  // Two probes:
  //   1. \p{L} with /u — engines without ICU (V8's prebuilt monolith)
  //      throw at parse time.
  //   2. /v set-difference [\p{L}--\p{ASCII}] — QJS lacks /v entirely;
  //      V8 14.9's CharacterClass+\p{} interaction returns wrong
  //      results for set ops. JSC handles both natively.
  //
  // Polyfill installs only if at least one probe fails. The probes
  // double as feature tests for RegExp.prototype.unicodeSets and
  // the /v set operators.
  var BS = String.fromCharCode(92);
  var nativePropOk = false;
  var nativeVSetOk = false;
  try { new RegExp(BS + 'p{L}', 'u'); nativePropOk = true; } catch (e) {}
  try {
    var probe = new RegExp('[' + BS + 'p{L}--' + BS + 'p{ASCII}]', 'v');
    nativeVSetOk = probe.test('é') && !probe.test('a');
  } catch (e) {}
  if (nativePropOk && nativeVSetOk) return;

  // Pre-baked character classes for common Unicode properties.
  // Each entry maps a property escape to the body of an equivalent
  // character class. ranges are conservative: slightly broader than
  // the strict spec but never narrower for the common tests.
  var T = {
    'L':           'A-Za-z\\u00AA\\u00B5\\u00BA\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02C1\\u02C6-\\u02D1\\u02E0-\\u02E4\\u02EC\\u02EE\\u0370-\\u0374\\u0376-\\u0377\\u037A-\\u037D\\u0386\\u0388-\\u03FF\\u0400-\\u0481\\u048A-\\u052F\\u0531-\\u0556\\u0561-\\u0587\\u05D0-\\u05F2\\u0620-\\u064A\\u066E-\\u066F\\u0671-\\u06D3\\u06D5\\u06E5-\\u06E6\\u06EE-\\u06EF\\u06FA-\\u06FC\\u06FF\\u0710\\u0712-\\u072F\\u074D-\\u07A5\\u07B1\\u07CA-\\u07EA\\u0904-\\u0939\\u093D\\u0950\\u0958-\\u0961\\u0971-\\u097F\\u0985-\\u09B9\\u09BD\\u09CE\\u09DC-\\u09DD\\u09DF-\\u09E1\\u0A05-\\u0A39\\u0A59-\\u0A5E\\u0A72-\\u0A74\\u0A85-\\u0AB9\\u0ABD\\u0AD0\\u0AE0-\\u0AE1\\u0B05-\\u0B39\\u0B3D\\u0B5C-\\u0B5D\\u0B5F-\\u0B61\\u0B71\\u0B83-\\u0BB9\\u0BD0\\u0C05-\\u0C39\\u0C3D\\u0C58-\\u0C61\\u0C85-\\u0CB9\\u0CBD\\u0CDE-\\u0CE1\\u0D05-\\u0D39\\u0D3D\\u0D60-\\u0D61\\u0D7A-\\u0D7F\\u0D85-\\u0DC6\\u0E01-\\u0E30\\u0E32-\\u0E33\\u0E40-\\u0E46\\u0E81-\\u0EB0\\u0EB2-\\u0EB3\\u0EBD\\u0EC0-\\u0EC4\\u0EC6\\u0EDC-\\u0EDD\\u0F00\\u0F40-\\u0F6C\\u0F88-\\u0F8B\\u1000-\\u102A\\u103F\\u1050-\\u1055\\u105A-\\u105D\\u1061\\u1065-\\u1066\\u106E-\\u1070\\u1075-\\u1081\\u108E\\u10A0-\\u10C5\\u10D0-\\u10FA\\u10FC\\u1100-\\u1248\\u1250-\\u1288\\u1290-\\u12B0\\u12B8-\\u12C0\\u12C2-\\u12D6\\u12D8-\\u1310\\u1312-\\u1316\\u1318-\\u135A\\u1380-\\u138F\\u13A0-\\u13F4\\u1401-\\u166C\\u166F-\\u167F\\u1681-\\u169A\\u16A0-\\u16EA\\u1700-\\u170C\\u170E-\\u1711\\u1720-\\u1731\\u1740-\\u1751\\u1760-\\u1770\\u1780-\\u17B3\\u17D7\\u17DC\\u1820-\\u1877\\u1880-\\u18A8\\u18AA\\u1900-\\u191C\\u1950-\\u196D\\u1970-\\u1974\\u1980-\\u19AB\\u19C1-\\u19C7\\u1A00-\\u1A16\\u1B05-\\u1B33\\u1B45-\\u1B4B\\u1B83-\\u1BA0\\u1BAE-\\u1BAF\\u1C00-\\u1C23\\u1C4D-\\u1C4F\\u1C5A-\\u1C7D\\u1CE9-\\u1CEC\\u1CEE-\\u1CF1\\u1D00-\\u1DBF\\u1E00-\\u1F15\\u1F18-\\u1F1D\\u1F20-\\u1F45\\u1F48-\\u1F4D\\u1F50-\\u1F57\\u1F59\\u1F5B\\u1F5D\\u1F5F-\\u1F7D\\u1F80-\\u1FB4\\u1FB6-\\u1FBC\\u1FBE\\u1FC2-\\u1FC4\\u1FC6-\\u1FCC\\u1FD0-\\u1FD3\\u1FD6-\\u1FDB\\u1FE0-\\u1FEC\\u1FF2-\\u1FF4\\u1FF6-\\u1FFC\\u2071\\u207F\\u2090-\\u209C\\u2102\\u2107\\u210A-\\u2113\\u2115\\u2119-\\u211D\\u2124\\u2126\\u2128\\u212A-\\u212D\\u212F-\\u2139\\u213C-\\u213F\\u2145-\\u2149\\u214E\\u2183-\\u2184\\u2C00-\\u2C2E\\u2C30-\\u2C5E\\u2C60-\\u2CE4\\u2CEB-\\u2CEE\\u2D00-\\u2D25\\u2D30-\\u2D6F\\u2D80-\\u2DDE\\u2E2F\\u3005-\\u3006\\u3031-\\u3035\\u303B-\\u303C\\u3041-\\u3096\\u309D-\\u309F\\u30A1-\\u30FA\\u30FC-\\u30FF\\u3105-\\u312D\\u3131-\\u318E\\u31A0-\\u31BA\\u31F0-\\u31FF\\u3400-\\u4DB5\\u4E00-\\u9FCC\\uA000-\\uA48C\\uA4D0-\\uA4FD\\uA500-\\uA60C\\uA610-\\uA61F\\uA62A-\\uA62B\\uA640-\\uA66E\\uA67F-\\uA697\\uA6A0-\\uA6E5\\uA717-\\uA71F\\uA722-\\uA788\\uA78B-\\uA78E\\uA790-\\uA793\\uA7A0-\\uA7AA\\uA7F8-\\uA801\\uA803-\\uA805\\uA807-\\uA80A\\uA80C-\\uA822\\uA840-\\uA873\\uA882-\\uA8B3\\uA8F2-\\uA8F7\\uA8FB\\uA90A-\\uA925\\uA930-\\uA946\\uA960-\\uA97C\\uA984-\\uA9B2\\uAA00-\\uAA28\\uAA40-\\uAA42\\uAA44-\\uAA4B\\uAA60-\\uAA76\\uAA7A\\uAA80-\\uAAAF\\uAAB1\\uAAB5-\\uAAB6\\uAAB9-\\uAABD\\uAAC0\\uAAC2\\uAADB-\\uAADD\\uABC0-\\uABE2\\uAC00-\\uD7A3\\uD7B0-\\uD7C6\\uD7CB-\\uD7FB\\uF900-\\uFA6D\\uFA70-\\uFAD9\\uFB00-\\uFB06\\uFB13-\\uFB17\\uFB1D\\uFB1F-\\uFB28\\uFB2A-\\uFB36\\uFB38-\\uFB3C\\uFB3E\\uFB40-\\uFB41\\uFB43-\\uFB44\\uFB46-\\uFBB1\\uFBD3-\\uFD3D\\uFD50-\\uFD8F\\uFD92-\\uFDC7\\uFDF0-\\uFDFB\\uFE70-\\uFE74\\uFE76-\\uFEFC\\uFF21-\\uFF3A\\uFF41-\\uFF5A\\uFF66-\\uFFBE\\uFFC2-\\uFFC7\\uFFCA-\\uFFCF\\uFFD2-\\uFFD7\\uFFDA-\\uFFDC',
    'N':           '0-9\\u00B2-\\u00B3\\u00B9\\u00BC-\\u00BE\\u0660-\\u0669\\u06F0-\\u06F9\\u07C0-\\u07C9\\u0966-\\u096F\\u09E6-\\u09EF\\u0A66-\\u0A6F\\u0AE6-\\u0AEF\\u0B66-\\u0B6F\\u0BE6-\\u0BF2\\u0C66-\\u0C6F\\u0CE6-\\u0CEF\\u0D66-\\u0D75\\u0E50-\\u0E59\\u0ED0-\\u0ED9\\u0F20-\\u0F33\\u1040-\\u1049\\u1090-\\u1099\\u17E0-\\u17E9\\u1810-\\u1819\\u1946-\\u194F\\u19D0-\\u19DA\\u1A80-\\u1A99\\u1B50-\\u1B59\\u1BB0-\\u1BB9\\u1C40-\\u1C49\\u1C50-\\u1C59\\u2070\\u2074-\\u2079\\u2080-\\u2089\\u2150-\\u2189\\u2460-\\u24FF\\u2776-\\u2793\\u3007\\u3021-\\u3029\\u3038-\\u303A\\u3192-\\u3195\\u3220-\\u3229\\u3248-\\u324F\\u3251-\\u325F\\u3280-\\u3289\\u32B1-\\u32BF\\uA620-\\uA629\\uA8D0-\\uA8D9\\uA900-\\uA909\\uA9D0-\\uA9D9\\uAA50-\\uAA59\\uABF0-\\uABF9\\uFF10-\\uFF19',
    'P':           '!-#%-*,-/:-;?-@\\[-\\]_{-}\\u00A1\\u00A7\\u00AB\\u00B6-\\u00B7\\u00BB\\u00BF\\u037E\\u0387\\u055A-\\u055F\\u0589-\\u058A\\u05BE\\u05C0\\u05C3\\u05C6\\u05F3-\\u05F4\\u0609-\\u060A\\u060C-\\u060D\\u061B\\u061E-\\u061F\\u066A-\\u066D\\u06D4\\u0700-\\u070D\\u07F7-\\u07F9\\u0830-\\u083E\\u085E\\u0964-\\u0965\\u0970\\u0AF0\\u0DF4\\u0E4F\\u0E5A-\\u0E5B\\u0F04-\\u0F12\\u0F14\\u0F3A-\\u0F3D\\u0F85\\u0FD0-\\u0FD4\\u0FD9-\\u0FDA\\u104A-\\u104F\\u10FB\\u1360-\\u1368\\u1400\\u166D-\\u166E\\u169B-\\u169C\\u16EB-\\u16ED\\u1735-\\u1736\\u17D4-\\u17D6\\u17D8-\\u17DA\\u1800-\\u180A\\u1944-\\u1945\\u1A1E-\\u1A1F\\u1AA0-\\u1AA6\\u1AA8-\\u1AAD\\u1B5A-\\u1B60\\u1BFC-\\u1BFF\\u1C3B-\\u1C3F\\u1C7E-\\u1C7F\\u1CC0-\\u1CC7\\u1CD3\\u2010-\\u2027\\u2030-\\u2043\\u2045-\\u2051\\u2053-\\u205E\\u207D-\\u207E\\u208D-\\u208E\\u2308-\\u230B\\u2329-\\u232A\\u2768-\\u2775\\u27C5-\\u27C6\\u27E6-\\u27EF\\u2983-\\u2998\\u29D8-\\u29DB\\u29FC-\\u29FD\\u2CF9-\\u2CFC\\u2CFE-\\u2CFF\\u2D70\\u2E00-\\u2E2E\\u2E30-\\u2E3B\\u3001-\\u3003\\u3008-\\u3011\\u3014-\\u301F\\u3030\\u303D\\u30A0\\u30FB\\uA4FE-\\uA4FF\\uA60D-\\uA60F\\uA673\\uA67E\\uA6F2-\\uA6F7\\uA874-\\uA877\\uA8CE-\\uA8CF\\uA8F8-\\uA8FA\\uA92E-\\uA92F\\uA95F\\uA9C1-\\uA9CD\\uA9DE-\\uA9DF\\uAA5C-\\uAA5F\\uAADE-\\uAADF\\uAAF0-\\uAAF1\\uABEB\\uFD3E-\\uFD3F\\uFE10-\\uFE19\\uFE30-\\uFE52\\uFE54-\\uFE61\\uFE63\\uFE68\\uFE6A-\\uFE6B\\uFF01-\\uFF03\\uFF05-\\uFF0A\\uFF0C-\\uFF0F\\uFF1A-\\uFF1B\\uFF1F-\\uFF20\\uFF3B-\\uFF3D\\uFF3F\\uFF5B\\uFF5D\\uFF5F-\\uFF65',
    'S':           '$+<-=>^|~\\u00A2-\\u00A6\\u00A8-\\u00A9\\u00AC\\u00AE-\\u00B1\\u00B4\\u00B8\\u00D7\\u00F7\\u02C2-\\u02C5\\u02D2-\\u02DF\\u02E5-\\u02EB\\u02ED\\u02EF-\\u02FF\\u0375\\u0384-\\u0385\\u03F6\\u0482\\u058D-\\u058F\\u0606-\\u0608\\u060B\\u060E-\\u060F\\u06DE\\u06E9\\u06FD-\\u06FE\\u07F6\\u09F2-\\u09F3\\u09FA-\\u09FB\\u0AF1\\u0B70\\u0BF3-\\u0BFA\\u0C7F\\u0D4F\\u0D79\\u0E3F\\u0F01-\\u0F03\\u0F13\\u0F15-\\u0F17\\u0F1A-\\u0F1F\\u0F34\\u0F36\\u0F38\\u0FBE-\\u0FC5\\u0FC7-\\u0FCC\\u0FCE-\\u0FCF\\u0FD5-\\u0FD8\\u109E-\\u109F\\u1390-\\u1399\\u17DB\\u1940\\u19DE-\\u19FF\\u1B61-\\u1B6A\\u1B74-\\u1B7C\\u1FBD\\u1FBF-\\u1FC1\\u1FCD-\\u1FCF\\u1FDD-\\u1FDF\\u1FED-\\u1FEF\\u1FFD-\\u1FFE\\u2044\\u2052\\u207A-\\u207C\\u208A-\\u208C\\u20A0-\\u20BD\\u2100-\\u2101\\u2103-\\u2106\\u2108-\\u2109\\u2114\\u2116-\\u2118\\u211E-\\u2123\\u2125\\u2127\\u2129\\u212E\\u213A-\\u213B\\u2140-\\u2144\\u214A-\\u214D\\u214F\\u2190-\\u2328\\u232B-\\u23F3\\u2400-\\u2426\\u2440-\\u244A\\u249C-\\u24E9\\u2500-\\u26FF\\u2701-\\u2767\\u2794-\\u27C4\\u27C7-\\u27E5\\u27F0-\\u2982\\u2999-\\u29D7\\u29DC-\\u29FB\\u29FE-\\u2B73\\u2B76-\\u2B95\\u2B98-\\u2BB9\\u2BBD-\\u2BC8\\u2BCA-\\u2BD1\\u2CE5-\\u2CEA\\u2E80-\\u2EF3\\u2F00-\\u2FD5\\u2FF0-\\u2FFB\\u3012-\\u3013\\u3020\\u3036-\\u3037\\u303E-\\u303F\\u309B-\\u309C\\u3190-\\u3191\\u3196-\\u319F\\u31C0-\\u31E3\\u3200-\\u321E\\u322A-\\u3247\\u3250\\u3260-\\u327F\\u328A-\\u32B0\\u32C0-\\u32FE\\u3300-\\u33FF\\u4DC0-\\u4DFF\\uA490-\\uA4C6\\uA700-\\uA716\\uA720-\\uA721\\uA789-\\uA78A\\uA828-\\uA82B\\uA836-\\uA839\\uAA77-\\uAA79\\uAB5B\\uFB29\\uFBB2-\\uFBC2\\uFD40-\\uFD4F\\uFDFC-\\uFDFF\\uFE62\\uFE64-\\uFE66\\uFE69\\uFF04\\uFF0B\\uFF1C-\\uFF1E\\uFF3E\\uFF40\\uFF5C\\uFF5E\\uFFE0-\\uFFE6\\uFFE8-\\uFFEE\\uFFFC-\\uFFFD',
    'M':           '\\u0300-\\u036F\\u0483-\\u0489\\u0591-\\u05BD\\u05BF\\u05C1-\\u05C2\\u05C4-\\u05C5\\u05C7\\u0610-\\u061A\\u064B-\\u065F\\u0670\\u06D6-\\u06DC\\u06DF-\\u06E4\\u06E7-\\u06E8\\u06EA-\\u06ED\\u0711\\u0730-\\u074A\\u07A6-\\u07B0\\u07EB-\\u07F3\\u0816-\\u082D\\u0859-\\u085B\\u08E4-\\u0903\\u093A-\\u094F\\u0951-\\u0957\\u0962-\\u0963\\u0981-\\u0983\\u09BC\\u09BE-\\u09CD\\u09D7\\u09E2-\\u09E3\\u0A01-\\u0A03\\u0A3C\\u0A3E-\\u0A4D\\u0A51\\u0A70-\\u0A71\\u0A75\\u0A81-\\u0A83\\u0ABC-\\u0ACD\\u0AE2-\\u0AE3\\u0B01-\\u0B03\\u0B3C-\\u0B57\\u0B62-\\u0B63\\u0B82\\u0BBE-\\u0BD7\\u0C01-\\u0C03\\u0C3E-\\u0C56\\u0C62-\\u0C63\\u0C82-\\u0C83\\u0CBC-\\u0CD6\\u0CE2-\\u0CE3\\u0D02-\\u0D03\\u0D3E-\\u0D57\\u0D62-\\u0D63\\u0D82-\\u0D83\\u0DCA-\\u0DF3\\u0E31\\u0E34-\\u0E3A\\u0E47-\\u0E4E\\u0EB1\\u0EB4-\\u0EBC\\u0EC8-\\u0ECD\\u0F18-\\u0F19\\u0F35\\u0F37\\u0F39\\u0F3E-\\u0F3F\\u0F71-\\u0F84\\u0F86-\\u0F87\\u0F8D-\\u0FBC\\u0FC6\\u102B-\\u103E\\u1056-\\u1059\\u105E-\\u1060\\u1062-\\u1064\\u1067-\\u106D\\u1071-\\u1074\\u1082-\\u108D\\u108F\\u109A-\\u109D\\u135D-\\u135F\\u1712-\\u1714\\u1732-\\u1734\\u1752-\\u1753\\u1772-\\u1773\\u17B4-\\u17D3\\u17DD\\u180B-\\u180D\\u18A9\\u1920-\\u193B\\u19B0-\\u19C0\\u19C8-\\u19C9\\u1A17-\\u1A1B\\u1A55-\\u1A7F\\u1AB0-\\u1ABE\\u1B00-\\u1B04\\u1B34-\\u1B44\\u1B6B-\\u1B73\\u1B80-\\u1B82\\u1BA1-\\u1BAD\\u1BE6-\\u1BF3\\u1C24-\\u1C37\\u1CD0-\\u1CD2\\u1CD4-\\u1CE8\\u1CED\\u1CF2-\\u1CF4\\u1DC0-\\u1DFF\\u20D0-\\u20F0\\u2CEF-\\u2CF1\\u2D7F\\u2DE0-\\u2DFF\\u302A-\\u302F\\u3099-\\u309A\\uA66F-\\uA672\\uA674-\\uA67D\\uA69F\\uA6F0-\\uA6F1\\uA802\\uA806\\uA80B\\uA823-\\uA827\\uA880-\\uA881\\uA8B4-\\uA8C4\\uA8E0-\\uA8F1\\uA926-\\uA92D\\uA947-\\uA953\\uA980-\\uA983\\uA9B3-\\uA9C0\\uAA29-\\uAA36\\uAA43\\uAA4C-\\uAA4D\\uAA7B\\uAAB0\\uAAB2-\\uAAB4\\uAAB7-\\uAAB8\\uAABE-\\uAABF\\uAAC1\\uAAEB-\\uAAEF\\uAAF5-\\uAAF6\\uABE3-\\uABEA\\uABEC-\\uABED\\uFB1E\\uFE00-\\uFE0F\\uFE20-\\uFE2F',
    'Z':           ' \\u00A0\\u1680\\u2000-\\u200A\\u2028-\\u2029\\u202F\\u205F\\u3000',
    'C':           '\\u0000-\\u001F\\u007F-\\u009F\\u00AD\\u0600-\\u0605\\u061C\\u06DD\\u070F\\u180E\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u206F\\uFEFF\\uFFF9-\\uFFFB',
    'ASCII':       '\\u0000-\\u007F'
  };
  // Aliases.
  T['Letter']      = T['L'];
  T['Number']      = T['N'];
  T['Punctuation'] = T['P'];
  T['Symbol']      = T['S'];
  T['Mark']        = T['M'];
  T['Separator']   = T['Z'];
  T['Other']       = T['C'];
  T['ID_Start']    = T['L'];
  T['ID_Continue'] = T['L'] + T['N'] + T['M'];
  T['XID_Start']   = T['L'];
  T['XID_Continue']= T['L'] + T['N'] + T['M'];
  T['Lu']          = 'A-Z\\u00C0-\\u00D6\\u00D8-\\u00DE';
  T['Ll']          = 'a-z\\u00DF-\\u00F6\\u00F8-\\u00FF';
  T['Lt']          = T['L'];
  T['Lo']          = T['L'];
  T['Lm']          = T['L'];
  T['Nd']          = '0-9\\u0660-\\u0669\\u06F0-\\u06F9';
  T['Nl']          = T['N'];
  /* Common script names: long form and four-letter codes.
     Long form: Script=Latin / Script=Han / etc.
     Short:     sc=Latn / sc=Hani / ...
     Both map to the same range — the key half is already extracted
     by the caller, so we just need the script name. */
  T['Latin']      = T['Latn']  = 'A-Za-z\\u00AA\\u00B5\\u00BA\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02AF\\u1E00-\\u1EFF';
  T['Greek']      = T['Grek']  = '\\u0370-\\u03FF\\u1F00-\\u1FFE';
  T['Cyrillic']   = T['Cyrl']  = '\\u0400-\\u052F\\u1C80-\\u1C8F\\uA640-\\uA69F';
  T['Han']        = T['Hani']  = '\\u3400-\\u4DBF\\u4E00-\\u9FFF\\uF900-\\uFAFF';
  T['Hiragana']   = T['Hira']  = '\\u3041-\\u3096\\u309D-\\u309F';
  T['Katakana']   = T['Kana']  = '\\u30A1-\\u30FA\\u30FC-\\u30FF\\uFF66-\\uFF9F';
  T['Hangul']     = T['Hang']  = '\\u1100-\\u11FF\\u3131-\\u318E\\uAC00-\\uD7A3';
  T['Arabic']     = T['Arab']  = '\\u0600-\\u06FF\\u0750-\\u077F\\uFB50-\\uFDFF';
  T['Hebrew']     = T['Hebr']  = '\\u0590-\\u05FF\\uFB1D-\\uFB4F';
  T['Devanagari'] = T['Deva']  = '\\u0900-\\u097F';
  T['Thai']                    = '\\u0E01-\\u0E5B';
  T['No']          = T['N'];

  // Hand-walk the pattern so we know whether each \p{} sits inside
  // a character class. Inside []  we emit bare ranges; outside,
  // we wrap them in [].
  function expand(src) {
    var out = '';
    var i = 0;
    var inClass = false;
    var BS = String.fromCharCode(92);  // single backslash, dodges raw-string quoting
    while (i < src.length) {
      var c = src[i];
      if (c === BS && i + 1 < src.length) {
        var n = src[i + 1];
        if ((n === 'p' || n === 'P') && src[i + 2] === '{') {
          var end = src.indexOf('}', i + 3);
          if (end > 0) {
            var name = src.slice(i + 3, end);
            var eq = name.indexOf('=');
            var key = (eq >= 0) ? name.slice(eq + 1) : name;
            var cls = T[key];
            if (!cls) cls = 'XX';
            if (n === 'P') {
              out += inClass ? '' : '[^';
              out += cls;
              if (!inClass) out += ']';
            } else {
              out += inClass ? cls : '[' + cls + ']';
            }
            i = end + 1;
            continue;
          }
        }
        out += c + n;
        i += 2;
        continue;
      }
      if (c === '[' && !inClass) inClass = true;
      else if (c === ']' && inClass) inClass = false;
      out += c;
      i++;
    }
    return out;
  }

  // /v set-operation helpers. Each set is a sorted array of
  // [lo, hi] code-point ranges (inclusive). Operates on ranges
  // rather than expanded character lists so wide \p{L} (~50k codes)
  // doesn't blow up.
  function normRanges(rs) {
    rs.sort(function(a, b) { return a[0] - b[0]; });
    var out = [];
    for (var k = 0; k < rs.length; k++) {
      var r = rs[k];
      if (out.length && r[0] <= out[out.length - 1][1] + 1)
        out[out.length - 1][1] = Math.max(out[out.length - 1][1], r[1]);
      else
        out.push([r[0], r[1]]);
    }
    return out;
  }
  function diffRanges(A, B) {
    A = normRanges(A); B = normRanges(B);
    var out = [], bi = 0;
    for (var k = 0; k < A.length; k++) {
      var lo = A[k][0], hi = A[k][1];
      while (bi < B.length && B[bi][1] < lo) bi++;
      var j = bi;
      while (lo <= hi && j < B.length && B[j][0] <= hi) {
        if (B[j][0] > lo) out.push([lo, B[j][0] - 1]);
        lo = Math.max(lo, B[j][1] + 1);
        j++;
      }
      if (lo <= hi) out.push([lo, hi]);
    }
    return out;
  }
  function interRanges(A, B) {
    A = normRanges(A); B = normRanges(B);
    var out = [], ai = 0, bi = 0;
    while (ai < A.length && bi < B.length) {
      var lo = Math.max(A[ai][0], B[bi][0]);
      var hi = Math.min(A[ai][1], B[bi][1]);
      if (lo <= hi) out.push([lo, hi]);
      if (A[ai][1] < B[bi][1]) ai++; else bi++;
    }
    return out;
  }
  function rangesFromKey(key) {
    var s = T[key];
    if (!s) return null;
    var rs = [], i = 0;
    function dec() {
      var c = s[i];
      if (c === BS && s[i+1] === 'u') {
        var hex = s.slice(i+2, i+6); i += 6;
        return parseInt(hex, 16);
      }
      i++;
      return c.charCodeAt(0);
    }
    while (i < s.length) {
      var a = dec();
      if (s[i] === '-' && i+1 < s.length) {
        i++;
        var b = dec();
        rs.push([a, b]);
      } else {
        rs.push([a, a]);
      }
    }
    return rs;
  }
  function hexEsc(cp) {
    // Always emit \uXXXX / \u{...} so set operators in /v don't
    // collide with literal hyphens after expansion.
    if (cp <= 0xFFFF)
      return BS + 'u' + ('0000' + cp.toString(16).toUpperCase()).slice(-4);
    return BS + 'u{' + cp.toString(16).toUpperCase() + '}';
  }
  function rangesToClass(rs) {
    if (rs.length === 0) return '(?!)';  // empty set: never match
    var out = '[';
    for (var k = 0; k < rs.length; k++) {
      out += hexEsc(rs[k][0]);
      if (rs[k][0] !== rs[k][1]) out += '-' + hexEsc(rs[k][1]);
    }
    return out + ']';
  }
  // Parse the inside of a [] in /v mode. Returns ranges or null
  // when the content uses a /v feature we don't support
  // (\q{strings}, nested negation, etc.).
  function parseVSet(content) {
    var i = 0;
    function parseOperand() {
      if (i >= content.length) return null;
      var ch = content[i];
      if (ch === BS) {
        if (content[i+1] === 'p' || content[i+1] === 'P') {
          if (content[i+2] !== '{') return null;
          var negated = content[i+1] === 'P';
          var end = content.indexOf('}', i+3);
          if (end < 0) return null;
          var name = content.slice(i+3, end);
          var eq = name.indexOf('=');
          var key = (eq >= 0) ? name.slice(eq+1) : name;
          i = end + 1;
          var r = rangesFromKey(key);
          if (!r) return null;
          return negated ? diffRanges([[0, 0x10FFFF]], r) : r;
        }
        // Generic escape: \u{...}, \uXXXX, \n, \t, \r, \\, etc.
        var c;
        if (content[i+1] === 'u' && content[i+2] === '{') {
          var end = content.indexOf('}', i+3);
          if (end < 0) return null;
          c = parseInt(content.slice(i+3, end), 16);
          i = end + 1;
        } else if (content[i+1] === 'u') {
          c = parseInt(content.slice(i+2, i+6), 16);
          i += 6;
        } else if (content[i+1] === 'n') { c = 10; i += 2; }
        else if (content[i+1] === 't') { c = 9; i += 2; }
        else if (content[i+1] === 'r') { c = 13; i += 2; }
        else if (content[i+1] === BS) { c = 92; i += 2; }
        else { c = content.charCodeAt(i+1); i += 2; }
        if (content[i] === '-' && content[i+1] !== '-' && i+1 < content.length) {
          i++;
          var e = parseChar();
          if (e === null) return null;
          return [[c, e]];
        }
        return [[c, c]];
      }
      if (ch === '[') {
        var depth = 1, j = i + 1;
        while (j < content.length && depth > 0) {
          if (content[j] === BS) { j += 2; continue; }
          if (content[j] === '[') depth++;
          else if (content[j] === ']') depth--;
          if (depth > 0) j++;
        }
        var inner = content.slice(i+1, j);
        i = j + 1;
        return parseVSet(inner);
      }
      // Plain character
      var start = content.charCodeAt(i); i++;
      if (content[i] === '-' && content[i+1] !== '-' && i+1 < content.length) {
        i++;
        var e2 = parseChar();
        if (e2 === null) return null;
        return [[start, e2]];
      }
      return [[start, start]];
    }
    function parseChar() {
      if (i >= content.length) return null;
      if (content[i] === BS) {
        var c;
        if (content[i+1] === 'u' && content[i+2] === '{') {
          var end = content.indexOf('}', i+3);
          c = parseInt(content.slice(i+3, end), 16);
          i = end + 1;
        } else if (content[i+1] === 'u') {
          c = parseInt(content.slice(i+2, i+6), 16); i += 6;
        } else { c = content.charCodeAt(i+1); i += 2; }
        return c;
      }
      var x = content.charCodeAt(i); i++;
      return x;
    }
    var lhs = parseOperand();
    if (lhs === null) return null;
    var result = lhs;
    var mode = 'union';  // 'union' | 'diff' | 'inter'
    while (i < content.length) {
      if (content[i] === '-' && content[i+1] === '-') {
        if (mode === 'inter') return null;  // can't mix in same level
        mode = 'diff'; i += 2;
        var r = parseOperand(); if (r === null) return null;
        result = diffRanges(result, r);
      } else if (content[i] === '&' && content[i+1] === '&') {
        if (mode === 'diff') return null;
        mode = 'inter'; i += 2;
        var r2 = parseOperand(); if (r2 === null) return null;
        result = interRanges(result, r2);
      } else {
        if (mode !== 'union') return null;  // mixed with set op
        var r3 = parseOperand(); if (r3 === null) return null;
        result = normRanges(result.concat(r3));
      }
    }
    return result;
  }
  // Top-level rewriter: find every [...] in src that contains a /v
  // set operator (\-\-, &&) and replace with the computed range
  // class. Tracks bracket depth and skips strings / escapes inside
  // the regex source itself. Returns null if any rewrite fails.
  function rewriteVSetOps(src) {
    var out = '', i = 0;
    while (i < src.length) {
      var c = src[i];
      if (c === BS && i + 1 < src.length) {
        out += src[i] + src[i+1];
        i += 2;
        continue;
      }
      if (c === '[') {
        // Find matching ']' (account for escaped ] and nested [])
        var depth = 1, j = i + 1;
        while (j < src.length && depth > 0) {
          if (src[j] === BS) { j += 2; continue; }
          if (src[j] === '[') depth++;
          else if (src[j] === ']') depth--;
          if (depth > 0) j++;
        }
        if (j >= src.length) return null;
        var inner = src.slice(i + 1, j);
        if (inner.indexOf('--') !== -1 || inner.indexOf('&&') !== -1) {
          var rs = parseVSet(inner);
          if (rs === null) return null;
          out += rangesToClass(rs);
        } else {
          out += src.slice(i, j + 1);
        }
        i = j + 1;
        continue;
      }
      out += c;
      i++;
    }
    return out;
  }

  var OrigRegExp = RegExp;
  function PatchedRegExp(pattern, flags) {
    if (pattern instanceof OrigRegExp && flags === undefined) {
      return new OrigRegExp(pattern);
    }
    var src = (typeof pattern === 'string') ? pattern : pattern + '';
    var BS_ = BS;
    var flagStr = (typeof flags === 'string') ? flags : '';
    var isV = flagStr.indexOf('v') !== -1;
    var hasSetOp = isV
      && (src.indexOf('--') !== -1 || src.indexOf('&&') !== -1);
    var hasProp = src.indexOf(BS_ + 'p{') !== -1
      || src.indexOf(BS_ + 'P{') !== -1;

    // /v + set ops: rewrite to a precomputed range class with /u.
    // Done first so the second branch (\p{} expansion) doesn't see
    // operators that would clash with hyphens in the expanded ranges.
    if (hasSetOp) {
      var rewritten = rewriteVSetOps(src);
      if (rewritten !== null) {
        var f1 = flagStr.replace('v', 'u');
        try { return new OrigRegExp(rewritten, f1); }
        catch (e) { /* fall through to other paths */ }
      }
    }

    if (hasProp) {
      try {
        return new OrigRegExp(pattern, flags);
      } catch (e) {
        var expanded = expand(src);
        if (globalThis.__DUN_REGEX_TRACE__) console.log('expanded:', expanded);
        try {
          return new OrigRegExp(expanded, flags);
        } catch (e2) {
          var f = flagStr.replace('v', 'u');
          try { return new OrigRegExp(expanded, f); }
          catch (e3) {
            // Last-resort never-match so the regex still constructs.
            return new OrigRegExp('(?!)', '');
          }
        }
      }
    }
    return new OrigRegExp(pattern, flags);
  }
  PatchedRegExp.prototype = OrigRegExp.prototype;
  PatchedRegExp.escape = OrigRegExp.escape;
  Object.defineProperty(globalThis, 'RegExp', {
    value: PatchedRegExp, writable: true, configurable: true
  });
})()`;
}

private JSHandle jsGlobalGC(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGlobalGC");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in jsGlobalGC");
    state.engine.collectGarbage();
    return state.engine.newUndefined();
}
