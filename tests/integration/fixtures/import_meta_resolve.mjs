// import.meta.resolve(spec) per Node ESM spec.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

ok("resolve is function", typeof import.meta.resolve === "function");

// URL specifiers pass through.
ok("https:// pass-through",
  import.meta.resolve("https://example.com/x") === "https://example.com/x");
ok("file:// pass-through",
  import.meta.resolve("file:///etc/hosts") === "file:///etc/hosts");

// Absolute paths become file:// URLs.
ok("absolute path → file URL",
  import.meta.resolve("/some/abs/path") === "file:///some/abs/path");

// Relative paths resolve against the module's dirname. The fixture
// lives at tests/integration/fixtures/import_meta_resolve.mjs, so
// dirname is that path's directory.
const r = import.meta.resolve("./sibling.js");
ok("relative → file URL", r.startsWith("file:///") && r.endsWith("/sibling.js"));
ok("relative includes fixture dir", r.includes("fixtures"));

// `..` navigates up.
const up = import.meta.resolve("../up.js");
ok("`..` navigation", up.endsWith("/up.js") && !up.includes("/fixtures/"));

// TypeError on non-string spec.
let threw = false;
try { import.meta.resolve(42); } catch (e) { threw = e instanceof TypeError; }
ok("TypeError on non-string", threw);

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
