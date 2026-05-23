// Node v26 compat additions — surfaced by exploring `nodejs/node`
// `v26.x` branch's util + assert surface against DunJS's exposed
// API set. Five gaps closed in this PR:
//
//   - util.MIMEParams        (Node v18+) — companion to MIMEType
//   - util.getSystemErrorMap (Node v16+) — errno → [code, msg]
//   - util.getSystemErrorMessage (Node v22+) — errno → msg
//   - util.formatWithOptions (Node v10+) — format with inspect opts
//   - assert.partialDeepStrictEqual (Node v22+) — subset matcher

const util   = require("util");
const assert = require("assert");

let passed = 0, total = 0;
function check(name, fn) {
  total++;
  try { fn(); passed++; }
  catch (e) { console.log("FAIL:", name, "—", e.message || e); }
}

// ─── util.getSystemErrorMap ────────────────────────────────────
check("getSystemErrorMap is a function", () =>
  assert.strictEqual(typeof util.getSystemErrorMap, "function"));
check("getSystemErrorMap returns a Map", () =>
  assert.ok(util.getSystemErrorMap() instanceof Map));
check("Map has ENOENT (-2)", () => {
  const m = util.getSystemErrorMap();
  assert.deepStrictEqual(m.get(-2), ["ENOENT", "No such file or directory"]);
});
check("Map has EACCES (-13)", () => {
  const m = util.getSystemErrorMap();
  assert.deepStrictEqual(m.get(-13), ["EACCES", "Permission denied"]);
});

// ─── util.getSystemErrorMessage ────────────────────────────────
check("getSystemErrorMessage(-2) = ENOENT message", () =>
  assert.strictEqual(util.getSystemErrorMessage(-2),
                     "No such file or directory"));
check("getSystemErrorMessage of unknown errno is empty string", () =>
  assert.strictEqual(util.getSystemErrorMessage(-99999), ""));

// ─── util.MIMEParams ───────────────────────────────────────────
check("MIMEParams is a constructor", () =>
  assert.strictEqual(typeof util.MIMEParams, "function"));
check("new MIMEParams() empty", () => {
  const p = new util.MIMEParams();
  assert.strictEqual(p.has("foo"), false);
});
check("set + get + has + delete", () => {
  const p = new util.MIMEParams();
  p.set("charset", "utf-8");
  assert.strictEqual(p.get("charset"), "utf-8");
  assert.strictEqual(p.has("charset"), true);
  p.delete("charset");
  assert.strictEqual(p.has("charset"), false);
});
check("MIMEParams.entries iterable", () => {
  const p = new util.MIMEParams();
  p.set("a", "1");
  p.set("b", "2");
  const out = [];
  for (const e of p.entries()) out.push(e);
  assert.deepStrictEqual(out, [["a", "1"], ["b", "2"]]);
});

// ─── util.formatWithOptions ────────────────────────────────────
check("formatWithOptions is a function", () =>
  assert.strictEqual(typeof util.formatWithOptions, "function"));
check("formatWithOptions('%s')", () =>
  assert.strictEqual(util.formatWithOptions({colors: false}, "%s = %s", "x", 42),
                     "x = 42"));
check("formatWithOptions('%j')", () =>
  assert.strictEqual(util.formatWithOptions({colors: false}, "%j", {a: 1}),
                     '{"a":1}'));

// ─── assert.partialDeepStrictEqual ─────────────────────────────
check("partialDeepStrictEqual is a function", () =>
  assert.strictEqual(typeof assert.partialDeepStrictEqual, "function"));
check("subset matches (extra key in actual)", () =>
  assert.partialDeepStrictEqual({a: 1, b: 2, c: 3}, {a: 1, b: 2}));
check("identical matches", () =>
  assert.partialDeepStrictEqual({a: 1}, {a: 1}));
check("missing required key throws", () => {
  let threw = false;
  try { assert.partialDeepStrictEqual({a: 1}, {a: 1, b: 2}); }
  catch (e) { threw = true; }
  assert.strictEqual(threw, true);
});
check("nested partial subset", () =>
  assert.partialDeepStrictEqual({a: {x: 1, y: 2}, b: 3}, {a: {x: 1}}));
check("array prefix matches (length >= expected)", () =>
  assert.partialDeepStrictEqual([1, 2, 3, 4], [1, 2]));
check("array element mismatch throws", () => {
  let threw = false;
  try { assert.partialDeepStrictEqual([1, 2, 3], [1, 9]); }
  catch (e) { threw = true; }
  assert.strictEqual(threw, true);
});
check("Map subset matches", () => {
  const a = new Map([["x", 1], ["y", 2]]);
  const b = new Map([["x", 1]]);
  assert.partialDeepStrictEqual(a, b);
});

console.log(`\n${passed}/${total} Node-v26 compat additions verified`);
if (passed !== total) {
  console.log("FAIL: some v26 surface invariants don't hold on DunJS");
  process.exit(1);
}
