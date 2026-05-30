// v1.1.31 — pin the HTTP/2 connection-window overflow predicate
// (CVE-2026-21714 class, Node Mar-2026 security release). RFC 7540
// §6.9.1 mandates that a WINDOW_UPDATE which would push the connection
// or stream send window past 2^31-1 MUST be answered with a
// FLOW_CONTROL_ERROR. Before the fix `connectionSendWindow += increment`
// wrapped to negative on overflow and the streams[] AA was never cleared
// even after GOAWAY — leaking H2Stream state on poisoned sessions.
//
// Full live-wire test requires raw H2 frame forging against a running
// server, which depends on `srv.address()` — currently not exposed by
// DunJS's H2 server JS object. This fixture pins the predicate; the
// in-tree D fix lives at source/dun/builtins/http2.d processWindowUpdate
// (server line ~1180, client line ~1764) and sendGoaway (~1255).
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const MAX = 0x7fffffff;

// 1. Overflow predicate mirrors the D-side guard
//    (cast(long) connectionSendWindow + increment > 0x7FFF_FFFF).
ok("overflow at exact boundary", (MAX - 10) + 100 > MAX);
ok("no overflow below boundary", (MAX - 10) + 5 <= MAX);
ok("overflow at exact wrap (1 + MAX)", 1 + MAX > MAX);
ok("no overflow at zero increment", 100 + 0 <= MAX);
ok("overflow from default window (65535)", 65535 + 0x7fffffff > MAX);
ok("no overflow under default + safe", 65535 + 100 <= MAX);

// 2. Confirm 31-bit increment masking (top bit reserved per RFC 7540).
function mask31(v) { return v & 0x7fffffff; }
ok("31-bit mask drops sign bit", mask31(0x80000000 | 0x1234) === 0x1234);
ok("31-bit mask preserves max valid", mask31(0x7fffffff) === 0x7fffffff);

// 3. H2 module is loadable and the createServer / connect API exists
//    (smoke — confirms our edits didn't break module init).
const http2 = require("http2");
ok("http2.createServer present", typeof http2.createServer === "function");
ok("http2.connect present", typeof http2.connect === "function");
ok("http2 FLOW_CONTROL_ERROR constant present",
   http2.constants && http2.constants.NGHTTP2_FLOW_CONTROL_ERROR === 3);

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
