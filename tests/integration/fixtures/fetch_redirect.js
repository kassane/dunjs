// fetch redirect mode test — Fetch spec compliance for
// opts.redirect = "follow" | "manual" | "error".
// Spins up a local redirect chain and verifies each mode behaves
// per spec. Cross-runtime: Node/Deno/Bun all support these.
const http = require("http");

let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const target = http.createServer((req, res) => {
  res.writeHead(200);
  res.end("final");
});

target.listen(0, "127.0.0.1", () => {
  const tport = target.address().port;
  const redir = http.createServer((req, res) => {
    res.writeHead(302, { "location": `http://127.0.0.1:${tport}/final` });
    res.end();
  });
  redir.listen(0, "127.0.0.1", async () => {
    const rport = redir.address().port;
    const url = `http://127.0.0.1:${rport}/`;

    // 1. redirect: "manual" — return 3xx as-is
    const r1 = await fetch(url, { redirect: "manual" });
    ok("manual returns 3xx", r1.status === 302);
    ok("manual exposes Location", r1.headers.get("location") &&
      r1.headers.get("location").includes("/final"));

    // 2. default + redirect: "follow" — chase to 200
    const r2 = await fetch(url);
    ok("default follows", r2.status === 200);
    ok("default reads final body", (await r2.text()) === "final");

    const r3 = await fetch(url, { redirect: "follow" });
    ok("follow=200", r3.status === 200);

    // 3. redirect: "error" — throw
    let threw = false;
    try { await fetch(url, { redirect: "error" }); }
    catch { threw = true; }
    ok("error throws", threw);

    console.log(`Score: ${pass}/${pass + fail}`);
    target.close();
    redir.close();
    process.exit(fail > 0 ? 1 : 0);
  });
});
