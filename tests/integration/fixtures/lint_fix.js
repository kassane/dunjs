// v0.8.0 — `dun lint --fix` self-test driven from JS.
// Writes a sample file with eqeqeq + no-debugger violations, shells
// out to `dun lint --fix`, then verifies the file got rewritten
// correctly. Uses Bun.spawnSync for portability across backends.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-lint-fix-"));
const target = path.join(dir, "sample.js");
const before = `let x = 1;
if (x == 5) console.log("ee");
debugger;
if (x != 0) {
  console.log("nz");
}
`;
fs.writeFileSync(target, before);

/* process.execPath is the resolved binary; argv[0] is the
   short name. Bun.spawnSync needs the resolved path. */
const exe = process.execPath || process.argv[0];
const r = Bun.spawnSync({ cmd: [exe, "lint", "--fix", target] });
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

ok("dun lint --fix exits 0", r.success === true);
const after = fs.readFileSync(target, "utf-8");
/* "=== 5" contains "== 5" as a substring, so we check via a regex
   word boundary instead of a raw indexOf. */
ok("eqeqeq fixed to ===", /[^=]=== 5/.test(after) && !/[^=]== 5/.test(after));
ok("eqeqeq fixed to !==", /[^!]!== 0/.test(after) && !/[^!]!= 0/.test(after));
ok("no-debugger statement removed", after.indexOf("debugger") < 0);

// Re-run lint without --fix to confirm clean
const r2 = Bun.spawnSync({ cmd: [exe, "lint", target] });
ok("lint after --fix exits 0", r2.success === true);

// Verify --fix is idempotent (running it again is a no-op)
const r3 = Bun.spawnSync({ cmd: [exe, "lint", "--fix", target] });
const after2 = fs.readFileSync(target, "utf-8");
ok("--fix is idempotent", after === after2);
ok("idempotent --fix exits 0", r3.success === true);

try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
