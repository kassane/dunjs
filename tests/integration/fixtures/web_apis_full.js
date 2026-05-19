// 100% web-API surface audit — every entry from the Bun + Deno
// global namespace audit now resolves to a defined value.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// DOM observers (headless stubs)
ok("IntersectionObserver", typeof IntersectionObserver === "function");
ok("MutationObserver", typeof MutationObserver === "function");
ok("ResizeObserver", typeof ResizeObserver === "function");
const obs = new IntersectionObserver(() => {});
obs.observe({}); obs.disconnect();
ok("Observer disconnect chain", true);

// WebTransport
ok("WebTransport defined", typeof WebTransport === "function");
let threw = false;
try { new WebTransport("https://x"); } catch (e) { threw = true; }
ok("WebTransport throws (not implemented)", threw);
ok("WebTransportError", typeof WebTransportError === "function");
const wte = new WebTransportError("oops", { source: "session" });
ok("WebTransportError instance fields", wte.message === "oops" && wte.source === "session");

// WebRTC
ok("RTCPeerConnection defined", typeof RTCPeerConnection === "function");
let rtcThrew = false;
try { new RTCPeerConnection(); } catch (e) { rtcThrew = true; }
ok("RTCPeerConnection throws", rtcThrew);
ok("RTCSessionDescription", typeof RTCSessionDescription === "function");
ok("MediaStream", typeof MediaStream === "function");

// IndexedDB
ok("indexedDB defined", typeof indexedDB !== "undefined");
ok("IDBDatabase class", typeof IDBDatabase === "function");
const req = indexedDB.open("test", 1);
ok("indexedDB.open returns IDBRequest-shaped", typeof req === "object" && "readyState" in req);
const cmpResult = indexedDB.cmp(1, 2);
ok("indexedDB.cmp", cmpResult === -1);

// Notification
ok("Notification class", typeof Notification === "function");
ok("Notification.permission", Notification.permission === "denied");

// CookieStore
ok("cookieStore defined", typeof cookieStore !== "undefined");
ok("CookieStore class", typeof CookieStore === "function");
ok("CookieChangeEvent", typeof CookieChangeEvent === "function");

// FileReaderSync
ok("FileReaderSync defined", typeof FileReaderSync === "function");

// ImageBitmap
ok("ImageBitmap defined", typeof ImageBitmap === "function");
ok("createImageBitmap", typeof createImageBitmap === "function");

// Cookie store + IndexedDB async behaviour
(async () => {
  await cookieStore.set("foo", "bar");
  const got = await cookieStore.get("foo");
  ok("cookieStore round-trip", got && got.value === "bar");
  await cookieStore.delete("foo");
  const gone = await cookieStore.get("foo");
  ok("cookieStore delete", gone === null);

  const dbs = await indexedDB.databases();
  ok("indexedDB.databases empty list", Array.isArray(dbs));

  console.log(`Score: ${pass}/${pass + fail}`);
  process.exit(fail > 0 ? 1 : 0);
})();
