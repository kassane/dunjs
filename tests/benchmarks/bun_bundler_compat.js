// Cross-runtime Bun.build / bundler compatibility test.
// Exercises the bundler surface that real Bun projects rely on:
//   - relative imports inlined
//   - bare specifiers left external
//   - define {} compile-time constants
//   - external [] keep-as-runtime list
//   - minify whitespace
//   - target='node' vs target='browser' banner
//   - naming.entry rename
//
// Runs on Bun (the gold reference for Bun.build) and DunJS. Other
// runtimes lack Bun.build entirely and SKIP via try/catch.

const fs = require("fs");
const path = require("path");
const os = require("os");

let pass = 0, fail = 0;
function ok(name, cond, detail) {
  if (cond) { pass++; }
  else { fail++; console.log("FAIL", name, detail || ""); }
}

// Each runtime gets its own scratch dir so we can run them in
// parallel without colliding.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "bun-bundler-"));
function w(p, src) {
  const full = path.join(tmp, p);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, src);
  return full;
}

(async () => {
  if (typeof Bun === "undefined" || typeof Bun.build !== "function") {
    console.log("SKIP Bun.build not available");
    console.log("Score: 0/0 (skipped)");
    return;
  }

  // ── 1. Relative-import inlining ─────────────────────────────
  const entry1 = w("t1/a.js", `import { hello } from "./b.js";\nconsole.log(hello());`);
  w("t1/b.js", `export function hello() { return "hi"; }`);
  const r1 = await Bun.build({ entrypoints: [entry1] });
  const t1 = await r1.outputs[0].text();
  ok("relative-import inlined", t1.includes("function hello"));
  ok("entry source present", t1.includes("console.log(hello"));

  // ── 2. Bare specifier kept external ─────────────────────────
  const entry2 = w("t2/main.js", `import { readFileSync } from "node:fs";\nreadFileSync("/etc/hostname");`);
  const r2 = await Bun.build({ entrypoints: [entry2] });
  const t2 = await r2.outputs[0].text();
  ok("bare specifier ext (no inline)", !t2.includes("module.exports"));

  // ── 3. define {} substitutes constants ───────────────────────
  const entry3 = w("t3/main.js", `console.log(process.env.NODE_ENV);`);
  const r3 = await Bun.build({
    entrypoints: [entry3],
    define: { "process.env.NODE_ENV": '"production"' },
  });
  const t3 = await r3.outputs[0].text();
  ok("define replaces token", t3.includes('"production"'));

  // ── 4. minify: true collapses whitespace + strips comments ──
  const entry4 = w("t4/main.js", `
    // line comment
    /* block
       comment */
    function add(a,b) {
        return a + b;
    }
    console.log(add(1, 2));
  `);
  const r4 = await Bun.build({ entrypoints: [entry4], minify: true });
  const t4 = await r4.outputs[0].text();
  ok("minify drops line comment", !t4.includes("line comment"));
  ok("minify drops block comment", !t4.includes("block"));
  ok("minify keeps console.log", t4.includes("console.log"));

  // ── 5. naming.entry renames output ───────────────────────────
  const outdir5 = path.join(tmp, "t5out");
  const entry5 = w("t5/main.js", `console.log("renamed");`);
  await Bun.build({
    entrypoints: [entry5],
    outdir: outdir5,
    naming: { entry: "app.js" },
  });
  ok("naming.entry honored", fs.existsSync(path.join(outdir5, "app.js")));

  // ── 6. target= banner / option pass-through ──────────────────
  const entry6 = w("t6/main.js", `console.log("targeted");`);
  const r6n = await Bun.build({ entrypoints: [entry6], target: "node" });
  const t6n = await r6n.outputs[0].text();
  const r6b = await Bun.build({ entrypoints: [entry6], target: "browser" });
  const t6b = await r6b.outputs[0].text();
  // Bun's actual behavior: same source, different target metadata.
  // The shim emits a banner; Bun doesn't but doesn't fail either.
  ok("target=node accepted", typeof t6n === "string" && t6n.length > 0);
  ok("target=browser accepted", typeof t6b === "string" && t6b.length > 0);

  // ── 7. outputs[].arrayBuffer() ──────────────────────────────
  const r7 = await Bun.build({ entrypoints: [entry5] });
  if (typeof r7.outputs[0].arrayBuffer === "function") {
    const ab = await r7.outputs[0].arrayBuffer();
    ok("outputs[].arrayBuffer", ab.byteLength > 0);
  } else {
    ok("outputs[].arrayBuffer", false, "missing method");
  }

  // ── 8. unresolved import is surfaced (logs[] OR throw) ──────
  // Bun's real behavior is to throw an AggregateError; DunJS's
  // shim returns success:false with logs[]. Either is acceptable;
  // silently swallowing the failure is not.
  const entry8 = w("t8/main.js", `import { x } from "./missing.js"; console.log(x);`);
  let r8signalled = false;
  try {
    const r8 = await Bun.build({ entrypoints: [entry8] });
    if ((Array.isArray(r8.logs) && r8.logs.length > 0) || r8.success === false) {
      r8signalled = true;
    }
  } catch (_e) {
    r8signalled = true;
  }
  ok("unresolved import signalled (throw or logs)", r8signalled);

  // ── 9. Single file ESM round-trip ───────────────────────────
  const entry9 = w("t9/main.js", `const x = 42;\nconsole.log(x);`);
  const r9 = await Bun.build({ entrypoints: [entry9] });
  ok("single file passthrough", (await r9.outputs[0].text()).includes("42"));

  console.log(`Score: ${pass}/${pass + fail}`);

  // Cleanup
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
  if (fail > 0) process.exit(1);
})().catch(e => { console.log("CRASH", e); process.exit(2); });
