module dun.builtins.events;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

void registerEventsModule(IJSEngine engine) @trusted
{
    auto global = engine.getGlobal();

    // EventEmitter is implemented in JS since it's mostly data structure logic.
    // This avoids complex D<->JS callback management for .on()/.emit().
    auto src = eventEmitterSource();
    auto result = engine.eval(src, "<events>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("EventEmitter init failed: ", result.errorMessage);
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
        auto m = JS_NewCModule(ctx, "dun:events", &eventsModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "EventEmitter");
        JS_AddModuleExport(ctx, m, "once");
        JS_AddModuleExport(ctx, m, "on");
        JS_AddModuleExport(ctx, m, "getEventListeners");
        JS_AddModuleExport(ctx, m, "getMaxListeners");
        JS_AddModuleExport(ctx, m, "setMaxListeners");
        JS_AddModuleExport(ctx, m, "addAbortListener");
        JS_AddModuleExport(ctx, m, "captureRejectionSymbol");
        JS_AddModuleExport(ctx, m, "captureRejections");
        JS_AddModuleExport(ctx, m, "errorMonitor");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int eventsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto ee = JS_GetPropertyStr(ctx, global, "__dun_cjs_events__");
        auto eeClass = JS_GetPropertyStr(ctx, ee, "EventEmitter");
        auto onceFn = JS_GetPropertyStr(ctx, ee, "once");
        auto onFn = JS_GetPropertyStr(ctx, ee, "on");
        JS_SetModuleExport(ctx, m, "EventEmitter", JS_DupValue(ctx, eeClass));
        JS_SetModuleExport(ctx, m, "once", onceFn);
        JS_SetModuleExport(ctx, m, "on", onFn);
        foreach (name; ["getEventListeners", "getMaxListeners", "setMaxListeners", "addAbortListener",
                        "captureRejectionSymbol", "captureRejections", "errorMonitor"])
        {
            auto val = JS_GetPropertyStr(ctx, ee, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, val);
        }
        JS_SetModuleExport(ctx, m, "default", ee);
        JS_FreeValue(ctx, eeClass);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string eventEmitterSource() pure @safe nothrow
{
    return `(function() {
  function EventEmitter() {
    this._events = {};
    this._maxListeners = 10;
  }

  EventEmitter.prototype.on = function(event, listener) {
    if (typeof listener !== 'function')
      throw new TypeError('listener must be a function');
    if (!this._events[event]) this._events[event] = [];
    var listeners = this._events[event];
    if (listeners.length >= this._maxListeners && this._maxListeners > 0)
      console.warn('MaxListenersExceededWarning: ' + event);
    listeners.push({ fn: listener, once: false });
    return this;
  };

  EventEmitter.prototype.addListener = EventEmitter.prototype.on;

  EventEmitter.prototype.once = function(event, listener) {
    if (typeof listener !== 'function')
      throw new TypeError('listener must be a function');
    if (!this._events[event]) this._events[event] = [];
    this._events[event].push({ fn: listener, once: true });
    return this;
  };

  EventEmitter.prototype.off = function(event, listener) {
    if (!this._events[event]) return this;
    var arr = this._events[event];
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].fn === listener) {
        arr.splice(i, 1);
        break;
      }
    }
    if (arr.length === 0) delete this._events[event];
    return this;
  };

  EventEmitter.prototype.removeListener = EventEmitter.prototype.off;

  EventEmitter.prototype.removeAllListeners = function(event) {
    if (event !== undefined) delete this._events[event];
    else this._events = {};
    return this;
  };

  EventEmitter.prototype.emit = function(event) {
    if (!this._events[event]) return false;
    var listeners = this._events[event].slice();
    var args = [];
    for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
    for (var j = 0; j < listeners.length; j++) {
      try {
        listeners[j].fn.apply(this, args);
      } catch (e) {
        if (event !== 'error') this.emit('error', e);
        else throw e;
      }
      if (listeners[j].once) this.off(event, listeners[j].fn);
    }
    return true;
  };

  EventEmitter.prototype.listenerCount = function(event) {
    return this._events[event] ? this._events[event].length : 0;
  };

  EventEmitter.prototype.listeners = function(event) {
    if (!this._events[event]) return [];
    return this._events[event].map(function(l) { return l.fn; });
  };

  EventEmitter.prototype.rawListeners = function(event) {
    if (!this._events[event]) return [];
    return this._events[event].slice();
  };

  EventEmitter.prototype.eventNames = function() {
    return Object.keys(this._events);
  };

  EventEmitter.prototype.setMaxListeners = function(n) {
    this._maxListeners = n;
    return this;
  };

  EventEmitter.prototype.getMaxListeners = function() {
    return this._maxListeners;
  };

  EventEmitter.prototype.prependListener = function(event, listener) {
    if (typeof listener !== 'function')
      throw new TypeError('listener must be a function');
    if (!this._events[event]) this._events[event] = [];
    this._events[event].unshift({ fn: listener, once: false });
    return this;
  };

  EventEmitter.prototype.prependOnceListener = function(event, listener) {
    if (typeof listener !== 'function')
      throw new TypeError('listener must be a function');
    if (!this._events[event]) this._events[event] = [];
    this._events[event].unshift({ fn: listener, once: true });
    return this;
  };

  EventEmitter.defaultMaxListeners = 10;

  EventEmitter.listenerCount = function(emitter, eventName) {
    if (emitter && typeof emitter.listenerCount === 'function') {
      return emitter.listenerCount(eventName);
    }
    return 0;
  };

  function once(emitter, event, options) {
    return new Promise(function(resolve, reject) {
      var signal = options && options.signal;
      if (signal && signal.aborted) {
        reject(signal.reason || new Error('AbortError'));
        return;
      }
      function onEvent() {
        cleanup();
        var args = [];
        for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
        resolve(args);
      }
      function onError(err) {
        cleanup();
        reject(err);
      }
      function cleanup() {
        emitter.removeListener(event, onEvent);
        if (event !== 'error') emitter.removeListener('error', onError);
      }
      emitter.once(event, onEvent);
      if (event !== 'error') emitter.once('error', onError);
    });
  }

  EventEmitter.once = once;

  function on(emitter, event, options) {
    var signal = options && options.signal;
    var unconsumedEvents = [];
    var unconsumedPromises = [];
    var done = false;
    var error = null;

    function eventHandler() {
      var args = [];
      for (var i = 0; i < arguments.length; i++) args.push(arguments[i]);
      if (unconsumedPromises.length > 0) {
        var resolve = unconsumedPromises.shift();
        resolve({ value: args, done: false });
      } else {
        unconsumedEvents.push(args);
      }
    }

    function errorHandler(err) {
      error = err;
      done = true;
      while (unconsumedPromises.length > 0) {
        var reject = unconsumedPromises.shift();
        reject(err);
      }
    }

    emitter.on(event, eventHandler);
    if (event !== 'error') emitter.on('error', errorHandler);

    if (signal) {
      signal.addEventListener('abort', function() {
        done = true;
        emitter.removeListener(event, eventHandler);
        if (event !== 'error') emitter.removeListener('error', errorHandler);
        while (unconsumedPromises.length > 0) {
          var reject = unconsumedPromises.shift();
          reject(signal.reason || new Error('AbortError'));
        }
      });
    }

    var iterator = {};
    iterator.next = function() {
      if (unconsumedEvents.length > 0) {
        return Promise.resolve({ value: unconsumedEvents.shift(), done: false });
      }
      if (done) {
        if (error) return Promise.reject(error);
        return Promise.resolve({ value: undefined, done: true });
      }
      return new Promise(function(resolve, reject) {
        unconsumedPromises.push(function(result) {
          if (result && result.done === false) resolve(result);
          else resolve({ value: undefined, done: true });
        });
      });
    };
    iterator['return'] = function() {
      done = true;
      emitter.removeListener(event, eventHandler);
      if (event !== 'error') emitter.removeListener('error', errorHandler);
      return Promise.resolve({ value: undefined, done: true });
    };
    iterator[Symbol.asyncIterator] = function() { return iterator; };
    return iterator;
  }

  EventEmitter.on = on;

  EventEmitter.getEventListeners = function(emitterOrTarget, eventName) {
    if (emitterOrTarget && typeof emitterOrTarget.listeners === 'function') return emitterOrTarget.listeners(eventName);
    return [];
  };
  EventEmitter.getMaxListeners = function(emitterOrTarget) {
    if (emitterOrTarget && typeof emitterOrTarget.getMaxListeners === 'function') return emitterOrTarget.getMaxListeners();
    return EventEmitter.defaultMaxListeners;
  };
  EventEmitter.setMaxListeners = function(n) { EventEmitter.defaultMaxListeners = n; };
  EventEmitter.addAbortListener = function(signal, listener) {
    if (signal && typeof signal.addEventListener === 'function') signal.addEventListener('abort', listener);
    return { [Symbol.dispose]: function() { if (signal && typeof signal.removeEventListener === 'function') signal.removeEventListener('abort', listener); } };
  };

  EventEmitter.captureRejectionSymbol = Symbol.for('nodejs.rejection');
  EventEmitter.captureRejections = false;
  EventEmitter.errorMonitor = Symbol.for('events.errorMonitor');

  var mod = { EventEmitter: EventEmitter, once: once, on: on,
              getEventListeners: EventEmitter.getEventListeners,
              getMaxListeners: EventEmitter.getMaxListeners,
              setMaxListeners: EventEmitter.setMaxListeners,
              addAbortListener: EventEmitter.addAbortListener,
              captureRejectionSymbol: EventEmitter.captureRejectionSymbol,
              captureRejections: EventEmitter.captureRejections,
              errorMonitor: EventEmitter.errorMonitor };
  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_events__ = mod;
    globalThis.EventEmitter = EventEmitter;
  }
})();`;
}
