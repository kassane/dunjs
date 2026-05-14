module dun.builtins.perf_hooks;

import dun.engine.iface : IJSEngine, JSHandle;

void registerPerfHooksModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerPerfHooksModule");

    // Evaluate JS source that creates the full perf_hooks module
    auto result = engine.eval(perfHooksSource(), "<perf_hooks>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("perf_hooks init failed: ", result.errorMessage);
        }
        catch (Exception) {}
    }
    engine.freeValue(result.value);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null JSContext in perf_hooks registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:perf_hooks", &perfHooksModuleInit);
        if (m is null) return;
        foreach (name; ["performance", "PerformanceObserver",
                        "monitorEventLoopDelay", "constants", "default"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int perfHooksModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in perfHooksModuleInit");
        assert(m !is null, "Null JSModuleDef in perfHooksModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_perf_hooks__");

        foreach (name; ["performance", "PerformanceObserver",
                        "monitorEventLoopDelay", "constants"])
        {
            auto prop = JS_GetPropertyStr(ctx, mod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, prop);
        }
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string perfHooksSource() pure @safe nothrow
{
    return `(function() {
  // ─── Internal storage for performance entries ───
  var _marks = [];
  var _measures = [];

  // ─── Grab the existing global performance object (installed by web_apis) ───
  var perf = (typeof performance !== 'undefined') ? performance : {};
  if (typeof perf.now !== 'function') {
    var _origin = Date.now();
    perf.now = function() { return Date.now() - _origin; };
  }

  // ─── timeOrigin: startup timestamp in ms since epoch ───
  if (typeof perf.timeOrigin === 'undefined') {
    perf.timeOrigin = Date.now();
  }
  var _timeOrigin = perf.timeOrigin;

  // ─── PerformanceEntry base ───
  function PerformanceEntry(name, entryType, startTime, duration) {
    this.name = name;
    this.entryType = entryType;
    this.startTime = startTime;
    this.duration = duration;
  }
  PerformanceEntry.prototype.toJSON = function() {
    return {
      name: this.name,
      entryType: this.entryType,
      startTime: this.startTime,
      duration: this.duration
    };
  };

  // ─── performance.mark(name, options?) ───
  perf.mark = function(name, options) {
    if (typeof name !== 'string') throw new TypeError('mark name must be a string');
    var startTime = (options && typeof options.startTime === 'number')
      ? options.startTime : perf.now();
    var entry = new PerformanceEntry(name, 'mark', startTime, 0);
    if (options && options.detail !== undefined) entry.detail = options.detail;
    _marks.push(entry);
    return entry;
  };

  // ─── performance.measure(name, startMarkOrOptions?, endMark?) ───
  perf.measure = function(name, startMarkOrOptions, endMark) {
    if (typeof name !== 'string') throw new TypeError('measure name must be a string');
    var startTime = 0;
    var endTime = perf.now();
    var detail;

    if (startMarkOrOptions && typeof startMarkOrOptions === 'object'
        && !Array.isArray(startMarkOrOptions)) {
      // Options object form: measure(name, {start, end, duration, detail})
      var opts = startMarkOrOptions;
      detail = opts.detail;
      if (typeof opts.start === 'string') {
        var sm = _findMark(opts.start);
        if (!sm) throw new DOMException("Failed to execute 'measure': mark '" + opts.start + "' not found", 'SyntaxError');
        startTime = sm.startTime;
      } else if (typeof opts.start === 'number') {
        startTime = opts.start;
      }
      if (typeof opts.end === 'string') {
        var em = _findMark(opts.end);
        if (!em) throw new DOMException("Failed to execute 'measure': mark '" + opts.end + "' not found", 'SyntaxError');
        endTime = em.startTime;
      } else if (typeof opts.end === 'number') {
        endTime = opts.end;
      }
      if (typeof opts.duration === 'number') {
        endTime = startTime + opts.duration;
      }
    } else if (typeof startMarkOrOptions === 'string') {
      // String form: measure(name, startMark, endMark?)
      var sm2 = _findMark(startMarkOrOptions);
      if (!sm2) throw new DOMException("Failed to execute 'measure': mark '" + startMarkOrOptions + "' not found", 'SyntaxError');
      startTime = sm2.startTime;
      if (typeof endMark === 'string') {
        var em2 = _findMark(endMark);
        if (!em2) throw new DOMException("Failed to execute 'measure': mark '" + endMark + "' not found", 'SyntaxError');
        endTime = em2.startTime;
      }
    }

    var duration = endTime - startTime;
    var entry = new PerformanceEntry(name, 'measure', startTime, duration);
    if (detail !== undefined) entry.detail = detail;
    _measures.push(entry);
    return entry;
  };

  function _findMark(name) {
    for (var i = _marks.length - 1; i >= 0; i--) {
      if (_marks[i].name === name) return _marks[i];
    }
    return null;
  }

  // ─── performance.getEntries() ───
  perf.getEntries = function() {
    return _marks.concat(_measures).sort(function(a, b) {
      return a.startTime - b.startTime;
    });
  };

  // ─── performance.getEntriesByName(name, type?) ───
  perf.getEntriesByName = function(name, type) {
    var all = _marks.concat(_measures);
    return all.filter(function(e) {
      if (e.name !== name) return false;
      if (type && e.entryType !== type) return false;
      return true;
    });
  };

  // ─── performance.getEntriesByType(type) ───
  perf.getEntriesByType = function(type) {
    if (type === 'mark') return _marks.slice();
    if (type === 'measure') return _measures.slice();
    return [];
  };

  // ─── performance.clearMarks(name?) ───
  perf.clearMarks = function(name) {
    if (name === undefined) {
      _marks = [];
    } else {
      _marks = _marks.filter(function(e) { return e.name !== name; });
    }
  };

  // ─── performance.clearMeasures(name?) ───
  perf.clearMeasures = function(name) {
    if (name === undefined) {
      _measures = [];
    } else {
      _measures = _measures.filter(function(e) { return e.name !== name; });
    }
  };

  // ─── performance.timerify(fn) ───
  perf.timerify = function(fn) {
    if (typeof fn !== 'function') throw new TypeError('timerify argument must be a function');
    var wrapped = function() {
      var start = perf.now();
      var result = fn.apply(this, arguments);
      var duration = perf.now() - start;
      var entry = new PerformanceEntry(fn.name || 'anonymous', 'function', start, duration);
      _measures.push(entry);
      return result;
    };
    Object.defineProperty(wrapped, 'name', { value: fn.name, configurable: true });
    Object.defineProperty(wrapped, 'length', { value: fn.length, configurable: true });
    return wrapped;
  };

  // ─── PerformanceObserver ───
  function PerformanceObserver(callback) {
    if (typeof callback !== 'function') throw new TypeError('PerformanceObserver callback must be a function');
    this._callback = callback;
    this._entryTypes = [];
    this._active = false;
    this._buffer = [];
  }

  PerformanceObserver.prototype.observe = function(options) {
    if (options && options.entryTypes) {
      this._entryTypes = options.entryTypes;
    } else if (options && options.type) {
      this._entryTypes = [options.type];
    }
    this._active = true;
  };

  PerformanceObserver.prototype.disconnect = function() {
    this._active = false;
    this._entryTypes = [];
    this._buffer = [];
  };

  PerformanceObserver.prototype.takeRecords = function() {
    var records = this._buffer.slice();
    this._buffer = [];
    return records;
  };

  PerformanceObserver.supportedEntryTypes = ['mark', 'measure', 'function'];

  // ─── monitorEventLoopDelay ───
  function monitorEventLoopDelay(options) {
    var resolution = (options && options.resolution) ? options.resolution : 10;
    return {
      resolution: resolution,
      enable: function() {},
      disable: function() {},
      reset: function() {},
      percentile: function(p) { return 0; },
      percentiles: new Map(),
      min: 0,
      max: 0,
      mean: 0,
      stddev: 0,
      exceeds: 0
    };
  }

  // ─── constants ───
  var constants = {
    NODE_PERFORMANCE_GC_MAJOR: 4,
    NODE_PERFORMANCE_GC_MINOR: 1,
    NODE_PERFORMANCE_GC_INCREMENTAL: 8,
    NODE_PERFORMANCE_GC_WEAKCB: 16,
    NODE_PERFORMANCE_GC_FLAGS_NO: 0,
    NODE_PERFORMANCE_GC_FLAGS_CONSTRUCT_CB: 1,
    NODE_PERFORMANCE_GC_FLAGS_FORCED: 2,
    NODE_PERFORMANCE_GC_FLAGS_SYNCHRONOUS_PHANTOM_PROCESSING: 4,
    NODE_PERFORMANCE_GC_FLAGS_ALL_AVAILABLE_GARBAGE: 8,
    NODE_PERFORMANCE_GC_FLAGS_ALL_EXTERNAL_MEMORY: 16,
    NODE_PERFORMANCE_GC_FLAGS_SCHEDULE_IDLE: 32
  };

  // ─── Build module object ───
  var mod = {
    performance: perf,
    PerformanceObserver: PerformanceObserver,
    PerformanceEntry: PerformanceEntry,
    monitorEventLoopDelay: monitorEventLoopDelay,
    constants: constants
  };

  // Wire up for CJS require('perf_hooks')
  globalThis.__dun_cjs_perf_hooks__ = mod;
})()`;
}
