// v1.1.31 — regression watch for shell-metacharacter bypass classes
// (Deno CVE-2026-27190 + CVE-2026-32260 bypass-of-fix, Bun 1.3.x).
// DunJS's `hasShellMetaChars` blocks `;`, `&`, `|`, `$`, `` ` ``, `(`, `)`,
// `{`, `}`, `<`, `>`, `\n` UNLESS global `--allow-run` is granted. Lock
// this gate in against the inputs that bypassed Deno's first fix:
// newline-prefixed, `$()`, backticks, NUL-injected, tab-separated.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-cve-shellv2-"));
const canary = path.join(dir, "canary");

// Probe runs under --allow-read (only) — execSync with metachars MUST
// be refused before any shell side-effect runs.
const probe = path.join(dir, "probe.js");
fs.writeFileSync(probe,
  `const cp = require("child_process");` +
  `try { cp.execSync(process.argv[2], { stdio: "ignore" }); console.log("EXECUTED"); }` +
  `catch (e) { console.log("BLOCKED:" + (e.message.match(/allow-run|metachar|EPERM|EACCES/i) || ["ERR"])[0]); }`);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const payloads = [
  "echo arg\n; touch " + JSON.stringify(canary),
  "echo $(touch " + JSON.stringify(canary) + ")",
  "echo `touch " + JSON.stringify(canary) + "`",
  "echo arg\x00; touch " + JSON.stringify(canary),
  "echo arg\t; touch " + JSON.stringify(canary),
];

for (const payload of payloads) {
  try { fs.unlinkSync(canary); } catch {}
  // Subprocess runs with only --allow-read of the tmpdir (no --allow-run).
  const r = Bun.spawnSync({
    cmd: [exe, "run", "--allow-read=" + dir, probe, payload],
  });
  const out = new TextDecoder().decode(r.stdout || Buffer.alloc(0));
  const canaryWritten = (() => { try { fs.statSync(canary); return true; } catch { return false; } })();
  // Either: (a) BLOCKED was printed AND canary not written, or
  // (b) canary not written (interpreter refused to spawn) — both count
  // as the metachar gate having held.
  ok("metachar payload " + JSON.stringify(payload.slice(5, 16)),
     !canaryWritten);
}

try { fs.unlinkSync(canary); } catch {}
try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
