module dun.engine.fuzz;

version (DunTest):

import dun.engine.iface;
import dun.engine.test : Test, Describe, ShouldFail, EngineTestRunner, runModuleTests;

// ---------------------------------------------------------------------------
// Fuzz tests -- annotated functions using shared UDA framework
// ---------------------------------------------------------------------------

// --- empty and whitespace inputs ------------------------------------------

@Describe("fuzz: empty and whitespace inputs")
@Test("handles empty string eval")
void fuzzEmptyStringEval(IJSEngine e)
{
    auto r = e.eval("", "<fuzz>");
    if (!r.isError)
        e.freeValue(r.value);
}

@Describe("fuzz: empty and whitespace inputs")
@Test("handles whitespace-only eval")
void fuzzWhitespaceOnlyEval(IJSEngine e)
{
    auto r = e.eval("   \t\n  ", "<fuzz>");
    if (!r.isError)
        e.freeValue(r.value);
}

@Describe("fuzz: empty and whitespace inputs")
@Test("handles semicolons only")
void fuzzSemicolonsOnly(IJSEngine e)
{
    auto r = e.eval(";;;", "<fuzz>");
    if (!r.isError)
        e.freeValue(r.value);
}

@Describe("fuzz: empty and whitespace inputs")
@Test("handles newlines only")
void fuzzNewlinesOnly(IJSEngine e)
{
    auto r = e.eval("\n\n\n", "<fuzz>");
    if (!r.isError)
        e.freeValue(r.value);
}

@Describe("fuzz: empty and whitespace inputs")
@Test("handles null bytes in source")
void fuzzNullBytes(IJSEngine e)
{
    auto r = e.eval("1+\x00+2", "<fuzz>");
    if (!r.isError)
        e.freeValue(r.value);
}

@Describe("fuzz: empty and whitespace inputs")
@Test("creates empty string value")
void fuzzEmptyStringValue(IJSEngine e)
{
    auto h = e.newString("");
    assert(e.extractString(h) == "");
    e.freeValue(h);
}

// --- malformed syntax -----------------------------------------------------

// Generate individual test functions for each malformed input at compile time.
// This uses a mixin + static foreach to produce one @Test function per input.
private immutable string[] _badInputs = [
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

private string _safeSnippet(string input) pure
{
    if (input.length > 20)
        return input[0 .. 20] ~ "...";
    return input;
}

// Single test that iterates all malformed inputs (preserves original coverage).
@Describe("fuzz: malformed syntax")
@Test("survives all malformed inputs")
void fuzzMalformedSyntaxAll(IJSEngine e)
{
    foreach (input; _badInputs)
    {
        auto r = e.eval(input, "<fuzz>");
        if (!r.isError)
            e.freeValue(r.value);
    }
}

// --- unicode edge cases ---------------------------------------------------

@Describe("fuzz: unicode edge cases")
@Test("handles BMP characters")
void fuzzBMPCharacters(IJSEngine e)
{
    auto h = e.newString("éñü");
    auto s = e.extractString(h);
    assert(s.length > 0);
    e.freeValue(h);
}

@Describe("fuzz: unicode edge cases")
@Test("handles CJK characters")
void fuzzCJKCharacters(IJSEngine e)
{
    auto h = e.newString("世界");
    auto s = e.extractString(h);
    assert(s == "世界");
    e.freeValue(h);
}

@Describe("fuzz: unicode edge cases")
@Test("handles emoji (supplementary plane)")
void fuzzEmoji(IJSEngine e)
{
    auto h = e.newString("\U0001F600\U0001F680");
    auto s = e.extractString(h);
    assert(s.length > 0);
    e.freeValue(h);
}

@Describe("fuzz: unicode edge cases")
@Test("handles mixed ASCII and unicode")
void fuzzMixedUnicode(IJSEngine e)
{
    auto h = e.newString("hello é world \U0001F600");
    auto s = e.extractString(h);
    assert(s.length > 0);
    e.freeValue(h);
}

@Describe("fuzz: unicode edge cases")
@Test("eval with unicode identifiers")
void fuzzUnicodeIdentifiers(IJSEngine e)
{
    auto r = e.eval("var é = 42; é", "<fuzz>");
    if (!r.isError)
    {
        assert(e.extractInt(r.value) == 42);
        e.freeValue(r.value);
    }
}

@Describe("fuzz: unicode edge cases")
@Test("eval with unicode string literals")
void fuzzUnicodeStringLiterals(IJSEngine e)
{
    auto r = e.eval("'世界'", "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: unicode edge cases")
@Test("handles zero-width characters")
void fuzzZeroWidthChars(IJSEngine e)
{
    auto h = e.newString("a​b‌c﻿");
    auto s = e.extractString(h);
    assert(s.length > 0);
    e.freeValue(h);
}

@Describe("fuzz: unicode edge cases")
@Test("handles replacement character")
void fuzzReplacementChar(IJSEngine e)
{
    auto h = e.newString("�");
    auto s = e.extractString(h);
    assert(s.length > 0);
    e.freeValue(h);
}

// --- large values ---------------------------------------------------------

@Describe("fuzz: large values")
@Test("handles large string creation")
void fuzzLargeString(IJSEngine e)
{
    char[] big;
    big.length = 100_000;
    big[] = 'A';
    auto h = e.newString(cast(string) big);
    auto s = e.extractString(h);
    assert(s.length == 100_000);
    e.freeValue(h);
}

@Describe("fuzz: large values")
@Test("handles large array via eval")
void fuzzLargeArray(IJSEngine e)
{
    auto r = e.eval("new Array(10000).fill(0).length", "<fuzz>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 10000);
    e.freeValue(r.value);
}

@Describe("fuzz: large values")
@Test("handles deeply nested object access")
void fuzzDeepObjectAccess(IJSEngine e)
{
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
}

@Describe("fuzz: large values")
@Test("handles long property name")
void fuzzLongPropertyName(IJSEngine e)
{
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
}

// --- numeric edge cases ---------------------------------------------------

@Describe("fuzz: numeric edge cases")
@Test("handles MAX_SAFE_INTEGER")
void fuzzMaxSafeInt(IJSEngine e)
{
    auto r = e.eval("Number.MAX_SAFE_INTEGER", "<fuzz>");
    assert(!r.isError);
    auto v = e.extractFloat(r.value);
    assert(v == 9007199254740991.0);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles MIN_SAFE_INTEGER")
void fuzzMinSafeInt(IJSEngine e)
{
    auto r = e.eval("Number.MIN_SAFE_INTEGER", "<fuzz>");
    assert(!r.isError);
    auto v = e.extractFloat(r.value);
    assert(v == -9007199254740991.0);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles Infinity")
void fuzzInfinity(IJSEngine e)
{
    auto r = e.eval("Infinity", "<fuzz>");
    assert(!r.isError);
    auto v = e.extractFloat(r.value);
    assert(v == double.infinity);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles -Infinity")
void fuzzNegInfinity(IJSEngine e)
{
    auto r = e.eval("-Infinity", "<fuzz>");
    assert(!r.isError);
    auto v = e.extractFloat(r.value);
    assert(v == -double.infinity);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles NaN")
void fuzzNaN(IJSEngine e)
{
    auto r = e.eval("NaN", "<fuzz>");
    assert(!r.isError);
    auto v = e.extractFloat(r.value);
    assert(v != v);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles -0")
void fuzzNegativeZero(IJSEngine e)
{
    auto r = e.eval("-0", "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: numeric edge cases")
@Test("handles int32 min")
void fuzzInt32Min(IJSEngine e)
{
    auto h = e.newInt(int.min);
    assert(e.extractInt(h) == int.min);
    e.freeValue(h);
}

@Describe("fuzz: numeric edge cases")
@Test("handles int32 max")
void fuzzInt32Max(IJSEngine e)
{
    auto h = e.newInt(int.max);
    assert(e.extractInt(h) == int.max);
    e.freeValue(h);
}

@Describe("fuzz: numeric edge cases")
@Test("handles very small float")
void fuzzVerySmallFloat(IJSEngine e)
{
    auto h = e.newFloat(double.min_normal);
    auto v = e.extractFloat(h);
    assert(v > 0);
    e.freeValue(h);
}

// --- deep nesting ---------------------------------------------------------

@Describe("fuzz: deep nesting")
@Test("handles deeply nested function calls")
void fuzzDeepFunctionCalls(IJSEngine e)
{
    auto r = e.eval(
        "function f(n) { return n <= 0 ? 0 : f(n-1) + 1; } f(100)",
        "<fuzz>"
    );
    assert(!r.isError);
    assert(e.extractInt(r.value) == 100);
    e.freeValue(r.value);
}

@Describe("fuzz: deep nesting")
@Test("handles deeply nested arrays")
void fuzzDeepArrays(IJSEngine e)
{
    auto r = e.eval(
        "var a = 42; for(var i=0;i<50;i++) a=[a]; " ~
        "var v = a; for(var i=0;i<50;i++) v=v[0]; v",
        "<fuzz>"
    );
    assert(!r.isError);
    assert(e.extractInt(r.value) == 42);
    e.freeValue(r.value);
}

@Describe("fuzz: deep nesting")
@Test("handles chained property access via eval")
void fuzzChainedPropertyAccess(IJSEngine e)
{
    auto r = e.eval(
        "({a:{b:{c:{d:{e:99}}}}})" ~ ".a.b.c.d.e",
        "<fuzz>"
    );
    assert(!r.isError);
    assert(e.extractInt(r.value) == 99);
    e.freeValue(r.value);
}

@Describe("fuzz: deep nesting")
@Test("handles many sequential evals")
void fuzzManySequentialEvals(IJSEngine e)
{
    for (int i = 0; i < 200; i++)
    {
        auto r = e.eval("1+1", "<fuzz>");
        assert(!r.isError);
        e.freeValue(r.value);
    }
}

// --- string edge cases ----------------------------------------------------

@Describe("fuzz: string edge cases")
@Test("handles string with backslashes")
void fuzzStringBackslashes(IJSEngine e)
{
    auto r = e.eval(`'hello\\world'`, "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: string edge cases")
@Test("handles string with quotes")
void fuzzStringQuotes(IJSEngine e)
{
    auto r = e.eval(`"it's a \"test\""`, "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: string edge cases")
@Test("handles string with newlines")
void fuzzStringNewlines(IJSEngine e)
{
    auto r = e.eval("'line1\\nline2'", "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: string edge cases")
@Test("handles template literal with expressions")
void fuzzTemplateLiteralExpressions(IJSEngine e)
{
    auto r = e.eval("`${'a'.repeat(100)}`", "<fuzz>");
    assert(!r.isError);
    auto s = e.extractString(r.value);
    assert(s.length == 100);
    e.freeValue(r.value);
}

@Describe("fuzz: string edge cases")
@Test("handles string concatenation stress")
void fuzzStringConcatStress(IJSEngine e)
{
    auto r = e.eval(
        "var s = ''; for(var i=0;i<1000;i++) s += 'x'; s.length",
        "<fuzz>"
    );
    assert(!r.isError);
    assert(e.extractInt(r.value) == 1000);
    e.freeValue(r.value);
}

// --- eval stress ----------------------------------------------------------

@Describe("fuzz: eval stress")
@Test("handles rapid object creation/destruction")
void fuzzRapidObjects(IJSEngine e)
{
    for (int i = 0; i < 500; i++)
    {
        auto obj = e.newObject();
        auto val = e.newInt(i);
        e.setProperty(obj, "v", val);
        e.freeValue(obj);
    }
}

@Describe("fuzz: eval stress")
@Test("handles rapid string creation/destruction")
void fuzzRapidStrings(IJSEngine e)
{
    for (int i = 0; i < 500; i++)
    {
        auto h = e.newString("test string value");
        auto s = e.extractString(h);
        assert(s == "test string value");
        e.freeValue(h);
    }
}

@Describe("fuzz: eval stress")
@Test("handles rapid eval")
void fuzzRapidEval(IJSEngine e)
{
    for (int i = 0; i < 100; i++)
    {
        auto r = e.eval("({a:1,b:2,c:3})", "<fuzz>");
        assert(!r.isError);
        e.freeValue(r.value);
    }
}

@Describe("fuzz: eval stress")
@Test("handles promise chain stress")
void fuzzPromiseChainStress(IJSEngine e)
{
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
}

@Describe("fuzz: eval stress")
@Test("handles concurrent dup/free")
void fuzzConcurrentDupFree(IJSEngine e)
{
    auto h = e.newString("shared value");
    auto d1 = e.dupValue(h);
    auto d2 = e.dupValue(h);
    auto d3 = e.dupValue(d1);
    e.freeValue(d2);
    e.freeValue(d1);
    assert(e.extractString(d3) == "shared value");
    e.freeValue(d3);
    e.freeValue(h);
}

// --- exception recovery ---------------------------------------------------

@Describe("fuzz: exception recovery")
@Test("recovers from repeated errors")
void fuzzRepeatedErrors(IJSEngine e)
{
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
}

@Describe("fuzz: exception recovery")
@Test("recovers from type errors")
void fuzzRecoverTypeErrors(IJSEngine e)
{
    for (int i = 0; i < 20; i++)
    {
        auto r = e.eval("null.prop", "<fuzz>");
        assert(r.isError);
    }
    auto r = e.eval("'ok'", "<fuzz>");
    assert(!r.isError);
    assert(e.extractString(r.value) == "ok");
    e.freeValue(r.value);
}

@Describe("fuzz: exception recovery")
@Test("recovers from stack overflow")
void fuzzRecoverStackOverflow(IJSEngine e)
{
    auto r = e.eval("function f(){f()}; try{f()}catch(e){e.message}", "<fuzz>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("fuzz: exception recovery")
@Test("recovers from syntax errors then runs valid code")
void fuzzRecoverSyntaxErrors(IJSEngine e)
{
    auto r1 = e.eval("{{{{", "<fuzz>");
    assert(r1.isError);

    auto r2 = e.eval("42", "<fuzz>");
    assert(!r2.isError);
    assert(e.extractInt(r2.value) == 42);
    e.freeValue(r2.value);
}

// --- property edge cases --------------------------------------------------

@Describe("fuzz: property edge cases")
@Test("handles special property names")
void fuzzSpecialPropertyNames(IJSEngine e)
{
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
}

@Describe("fuzz: property edge cases")
@Test("handles overwriting properties")
void fuzzOverwriteProperties(IJSEngine e)
{
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
}

@Describe("fuzz: property edge cases")
@Test("handles many unique properties")
void fuzzManyUniqueProperties(IJSEngine e)
{
    auto r = e.eval(
        "var o = {}; for(var i=0;i<500;i++) o['prop'+i] = i; " ~
        "Object.keys(o).length",
        "<fuzz>"
    );
    assert(!r.isError);
    assert(e.extractInt(r.value) == 500);
    e.freeValue(r.value);
}

// ---------------------------------------------------------------------------
// Per-backend fuzz test instantiation via EngineTestRunner
// ---------------------------------------------------------------------------

mixin EngineTestRunner!("Engine Fuzz Tests", dun.engine.fuzz);
