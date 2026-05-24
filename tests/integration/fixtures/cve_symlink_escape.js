// v1.1.31 — verify the symlink permission-bypass fix (CVE-2025-55130
// class, Node.js Jan-2026 security release). Before the fix, the
// permission scope check canonicalized paths only *lexically*
// (`buildNormalizedPath`), which collapses `..`/`.` but does NOT
// follow symlinks. So a symlink placed INSIDE an --allow-read scope
// that targets a file OUTSIDE the scope passed the subpath check
// (the link path is under the scope dir) while the OS followed the
// link out of the sandbox. Fix: resolve symlinks via realpath(3) on
// both the resource and the scope before the subpath match.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-cve-sym-"));
const safe = path.join(dir, "safe");
fs.mkdirSync(safe);
fs.writeFileSync(path.join(safe, "real.txt"), "in-scope");

// A target file OUTSIDE the safe scope.
const secret = path.join(dir, "secret.txt");
fs.writeFileSync(secret, "out-of-scope-secret");

// Symlink INSIDE the safe scope that escapes to the secret.
const escapeLink = path.join(safe, "escape_link");
try { fs.symlinkSync(secret, escapeLink); } catch {}

// A legitimately symlinked scope dir: link -> realdata. Reading the
// real contents through the symlinked scope must NOT be falsely denied.
const realdata = path.join(dir, "realdata");
fs.mkdirSync(realdata);
fs.writeFileSync(path.join(realdata, "ok.txt"), "via-symlinked-scope");
const linkdir = path.join(dir, "linkdir");
try { fs.symlinkSync(realdata, linkdir); } catch {}

function writeProbe(name, body) {
  const p = path.join(dir, name);
  fs.writeFileSync(p, body);
  return p;
}

const probeRead = writeProbe("read.js",
  `try { console.log("READ:" + require("fs").readFileSync(process.argv[2], "utf-8").trim()); }` +
  `catch (e) { console.log("BLOCKED:" + e.message); }`);

const probeWrite = writeProbe("write.js",
  `try { require("fs").writeFileSync(process.argv[2], "x"); console.log("WROTE"); }` +
  `catch (e) { console.log("BLOCKED:" + e.message); }`);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

function run(probe, scopeFlag, scope_, target) {
  const r = Bun.spawnSync({
    cmd: [exe, "run", scopeFlag + "=" + scope_, probe, target],
  });
  return new TextDecoder().decode(r.stdout || Buffer.alloc(0));
}

// 1. Symlink escape (read) — MUST be blocked.
const escRead = run(probeRead, "--allow-read", safe, escapeLink);
ok("symlink read-escape blocked", escRead.indexOf("BLOCKED:") >= 0);
ok("symlink read-escape leaked no content", escRead.indexOf("out-of-scope-secret") < 0);

// 2. Legit in-scope read — MUST succeed.
const legitRead = run(probeRead, "--allow-read", safe, path.join(safe, "real.txt"));
ok("legit in-scope read succeeds", legitRead.indexOf("READ:in-scope") >= 0);

// 3. Read via a legitimately-symlinked scope dir — MUST succeed (no
//    false denial after symlink resolution).
const symScope = run(probeRead, "--allow-read", linkdir, path.join(linkdir, "ok.txt"));
ok("symlinked-scope read not falsely denied", symScope.indexOf("READ:via-symlinked-scope") >= 0);

// 4. Symlink escape (write to a new file through an escaping link
//    target) — MUST be blocked. escape_link -> secret.txt (a file),
//    so write through it targets the out-of-scope secret.
const escWrite = run(probeWrite, "--allow-write", safe, escapeLink);
ok("symlink write-escape blocked", escWrite.indexOf("BLOCKED:") >= 0);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
