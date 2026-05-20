// v0.8.1 — additional lint rules: no-var, no-empty-block.
// Verifies that `dun lint` detects each + that --fix rewrites
// `var` to `let` (no-empty-block is report-only).
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-lint-more-"));
const target = path.join(dir, "rules.js");
const before = `var oldStyle = 1;
let always = "ok";
if (oldStyle == 5) {}
function noop() {}
`;
fs.writeFileSync(target, before);

const exe = process.execPath;
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

/* lint without --fix surfaces all 4 violations */
const r = Bun.spawnSync({ cmd: [exe, "lint", target] });
const out = r.stdout ? new TextDecoder().decode(r.stdout) : "";
ok("no-var detected", out.indexOf("no-var") >= 0);
ok("eqeqeq detected", out.indexOf("eqeqeq") >= 0);
ok("no-empty-block detected (twice)",
   (out.match(/no-empty-block/g) || []).length === 2);
ok("[fixable] annotation on no-var", /no-var\s+\[fixable\]/.test(out));
ok("no-empty-block has no [fixable]", !/empty block.*\[fixable\]/.test(out));

/* --fix rewrites var → let; empty blocks stay */
const r2 = Bun.spawnSync({ cmd: [exe, "lint", "--fix", target] });
const after = fs.readFileSync(target, "utf-8");
ok("var rewritten to let", /^let oldStyle = 1;/.test(after));
ok("eqeqeq fixed", after.indexOf("=== 5") >= 0);
ok("empty blocks remain (no-fix)", after.indexOf("{}") >= 0);

/* idempotent */
const r3 = Bun.spawnSync({ cmd: [exe, "lint", "--fix", target] });
const after2 = fs.readFileSync(target, "utf-8");
ok("--fix idempotent", after === after2);

/* second lint reports only no-empty-block (warns, not errors → exit 0) */
const r4 = Bun.spawnSync({ cmd: [exe, "lint", target] });
ok("post-fix lint exits 0 (warns only)", r4.success === true);
const out4 = r4.stdout ? new TextDecoder().decode(r4.stdout) : "";
ok("post-fix output mentions no-empty-block",
   out4.indexOf("no-empty-block") >= 0);
ok("post-fix output does NOT mention no-var",
   out4.indexOf("no-var") < 0);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
