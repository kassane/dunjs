# DunJS — Handoff Notes

Living document. Points the next maintainer at the moving pieces
and the gotchas that bite you on day one. Read alongside
[`CLAUDE.md`](CLAUDE.md), [`SECURITY.md`](SECURITY.md), and
[`TESTING.md`](TESTING.md).

## Current state (v1.1.25)

- Integration sweep: **155/155 + 1 new fixture** on QJS / V8
  (156/156), **154/154 + 1 SKIP + 1 new fixture** on JSC
  (155/155 + 1 SKIP). New fixture is `cve_priv_files.js` (8/8
  on every backend) for the v1.1.25 sandbox-bypass fix below.
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
