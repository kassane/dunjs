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
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int eventsModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto ee = JS_GetPropertyStr(ctx, global, "__dun_cjs_events__");
        auto eeClass = JS_GetPropertyStr(ctx, ee, "EventEmitter");
        JS_SetModuleExport(ctx, m, "EventEmitter", JS_DupValue(ctx, eeClass));
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

  var mod = { EventEmitter: EventEmitter };
  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_events__ = mod;
    globalThis.EventEmitter = EventEmitter;
  }
})();`;
}
