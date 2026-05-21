// Smoke test for the extern(C++, "v8shim") FFI path.
// Validates that D can call C++ static methods directly via
// Itanium ABI mangling without an extern(C) shim layer in between.
// V8-only — QJS/JSC skip this fixture via .backends sidecar.
//
// Run: dun run tests/integration/fixtures/v8shim_extern_cpp.js

const diag = globalThis.__dun_v8shim_diag__;
if (typeof diag !== "function") {
  console.log("SKIP: __dun_v8shim_diag__ not present (non-V8 backend)");
  process.exit(0);
}

const a = diag();
const b = diag();

// shimVersion is a const C++ string sourced from build.d (which reads
// app.d's VERSION enum at configure time). Regex-match the shape so
// the fixture doesn't need a bump on every patch release.
console.log(/^v8shim-\d+\.\d+\.\d+$/.test(a.shimVersion)
  ? "OK shimVersion matches v8shim-<semver>"
  : "FAIL shimVersion = " + a.shimVersion);

// probe is a sequential counter — consecutive calls differ by exactly 1
console.log(b.probe === a.probe + 1
  ? "OK probe bumped by 1"
  : "FAIL probe did not bump: " + a.probe + " -> " + b.probe);

// totalAllocs is monotonically increasing — second call's value > first
console.log(b.totalAllocs > a.totalAllocs
  ? "OK totalAllocs grew between calls"
  : "FAIL totalAllocs did not grow: " + a.totalAllocs + " -> " + b.totalAllocs);

// liveCount = totalAllocs - totalReleases at the snapshot point
const expectedLive = a.totalAllocs - a.totalReleases;
console.log(Math.abs(a.liveCount - expectedLive) <= 16
  ? "OK liveCount ≈ totalAllocs - totalReleases"
  : "FAIL liveCount mismatch: " + a.liveCount + " vs " + expectedLive);

// valuePoolFree should be a small non-negative number
console.log(a.valuePoolFree >= 0 && a.valuePoolFree <= 512
  ? "OK valuePoolFree in range [0, 512]"
  : "FAIL valuePoolFree out of range: " + a.valuePoolFree);

// D ↔ C++ TMP FFI — each invocation of __dun_v8shim_diag__() calls
// v8shim::TypedCounter<0>::increment() once, so consecutive calls differ
// by 1. Proves the pragma(mangle) → C++ template instantiation path
// is live. Same check for TypedCounter<1>.
console.log(b.tmpCounter0 === a.tmpCounter0 + 1
  ? "OK D->C++ TMP counter<0> bumped by 1"
  : "FAIL TMP counter<0>: " + a.tmpCounter0 + " -> " + b.tmpCounter0);
console.log(b.tmpCounter1 === a.tmpCounter1 + 1
  ? "OK D->C++ TMP counter<1> bumped by 1"
  : "FAIL TMP counter<1>: " + a.tmpCounter1 + " -> " + b.tmpCounter1);
