module dun.engine.jsc.cppbindings;

// D TMP bridge for JavaScriptCore + experimental C++ bindings.
//
// Two sections:
//   1. D TMP bridge types (always available — pure D, used by backend.d)
//   2. C++ extern bindings (version-gated — only when EngineJSC selected)

// ---------------------------------------------------------------------------
// D TMP bridge (always available)
//
// JSC has a stable C API with JSValueGetType() returning a JSType enum,
// making it a natural fit for compile-time dispatch. Unlike V8 (which
// needs a C++ shim with isV8Type<Tag> + if constexpr), JSC's type system
// is directly accessible via a single C call.
//
// Pattern comparison:
//   V8:  isV8Type<Tag> dispatches via if constexpr → separate IsXxx() calls
//   JSC: JSValueGetType() returns tag directly → single call for basic types
//
// For composite types (Array, Function, Date) that JSType doesn't cover,
// we fall back to individual check functions (JSValueIsArray, etc.).
// ---------------------------------------------------------------------------

/// JSC type tag — mirrors kJSType* constants from JavaScriptCore C API.
/// Basic types (Undefined..Symbol) map 1:1 to JSType enum values.
/// Extended types (Array, Function, Date) require separate API calls.
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
    "JSCTypeTag member count changed — update JSCTypeChecks table and JSCTypeName template");

/// Compile-time map: JSCTypeTag → display name.
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

// JSCTypeChecks and its bindings-dependent methods are JSC-backend-only.
// They must be compiled as a module-level entity (not with a local struct import)
// so that the D compiler emits method bodies into the object file.
version (EngineJSC)
{
    import dun.engine.jsc.bindings;

    /// Type-check dispatch table for JSC values.
    ///
    /// Two dispatch strategies:
    ///   1. getType() — single JSValueGetType() call for basic types (O(1))
    ///   2. check(tag) — function pointer table for all types including extended
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

        /// Check if a value matches the given type tag.
        /// Function is handled specially (requires JSObjectIsFunction).
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

        /// Fast path: JSValueGetType() for the 7 basic types (single C call).
        /// Returns a JSCTypeTag in the Undefined..Symbol range.
        /// Does NOT detect Array/Function/Date — use check() for those.
        static JSCTypeTag getType(JSContextRef ctx, JSValueRef val) @trusted nothrow @nogc
        {
            return cast(JSCTypeTag) JSValueGetType(ctx, val);
        }

        /// JS typeof semantics using single-dispatch getType().
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

// ---------------------------------------------------------------------------
// C++ extern bindings (only when JSC engine selected)
//
// Experimental: Direct D → JSC/WebKit C++ bindings using extern(C++, ns).
// The C++ API is NOT stable across WebKit releases — use the C API
// (bindings.d) for production code.
// ---------------------------------------------------------------------------

version (EngineJSC)
{
    extern (C++, "JSC")
    {
        enum HeapType : ubyte
        {
            SmallHeap = 0,
            LargeHeap = 1,
        }

        extern class SourceOrigin
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
