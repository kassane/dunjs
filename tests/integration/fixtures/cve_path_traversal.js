// v1.1.0 — verify the path-traversal CVE fix (mirrors the class of
// CVE-2023-32004 and CVE-2024-21896 in Node.js, plus similar pre-2025
// Deno permission-bypass advisories). Before the fix, paths
// containing `..` segments bypassed --allow-read scope checks
// because the raw string was compared via `startsWith` without
// canonicalization.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-cve-pt-"));
const inside = path.join(dir, "file.txt");
fs.writeFileSync(inside, "inside");

/* Test scripts live in temp files (avoids stdin handling
   differences across backends). */
function writeProbe(name, body) {
  const p = path.join(dir, name);
  fs.writeFileSync(p, body);
  return p;
}

/* `process.argv[1]` is the script path; the target file is at `[2]`. */
const probeRead = writeProbe("read.js",
  `try { console.log("READ:" + require("fs").readFileSync(process.argv[2], "utf-8").trim()); }` +
  `catch (e) { console.log("BLOCKED:" + e.message); }`);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

function tryRead(scope_, target, cwd) {
  const r = Bun.spawnSync({
    cwd,
    cmd: [exe, "run", "--allow-read=" + scope_, probeRead, target],
  });
  return new TextDecoder().decode(r.stdout || Buffer.alloc(0));
}

/* Legit read inside the scope — must succeed. */
const okOut = tryRead(dir, inside);
ok("legit read inside scope succeeds", okOut.indexOf("READ:inside") >= 0);

/* Path traversal via .. — must be blocked. The pre-fix behavior
   allowed this because the literal prefix `<dir>/` matches. */
const escapePath = dir + "/../../etc/hostname";
const escapeOut = tryRead(dir, escapePath);
ok("path traversal via .. is blocked", escapeOut.indexOf("BLOCKED:") >= 0);
ok("path traversal didn't leak file content", escapeOut.indexOf("READ:") < 0);

/* Multiple `..` segments. */
const escapePath2 = dir + "/sub/../../../etc/hostname";
const escapeOut2 = tryRead(dir, escapePath2);
ok("nested .. traversal blocked", escapeOut2.indexOf("BLOCKED:") >= 0);

/* Absolute path NOT under the scope — also blocked. */
const outsideOut = tryRead(dir, "/etc/hostname");
ok("absolute path outside scope blocked", outsideOut.indexOf("BLOCKED:") >= 0);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
