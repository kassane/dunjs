module dun.builtins.assert_;


/++
 + `@trusted policy`: Node's `assert` module — `assert`, `deepEqual`,
 + `throws`, etc. Every `@trusted` is one of:
 +   1. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +   2. Engine method calls for value introspection + AssertionError
 +      construction.
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.builtins.helpers : installPureJsModule;

void registerAssertModule(IJSEngine engine) @trusted
{
    installPureJsModule(engine, assertSource(), "<assert>", "assert");

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
        assert(ctx !is null, "Null context in assert registerQuickJSModule");
        auto m = JS_NewCModule(ctx, "dun:assert", &assertModuleInit);
        if (m is null) return;
        JS_AddModuleExport(ctx, m, "default");
        JS_AddModuleExport(ctx, m, "ok");
        JS_AddModuleExport(ctx, m, "equal");
        JS_AddModuleExport(ctx, m, "notEqual");
        JS_AddModuleExport(ctx, m, "strictEqual");
        JS_AddModuleExport(ctx, m, "notStrictEqual");
        JS_AddModuleExport(ctx, m, "deepEqual");
        JS_AddModuleExport(ctx, m, "deepStrictEqual");
        JS_AddModuleExport(ctx, m, "notDeepEqual");
        JS_AddModuleExport(ctx, m, "notDeepStrictEqual");
        JS_AddModuleExport(ctx, m, "throws");
        JS_AddModuleExport(ctx, m, "doesNotThrow");
        JS_AddModuleExport(ctx, m, "rejects");
        JS_AddModuleExport(ctx, m, "doesNotReject");
        JS_AddModuleExport(ctx, m, "match");
        JS_AddModuleExport(ctx, m, "doesNotMatch");
        JS_AddModuleExport(ctx, m, "fail");
        JS_AddModuleExport(ctx, m, "ifError");
        JS_AddModuleExport(ctx, m, "AssertionError");
        JS_AddModuleExport(ctx, m, "strict");
    }

    private extern(C) int assertModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null ctx in assertModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto assertMod = JS_GetPropertyStr(ctx, global, "__dun_cjs_assert__");
        JS_FreeValue(ctx, global);

        JS_SetModuleExport(ctx, m, "default", JS_DupValue(ctx, assertMod));
        static immutable names = [
            "ok", "equal", "notEqual", "strictEqual", "notStrictEqual",
            "deepEqual", "deepStrictEqual", "notDeepEqual", "notDeepStrictEqual",
            "throws", "doesNotThrow", "rejects", "doesNotReject",
            "match", "doesNotMatch", "fail", "ifError", "AssertionError", "strict"
        ];
        foreach (name; names)
        {
            auto val = JS_GetPropertyStr(ctx, assertMod, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, val);
        }
        JS_FreeValue(ctx, assertMod);
        return 0;
    }
}

private string assertSource() pure nothrow @safe
{
    return `(function() {
    'use strict';

    class AssertionError extends Error {
        constructor(opts) {
            var msg = opts && opts.message ? opts.message :
                      opts ? 'Expected ' + JSON.stringify(opts.expected) +
                            ' ' + opts.operator + ' ' + JSON.stringify(opts.actual)
                          : 'Assertion failed';
            super(msg);
            this.name = 'AssertionError';
            this.code = 'ERR_ASSERTION';
            if (opts) {
                this.actual = opts.actual;
                this.expected = opts.expected;
                this.operator = opts.operator;
            }
        }
    }

    function deepEqual(a, b) {
        if (a === b) return true;
        if (a === null || b === null) return false;
        if (typeof a !== typeof b) return false;
        if (typeof a !== 'object') return a === b;
        if (Array.isArray(a)) {
            if (!Array.isArray(b) || a.length !== b.length) return false;
            for (var i = 0; i < a.length; i++) {
                if (!deepEqual(a[i], b[i])) return false;
            }
            return true;
        }
        var ka = Object.keys(a), kb = Object.keys(b);
        if (ka.length !== kb.length) return false;
        for (var i = 0; i < ka.length; i++) {
            if (!deepEqual(a[ka[i]], b[ka[i]])) return false;
        }
        return true;
    }

    function assertFn(value, message) {
        if (!value) throw new AssertionError({
            message: message || 'Assertion failed',
            actual: value, expected: true, operator: '=='
        });
    }

    assertFn.ok = function ok(value, message) {
        if (!value) throw new AssertionError({
            message: message || 'Expected truthy value',
            actual: value, expected: true, operator: '=='
        });
    };

    assertFn.equal = function equal(actual, expected, message) {
        if (actual != expected) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: '=='
        });
    };

    assertFn.notEqual = function notEqual(actual, expected, message) {
        if (actual == expected) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: '!='
        });
    };

    assertFn.strictEqual = function strictEqual(actual, expected, message) {
        if (actual !== expected) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: '==='
        });
    };

    assertFn.notStrictEqual = function notStrictEqual(actual, expected, message) {
        if (actual === expected) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: '!=='
        });
    };

    assertFn.deepEqual = function deepEqualFn(actual, expected, message) {
        if (!deepEqual(actual, expected)) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: 'deepEqual'
        });
    };

    assertFn.deepStrictEqual = function deepStrictEqualFn(actual, expected, message) {
        if (!deepEqual(actual, expected)) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: 'deepStrictEqual'
        });
    };

    assertFn.throws = function throws(fn, expectedErr, message) {
        var threw = false;
        try { fn(); } catch(e) {
            threw = true;
            if (expectedErr) {
                if (typeof expectedErr === 'function') {
                    if (!(e instanceof expectedErr)) throw new AssertionError({
                        message: message || 'Wrong error type',
                        actual: e, expected: expectedErr, operator: 'throws'
                    });
                } else if (expectedErr instanceof RegExp) {
                    if (!expectedErr.test(e.message)) throw new AssertionError({
                        message: message || 'Error message mismatch',
                        actual: e.message, expected: expectedErr, operator: 'throws'
                    });
                }
            }
        }
        if (!threw) throw new AssertionError({
            message: message || 'Expected function to throw',
            operator: 'throws'
        });
    };

    assertFn.doesNotThrow = function doesNotThrow(fn, message) {
        try { fn(); } catch(e) {
            throw new AssertionError({
                message: message || 'Expected function not to throw: ' + e.message,
                actual: e, operator: 'doesNotThrow'
            });
        }
    };

    assertFn.rejects = async function rejects(asyncFn, expectedErr, message) {
        var threw = false;
        try {
            var p = typeof asyncFn === 'function' ? asyncFn() : asyncFn;
            await p;
        } catch(e) {
            threw = true;
            if (expectedErr && typeof expectedErr === 'function') {
                if (!(e instanceof expectedErr)) throw new AssertionError({
                    message: message || 'Wrong rejection type',
                    actual: e, expected: expectedErr, operator: 'rejects'
                });
            }
        }
        if (!threw) throw new AssertionError({
            message: message || 'Expected promise to reject',
            operator: 'rejects'
        });
    };

    assertFn.match = function match(string, regexp, message) {
        if (!regexp.test(string)) throw new AssertionError({
            message: message || 'String does not match regexp',
            actual: string, expected: regexp, operator: 'match'
        });
    };

    assertFn.notDeepEqual = function notDeepEqual(actual, expected, message) {
        if (deepEqual(actual, expected)) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: 'notDeepEqual'
        });
    };

    assertFn.notDeepStrictEqual = function notDeepStrictEqual(actual, expected, message) {
        if (deepEqual(actual, expected)) throw new AssertionError({
            message: message, actual: actual, expected: expected, operator: 'notDeepStrictEqual'
        });
    };

    assertFn.doesNotMatch = function doesNotMatch(string, regexp, message) {
        if (regexp.test(string)) throw new AssertionError({
            message: message || 'String should not match regexp',
            actual: string, expected: regexp, operator: 'doesNotMatch'
        });
    };

    assertFn.doesNotReject = async function doesNotReject(asyncFn, expectedErr, message) {
        try {
            var p = typeof asyncFn === 'function' ? asyncFn() : asyncFn;
            await p;
        } catch(e) {
            throw new AssertionError({
                message: message || 'Expected promise not to reject: ' + e.message,
                actual: e, operator: 'doesNotReject'
            });
        }
    };

    assertFn.ifError = function ifError(value) {
        if (value !== null && value !== undefined) {
            throw value instanceof Error ? value : new AssertionError({
                message: 'ifError got unwanted value: ' + value,
                actual: value, operator: 'ifError'
            });
        }
    };

    assertFn.fail = function fail(message) {
        throw new AssertionError({
            message: message || 'Assertion failed',
            operator: 'fail'
        });
    };

    assertFn.AssertionError = AssertionError;

    // assert.strict is a reference to itself (all methods are strict in our impl)
    assertFn.strict = assertFn;
    assertFn.strict.strict = assertFn;

    globalThis.__dun_cjs_assert__ = assertFn;
})();`;
}
