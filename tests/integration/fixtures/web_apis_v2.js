// EventSource + URLPattern + Bun.Glob + Bun.readableStreamTo* — modern
// web standards and Bun helpers ported from upstream Bun/Deno surface
// audits. All previously absent on DunJS.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// EventSource constructor exists, state constants
ok("EventSource defined", typeof EventSource === "function");
ok("EventSource.CONNECTING", EventSource.CONNECTING === 0);
ok("EventSource.OPEN", EventSource.OPEN === 1);
ok("EventSource.CLOSED", EventSource.CLOSED === 2);

// URLPattern basics
ok("URLPattern defined", typeof URLPattern === "function");
const p1 = new URLPattern("/users/:id");
const m1 = p1.exec("https://x.com/users/42");
ok("URLPattern groups", m1 && m1.pathname.groups.id === "42");
ok("URLPattern test", p1.test("/users/100"));
ok("URLPattern test miss", !p1.test("/posts/1"));

// Bun.Glob
ok("Bun.Glob defined", typeof Bun.Glob === "function");
ok("Bun.Glob match *", new Bun.Glob("*.js").match("a.js"));
ok("Bun.Glob match **", new Bun.Glob("**/*.js").match("a/b/c.js"));
ok("Bun.Glob alternation", new Bun.Glob("{a,b}.js").match("b.js"));

// Bun.readableStreamTo*
ok("Bun.readableStreamToText defined", typeof Bun.readableStreamToText === "function");
ok("Bun.readableStreamToJSON defined", typeof Bun.readableStreamToJSON === "function");
ok("Bun.readableStreamToArrayBuffer defined", typeof Bun.readableStreamToArrayBuffer === "function");
ok("Bun.readableStreamToBlob defined", typeof Bun.readableStreamToBlob === "function");

// Async test: drain a stream
(async () => {
  const stream = new ReadableStream({
    start(c) {
      c.enqueue(new TextEncoder().encode("hello "));
      c.enqueue(new TextEncoder().encode("world"));
      c.close();
    }
  });
  const txt = await Bun.readableStreamToText(stream);
  ok("Bun.readableStreamToText drains", txt === "hello world");
  console.log(`Score: ${pass}/${pass + fail}`);
  process.exit(fail > 0 ? 1 : 0);
})();
