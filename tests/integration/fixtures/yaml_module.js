// dun:yaml built-in: parse + stringify subset coverage
const yaml = require("yaml");
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

// ── parse: scalars ─────────────────────────────────────────────
const a = yaml.parse("name: alice\nage: 30\nactive: true\nspeed: 3.14\n");
ok("scalar string",  a.name === "alice");
ok("scalar int",     a.age === 30);
ok("scalar bool",    a.active === true);
ok("scalar float",   a.speed === 3.14);

// ── parse: block sequence ──────────────────────────────────────
const b = yaml.parse("- 1\n- 2\n- 3\n");
ok("block seq length",  b.length === 3);
ok("block seq element", b[0] === 1 && b[2] === 3);

// ── parse: mapping with nested sequence ────────────────────────
const c = yaml.parse("items:\n  - apple\n  - banana\n  - cherry\n");
ok("nested seq length",  c.items.length === 3);
ok("nested seq item",    c.items[1] === "banana");

// ── parse: nested mapping ──────────────────────────────────────
const d = yaml.parse("server:\n  host: localhost\n  port: 8080\n");
ok("nested map host",   d.server.host === "localhost");
ok("nested map port",   d.server.port === 8080);

// ── parse: flow style ──────────────────────────────────────────
const e = yaml.parse("colors: [red, green, blue]\nopts: {x: 1, y: 2}\n");
ok("flow seq length",   e.colors.length === 3);
ok("flow seq item",     e.colors[2] === "blue");
ok("flow map x",        e.opts.x === 1);
ok("flow map y",        e.opts.y === 2);

// ── parse: null + comment + quoted ─────────────────────────────
const f = yaml.parse("# comment\nfoo: \"bar baz\"\nnothing: ~\nempty: null\n");
ok("quoted string",     f.foo === "bar baz");
ok("tilde null",        f.nothing === null);
ok("null keyword",      f.empty === null);

// ── parse: deeply nested ───────────────────────────────────────
const g = yaml.parse("app:\n  db:\n    host: pg\n    port: 5432\n  cache:\n    - redis\n    - memcached\n");
ok("deep map host",     g.app.db.host === "pg");
ok("deep seq[1]",       g.app.cache[1] === "memcached");

// ── stringify: round-trip simple ──────────────────────────────
const orig = {name: "bob", scores: [90, 85, 88], active: true};
const dumped = yaml.stringify(orig);
const reparsed = yaml.parse(dumped);
ok("roundtrip name",    reparsed.name === "bob");
ok("roundtrip scores",  reparsed.scores.length === 3 && reparsed.scores[0] === 90);
ok("roundtrip bool",    reparsed.active === true);

// ── stringify: nested ──────────────────────────────────────────
const o2 = {meta: {tag: "v1", count: 5}, items: [{n: 1}, {n: 2}]};
const dumped2 = yaml.stringify(o2);
const re2 = yaml.parse(dumped2);
ok("nested map tag",    re2.meta.tag === "v1");
ok("nested seq[0].n",   re2.items[0].n === 1);

// ── stringify: null/empty ──────────────────────────────────────
ok("stringify null",    yaml.stringify(null).trim() === "null");
ok("stringify empty[]", yaml.stringify([]).trim() === "[]");
ok("stringify empty{}", yaml.stringify({}).trim() === "{}");

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
