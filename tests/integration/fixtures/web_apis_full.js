// v0.6.0 — full web API parity surface (38/38).
// Covers the *lazy* extras: observers, WebTransport, WebRTC, IndexedDB,
// Notification, CookieStore, FileReaderSync, ImageBitmap. Constructors
// are stubs that throw "not implemented" when invoked, but `typeof X
// === 'function'` and the property accesses our targets do must work.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// === Observers ===
ok("IntersectionObserver", typeof IntersectionObserver === "function");
ok("MutationObserver", typeof MutationObserver === "function");
ok("ResizeObserver", typeof ResizeObserver === "function");
ok("IntersectionObserverEntry", typeof IntersectionObserverEntry === "function");
ok("ResizeObserverEntry", typeof ResizeObserverEntry === "function");
ok("MutationRecord", typeof MutationRecord === "function");
ok("ResizeObserver.observe noop", (() => {
  const r = new ResizeObserver(() => {});
  r.observe({});
  r.disconnect();
  return Array.isArray(r.takeRecords());
})());

// === WebTransport / WebRTC ===
ok("WebTransport", typeof WebTransport === "function");
ok("WebTransportError", typeof WebTransportError === "function");
ok("WebTransportError instanceof Error", (() => {
  try { throw new WebTransportError("x"); }
  catch (e) { return e instanceof Error && e.name === "WebTransportError"; }
})());
ok("WebTransportBidirectionalStream", typeof WebTransportBidirectionalStream === "function");
ok("WebTransportDatagramDuplexStream", typeof WebTransportDatagramDuplexStream === "function");
ok("RTCPeerConnection", typeof RTCPeerConnection === "function");

// === IndexedDB ===
ok("indexedDB defined", typeof indexedDB !== "undefined");
ok("IDBDatabase", typeof IDBDatabase === "function");
ok("IDBTransaction", typeof IDBTransaction === "function");
ok("IDBObjectStore", typeof IDBObjectStore === "function");
ok("indexedDB.databases() returns Promise", indexedDB.databases() instanceof Promise);
ok("indexedDB.cmp", indexedDB.cmp(1, 2) === -1 && indexedDB.cmp("b", "a") === 1);

// === Notification ===
ok("Notification class", typeof Notification === "function");
ok("Notification.permission denied", Notification.permission === "denied");
ok("Notification.requestPermission returns Promise",
  Notification.requestPermission() instanceof Promise);
ok("new Notification(...)", (() => {
  const n = new Notification("hi", { body: "world" });
  return n.title === "hi" && n.body === "world";
})());

// === CookieStore ===
ok("CookieStore class", typeof CookieStore === "function");
ok("cookieStore global", typeof cookieStore === "object");
ok("CookieChangeEvent", typeof CookieChangeEvent === "function");

// === FileReaderSync ===
ok("FileReaderSync class", typeof FileReaderSync === "function");
ok("FileReaderSync.readAsText throws", (() => {
  try { new FileReaderSync().readAsText({}); return false; }
  catch (e) { return /not implemented|use async/.test(e.message); }
})());

// === ImageBitmap ===
ok("ImageBitmap class", typeof ImageBitmap === "function");
ok("createImageBitmap returns Promise",
  createImageBitmap({ width: 10, height: 5 }) instanceof Promise);
ok("ImageBitmap.close", (() => {
  const b = new ImageBitmap();
  b.close();
  return b._closed === true;
})());

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
