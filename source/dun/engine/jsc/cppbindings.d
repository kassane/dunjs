module dun.engine.jsc.cppbindings;

// Experimental: Direct D → JSC/WebKit C++ bindings using extern(C++, ns).
//
// JavaScriptCore has a stable C API (JSC/*.h) which is the recommended
// interface and what bindings.d uses. However, the C++ internals in the
// JSC:: and WTF:: namespaces expose additional capabilities:
//
//   - JSC::JSGlobalObject — direct global object access
//   - JSC::VM — the JS virtual machine (GC, compilation tiers)
//   - JSC::JSValue — the tagged value type (NaN-boxing)
//   - WTF::String — WebKit's string type
//
// IMPORTANT: The C++ API is NOT stable across WebKit releases.
// Use the C API (bindings.d) for production code. These bindings
// are experimental and only useful for:
//   1. Performance-critical paths that need to skip C API overhead
//   2. Accessing features not exposed by the C API (e.g., JIT tiers)
//   3. Research and benchmarking
//
// JSC uses the "Objective-C++" convention on macOS, but on Linux
// with libjavascriptcoregtk, it's pure C++.

version (EngineJSC):

// --- WTF:: namespace (WebKit Template Framework) ---
extern (C++, "WTF")
{
    // WTF::String — WebKit's string type (ref-counted, UTF-16 internal)
    extern class String
    {
        bool isNull() const;
        bool isEmpty() const;
        uint length() const;
    }

    extern class StringImpl
    {
        uint length() const;
        bool is8Bit() const;
    }
}

// --- JSC:: namespace ---
extern (C++, "JSC")
{
    // JSC::HeapType — used in VM creation
    enum HeapType : ubyte
    {
        SmallHeap = 0,
        LargeHeap = 1,
    }

    // JSC::SourceOrigin — identifies script source
    extern class SourceOrigin
    {
    }

    // JSC::JSValue — the core tagged value (64-bit NaN-boxed on 64-bit)
    // WARNING: This is a value type in C++, not a class. D extern(C++)
    // classes map to C++ classes with vtables. JSValue has no vtable,
    // so we model it as a struct.
    struct JSCValue
    {
        long encoded;
    }

    // JSC::CallData — describes how to call a function
    enum CallMode : ubyte
    {
        None = 0,
        Host = 1,
        JS = 2,
    }
}

// --- Why extern(C) is preferred for JSC ---
//
// JSC's public C API (JavaScriptCore/JavaScript.h) is:
//   1. Stable across WebKit releases
//   2. Available on macOS (framework), Linux (libjavascriptcoregtk), iOS
//   3. Well-documented by Apple
//   4. Uses opaque types that hide implementation details
//
// The C++ internals (JSC::VM, JSC::JSGlobalObject) are:
//   1. Unstable — layouts change between WebKit versions
//   2. Header-only templates in many cases
//   3. Tightly coupled to WTF:: types
//   4. Different on Apple platforms vs GTK port
//
// Verdict: Use extern(C) bindings.d for production,
// extern(C++, "JSC") only for experimental/research work.

unittest
{
    version (DunTest)
    {
        // Compile-time verification of type layouts
        static assert(JSCValue.sizeof == 8);
        static assert(is(typeof(HeapType.SmallHeap)));
    }
}
