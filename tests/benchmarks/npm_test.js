const results = [];
function tryPkg(name, testFn) {
  try {
    const mod = require(name);
    const ok = testFn(mod);
    results.push({ name, status: ok ? "OK" : "FAIL" });
  } catch(e) {
    results.push({ name, status: "ERR", msg: e.message ? e.message.substring(0, 60) : String(e) });
  }
}

tryPkg("lodash", _ => typeof _.chunk === "function" && _.chunk([1,2,3,4], 2).length === 2);
tryPkg("ms", ms => ms("2 days") === 172800000);
tryPkg("escape-html", esc => esc("<b>") === "&lt;b&gt;");
tryPkg("bytes", b => b.parse("1KB") === 1024);
tryPkg("cookie", c => typeof c.parse === "function");
tryPkg("content-type", ct => typeof ct.parse === "function");
tryPkg("validator", v => typeof v.isEmail === "function" && v.isEmail("a@b.com"));
tryPkg("qs", qs => typeof qs.parse === "function");
tryPkg("safe-buffer", sb => typeof sb.Buffer === "function");
tryPkg("depd", depd => typeof depd === "function");
tryPkg("fast-deep-equal", eq => eq({a:1}, {a:1}) === true);
tryPkg("is-plain-object", m => typeof m.isPlainObject === "function");
tryPkg("deepmerge", dm => typeof dm === "function");
tryPkg("flat", f => typeof f.flatten === "function" || typeof f === "function");
tryPkg("retry", r => typeof r.operation === "function");
tryPkg("eventemitter3", EE => typeof EE === "function");
tryPkg("camelcase", cc => typeof cc === "function");
tryPkg("decamelize", dc => typeof dc === "function");

for (const r of results) {
  console.log(`${r.status.padEnd(4)} ${r.name}${r.msg ? " (" + r.msg + ")" : ""}`);
}
console.log(`\n${results.filter(r => r.status === "OK").length}/${results.length} packages working`);
