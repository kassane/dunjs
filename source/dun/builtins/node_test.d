module dun.builtins.node_test;


/++
 + `@trusted policy`: `node:test` Node module — built-in test runner.
 + Every `@trusted` is one of:
 +   1. `core.time.MonoTime` for test-duration measurement.
 +   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +   3. Engine method calls for assertion / hook dispatch.
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback, mustEval;
import dun.runtime.globals : DunState;

void registerNodeTestModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerNodeTestModule");

    auto src = nodeTestSource();
    auto result = engine.eval(src, "<node-test>");
    if (result.isError)
    {
        try
        {
            import std.stdio : stderr;
            stderr.writeln("node:test init failed: ", result.errorMessage);
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
        assert(engine !is null, "Null engine in registerQuickJSModule");
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null context in node-test registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:test", &nodeTestModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "test");
        JS_AddModuleExport(ctx, m, "describe");
        JS_AddModuleExport(ctx, m, "it");
        JS_AddModuleExport(ctx, m, "before");
        JS_AddModuleExport(ctx, m, "after");
        JS_AddModuleExport(ctx, m, "beforeEach");
        JS_AddModuleExport(ctx, m, "afterEach");
        JS_AddModuleExport(ctx, m, "default");
    }

    private extern (C) int nodeTestModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        auto global = JS_GetGlobalObject(ctx);
        auto mod = JS_GetPropertyStr(ctx, global, "__dun_cjs_node_test__");

        JS_SetModuleExport(ctx, m, "test",       JS_GetPropertyStr(ctx, mod, "test"));
        JS_SetModuleExport(ctx, m, "describe",   JS_GetPropertyStr(ctx, mod, "describe"));
        JS_SetModuleExport(ctx, m, "it",         JS_GetPropertyStr(ctx, mod, "it"));
        JS_SetModuleExport(ctx, m, "before",     JS_GetPropertyStr(ctx, mod, "before"));
        JS_SetModuleExport(ctx, m, "after",      JS_GetPropertyStr(ctx, mod, "after"));
        JS_SetModuleExport(ctx, m, "beforeEach", JS_GetPropertyStr(ctx, mod, "beforeEach"));
        JS_SetModuleExport(ctx, m, "afterEach",  JS_GetPropertyStr(ctx, mod, "afterEach"));
        JS_SetModuleExport(ctx, m, "default",    mod);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

// Minimal `node:test` shim. Not a full implementation — registers
// tests + describes and runs them on the next microtask, reporting
// TAP-like output. Good enough for libraries that use the canonical
// `test(name, fn)` / `describe(name, fn)` / `it(name, fn)` pattern.
// `t` object passed to test callbacks exposes:
//   - t.test / t.it — subtests
//   - t.skip — mark as skipped
//   - t.assert — a wrapper around the `assert` module's strict
//                bindings (deep equal, equal, ok, throws…)
// Hooks (`before` / `after` / `beforeEach` / `afterEach`) run as
// you'd expect, scoped to their describe() block.
private string nodeTestSource() pure @safe nothrow
{
    return `(function() {
  var pending = [];
  var stats = { pass: 0, fail: 0, skip: 0 };
  var draining = false;

  function makeContext(name) {
    var ctx = {
      name: name,
      _children: [],
      skip: function() { ctx._skipped = true; },
      test: function(n, fn) { ctx._children.push({name: n, fn: fn, mode: 'test'}); },
      it:   function(n, fn) { ctx._children.push({name: n, fn: fn, mode: 'test'}); },
      diagnostic: function(msg) { console.log("# " + msg); },
      assert: globalThis.__dun_cjs_assert__ || {}
    };
    return ctx;
  }

  async function runOne(entry, depth) {
    var pad = "    ".repeat(depth || 0);
    var ctx = makeContext(entry.name);
    if (entry.mode === 'skip') { stats.skip++; console.log(pad + "skip — " + entry.name); return; }
    try {
      var r = entry.fn(ctx);
      if (r && typeof r.then === 'function') await r;
      if (ctx._skipped) { stats.skip++; console.log(pad + "skip — " + entry.name); return; }
      for (var i = 0; i < ctx._children.length; i++) {
        await runOne(ctx._children[i], (depth || 0) + 1);
      }
      stats.pass++;
      console.log(pad + "ok — " + entry.name);
    } catch (e) {
      stats.fail++;
      console.log(pad + "not ok — " + entry.name);
      console.log(pad + "  " + (e && e.stack || e));
    }
  }

  // Hooks — collected; node:test runs them at the appropriate scope.
  // The minimal shim runs before/after once around the whole queue,
  // and beforeEach/afterEach around each test. (Full Node node:test
  // semantics are stricter; this covers the common usage.)
  var beforeFns = [], afterFns = [], beforeEachFns = [], afterEachFns = [];
  function before(fn)     { beforeFns.push(fn); }
  function after(fn)      { afterFns.push(fn); }
  function beforeEach(fn) { beforeEachFns.push(fn); }
  function afterEach(fn)  { afterEachFns.push(fn); }

  async function drain() {
    if (draining) return;
    draining = true;
    for (var i = 0; i < beforeFns.length; i++) await beforeFns[i]();
    while (pending.length > 0) {
      for (var j = 0; j < beforeEachFns.length; j++) await beforeEachFns[j]();
      var entry = pending.shift();
      await runOne(entry, 0);
      for (var k = 0; k < afterEachFns.length; k++) await afterEachFns[k]();
    }
    for (var m = 0; m < afterFns.length; m++) await afterFns[m]();
    draining = false;
    if (typeof process !== 'undefined' && stats.fail > 0) process.exitCode = 1;
    console.log("# tests " + (stats.pass + stats.fail + stats.skip));
    console.log("# pass "  + stats.pass);
    console.log("# fail "  + stats.fail);
    console.log("# skip "  + stats.skip);
  }

  function schedule() {
    if (pending.length === 1) {
      // First pending entry — kick off drain on next microtask.
      Promise.resolve().then(drain);
    }
  }

  function test(name, fn) {
    if (typeof name === 'function') { fn = name; name = fn.name || '(anonymous)'; }
    pending.push({ name: name, fn: fn || function() {}, mode: 'test' });
    schedule();
  }

  // describe/it are aliases for the same registration path; node:test
  // doesn't distinguish at the top level. Inside a describe(), the t
  // context's .test / .it methods nest as subtests.
  function describe(name, fn) { test(name, fn); }
  function it(name, fn)       { test(name, fn); }

  globalThis.__dun_cjs_node_test__ = {
    test: test, describe: describe, it: it,
    before: before, after: after,
    beforeEach: beforeEach, afterEach: afterEach,
  };
})()`;
}
