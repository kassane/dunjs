// Permanent regression for `diagnostics_channel.tracingChannel` —
// Node v15+ API that pino's tools.js calls at module-load time AND
// invokes per-log-call to wrap _asJson with `this`-bound state. Two
// failure modes caught in v1.1.26-dev:
//   1. tracingChannel itself missing -> require("pino") crashes
//      with "undefined is not a function" at tools.js:32
//   2. tracingChannel present but traceSync drops thisArg ->
//      first log call fails with "cannot read property
//      'pino.stringify' of null" inside pino _asJson, because
//      it reads this[stringifySym] and `this` arrived as null
//
// This fixture exercises the full API surface without depending
// on pino itself (which would need a network install).

const dc = require("node:diagnostics_channel");

// 1. tracingChannel returns an object with the expected shape
const tc = dc.tracingChannel("test.fixture");
console.log(typeof tc === "object" && tc !== null
  ? "OK tracingChannel returns object"
  : "FAIL tracingChannel: " + typeof tc);

// 2. The 5 standard Channel slots exist
const slots = ["start", "end", "asyncStart", "asyncEnd", "error"];
let allChannels = true;
for (const k of slots) {
  if (typeof tc[k] !== "object" || tc[k] === null) { allChannels = false; break; }
}
console.log(allChannels
  ? "OK 5 standard channel slots present"
  : "FAIL channel slots missing");

// 3. trace{Sync,Promise,Callback} are functions
const traceMethods = ["traceSync", "tracePromise", "traceCallback"];
let allTrace = true;
for (const k of traceMethods) {
  if (typeof tc[k] !== "function") { allTrace = false; break; }
}
console.log(allTrace
  ? "OK trace{Sync,Promise,Callback} are functions"
  : "FAIL trace methods missing");

// 4. traceSync threads `thisArg` through to fn.apply (the pino bug)
const obj = { stash: "from-thisArg" };
function readStash() { return this.stash; }
const got = tc.traceSync(readStash, { ctx: 1 }, obj);
console.log(got === "from-thisArg"
  ? "OK traceSync threads thisArg to fn.apply"
  : "FAIL traceSync thisArg dropped: got '" + got + "'");

// 5. traceSync passes the trailing args
function sum(a, b, c) { return a + b + c; }
const total = tc.traceSync(sum, null, null, 1, 2, 3);
console.log(total === 6
  ? "OK traceSync passes trailing args"
  : "FAIL traceSync args dropped: got " + total);

// 6. tracePromise returns a Promise that resolves to fn's return
(async () => {
  const r = await tc.tracePromise(() => 42, null, null);
  console.log(r === 42
    ? "OK tracePromise resolves with fn result"
    : "FAIL tracePromise: got " + r);
})();
