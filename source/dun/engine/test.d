module dun.engine.test;

version (DunTest):

import dun.engine.iface;

// BDD-style test helpers
private void describe(string what, void delegate() block)
{
    import std.stdio : writeln;
    writeln("  ", what);
    block();
}

private void it(string what, void delegate() block) @trusted
{
    import std.stdio : writeln;
    try
    {
        block();
        writeln("    + ", what);
    }
    catch (Exception e)
    {
        writeln("    x ", what, " -- ", e.msg);
    }
    catch (Error e)
    {
        writeln("    x ", what, " -- ", e.msg);
        throw e;
    }
}

void runEngineContractTests(IJSEngine engine)
{
    auto cfg = EngineConfig(64 * 1024 * 1024, 4 * 1024 * 1024);
    engine.initialize(cfg);
    scope (exit)
        engine.shutdown();

    testValueCreation(engine);
    testTypeChecks(engine);
    testProperties(engine);
    testEval(engine);
    testRefCounting(engine);
    testExceptions(engine);
    testDrainJobs(engine);
    testContextOpaque(engine);
}

private void testValueCreation(IJSEngine e)
{
    describe("value creation", {
        it("creates integers", {
            auto h = e.newInt(42);
            assert(e.extractInt(h) == 42);
            e.freeValue(h);
        });

        it("creates negative integers", {
            auto h = e.newInt(-1);
            assert(e.extractInt(h) == -1);
            e.freeValue(h);
        });

        it("creates zero", {
            auto h = e.newInt(0);
            assert(e.extractInt(h) == 0);
            e.freeValue(h);
        });

        it("creates floats", {
            auto h = e.newFloat(3.14);
            auto v = e.extractFloat(h);
            assert(v > 3.13 && v < 3.15);
            e.freeValue(h);
        });

        it("creates booleans", {
            auto t = e.newBool(true);
            auto f = e.newBool(false);
            assert(e.extractBool(t) == true);
            assert(e.extractBool(f) == false);
            e.freeValue(t);
            e.freeValue(f);
        });

        it("creates strings", {
            auto h = e.newString("hello");
            assert(e.extractString(h) == "hello");
            e.freeValue(h);
        });

        it("creates empty strings", {
            auto h = e.newString("");
            assert(e.extractString(h) == "");
            e.freeValue(h);
        });

        it("creates unicode strings", {
            auto h = e.newString("日本語");
            assert(e.extractString(h) == "日本語");
            e.freeValue(h);
        });

        it("creates objects", {
            auto h = e.newObject();
            assert(e.isObject(h));
            e.freeValue(h);
        });

        it("creates arrays", {
            auto h = e.newArray();
            assert(!e.isNull(h));
            e.freeValue(h);
        });
    });
}

private void testTypeChecks(IJSEngine e)
{
    describe("type checks", {
        it("identifies booleans", {
            auto h = e.newBool(true);
            assert(e.isBool(h));
            assert(!e.isNumber(h));
            assert(!e.isString(h));
            assert(!e.isNull(h));
            assert(!e.isUndefined(h));
            e.freeValue(h);
        });

        it("identifies integers as numbers", {
            auto h = e.newInt(1);
            assert(e.isNumber(h));
            assert(!e.isString(h));
            e.freeValue(h);
        });

        it("identifies floats as numbers", {
            auto h = e.newFloat(1.0);
            assert(e.isNumber(h));
            assert(!e.isString(h));
            e.freeValue(h);
        });

        it("identifies strings", {
            auto h = e.newString("x");
            assert(e.isString(h));
            assert(!e.isNumber(h));
            assert(!e.isBool(h));
            e.freeValue(h);
        });

        it("identifies objects", {
            auto h = e.newObject();
            assert(e.isObject(h));
            assert(!e.isString(h));
            assert(!e.isNumber(h));
            e.freeValue(h);
        });

        it("identifies undefined from eval", {
            auto r = e.eval("undefined", "<test>");
            assert(!r.isError);
            assert(e.isUndefined(r.value));
            e.freeValue(r.value);
        });

        it("identifies null from eval", {
            auto r = e.eval("null", "<test>");
            assert(!r.isError);
            assert(e.isNull(r.value));
            e.freeValue(r.value);
        });

        it("identifies functions from eval", {
            auto r = e.eval("(function(){})", "<test>");
            assert(!r.isError);
            assert(e.isFunction(r.value));
            e.freeValue(r.value);
        });
    });
}

private void testProperties(IJSEngine e)
{
    describe("property access", {
        it("sets and gets integer properties", {
            auto obj = e.newObject();
            auto val = e.newInt(99);
            e.setProperty(obj, "x", val);
            auto got = e.getProperty(obj, "x");
            assert(e.extractInt(got) == 99);
            e.freeValue(got);
            e.freeValue(obj);
        });

        it("sets and gets string properties", {
            auto obj = e.newObject();
            auto val = e.newString("world");
            e.setProperty(obj, "greeting", val);
            auto got = e.getProperty(obj, "greeting");
            assert(e.extractString(got) == "world");
            e.freeValue(got);
            e.freeValue(obj);
        });

        it("returns undefined for missing properties", {
            auto obj = e.newObject();
            auto got = e.getProperty(obj, "nonexistent");
            assert(e.isUndefined(got));
            e.freeValue(got);
            e.freeValue(obj);
        });

        it("accesses global object", {
            auto g = e.getGlobal();
            assert(e.isObject(g));
            e.freeValue(g);
        });

        it("sets global properties visible to eval", {
            auto g = e.getGlobal();
            auto val = e.newInt(777);
            e.setProperty(g, "__test_val", val);
            e.freeValue(g);

            auto r = e.eval("__test_val", "<test>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 777);
            e.freeValue(r.value);
        });
    });
}

private void testEval(IJSEngine e)
{
    describe("eval", {
        it("evaluates arithmetic", {
            auto r = e.eval("1 + 2", "<test>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 3);
            e.freeValue(r.value);
        });

        it("evaluates multiplication", {
            auto r = e.eval("6 * 7", "<test>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 42);
            e.freeValue(r.value);
        });

        it("evaluates string concatenation", {
            auto r = e.eval("'hello' + ' ' + 'world'", "<test>");
            assert(!r.isError);
            assert(e.extractString(r.value) == "hello world");
            e.freeValue(r.value);
        });

        it("evaluates template literals", {
            auto r = e.eval("`sum: ${1+2}`", "<test>");
            assert(!r.isError);
            assert(e.extractString(r.value) == "sum: 3");
            e.freeValue(r.value);
        });

        it("evaluates boolean expressions", {
            auto r = e.eval("true === true", "<test>");
            assert(!r.isError);
            assert(e.extractBool(r.value) == true);
            e.freeValue(r.value);
        });

        it("evaluates object literals", {
            auto r = e.eval("({a: 1})", "<test>");
            assert(!r.isError);
            assert(e.isObject(r.value));
            auto a = e.getProperty(r.value, "a");
            assert(e.extractInt(a) == 1);
            e.freeValue(a);
            e.freeValue(r.value);
        });

        it("evaluates array literals", {
            auto r = e.eval("[1,2,3]", "<test>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("evaluates arrow functions", {
            auto r = e.eval("((x) => x * 2)(21)", "<test>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 42);
            e.freeValue(r.value);
        });

        it("reports syntax errors", {
            auto r = e.eval("function(", "<test>");
            assert(r.isError);
            assert(r.errorMessage.length > 0);
        });

        it("reports reference errors", {
            auto r = e.eval("undefined_var.prop", "<test>");
            assert(r.isError);
        });

        it("reports type errors", {
            auto r = e.eval("null.prop", "<test>");
            assert(r.isError);
        });

        it("evaluates JSON operations", {
            auto r = e.eval("JSON.stringify({a:1})", "<test>");
            assert(!r.isError);
            assert(e.extractString(r.value) == `{"a":1}`);
            e.freeValue(r.value);
        });

        it("evaluates Math operations", {
            auto r = e.eval("Math.max(1, 2, 3)", "<test>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 3);
            e.freeValue(r.value);
        });
    });
}

private void testRefCounting(IJSEngine e)
{
    describe("reference management", {
        it("duplicates values", {
            auto h = e.newString("dup me");
            auto h2 = e.dupValue(h);
            assert(e.extractString(h2) == "dup me");
            e.freeValue(h2);
            e.freeValue(h);
        });

        it("duplicate is independent", {
            auto h = e.newInt(123);
            auto h2 = e.dupValue(h);
            e.freeValue(h);
            assert(e.extractInt(h2) == 123);
            e.freeValue(h2);
        });
    });
}

private void testExceptions(IJSEngine e)
{
    describe("exceptions", {
        it("detects runtime errors", {
            auto r = e.eval("undefined_var.prop", "<test>");
            assert(r.isError);
            assert(r.errorMessage.length > 0);
        });

        it("throws TypeError", {
            auto r = e.eval("null()", "<test>");
            assert(r.isError);
        });

        it("throws RangeError", {
            auto r = e.eval("new Array(-1)", "<test>");
            assert(r.isError);
        });

        it("catches and rethrows", {
            auto r = e.eval("try { throw new Error('test'); } catch(e) { e.message }", "<test>");
            assert(!r.isError);
            assert(e.extractString(r.value) == "test");
            e.freeValue(r.value);
        });
    });
}

private void testDrainJobs(IJSEngine e)
{
    describe("microtask queue", {
        it("drains empty queue without hanging", {
            e.drainJobs();
        });

        it("has no pending jobs initially", {
            assert(!e.hasPendingJobs());
        });

        it("resolves promises via drainJobs", {
            auto r = e.eval("Promise.resolve(42).then(v => globalThis.__promiseResult = v)", "<test>");
            assert(!r.isError);
            e.freeValue(r.value);

            e.drainJobs();

            auto r2 = e.eval("globalThis.__promiseResult", "<test>");
            assert(!r2.isError);
            assert(e.extractInt(r2.value) == 42);
            e.freeValue(r2.value);
        });
    });
}

private void testContextOpaque(IJSEngine e)
{
    describe("context opaque data", {
        it("stores and retrieves opaque pointer", {
            int data = 12345;
            e.setContextOpaque(cast(void*)&data);
            auto got = cast(int*) e.getContextOpaque();
            assert(*got == 12345);
        });
    });
}

// Per-backend test instantiation
version (EngineQuickJS)
{
    @("quickjs: engine contract")
    unittest
    {
        import std.stdio : writeln;
        writeln("QuickJS Engine Contract Tests");
        auto engine = createEngine();
        runEngineContractTests(engine);
    }
}

version (EngineJSC)
{
    @("jsc: engine contract")
    unittest
    {
        import std.stdio : writeln;
        writeln("JSC Engine Contract Tests");
        auto engine = createEngine();
        runEngineContractTests(engine);
    }
}

version (EngineV8)
{
    @("v8: engine contract")
    unittest
    {
        import std.stdio : writeln;
        writeln("V8 Engine Contract Tests");
        auto engine = createEngine();
        runEngineContractTests(engine);
    }
}
