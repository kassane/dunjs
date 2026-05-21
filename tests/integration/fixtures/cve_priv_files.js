// CVE-2024-34346 / GHSA-23rx-c3g5-hv9w class regression check.
// Global --allow-read MUST NOT grant access to /proc /sys /dev /etc
// on POSIX (or \\?\ \\.\ on Windows). Mirrors the Deno 1.43 fix.
// Run with: dun run --allow-read tests/integration/fixtures/cve_priv_files.js
const fs = require("fs");

function expectDenied(path) {
  try {
    fs.readFileSync(path);
    console.log("FAIL: " + path + " was readable with global --allow-read");
  } catch (e) {
    if (String(e.message || e).includes("ermission") ||
        String(e.code || "") === "ERR_PERMISSION_DENIED") {
      console.log("OK: " + path + " blocked");
    } else {
      console.log("OK: " + path + " errored (" + String(e.code || "?") + ")");
    }
  }
}

expectDenied("/proc/self/environ");
expectDenied("/proc/self/maps");
expectDenied("/etc/passwd");
expectDenied("/etc/hostname");
expectDenied("/dev/null");
expectDenied("/proc/cpuinfo");
expectDenied("/sys/devices");
expectDenied("/etc");
