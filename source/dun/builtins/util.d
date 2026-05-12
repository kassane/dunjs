module dun.builtins.util;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerUtilModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerUtilModule");

    auto global = engine.getGlobal();

    auto src = utilSource();
    auto result = engine.eval(src, "<util>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("util init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in util registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:util", &utilModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "format");
        JS_AddModuleExport(ctx, m, "inspect");
        JS_AddModuleExport(ctx, m, "inherits");
        JS_AddModuleExport(ctx, m, "promisify");
        JS_AddModuleExport(ctx, m, "deprecate");
        JS_AddModuleExport(ctx, m, "isDeepStrictEqual");
        JS_AddModuleExport(ctx, m, "types");
        JS_AddModuleExport(ctx, m, "TextEncoder");
        JS_AddModuleExport(ctx, m, "TextDecoder");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int utilModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_util__");

        auto format = JS_GetPropertyStr(ctx, mod, "format");
        auto inspect = JS_GetPropertyStr(ctx, mod, "inspect");
        auto inherits = JS_GetPropertyStr(ctx, mod, "inherits");
        auto promisify = JS_GetPropertyStr(ctx, mod, "promisify");
        auto deprecate = JS_GetPropertyStr(ctx, mod, "deprecate");
        auto isDeepStrictEqual = JS_GetPropertyStr(ctx, mod, "isDeepStrictEqual");
        auto types = JS_GetPropertyStr(ctx, mod, "types");
        auto te = JS_GetPropertyStr(ctx, mod, "TextEncoder");
        auto td = JS_GetPropertyStr(ctx, mod, "TextDecoder");

        JS_SetModuleExport(ctx, m, "format", format);
        JS_SetModuleExport(ctx, m, "inspect", inspect);
        JS_SetModuleExport(ctx, m, "inherits", inherits);
        JS_SetModuleExport(ctx, m, "promisify", promisify);
        JS_SetModuleExport(ctx, m, "deprecate", deprecate);
        JS_SetModuleExport(ctx, m, "isDeepStrictEqual", isDeepStrictEqual);
        JS_SetModuleExport(ctx, m, "types", types);
        JS_SetModuleExport(ctx, m, "TextEncoder", te);
        JS_SetModuleExport(ctx, m, "TextDecoder", td);
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string utilSource() pure @safe nothrow
{
    return `(function() {
  // --- Deep equality helper ---
  function isDeepStrictEqual(a, b) {
    if (a === b) return true;
    if (a === null || b === null) return false;
    if (typeof a !== typeof b) return false;
    if (typeof a !== 'object') return false;

    // Date comparison
    if (a instanceof Date && b instanceof Date)
      return a.getTime() === b.getTime();

    // RegExp comparison
    if (a instanceof RegExp && b instanceof RegExp)
      return a.source === b.source && a.flags === b.flags;

    // Array comparison
    if (Array.isArray(a)) {
      if (!Array.isArray(b)) return false;
      if (a.length !== b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!isDeepStrictEqual(a[i], b[i])) return false;
      }
      return true;
    }

    // Map comparison
    if (a instanceof Map && b instanceof Map) {
      if (a.size !== b.size) return false;
      var aEntries = Array.from(a.entries());
      for (var mi = 0; mi < aEntries.length; mi++) {
        if (!b.has(aEntries[mi][0])) return false;
        if (!isDeepStrictEqual(a.get(aEntries[mi][0]), b.get(aEntries[mi][0]))) return false;
      }
      return true;
    }

    // Set comparison
    if (a instanceof Set && b instanceof Set) {
      if (a.size !== b.size) return false;
      var aVals = Array.from(a.values());
      for (var si = 0; si < aVals.length; si++) {
        if (!b.has(aVals[si])) return false;
      }
      return true;
    }

    // Plain object comparison
    var keysA = Object.keys(a);
    var keysB = Object.keys(b);
    if (keysA.length !== keysB.length) return false;
    for (var ki = 0; ki < keysA.length; ki++) {
      if (!Object.prototype.hasOwnProperty.call(b, keysA[ki])) return false;
      if (!isDeepStrictEqual(a[keysA[ki]], b[keysA[ki]])) return false;
    }
    return true;
  }

  // --- util.types ---
  var types = {
    isDate: function(v) { return v instanceof Date; },
    isRegExp: function(v) { return v instanceof RegExp; },
    isNativeError: function(v) { return v instanceof Error; },
    isPromise: function(v) { return v instanceof Promise; },
    isArrayBuffer: function(v) { return v instanceof ArrayBuffer; },
    isTypedArray: function(v) {
      return (v instanceof Uint8Array) || (v instanceof Int8Array) ||
             (v instanceof Uint16Array) || (v instanceof Int16Array) ||
             (v instanceof Uint32Array) || (v instanceof Int32Array) ||
             (v instanceof Float32Array) || (v instanceof Float64Array) ||
             (typeof BigInt64Array !== 'undefined' && v instanceof BigInt64Array) ||
             (typeof BigUint64Array !== 'undefined' && v instanceof BigUint64Array);
    },
    isMap: function(v) { return v instanceof Map; },
    isSet: function(v) { return v instanceof Set; }
  };

  // --- util.format ---
  function format() {
    if (arguments.length === 0) return '';
    var f = arguments[0];
    if (typeof f !== 'string') {
      var parts = [];
      for (var pi = 0; pi < arguments.length; pi++) {
        parts.push(inspect(arguments[pi]));
      }
      return parts.join(' ');
    }
    var argIdx = 1;
    var result = f.replace(/%[sdjoO%]/g, function(match) {
      if (match === '%%') return '%';
      if (argIdx >= arguments.length + 1) return match;
      var arg = arguments.length > argIdx ? arguments[argIdx] : undefined;
      // We need to use the outer arguments, not the replace callback arguments
      return match;
    });
    // Manual replacement to use outer arguments correctly
    var out = '';
    argIdx = 1;
    for (var ci = 0; ci < f.length; ci++) {
      if (f[ci] === '%' && ci + 1 < f.length) {
        var ch = f[ci + 1];
        if (ch === '%') { out += '%'; ci++; continue; }
        if (argIdx < arguments.length) {
          var val = arguments[argIdx++];
          if (ch === 's') { out += String(val); ci++; continue; }
          if (ch === 'd') { out += Number(val); ci++; continue; }
          if (ch === 'j') {
            try { out += JSON.stringify(val); } catch(e) { out += '[Circular]'; }
            ci++; continue;
          }
          if (ch === 'o' || ch === 'O') {
            try { out += JSON.stringify(val, null, 2); } catch(e) { out += '[Circular]'; }
            ci++; continue;
          }
        }
      }
      out += f[ci];
    }
    // Append remaining arguments
    for (; argIdx < arguments.length; argIdx++) {
      out += ' ' + inspect(arguments[argIdx]);
    }
    return out;
  }

  // --- util.inspect ---
  function inspect(obj, opts) {
    if (obj === null) return 'null';
    if (obj === undefined) return 'undefined';
    if (typeof obj === 'string') return "'" + obj + "'";
    if (typeof obj === 'number' || typeof obj === 'boolean') return String(obj);
    if (typeof obj === 'function') return '[Function: ' + (obj.name || 'anonymous') + ']';
    if (typeof obj === 'symbol') return obj.toString();
    var depth = (opts && typeof opts.depth === 'number') ? opts.depth : 2;
    try { return JSON.stringify(obj, null, 2); } catch(e) { return '[Circular]'; }
  }

  // --- util.inherits ---
  function inherits(ctor, superCtor) {
    if (typeof ctor !== 'function') throw new TypeError('ctor must be a function');
    if (typeof superCtor !== 'function') throw new TypeError('superCtor must be a function');
    ctor.super_ = superCtor;
    ctor.prototype = Object.create(superCtor.prototype, {
      constructor: { value: ctor, enumerable: false, writable: true, configurable: true }
    });
  }

  // --- util.promisify ---
  function promisify(original) {
    if (typeof original !== 'function')
      throw new TypeError('The "original" argument must be of type Function');
    function fn() {
      var args = Array.prototype.slice.call(arguments);
      return new Promise(function(resolve, reject) {
        args.push(function(err, result) {
          if (err) reject(err);
          else resolve(result);
        });
        original.apply(this, args);
      });
    }
    Object.setPrototypeOf(fn, Object.getPrototypeOf(original));
    fn.__isPromisified__ = true;
    return fn;
  }

  // --- util.deprecate ---
  function deprecate(fn, msg, code) {
    if (typeof fn !== 'function')
      throw new TypeError('The "fn" argument must be of type Function');
    var warned = false;
    function deprecated() {
      if (!warned) {
        console.warn('DeprecationWarning: ' + msg + (code ? ' [' + code + ']' : ''));
        warned = true;
      }
      return fn.apply(this, arguments);
    }
    return deprecated;
  }

  var mod = {
    format: format,
    inspect: inspect,
    inherits: inherits,
    promisify: promisify,
    deprecate: deprecate,
    isDeepStrictEqual: isDeepStrictEqual,
    types: types,
    TextEncoder: typeof TextEncoder !== 'undefined' ? TextEncoder : undefined,
    TextDecoder: typeof TextDecoder !== 'undefined' ? TextDecoder : undefined
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_util__ = mod;
  }
})();`;
}
