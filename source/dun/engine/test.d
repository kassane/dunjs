module dun.engine.test;

version (DunTest):

import dun.engine.iface;
import std.stdio : writeln;
import std.traits : getUDAs, hasUDA;

// ---------------------------------------------------------------------------
// UDA-based test framework using D compile-time reflection
// ---------------------------------------------------------------------------

/// UDA to mark a function as a test case.
struct Test
{
    string name;
}

/// UDA to group tests under a describe block.
struct Describe
{
    string group;
}

/// UDA to mark tests that are expected to fail (error is success).
enum ShouldFail;

/// Extract the @Test name from a symbol, falling back to the symbol's identifier.
template getTestName(alias func)
{
    static if (getUDAs!(func, Test).length > 0)
        enum getTestName = getUDAs!(func, Test)[0].name;
    else
        enum getTestName = __traits(identifier, func);
}

/// Extract the @Describe group from a symbol, or "" if none.
template getGroupName(alias func)
{
    static if (getUDAs!(func, Describe).length > 0)
        enum getGroupName = getUDAs!(func, Describe)[0].group;
    else
        enum getGroupName = "";
}

/// True if the symbol carries `@Test`.
template hasTestUDA(alias func)
{
    enum hasTestUDA = hasUDA!(func, Test);
}

/// True if the symbol carries `@ShouldFail`.
template hasShouldFail(alias func)
{
    enum hasShouldFail = hasUDA!(func, ShouldFail);
}

/// Run all @Test functions in module M.
void runModuleTests(alias M)(IJSEngine engine)
{
    string currentGroup;
    uint passed, failed;

    static foreach (name; __traits(allMembers, M))
    {{
        static if (__traits(compiles, __traits(getMember, M, name))
                && is(typeof(&__traits(getMember, M, name)) : void function(IJSEngine)))
        {
            alias func = __traits(getMember, M, name);
            static if (hasTestUDA!func)
            {
                enum group = getGroupName!func;
                enum testName = getTestName!func;
                enum shouldFail = hasShouldFail!func;

                // Print group header on change
                if (group.length > 0 && group != currentGroup)
                {
                    currentGroup = group;
                    writeln("  ", group);
                }

                try
                {
                    func(engine);

                    static if (shouldFail)
                    {
                        writeln("    x ", testName, " -- expected failure but passed");
                        failed++;
                    }
                    else
                    {
                        writeln("    + ", testName);
                        passed++;
                    }
                }
                catch (Exception ex)
                {
                    static if (shouldFail)
                    {
                        writeln("    + ", testName, " (expected fail)");
                        passed++;
                    }
                    else
                    {
                        writeln("    x ", testName, " -- ", ex.msg);
                        failed++;
                    }
                }
                catch (Error err)
                {
                    static if (shouldFail)
                    {
                        writeln("    + ", testName, " (expected fail)");
                        passed++;
                    }
                    else
                    {
                        writeln("    x ", testName, " -- ", err.msg);
                        throw err;
                    }
                }
            }
        }
    }}

    writeln("  -- ", passed, " passed, ", failed, " failed");
}

/// Generates per-backend unittest blocks from a tuple of test modules.
mixin template EngineTestRunner(string label, Modules...)
{
    version (EngineQuickJS)
    {
        @("quickjs: " ~ label)
        unittest
        {
            writeln("QuickJS ", label);
            auto engine = createEngine();
            auto cfg = EngineConfig(TEST_MEMORY_LIMIT, TEST_MAX_STACK);
            engine.initialize(cfg);
            scope (exit)
                engine.shutdown();

            static foreach (M; Modules)
                runModuleTests!M(engine);
        }
    }

    version (EngineJSC)
    {
        @("jsc: " ~ label)
        unittest
        {
            writeln("JSC ", label);
            auto engine = createEngine();
            auto cfg = EngineConfig(TEST_MEMORY_LIMIT, TEST_MAX_STACK);
            engine.initialize(cfg);
            scope (exit)
                engine.shutdown();

            static foreach (M; Modules)
                runModuleTests!M(engine);
        }
    }

    version (EngineV8)
    {
        @("v8: " ~ label)
        unittest
        {
            writeln("V8 ", label);
            auto engine = createEngine();
            auto cfg = EngineConfig(TEST_MEMORY_LIMIT, TEST_MAX_STACK);
            engine.initialize(cfg);
            scope (exit)
                engine.shutdown();

            static foreach (M; Modules)
                runModuleTests!M(engine);
        }
    }
}

// ---------------------------------------------------------------------------
// Engine contract tests -- annotated functions
// ---------------------------------------------------------------------------

// --- value creation -------------------------------------------------------

@Describe("value creation")
@Test("creates integers")
void testCreatesIntegers(IJSEngine e)
{
    auto h = e.newInt(42);
    assert(e.extractInt(h) == 42);
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates negative integers")
void testCreatesNegativeIntegers(IJSEngine e)
{
    auto h = e.newInt(-1);
    assert(e.extractInt(h) == -1);
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates zero")
void testCreatesZero(IJSEngine e)
{
    auto h = e.newInt(0);
    assert(e.extractInt(h) == 0);
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates floats")
void testCreatesFloats(IJSEngine e)
{
    auto h = e.newFloat(3.14);
    auto v = e.extractFloat(h);
    assert(v > 3.13 && v < 3.15);
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates booleans")
void testCreatesBooleans(IJSEngine e)
{
    auto t = e.newBool(true);
    auto f = e.newBool(false);
    assert(e.extractBool(t) == true);
    assert(e.extractBool(f) == false);
    e.freeValue(t);
    e.freeValue(f);
}

@Describe("value creation")
@Test("creates strings")
void testCreatesStrings(IJSEngine e)
{
    auto h = e.newString("hello");
    assert(e.extractString(h) == "hello");
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates empty strings")
void testCreatesEmptyStrings(IJSEngine e)
{
    auto h = e.newString("");
    assert(e.extractString(h) == "");
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates unicode strings")
void testCreatesUnicodeStrings(IJSEngine e)
{
    auto h = e.newString("日本語");
    assert(e.extractString(h) == "日本語");
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates objects")
void testCreatesObjects(IJSEngine e)
{
    auto h = e.newObject();
    assert(e.isObject(h));
    e.freeValue(h);
}

@Describe("value creation")
@Test("creates arrays")
void testCreatesArrays(IJSEngine e)
{
    auto h = e.newArray();
    assert(!e.isNull(h));
    e.freeValue(h);
}

// --- type checks ----------------------------------------------------------

@Describe("type checks")
@Test("identifies booleans")
void testIdentifiesBooleans(IJSEngine e)
{
    auto h = e.newBool(true);
    assert(e.isBool(h));
    assert(!e.isNumber(h));
    assert(!e.isString(h));
    assert(!e.isNull(h));
    assert(!e.isUndefined(h));
    e.freeValue(h);
}

@Describe("type checks")
@Test("identifies integers as numbers")
void testIdentifiesIntegersAsNumbers(IJSEngine e)
{
    auto h = e.newInt(1);
    assert(e.isNumber(h));
    assert(!e.isString(h));
    e.freeValue(h);
}

@Describe("type checks")
@Test("identifies floats as numbers")
void testIdentifiesFloatsAsNumbers(IJSEngine e)
{
    auto h = e.newFloat(1.0);
    assert(e.isNumber(h));
    assert(!e.isString(h));
    e.freeValue(h);
}

@Describe("type checks")
@Test("identifies strings")
void testIdentifiesStrings(IJSEngine e)
{
    auto h = e.newString("x");
    assert(e.isString(h));
    assert(!e.isNumber(h));
    assert(!e.isBool(h));
    e.freeValue(h);
}

@Describe("type checks")
@Test("identifies objects")
void testIdentifiesObjects(IJSEngine e)
{
    auto h = e.newObject();
    assert(e.isObject(h));
    assert(!e.isString(h));
    assert(!e.isNumber(h));
    e.freeValue(h);
}

@Describe("type checks")
@Test("identifies undefined from eval")
void testIdentifiesUndefined(IJSEngine e)
{
    auto r = e.eval("undefined", "<test>");
    assert(!r.isError);
    assert(e.isUndefined(r.value));
    e.freeValue(r.value);
}

@Describe("type checks")
@Test("identifies null from eval")
void testIdentifiesNull(IJSEngine e)
{
    auto r = e.eval("null", "<test>");
    assert(!r.isError);
    assert(e.isNull(r.value));
    e.freeValue(r.value);
}

@Describe("type checks")
@Test("identifies functions from eval")
void testIdentifiesFunctions(IJSEngine e)
{
    auto r = e.eval("(function(){})", "<test>");
    assert(!r.isError);
    assert(e.isFunction(r.value));
    e.freeValue(r.value);
}

// --- property access ------------------------------------------------------

@Describe("property access")
@Test("sets and gets integer properties")
void testPropertyInt(IJSEngine e)
{
    auto obj = e.newObject();
    auto val = e.newInt(99);
    e.setProperty(obj, "x", val);
    auto got = e.getProperty(obj, "x");
    assert(e.extractInt(got) == 99);
    e.freeValue(got);
    e.freeValue(obj);
}

@Describe("property access")
@Test("sets and gets string properties")
void testPropertyString(IJSEngine e)
{
    auto obj = e.newObject();
    auto val = e.newString("world");
    e.setProperty(obj, "greeting", val);
    auto got = e.getProperty(obj, "greeting");
    assert(e.extractString(got) == "world");
    e.freeValue(got);
    e.freeValue(obj);
}

@Describe("property access")
@Test("returns undefined for missing properties")
void testPropertyMissing(IJSEngine e)
{
    auto obj = e.newObject();
    auto got = e.getProperty(obj, "nonexistent");
    assert(e.isUndefined(got));
    e.freeValue(got);
    e.freeValue(obj);
}

@Describe("property access")
@Test("accesses global object")
void testGlobalObject(IJSEngine e)
{
    auto g = e.getGlobal();
    assert(e.isObject(g));
    e.freeValue(g);
}

@Describe("property access")
@Test("sets global properties visible to eval")
void testGlobalPropertyEval(IJSEngine e)
{
    auto g = e.getGlobal();
    auto val = e.newInt(777);
    e.setProperty(g, "__test_val", val);
    e.freeValue(g);

    auto r = e.eval("__test_val", "<test>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 777);
    e.freeValue(r.value);
}

// --- eval -----------------------------------------------------------------

@Describe("eval")
@Test("evaluates arithmetic")
void testEvalArithmetic(IJSEngine e)
{
    auto r = e.eval("1 + 2", "<test>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 3);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates multiplication")
void testEvalMultiplication(IJSEngine e)
{
    auto r = e.eval("6 * 7", "<test>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 42);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates string concatenation")
void testEvalStringConcat(IJSEngine e)
{
    auto r = e.eval("'hello' + ' ' + 'world'", "<test>");
    assert(!r.isError);
    assert(e.extractString(r.value) == "hello world");
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates template literals")
void testEvalTemplateLiterals(IJSEngine e)
{
    auto r = e.eval("`sum: ${1+2}`", "<test>");
    assert(!r.isError);
    assert(e.extractString(r.value) == "sum: 3");
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates boolean expressions")
void testEvalBooleanExpr(IJSEngine e)
{
    auto r = e.eval("true === true", "<test>");
    assert(!r.isError);
    assert(e.extractBool(r.value) == true);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates object literals")
void testEvalObjectLiterals(IJSEngine e)
{
    auto r = e.eval("({a: 1})", "<test>");
    assert(!r.isError);
    assert(e.isObject(r.value));
    auto a = e.getProperty(r.value, "a");
    assert(e.extractInt(a) == 1);
    e.freeValue(a);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates array literals")
void testEvalArrayLiterals(IJSEngine e)
{
    auto r = e.eval("[1,2,3]", "<test>");
    assert(!r.isError);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates arrow functions")
void testEvalArrowFunctions(IJSEngine e)
{
    auto r = e.eval("((x) => x * 2)(21)", "<test>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 42);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("reports syntax errors")
void testEvalSyntaxErrors(IJSEngine e)
{
    auto r = e.eval("function(", "<test>");
    assert(r.isError);
    assert(r.errorMessage.length > 0);
}

@Describe("eval")
@Test("reports reference errors")
void testEvalReferenceErrors(IJSEngine e)
{
    auto r = e.eval("undefined_var.prop", "<test>");
    assert(r.isError);
}

@Describe("eval")
@Test("reports type errors")
void testEvalTypeErrors(IJSEngine e)
{
    auto r = e.eval("null.prop", "<test>");
    assert(r.isError);
}

@Describe("eval")
@Test("evaluates JSON operations")
void testEvalJSON(IJSEngine e)
{
    auto r = e.eval("JSON.stringify({a:1})", "<test>");
    assert(!r.isError);
    assert(e.extractString(r.value) == `{"a":1}`);
    e.freeValue(r.value);
}

@Describe("eval")
@Test("evaluates Math operations")
void testEvalMath(IJSEngine e)
{
    auto r = e.eval("Math.max(1, 2, 3)", "<test>");
    assert(!r.isError);
    assert(e.extractInt(r.value) == 3);
    e.freeValue(r.value);
}

// --- reference management -------------------------------------------------

@Describe("reference management")
@Test("duplicates values")
void testDuplicatesValues(IJSEngine e)
{
    auto h = e.newString("dup me");
    auto h2 = e.dupValue(h);
    assert(e.extractString(h2) == "dup me");
    e.freeValue(h2);
    e.freeValue(h);
}

@Describe("reference management")
@Test("duplicate is independent")
void testDuplicateIsIndependent(IJSEngine e)
{
    auto h = e.newInt(123);
    auto h2 = e.dupValue(h);
    e.freeValue(h);
    assert(e.extractInt(h2) == 123);
    e.freeValue(h2);
}

// --- exceptions -----------------------------------------------------------

@Describe("exceptions")
@Test("detects runtime errors")
void testDetectsRuntimeErrors(IJSEngine e)
{
    auto r = e.eval("undefined_var.prop", "<test>");
    assert(r.isError);
    assert(r.errorMessage.length > 0);
}

@Describe("exceptions")
@Test("throws TypeError")
void testThrowsTypeError(IJSEngine e)
{
    auto r = e.eval("null()", "<test>");
    assert(r.isError);
}

@Describe("exceptions")
@Test("throws RangeError")
void testThrowsRangeError(IJSEngine e)
{
    auto r = e.eval("new Array(-1)", "<test>");
    assert(r.isError);
}

@Describe("exceptions")
@Test("catches and rethrows")
void testCatchesAndRethrows(IJSEngine e)
{
    auto r = e.eval("try { throw new Error('test'); } catch(e) { e.message }", "<test>");
    assert(!r.isError);
    assert(e.extractString(r.value) == "test");
    e.freeValue(r.value);
}

// --- microtask queue ------------------------------------------------------

@Describe("microtask queue")
@Test("drains empty queue without hanging")
void testDrainEmptyQueue(IJSEngine e)
{
    e.drainJobs();
}

@Describe("microtask queue")
@Test("has no pending jobs initially")
void testNoPendingJobsInitially(IJSEngine e)
{
    assert(!e.hasPendingJobs());
}

@Describe("microtask queue")
@Test("resolves promises via drainJobs")
void testResolvesPromises(IJSEngine e)
{
    auto r = e.eval("Promise.resolve(42).then(v => globalThis.__promiseResult = v)", "<test>");
    assert(!r.isError);
    e.freeValue(r.value);

    e.drainJobs();

    auto r2 = e.eval("globalThis.__promiseResult", "<test>");
    assert(!r2.isError);
    assert(e.extractInt(r2.value) == 42);
    e.freeValue(r2.value);
}

// --- context opaque data --------------------------------------------------

@Describe("context opaque data")
@Test("stores and retrieves opaque pointer")
void testContextOpaque(IJSEngine e) @trusted
{
    int data = 12345;
    e.setContextOpaque(cast(void*)&data);
    auto got = cast(int*) e.getContextOpaque();
    assert(*got == 12345);
}

// ---------------------------------------------------------------------------
// Per-backend test instantiation via EngineTestRunner
// ---------------------------------------------------------------------------

mixin EngineTestRunner!("Engine Contract Tests", dun.engine.test);
