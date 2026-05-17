// Bun.hash.{crc32, adler32, xxh32, xxh64} + Deno.mkdir async.
const buf = new Uint8Array([1, 2, 3, 4, 5]);
console.log("crc32:", Bun.hash.crc32(buf).toString(16));
console.log("adler32:", Bun.hash.adler32(buf).toString(16));
console.log("xxh32:", Bun.hash.xxh32(buf).toString(16));
console.log("xxh64:", typeof Bun.hash.xxh64(buf));
console.log("crc32 of 'hello':", Bun.hash.crc32("hello").toString(16));

// Deno.mkdir async (returns a Promise) and mkdirSync (sync).
const t = `/tmp/dun_using_test_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
await Deno.mkdir(t);
console.log("mkdir async ok");
Deno.removeSync(t);

const t2 = `/tmp/dun_using_test_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
Deno.mkdirSync(t2);
console.log("mkdir sync ok");
Deno.removeSync(t2);
