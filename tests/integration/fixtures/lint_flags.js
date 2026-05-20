// v0.8.2 — lint CI flags: --quiet (errors only) + --max-warnings=N
// (warning cap that fails CI).
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-lint-flags-"));
const target = path.join(dir, "sample.js");
fs.writeFileSync(target, `var x = 1;
if (x == 5) {}
debugger;
`);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

/* default: prints all 4 diagnostics, exit 1 (1 error) */
const r1 = Bun.spawnSync({ cmd: [exe, "lint", target] });
const out1 = new TextDecoder().decode(r1.stdout);
ok("default exits 1 (1 error)", r1.exitCode === 1);
ok("default prints 4 diagnostics",
   (out1.match(/^\/.+?:\d+:\d+/gm) || []).length === 4);

/* --quiet: hides warnings, shows only the 1 error */
const r2 = Bun.spawnSync({ cmd: [exe, "lint", "--quiet", target] });
const out2 = new TextDecoder().decode(r2.stdout);
ok("--quiet exits 1 (1 error)", r2.exitCode === 1);
ok("--quiet hides warnings",
   (out2.match(/^\/.+?:\d+:\d+/gm) || []).length === 1);
ok("--quiet shows error", out2.indexOf("no-debugger") >= 0);
ok("--quiet hides no-var warning", out2.indexOf("no-var") < 0);

/* --max-warnings=0 with only warnings (no errors) → exit 1 */
const target2 = path.join(dir, "warn_only.js");
fs.writeFileSync(target2, "var x = 1;\n");
const r3 = Bun.spawnSync({ cmd: [exe, "lint", "--max-warnings=0", target2] });
ok("--max-warnings=0 exits 1 (cap exceeded)", r3.exitCode === 1);
const out3 = new TextDecoder().decode(r3.stdout);
ok("--max-warnings cap message",
   out3.indexOf("exceeds --max-warnings=0") >= 0);

/* --max-warnings=5 with 1 warning → exit 0 */
const r4 = Bun.spawnSync({ cmd: [exe, "lint", "--max-warnings=5", target2] });
ok("--max-warnings=5 exits 0 (under cap)", r4.exitCode === 0);

/* --quiet + --max-warnings=0 with only warnings → exit 1 (cap)
   but output is empty (quiet) */
const r5 = Bun.spawnSync({ cmd: [exe, "lint", "--quiet", "--max-warnings=0", target2] });
ok("--quiet --max-warnings=0 exits 1", r5.exitCode === 1);
const out5 = new TextDecoder().decode(r5.stdout);
ok("--quiet --max-warnings=0 hides individual warnings",
   (out5.match(/^\/.+?:\d+:\d+/gm) || []).length === 0);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
