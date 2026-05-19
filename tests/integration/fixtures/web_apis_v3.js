// v0.6.0 web API parity — MessageEvent / ErrorEvent / CloseEvent /
// PromiseRejectionEvent / localStorage / sessionStorage / Cache /
// CacheStorage / FileReader / DOMRect / DOMPoint / ImageData /
// CryptoKey / PerformanceObserver. All were undefined in v0.5.0.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// Event subclasses
ok("MessageEvent", typeof MessageEvent === "function");
ok("MessageEvent data field", new MessageEvent("m", { data: 42 }).data === 42);
ok("ErrorEvent", typeof ErrorEvent === "function");
ok("ErrorEvent.message", new ErrorEvent("err", { message: "x" }).message === "x");
ok("PromiseRejectionEvent", typeof PromiseRejectionEvent === "function");
ok("CloseEvent", typeof CloseEvent === "function");
ok("CloseEvent.code default 1005", new CloseEvent("c").code === 1005);

// Storage
ok("localStorage defined", typeof localStorage !== "undefined");
ok("sessionStorage defined", typeof sessionStorage !== "undefined");
localStorage.setItem("k", "v");
ok("localStorage round-trip", localStorage.getItem("k") === "v");
ok("localStorage length", localStorage.length === 1);
localStorage.removeItem("k");
ok("localStorage remove", localStorage.getItem("k") === null);

// Cache API
ok("caches defined", typeof caches !== "undefined");
ok("CacheStorage class", typeof CacheStorage === "function");
ok("Cache class", typeof Cache === "function");

// FileReader (sync surface check)
ok("FileReader defined", typeof FileReader === "function");
ok("FileReader constants", FileReader.EMPTY === 0 && FileReader.LOADING === 1 && FileReader.DONE === 2);

// DOM geometry
ok("DOMRect", typeof DOMRect === "function");
ok("DOMRect math", new DOMRect(1, 2, 10, 20).right === 11);
ok("DOMPoint", typeof DOMPoint === "function");
ok("DOMPoint x/y", new DOMPoint(3, 4).x === 3);
ok("DOMMatrix identity", new DOMMatrix().isIdentity);
ok("DOMQuad bounds", new DOMQuad({x:0,y:0},{x:5,y:0},{x:5,y:5},{x:0,y:5}).getBounds().width === 5);

// ImageData
ok("ImageData", typeof ImageData === "function");
ok("ImageData buffer size", new ImageData(2, 3).data.length === 24);

// Crypto types
ok("CryptoKey", typeof CryptoKey === "function");
ok("SubtleCrypto", typeof SubtleCrypto === "function");

// PerformanceObserver
ok("PerformanceObserver", typeof PerformanceObserver === "function");

// Bun.* additions
ok("Bun.deflateSync", typeof Bun.deflateSync === "function");
ok("Bun.gunzipSync round-trip", (() => {
  const z = Bun.gzipSync(Buffer.from("hello"));
  const u = Bun.gunzipSync(z);
  return u.toString() === "hello";
})());
ok("Bun.SHA256", typeof Bun.SHA256 === "function");
ok("Bun.SHA256.hash", Bun.SHA256.hash("hello", "hex").length === 64);
ok("Bun.allocUnsafe", typeof Bun.allocUnsafe === "function");
ok("Bun.semver.satisfies", Bun.semver.satisfies("1.2.3", "^1.0.0"));
ok("Bun.semver mismatch", !Bun.semver.satisfies("2.0.0", "^1.0.0"));
ok("Bun.openInEditor", typeof Bun.openInEditor === "function");

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
