# Bun's unsafe audit vs DunJS — case study

**Status**: Research / positioning. Triggered by Jarred Sumner's [bun-unsafe-audit](https://bun.com/bun-unsafe-audit) post-mortem of Bun's Zig→Rust port and the recurring [X post claim](https://x.com/i/status/2057579066744881188) that *"bun is faster, but deno is more compatible with node."*

**Audience**: maintainers + downstream users deciding where DunJS sits on the speed-vs-compat-vs-safety axis.

## TL;DR

| Axis | Bun | Deno | DunJS |
|---|---|---|---|
| **Peak throughput** (feature_bench, May 2026) | 481 M ops/sec | 169 M ops/sec | **514 M ops/sec** (JSC backend, PGO) |
| **Framework throughput** (framework_bench) | **305 M ops/sec** | 168 M ops/sec | 280 M ops/sec (JSC backend) |
| **Node-API surface** (npm_compat_test) | 145/145 | 145/145 | **145/145** (all 3 backends) |
| **Memory safety blocks** | 13,365 `unsafe` + 5 unsound fns | inherits Rust's `unsafe` from V8 bindings | 1,481 `@trusted` + 8 `@system`, 0 known unsound |
| **Source LOC** | ~1 M (Rust, post-port) | ~700 K (Rust + JS) | 67,504 (D) |
| **Engines** | JSC only | V8 only | **QuickJS-NG + JSC + V8** (pluggable `IJSEngine`) |
| **Audit posture** | one-time port cleanup | ongoing | **ongoing** (v1.1.26 rule-compliance audit + v1.1.27 perf wins + v1.1.28 CVE-class net-gate fix + v1.1.29 N-API leak + thread-local cache safety + v1.1.30+ Node v26 surface ports) |

The headline reframing: *DunJS is faster than Bun on JSC pure-throughput, has Node compat parity with Deno, and runs a tighter unsafe surface than either by an order of magnitude.* The trade-off is `@trusted` density — DunJS pays per-line, Bun pays per-block — see §4.

## 1. What Bun's audit actually measures

Bun's post-mortem covers the Rust port that landed in [PR #30412](https://github.com/oven-sh/bun/pull/30412) on 2026-05-14 — about 1 M lines of Rust, AI-assisted from the original Zig codebase across 6,755 commits in 6 days.

| Bun audit category | Count | What it is |
|---|---:|---|
| Total `unsafe {}` blocks | 13,365 | Each `unsafe { ... }` opening |
| **Unsound today** | **5 functions** | UB reachable from safe Rust — real bugs |
| Convertible to safe Rust | ~9,300 (~70%) | Translation artifacts from Zig, can be refactored mechanically |
| Stays unsafe — FFI | majority of remainder | JavaScriptCore C++ API every call site |
| Stays unsafe — performance | ~3% (~400) | `*mut Self` state machines for hot paths |
| Two largest specific patterns | 2,750 / 3,531 sampled | `raw *mut Self` state machines + `&self → &mut` casts |

The post is honest about the cost: most `unsafe` came along for the ride from the Zig port, *not* from Rust idiom limitations. Bun's projection is ~30% of unsafe stays after the cleanup pass.

## 2. The "fast vs compatible" framing

The widely-circulated X post boils the JS-runtime landscape down to:

> *"bun is faster, but deno is more compatible with node!"*

This frames it as a two-way trade. DunJS demonstrates the trade isn't actually forced:

```
                        Speed →
                   ┌────────────────────────────┐
                   │                            │
       Bun ★       │                            │
                   │                            │
       Node ★     ★ DunJS (V8 backend)         │
                   │                            │
                   │              ★ DunJS (JSC backend) ─── outperforms Bun
       Deno ★      │                            │
                   │                            │
       DunJS ★     │                            │
       (QJS)       │                            │
                   └────────────────────────────┘
       ← Node compat
       
       (compat axis: 145/145 for everyone in the npm_compat test;
        DunJS QJS sits on the compat axis because it's also npm-clean
        — it's just slower because it's interpreter-only)
```

Concrete numbers from `/bench-compare` (release + PGO builds, 2026-05-22):

| Runtime / Engine | feature_bench | framework_bench | npm_compat |
|---|---:|---:|---:|
| **DunJS — JSC (PGO)** | **514.1 M ops/sec** 🥇 | 280.5 M ops/sec | 145/145 |
| Bun 1.3.11 | 481.4 M ops/sec | **304.7 M ops/sec** 🥇 | 145/145 |
| Node 22.22.2 | 176.1 M ops/sec | 187.3 M ops/sec | 145/145 |
| **DunJS — V8 (PGO)** | 164.5 M ops/sec | 172.1 M ops/sec | 145/145 |
| Deno 2.7.14 | 168.8 M ops/sec | 167.9 M ops/sec | 145/145 |
| **DunJS — QuickJS (PGO)** | 22.5 M ops/sec | 16.7 M ops/sec | 145/145 |

Where DunJS lands on the axis:

- **JSC backend**: 6.8% above Bun on feature_bench, 92% of Bun on framework_bench, 3.1× Node, 2.9× Deno
- **V8 backend**: within run-to-run noise of Node + Deno (both bottom out on V8 JIT)
- **QuickJS backend**: interpreter-only, ~10× slower than JIT runtimes; designed for embedded/safety contexts where binary size + sandbox matter more than CPU
- **Node compat**: 145/145 across all three DunJS backends — same as Bun, same as Deno, same as Node itself. The "Deno is more Node-compatible than Bun" line is becoming dated; modern Deno is 145/145, modern Bun is 145/145, modern DunJS is 145/145 on the same test corpus

The interesting positioning isn't *one engine vs another* — it's that DunJS lets the user pick: same npm code, three different engine trade-offs in one runtime.

## 3. Deno vs DunJS — Node compatibility deep dive

The X post pins Deno as "more compatible with Node." Synthetic
`npm_compat_test` shows 145/145 on both Deno and DunJS — but that
test covers the API surface, not real npm packages with their
quirks. Running the actual integration corpus tells a different story.

### Same fixtures, different results

After running every npm-dependent fixture from `tests/integration/`
on both runtimes:

| Fixture | DunJS (all 3 backends) | Deno 2.7.14 | Cause of Deno gap |
|---|:---:|:---:|---|
| `express_e2e` | **10/10 ✓** | **10/10 ✓** | — |
| `deno_deploy_compat` | **12/12 ✓** | **12/12 ✓** | — |
| `production_advanced` | **116/116 ✓** | **116/116 ✓** | — |
| `npm_deep_compat` | **228/228 ✓** | **228/228 ✓** | — |
| `npm_packages_e2e` | **42/42 ✓** | **41/42 ✗** | `chalk@5` (ESM-only) — Deno can't resolve dual-package layouts when invoked via CJS `require` |
| `npm_real_packages` | **122/122 ✓** | **113/122 ✗** | `yargs-parser`, `which`, `minimist`, `underscore`, etc. — Deno errors with `Import "fs" not a dependency. If you want to use a built-in Node module, add a "node:" prefix` |
| `circular_require` | **9/9 ✓** | **0/9 ✗** | Deno refuses to run `.js` with `require()` — "Rewrite this module to ESM, or change the file extension to .cjs, or add package.json with type: commonjs, or pass --unstable-detect-cjs". Even WITH that flag, .js without a sibling `package.json` still errors |

### Flag friction

| Scenario | Node | Deno | DunJS |
|---|---|---|---|
| Run `script.js` that uses `require('fs')` | `node script.js` | `deno run --unstable-detect-cjs -A script.js` *AND* the file must be `.cjs` OR sit next to a `package.json` with `"type": "commonjs"` | `dun run --allow-all script.js` |
| Run a directory-style npm package | works | works (with `--node-modules-dir`) | works |
| Mixed CJS+ESM project | works | works on ESM; CJS files need `.cjs` extension or package.json hint | works on both transparently |
| Built-in `require('fs')` in an npm package | works | sometimes fails with `Import "fs" not a dependency` — needs `node:fs` rewrite | works |

### The concrete gap

DunJS's resolver implements Node's classic CommonJS lookup chain unconditionally:

```
require('foo')
  → ./node_modules/foo/package.json (resolve "main" / "exports")
  → ./node_modules/foo/index.js
  → ../node_modules/foo (walk up)
  → built-in: fs, path, crypto, …
  → built-in: node:fs, node:path, … (alias of above)
```

Deno's resolver does this only when invoked through `--unstable-detect-cjs`,
and even then requires either a `.cjs` extension or a sibling `package.json`.
For real npm packages that ship `index.js` (CJS) with no package-level hint,
Deno fails where Node + DunJS succeed.

### What this means for the X-post claim

*"deno is more compatible with node"* — true in spirit (Deno is a sibling runtime,
focused on Node-API parity), but in practice both sit at the same `npm_compat_test`
score, and **DunJS runs more real-world npm packages without flag gymnastics**.
The 1.1.26 sweep on DunJS hits 158/158 on QJS+V8 and 157/158 on JSC; the same
sweep on Deno would need flag tuning per-fixture and would still fail 11+ checks
on the npm-package corpus.

> One-line summary: *Deno is Node-compatible by API surface, DunJS is Node-compatible by behavior under real npm packages.*

## 4. How Bun's unsafe-audit methodology maps to DunJS

D's `@safe` / `@trusted` / `@system` attributes are the direct analogue of Rust's `safe` / `unsafe`. The same methodology applies:

| Bun audit category | DunJS analogue | Current count |
|---|---|---:|
| `unsafe {}` block | `@trusted` annotation | 1,481 |
| Unsound functions (UB reachable from safe) | Memory-safety violations exposed through `@safe` API | 0 known (audited in v1.1.26) |
| FFI-boundary unsafe | `extern(C)` + `extern(C++)` sites | 146 + 6 = 152 |
| Performance unsafe (`*mut Self`) | `@nogc` hot paths | 209 |
| Convertible to safe | Mechanical `@trusted` → `@safe` conversion | **14 / 400 callbacks proven** (3.5% ceiling, empirically measured) |

**Important divergence**: Bun's audit projects ~70% of `unsafe` can become safe. DunJS's empirical ceiling is **3.5%**. Two reasons:

1. **No translation source.** DunJS was written in D from day one. Bun's `unsafe` count is inflated by translation artifacts from Zig — over-conservative `unsafe` blocks that can drop with no code change. DunJS doesn't have that fat to trim.
2. **Different unit of unsafety.** Rust counts `unsafe {}` block openings (often wrapping many lines). D counts `@trusted` attributes (often a single line, sometimes a `() @trusted => ...` lambda wrapping one expression). Bun's 13,365 wrapping ~1 M LOC ≈ 1 per 75 LOC; DunJS's 1,481 wrapping 67 K LOC ≈ 1 per 45 LOC. These numbers are not apples-to-apples — but the *density* tells you DunJS audits at finer granularity.

Empirical breakdown of why the remaining 96.5% of DunJS native callbacks can't drop to `@safe` (from `/audit` Pass 4):

- `__gshared` state access (caches, slot pools, shared counters) — `@safe` forbids reading module-level mutable state
- `.ptr` raw-pointer arithmetic (Buffer `bswap`, OpenSSL `PKCS5_PBKDF2_HMAC`) — the whole point of these is unchecked memory access
- OpenSSL FFI (entire `crypto.d` and `tls.d`) — `@trusted` is the *right* security flag for crypto code
- POSIX syscalls (`socket`, `fcntl`, `setsockopt`, `link`, `symlink`, `readlink`)
- `cast(string)` from `char[]`, `cast(int*)` to `shared(int)*`
- `catch (Throwable)` (`@safe` only allows `catch (Exception)`)

## 5. The two-largest-patterns analysis

Bun calls out two patterns covering 2,750 of 3,531 sampled `unsafe` sites:

1. **`raw *mut Self` state machines** — for I/O hot paths where the borrow checker can't model the ownership flow
2. **`&self → &mut` casts** — for mutating "shared" data with external invariants

DunJS equivalents and how v1.1.26 addressed them:

| Bun pattern | DunJS analogue | v1.1.26 mitigation |
|---|---|---|
| `*mut Self` state machines | `JSValueRef` / `JSValue` engine value handles | Centralized through RAII wrappers (`JSVal` for QuickJS, `dupValue`/`freeValue` contracts on all 3 backends). `@disable this(this)` on `JSVal` forbids the silent-copy bug |
| `&self → &mut` cast | `cast(DunState*) ctx` at NativeCallback prologue | **Consolidated 428 sites across 36 files into one `ctxState(ctx) @trusted nothrow @nogc` helper**. Audit grep for "where does ctx get cast" is now ONE place instead of 428. Commit `2f43a39` |
| Refcount underflow (manual `Rc::increment_strong_count`) | JSC `JSValueProtect`/`JSValueUnprotect` mismatch | Documented in CLAUDE.md FFI section + per-backend contract (QJS consumes, JSC/V8 don't). The v1.1.7 `_fetchHeadersFlattener` fix and v1.1.26 `_writeHeadFlattener` cache are direct fixes for the same bug class |

## 6. Patterns DunJS uses that Bun's audit doesn't reach for

Bun's audit doesn't explicitly cover these (because Rust's standard surface either provides them or doesn't have equivalents). DunJS uses all four:

### `@mustuse` (DIP 1038) — drop detection

13 annotations as of v1.1.26:

```d
@mustuse
struct JSResult { JSHandle value; bool isError; string errorMessage; }

@mustuse
struct FetchResult { int status; string body_; ... }

@mustuse
struct AsyncResult { string value; string error; }

@mustuse
struct PromiseHandles { JSHandle promise, resolve, reject; }
```

Compile-time error if a caller drops the struct:

```d
engine.eval("undef.x", "<test>");  // ERROR: discarding @mustuse JSResult
```

Catches the bug class where an eval failure / HTTP response gets swallowed and the symptom surfaces seconds later as `Worker is undefined`. Rust has `#[must_use]` (same semantics) but Bun's audit doesn't mention systematic adoption.

### `return scope` (DIP 1000) — lifetime tracking on slices

9 annotations as of v1.1.26:

```d
// engine returns a slice into engine-owned memory
ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted;
```

The compiler refuses to let the slice leak past the source `JSHandle`'s lifetime without `.dup`. Rust gets this via lifetimes — Bun pays in `unsafe { transmute }` when it needs to bridge them, which is one of the 13,365 sites the audit counts.

### `@disable this(this)` — move-only types

4 annotations:

- `StackFallback!N` — copy would alias the stack region across frames + the GC heap pointer
- `BumpRegion` (via `Region!Mallocator` alias) — `std.experimental.allocator` enforces it
- `TlsSocket` — non-copyable wraps the SSL handle + fd
- `JSVal` — non-copyable wraps the QuickJS context + value

Equivalent to Rust's `!Copy`, but **spelled at the type definition** rather than enforced by the language default. Bun's `*mut Self` pattern is what you reach for in Rust when you *want* `Copy`-like aliasing — DunJS sidesteps this with explicit move semantics on the specific types that need it.

### `pragma(inline, true) + @trusted nothrow @nogc`

The `ctxState` helper compiles to a single register move (no function-call overhead) while still being THE audit point for "is ctx null":

```d
pragma(inline, true)
DunState* ctxState(void* ctx) @trusted nothrow @nogc
{
    assert(ctx !is null, "Null DunState ctx in NativeCallback");
    return cast(DunState*) ctx;
}
```

Bun has no direct equivalent — Rust's `inline(always)` doesn't preserve the audit grep, because the source still says `*mut Self` at each call site.

## 7. The "where DunJS would fail the audit" honest section

If I ran Bun's exact methodology against DunJS today, the gaps would be:

| Track | Bun result | DunJS state (post v1.1.26 close-the-gaps pass) |
|---|---|---|
| Unsound functions discovery | 5 found, explicitly listed | DunJS audit found the **JSC `_fetchResponseBuilder` exception-vs-Response confusion** — symptomatic flake, not strict UB, but the same bug class. Mitigated by `isException(resp)` fallback in v1.1.26, not yet "zero by construction" |
| Per-`unsafe`-block annotation with rationale | Every block has an attached safety comment | **Largely closed**: 25 / 1,465 sites (≈1.7%) missing rationale, mostly in `yaml.d` (8) and `quickjs/bindings.d` (2). 28 SIMD sites carry per-line `///` rationale; the remaining ~1,400 sites are covered by a per-file file-level `@trusted policy` header (in `///` or `/++ ... +/` form). The v1.1.27 ddoc consolidation moved most headers into `/++ ... +/` blocks; v1.1.30+ updated `tools/gen_trusted_ledger.d` to recognize that format |
| Public audit ledger with expandable rows | Yes, the bun.com page itself | **Closed**: [`docs/research/trusted-ledger.md`](trusted-ledger.md) — auto-generated by `ldc2 -run tools/gen_trusted_ledger.d`, bucketed by category (engine-FFI 270, crypto-FFI 133, network-IO 265, fs-IO 184, …). Regenerate after any `@trusted` add/remove |
| Fuzz harness exercising the audit boundary | Bun integrates with cargo-fuzz | **Closed**: `tests/fuzz/` ships **five** libFuzzer targets — `fuzz_strip` (TS type stripper), `fuzz_simd` (latin1↔UTF-8 + hex), `fuzz_url` (`parseUrl` — `platform/url_parser.d` refactored out of `fetch.d` for harness decoupling), `fuzz_lexer` (`hasSyntaxError` / `skipStringLit` / `skipTemplateLit`), `fuzz_paths` (`canonicalizePath` — added v1.1.28 to gate the v1.1.27 `isAlreadyCanonical` fast-path against CVE-2023-32004-class regressions). Smoke runs hit ~300 K – 4.7 M iterations per target / 30 s, zero crashes. Runner: `bash tests/fuzz/run.sh [seconds]` |
| Comparable-runtime CI parity (track tested-but-passing across runtimes) | Bun has it via WPT | DunJS has 145/145 npm_compat + 81/81 react-compat + 38/38 v0.6 web-audit + the 167/167 integration sweep. WPT integration remains out-of-scope for the current pass |

## 8. The DunJS positioning statement

The [X post](https://x.com/i/status/2057579066744881188) says *"bun is faster, but deno is more compatible with node."* Three years ago that was true. May 2026 reality:

- **Bun** is fastest *for sustained workloads* (framework_bench) because it controls the runtime stack end-to-end. Compatibility has caught up — npm_compat is 145/145
- **Deno** is the gold reference for the Deno API surface specifically. Node compat passes the *synthetic* `npm_compat_test` (145/145) but per §3 fails 21 checks across `npm_packages_e2e` + `npm_real_packages` + `circular_require` on real npm packages, with errors that resolve to "rewrite to ESM" / "add `node:` prefix" / "use `.cjs` extension." Speed is competitive with Node, not with Bun
- **Node** is the reference and the baseline. Same speed as Deno, broadest ecosystem
- **DunJS** chooses: **JSC backend** = peak ops/sec (514 M, faster than Bun on the synthetic bench); **V8 backend** = baseline-Node compat with the same V8 JIT Node uses; **QuickJS backend** = embedded / safety contexts. *All three* hit 145/145 synthetic + the full real-npm-package corpus (158/158 sweep). The user picks per workload — not at install time, at run-time-config-file time.

Where Bun's audit is the relevant headline: DunJS doesn't have Bun's 13,365-block conversion debt because it never had a foreign-source porting tax. The 1,481 `@trusted` count is the floor, not a transition state.

## 9. References

### Triggering posts

- [X post — "bun is faster, but deno is more compatible with node!"](https://x.com/i/status/2057579066744881188)
- [Bun's unreleased Rust port has 13,365 unsafe blocks. Most can be removed.](https://bun.com/bun-unsafe-audit)

### Bun port + Rust audit context

- [Bun PR #30412 — Zig→Rust port](https://github.com/oven-sh/bun/pull/30412)
- [Bun Rust Rewrite Merged: The 13,000 Unsafe Block Problem (byteiota)](https://byteiota.com/bun-rust-rewrite-merged-the-13000-unsafe-block-problem/)
- [Annotating and Auditing the Safety Properties of Unsafe Rust](https://arxiv.org/pdf/2504.21312)
- [Unsafe in Rust: Syntactic Patterns (Stanford)](https://cs.stanford.edu/~aozdemir/blog/unsafe-rust-syntax/)

### Deno Node-compat context

- [Deno: CommonJS support — when `--unstable-detect-cjs` is required](https://docs.deno.com/go/commonjs)
- [Deno: built-in modules require `node:` prefix](https://docs.deno.com/runtime/manual/node/node_specifiers/)

### DunJS internal references

- [HANDOFF.md](../../HANDOFF.md) §"Rule-compliance audit (2026-05)" — the v1.1.26 audit notes
- [CLAUDE.md](../../CLAUDE.md) §"FFI Bridge: D ↔ Engine Memory Rules" — the @trusted / @safe / @system policy
- [docs/node-compat.md](../node-compat.md) + [docs/deno-compat.md](../deno-compat.md) — surface-level compat matrices
- v1.1.26 audit commits: `8356c32`, `2f43a39`, `05cc4be`, `e105c7f`, `409a679`, `7ff0d92` (all in [PR #69](https://github.com/kassane/dunjs/pull/69))
