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

// shimVersion is a const C++ string — must equal v8shim-1.1.25
console.log(a.shimVersion === "v8shim-1.1.25"
  ? "OK shimVersion = " + a.shimVersion
  : "FAIL shimVersion = " + a.shimVersion);

// probe is a counter — second call must equal first + 1
console.log(b.probe === a.probe + 1
  ? "OK probe bumped (" + a.probe + " -> " + b.probe + ")"
  : "FAIL probe did not bump: " + a.probe + " -> " + b.probe);

// totalAllocs is monotonically increasing — second call's value > first
console.log(b.totalAllocs > a.totalAllocs
  ? "OK totalAllocs grew (" + a.totalAllocs + " -> " + b.totalAllocs + ")"
  : "FAIL totalAllocs did not grow: " + a.totalAllocs + " -> " + b.totalAllocs);

// liveCount = totalAllocs - totalReleases at the snapshot point
const expectedLive = a.totalAllocs - a.totalReleases;
console.log(Math.abs(a.liveCount - expectedLive) <= 16
  ? "OK liveCount ≈ totalAllocs - totalReleases (within race window)"
  : "FAIL liveCount mismatch: " + a.liveCount + " vs " + expectedLive);

// valuePoolFree should be a small non-negative number
console.log(a.valuePoolFree >= 0 && a.valuePoolFree <= 512
  ? "OK valuePoolFree in range [0, 512]: " + a.valuePoolFree
  : "FAIL valuePoolFree out of range: " + a.valuePoolFree);
