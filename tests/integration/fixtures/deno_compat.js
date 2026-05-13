// Test Deno API compatibility
console.log("Deno.version.deno:", typeof Deno.version.deno === "string" ? "ok" : "fail");
console.log("Deno.build.os:", typeof Deno.build.os === "string" ? "ok" : "fail");
console.log("Deno.pid:", typeof Deno.pid === "number" ? "ok" : "fail");
console.log("Deno.cwd:", typeof Deno.cwd() === "string" ? "ok" : "fail");
console.log("Deno.hostname:", typeof Deno.hostname() === "string" ? "ok" : "fail");
console.log("Deno.noColor:", typeof Deno.noColor === "boolean" ? "ok" : "fail");
console.log("Deno.errors:", typeof Deno.errors === "object" ? "ok" : "fail");
console.log("Deno.inspect:", typeof Deno.inspect === "function" ? "ok" : "fail");

// env
Deno.env.set("DUN_TEST_123", "hello");
console.log("env.set/get:", Deno.env.get("DUN_TEST_123") === "hello" ? "ok" : "fail");
console.log("env.has:", Deno.env.has("DUN_TEST_123") ? "ok" : "fail");
Deno.env.delete("DUN_TEST_123");
console.log("env.delete:", Deno.env.get("DUN_TEST_123") === undefined ? "ok" : "fail");

// fs ops
Deno.writeTextFileSync("/tmp/dun_deno_test.txt", "deno compat");
console.log("writeTextFileSync:", "ok");
console.log("readTextFileSync:", Deno.readTextFileSync("/tmp/dun_deno_test.txt") === "deno compat" ? "ok" : "fail");
const stat = Deno.statSync("/tmp/dun_deno_test.txt");
console.log("statSync.isFile:", stat.isFile ? "ok" : "fail");
console.log("statSync.size:", stat.size > 0 ? "ok" : "fail");
Deno.copyFileSync("/tmp/dun_deno_test.txt", "/tmp/dun_deno_test2.txt");
console.log("copyFileSync:", Deno.readTextFileSync("/tmp/dun_deno_test2.txt") === "deno compat" ? "ok" : "fail");
Deno.renameSync("/tmp/dun_deno_test2.txt", "/tmp/dun_deno_test3.txt");
console.log("renameSync:", Deno.readTextFileSync("/tmp/dun_deno_test3.txt") === "deno compat" ? "ok" : "fail");
Deno.removeSync("/tmp/dun_deno_test.txt");
Deno.removeSync("/tmp/dun_deno_test3.txt");
console.log("removeSync:", "ok");

// web compat
console.log("atob:", atob(btoa("hello")) === "hello" ? "ok" : "fail");
console.log("structuredClone:", structuredClone({a: 1}).a === 1 ? "ok" : "fail");
const enc = new TextEncoder();
console.log("TextEncoder:", enc.encoding === "utf-8" ? "ok" : "fail");
const dec = new TextDecoder();
console.log("TextDecoder:", dec.encoding === "utf-8" ? "ok" : "fail");
