/// V8-only diagnostics global. Wires `v8shim::Diagnostics` (C++
/// static-method class in `vendor/v8shim/v8shim.cpp`) to
/// `globalThis.__dun_v8shim_diag__()` via direct
/// `extern(C++, "v8shim")` — no `extern(C)` wrapper in between.
/// Research doc §10 has the FFI rationale + symbol-mangling table.

module dun.runtime.v8shim_diag;

version (EngineV8):

import dun.engine.iface : IJSEngine, JSHandle;
import dun.engine.v8.cppbindings : Diagnostics,
    tmpCounter0Increment, tmpCounter0Read,
    tmpCounter1Increment, tmpCounter1Read;
import std.string : fromStringz;

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
    assert(state !is null, "Null DunState in jsV8ShimDiag");
    assert(state.engine !is null, "Null engine in jsV8ShimDiag");
    auto engine = state.engine;

    auto poolFree   = Diagnostics.valuePoolFreeCount();
    auto totAlloc   = Diagnostics.totalAllocs();
    auto totRelease = Diagnostics.totalReleases();
    auto live       = Diagnostics.liveCount();
    auto verCstr    = Diagnostics.shimVersion();
    auto probe      = Diagnostics.probeBumpCounter();

    // D ↔ C++ TMP FFI: each call resolves to
    // `v8shim::TypedCounter<N>::increment()` — an explicit C++ template
    // instantiation — via pragma(mangle). Validates the TMP path is
    // live, not just declared. See research doc §11.
    auto tmp0 = tmpCounter0Increment();
    auto tmp1 = tmpCounter1Increment();

    string verStr = verCstr is null ? "" : cast(string) fromStringz(verCstr);

    auto obj = engine.newObject();
    setNum(engine, obj, "valuePoolFree", poolFree);
    setNum(engine, obj, "totalAllocs",   totAlloc);
    setNum(engine, obj, "totalReleases", totRelease);
    setNum(engine, obj, "liveCount",     live);
    setNum(engine, obj, "probe",         cast(size_t) probe);
    setNum(engine, obj, "tmpCounter0",   cast(size_t) tmp0);
    setNum(engine, obj, "tmpCounter1",   cast(size_t) tmp1);
    auto verH = engine.newString(verStr);
    engine.setProperty(obj, "shimVersion", verH);
    engine.freeValue(verH);
    return obj;
}

/// size_t can exceed `int` range on long-running counters, so use
/// `newFloat` (IEEE 754 double, exact for integers up to 2^53).
private void setNum(IJSEngine engine, JSHandle obj, string key, size_t val) @trusted
{
    assert(engine !is null, "Null engine in setNum");
    auto h = engine.newFloat(cast(double) val);
    engine.setProperty(obj, key, h);
    engine.freeValue(h);
}
