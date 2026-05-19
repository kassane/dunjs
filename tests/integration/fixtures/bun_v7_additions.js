// v0.7.0 — Bun.* additions: deepMatch, concatArrayBuffers,
// arrayBufferToString, randomUUIDv7, nanoseconds, gcAggressionLevel,
// shrink, generateHeapSnapshot. Limited to quickjs+v8 via the
// `bun_v7_additions.backends` sidecar; on JSC the install of these
// extras shifts the io_uring fd-accumulation threshold below 7
// servers which would break `deno_deploy_compat`.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// Bun.deepMatch — `b` is a subset of `a`
ok("deepMatch exact", Bun.deepMatch({a:1, b:2}, {a:1, b:2}));
ok("deepMatch subset", Bun.deepMatch({a:1, b:2, c:3}, {a:1}));
ok("deepMatch fails on mismatch", !Bun.deepMatch({a:1}, {a:2}));
ok("deepMatch nested", Bun.deepMatch({a:{b:1, c:2}}, {a:{b:1}}));
ok("deepMatch array", Bun.deepMatch([1,2,3], [1,2,3]));

// Bun.concatArrayBuffers
const b1 = new Uint8Array([1,2,3]).buffer;
const b2 = new Uint8Array([4,5,6]).buffer;
const cat = Bun.concatArrayBuffers([b1, b2]);
ok("concat result is ArrayBuffer", cat instanceof ArrayBuffer);
ok("concat length", cat.byteLength === 6);
ok("concat content", new Uint8Array(cat).join() === "1,2,3,4,5,6");
const cap = Bun.concatArrayBuffers([b1, b2], 4);
ok("concat with cap", cap.byteLength === 4);
const asU8 = Bun.concatArrayBuffers([b1, b2], undefined, true);
ok("concat asUint8Array", asU8 instanceof Uint8Array);

// Bun.arrayBufferToString — UTF-8 decode
const helloBuf = new TextEncoder().encode("hello world").buffer;
ok("arrayBufferToString", Bun.arrayBufferToString(helloBuf) === "hello world");
ok("arrayBufferToString passthru", Bun.arrayBufferToString("already a string") === "already a string");

// Bun.randomUUIDv7 — RFC 9562 sortable UUID
const u1 = Bun.randomUUIDv7();
ok("UUIDv7 canonical form", /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(u1));
const u2 = Bun.randomUUIDv7("hex");
ok("UUIDv7 hex form", /^[0-9a-f]{32}$/.test(u2));
const u3 = Bun.randomUUIDv7("buffer");
ok("UUIDv7 buffer form", u3 && u3.length === 16);
const tsBase = Date.now();
const a = Bun.randomUUIDv7(undefined, tsBase);
const b = Bun.randomUUIDv7(undefined, tsBase + 1000);
ok("UUIDv7 sorts by timestamp", a < b);

// Bun.nanoseconds — non-zero, ns-scale
const ns = Bun.nanoseconds();
ok("nanoseconds returns number", typeof ns === "number" && ns > 0);

// Bun.gcAggressionLevel
ok("gcAggressionLevel default 1", Bun.gcAggressionLevel() === 1);
ok("gcAggressionLevel set 2", Bun.gcAggressionLevel(2) === 2);
ok("gcAggressionLevel persists", Bun.gcAggressionLevel() === 2);
ok("gcAggressionLevel rejects 5", Bun.gcAggressionLevel(5) === 2);

// Bun.shrink — no return, no throw
Bun.shrink();
ok("shrink returns undefined cleanly", true);

// Bun.generateHeapSnapshot — stub object
const snap = Bun.generateHeapSnapshot();
ok("heapSnapshot has version", snap && snap.version === 1);
ok("heapSnapshot is shape-correct", Array.isArray(snap.nodes) && Array.isArray(snap.edges));

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
