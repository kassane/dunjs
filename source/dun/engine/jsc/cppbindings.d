module dun.engine.jsc.cppbindings;


/++
 + `@trusted policy`: D template metaprogramming bridge to JSC's
 + C API type tags. `@trusted` for the function pointer table init
 + + lazy-init lock. Single-threaded init.
 + JSC type tag — values 0-6 match kJSType* constants.
 +/
enum JSCTypeTag
{
    Undefined = 0,
    Null = 1,
    Boolean = 2,
    Number = 3,
    String = 4,
    Object = 5,
    Symbol = 6,
    Array,
    Function,
    Date,
}

static assert(__traits(allMembers, JSCTypeTag).length == 10,
    "JSCTypeTag member count changed -- update JSCTypeChecks table and JSCTypeName template");

// Verify basic types match kJSType* enum values from JSC C API
static assert(JSCTypeTag.Undefined == 0 && JSCTypeTag.Null == 1
    && JSCTypeTag.Boolean == 2 && JSCTypeTag.Number == 3
    && JSCTypeTag.String == 4 && JSCTypeTag.Object == 5
    && JSCTypeTag.Symbol == 6,
    "JSCTypeTag basic type ordinals must match kJSType* constants");

// FFI pointer size guarantee
static assert((void*).sizeof == size_t.sizeof,
    "pointer/size_t size mismatch for C FFI");

/// JSCTypeTag → display name.
template JSCTypeName(JSCTypeTag tag)
{
    static if (tag == JSCTypeTag.Undefined) enum JSCTypeName = "undefined";
    else static if (tag == JSCTypeTag.Null) enum JSCTypeName = "null";
    else static if (tag == JSCTypeTag.Boolean) enum JSCTypeName = "boolean";
    else static if (tag == JSCTypeTag.Number) enum JSCTypeName = "number";
    else static if (tag == JSCTypeTag.String) enum JSCTypeName = "string";
    else static if (tag == JSCTypeTag.Object) enum JSCTypeName = "object";
    else static if (tag == JSCTypeTag.Symbol) enum JSCTypeName = "symbol";
    else static if (tag == JSCTypeTag.Array) enum JSCTypeName = "array";
    else static if (tag == JSCTypeTag.Function) enum JSCTypeName = "function";
    else static if (tag == JSCTypeTag.Date) enum JSCTypeName = "date";
}

version (EngineJSC)
{
    import dun.engine.jsc.bindings;

    /// Type-check dispatch table for JSC values.
    struct JSCTypeChecks
    {
        alias CheckFn = extern (C) bool function(JSContextRef, JSValueRef) nothrow @nogc;
        CheckFn[JSCTypeTag.max + 1] table;

        static JSCTypeChecks create() @trusted nothrow @nogc
        {
            JSCTypeChecks tc;
            tc.table[JSCTypeTag.Undefined] = &JSValueIsUndefined;
            tc.table[JSCTypeTag.Null] = &JSValueIsNull;
            tc.table[JSCTypeTag.Boolean] = &JSValueIsBoolean;
            tc.table[JSCTypeTag.Number] = &JSValueIsNumber;
            tc.table[JSCTypeTag.String] = &JSValueIsString;
            tc.table[JSCTypeTag.Object] = &JSValueIsObject;
            tc.table[JSCTypeTag.Symbol] = &JSValueIsSymbol;
            tc.table[JSCTypeTag.Array] = &JSValueIsArray;
            tc.table[JSCTypeTag.Date] = &JSValueIsDate;
            return tc;
        }

        /// Function tag needs JSObjectIsFunction (not in JSValueGetType).
        bool check(JSCTypeTag tag, JSContextRef ctx, JSValueRef val) @trusted nothrow @nogc
        {
            assert(ctx !is null, "Null JSContextRef in JSCTypeChecks.check");
            assert(cast(size_t) tag <= JSCTypeTag.max, "JSCTypeTag out of range");
            if (tag == JSCTypeTag.Function)
            {
                if (!JSValueIsObject(ctx, val))
                    return false;
                JSValueRef exc = null;
                auto obj = JSValueToObject(ctx, val, &exc);
                return obj !is null && JSObjectIsFunction(ctx, obj);
            }
            return table[tag](ctx, val);
        }

        /// Single JSValueGetType() call — basic types only (not Array/Function/Date).
        static JSCTypeTag getType(JSContextRef ctx, JSValueRef val) @trusted nothrow @nogc
        {
            return cast(JSCTypeTag) JSValueGetType(ctx, val);
        }

        /// JS typeof semantics.
        static string typeofString(JSContextRef ctx, JSValueRef val) @trusted nothrow
        {
            final switch (getType(ctx, val))
            {
                case JSCTypeTag.Undefined: return "undefined";
                case JSCTypeTag.Null: return "object";
                case JSCTypeTag.Boolean: return "boolean";
                case JSCTypeTag.Number: return "number";
                case JSCTypeTag.String: return "string";
                case JSCTypeTag.Symbol: return "symbol";
                case JSCTypeTag.Object:
                {
                    JSValueRef exc = null;
                    auto obj = JSValueToObject(ctx, val, &exc);
                    if (obj !is null && JSObjectIsFunction(ctx, obj))
                        return "function";
                    return "object";
                }
                case JSCTypeTag.Array: return "object";
                case JSCTypeTag.Function: return "function";
                case JSCTypeTag.Date: return "object";
            }
        }
    }

    unittest
    {
        // Verify basic JSCTypeTag values match kJSType* constants
        static assert(cast(uint) JSCTypeTag.Undefined == kJSTypeUndefined);
        static assert(cast(uint) JSCTypeTag.Null == kJSTypeNull);
        static assert(cast(uint) JSCTypeTag.Boolean == kJSTypeBoolean);
        static assert(cast(uint) JSCTypeTag.Number == kJSTypeNumber);
        static assert(cast(uint) JSCTypeTag.String == kJSTypeString);
        static assert(cast(uint) JSCTypeTag.Object == kJSTypeObject);
        static assert(cast(uint) JSCTypeTag.Symbol == kJSTypeSymbol);
    }
}

unittest
{
    // Verify TMP name mapping covers all tags (no JSC dependency)
    static foreach (tag; __traits(allMembers, JSCTypeTag))
    {{
        enum t = __traits(getMember, JSCTypeTag, tag);
        static assert(JSCTypeName!t.length > 0,
            "Missing JSCTypeName for " ~ tag);
    }}
}

// Experimental C++ bindings — JSC C++ API is unstable across WebKit releases.
version (EngineJSC)
{
    extern (C++, "JSC")
    {
        enum HeapType : ubyte
        {
            SmallHeap = 0,
            LargeHeap = 1,
        }

        // C++ `class SourceOrigin` carries no D-side state — bind as
        // value-type struct (matches the C++ class layout) rather
        // than D reference class.
        extern (C++, class) struct SourceOrigin
        {
        }

        struct JSCValue
        {
            long encoded;
        }

        enum CallMode : ubyte
        {
            None = 0,
            Host = 1,
            JS = 2,
        }
    }

    unittest
    {
        version (DunTest)
        {
            static assert(JSCValue.sizeof == 8);
            static assert(is(typeof(HeapType.SmallHeap)));
        }
    }
}
