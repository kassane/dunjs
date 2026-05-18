// Binary fs round-trip — writeFileSync / appendFileSync / writeFile
// must NOT UTF-8-encode a Buffer or Uint8Array payload. Previously,
// any byte >= 0x80 got replaced with the 3-byte UTF-8 replacement
// char (U+FFFD), silently corrupting writes of binary data (random
// bytes, image data, protobuf, etc.).
const fs = require("fs");
const crypto = require("crypto");

let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const tmp = `/tmp/dun_binary_fs_${process.pid}`;
fs.mkdirSync(tmp, { recursive: true });

// 1. writeFileSync(Buffer) — 4096 random bytes round-trip
const buf1 = crypto.randomBytes(4096);
fs.writeFileSync(`${tmp}/b1.bin`, buf1);
const back1 = fs.readFileSync(`${tmp}/b1.bin`);
ok("writeFileSync(Buffer) length", back1.length === 4096);
ok("writeFileSync(Buffer) bytes", back1.equals(buf1));

// 2. writeFileSync(Uint8Array) — same path
const u8 = new Uint8Array([0x00, 0x80, 0xFF, 0xAA, 0x55]);
fs.writeFileSync(`${tmp}/b2.bin`, u8);
const back2 = fs.readFileSync(`${tmp}/b2.bin`);
ok("writeFileSync(Uint8Array) length", back2.length === 5);
ok("writeFileSync(Uint8Array) bytes",
  back2[0] === 0x00 && back2[1] === 0x80 && back2[2] === 0xFF
  && back2[3] === 0xAA && back2[4] === 0x55);

// 3. writeFileSync(string) still works (sanity)
fs.writeFileSync(`${tmp}/b3.txt`, "ABC");
const back3 = fs.readFileSync(`${tmp}/b3.txt`, "utf8");
ok("writeFileSync(string)", back3 === "ABC");

// 4. appendFileSync(Buffer)
const head = Buffer.from([0xCA, 0xFE]);
const tail = Buffer.from([0xBA, 0xBE]);
fs.writeFileSync(`${tmp}/b4.bin`, head);
fs.appendFileSync(`${tmp}/b4.bin`, tail);
const back4 = fs.readFileSync(`${tmp}/b4.bin`);
ok("appendFileSync(Buffer) length", back4.length === 4);
ok("appendFileSync(Buffer) bytes",
  back4[0] === 0xCA && back4[1] === 0xFE
  && back4[2] === 0xBA && back4[3] === 0xBE);

// 5. async writeFile (promises) with Buffer
(async () => {
  const fsp = require("fs/promises");
  const buf5 = crypto.randomBytes(256);
  await fsp.writeFile(`${tmp}/b5.bin`, buf5);
  const back5 = await fsp.readFile(`${tmp}/b5.bin`);
  ok("fs.promises.writeFile(Buffer) length", back5.length === 256);
  ok("fs.promises.writeFile(Buffer) bytes", back5.equals(buf5));

  // Cleanup
  for (const n of ["b1", "b2", "b4", "b5"]) {
    try { fs.unlinkSync(`${tmp}/${n}.bin`); } catch {}
  }
  fs.unlinkSync(`${tmp}/b3.txt`);
  fs.rmdirSync(tmp);
  console.log(`Score: ${pass}/${pass + fail}`);
  process.exit(fail > 0 ? 1 : 0);
})().catch(e => { console.log("CRASH", e && e.stack || e); process.exit(2); });
