module dun.engine.fuzz;

version (DunTest):

import dun.engine.iface;

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

void runFuzzTests(IJSEngine engine)
{
    auto cfg = EngineConfig(64 * 1024 * 1024, 4 * 1024 * 1024);
    engine.initialize(cfg);
    scope (exit)
        engine.shutdown();

    fuzzEmptyAndWhitespace(engine);
    fuzzMalformedSyntax(engine);
    fuzzUnicode(engine);
    fuzzLargeValues(engine);
    fuzzEdgeCaseNumbers(engine);
    fuzzDeepNesting(engine);
    fuzzStringEdgeCases(engine);
    fuzzEvalStress(engine);
    fuzzExceptionRecovery(engine);
    fuzzPropertyEdgeCases(engine);
}

private void fuzzEmptyAndWhitespace(IJSEngine e)
{
    describe("fuzz: empty and whitespace inputs", {
        it("handles empty string eval", {
            auto r = e.eval("", "<fuzz>");
            if (!r.isError)
                e.freeValue(r.value);
        });

        it("handles whitespace-only eval", {
            auto r = e.eval("   \t\n  ", "<fuzz>");
            if (!r.isError)
                e.freeValue(r.value);
        });

        it("handles semicolons only", {
            auto r = e.eval(";;;", "<fuzz>");
            if (!r.isError)
                e.freeValue(r.value);
        });

        it("handles newlines only", {
            auto r = e.eval("\n\n\n", "<fuzz>");
            if (!r.isError)
                e.freeValue(r.value);
        });

        it("handles null bytes in source", {
            auto r = e.eval("1+\x00+2", "<fuzz>");
            if (!r.isError)
                e.freeValue(r.value);
        });

        it("creates empty string value", {
            auto h = e.newString("");
            assert(e.extractString(h) == "");
            e.freeValue(h);
        });
    });
}

private void fuzzMalformedSyntax(IJSEngine e)
{
    describe("fuzz: malformed syntax", {
        static immutable badInputs = [
            "{{{", "}}}", "(((",
            "function", "function(",
            "var", "var =",
            "if else", "while",
            "for(", "for(;;",
            "switch{", "case",
            "return return",
            "class {", "class { constructor(",
            "import", "export",
            "async", "await",
            "yield",
            "=>", "=>>",
            "...", "...x",
            "@", "#",
            "` ${", "`${}`",
            "0x", "0b", "0o",
            "1e999999",
            "/[/", "/(/",
        ];

        foreach (input; badInputs)
        {
            it("survives malformed: " ~ safeSnippet(input), {
                auto r = e.eval(input, "<fuzz>");
                if (!r.isError)
                    e.freeValue(r.value);
            });
        }
    });
}

private void fuzzUnicode(IJSEngine e)
{
    describe("fuzz: unicode edge cases", {
        it("handles BMP characters", {
            auto h = e.newString("éñü");
            auto s = e.extractString(h);
            assert(s.length > 0);
            e.freeValue(h);
        });

        it("handles CJK characters", {
            auto h = e.newString("世界");
            auto s = e.extractString(h);
            assert(s == "世界");
            e.freeValue(h);
        });

        it("handles emoji (supplementary plane)", {
            auto h = e.newString("\U0001F600\U0001F680");
            auto s = e.extractString(h);
            assert(s.length > 0);
            e.freeValue(h);
        });

        it("handles mixed ASCII and unicode", {
            auto h = e.newString("hello é world \U0001F600");
            auto s = e.extractString(h);
            assert(s.length > 0);
            e.freeValue(h);
        });

        it("eval with unicode identifiers", {
            auto r = e.eval("var é = 42; é", "<fuzz>");
            if (!r.isError)
            {
                assert(e.extractInt(r.value) == 42);
                e.freeValue(r.value);
            }
        });

        it("eval with unicode string literals", {
            auto r = e.eval("'世界'", "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("handles zero-width characters", {
            auto h = e.newString("a​b‌c﻿");
            auto s = e.extractString(h);
            assert(s.length > 0);
            e.freeValue(h);
        });

        it("handles replacement character", {
            auto h = e.newString("�");
            auto s = e.extractString(h);
            assert(s.length > 0);
            e.freeValue(h);
        });
    });
}

private void fuzzLargeValues(IJSEngine e)
{
    describe("fuzz: large values", {
        it("handles large string creation", {
            char[] big;
            big.length = 100_000;
            big[] = 'A';
            auto h = e.newString(cast(string) big);
            auto s = e.extractString(h);
            assert(s.length == 100_000);
            e.freeValue(h);
        });

        it("handles large array via eval", {
            auto r = e.eval("new Array(10000).fill(0).length", "<fuzz>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 10000);
            e.freeValue(r.value);
        });

        it("handles deeply nested object access", {
            auto r = e.eval(
                "var o = {}; var c = o; " ~
                "for(var i=0;i<100;i++){c.n={};c=c.n;} " ~
                "c.val = 42; " ~
                "var r = o; for(var i=0;i<100;i++) r=r.n; r.val",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 42);
            e.freeValue(r.value);
        });

        it("handles long property name", {
            char[] name;
            name.length = 1000;
            name[] = 'x';
            auto obj = e.newObject();
            auto val = e.newInt(99);
            e.setProperty(obj, cast(string) name, val);
            auto got = e.getProperty(obj, cast(string) name);
            assert(e.extractInt(got) == 99);
            e.freeValue(got);
            e.freeValue(obj);
        });
    });
}

private void fuzzEdgeCaseNumbers(IJSEngine e)
{
    describe("fuzz: numeric edge cases", {
        it("handles MAX_SAFE_INTEGER", {
            auto r = e.eval("Number.MAX_SAFE_INTEGER", "<fuzz>");
            assert(!r.isError);
            auto v = e.extractFloat(r.value);
            assert(v == 9007199254740991.0);
            e.freeValue(r.value);
        });

        it("handles MIN_SAFE_INTEGER", {
            auto r = e.eval("Number.MIN_SAFE_INTEGER", "<fuzz>");
            assert(!r.isError);
            auto v = e.extractFloat(r.value);
            assert(v == -9007199254740991.0);
            e.freeValue(r.value);
        });

        it("handles Infinity", {
            auto r = e.eval("Infinity", "<fuzz>");
            assert(!r.isError);
            auto v = e.extractFloat(r.value);
            assert(v == double.infinity);
            e.freeValue(r.value);
        });

        it("handles -Infinity", {
            auto r = e.eval("-Infinity", "<fuzz>");
            assert(!r.isError);
            auto v = e.extractFloat(r.value);
            assert(v == -double.infinity);
            e.freeValue(r.value);
        });

        it("handles NaN", {
            auto r = e.eval("NaN", "<fuzz>");
            assert(!r.isError);
            auto v = e.extractFloat(r.value);
            assert(v != v);
            e.freeValue(r.value);
        });

        it("handles -0", {
            auto r = e.eval("-0", "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("handles int32 min", {
            auto h = e.newInt(int.min);
            assert(e.extractInt(h) == int.min);
            e.freeValue(h);
        });

        it("handles int32 max", {
            auto h = e.newInt(int.max);
            assert(e.extractInt(h) == int.max);
            e.freeValue(h);
        });

        it("handles very small float", {
            auto h = e.newFloat(double.min_normal);
            auto v = e.extractFloat(h);
            assert(v > 0);
            e.freeValue(h);
        });
    });
}

private void fuzzDeepNesting(IJSEngine e)
{
    describe("fuzz: deep nesting", {
        it("handles deeply nested function calls", {
            auto r = e.eval(
                "function f(n) { return n <= 0 ? 0 : f(n-1) + 1; } f(100)",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 100);
            e.freeValue(r.value);
        });

        it("handles deeply nested arrays", {
            auto r = e.eval(
                "var a = 42; for(var i=0;i<50;i++) a=[a]; " ~
                "var v = a; for(var i=0;i<50;i++) v=v[0]; v",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 42);
            e.freeValue(r.value);
        });

        it("handles chained property access via eval", {
            auto r = e.eval(
                "({a:{b:{c:{d:{e:99}}}}})" ~ ".a.b.c.d.e",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 99);
            e.freeValue(r.value);
        });

        it("handles many sequential evals", {
            for (int i = 0; i < 200; i++)
            {
                auto r = e.eval("1+1", "<fuzz>");
                assert(!r.isError);
                e.freeValue(r.value);
            }
        });
    });
}

private void fuzzStringEdgeCases(IJSEngine e)
{
    describe("fuzz: string edge cases", {
        it("handles string with backslashes", {
            auto r = e.eval(`'hello\\world'`, "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("handles string with quotes", {
            auto r = e.eval(`"it's a \"test\""`, "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("handles string with newlines", {
            auto r = e.eval("'line1\\nline2'", "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("handles template literal with expressions", {
            auto r = e.eval("`${'a'.repeat(100)}`", "<fuzz>");
            assert(!r.isError);
            auto s = e.extractString(r.value);
            assert(s.length == 100);
            e.freeValue(r.value);
        });

        it("handles string concatenation stress", {
            auto r = e.eval(
                "var s = ''; for(var i=0;i<1000;i++) s += 'x'; s.length",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 1000);
            e.freeValue(r.value);
        });
    });
}

private void fuzzEvalStress(IJSEngine e)
{
    describe("fuzz: eval stress", {
        it("handles rapid object creation/destruction", {
            for (int i = 0; i < 500; i++)
            {
                auto obj = e.newObject();
                auto val = e.newInt(i);
                e.setProperty(obj, "v", val);
                e.freeValue(obj);
            }
        });

        it("handles rapid string creation/destruction", {
            for (int i = 0; i < 500; i++)
            {
                auto h = e.newString("test string value");
                auto s = e.extractString(h);
                assert(s == "test string value");
                e.freeValue(h);
            }
        });

        it("handles rapid eval", {
            for (int i = 0; i < 100; i++)
            {
                auto r = e.eval("({a:1,b:2,c:3})", "<fuzz>");
                assert(!r.isError);
                e.freeValue(r.value);
            }
        });

        it("handles promise chain stress", {
            auto r = e.eval(
                "var chain = Promise.resolve(0);" ~
                "for(var i=0;i<50;i++) chain = chain.then(v => v+1);" ~
                "chain.then(v => globalThis.__chainResult = v)",
                "<fuzz>"
            );
            assert(!r.isError);
            e.freeValue(r.value);
            e.drainJobs();

            auto r2 = e.eval("globalThis.__chainResult", "<fuzz>");
            assert(!r2.isError);
            assert(e.extractInt(r2.value) == 50);
            e.freeValue(r2.value);
        });

        it("handles concurrent dup/free", {
            auto h = e.newString("shared value");
            auto d1 = e.dupValue(h);
            auto d2 = e.dupValue(h);
            auto d3 = e.dupValue(d1);
            e.freeValue(d2);
            e.freeValue(d1);
            assert(e.extractString(d3) == "shared value");
            e.freeValue(d3);
            e.freeValue(h);
        });
    });
}

private void fuzzExceptionRecovery(IJSEngine e)
{
    describe("fuzz: exception recovery", {
        it("recovers from repeated errors", {
            for (int i = 0; i < 50; i++)
            {
                auto r = e.eval("undefined_var_xyz", "<fuzz>");
                assert(r.isError);
            }
            // Engine should still work after many errors
            auto r = e.eval("1 + 1", "<fuzz>");
            assert(!r.isError);
            assert(e.extractInt(r.value) == 2);
            e.freeValue(r.value);
        });

        it("recovers from type errors", {
            for (int i = 0; i < 20; i++)
            {
                auto r = e.eval("null.prop", "<fuzz>");
                assert(r.isError);
            }
            auto r = e.eval("'ok'", "<fuzz>");
            assert(!r.isError);
            assert(e.extractString(r.value) == "ok");
            e.freeValue(r.value);
        });

        it("recovers from stack overflow", {
            auto r = e.eval("function f(){f()}; try{f()}catch(e){e.message}", "<fuzz>");
            assert(!r.isError);
            e.freeValue(r.value);
        });

        it("recovers from syntax errors then runs valid code", {
            auto r1 = e.eval("{{{{", "<fuzz>");
            assert(r1.isError);

            auto r2 = e.eval("42", "<fuzz>");
            assert(!r2.isError);
            assert(e.extractInt(r2.value) == 42);
            e.freeValue(r2.value);
        });
    });
}

private void fuzzPropertyEdgeCases(IJSEngine e)
{
    describe("fuzz: property edge cases", {
        it("handles special property names", {
            auto obj = e.newObject();

            static immutable names = [
                "constructor", "prototype", "__proto__",
                "toString", "valueOf", "hasOwnProperty",
                "", "0", "-1", "null", "undefined",
                "true", "false",
            ];

            foreach (name; names)
            {
                auto val = e.newInt(1);
                e.setProperty(obj, name, val);
                auto got = e.getProperty(obj, name);
                e.freeValue(got);
            }

            e.freeValue(obj);
        });

        it("handles overwriting properties", {
            auto obj = e.newObject();
            for (int i = 0; i < 100; i++)
            {
                auto val = e.newInt(i);
                e.setProperty(obj, "key", val);
            }
            auto got = e.getProperty(obj, "key");
            assert(e.extractInt(got) == 99);
            e.freeValue(got);
            e.freeValue(obj);
        });

        it("handles many unique properties", {
            auto r = e.eval(
                "var o = {}; for(var i=0;i<500;i++) o['prop'+i] = i; " ~
                "Object.keys(o).length",
                "<fuzz>"
            );
            assert(!r.isError);
            assert(e.extractInt(r.value) == 500);
            e.freeValue(r.value);
        });
    });
}

private string safeSnippet(string input)
{
    if (input.length > 20)
        return input[0 .. 20] ~ "...";
    return input;
}

// Per-backend fuzz test instantiation
version (EngineQuickJS)
{
    @("quickjs: fuzz tests")
    unittest
    {
        import std.stdio : writeln;
        writeln("QuickJS Engine Fuzz Tests");
        auto engine = createEngine();
        runFuzzTests(engine);
    }
}

version (EngineJSC)
{
    @("jsc: fuzz tests")
    unittest
    {
        import std.stdio : writeln;
        writeln("JSC Engine Fuzz Tests");
        auto engine = createEngine();
        runFuzzTests(engine);
    }
}

version (EngineV8)
{
    @("v8: fuzz tests")
    unittest
    {
        import std.stdio : writeln;
        writeln("V8 Engine Fuzz Tests");
        auto engine = createEngine();
        runFuzzTests(engine);
    }
}
