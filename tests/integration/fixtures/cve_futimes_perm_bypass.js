// v1.1.31 — verify fs.futimesSync permission gate (CVE-2025-55132
// class, Node Jan-2026 / Mar-2026 incomplete-fix follow-up to
// CVE-2024-36137). Before the fix, `futimesSync(fd, a, m)` ran
// `futimens()` with no permission check, so a process granted only
// `--allow-read` could open a file read-only and then forge mtime/atime
// (anti-forensics / log tamper). Fix gates on global `--allow-write`
// since the fd has no resolved path to validate against a scope.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-cve-futimes-"));
const target = path.join(dir, "log.txt");
fs.writeFileSync(target, "stable-mtime-content");
const origMtime = Math.floor(fs.statSync(target).mtimeMs / 1000);

function writeProbe(name, body) {
  const p = path.join(dir, name);
  fs.writeFileSync(p, body);
  return p;
}

// Probe opens the file under --allow-read=<dir> (read-only) then tries
// to futimes it. Without the gate this succeeds silently and the file's
// mtime gets clobbered.
const probe = writeProbe("probe.js",
  `const fs = require("fs");` +
  `const target = process.argv[2];` +
  `const fd = fs.openSync(target, "r");` +
  `try { fs.futimesSync(fd, 0, 0); console.log("FORGED"); }` +
  `catch (e) { console.log("BLOCKED:" + (e.message.match(/Requires --allow-write|EPERM|EACCES/) || ["ERR"])[0]); }` +
  `finally { try { fs.closeSync(fd); } catch {} }`);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

function run(flags, target) {
  const r = Bun.spawnSync({ cmd: [exe, "run", ...flags, probe, target] });
  return new TextDecoder().decode(r.stdout || Buffer.alloc(0));
}

// 1. --allow-read only: futimes MUST be blocked.
const r1 = run(["--allow-read=" + dir], target);
ok("futimes blocked under --allow-read only", r1.indexOf("BLOCKED:") >= 0);
ok("futimes did not forge under --allow-read", r1.indexOf("FORGED") < 0);

// 2. --allow-write scoped to dir: still MUST be blocked — fd has no
//    path to match against the scope.
const r2 = run(["--allow-read=" + dir, "--allow-write=" + dir], target);
ok("futimes blocked under scoped --allow-write (no fd→path resolution)",
   r2.indexOf("BLOCKED:") >= 0);

// 3. Global --allow-write: MUST succeed.
const r3 = run(["--allow-read=" + dir, "--allow-write"], target);
ok("futimes allowed under global --allow-write", r3.indexOf("FORGED") >= 0);

// 4. --allow-all: MUST succeed.
const r4 = run(["--allow-all"], target);
ok("futimes allowed under --allow-all", r4.indexOf("FORGED") >= 0);

// 5. Verify the file was actually mutated only in cases that succeeded
//    (post-test sanity — make sure the syscall was wired correctly).
const finalMtime = Math.floor(fs.statSync(target).mtimeMs / 1000);
ok("file mtime mutated by at least one successful run",
   finalMtime !== origMtime);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
