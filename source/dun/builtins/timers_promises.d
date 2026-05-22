module dun.builtins.timers_promises;


/++
 + `@trusted policy`: `timers/promises` Node module — Promise-returning
 + variants of setTimeout/setInterval. Every `@trusted` is one of:
 +   1. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +   2. Engine method calls (newPromise, callFunction).
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.builtins.helpers : installPureJsModule;

void registerTimersPromisesModule(IJSEngine engine) @trusted
{
    installPureJsModule(engine, timersPromisesSource(), "<timers_promises>", "timers/promises");

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
        assert(ctx !is null, "Null context in timers_promises registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:timers/promises", &timersPromisesModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "setTimeout");
        JS_AddModuleExport(ctx, m, "setInterval");
        JS_AddModuleExport(ctx, m, "setImmediate");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int timersPromisesModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_timers_promises__");

        JS_SetModuleExport(ctx, m, "setTimeout", JS_GetPropertyStr(ctx, mod, "setTimeout"));
        JS_SetModuleExport(ctx, m, "setInterval", JS_GetPropertyStr(ctx, mod, "setInterval"));
        JS_SetModuleExport(ctx, m, "setImmediate", JS_GetPropertyStr(ctx, mod, "setImmediate"));
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

string timersPromisesSource() pure @safe nothrow
{
    return `(function() {
  function promiseSetTimeout(delay, value) {
    var ms = (typeof delay === 'number') ? delay : 0;
    return new Promise(function(resolve) {
      setTimeout(function() { resolve(value); }, ms);
    });
  }

  function promiseSetImmediate(value) {
    return new Promise(function(resolve) {
      setTimeout(function() { resolve(value); }, 0);
    });
  }

  function promiseSetInterval(delay, value) {
    var ms = (typeof delay === 'number') ? delay : 0;
    // Return an async iterable that yields the value on each interval.
    // For simplicity, this stub yields a single value then completes.
    // A full implementation would require AbortController support.
    var done = false;
    return {
      next: function() {
        if (done) return Promise.resolve({ done: true, value: undefined });
        done = true;
        return new Promise(function(resolve) {
          setTimeout(function() {
            resolve({ done: false, value: value });
          }, ms);
        });
      },
      return: function() {
        done = true;
        return Promise.resolve({ done: true, value: undefined });
      },
      [Symbol.asyncIterator]: function() { return this; }
    };
  }

  var mod = {
    setTimeout: promiseSetTimeout,
    setInterval: promiseSetInterval,
    setImmediate: promiseSetImmediate
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_timers_promises__ = mod;
  }
})();`;
}
