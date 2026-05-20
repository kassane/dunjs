// Verify diagnostics_channel works end-to-end. We ship the core
// publish/subscribe surface; tracingChannel is deferred.
const dc = require("diagnostics_channel");

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) pass++;
  else { fail++; console.log("FAIL", name); }
}

// 1. channel() returns the same instance for the same name
const c1 = dc.channel("test:foo");
const c2 = dc.channel("test:foo");
check("channel identity", c1 === c2);

// 2. hasSubscribers correctly tracks
check("no subscribers initially", c1.hasSubscribers === false);
check("dc.hasSubscribers returns false", dc.hasSubscribers("test:foo") === false);

let received = [];
const listener = (msg, name) => received.push({msg, name});

// 3. subscribe / publish flow
c1.subscribe(listener);
check("hasSubscribers after subscribe", c1.hasSubscribers === true);
check("dc.hasSubscribers after subscribe", dc.hasSubscribers("test:foo") === true);

c1.publish({hello: "world"});
check("publish delivered", received.length === 1);
check("publish msg correct", received[0].msg.hello === "world");
check("publish name correct", received[0].name === "test:foo");

// 4. unsubscribe
const removed = c1.unsubscribe(listener);
check("unsubscribe returns true", removed === true);
check("no subscribers after unsubscribe", c1.hasSubscribers === false);

// 5. dc.subscribe / dc.unsubscribe shortcuts
received = [];
dc.subscribe("test:bar", listener);
const cBar = dc.channel("test:bar");
cBar.publish("hello");
check("dc.subscribe registered listener", received.length === 1);
check("dc.unsubscribe", dc.unsubscribe("test:bar", listener) === true);

// 6. publish-during-unsubscribe is safe
received = [];
const l1 = () => received.push(1);
const l2 = () => { received.push(2); c1.unsubscribe(l2); };
const l3 = () => received.push(3);
c1.subscribe(l1); c1.subscribe(l2); c1.subscribe(l3);
c1.publish("snapshot");
check("publish snapshot safety - all 3 fired", received.length === 3);
check("publish snapshot order", received.join() === "1,2,3");

// 7. TypeError on bad listener
try { c1.subscribe("not a function"); check("subscribe rejects non-fn", false); }
catch (e) { check("subscribe rejects non-fn", e instanceof TypeError); }

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
