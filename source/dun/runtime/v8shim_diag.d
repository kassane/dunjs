// V8-only diagnostics global — production validation of the
// extern(C++, "v8shim") FFI path. Forces D → C++ static-method
// calls without any extern(C) shim layer in between.
//
// Binding: `extern(C++, "v8shim")` in dun.engine.v8.cppbindings
// declares the v8shim::Diagnostics class; the linker resolves
// each static-method call to the Itanium-ABI-mangled symbol in
// vendor/v8shim/libv8shim.a. Validated symbol form:
//   _ZN6v8shim11Diagnostics18valuePoolFreeCountEv
//
// Exposes `globalThis.__dun_v8shim_diag__()` returning a plain JS
// object with the live alloc / pool stats. Useful for:
//   - regression testing (smoke fixture proves the C++ FFI works)
//   - operational visibility (Worker leak hunting, see PR #61)
//   - DunJS-specific perf observability (no Node.js equivalent)

module dun.runtime.v8shim_diag;

version (EngineV8):

import dun.engine.iface : IJSEngine, JSHandle;
import dun.engine.v8.cppbindings : Diagnostics;
import core.stdc.string : strlen;

void installV8ShimDiag(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in installV8ShimDiag");
    auto global = engine.getGlobal();
    scope(exit) engine.freeValue(global);
    auto fn = engine.newFunction(&jsV8ShimDiag, "__dun_v8shim_diag__", 0);
    engine.setProperty(global, "__dun_v8shim_diag__", fn);
}

private JSHandle jsV8ShimDiag(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    import dun.runtime.globals : DunState;
    assert(ctx !is null, "Null ctx in jsV8ShimDiag");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsV8ShimDiag");
    auto engine = state.engine;

    // Direct extern(C++, "v8shim") calls — no shim wrapper.
    // Each line below resolves to a mangled Itanium symbol at link
    // time; the link succeeds iff the v8shim::Diagnostics class
    // exists with matching signatures in libv8shim.a.
    auto poolFree   = Diagnostics.valuePoolFreeCount();
    auto totAlloc   = Diagnostics.totalAllocs();
    auto totRelease = Diagnostics.totalReleases();
    auto live       = Diagnostics.liveCount();
    auto verCstr    = Diagnostics.shimVersion();
    auto probe      = Diagnostics.probeBumpCounter();

    string verStr = verCstr is null ? "" :
        cast(string) verCstr[0 .. strlen(verCstr)];

    auto obj = engine.newObject();
    setNum(engine, obj, "valuePoolFree", poolFree);
    setNum(engine, obj, "totalAllocs",   totAlloc);
    setNum(engine, obj, "totalReleases", totRelease);
    setNum(engine, obj, "liveCount",     live);
    setNum(engine, obj, "probe",         cast(size_t) probe);
    auto verH = engine.newString(verStr);
    engine.setProperty(obj, "shimVersion", verH);
    engine.freeValue(verH);
    return obj;
}

private void setNum(IJSEngine engine, JSHandle obj, string key, size_t val) @trusted
{
    // size_t is 64-bit; D's newInt takes int. For pool depths /
    // probe counters this is safe; long-running alloc/release
    // counters will eventually saturate but that's deferred — the
    // smoke fixture only verifies single-digit values.
    auto h = engine.newFloat(cast(double) val);
    engine.setProperty(obj, key, h);
    engine.freeValue(h);
}
