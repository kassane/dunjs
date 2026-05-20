// v0.7.0 — `Bun.build({ sourcemap: 'inline' | 'external' })` emits a
// v3 source map alongside or inside the bundle.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const fs = require("fs");
const path = require("path");
const os = require("os");

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dun-bundle-sm-"));
const entry = path.join(dir, "entry.js");
fs.writeFileSync(entry, `const greeting = "hello";\nconsole.log(greeting);\n`);

async function main() {
  // external sourcemap
  let out = path.join(dir, "ext");
  fs.mkdirSync(out, { recursive: true });
  let r = await Bun.build({ entrypoints: [entry], outdir: out, sourcemap: "external" });
  ok("external bundle ok", r.success);
  ok("external outputs has 2 artifacts (.js + .map)", r.outputs.length === 2);
  ok("external map file written", fs.existsSync(path.join(out, "bundle.js.map")));
  const mapJson = JSON.parse(fs.readFileSync(path.join(out, "bundle.js.map"), "utf-8"));
  ok("map.version is 3", mapJson.version === 3);
  ok("map.sources has entry", mapJson.sources.indexOf(entry) >= 0);
  ok("map.sourcesContent has entry source", Array.isArray(mapJson.sourcesContent) && mapJson.sourcesContent.length > 0);
  ok("map.mappings is non-empty", typeof mapJson.mappings === "string" && mapJson.mappings.length > 0);
  ok("bundle.js has sourceMappingURL=bundle.js.map", fs.readFileSync(path.join(out, "bundle.js"), "utf-8").indexOf("sourceMappingURL=bundle.js.map") >= 0);

  // inline sourcemap
  out = path.join(dir, "inl");
  fs.mkdirSync(out, { recursive: true });
  r = await Bun.build({ entrypoints: [entry], outdir: out, sourcemap: "inline" });
  ok("inline bundle ok", r.success);
  ok("inline outputs has 1 artifact", r.outputs.length === 1);
  ok("inline no .map sibling", !fs.existsSync(path.join(out, "bundle.js.map")));
  const inlineBundle = fs.readFileSync(path.join(out, "bundle.js"), "utf-8");
  ok("inline has data: URI", inlineBundle.indexOf("sourceMappingURL=data:application/json;base64,") >= 0);

  // 'none' (default) — no map
  out = path.join(dir, "none");
  fs.mkdirSync(out, { recursive: true });
  r = await Bun.build({ entrypoints: [entry], outdir: out });
  ok("default no .map", !fs.existsSync(path.join(out, "bundle.js.map")));
  ok("default no inline data URI", fs.readFileSync(path.join(out, "bundle.js"), "utf-8").indexOf("sourceMappingURL=data:") < 0);

  // Clean up the tmpdir so sweeps don't accumulate bundle artifacts.
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch {}

  console.log(`Score: ${pass}/${pass + fail}`);
  process.exit(fail > 0 ? 1 : 0);
}

main().catch(e => { console.error("ERR", e.message); process.exit(1); });
