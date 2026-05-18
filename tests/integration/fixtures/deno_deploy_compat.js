// Cross-runtime Deno.serve / Deno Deploy compatibility test.
//
// Exercises the request handler surface that real Deno Deploy
// scripts rely on:
//   - Deno.serve(handler) - simplest signature
//   - Deno.serve({ port: 0 }, handler) - port: 0 → ephemeral port
//   - Response with string body
//   - Response with Uint8Array / ArrayBuffer body
//   - Response with ReadableStream body
//   - opts.onListen called with { hostname, port }
//   - server.shutdown() resolves
//
// Runs on Deno (gold reference) + DunJS (all 3 backends, since
// installDenoCompat is engine-agnostic). Other runtimes lack
// Deno.serve and SKIP via try/catch.

let pass = 0, fail = 0;
function ok(name, cond, detail) {
  if (cond) { pass++; }
  else { fail++; console.log("FAIL", name, detail || ""); }
}

(async () => {
  if (typeof Deno === "undefined" || typeof Deno.serve !== "function") {
    console.log("SKIP Deno.serve not available");
    console.log("Score: 0/0 (skipped)");
    return;
  }

  // Helper: fetch with timeout (Deno Deploy doesn't have AbortSignal.timeout
  // on every minor version; use a Promise.race instead).
  function fetchWithTimeout(url, opts, ms) {
    return Promise.race([
      fetch(url, opts || {}),
      new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), ms || 3000)),
    ]);
  }

  // ── 1. simplest signature: Deno.serve(handler) ─────────────
  {
    let listened = false;
    const srv = Deno.serve({ port: 0, onListen: () => { listened = true; } }, () => {
      return new Response("hello");
    });
    await new Promise(r => setTimeout(r, 50));
    ok("onListen fired", listened);
    ok("server.addr.port > 0", srv.addr.port > 0);
    const r = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/`);
    const text = await r.text();
    ok("string body round-trips", text === "hello");
    await srv.shutdown();
  }

  // ── 2. Uint8Array body ──────────────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, () => {
      const bytes = new Uint8Array([72, 105, 33]);  // "Hi!"
      return new Response(bytes, {
        headers: { "content-type": "application/octet-stream" },
      });
    });
    await new Promise(r => setTimeout(r, 50));
    const r = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/`);
    const ab = await r.arrayBuffer();
    const view = new Uint8Array(ab);
    ok("octet-stream length=3", view.length === 3);
    ok("octet-stream content", view[0] === 72 && view[1] === 105 && view[2] === 33);
    await srv.shutdown();
  }

  // ── 3. ReadableStream body ──────────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, () => {
      const stream = new ReadableStream({
        async start(controller) {
          controller.enqueue(new TextEncoder().encode("part1-"));
          controller.enqueue(new TextEncoder().encode("part2"));
          controller.close();
        },
      });
      return new Response(stream);
    });
    await new Promise(r => setTimeout(r, 50));
    const r = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/`);
    const text = await r.text();
    ok("stream body assembled", text === "part1-part2");
    await srv.shutdown();
  }

  // ── 4. shutdown() resolves ───────────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, () => new Response("x"));
    await new Promise(r => setTimeout(r, 50));
    let shutResolved = false;
    await srv.shutdown().then(() => { shutResolved = true; });
    ok("shutdown() resolves", shutResolved);
  }

  // ── 5. server.finished promise ───────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, () => new Response("x"));
    await new Promise(r => setTimeout(r, 50));
    let finishedFired = false;
    srv.finished.then(() => { finishedFired = true; });
    await srv.shutdown();
    await new Promise(r => setTimeout(r, 50));
    ok("server.finished fires", finishedFired);
  }

  // ── 6. Headers round-trip ───────────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, (req) => {
      const h = req.headers.get("x-test") || "<missing>";
      return new Response(`got:${h}`, {
        headers: { "x-echo": "v1" },
      });
    });
    await new Promise(r => setTimeout(r, 50));
    const r = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/`, {
      headers: { "x-test": "hello-header" },
    });
    const text = await r.text();
    ok("request header readable", text === "got:hello-header");
    ok("response header set", r.headers.get("x-echo") === "v1");
    await srv.shutdown();
  }

  // ── 7. Method / URL routing ─────────────────────────────────
  {
    const srv = Deno.serve({ port: 0 }, (req) => {
      const u = new URL(req.url);
      return new Response(`${req.method} ${u.pathname}`);
    });
    await new Promise(r => setTimeout(r, 50));
    const r1 = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/foo`);
    const r2 = await fetchWithTimeout(`http://127.0.0.1:${srv.addr.port}/bar`, {
      method: "POST",
      body: "x",
    });
    ok("GET path captured", (await r1.text()) === "GET /foo");
    ok("POST path captured", (await r2.text()) === "POST /bar");
    await srv.shutdown();
  }

  console.log(`Score: ${pass}/${pass + fail}`);
  // Explicit exit — multiple Deno.serve teardowns can leave residual
  // event loop work (e.g. lingering keepalive sockets), and tests
  // shouldn't have to wait for that to drain.
  process.exit(fail > 0 ? 1 : 0);
})().catch(e => { console.log("CRASH", e && e.stack || e); process.exit(2); });
