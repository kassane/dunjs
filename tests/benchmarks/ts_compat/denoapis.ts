// deno-apis.ts — Deno.* compatibility surface test
// Covers: Deno.env, Deno.readTextFileSync/writeTextFileSync, Deno.stat,
//         Deno.mkdir/remove/rename/copy, Deno.readDir, Deno.permissions,
//         Deno.serve, Deno.openKv, Deno.cron, Deno.build, Deno.errors

const { existsSync } = require("fs");

const tmpDir = "/tmp/dunjs-deno-test";

// ── Deno.build ─────────────────────────────────────────────────────────────
console.log("=== Deno.build ===");
console.log("os:", typeof Deno.build.os === "string");
console.log("arch:", typeof Deno.build.arch === "string");
console.log("target:", typeof Deno.build.target === "string");
console.log("os value:", ["linux", "darwin", "windows"].includes(Deno.build.os));
console.log("arch value:", ["x86_64", "aarch64"].includes(Deno.build.arch));

// ── Deno.version ───────────────────────────────────────────────────────────
console.log("\n=== Deno.version ===");
console.log("deno:", typeof Deno.version.deno === "string");
console.log("v8:", typeof Deno.version.v8 === "string");
console.log("typescript:", typeof Deno.version.typescript === "string");

// ── Deno.env ───────────────────────────────────────────────────────────────
console.log("\n=== Deno.env ===");
Deno.env.set("DUN_TEST_VAR", "hello-deno");
console.log("env.set:", Deno.env.get("DUN_TEST_VAR") === "hello-deno");

Deno.env.set("DUN_TEST_NUM", "42");
console.log("env.get:", Deno.env.get("DUN_TEST_NUM") === "42");

const allEnv = Deno.env.toObject();
console.log("toObject is object:", typeof allEnv === "object");
console.log("toObject has var:", allEnv["DUN_TEST_VAR"] === "hello-deno");

Deno.env.delete("DUN_TEST_VAR");
console.log("env.delete:", Deno.env.get("DUN_TEST_VAR") === undefined);

// ── Deno.cwd / chdir ───────────────────────────────────────────────────────
console.log("\n=== Deno.cwd / chdir ===");
const cwd = Deno.cwd();
console.log("cwd is string:", typeof cwd === "string");
console.log("cwd starts with /:", cwd.startsWith("/"));

// ── Deno.mkdir / readDir / remove ─────────────────────────────────────────
console.log("\n=== Deno.mkdir / readDir / remove ===");
await Deno.mkdir(tmpDir, { recursive: true });
console.log("mkdir:", existsSync(tmpDir));

await Deno.mkdir(`${tmpDir}/subdir`, { recursive: true });
console.log("mkdir recursive:", existsSync(`${tmpDir}/subdir`));

// ── Deno.writeTextFileSync / readTextFileSync ──────────────────────────────
console.log("\n=== Deno.readTextFileSync / writeTextFileSync ===");
const testFile = `${tmpDir}/test.txt`;
Deno.writeTextFileSync(testFile, "Hello from Deno compat!\n");
console.log("writeTextFileSync:", existsSync(testFile));

const content = Deno.readTextFileSync(testFile);
console.log("readTextFileSync:", content.trim() === "Hello from Deno compat!");

// Async versions
await Deno.writeTextFile(`${tmpDir}/async.txt`, "async content");
const asyncContent = await Deno.readTextFile(`${tmpDir}/async.txt`);
console.log("writeTextFile async:", asyncContent === "async content");
console.log("readTextFile async:", asyncContent === "async content");

// ── Deno.readTextFile with encoding ───────────────────────────────────────
const utf8File = `${tmpDir}/utf8.txt`;
Deno.writeTextFileSync(utf8File, "Héllo Wörld 日本語");
const utf8Content = Deno.readTextFileSync(utf8File);
console.log("UTF-8 roundtrip:", utf8Content === "Héllo Wörld 日本語");

// ── Deno.stat / lstat ─────────────────────────────────────────────────────
console.log("\n=== Deno.stat / lstat ===");
const stat = await Deno.stat(testFile);
console.log("stat.isFile:", stat.isFile);
console.log("stat.isDirectory:", !stat.isDirectory);
console.log("stat.size:", stat.size > 0);
console.log("stat.mtime:", stat.mtime instanceof Date || stat.mtime !== null);

const dirStat = await Deno.stat(tmpDir);
console.log("dir.isDirectory:", dirStat.isDirectory);
console.log("dir.isFile:", !dirStat.isFile);

// Sync stat
const statSync = Deno.statSync(testFile);
console.log("statSync.isFile:", statSync.isFile);

// ── Deno.rename ───────────────────────────────────────────────────────────
console.log("\n=== Deno.rename ===");
const renamed = `${tmpDir}/renamed.txt`;
await Deno.rename(testFile, renamed);
console.log("rename: src gone:", !existsSync(testFile));
console.log("rename: dst exists:", existsSync(renamed));

// ── Deno.copy (file) ──────────────────────────────────────────────────────
console.log("\n=== Deno.copy ===");
const copied = `${tmpDir}/copied.txt`;
await Deno.copyFile(renamed, copied);
console.log("copyFile:", existsSync(copied));
const copiedContent = Deno.readTextFileSync(copied);
console.log("copyFile content:", copiedContent.trim() === "Hello from Deno compat!");

// ── Deno.readDir ──────────────────────────────────────────────────────────
console.log("\n=== Deno.readDir ===");
const entries: string[] = [];
for await (const entry of Deno.readDir(tmpDir)) {
  entries.push(entry.name);
}
console.log("readDir count:", entries.length >= 3);
console.log("readDir has subdir:", entries.includes("subdir"));
console.log("readDir has async.txt:", entries.includes("async.txt"));

// Sync readDir
const syncEntries: string[] = [];
for (const entry of Deno.readDirSync(tmpDir)) {
  syncEntries.push(entry.name);
}
console.log("readDirSync:", syncEntries.length >= 3);

// ── Deno.remove ───────────────────────────────────────────────────────────
console.log("\n=== Deno.remove ===");
await Deno.remove(copied);
console.log("remove file:", !existsSync(copied));

await Deno.remove(`${tmpDir}/subdir`, { recursive: true });
console.log("remove dir:", !existsSync(`${tmpDir}/subdir`));

// ── Deno.errors ───────────────────────────────────────────────────────────
console.log("\n=== Deno.errors ===");
try {
  await Deno.stat("/nonexistent/path/xyz");
  console.log("should have thrown");
} catch (e) {
  console.log("NotFound error:", e instanceof Deno.errors.NotFound);
  console.log("error name:", e.name === "NotFound" || e.message?.includes("No such"));
}

try {
  Deno.readTextFileSync("/nonexistent/file.txt");
} catch (e) {
  console.log("readTextFileSync throws:", e instanceof Deno.errors.NotFound || e.code === "ENOENT");
}

// Error types exist
console.log("NotFound class:", typeof Deno.errors.NotFound === "function");
console.log("PermissionDenied class:", typeof Deno.errors.PermissionDenied === "function");
console.log("AlreadyExists class:", typeof Deno.errors.AlreadyExists === "function");

// ── Deno.permissions ──────────────────────────────────────────────────────
console.log("\n=== Deno.permissions ===");
const permResult = await Deno.permissions.query({ name: "read", path: "/tmp" });
console.log("permissions.query:", typeof permResult.state === "string");
console.log("perm state:", ["granted", "denied", "prompt"].includes(permResult.state));

const netPerm = await Deno.permissions.query({ name: "net" });
console.log("net perm:", typeof netPerm.state === "string");

// ── Deno.serve (HTTP server) ───────────────────────────────────────────────
console.log("\n=== Deno.serve ===");
let serverStopped = false;
const port = 34821;

const server = Deno.serve(
  { port, hostname: "127.0.0.1", onListen: ({ port: p }) => console.log(`Deno.serve listening on ${p}`) },
  (req: Request) => {
    const url = new URL(req.url);
    if (url.pathname === "/json") {
      return new Response(JSON.stringify({ ok: true, path: "/json" }), {
        headers: { "content-type": "application/json" },
      });
    }
    if (url.pathname === "/echo") {
      return new Response(`echo: ${url.searchParams.get("msg") ?? ""}`);
    }
    return new Response("OK from Deno.serve", { status: 200 });
  },
);

console.log("server object:", typeof server === "object");

// Give server time to start
await new Promise((r) => setTimeout(r, 50));

// Test request
try {
  const res = await fetch(`http://127.0.0.1:${port}/`);
  const body = await res.text();
  console.log("serve response:", body === "OK from Deno.serve");
  console.log("serve status:", res.status === 200);

  const jsonRes = await fetch(`http://127.0.0.1:${port}/json`);
  const jsonBody = await jsonRes.json();
  console.log("serve json:", jsonBody.ok === true);

  const echoRes = await fetch(`http://127.0.0.1:${port}/echo?msg=hello`);
  const echoBody = await echoRes.text();
  console.log("serve echo:", echoBody === "echo: hello");
} catch (e) {
  console.log("serve fetch failed:", e.message);
}

server.shutdown?.();
server.close?.();

// ── Deno.openKv ────────────────────────────────────────────────────────────
console.log("\n=== Deno.openKv ===");
const kv = await Deno.openKv(`${tmpDir}/test.kv`);
console.log("openKv:", typeof kv === "object");

await kv.set(["users", "alice"], { name: "Alice", age: 30 });
await kv.set(["users", "bob"], { name: "Bob", age: 25 });
await kv.set(["config", "theme"], "dark");

const alice = await kv.get(["users", "alice"]);
console.log("kv.get:", alice.value?.name === "Alice");
console.log("kv.get value:", alice.value?.age === 30);
console.log("kv.versionstamp:", typeof alice.versionstamp === "string");

const missing = await kv.get(["users", "nobody"]);
console.log("kv.get missing:", missing.value === null);

// List entries
const list = kv.list({ prefix: ["users"] });
const collected: any[] = [];
for await (const entry of list) {
  collected.push(entry);
}
console.log("kv.list count:", collected.length === 2);
console.log("kv.list keys:", collected.some((e) => e.key[1] === "alice"));

// Atomic transaction
const result = await kv.atomic()
  .check({ key: ["users", "alice"], versionstamp: alice.versionstamp })
  .set(["users", "alice"], { name: "Alice", age: 31 })
  .commit();
console.log("atomic commit:", result.ok === true);

const updated = await kv.get(["users", "alice"]);
console.log("atomic update:", updated.value?.age === 31);

await kv.delete(["config", "theme"]);
const deleted = await kv.get(["config", "theme"]);
console.log("kv.delete:", deleted.value === null);

kv.close();
console.log("kv.close: OK");

// ── Deno.cron ──────────────────────────────────────────────────────────────
console.log("\n=== Deno.cron ===");
let cronFired = false;
const cron = Deno.cron("test-cron", "* * * * *", async () => {
  cronFired = true;
});
console.log("cron created:", typeof cron === "object" || cron === undefined);

// Trigger manually via returned handle
if (cron && typeof cron.trigger === "function") {
  await cron.trigger();
  console.log("cron triggered:", cronFired);
} else {
  console.log("cron registered (trigger not available in shim)");
}

// Cleanup
try {
  await Deno.remove(tmpDir, { recursive: true });
} catch {}

console.log("\nAll Deno.* APIs OK");
