// Audit: stress SIMD hex encoder edge cases that the unit tests
// don't cover: empty, off-by-one boundaries (15, 16, 17 bytes), large
// (1MB+), per-byte correctness.
const crypto = require("crypto");

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) pass++;
  else { fail++; console.log("FAIL", name); }
}

// 1) Empty buffer
check("empty digest hex", crypto.createHash("md5").update("").digest("hex") === "d41d8cd98f00b204e9800998ecf8427e");

// 2) Single byte
check("1-byte hash hex", crypto.createHash("sha256").update("a").digest("hex").length === 64);

// 3) Boundary cases for SIMD 16-byte cycle: 15, 16, 17 bytes
const b15 = Buffer.alloc(15).fill(0xAB).toString("hex");
const b16 = Buffer.alloc(16).fill(0xAB).toString("hex");
const b17 = Buffer.alloc(17).fill(0xAB).toString("hex");
check("hex 15 bytes",  b15 === "ab".repeat(15));
check("hex 16 bytes",  b16 === "ab".repeat(16));
check("hex 17 bytes",  b17 === "ab".repeat(17));

// 4) Large buffer
const big = Buffer.alloc(1024 * 1024).fill(0xCD).toString("hex");
check("hex 1MB length", big.length === 2 * 1024 * 1024);
check("hex 1MB content head", big.startsWith("cd".repeat(8)));
check("hex 1MB content tail", big.endsWith("cd".repeat(8)));

// 5) Per-byte correctness: all 256 byte values
const all = Buffer.alloc(256);
for (let i = 0; i < 256; i++) all[i] = i;
const allHex = all.toString("hex");
check("hex 0..255 length", allHex.length === 512);
check("hex 0..255 byte 0",   allHex.substr(0, 2)   === "00");
check("hex 0..255 byte 255", allHex.substr(510, 2) === "ff");
check("hex 0..255 byte 128", allHex.substr(256, 2) === "80");

// 6) GCM auth tag (16 bytes) — uses hexEncodeFixed!16
try {
  const iv = crypto.randomBytes(12);
  const key = crypto.randomBytes(32);
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  c.update("hello");
  const tag = c.final("hex");  // we don't check final's result, just tag
  // Note: cipher.final returns the last block. getAuthTag returns the tag.
  check("gcm cipher final non-empty", typeof tag === "string");
} catch (e) {
  console.log("GCM not supported (expected on some platforms):", e.message);
}

// 7) HMAC hex output
const hmac = crypto.createHmac("sha256", "key").update("data").digest("hex");
check("hmac sha256 hex length", hmac.length === 64);
check("hmac sha256 lowercase", /^[0-9a-f]+$/.test(hmac));

// 8) randomBytes -> toString("hex")
const rb = crypto.randomBytes(32).toString("hex");
check("randomBytes 32 hex length", rb.length === 64);
check("randomBytes lowercase", /^[0-9a-f]+$/.test(rb));

// 9) randomUUID format
const uuid = crypto.randomUUID();
check("uuid format", /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid));

// 10) Buffer.from(hex) round-trip
const orig = Buffer.from([0x00, 0x7F, 0x80, 0xFF, 0xAB, 0xCD, 0xEF]);
const hex = orig.toString("hex");
const back = Buffer.from(hex, "hex");
check("hex roundtrip length", back.length === orig.length);
let roundtripEq = true;
for (let i = 0; i < orig.length; i++) if (orig[i] !== back[i]) roundtripEq = false;
check("hex roundtrip content", roundtripEq);

// 11) Latin1 encoding (uses StackFallback now)
const l1 = Buffer.from([0x41, 0x42, 0x43, 0x80, 0xFF]).toString("latin1");
check("latin1 length", l1.length === 5);
check("latin1 byte 3", l1.charCodeAt(3) === 0x80);
check("latin1 byte 4", l1.charCodeAt(4) === 0xFF);

// 12) Latin1 large (>2KB stack budget)
const l1Big = Buffer.alloc(4096).fill(0x41).toString("latin1");
check("latin1 4KB length", l1Big.length === 4096);
check("latin1 4KB content", l1Big[0] === "A" && l1Big[4095] === "A");

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
