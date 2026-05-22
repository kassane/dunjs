module dun.builtins.https;


/// `@trusted policy`: HTTPS server + client. Thin wrapper over
/// `dun.builtins.http` that swaps TCP for TLS via
/// `dun.builtins.tls`. Every `@trusted` is one of:
///   1. OpenSSL FFI for the TLS handshake + read/write — same
///      surface as `tls.d`.
///   2. Underlying HTTP server logic from `http.d`.
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;

void registerHttpsModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerHttpsModule");
    auto obj = engine.newObject();
    engine.setProperty(obj, "createServer",
        engine.newFunction(&jsHttpsCreateServer, "createServer", 2));

    auto httpsExtResult = engine.eval(httpsExtensionSource(), "<https-ext>");
    if (!httpsExtResult.isError)
    {
        foreach (name; ["request", "get", "METHODS", "STATUS_CODES", "Agent", "globalAgent"])
        {
            auto prop = engine.getProperty(httpsExtResult.value, name);
            engine.setProperty(obj, name, prop);
        }
    }
    engine.freeValue(httpsExtResult.value);

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_https__", obj);
    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:https", &httpsModuleInit);
        if (m is null) return;
        foreach (name; ["createServer", "request", "get", "METHODS",
                        "STATUS_CODES", "Agent", "globalAgent"])
            JS_AddModuleExport(ctx, m, name.ptr);

        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int httpsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in httpsModuleInit");
        assert(m !is null, "Null JSModuleDef in httpsModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto httpsObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_https__");
        foreach (name; ["createServer", "request", "get", "METHODS",
                        "STATUS_CODES", "Agent", "globalAgent"])
        {
            auto fn = JS_GetPropertyStr(ctx, httpsObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_SetModuleExport(ctx, m, "default", httpsObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

JSHandle jsHttpsCreateServer(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsHttpsCreateServer");
    auto engine = state.engine;

    version (Posix)
    {
        import dun.platform.openssl;

        if (args.length < 1 || !engine.isObject(args[0]))
            return engine.throwTypeError("https.createServer requires options object with key and cert");

        auto keyProp = engine.getProperty(args[0], "key");
        auto certProp = engine.getProperty(args[0], "cert");

        string keyPath, certPath;
        scope(exit) { engine.freeValue(keyProp); engine.freeValue(certProp); }

        if (!engine.isString(keyProp) || !engine.isString(certProp))
            return engine.throwTypeError("https.createServer: options must have 'key' and 'cert' strings");

        keyPath = engine.extractString(keyProp);
        certPath = engine.extractString(certProp);

        ensureTlsServerInit();
        auto sslCtx = SSL_CTX_new(TLS_method());
        if (sslCtx is null)
            return engine.throwTypeError("https.createServer: failed to create SSL context");

        SSL_CTX_ctrl(sslCtx, SSL_CTRL_SET_MIN_PROTO_VERSION, TLS1_2_VERSION, null);

        import std.string : toStringz;
        if (SSL_CTX_use_certificate_file(sslCtx, certPath.toStringz, SSL_FILETYPE_PEM) != 1)
        {
            SSL_CTX_free(sslCtx);
            return engine.throwTypeError("https.createServer: failed to load certificate file");
        }
        if (SSL_CTX_use_PrivateKey_file(sslCtx, keyPath.toStringz, SSL_FILETYPE_PEM) != 1)
        {
            SSL_CTX_free(sslCtx);
            return engine.throwTypeError("https.createServer: failed to load private key file");
        }
        if (SSL_CTX_check_private_key(sslCtx) != 1)
        {
            SSL_CTX_free(sslCtx);
            return engine.throwTypeError("https.createServer: private key does not match certificate");
        }

        JSHandle cb;
        bool hasCb = false;
        if (args.length >= 2 && engine.isFunction(args[1]))
        {
            cb = engine.dupValue(args[1]);
            hasCb = true;
        }

        import dun.builtins.http : createServerWithTls;
        return createServerWithTls(engine, cb, hasCb, cast(void*) sslCtx);
    }
    else
    {
        return engine.throwTypeError("https server not supported on this platform");
    }
}

version (Posix)
{
    import dun.platform.openssl;

    private __gshared bool gServerInitDone;

    void ensureTlsServerInit() @trusted nothrow @nogc
    {
        if (gServerInitDone) return;
        OPENSSL_init_ssl(
            OPENSSL_INIT_LOAD_SSL_STRINGS | OPENSSL_INIT_LOAD_CRYPTO_STRINGS, null);
        gServerInitDone = true;
    }
}

string httpsExtensionSource() pure @safe nothrow
{
    return `(function() {
  var httpMod = globalThis.__dun_cjs_http__;
  var result = {
    METHODS: httpMod ? httpMod.METHODS : [],
    STATUS_CODES: httpMod ? httpMod.STATUS_CODES : {},
    Agent: httpMod ? httpMod.Agent : function(){},
    globalAgent: httpMod ? httpMod.globalAgent : {}
  };

  function request(urlOrOptions, optionsOrCallback, callback) {
    var options;
    if (typeof urlOrOptions === 'string') {
      try {
        var parsed = new URL(urlOrOptions);
        options = {
          protocol: parsed.protocol,
          hostname: parsed.hostname,
          port: parsed.port || 443,
          path: parsed.pathname + parsed.search
        };
      } catch(e) {
        options = { path: urlOrOptions, protocol: 'https:', port: 443 };
      }
      if (typeof optionsOrCallback === 'function') {
        callback = optionsOrCallback;
      } else if (typeof optionsOrCallback === 'object' && optionsOrCallback !== null) {
        var keys = Object.keys(optionsOrCallback);
        for (var i = 0; i < keys.length; i++) options[keys[i]] = optionsOrCallback[keys[i]];
      }
    } else {
      options = Object.assign({}, urlOrOptions || {});
      callback = typeof optionsOrCallback === 'function' ? optionsOrCallback : callback;
    }
    if (!options.protocol) options.protocol = 'https:';
    if (!options.port) options.port = 443;
    return httpMod.request(options, callback);
  }

  function get(urlOrOptions, optionsOrCallback, callback) {
    var req = request(urlOrOptions, optionsOrCallback, callback);
    req.end();
    return req;
  }

  result.request = request;
  result.get = get;
  return result;
})();`;
}
