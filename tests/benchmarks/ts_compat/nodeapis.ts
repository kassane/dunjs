// node-apis.ts — Node.js core API comprehensive test
// fs, path, crypto, stream, http, buffer, events, url, os, util, worker_threads

const fs = require("fs");
const fsP = require("fs/promises");
const path = require("path");
const crypto = require("crypto");
const { Readable, Writable, Transform, pipeline } = require("stream");
const { promisify } = require("util");
const { EventEmitter } = require("events");
const { URL, URLSearchParams } = require("url");
const os = require("os");
const util = require("util");
const { Worker, isMainThread, threadId, workerData, parentPort } = require("worker_threads");
const zlib = require("zlib");
const assert = require("assert");

const TMP = "/tmp/dunjs-node-test";
fs.mkdirSync(TMP, { recursive: true });

// ── fs sync ───────────────────────────────────────────────────────────────
console.log("=== fs (sync) ===");
const testFile = `${TMP}/test.txt`;
fs.writeFileSync(testFile, "Hello Node.js fs!\n");
console.log("writeFileSync:", fs.existsSync(testFile));

const content = fs.readFileSync(testFile, "utf8");
console.log("readFileSync:", content.trim() === "Hello Node.js fs!");

fs.appendFileSync(testFile, "appended line\n");
const appended = fs.readFileSync(testFile, "utf8");
console.log("appendFileSync:", appended.includes("appended line"));

const stat = fs.statSync(testFile);
console.log("statSync.isFile:", stat.isFile());
console.log("statSync.size:", stat.size > 0);
console.log("statSync.mtime:", stat.mtime instanceof Date);

fs.mkdirSync(`${TMP}/subdir/nested`, { recursive: true });
console.log("mkdirSync recursive:", fs.existsSync(`${TMP}/subdir/nested`));

fs.writeFileSync(`${TMP}/subdir/a.txt`, "a");
fs.writeFileSync(`${TMP}/subdir/b.txt`, "b");
const entries = fs.readdirSync(`${TMP}/subdir`);
console.log("readdirSync:", entries.includes("a.txt") && entries.includes("b.txt"));

fs.renameSync(`${TMP}/subdir/a.txt`, `${TMP}/subdir/renamed.txt`);
console.log("renameSync:", fs.existsSync(`${TMP}/subdir/renamed.txt`));

fs.copyFileSync(testFile, `${TMP}/copied.txt`);
console.log("copyFileSync:", fs.existsSync(`${TMP}/copied.txt`));

fs.unlinkSync(`${TMP}/copied.txt`);
console.log("unlinkSync:", !fs.existsSync(`${TMP}/copied.txt`));

// ── fs/promises ───────────────────────────────────────────────────────────
console.log("\n=== fs/promises ===");
await fsP.writeFile(`${TMP}/async.txt`, "async content");
const asyncContent = await fsP.readFile(`${TMP}/async.txt`, "utf8");
console.log("readFile async:", asyncContent === "async content");

const asyncStat = await fsP.stat(`${TMP}/async.txt`);
console.log("stat async:", asyncStat.isFile());

await fsP.rename(`${TMP}/async.txt`, `${TMP}/async-renamed.txt`);
console.log("rename async:", fs.existsSync(`${TMP}/async-renamed.txt`));

const handle = await fsP.open(`${TMP}/fh.txt`, "w");
await handle.write("via file handle");
await handle.close();
console.log("fileHandle.write:", fs.readFileSync(`${TMP}/fh.txt`, "utf8") === "via file handle");

// readdir with withFileTypes
const dirents = await fsP.readdir(TMP, { withFileTypes: true });
console.log("readdir withFileTypes:", dirents.some((d) => d.isFile() && d.name === "test.txt"));

// ── path ──────────────────────────────────────────────────────────────────
console.log("\n=== path ===");
console.log("join:", path.join("/foo", "bar", "baz") === "/foo/bar/baz");
console.log("resolve:", path.resolve("foo", "bar").startsWith("/"));
console.log("dirname:", path.dirname("/foo/bar/baz.txt") === "/foo/bar");
console.log("basename:", path.basename("/foo/bar/baz.txt") === "baz.txt");
console.log("extname:", path.extname("file.ts") === ".ts");
console.log("parse:", path.parse("/foo/bar.ts").name === "bar");
console.log("format:", path.format({ dir: "/foo", name: "bar", ext: ".ts" }) === "/foo/bar.ts");
console.log("isAbsolute:", path.isAbsolute("/foo") && !path.isAbsolute("foo"));
console.log("relative:", path.relative("/foo/bar", "/foo/baz") === "../baz");
console.log("sep:", path.sep === "/");
console.log("delimiter:", path.delimiter === ":");
console.log("join empty:", path.join("") === ".");

// ── crypto ────────────────────────────────────────────────────────────────
console.log("\n=== crypto ===");
// Hash
const md5 = crypto.createHash("md5").update("hello").digest("hex");
console.log("md5:", md5.length === 32);
const sha256 = crypto.createHash("sha256").update("hello").digest("hex");
console.log("sha256:", sha256.length === 64);
const sha512 = crypto.createHash("sha512").update("hello").digest("base64");
console.log("sha512 base64:", sha512.length > 0);

// Multi-update hash
const h = crypto.createHash("sha256");
h.update("hel");
h.update("lo");
const multiHash = h.digest("hex");
console.log("multi-update hash:", multiHash === sha256);

// HMAC
const hmac = crypto.createHmac("sha256", "secret-key").update("message").digest("hex");
console.log("hmac:", hmac.length === 64);

// Random bytes
const rand = crypto.randomBytes(32);
console.log("randomBytes:", rand.length === 32);
console.log("randomBytes is Buffer:", Buffer.isBuffer(rand));

// Random UUID
const uuid = crypto.randomUUID();
console.log("randomUUID:", /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid));

// createCipheriv / createDecipheriv
const key = crypto.randomBytes(32);
const iv = crypto.randomBytes(16);
const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);
let encrypted = cipher.update("secret message", "utf8", "hex");
encrypted += cipher.final("hex");
const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);
let decrypted = decipher.update(encrypted, "hex", "utf8");
decrypted += decipher.final("utf8");
console.log("cipher/decipher:", decrypted === "secret message");

// pbkdf2Sync
const derived = crypto.pbkdf2Sync("password", "salt", 1000, 32, "sha256");
console.log("pbkdf2Sync:", derived.length === 32);

// timingSafeEqual
const a = Buffer.from("abc");
const b = Buffer.from("abc");
const c = Buffer.from("xyz");
console.log("timingSafeEqual equal:", crypto.timingSafeEqual(a, b));
console.log("timingSafeEqual diff:", !crypto.timingSafeEqual(a, c));

// ── Buffer ────────────────────────────────────────────────────────────────
console.log("\n=== Buffer ===");
const buf = Buffer.from("Hello, Buffer!");
console.log("from string:", buf.toString() === "Hello, Buffer!");
console.log("length:", buf.length === 14);

const hexBuf = Buffer.from("48656c6c6f", "hex");
console.log("from hex:", hexBuf.toString() === "Hello");

const b64Buf = Buffer.from("SGVsbG8=", "base64");
console.log("from base64:", b64Buf.toString() === "Hello");

const alloc = Buffer.alloc(4, 0xff);
console.log("alloc fill:", alloc[0] === 255 && alloc[3] === 255);

const concat = Buffer.concat([Buffer.from("Hello"), Buffer.from(", "), Buffer.from("World")]);
console.log("concat:", concat.toString() === "Hello, World");

const copy = Buffer.allocUnsafe(5);
buf.copy(copy, 0, 0, 5);
console.log("copy:", copy.toString() === "Hello");

const u8 = new Uint8Array([1, 2, 3]);
const fromU8 = Buffer.from(u8);
console.log("from Uint8Array:", fromU8[0] === 1 && fromU8[2] === 3);

console.log("readUInt32BE:", Buffer.from([0, 0, 1, 0]).readUInt32BE(0) === 256);
console.log("readUInt32LE:", Buffer.from([0, 1, 0, 0]).readUInt32LE(0) === 256);

// ── EventEmitter ──────────────────────────────────────────────────────────
console.log("\n=== EventEmitter ===");
const ee = new EventEmitter();
const results: string[] = [];

ee.on("data", (x: string) => results.push(x));
ee.once("once", (x: string) => results.push("once:" + x));
ee.emit("data", "first");
ee.emit("data", "second");
ee.emit("once", "fired");
ee.emit("once", "again"); // shouldn't fire

console.log("on:", results[0] === "first" && results[1] === "second");
console.log("once:", results[2] === "once:fired" && results.length === 3);

// Listener count
ee.on("multi", () => {});
ee.on("multi", () => {});
console.log("listenerCount:", ee.listenerCount("multi") === 2);

// Remove listener
const fn = () => {};
ee.on("test", fn);
ee.removeListener("test", fn);
console.log("removeListener:", ee.listenerCount("test") === 0);

// Error event
const errEe = new EventEmitter();
errEe.on("error", (e: Error) => {
  console.log("error event:", e.message === "test error");
});
errEe.emit("error", new Error("test error"));

// ── URL / URLSearchParams ─────────────────────────────────────────────────
console.log("\n=== URL / URLSearchParams ===");
const url = new URL("https://example.com:8080/path?a=1&b=2#hash");
console.log("hostname:", url.hostname === "example.com");
console.log("port:", url.port === "8080");
console.log("pathname:", url.pathname === "/path");
console.log("hash:", url.hash === "#hash");
console.log("searchParams a:", url.searchParams.get("a") === "1");

const params = new URLSearchParams("x=1&y=2&y=3");
console.log("getAll:", params.getAll("y").length === 2);
params.append("z", "4");
console.log("append:", params.get("z") === "4");
params.set("x", "99");
console.log("set:", params.get("x") === "99");
console.log("toString:", params.toString().includes("x=99"));

// ── os ────────────────────────────────────────────────────────────────────
console.log("\n=== os ===");
console.log("platform:", ["linux", "darwin", "win32"].includes(os.platform()));
console.log("arch:", ["x64", "arm64"].includes(os.arch()));
console.log("hostname:", typeof os.hostname() === "string");
console.log("homedir:", typeof os.homedir() === "string");
console.log("tmpdir:", os.tmpdir().startsWith("/"));
console.log("totalmem:", os.totalmem() > 0);
console.log("freemem:", os.freemem() > 0);
console.log("cpus:", Array.isArray(os.cpus()) && os.cpus().length > 0);
console.log("loadavg:", os.loadavg().length === 3);
console.log("uptime:", os.uptime() > 0);
console.log("EOL:", os.EOL === "\n");

const ifaces = os.networkInterfaces();
console.log("networkInterfaces:", typeof ifaces === "object");

const ui = os.userInfo();
console.log("userInfo.username:", typeof ui.username === "string");

// ── util ──────────────────────────────────────────────────────────────────
console.log("\n=== util ===");
const promisified = promisify(fs.readFile);
const pContent = await promisified(testFile);
console.log("promisify:", pContent.toString().includes("Hello Node.js fs!"));

console.log("util.format:", util.format("%s = %d", "x", 42) === "x = 42");
console.log("util.inspect:", util.inspect({ a: 1 }).includes("a"));
console.log("util.isString:", util.types.isStringObject(new String("hi")));
console.log("util.isDate:", util.types.isDate(new Date()));
console.log("util.isRegExp:", util.types.isRegExp(/test/));

function oldStyleCb(x: number, cb: (err: Error | null, res?: number) => void) {
  cb(null, x * 2);
}
const pOld = promisify(oldStyleCb);
const doubled = await pOld(21);
console.log("promisify custom:", doubled === 42);

// ── Streams ───────────────────────────────────────────────────────────────
console.log("\n=== Streams ===");
// Readable from array
const readable = Readable.from(["hello", " ", "world"]);
const chunks: string[] = [];
for await (const chunk of readable) {
  chunks.push(String(chunk));
}
console.log("Readable.from:", chunks.join("") === "hello world");

// Transform stream
const upper = new Transform({
  transform(chunk, _enc, cb) {
    cb(null, chunk.toString().toUpperCase());
  },
});

const pipeResult = await new Promise<string>((resolve) => {
  let out = "";
  const src = Readable.from(["hello ", "stream"]);
  src.pipe(upper).on("data", (d: Buffer) => (out += d.toString())).on("end", () => resolve(out));
});
console.log("Transform pipe:", pipeResult === "HELLO STREAM");

// pipeline (promisified)
const pipelineP = promisify(pipeline);
const src2 = Readable.from(["a", "b", "c"]);
const collected: string[] = [];
const sink = new Writable({
  write(chunk, _enc, cb) {
    collected.push(chunk.toString());
    cb();
  },
});
await pipelineP(src2, sink);
console.log("pipeline:", collected.join("") === "abc");

// createReadStream / createWriteStream
const rsFile = `${TMP}/rs-test.txt`;
fs.writeFileSync(rsFile, "stream content here");
const rs = fs.createReadStream(rsFile, { encoding: "utf8" });
const rsChunks: string[] = [];
for await (const chunk of rs) {
  rsChunks.push(chunk as string);
}
console.log("createReadStream:", rsChunks.join("") === "stream content here");

// ── zlib ──────────────────────────────────────────────────────────────────
console.log("\n=== zlib ===");
const input = Buffer.from("Hello, zlib compression world! ".repeat(10));
const deflated = zlib.deflateSync(input);
const inflated = zlib.inflateSync(deflated);
console.log("deflate/inflate:", inflated.toString() === input.toString());

const gzipped = zlib.gzipSync(input);
const gunzipped = zlib.gunzipSync(gzipped);
console.log("gzip/gunzip:", gunzipped.toString() === input.toString());
console.log("gzip smaller:", gzipped.length < input.length);

// ── assert ────────────────────────────────────────────────────────────────
console.log("\n=== assert ===");
assert.ok(true);
assert.strictEqual(1 + 1, 2);
assert.deepStrictEqual({ a: 1 }, { a: 1 });
assert.notStrictEqual(1, 2);
try {
  assert.strictEqual(1, 2);
  console.log("should have thrown");
} catch (e) {
  console.log("assert throws:", e instanceof assert.AssertionError);
}
console.log("assert OK");

// ── worker_threads ────────────────────────────────────────────────────────
console.log("\n=== worker_threads ===");
console.log("isMainThread:", isMainThread);
console.log("threadId:", typeof threadId === "number");

// Create a worker with inline code
const workerResult = await new Promise<number>((resolve, reject) => {
  const w = new Worker(
    `
    const { parentPort, workerData } = require('worker_threads');
    const result = workerData.x * workerData.y;
    parentPort.postMessage({ result });
    `,
    {
      eval: true,
      workerData: { x: 6, y: 7 },
    },
  );
  w.on("message", (msg: any) => resolve(msg.result));
  w.on("error", reject);
  w.on("exit", (code) => {
    if (code !== 0) reject(new Error(`Worker exited with code ${code}`));
  });
});
console.log("worker result:", workerResult === 42);

// SharedArrayBuffer + Atomics
const sab = new SharedArrayBuffer(4);
const arr = new Int32Array(sab);
Atomics.store(arr, 0, 100);
console.log("Atomics.store:", Atomics.load(arr, 0) === 100);
const prev = Atomics.add(arr, 0, 5);
console.log("Atomics.add:", prev === 100 && Atomics.load(arr, 0) === 105);
const swapped = Atomics.compareExchange(arr, 0, 105, 200);
console.log("Atomics.compareExchange:", swapped === 105 && Atomics.load(arr, 0) === 200);

// Cleanup
try { fs.rmSync(TMP, { recursive: true }); } catch {}

console.log("\nAll Node.js APIs OK");
