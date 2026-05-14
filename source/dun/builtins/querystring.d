module dun.builtins.querystring;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerQuerystringModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerQuerystringModule");

    auto global = engine.getGlobal();

    auto src = querystringSource();
    auto result = engine.eval(src, "<querystring>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("querystring init failed: ", result.errorMessage);
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
        assert(ctx !is null, "Null context in querystring registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:querystring", &querystringModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "parse");
        JS_AddModuleExport(ctx, m, "stringify");
        JS_AddModuleExport(ctx, m, "escape");
        JS_AddModuleExport(ctx, m, "unescape");
        JS_AddModuleExport(ctx, m, "encode");
        JS_AddModuleExport(ctx, m, "decode");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int querystringModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_querystring__");

        JS_SetModuleExport(ctx, m, "parse", JS_GetPropertyStr(ctx, mod, "parse"));
        JS_SetModuleExport(ctx, m, "stringify", JS_GetPropertyStr(ctx, mod, "stringify"));
        JS_SetModuleExport(ctx, m, "escape", JS_GetPropertyStr(ctx, mod, "escape"));
        JS_SetModuleExport(ctx, m, "unescape", JS_GetPropertyStr(ctx, mod, "unescape"));
        JS_SetModuleExport(ctx, m, "encode", JS_GetPropertyStr(ctx, mod, "encode"));
        JS_SetModuleExport(ctx, m, "decode", JS_GetPropertyStr(ctx, mod, "decode"));
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string querystringSource() pure @safe nothrow
{
    return `(function() {
  function escape(str) {
    return encodeURIComponent(str);
  }

  function unescape(str) {
    return decodeURIComponent(str.replace(/\+/g, ' '));
  }

  function parse(str, sep, eq, options) {
    sep = sep || '&';
    eq = eq || '=';
    var maxKeys = (options && typeof options.maxKeys === 'number') ? options.maxKeys : 1000;
    var obj = {};

    if (typeof str !== 'string' || str.length === 0) return obj;

    var pairs = str.split(sep);
    var len = maxKeys > 0 ? Math.min(pairs.length, maxKeys) : pairs.length;

    for (var i = 0; i < len; i++) {
      var pair = pairs[i];
      var eqIdx = pair.indexOf(eq);
      var key, val;

      if (eqIdx >= 0) {
        key = unescape(pair.substring(0, eqIdx));
        val = unescape(pair.substring(eqIdx + eq.length));
      } else {
        key = unescape(pair);
        val = '';
      }

      if (Object.prototype.hasOwnProperty.call(obj, key)) {
        if (Array.isArray(obj[key])) {
          obj[key].push(val);
        } else {
          obj[key] = [obj[key], val];
        }
      } else {
        obj[key] = val;
      }
    }
    return obj;
  }

  function stringify(obj, sep, eq) {
    sep = sep || '&';
    eq = eq || '=';

    if (obj === null || obj === undefined || typeof obj !== 'object') return '';

    var keys = Object.keys(obj);
    var parts = [];

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      var val = obj[key];
      var ek = escape(key);

      if (Array.isArray(val)) {
        for (var j = 0; j < val.length; j++) {
          parts.push(ek + eq + escape(String(val[j])));
        }
      } else {
        parts.push(ek + eq + escape(String(val)));
      }
    }
    return parts.join(sep);
  }

  var mod = {
    parse: parse,
    stringify: stringify,
    escape: escape,
    unescape: unescape,
    decode: parse,
    encode: stringify
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_querystring__ = mod;
  }
})();`;
}
