module dun.builtins.url;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerUrlModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerUrlModule");
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
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        auto m = JS_NewCModule(ctx, "dun:url", &urlModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "URL");
        JS_AddModuleExport(ctx, m, "URLSearchParams");
        JS_AddModuleExport(ctx, m, "parse");
        JS_AddModuleExport(ctx, m, "format");
        JS_AddModuleExport(ctx, m, "resolve");
        JS_AddModuleExport(ctx, m, "fileURLToPath");
        JS_AddModuleExport(ctx, m, "pathToFileURL");
        JS_AddModuleExport(ctx, m, "domainToASCII");
        JS_AddModuleExport(ctx, m, "domainToUnicode");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int urlModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto urlMod = JS_GetPropertyStr(ctx, global, "__dun_cjs_url__");
        auto urlClass = JS_GetPropertyStr(ctx, urlMod, "URL");
        auto uspClass = JS_GetPropertyStr(ctx, urlMod, "URLSearchParams");
        JS_SetModuleExport(ctx, m, "URL", urlClass);
        JS_SetModuleExport(ctx, m, "URLSearchParams", uspClass);
        JS_SetModuleExport(ctx, m, "parse", JS_GetPropertyStr(ctx, urlMod, "parse"));
        JS_SetModuleExport(ctx, m, "format", JS_GetPropertyStr(ctx, urlMod, "format"));
        JS_SetModuleExport(ctx, m, "resolve", JS_GetPropertyStr(ctx, urlMod, "resolve"));
        JS_SetModuleExport(ctx, m, "fileURLToPath", JS_GetPropertyStr(ctx, urlMod, "fileURLToPath"));
        JS_SetModuleExport(ctx, m, "pathToFileURL", JS_GetPropertyStr(ctx, urlMod, "pathToFileURL"));
        JS_SetModuleExport(ctx, m, "domainToASCII", JS_GetPropertyStr(ctx, urlMod, "domainToASCII"));
        JS_SetModuleExport(ctx, m, "domainToUnicode", JS_GetPropertyStr(ctx, urlMod, "domainToUnicode"));
        JS_SetModuleExport(ctx, m, "default", JS_DupValue(ctx, urlMod));
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

  URLSearchParams.prototype[Symbol.iterator] = URLSearchParams.prototype.entries;

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

  function urlParse(urlString, parseQueryString, slashesDenoteHost) {
    if (typeof urlString !== 'string') urlString = String(urlString);
    var result = {
      protocol: null, slashes: null, auth: null, host: null,
      port: null, hostname: null, hash: null, search: null,
      query: null, pathname: null, path: null, href: urlString
    };
    var rest = urlString;

    var protoMatch = rest.match(/^([a-zA-Z][a-zA-Z0-9+\-.]*:)/);
    if (protoMatch) {
      result.protocol = protoMatch[1].toLowerCase();
      rest = rest.substring(protoMatch[1].length);
    }

    if (result.protocol && rest.substring(0, 2) === '//') {
      result.slashes = true;
      rest = rest.substring(2);

      var atIdx = rest.indexOf('@');
      var slashIdx = rest.indexOf('/');
      var qIdx = rest.indexOf('?');
      var hIdx = rest.indexOf('#');
      var hostEnd = rest.length;
      if (slashIdx !== -1 && slashIdx < hostEnd) hostEnd = slashIdx;
      if (qIdx !== -1 && qIdx < hostEnd) hostEnd = qIdx;
      if (hIdx !== -1 && hIdx < hostEnd) hostEnd = hIdx;

      if (atIdx !== -1 && atIdx < hostEnd) {
        result.auth = rest.substring(0, atIdx);
        rest = rest.substring(atIdx + 1);
        hostEnd = rest.length;
        slashIdx = rest.indexOf('/');
        qIdx = rest.indexOf('?');
        hIdx = rest.indexOf('#');
        if (slashIdx !== -1 && slashIdx < hostEnd) hostEnd = slashIdx;
        if (qIdx !== -1 && qIdx < hostEnd) hostEnd = qIdx;
        if (hIdx !== -1 && hIdx < hostEnd) hostEnd = hIdx;
      }

      var hostPart = rest.substring(0, hostEnd);
      rest = rest.substring(hostEnd);
      result.host = hostPart;
      var colonIdx = hostPart.lastIndexOf(':');
      if (colonIdx !== -1) {
        var portStr = hostPart.substring(colonIdx + 1);
        if (/^\d+$/.test(portStr)) {
          result.port = portStr;
          result.hostname = hostPart.substring(0, colonIdx);
        } else {
          result.hostname = hostPart;
        }
      } else {
        result.hostname = hostPart;
      }
    }

    var hashIdx = rest.indexOf('#');
    if (hashIdx !== -1) {
      result.hash = rest.substring(hashIdx);
      rest = rest.substring(0, hashIdx);
    }

    var searchIdx = rest.indexOf('?');
    if (searchIdx !== -1) {
      result.search = rest.substring(searchIdx);
      result.query = rest.substring(searchIdx + 1);
      rest = rest.substring(0, searchIdx);
    }

    if (rest) result.pathname = rest;
    else if (result.slashes) result.pathname = '/';

    if (result.pathname || result.search) {
      result.path = (result.pathname || '') + (result.search || '');
    }

    result.href = urlFormat(result);
    return result;
  }

  function urlFormat(urlObj) {
    if (typeof urlObj === 'string') return urlObj;
    var out = '';
    if (urlObj.protocol) out += urlObj.protocol;
    if (urlObj.slashes || (urlObj.protocol && urlObj.protocol.match(/^https?:$/))) out += '//';
    if (urlObj.auth) out += urlObj.auth + '@';
    if (urlObj.hostname) out += urlObj.hostname;
    else if (urlObj.host) out += urlObj.host;
    if (urlObj.port && urlObj.hostname) out += ':' + urlObj.port;
    if (urlObj.pathname) out += urlObj.pathname;
    if (urlObj.search) out += urlObj.search;
    else if (urlObj.query) {
      out += '?' + (typeof urlObj.query === 'string' ? urlObj.query : '');
    }
    if (urlObj.hash) out += urlObj.hash;
    return out;
  }

  function urlResolve(from, to) {
    var base = urlParse(from);
    var rel = urlParse(to);
    if (rel.protocol) return urlFormat(rel);
    rel.protocol = base.protocol;
    if (!rel.slashes) {
      if (!rel.hostname) {
        rel.hostname = base.hostname;
        rel.host = base.host;
        rel.port = base.port;
        rel.auth = base.auth;
        rel.slashes = base.slashes;
        if (!rel.pathname) {
          rel.pathname = base.pathname;
        } else if (rel.pathname.charAt(0) !== '/') {
          var dir = base.pathname ? base.pathname.substring(0, base.pathname.lastIndexOf('/') + 1) : '/';
          rel.pathname = dir + rel.pathname;
        }
      }
      rel.slashes = base.slashes;
    }
    rel.path = (rel.pathname || '') + (rel.search || '');
    rel.href = urlFormat(rel);
    return rel.href;
  }

  function fileURLToPath(url) {
    var str = typeof url === 'string' ? url : url.href || url.toString();
    if (str.substring(0, 7) !== 'file://') throw new TypeError('The URL must be of scheme file');
    var pathname = str.substring(7);
    if (pathname.charAt(0) === '/') {
      // Remove host portion for file:///path
    }
    return decodeURIComponent(pathname);
  }

  function pathToFileURL(path) {
    var encoded = encodeURIComponent(path).replace(/%2F/g, '/').replace(/%3A/g, ':');
    return new URL('file://' + (path.charAt(0) === '/' ? '' : '/') + encoded);
  }

  function domainToASCII(domain) {
    // Simplified: return lowercase domain (full punycode would need ICU)
    return domain.toLowerCase();
  }

  function domainToUnicode(domain) {
    return domain;
  }

  var mod = { URL: URL, URLSearchParams: URLSearchParams,
    parse: urlParse, format: urlFormat, resolve: urlResolve,
    fileURLToPath: fileURLToPath, pathToFileURL: pathToFileURL,
    domainToASCII: domainToASCII, domainToUnicode: domainToUnicode };
  URL.canParse = function(url, base) {
    try { new URL(url, base); return true; }
    catch(e) { return false; }
  };
  URL.createObjectURL = function() { throw new Error('URL.createObjectURL is not supported in server-side JS'); };
  URL.revokeObjectURL = function() {};
  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_url__ = mod;
    globalThis.URL = URL;
    globalThis.URLSearchParams = URLSearchParams;
  }
})();`;
}
