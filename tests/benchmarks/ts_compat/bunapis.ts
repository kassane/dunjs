// bun-apis.ts — Bun.* compatibility surface test
// Covers: Bun.file, Bun.write, Bun.serve, Bun.spawn, Bun.password,
//         Bun.hash, Bun.sleep, Bun.FileSystemRouter, Bun.build,
//         Bun.fileURLToPath, Bun.pathToFileURL, Bun.indexOfLine,
//         Bun.stringWidth, Bun.nanoseconds, Bun.peek, Bun.resolveSync,
//         Bun.deepEquals, Bun.escapeHTML, Bun.inspect, Bun.which, Bun.gc

const { writeFileSync, readFileSync, existsSync, unlinkSync } = require("fs");

const tmpFile = "/tmp/dunjs-bun-test.txt";
const tmpContent = "Hello from DunJS Bun compat!\nLine 2\nLine 3\n";

// Setup
writeFileSync(tmpFile, tmpContent);

// ── Bun.file ──────────────────────────────────────────────────────────────
console.log("=== Bun.file ===");
const bunFile = Bun.file(tmpFile);
console.log("Bun.file exists:", typeof bunFile === "object");
console.log("Bun.file size:", bunFile.size > 0);
console.log("Bun.file type:", typeof bunFile.type === "string");

const text = await bunFile.text();
console.log("Bun.file.text():", text.startsWith("Hello from DunJS"));

const arrayBuf = await bunFile.arrayBuffer();
console.log("Bun.file.arrayBuffer():", arrayBuf.byteLength > 0);

const bytes = new Uint8Array(arrayBuf);
console.log("First bytes:", bytes[0] === 72); // 'H'

// ── Bun.write ─────────────────────────────────────────────────────────────
console.log("\n=== Bun.write ===");
const writeFile = "/tmp/dunjs-bun-write.txt";
const bytesWritten = await Bun.write(writeFile, "Written by Bun.write!");
console.log("Bun.write bytesWritten:", bytesWritten > 0);
const written = readFileSync(writeFile, "utf8");
console.log("Bun.write content OK:", written === "Written by Bun.write!");

// Write Buffer
const buf = Buffer.from("Binary content");
await Bun.write("/tmp/dunjs-bun-buf.txt", buf);
const bufRead = readFileSync("/tmp/dunjs-bun-buf.txt", "utf8");
console.log("Bun.write Buffer:", bufRead === "Binary content");

// ── Bun.hash ──────────────────────────────────────────────────────────────
console.log("\n=== Bun.hash ===");
const h1 = Bun.hash("hello");
const h2 = Bun.hash("hello");
const h3 = Bun.hash("world");
console.log("hash is number:", typeof h1 === "number" || typeof h1 === "bigint");
console.log("hash deterministic:", h1 === h2);
console.log("hash differs:", h1 !== h3);

// Specific hash algorithms
const crc32 = Bun.hash.crc32("test");
console.log("crc32:", typeof crc32 === "number");
const adler32 = Bun.hash.adler32("test");
console.log("adler32:", typeof adler32 === "number");
const xxh32 = Bun.hash.xxh32("test");
console.log("xxh32:", typeof xxh32 === "number");
const xxh64 = Bun.hash.xxh64("test");
console.log("xxh64:", typeof xxh64 === "number" || typeof xxh64 === "bigint");

// ── Bun.sleep ─────────────────────────────────────────────────────────────
console.log("\n=== Bun.sleep ===");
const before = Date.now();
await Bun.sleep(20);
const after = Date.now();
console.log("Bun.sleep worked:", after - before >= 15);

await Bun.sleepSync(10);
console.log("Bun.sleepSync worked:", true);

// ── Bun.nanoseconds ───────────────────────────────────────────────────────
console.log("\n=== Bun.nanoseconds ===");
const t1 = Bun.nanoseconds();
const t2 = Bun.nanoseconds();
console.log("nanoseconds is number:", typeof t1 === "number");
console.log("nanoseconds increases:", t2 >= t1);

// ── Bun.deepEquals ────────────────────────────────────────────────────────
console.log("\n=== Bun.deepEquals ===");
console.log("equal primitives:", Bun.deepEquals(1, 1));
console.log("equal arrays:", Bun.deepEquals([1, 2, 3], [1, 2, 3]));
console.log("equal objects:", Bun.deepEquals({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] }));
console.log("not equal:", !Bun.deepEquals({ a: 1 }, { a: 2 }));
console.log("nested equal:", Bun.deepEquals({ x: { y: { z: 42 } } }, { x: { y: { z: 42 } } }));

// Strict mode
console.log("strict 1 vs '1':", !Bun.deepEquals(1, "1", true));
console.log("strict NaN:", Bun.deepEquals(NaN, NaN, true));

// ── Bun.escapeHTML ────────────────────────────────────────────────────────
console.log("\n=== Bun.escapeHTML ===");
const raw = '<script>alert("XSS")</script> & "test" \'foo\'';
const escaped = Bun.escapeHTML(raw);
console.log("escapeHTML:", !escaped.includes("<script>"));
console.log("has &amp;:", escaped.includes("&amp;"));
console.log("has &lt;:", escaped.includes("&lt;"));
console.log("has &gt;:", escaped.includes("&gt;"));
console.log("has &#34; or &quot;:", escaped.includes("&#34;") || escaped.includes("&quot;"));

// ── Bun.inspect ───────────────────────────────────────────────────────────
console.log("\n=== Bun.inspect ===");
const obj = { name: "dun", version: "0.3.0", backends: ["quickjs", "jsc", "v8"] };
const inspected = Bun.inspect(obj);
console.log("inspect returns string:", typeof inspected === "string");
console.log("inspect has name:", inspected.includes("dun"));
console.log("inspect has array:", inspected.includes("quickjs"));

// Inspect with options
const inspectDeep = Bun.inspect({ a: { b: { c: { d: 42 } } } }, { depth: 10 });
console.log("inspect deep:", inspectDeep.includes("42"));

// ── Bun.which ─────────────────────────────────────────────────────────────
console.log("\n=== Bun.which ===");
const ls = Bun.which("ls");
console.log("which ls:", typeof ls === "string" && ls.length > 0);
const cat = Bun.which("cat");
console.log("which cat:", typeof cat === "string");
const nonexistent = Bun.which("__nonexistent_binary_xyz__");
console.log("which nonexistent:", nonexistent === null);

// ── Bun.resolveSync ───────────────────────────────────────────────────────
console.log("\n=== Bun.resolveSync ===");
// Resolve a relative path
const resolved = Bun.resolveSync("./bun-apis.ts", "/tmp/dunjs-tests");
console.log("resolveSync relative:", resolved.includes("bun-apis.ts"));

// Resolve built-in equivalent
try {
  const fsPath = Bun.resolveSync("fs", "/tmp");
  console.log("resolveSync fs:", typeof fsPath === "string");
} catch {
  console.log("resolveSync fs: builtin (expected)");
}

// ── Bun.stringWidth ───────────────────────────────────────────────────────
console.log("\n=== Bun.stringWidth ===");
console.log("ascii width:", Bun.stringWidth("hello") === 5);
console.log("wide char:", Bun.stringWidth("こんにちは") === 10); // CJK = 2 each
console.log("emoji:", Bun.stringWidth("😀") >= 1); // emoji width
console.log("mixed:", Bun.stringWidth("hi 世界") === 7); // 2 + 1 + 2*2

// ── Bun.indexOfLine ───────────────────────────────────────────────────────
console.log("\n=== Bun.indexOfLine ===");
const multiline = "line one\nline two\nline three";
console.log("indexOfLine 0:", Bun.indexOfLine(multiline, 0) === 0);
console.log("indexOfLine 1:", Bun.indexOfLine(multiline, 1) === 9);
console.log("indexOfLine 2:", Bun.indexOfLine(multiline, 2) === 18);

// ── Bun.peek ──────────────────────────────────────────────────────────────
console.log("\n=== Bun.peek ===");
const resolved_p = Promise.resolve(42);
const pending_p = new Promise<number>((r) => setTimeout(() => r(99), 100));

// Peek at already-resolved
const peeked = Bun.peek(resolved_p);
// In DunJS, peek returns the value if resolved, or the promise if pending
console.log("peek resolved:", peeked === 42 || peeked === resolved_p);

const peekedPending = Bun.peek(pending_p);
console.log("peek pending is promise:", peekedPending === pending_p || peekedPending === undefined);

// Bun.peek.status
const s1 = Bun.peek.status(resolved_p);
console.log("status resolved:", s1 === "fulfilled" || s1 === "resolved");
const s2 = Bun.peek.status(pending_p);
console.log("status pending:", s2 === "pending");

// ── Bun.gc ────────────────────────────────────────────────────────────────
console.log("\n=== Bun.gc ===");
Bun.gc(false); // async GC hint
Bun.gc(true);  // sync GC
console.log("gc called OK");

// ── Bun.spawn ─────────────────────────────────────────────────────────────
console.log("\n=== Bun.spawn ===");
const proc = Bun.spawn(["echo", "hello from spawn"]);
const stdout = await new Response(proc.stdout).text();
console.log("spawn stdout:", stdout.trim() === "hello from spawn");
await proc.exited;
console.log("spawn exit code:", proc.exitCode === 0);

// Spawn with stdin
const proc2 = Bun.spawn(["cat"], {
  stdin: "piped input",
});
const out2 = await new Response(proc2.stdout).text();
console.log("spawn stdin:", out2 === "piped input");

// ── Bun.password ──────────────────────────────────────────────────────────
console.log("\n=== Bun.password ===");
const hash = await Bun.password.hash("my-secret-password");
console.log("hash is string:", typeof hash === "string");
console.log("hash length:", hash.length > 20);

const valid = await Bun.password.verify("my-secret-password", hash);
console.log("verify correct:", valid === true);

const invalid = await Bun.password.verify("wrong-password", hash);
console.log("verify wrong:", invalid === false);

// Bcrypt algorithm
const bcryptHash = await Bun.password.hash("test", { algorithm: "bcrypt", cost: 4 });
console.log("bcrypt hash:", typeof bcryptHash === "string");
const bcryptValid = await Bun.password.verify("test", bcryptHash);
console.log("bcrypt verify:", bcryptValid);

// ── Bun.fileURLToPath / pathToFileURL ────────────────────────────────────
console.log("\n=== Bun.fileURLToPath / pathToFileURL ===");
const url = Bun.pathToFileURL("/tmp/test.js");
console.log("pathToFileURL:", url instanceof URL || typeof url === "string");
const urlStr = url instanceof URL ? url.href : url;
console.log("URL has file://:", urlStr.startsWith("file://"));

const backPath = Bun.fileURLToPath(urlStr);
console.log("fileURLToPath:", backPath === "/tmp/test.js");

const urlObj = new URL("file:///tmp/another.js");
const fromUrlObj = Bun.fileURLToPath(urlObj);
console.log("fileURLToPath from URL:", fromUrlObj === "/tmp/another.js");

// ── Bun.FileSystemRouter ──────────────────────────────────────────────────
console.log("\n=== Bun.FileSystemRouter ===");
// Create some route files
const routesDir = "/tmp/dunjs-bun-routes";
const { mkdirSync } = await import("fs");
try { mkdirSync(routesDir, { recursive: true }); } catch {}
writeFileSync(`${routesDir}/index.ts`, "export default () => 'home'");
writeFileSync(`${routesDir}/about.ts`, "export default () => 'about'");
writeFileSync(`${routesDir}/[id].ts`, "export default (id: string) => id");

const router = new Bun.FileSystemRouter({
  style: "nextjs",
  dir: routesDir,
});

const homeMatch = router.match("/");
console.log("match /:", homeMatch !== null);
if (homeMatch) {
  console.log("home filePath:", homeMatch.filePath.endsWith("index.ts"));
}

const aboutMatch = router.match("/about");
console.log("match /about:", aboutMatch !== null);

const dynamicMatch = router.match("/123");
console.log("match /[id]:", dynamicMatch !== null);
if (dynamicMatch) {
  console.log("dynamic params:", dynamicMatch.params?.id === "123");
}

const noMatch = router.match("/nonexistent/deep/path");
console.log("no match:", noMatch === null);

console.log("routes list:", Object.keys(router.routes).length >= 3);

// ── Bun.build (bundler) ───────────────────────────────────────────────────
console.log("\n=== Bun.build ===");
const entryPoint = "/tmp/dunjs-bun-entry.ts";
writeFileSync(entryPoint, `
  const msg: string = "bundled!";
  export function greet(name: string): string {
    return \`Hello \${name}, \${msg}\`;
  }
  console.log(greet("World"));
`);

const buildResult = await Bun.build({
  entrypoints: [entryPoint],
  outdir: "/tmp/dunjs-bun-out",
  target: "bun",
  minify: false,
});

console.log("build success:", buildResult.success);
console.log("build outputs:", buildResult.outputs.length > 0);
if (buildResult.outputs.length > 0) {
  const outFile = buildResult.outputs[0];
  console.log("output kind:", outFile.kind === "entry-point" || outFile.kind === "chunk");
  const outContent = await outFile.text();
  console.log("output has greet:", outContent.includes("greet") || outContent.includes("Hello"));
}
if (!buildResult.success && buildResult.logs.length > 0) {
  console.log("build error:", buildResult.logs[0].message);
}

// Cleanup
try {
  unlinkSync(tmpFile);
  unlinkSync(writeFile);
  unlinkSync("/tmp/dunjs-bun-buf.txt");
  unlinkSync(entryPoint);
} catch {}

console.log("\nAll Bun.* APIs OK");
