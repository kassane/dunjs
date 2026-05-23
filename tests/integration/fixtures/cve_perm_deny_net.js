// CVE-class regression: net / http / http2 server listen + outbound
// connect must require --allow-net. Pre-v1.1.28 these modules had no
// `Permission.net` gate (despite the file-header doc-comment claiming
// they did) — a sandboxed script could open arbitrary inbound listeners
// AND outbound connections by going through `net` / `http` / `http2`
// instead of `fetch`/`tls`/`dgram` (which had the gate).
//
// Class: sandbox escape (same family as Deno's --allow-net bypass
// advisories). Tested standalone with NO `--allow-net` flag — every
// op below must throw a permission error.

let checks = 0;
let passed = 0;

function check(label, fn) {
  checks++;
  try {
    fn();
    console.log("FAIL: " + label + " — call succeeded without --allow-net");
  } catch (e) {
    if (String(e.message || e).includes("allow-net") ||
        String(e.message || e).includes("net permission") ||
        String(e.code || "").includes("ERR_PERMISSION_DENIED")) {
      passed++;
      console.log("OK: " + label + " denied (" + (e.code || e.message) + ")");
    } else {
      console.log("FAIL: " + label + " threw unexpected: " + (e.message || e));
    }
  }
}

const net = require("net");
const http = require("http");
const http2 = require("http2");

check("net.createConnection", () => {
  net.createConnection({ host: "127.0.0.1", port: 1 });
});

check("net.createServer().listen", () => {
  const s = net.createServer();
  s.listen(0);
});

check("http.createServer().listen", () => {
  const s = http.createServer();
  s.listen(0);
});

check("http2.createServer().listen", () => {
  const s = http2.createServer();
  s.listen(0);
});

check("http2.connect", () => {
  http2.connect("http://127.0.0.1:1/");
});

console.log("\n" + passed + "/" + checks + " permission denials enforced");
if (passed !== checks) {
  console.log("SANDBOX ESCAPE: some net I/O bypassed --allow-net");
  process.exit(1);
}
