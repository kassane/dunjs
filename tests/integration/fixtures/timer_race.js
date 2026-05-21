// Regression fixture for v1.1.22 — QJS Worker+setTimeout race.
// Before the fix: cached JS setup-fn for timer valueOf/Symbol.toPrimitive
// (set via `engine.eval` at install) reliably crashed QJS's
// `add_shape_property` when called from inside a timer callback that
// created another timer, after a Worker had been constructed earlier
// (gdb-traced — cached fn bytecode held a stale Function.prototype
// shape ID that QJS shape-table reorgs invalidated post Worker install).
//
// Fix: timer valueOf is now a native D callback (`jsTimerValueOf` reading
// `this._id`) — no JS eval at all, no shape-table fragility.

let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// 1. +timer returns the timer id (Node compat)
const t1 = setTimeout(() => {}, 99999);
ok("+timer is a number", typeof +t1 === "number");
ok("+timer is positive", +t1 > 0);
ok("+timer === t._id", +t1 === t1._id);
clearTimeout(t1);

// 2. Nested setTimeout — pre-fix crashed on QJS after Worker construction.
//    Worker construction must happen for the QJS shape-table reorg to
//    invalidate the cached setup fn's bytecode references; the crash
//    then manifested on the SECOND setTimeout creation.
const w = new Worker("/* noop */", { eval: true });
w.terminate();  // immediately terminate — we just need the construction side-effect

let firstFired = false;
setTimeout(() => {
  firstFired = true;
  // Inner setTimeout used to crash here on QJS.
  setTimeout(() => {
    ok("nested setTimeout fires after Worker construction", true);
    ok("outer setTimeout fired first", firstFired);
    console.log("Score:", pass + "/" + (pass + fail));
    if (pass === pass + fail) console.log("ALL CHECKS PASSED");
    process.exit(0);
  }, 10);
}, 10);
