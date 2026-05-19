// v0.9.0 — `dun bundle --compile=PATH` produces a self-contained
// executable. Test: compile a hello-world script, run the produced
// binary, verify it prints the expected output + passes argv through.
const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-compile-"));
const entry = path.join(dir, "entry.js");
fs.writeFileSync(entry, `console.log("hello", process.argv.slice(1).join(","));\n`);

const exe = process.execPath;
const outPath = path.join(dir, "hello-bin");
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

/* Step 1: bundle + compile */
const compileR = Bun.spawnSync({ cmd: [exe, "bundle", entry, "--compile=" + outPath] });
ok("compile exits 0", compileR.exitCode === 0);
ok("output file exists", fs.existsSync(outPath));
const sz = fs.statSync(outPath).size;
ok("output is non-empty + binary-sized (> 1 MB)", sz > 1024 * 1024);

/* Step 2: run the compiled binary */
const runR = Bun.spawnSync({ cmd: [outPath, "alpha", "beta"] });
ok("compiled binary exits 0", runR.exitCode === 0);
const out = new TextDecoder().decode(runR.stdout);
ok("compiled stdout has hello message", out.indexOf("hello") >= 0);
ok("compiled binary received argv", out.indexOf("alpha,beta") >= 0);

/* Step 3: re-run with no argv — should still work */
const runR2 = Bun.spawnSync({ cmd: [outPath] });
ok("compiled binary works without argv", runR2.exitCode === 0);
const out2 = new TextDecoder().decode(runR2.stdout);
ok("compiled stdout has hello", out2.indexOf("hello") >= 0);

/* Step 4: dun runtime still works after the compile step */
const sanity = Bun.spawnSync({ cmd: [exe, "eval", "1+1"] });
ok("dun runtime still exits 0", sanity.exitCode === 0);

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
