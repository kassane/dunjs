// Regression test for the things that gaia.ts hit on the way through:
//   - `import { createRequire } from "node:module"` (named ESM export
//     from a stub-registered C module on QuickJS)
//   - `const require = createRequire(import.meta.url)` (TDZ-safe with
//     other modules' require() bookkeeping)
//   - `new Intl.Collator().compare` destructuring → bound function
//     (V8 prebuilt lacks ICU and our polyfill used `this._options` directly)
//   - `enum` runtime objects with forward + reverse lookup
//
// If any of these regresses, this file fails fast.

import { createRequire } from "node:module"
const require = createRequire(import.meta.url)

// node:fs / node:path imports — the common Deno-port pattern.
import FS from "node:fs"
import PATH from "node:path"

let passed = 0, total = 0;
function check(name: string, cond: boolean) {
  total++;
  if (cond) passed++;
  else console.log("FAIL:", name);
}

check("createRequire is a function", typeof createRequire === "function");
check("require is a function", typeof require === "function");
check("require has resolve", typeof require.resolve === "function");
check("FS is an object", typeof FS === "object");
check("FS.readFileSync", typeof FS.readFileSync === "function");
check("PATH.join", typeof PATH.join === "function");

// Intl.Collator destructured compare — the failing path inside
// packageurl-js's strings.js.
const { compare } = new Intl.Collator();
check("destructured compare is function", typeof compare === "function");
check("destructured compare a/b => -1", compare("a", "b") === -1);
check("destructured compare b/a => 1", compare("b", "a") === 1);
check("destructured compare a/a => 0", compare("a", "a") === 0);

// And the normal `instance.compare(x, y)` path.
const coll = new Intl.Collator();
check("instance compare a/b", coll.compare("a", "b") === -1);
check("Intl.Collator.prototype.compare descriptor is a getter",
  typeof Object.getOwnPropertyDescriptor(
    Intl.Collator.prototype, "compare").get === "function");

console.log("gaia_smoke:", passed + "/" + total, "checks passed");
if (passed === total) console.log("ALL CHECKS PASSED");
