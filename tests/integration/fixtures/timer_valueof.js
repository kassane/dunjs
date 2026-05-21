// `+timer` numeric coercion regression — runs on all 3 backends.
// In v1.1.22 the cached JS setup-fn for timer valueOf was replaced
// with a native D callback (`jsTimerValueOf` reading `this._id`)
// after a QJS shape-table crash was traced (see timer_race.js for
// the QJS-specific Worker-interaction repro).
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const t = setTimeout(() => {}, 99999);
ok("+timer is a number", typeof +t === "number");
ok("+timer is positive", +t > 0);
ok("+timer === t._id", +t === t._id);

// Number() coercion also goes through valueOf
ok("Number(t) === +t", Number(t) === +t);

// clearTimeout accepts the raw object (no coercion needed)
clearTimeout(t);
ok("clearTimeout(timer) does not throw", true);

console.log("Score: " + pass + "/" + (pass + fail));
if (pass === pass + fail) console.log("ALL CHECKS PASSED");
