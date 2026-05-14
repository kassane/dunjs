module dun.builtins.url;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerUrlModule(IJSEngine engine) @trusted
{
    auto global = engine.getGlobal();

    // URL and URLSearchParams implemented in JS (pure data-structure logic)
    auto src = urlSource();
    auto result = engine.eval(src, "<url>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("URL init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }

    engine.freeValue(global);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:url", &urlModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "URL");
        JS_AddModuleExport(ctx, m, "URLSearchParams");
    }

    private extern (C) int urlModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto urlMod = JS_GetPropertyStr(ctx, global, "__dun_cjs_url__");
        auto urlClass = JS_GetPropertyStr(ctx, urlMod, "URL");
        auto uspClass = JS_GetPropertyStr(ctx, urlMod, "URLSearchParams");
        JS_SetModuleExport(ctx, m, "URL", urlClass);
        JS_SetModuleExport(ctx, m, "URLSearchParams", uspClass);
        JS_FreeValue(ctx, urlMod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string urlSource() pure @safe nothrow
{
    return `(function() {
  function URLSearchParams(init) {
    this._params = [];
    if (typeof init === 'string') {
      var s = init;
      if (s.charAt(0) === '?') s = s.substring(1);
      var pairs = s.split('&');
      for (var i = 0; i < pairs.length; i++) {
        if (pairs[i] === '') continue;
        var eq = pairs[i].indexOf('=');
        if (eq === -1) {
          this._params.push([decodeURIComponent(pairs[i]), '']);
        } else {
          this._params.push([
            decodeURIComponent(pairs[i].substring(0, eq)),
            decodeURIComponent(pairs[i].substring(eq + 1))
          ]);
        }
      }
    } else if (init && typeof init === 'object') {
      var keys = Object.keys(init);
      for (var k = 0; k < keys.length; k++)
        this._params.push([keys[k], String(init[keys[k]])]);
    }
  }

  URLSearchParams.prototype.get = function(name) {
    for (var i = 0; i < this._params.length; i++)
      if (this._params[i][0] === name) return this._params[i][1];
    return null;
  };

  URLSearchParams.prototype.getAll = function(name) {
    var result = [];
    for (var i = 0; i < this._params.length; i++)
      if (this._params[i][0] === name) result.push(this._params[i][1]);
    return result;
  };

  URLSearchParams.prototype.has = function(name) {
    for (var i = 0; i < this._params.length; i++)
      if (this._params[i][0] === name) return true;
    return false;
  };

  URLSearchParams.prototype.set = function(name, value) {
    var found = false;
    var i = 0;
    while (i < this._params.length) {
      if (this._params[i][0] === name) {
        if (!found) { this._params[i][1] = String(value); found = true; i++; }
        else this._params.splice(i, 1);
      } else i++;
    }
    if (!found) this._params.push([name, String(value)]);
  };

  URLSearchParams.prototype.append = function(name, value) {
    this._params.push([name, String(value)]);
  };

  URLSearchParams.prototype['delete'] = function(name) {
    var i = 0;
    while (i < this._params.length) {
      if (this._params[i][0] === name) this._params.splice(i, 1);
      else i++;
    }
  };

  URLSearchParams.prototype.toString = function() {
    return this._params.map(function(p) {
      return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
    }).join('&');
  };

  URLSearchParams.prototype.entries = function() {
    var idx = 0;
    var params = this._params;
    return { next: function() {
      if (idx >= params.length) return { done: true, value: undefined };
      return { done: false, value: params[idx++].slice() };
    }, [Symbol.iterator]: function() { return this; } };
  };

  URLSearchParams.prototype.keys = function() {
    var idx = 0;
    var params = this._params;
    return { next: function() {
      if (idx >= params.length) return { done: true, value: undefined };
      return { done: false, value: params[idx++][0] };
    }, [Symbol.iterator]: function() { return this; } };
  };

  URLSearchParams.prototype.values = function() {
    var idx = 0;
    var params = this._params;
    return { next: function() {
      if (idx >= params.length) return { done: true, value: undefined };
      return { done: false, value: params[idx++][1] };
    }, [Symbol.iterator]: function() { return this; } };
  };

  URLSearchParams.prototype.forEach = function(cb, thisArg) {
    for (var i = 0; i < this._params.length; i++)
      cb.call(thisArg, this._params[i][1], this._params[i][0], this);
  };

  URLSearchParams.prototype.sort = function() {
    this._params.sort(function(a, b) {
      if (a[0] < b[0]) return -1;
      if (a[0] > b[0]) return 1;
      return 0;
    });
  };

  Object.defineProperty(URLSearchParams.prototype, 'size', {
    get: function() { return this._params.length; }
  });

  function URL(input, base) {
    var url = input;
    if (base !== undefined) {
      if (!/^[a-zA-Z][a-zA-Z0-9+\-.]*:/.test(url)) {
        var b = typeof base === 'string' ? base : base.href;
        if (url.charAt(0) === '/') {
          var origin = b.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*:\/\/[^\/]*)/);
          url = origin ? origin[1] + url : url;
        } else {
          var lastSlash = b.lastIndexOf('/');
          url = b.substring(0, lastSlash + 1) + url;
        }
      }
    }

    var match = url.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*):\/\/(?:([^:@]*)(?::([^@]*))?@)?([^:\/\?#]*)(?::(\d+))?(\/[^\?#]*)?(\?[^#]*)?(#.*)?$/);
    if (!match) {
      // Try protocol-relative or opaque
      var simpleMatch = url.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*):(.*)$/);
      if (simpleMatch) {
        this.protocol = simpleMatch[1] + ':';
        this.pathname = simpleMatch[2] || '';
        this.hostname = '';
        this.port = '';
        this.host = '';
        this.origin = this.protocol + '//';
        this.search = '';
        this.hash = '';
        this.username = '';
        this.password = '';
        this.searchParams = new URLSearchParams('');
        this.href = url;
        return;
      }
      throw new TypeError("Invalid URL: " + input);
    }

    this.protocol = (match[1] || '') + ':';
    this.username = match[2] || '';
    this.password = match[3] || '';
    this.hostname = match[4] || '';
    this.port = match[5] || '';
    this.pathname = match[6] || '/';
    this.search = match[7] || '';
    this.hash = match[8] || '';

    this.host = this.hostname + (this.port ? ':' + this.port : '');
    this.origin = this.protocol + '//' + this.host;
    this.searchParams = new URLSearchParams(this.search);

    this.href = this.protocol + '//' +
      (this.username ? this.username + (this.password ? ':' + this.password : '') + '@' : '') +
      this.host + this.pathname + this.search + this.hash;
  }

  URL.prototype.toString = function() { return this.href; };
  URL.prototype.toJSON = function() { return this.href; };

  var mod = { URL: URL, URLSearchParams: URLSearchParams };
  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_url__ = mod;
    globalThis.URL = URL;
    globalThis.URLSearchParams = URLSearchParams;
  }
})();`;
}
