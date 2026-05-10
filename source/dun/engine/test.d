module dun.engine.test;

version (DunTest):

import dun.engine.iface;

// BDD-style test helpers
private void describe(string what, void delegate() block)
{
    block();
}

private void it(string what, void delegate() block)
{
    block();
}

// ---------------------------------------------------------------------------
// IJSEngine contract tests — each backend must pass these
// ---------------------------------------------------------------------------

void runEngineContractTests(IJSEngine engine)
{
    auto cfg = EngineConfig(64 * 1024 * 1024, 4 * 1024 * 1024);
    engine.initialize(cfg);
    scope (exit) engine.shutdown();

    testValueCreation(engine);
    testTypeChecks(engine);
    testProperties(engine);
    testEval(engine);
    testRefCounting(engine);
    testExceptions(engine);
}

private void testValueCreation(IJSEngine e)
{
    describe("value creation", {
        it("creates integers", {
            auto h = e.newInt(42);
            assert(e.extractInt(h) == 42);
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
            e.freeValue(h);
        });

        it("identifies numbers", {
            auto h = e.newFloat(1.0);
            assert(e.isNumber(h));
            assert(!e.isString(h));
            e.freeValue(h);
        });

        it("identifies strings", {
            auto h = e.newString("x");
            assert(e.isString(h));
            assert(!e.isNumber(h));
            e.freeValue(h);
        });

        it("identifies objects", {
            auto h = e.newObject();
            assert(e.isObject(h));
            assert(!e.isString(h));
            e.freeValue(h);
        });
    });
}

private void testProperties(IJSEngine e)
{
    describe("property access", {
        it("sets and gets properties", {
            auto obj = e.newObject();
            auto val = e.newInt(99);
            e.setProperty(obj, "x", val);
            auto got = e.getProperty(obj, "x");
            assert(e.extractInt(got) == 99);
            e.freeValue(got);
            e.freeValue(val);
            e.freeValue(obj);
        });

        it("accesses global object", {
            auto g = e.getGlobal();
            assert(e.isObject(g));
            e.freeValue(g);
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

        it("evaluates string expressions", {
            auto r = e.eval("'hello' + ' ' + 'world'", "<test>");
            assert(!r.isError);
            assert(e.extractString(r.value) == "hello world");
            e.freeValue(r.value);
        });

        it("reports syntax errors", {
            auto r = e.eval("function(", "<test>");
            assert(r.isError);
            assert(r.errorMessage.length > 0);
        });

        it("evaluates boolean expressions", {
            auto r = e.eval("true === true", "<test>");
            assert(!r.isError);
            assert(e.extractBool(r.value) == true);
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
    });
}

private void testExceptions(IJSEngine e)
{
    describe("exceptions", {
        it("detects runtime errors", {
            auto r = e.eval("undefined_var.prop", "<test>");
            assert(r.isError);
        });
    });
}

// ---------------------------------------------------------------------------
// Per-backend test instantiation (version-gated)
// ---------------------------------------------------------------------------

version (EngineQuickJS)
{
    @("quickjs: engine contract")
    unittest
    {
        auto engine = createEngine(EngineBackend.quickjs);
        runEngineContractTests(engine);
    }
}

version (EngineJSC)
{
    @("jsc: engine contract")
    unittest
    {
        auto engine = createEngine(EngineBackend.jsc);
        runEngineContractTests(engine);
    }
}

version (EngineV8)
{
    @("v8: engine contract")
    unittest
    {
        auto engine = createEngine(EngineBackend.v8);
        runEngineContractTests(engine);
    }
}
