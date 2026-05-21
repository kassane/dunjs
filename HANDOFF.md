# DunJS — Handoff Notes

Living document. Points the next maintainer at the moving pieces
and the gotchas that bite you on day one. Read alongside
[`CLAUDE.md`](CLAUDE.md), [`SECURITY.md`](SECURITY.md), and
[`TESTING.md`](TESTING.md).

## Current state (v1.1.25)

- Integration sweep: **156/156** on QJS / V8, **155/155 + 1 SKIP**
  on JSC. The `cve_priv_files.js` fixture (8/8) added in v1.1.25
  regression-tests the sandbox-bypass fix (CVE-2024-34346 class).
- Unit tests: **71/71** clean.
- Backends: QuickJS-NG **0.14.0**, JavaScriptCore (prebuilt
  WebKit), V8 **15.0.91** (via `vendor/v8shim/`). All three
  build & test green under LDC 1.42.0 / LLVM 21.1.8.
- Build types: `release`, `release-pgo-gen`, `release-pgo`,
  `asan`, `tsan`. None of them sets `--mcpu=native` anymore —
  per PR #59 the default is whatever LLVM picks. Docker images
  pin `x86-64-v3` (amd64) / `generic+NEON` (arm64) via
  `${TARGETARCH}` before `dub build` (PR #60).

## Recent security work (read this first)

| Window | Class | Status | Tested |
|--------|-------|--------|--------|
| **NEW v1.1.25** | CVE-2024-34346 / GHSA-23rx-c3g5-hv9w — privileged-path sandbox bypass | **Fixed** in `source/dun/security/permissions.d` (this PR) | `cve_priv_files.js` 8/8 on QJS/JSC/V8 |
| Reviewed 2026-05 | CVE-2026-32260 / CVE-2026-27190 — Deno child_process shell metachar bypass | **Not vulnerable** — `hasShellMetaChars` in `child_process.d:113` blocks `; & \| $ \` ( ) { } < > \n` before the shell sees the command | Existing fixtures + `/tmp/test_shell_meta.js` ad-hoc |
| Reviewed 2026-05 | CVE-2026-0821 / CVE-2026-0822 / CVE-2026-1145 — QuickJS-NG heap overflows in `js_typed_array_constructor[_ta]` and `js_typed_array_sort` (affect ≤ 0.11.0) | **Not vulnerable** — DunJS bundles QJS-NG **0.14.0** which includes the fixes (PRs #1299, #1306, commit `53eefbcd`) | Upstream regression suite + DunJS fuzz tests |
| v1.1.0 | CVE-2023-32004 / CVE-2024-21896 — path-traversal scope bypass | Fixed | `cve_path_traversal.js` 5/5 |
| v1.1.3 / v1.1.4 | Latin-1 high-byte + JSC NUL truncation | Fixed | `audit_simd.js` 25/25, `audit_roundtrip.js` 16/16 |

When investigating a new CVE class, the workflow is:

1. **Find** — `gh search` GitHub Advisory DB, `osv.dev`, MITRE
   for the CVE description. Focus on `denoland/deno`, `bun-sh/bun`,
   `nodejs/node`, and `quickjs-ng/quickjs` advisories.
2. **Map** — does DunJS expose the same surface? `grep -rn` the
   builtin module that mirrors the affected API. Permission-model
   CVEs almost always have a DunJS equivalent because the model
   is Deno-derived.
3. **Reproduce** — write a `/tmp/repro.js` and run against
   `./dun-rel-{qjs,jsc,v8}`. If all three show the vulnerable
   behavior, you've confirmed exposure.
4. **Fix** — usually in `source/dun/security/permissions.d`
   or the affected builtin. Cite the upstream CVE in the inline
   comment so the next reader doesn't think the guard is
   dead code.
5. **Test permanently** — add a fixture to
   `tests/integration/fixtures/cve_<class>.js` + expected
   output. Match Deno's behavior unless we have a documented
   reason to diverge. Verify on all three backends.
6. **Document** — update `SECURITY.md` ("Fixed Vulnerabilities"
   table) with the version that ships the fix.

## Built artifacts (regenerate via `/all-backends release`)

After running the skill, the working tree has:

- `./dun-rel-qjs` — QuickJS release binary
- `./dun-rel-jsc` — JSC release binary
- `./dun-rel-v8` — V8 release binary
- `./icudtl.dat` — V8 ICU data file (V8 looks for it next to the
  binary; **must** be present or any Intl / regex-Unicode / certain
  crypto operations throw `Internal error. Icu error.`)

The Dockerfiles **do not** currently copy `icudtl.dat` into the
runtime image — proposed fix is documented but deferred (see
"Known issues" below).

## Known issues / deferred work

| # | Issue | Impact | Notes |
|---|-------|--------|-------|
| 1 | JSC `bun_v7_additions` SKIP under `deno_deploy_compat` heap load | Single fixture skipped (1/156) | Pre-existing per-request listener-chain leak in fetch path. v1.1.5 → v1.1.20 plugged most of the JSC handle leaks but didn't fully close this. Standalone `bun_v7_additions` passes 24/24. Documented in CHANGELOG #43a/#58d/#59a/#60d for a future v1.2.x worker-lifecycle pass |
| 2 | Dockerfile V8 image missing `icudtl.dat` | `docker run dunjs:v8 run any-script-using-Intl-or-Unicode-regex.js` → `Internal error. Icu error.` | Proposed fix in earlier session: `COPY --from=build /src/build/icudtl.dat /usr/local/bin/icudtl.dat`. Needs the `touch build/icudtl.dat` placeholder trick for QJS/JSC images where postBuildCommand skips the copy |
| 3 | QJS `Worker(src, {eval:true})` + `setTimeout`-deferred `terminate` race | Edge-case crash | gdb-traced to QJS internal `add_shape_property`. Documented in CHANGELOG #58d/#59e. JSC/V8 don't hit it. Real apps use `await terminate(); process.exit()` rather than the racy pattern |
| 4 | No fuzzer harness for parser / type-stripper / Buffer roundtrip | Theoretical | LDC supports `-fsanitize=fuzzer` since 1.4 (see `.claude/commands/debug-native-callback.md`). Template is documented but no harness lives in the tree |

## Rule-compliance audit (2026-05) — applied + deferred

A three-track audit (`@trusted` overuse, magic-number duplicates, DIP
coverage) ran on the v1.1.25 tree across two commits.

**Pass 1 — Cross-module constants + paths.canonicalizePath**

- `dun.platform.paths.canonicalizePath`: dropped `@trusted` → `@safe`.
  This is the CVE-class fix gate (CVE-2023-32004 / CVE-2024-21896) and a
  security primitive should not need an `@trusted` escape — Phobos'
  `absolutePath` + `buildNormalizedPath` are both `@safe`, no FFI, no
  pointer arithmetic. Doc-comment now cites the CVE and the audit date
  so the next reader doesn't think the `@safe` is accidental.
- `dun.declarations`: hoisted six cross-module duplicates —
  `PAGE_SIZE_BYTES` / `NETWORK_READ_BUF_BYTES` / `STACK_BUFFER_BUDGET` /
  `MS_PER_SEC` / `NS_PER_MS` / `NS_PER_SEC`. Re-pointed the
  `LINUX_PAGE_SIZE` literal in `runtime.process_api.d:9` and the
  `timeoutMs / 1000 + (timeoutMs % 1000) * 1_000_000` math in
  `loop.iopoller.d:794` and `runtime.worker_api.d:539`. Other local
  enums (`SOCKET_READ_BUF_SIZE`, `HTTP_READ_BUF`, `TLS_READ_BUF_SIZE`,
  `READLINK_BUF_SIZE`, `WS_CLOSE_NORMAL`) were left alone — the local
  name carries documentation value the bare constant wouldn't.

**Pass 3 — IJSEngine @trusted annotation + @safe callback pilot + redundancy cleanup**

- IJSEngine: all 50+ interface methods now carry `@trusted`,
  matching what every backend implementation (QJS, JSC, V8) already
  has on its overrides. Two stay `@system`: `rawRuntime()` /
  `rawContext()` hand the caller a raw FFI pointer they can do
  anything with — pretending those are `@trusted` would be a lie.
- `@safe` callback pilot (8 functions converted as proof-of-pattern):
  `jsProcessGetuid/getgid/geteuid/getegid`, `jsBufferByteLength`,
  `consoleLog/consoleWarn/consoleError`, `jsSetTimeout/jsSetInterval/
  jsClearTimer`, `jsQueueMicrotask`. About 400 callbacks remain
  `@trusted`; most can now drop to `@safe` in follow-up commits.
- npm.d: `resolveVersion` / `findBestMatch` (both overloads) /
  `getTarballUrl` / `randomHex` dropped to `@safe`. The remaining
  11 `@trusted` functions do real IO / `spawnShell` / HTTP fetch and
  legitimately need the annotation as security flags.
- "No redundancies" cleanup: 340 occurrences of
  `assert(ctx !is null, "Null ctx in <name>");` followed by
  `auto state = ctxState(ctx);` removed. `ctxState` already asserts
  on null; combined with D's automatic function-name in assertion
  stack traces the descriptive prefix added no actionable information.
  Spread across 33 files (fs.d 54, crypto.d 47, buffer.d 45,
  process_api.d 24, deno_compat.d 23, fs_promises.d 19, ...).

**Pass 2 — ctxState consolidation + DIP1038 expansion + move semantics**

- `dun.runtime.globals.ctxState(void* ctx)`: new
  `@trusted nothrow @nogc` helper for the `cast(DunState*) ctx` pattern
  that opened every NativeCallback (428 sites across 36 files). The
  cast is the only `@system` operation in those callback prologues;
  centralizing it means the audit grep surface for "where does ctx
  get cast" is one place instead of 428. Mechanically replaced
  via a single `sed -i` pass + import-list update. Build clean,
  sweep at baseline.
- DIP1038 `@mustuse` on `FetchResult`: every caller of `doFetch()`
  consumes either `status` (for redirect chains) or `body_` (for the
  JS-side `Response` wrapper); silently dropping the struct would
  swallow an HTTP response. Build confirms no existing caller drops.
- Move semantics — `@disable this(this)` on `StackFallback!N`: copying
  it would alias the stack region across frames + the GC heap pointer,
  defeating the type's purpose. Pass by `ref` instead. `BumpRegion`
  inherits `@disable this(this)` from its `Region!Mallocator` alias
  already.
- `.gitignore` extended to `/dun-asan-*`, `/dun-tsan-*`, `/dun-pgo-*`
  so audit-builds don't show up as untracked.

**Sanitizer + debug verification**

- ASan integration sweep: 153/158 (5 pre-existing npm-network FAILs).
- TSan integration sweep: 153/158, zero data race warnings.
- gdb reproducer covering Buffer / crypto / fs.existsSync canonicalization:
  no SIGSEGV, no abort, heap stable. Verifies the `ctxState` helper
  symbol (`_D3dun7runtime7globals8ctxStateFNbNiNePvZPSQBpQBoQBj8DunState`)
  is reachable in the binary symbol table.
- PGO chain: `release-pgo-gen` (instrumented, 48 `__llvm_profile_`
  symbols) → 2 benchmark runs → `ldc-profdata merge` →
  `release-pgo` (optimized). All stages link clean.

**Still deferred — would need its own focused PR**

| Track | Module | Pattern | Why deferred |
|-------|--------|---------|--------------|
| `@safe` callback rollout | All builtins (~400 callbacks) | The interface annotation in Pass 3 unblocks this. Each callback drops to `@safe` if its body only calls IJSEngine methods + ctxState + safe Phobos. ~10 already piloted | Mechanical but huge diff; would obscure unrelated PRs in `git blame`. Best done in small per-file batches |
| `@trusted` IO reduction | `dun.modules.npm` (11 remaining) | Functions that touch `spawnShell`, `doFetch`, `readText`, `writefln` — keeping `@trusted` annotated as security flags | Real IO surface; keep `@trusted` as the audit signal |
| DIP1038 `@mustuse` on funcs | `StackFallback.allocate` and friends | D currently reserves `@mustuse on functions for future use`; only struct types accept it (compile error: `@mustuse on functions is reserved for future use`) | Compiler limitation; revisit when LDC/DMD lifts it |
| DIP1000 `return scope` | `JSVal` constructor (engine-context lifetime), additional `Buffer` slice getters | Compiler-enforced lifetime tracking | Current `JSVal` ctor stores a raw `JSContext*` field — `scope` on a ctor parameter doesn't track lifetime through struct fields. Practical answer is `@disable this(this)` + doc comment, which is what the wrapper already does. `getTypedArrayBytes` + `extractBytes` are already annotated `return scope` |
| `@live` (DIP1021) | Evaluated but not adopted | DMD/LDC support exists (`@live` attribute), but the feature has been in beta for years and isn't production-stable. Would enforce single-owner semantics on `JSHandle`/`JSVal` at compile time, with the same pattern as Rust borrow checking | Maturity risk. Re-evaluate when DMD/LDC marks it stable |
| RAII expansion | `UdpSocketState` (dgram.d), `DnsResolver` state, other fd-holders | Currently managed via fixed-size pool arrays (`gUdpSockets[MAX_UDP_SOCKETS]`) with index-based access, so `@disable this(this)` would break `pool[idx] = X.init` reset semantics | Pool-based lifecycle is intentional — non-copyable annotation would conflict |

The audit notes confirmed: the codebase is broadly disciplined — magic
numbers are mostly named local enums (intentional documentation), most
`@trusted` blocks are at real FFI boundaries (legitimate), `@mustuse`
is wired on `JSResult` + `AsyncResult` + `FetchResult` + `PromiseHandles`
(the four highest-value return types), `@disable this(this)` covers
`StackFallback` + `BumpRegion` + `TlsSocket` + `JSVal`, and DIP1000 is
annotated on every slice-returning engine method.

**Audit verification ledger (across all 3 commits)**

- `dub build -c {quickjs,jsc,v8}`: all clean (debug + release +
  release-pgo-gen + release-pgo + asan + tsan)
- `dub test -c unittest`: 71/71
- Integration sweep: QJS 153/158, V8 153/158, JSC 151/158
  (deltas are pre-existing npm-network FAILs + the documented
  `deno_deploy_compat` heap-load case — identical to baseline)
- ASan sweep: 153/158 baseline, no leaks/UBs
- TSan sweep: 153/158 baseline, zero data race warnings
- gdb crash-check on `/tmp/repro_audit.js`: no SIGSEGV, no abort,
  heap stable. Verifies the `ctxState` helper symbol is reachable
- PGO chain: 48 `__llvm_profile_` symbols at gen stage, profdata
  merge clean, optimized build links clean

## Build & test recipe (canonical)

```sh
# Full bootstrap (run once after a fresh clone)
ldc2 -run build.d --backend=quickjs
ldc2 -run build.d --backend=jsc
ldc2 -run build.d --backend=v8

# Release binaries
for B in quickjs jsc v8; do
  dub build -c $B -b release
  cp build/dun ./dun-rel-${B/quickjs/qjs}
  [ -f build/icudtl.dat ] && cp build/icudtl.dat ./icudtl.dat
  strip ./dun-rel-${B/quickjs/qjs}
done

# Integration sweep
dub test -c unittest                                # 71/71
bash tests/integration/run.sh                      # QJS  156/156
BACKEND=jsc DUN=./dun-rel-jsc bash tests/integration/run.sh   # JSC  155/155 + 1 SKIP
BACKEND=v8  DUN=./dun-rel-v8  bash tests/integration/run.sh   # V8   156/156
```

The slash-command equivalents are documented in
[`.claude/commands/`](.claude/commands/). `/all-backends release`
does the build chain; `/integration-sweep` runs all three sweeps
with the known-flake retry logic; `/bench-compare` runs
feature/framework/npm-compat against Bun + Node + Deno.

## Open questions for the next maintainer

1. **CVE intake cadence.** Right now CVE review is reactive
   (when a session asks for it). Worth scheduling a quarterly
   sweep of `denoland/deno/security/advisories` +
   `quickjs-ng/quickjs/security` + Node release notes?
2. **N-API stability gate.** N-API surface is 91 functions
   today (sharp + similar real addons work). Adding a new
   function is low-friction, but there's no compatibility
   matrix saying "these 30 addons pass on the version
   tagged for release."
3. **Bun parity drift.** v0.6.0 web-API audit was 38/38;
   Bun 1.3 keeps adding APIs (v7 round added 8 functions —
   `bun_v7_additions` fixture). Worth a regular Bun-surface
   diff?
4. **LDC version pin.** Currently 1.42.0. LDC ships every
   2-3 months. The `--mcpu=native` / `features ''` ldc#4919
   issue we documented in `.claude/commands/build.md`
   suggests we should run the bench-compare across LDC
   versions before bumping (e.g. 1.43 / 1.44 will use a
   newer LLVM with different scheduling).

## Where to look for things

| Need | Path |
|------|------|
| The IJSEngine interface (everything depends on it) | `source/dun/engine/iface.d` |
| Permission model + CVE-class fixes | `source/dun/security/permissions.d` |
| Built-in modules (fs, http, crypto, ...) | `source/dun/builtins/*.d` |
| LDC-only hot-path primitives (SIMD, llvm_*) | `source/dun/platform/simd.d` |
| Cross-module named constants | `source/dun/declarations.d` |
| Build orchestrator (vendor deps, ImportC, V8 monolith download) | `build.d` |
| CI pipeline | `.github/workflows/ci.yml`, `release.yml` |
| Dockerfiles (single + multi-backend) | `Dockerfile`, `Dockerfile.multibackend` |
| Slash-command skill prompts (Claude Code) | `.claude/commands/*.md` |
| Phase-by-phase history | `CHANGELOG.md` |
