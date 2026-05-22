// Regression: V8 backend `engine.throwTypeError` from a native callback
// was not visible to JS-side try/catch. The native function appeared
// to RETURN the TypeError instance instead of throwing it, so
// `try { require('./nonexistent.node') } catch (e) { ... }` silently
// fell through with `require()` returning a TypeError as the module
// value. Fixed by v8shim has_thrown flag + V8 backend
// lastCallWasException update (v1.1.26 follow-up).
//
// Surfaced by yuku-parser's N-API addon load path: the binding.js
// shim's try/catch on path 1 didn't fire on V8 specifically.

let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// require() of a missing .node addon must throw a TypeError that
// the JS-side catch sees.
let caught = null;
try {
  require("/tmp/this-path-definitely-does-not-exist-xyz.node");
} catch (e) {
  caught = e;
}
ok("require missing .node throws", caught !== null);
ok("caught is Error subtype", caught instanceof Error);
ok("error message mentions addon", caught && /Cannot load native addon|Cannot find module/.test(caught.message));

// Same shape: require of a missing JS module also throws + caught.
let caught2 = null;
try {
  require("./this-module-does-not-exist-xyz");
} catch (e) {
  caught2 = e;
}
ok("require missing JS throws", caught2 !== null);

console.log(`Score: ${pass}/${pass + fail}`);
