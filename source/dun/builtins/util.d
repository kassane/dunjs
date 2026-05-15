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
        assert(ctx !is null, "Null context in util registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:util", &utilModuleInit);
        if (m is null) return;
        foreach (name; ["format", "inspect", "inherits", "promisify",
                        "callbackify", "deprecate", "debuglog",
                        "isDeepStrictEqual", "types", "_extend",
                        "toUSVString", "stripVTControlCharacters",
                        "TextEncoder", "TextDecoder",
                        "getSystemErrorName", "parseArgs", "styleText", "MIMEType",
                        "aborted", "transferableAbortController", "transferableAbortSignal", "getCallSites"])
            JS_AddModuleExport(ctx, m, name.ptr);
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int utilModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_util__");

        foreach (name; ["format", "inspect", "inherits", "promisify",
                        "callbackify", "deprecate", "debuglog",
                        "isDeepStrictEqual", "types", "_extend",
                        "toUSVString", "stripVTControlCharacters",
                        "TextEncoder", "TextDecoder",
                        "getSystemErrorName", "parseArgs", "styleText", "MIMEType",
                        "aborted", "transferableAbortController", "transferableAbortSignal", "getCallSites"])
        {
            auto val = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, val);
        }
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
    isSet: function(v) { return v instanceof Set; },
    isAsyncFunction: function(v) {
      return typeof v === 'function' && v.constructor && v.constructor.name === 'AsyncFunction';
    },
    isGeneratorFunction: function(v) {
      return typeof v === 'function' && v.constructor && v.constructor.name === 'GeneratorFunction';
    },
    isGeneratorObject: function(v) {
      if (!v || typeof v !== 'object') return false;
      var proto = Object.getPrototypeOf(v);
      if (!proto) return false;
      return typeof proto.next === 'function' && typeof proto.throw === 'function';
    },
    isMapIterator: function(v) {
      try { return Object.prototype.toString.call(v) === '[object Map Iterator]'; }
      catch(e) { return false; }
    },
    isSetIterator: function(v) {
      try { return Object.prototype.toString.call(v) === '[object Set Iterator]'; }
      catch(e) { return false; }
    },
    isWeakMap: function(v) { return v instanceof WeakMap; },
    isWeakSet: function(v) { return v instanceof WeakSet; },
    isDataView: function(v) { return v instanceof DataView; },
    isUint8Array: function(v) { return v instanceof Uint8Array; },
    isUint16Array: function(v) { return v instanceof Uint16Array; },
    isUint32Array: function(v) { return v instanceof Uint32Array; },
    isInt8Array: function(v) { return v instanceof Int8Array; },
    isInt16Array: function(v) { return v instanceof Int16Array; },
    isInt32Array: function(v) { return v instanceof Int32Array; },
    isFloat32Array: function(v) { return v instanceof Float32Array; },
    isFloat64Array: function(v) { return v instanceof Float64Array; },
    isSharedArrayBuffer: function(v) {
      return typeof SharedArrayBuffer !== 'undefined' && v instanceof SharedArrayBuffer;
    },
    isNumberObject: function(v) {
      return typeof v === 'object' && v !== null && Object.prototype.toString.call(v) === '[object Number]';
    },
    isStringObject: function(v) {
      return typeof v === 'object' && v !== null && Object.prototype.toString.call(v) === '[object String]';
    },
    isBooleanObject: function(v) {
      return typeof v === 'object' && v !== null && Object.prototype.toString.call(v) === '[object Boolean]';
    },
    isSymbolObject: function(v) {
      return typeof v === 'object' && v !== null && Object.prototype.toString.call(v) === '[object Symbol]';
    },
    isProxy: function(v) { return false; },
    isExternal: function(v) { return false; },
    isAnyArrayBuffer: function(v) {
      return v instanceof ArrayBuffer || (typeof SharedArrayBuffer !== 'undefined' && v instanceof SharedArrayBuffer);
    }
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

  // --- util.inspect --- delegates to __dun_inspect__ for Node-style formatting
  function inspect(obj, opts) {
    var depth = 2;
    if (opts !== undefined) {
      if (typeof opts === 'number') depth = opts;
      else if (typeof opts === 'object' && opts !== null) {
        if (opts.depth === null || opts.depth === Infinity) depth = 20;
        else if (typeof opts.depth === 'number') depth = opts.depth;
      }
    }
    if (typeof globalThis.__dun_inspect__ === 'function') return globalThis.__dun_inspect__(obj, depth);
    if (obj === null) return 'null';
    if (obj === undefined) return 'undefined';
    if (typeof obj === 'string') return "'" + obj + "'";
    if (typeof obj === 'number' || typeof obj === 'boolean') return String(obj);
    if (typeof obj === 'function') return '[Function: ' + (obj.name || 'anonymous') + ']';
    if (typeof obj === 'symbol') return obj.toString();
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

  // --- util.callbackify ---
  function callbackify(original) {
    if (typeof original !== 'function')
      throw new TypeError('The "original" argument must be of type Function');
    function callbackified() {
      var args = Array.prototype.slice.call(arguments);
      var cb = args.pop();
      if (typeof cb !== 'function')
        throw new TypeError('The last argument must be of type Function');
      original.apply(this, args).then(
        function(ret) { cb(null, ret); },
        function(err) { cb(err || new Error('Promise rejected with falsy value')); }
      );
    }
    return callbackified;
  }

  // --- util.debuglog ---
  function debuglog(section) {
    var enabled = false;
    try {
      var envDebug = typeof process !== 'undefined' && process.env && process.env.NODE_DEBUG;
      if (envDebug) {
        var pat = new RegExp('\\b' + section + '\\b', 'i');
        enabled = pat.test(envDebug);
      }
    } catch(e) {}
    if (enabled) {
      return function() {
        var args = Array.prototype.slice.call(arguments);
        console.error(section.toUpperCase() + ' ' + format.apply(null, args));
      };
    }
    return function() {};
  }

  // --- util._extend (deprecated but widely used) ---
  function _extend(target, source) {
    if (source === null || source === undefined) return target;
    var keys = Object.keys(source);
    for (var i = 0; i < keys.length; i++) target[keys[i]] = source[keys[i]];
    return target;
  }

  // --- util.toUSVString ---
  function toUSVString(val) { return String(val); }

  // --- util.stripVTControlCharacters ---
  function stripVTControlCharacters(str) {
    return String(str).replace(/[\x1b\x9b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g, '');
  }

  var mod = {
    format: format,
    inspect: inspect,
    inherits: inherits,
    promisify: promisify,
    callbackify: callbackify,
    deprecate: deprecate,
    debuglog: debuglog,
    isDeepStrictEqual: isDeepStrictEqual,
    types: types,
    _extend: _extend,
    toUSVString: toUSVString,
    stripVTControlCharacters: stripVTControlCharacters
  };

  // --- util.getSystemErrorName ---
  var errNames = {1:'EPERM',2:'ENOENT',3:'ESRCH',4:'EINTR',5:'EIO',9:'EBADF',11:'EAGAIN',12:'ENOMEM',13:'EACCES',17:'EEXIST',20:'ENOTDIR',21:'EISDIR',22:'EINVAL',28:'ENOSPC',32:'EPIPE',36:'ENAMETOOLONG',38:'ENOSYS',39:'ENOTEMPTY',95:'ENOTSUP',98:'EADDRINUSE',104:'ECONNRESET',110:'ETIMEDOUT',111:'ECONNREFUSED'};
  mod.getSystemErrorName = function(err) { return errNames[-err] || 'Unknown system error ' + err; };

  // --- util.parseArgs ---
  mod.parseArgs = function(config) {
    var args = config && config.args || [];
    var options = config && config.options || {};
    var values = {}, positionals = [];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      if (a.startsWith('--')) {
        var eq = a.indexOf('=');
        var key = eq > 0 ? a.slice(2, eq) : a.slice(2);
        var val = eq > 0 ? a.slice(eq + 1) : true;
        if (options[key] && options[key].type === 'string' && val === true && i + 1 < args.length) val = args[++i];
        values[key] = val;
      } else if (a.startsWith('-') && a.length === 2) {
        values[a[1]] = i + 1 < args.length ? args[++i] : true;
      } else { positionals.push(a); }
    }
    return { values: values, positionals: positionals };
  };

  // --- util.styleText ---
  var styles = {reset:'\x1b[0m',bold:'\x1b[1m',dim:'\x1b[2m',italic:'\x1b[3m',underline:'\x1b[4m',inverse:'\x1b[7m',strikethrough:'\x1b[9m',red:'\x1b[31m',green:'\x1b[32m',yellow:'\x1b[33m',blue:'\x1b[34m',magenta:'\x1b[35m',cyan:'\x1b[36m',white:'\x1b[37m'};
  mod.styleText = function(fmt, text) { var s = styles[fmt]; return s ? s + text + '\x1b[0m' : text; };

  // --- util.MIMEType ---
  mod.MIMEType = function MIMEType(input) {
    var m = String(input).match(/^([^\/]+)\/([^;]+)/);
    this.type = m ? m[1].trim().toLowerCase() : '';
    this.subtype = m ? m[2].trim().toLowerCase() : '';
    this.essence = this.type + '/' + this.subtype;
    this.params = {};
    var rest = String(input).split(';').slice(1);
    for (var i = 0; i < rest.length; i++) {
      var kv = rest[i].split('=');
      if (kv.length === 2) this.params[kv[0].trim()] = kv[1].trim().replace(/^"|"$/g, '');
    }
  };
  mod.MIMEType.prototype.toString = function() { return this.essence; };

  // --- util.aborted ---
  mod.aborted = function(signal, resource) {
    return new Promise(function(resolve) {
      if (signal && signal.aborted) { resolve(signal.reason); return; }
      if (signal && typeof signal.addEventListener === 'function') signal.addEventListener('abort', function() { resolve(signal.reason); }, { once: true });
    });
  };

  // --- util.transferableAbortController / transferableAbortSignal ---
  mod.transferableAbortController = function() { return new AbortController(); };
  mod.transferableAbortSignal = function(reason) { return AbortSignal.abort(reason); };

  // --- util.getCallSites ---
  mod.getCallSites = function() { return []; };

  // TextEncoder/TextDecoder — lazy getters so they resolve after web compat is installed
  Object.defineProperty(mod, 'TextEncoder', {
    get: function() { return typeof globalThis.TextEncoder !== 'undefined' ? globalThis.TextEncoder : undefined; },
    enumerable: true, configurable: true
  });
  Object.defineProperty(mod, 'TextDecoder', {
    get: function() { return typeof globalThis.TextDecoder !== 'undefined' ? globalThis.TextDecoder : undefined; },
    enumerable: true, configurable: true
  });

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_util__ = mod;
  }
})();`;
}
