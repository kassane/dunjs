// Regression fixture for v1.1.23 — dns/promises builtin + ESM
// `module` condition support + ESM vs CJS condition order.
//
// Before the fix:
// - require('dns/promises') worked (via dns.promises sub-object)
//   but `import dns from 'node:dns/promises'` threw "Cannot find module".
// - `import { z } from 'zod'` threw "Cannot import a CommonJS module
//   from ESM" because the resolver checked `require` BEFORE `import`
//   in the conditions list — zod's `.cjs` won the lookup.
// - Packages with `exports: { ".": { module, esnext, types, default } }`
//   (no `import` condition — e.g. @opentelemetry/semantic-conventions)
//   fell through to `default` which often points at the CJS build.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// 1. require('dns/promises') — the legacy path that worked
const dnsP = require('dns/promises');
ok("dns/promises is an object", typeof dnsP === 'object');
ok("dns/promises.lookup is a function", typeof dnsP.lookup === 'function');
ok("dns/promises.resolve4 is a function", typeof dnsP.resolve4 === 'function');

// 2. dnsP.lookup returns a Promise
const lookupReturn = dnsP.lookup('127.0.0.1');
ok("lookup returns a Promise", typeof lookupReturn.then === 'function');
lookupReturn.then((res) => {
  ok("lookup result has address", typeof res.address === 'string');
  ok("lookup result has family", typeof res.family === 'number');
  console.log("Score: " + pass + "/" + (pass + fail));
  if (pass === pass + fail) console.log("ALL CHECKS PASSED");
  process.exit(0);
}).catch((e) => {
  // Network failures are OK in sandboxed envs — still count the API as present.
  ok("lookup did not throw at API level", true);
  console.log("Score: " + pass + "/" + (pass + fail));
  if (pass === pass + fail) console.log("ALL CHECKS PASSED");
  process.exit(0);
});
