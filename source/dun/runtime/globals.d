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
    import dun.modules.require : installRequire;

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
    registerStubModules(engine);

    version (Posix)
        registerFetchGlobal(engine);

    import dun.runtime.web_compat : installWebCompat;
    installWebCompat(engine);

    import dun.runtime.web_apis : installWebAPIs;
    installWebAPIs(engine);

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
  var tls = { createServer: function() { throw new Error('tls.createServer not implemented'); },
    connect: function() { throw new Error('tls.connect not implemented'); },
    TLSSocket: function() { throw new Error('TLSSocket not implemented'); },
    DEFAULT_MIN_VERSION: 'TLSv1.2', DEFAULT_MAX_VERSION: 'TLSv1.3' };
  var dgram = { createSocket: function() { throw new Error('dgram.createSocket not implemented'); } };
  var perf_hooks = {
    performance: typeof performance !== 'undefined' ? performance : { now: function() { return Date.now(); } },
    PerformanceObserver: function() { this.observe = function(){}; this.disconnect = function(){}; }
  };
  var punycode = {
    encode: function(s) { return s; },
    decode: function(s) { return s; },
    toASCII: function(s) { return s; },
    toUnicode: function(s) { return s; },
    ucs2: { decode: function(s) { var r=[]; for(var i=0;i<s.length;i++) r.push(s.charCodeAt(i)); return r; },
             encode: function(a) { var r=''; for(var i=0;i<a.length;i++) r+=String.fromCharCode(a[i]); return r; } },
    version: '2.1.0'
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
  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_tls__ = tls;
    globalThis.__dun_cjs_dgram__ = dgram;
    globalThis.__dun_cjs_perf_hooks__ = perf_hooks;
    globalThis.__dun_cjs_punycode__ = punycode;
    globalThis.__dun_cjs_diagnostics_channel__ = diagnostics_channel;
    globalThis.__dun_cjs_domain__ = domain;
  }
})()`, "<stubs>");
    engine.freeValue(result.value);
}

private JSHandle jsGlobalGC(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsGlobalGC");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in jsGlobalGC");
    state.engine.collectGarbage();
    return state.engine.newUndefined();
}
