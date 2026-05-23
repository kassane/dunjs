// `buffer.isUtf8(buf)` + `buffer.isAscii(buf)` — Node v19.5+ APIs
// surfaced by exploring Node v26.x's `benchmark/buffers/buffer-isutf8.js`
// and `buffer-isascii.js`. DunJS exposed neither (only had `Buffer`,
// `SlowBuffer`, `INSPECT_MAX_BYTES`, `constants`, `kMaxLength` on
// the `node:buffer` module surface).
//
// Tested across the full range of UTF-8 validity scenarios — only
// well-formed UTF-8 returns `true`, every malformed-byte case
// returns `false`. Matches Node's `assert.ok(buffer.isUtf8(...))`
// behavior in `benchmark/buffers/buffer-isutf8.js`.

const buffer = require("buffer");
const assert = require("assert");
let passed = 0, total = 0;
function check(name, fn) {
  total++;
  try { fn(); passed++; }
  catch (e) { console.log("FAIL:", name, "—", e.message || e); }
}

// ─── isUtf8 ────────────────────────────────────────────────────
check("isUtf8 empty buffer is true", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.alloc(0)), true));
check("isUtf8 ASCII text is true", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from("hello world")), true));
check("isUtf8 BMP non-ASCII text is true (é = C3 A9)", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from("héllo")), true));
check("isUtf8 3-byte UTF-8 text is true (ℝ = E2 84 9D)", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from("∀x∈ℝ")), true));
check("isUtf8 4-byte UTF-8 text is true (𠜎 = F0 A0 9C 8E)", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from("𠜎")), true));

// Invalid: lone 0xFF (not a valid lead byte)
check("isUtf8 [0xFF] is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0xFF])), false));
// Invalid: continuation byte without lead
check("isUtf8 [0x80] (orphan continuation) is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0x80])), false));
// Invalid: 2-byte lead with missing continuation
check("isUtf8 [0xC3] (truncated 2-byte) is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0xC3])), false));
// Invalid: overlong U+0041 encoded as 2 bytes (C1 81)
check("isUtf8 [0xC1, 0x81] (overlong 2-byte) is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0xC1, 0x81])), false));
// Invalid: lone surrogate U+D800 encoded as 3 bytes (ED A0 80)
check("isUtf8 [0xED, 0xA0, 0x80] (lone surrogate) is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0xED, 0xA0, 0x80])), false));
// Invalid: codepoint > U+10FFFF
check("isUtf8 [0xF5, 0x80, 0x80, 0x80] (> U+10FFFF) is false", () =>
  assert.strictEqual(buffer.isUtf8(Buffer.from([0xF5, 0x80, 0x80, 0x80])), false));

// ─── isAscii ───────────────────────────────────────────────────
check("isAscii empty buffer is true", () =>
  assert.strictEqual(buffer.isAscii(Buffer.alloc(0)), true));
check("isAscii pure ASCII is true", () =>
  assert.strictEqual(buffer.isAscii(Buffer.from("hello world")), true));
check("isAscii any byte ≥ 0x80 is false", () =>
  assert.strictEqual(buffer.isAscii(Buffer.from([0x41, 0x80])), false));
check("isAscii valid UTF-8 multi-byte is false (high bits set)", () =>
  assert.strictEqual(buffer.isAscii(Buffer.from("héllo")), false));

// ─── kStringMaxLength ──────────────────────────────────────────
check("buffer.kStringMaxLength is a number", () =>
  assert.strictEqual(typeof buffer.kStringMaxLength, "number"));
check("buffer.kStringMaxLength matches constants.MAX_STRING_LENGTH", () =>
  assert.strictEqual(buffer.kStringMaxLength,
                     buffer.constants.MAX_STRING_LENGTH));

console.log(`\n${passed}/${total} buffer-validator behaviors verified`);
if (passed !== total) {
  console.log("FAIL: some node:buffer invariants don't hold on DunJS");
  process.exit(1);
}
