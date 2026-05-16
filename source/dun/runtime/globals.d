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
    registerUtilModule(engine);
    registerAssertModule(engine);
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

    version (Posix)
        registerTlsModule(engine);

    registerStubModules(engine);

    version (Posix)
        registerFetchGlobal(engine);

    import dun.runtime.web_compat : installWebCompat;
    installWebCompat(engine);

    import dun.runtime.web_apis : installWebAPIs;
    installWebAPIs(engine);

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

    // perf_hooks must come after installWebAPIs so global performance object exists
    registerPerfHooksModule(engine);

    import dun.runtime.intl : installIntl;
    installIntl(engine);

    import dun.runtime.deno_compat : installDenoCompat;
    installDenoCompat(engine);

    installRequire(engine);

    import dun.runtime.rejection_tracker : installRejectionTracker;
    installRejectionTracker(engine, state);

    auto global = engine.getGlobal();
    engine.setProperty(global, "gc", engine.newFunction(&jsGlobalGC, "gc", 0));
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
  var diagnostics_channel = {
    channel: function(name) { return { subscribe: function(){}, unsubscribe: function(){}, hasSubscribers: false, name: name }; },
    hasSubscribers: function() { return false; },
    subscribe: function() {},
    unsubscribe: function() {},
    Channel: function(name) { this.name = name; this.hasSubscribers = false;
      this.subscribe = function(){}; this.unsubscribe = function(){}; this.publish = function(){}; }
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
            if (globalKey.length > 12 && globalKey[0 .. 11] == "__dun_cjs_"
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

private JSHandle jsGlobalGC(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGlobalGC");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in jsGlobalGC");
    state.engine.collectGarbage();
    return state.engine.newUndefined();
}
