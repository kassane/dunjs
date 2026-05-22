module dun.builtins.async_hooks;


/++
 + `@trusted policy`: Node's `async_hooks` module + AsyncLocalStorage.
 + Every `@trusted` is one of:
 +   1. `__gshared alsStoreStack` for the AsyncLocalStorage stack
 +      (single-threaded under the engine's main-thread-only contract).
 +   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +   3. `catch (Throwable)` for the recovery path — required because
 +      ALS unwinds across user-supplied callbacks that may throw
 +      Errors (not just Exceptions).
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;

/// Maximum nesting depth for AsyncLocalStorage.run() calls.
private enum MAX_ALS_STACK_DEPTH = 256;

/// Module-level store stack for AsyncLocalStorage (single-threaded runtime).
private __gshared JSHandle[] alsStoreStack;

void registerAsyncHooksModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerAsyncHooksModule");

    // Register native helper functions as globals
    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_als_run",
        engine.newFunction(&jsAlsRun, "__dun_als_run", 2));
    engine.setProperty(global, "__dun_als_getStore",
        engine.newFunction(&jsAlsGetStore, "__dun_als_getStore", 0));
    engine.setProperty(global, "__dun_als_enterWith",
        engine.newFunction(&jsAlsEnterWith, "__dun_als_enterWith", 1));
    engine.setProperty(global, "__dun_als_disable",
        engine.newFunction(&jsAlsDisable, "__dun_als_disable", 0));
    engine.freeValue(global);

    // Evaluate JS source that creates the AsyncLocalStorage constructor
    auto src = asyncHooksSource();
    auto result = engine.eval(src, "<async_hooks>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("async_hooks init failed: ", result.errorMessage);
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
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null JSContext in async_hooks registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:async_hooks", &asyncHooksModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "AsyncLocalStorage");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int asyncHooksModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in asyncHooksModuleInit");
        assert(m !is null, "Null JSModuleDef in asyncHooksModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_async_hooks__");

        auto als = JS_GetPropertyStr(ctx, mod, "AsyncLocalStorage");
        JS_SetModuleExport(ctx, m, "AsyncLocalStorage", als);
        JS_SetModuleExport(ctx, m, "default", mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

/// JS source that creates the AsyncLocalStorage constructor using native helpers.
string asyncHooksSource() pure @safe nothrow
{
    return `(function() {
  function AsyncLocalStorage() {
    // Each instance is a plain object -- the store stack is global (single-threaded)
  }

  AsyncLocalStorage.prototype.run = function(store, callback) {
    var args = [];
    for (var i = 2; i < arguments.length; i++) {
      args.push(arguments[i]);
    }
    return __dun_als_run(store, function() {
      return callback.apply(undefined, args);
    });
  };

  AsyncLocalStorage.prototype.getStore = function() {
    return __dun_als_getStore();
  };

  AsyncLocalStorage.prototype.enterWith = function(store) {
    return __dun_als_enterWith(store);
  };

  AsyncLocalStorage.prototype.disable = function() {
    return __dun_als_disable();
  };

  var mod = {
    AsyncLocalStorage: AsyncLocalStorage
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_async_hooks__ = mod;
  }
})();`;
}

/// als.run(store, callback): push store, call callback, pop store
JSHandle jsAlsRun(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsAlsRun");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsAlsRun");

    if (args.length < 2)
        return engine.throwTypeError("AsyncLocalStorage.run requires (store, callback)");

    if (!engine.isFunction(args[1]))
        return engine.throwTypeError("AsyncLocalStorage.run callback must be a function");

    assert(alsStoreStack.length < MAX_ALS_STACK_DEPTH,
        "AsyncLocalStorage stack overflow: exceeded maximum nesting depth");

    // Push store onto stack
    alsStoreStack ~= engine.dupValue(args[0]);

    // Call callback, ensuring stack is popped even on exception
    JSHandle result;
    bool hasResult = false;
    try
    {
        JSHandle[] noArgs;
        result = engine.callFunction(args[1], engine.newUndefined(), noArgs);
        hasResult = true;
    }
    catch (Throwable)
    {
        // Pop store on exception
        if (alsStoreStack.length > 0)
        {
            engine.freeValue(alsStoreStack[$ - 1]);
            alsStoreStack = alsStoreStack[0 .. $ - 1];
        }
        return engine.newUndefined();
    }

    // Pop store after successful call
    if (alsStoreStack.length > 0)
    {
        engine.freeValue(alsStoreStack[$ - 1]);
        alsStoreStack = alsStoreStack[0 .. $ - 1];
    }

    if (hasResult)
        return result;
    return engine.newUndefined();
}

/// als.getStore(): return top of stack (or undefined if empty)
JSHandle jsAlsGetStore(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsAlsGetStore");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsAlsGetStore");

    if (alsStoreStack.length == 0)
        return engine.newUndefined();

    return engine.dupValue(alsStoreStack[$ - 1]);
}

/// als.enterWith(store): push store (doesn't auto-pop)
JSHandle jsAlsEnterWith(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsAlsEnterWith");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsAlsEnterWith");

    if (args.length < 1)
        return engine.throwTypeError("AsyncLocalStorage.enterWith requires a store argument");

    assert(alsStoreStack.length < MAX_ALS_STACK_DEPTH,
        "AsyncLocalStorage stack overflow: exceeded maximum nesting depth");

    alsStoreStack ~= engine.dupValue(args[0]);
    return engine.newUndefined();
}

/// als.disable(): clear entire stack
JSHandle jsAlsDisable(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state !is null, "Null DunState in jsAlsDisable");
    auto engine = state.engine;
    assert(engine !is null, "Null engine in jsAlsDisable");

    foreach (ref h; alsStoreStack)
        engine.freeValue(h);
    alsStoreStack = null;

    return engine.newUndefined();
}
