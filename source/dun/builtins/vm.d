module dun.builtins.vm;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;

/// Number of exported vm API functions
enum VM_EXPORT_COUNT = 6;

void registerVmModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerVmModule");

    auto src = vmSource();
    auto result = engine.eval(src, "<vm>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("vm init failed: ", result.errorMessage);
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
        assert(ctx !is null, "Null context in vm registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:vm", &vmModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "runInThisContext");
        JS_AddModuleExport(ctx, m, "runInNewContext");
        JS_AddModuleExport(ctx, m, "createContext");
        JS_AddModuleExport(ctx, m, "runInContext");
        JS_AddModuleExport(ctx, m, "isContext");
        JS_AddModuleExport(ctx, m, "Script");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int vmModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in vmModuleInit");
        assert(m !is null, "Null JSModuleDef in vmModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_vm__");

        static immutable names = [
            "runInThisContext", "runInNewContext", "createContext",
            "runInContext", "isContext", "Script"
        ];
        static assert(names.length == VM_EXPORT_COUNT, "VM_EXPORT_COUNT mismatch");
        foreach (name; names)
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

string vmSource() pure @safe nothrow
{
    return `(function() {
  'use strict';

  var VM_CONTEXT_MARKER = '__isVmContext';

  function runInThisContext(code, options) {
    if (typeof code !== 'string')
      throw new TypeError('The "code" argument must be of type string');
    return (0, eval)(code);
  }

  function runInNewContext(code, sandbox, options) {
    if (typeof code !== 'string')
      throw new TypeError('The "code" argument must be of type string');
    if (sandbox === undefined || sandbox === null)
      sandbox = {};

    // Use with(sandbox) for proper read/write access to sandbox properties
    var fn = new Function('__sandbox__',
      'return (function(){with(this){return eval(' + JSON.stringify(code) + ')}}).call(__sandbox__);');
    return fn(sandbox);
  }

  function createContext(sandbox) {
    if (sandbox === undefined || sandbox === null)
      sandbox = {};
    if (typeof sandbox !== 'object')
      throw new TypeError('The "sandbox" argument must be an object');
    Object.defineProperty(sandbox, VM_CONTEXT_MARKER, {
      value: true,
      writable: false,
      enumerable: false,
      configurable: false
    });
    return sandbox;
  }

  function runInContext(code, context, options) {
    if (typeof code !== 'string')
      throw new TypeError('The "code" argument must be of type string');
    if (!context || context[VM_CONTEXT_MARKER] !== true)
      throw new TypeError('The "context" argument must be a vm.Context');

    // Reuse the with(this) pattern for context execution
    var fn = new Function('__sandbox__',
      'return (function(){with(this){return eval(' + JSON.stringify(code) + ')}}).call(__sandbox__);');
    return fn(context);
  }

  function isContext(obj) {
    if (obj === null || obj === undefined || typeof obj !== 'object')
      return false;
    return obj[VM_CONTEXT_MARKER] === true;
  }

  // Script class - precompiled script for reuse
  function Script(code, options) {
    if (!(this instanceof Script))
      return new Script(code, options);
    if (typeof code !== 'string')
      throw new TypeError('The "code" argument must be of type string');
    this._code = code;
  }

  Script.prototype.runInThisContext = function(options) {
    return runInThisContext(this._code, options);
  };

  Script.prototype.runInNewContext = function(sandbox, options) {
    return runInNewContext(this._code, sandbox, options);
  };

  Script.prototype.runInContext = function(context, options) {
    return runInContext(this._code, context, options);
  };

  var mod = {
    runInThisContext: runInThisContext,
    runInNewContext: runInNewContext,
    createContext: createContext,
    runInContext: runInContext,
    isContext: isContext,
    Script: Script
  };

  if (typeof globalThis !== 'undefined') {
    globalThis.__dun_cjs_vm__ = mod;
  }
})();`;
}
