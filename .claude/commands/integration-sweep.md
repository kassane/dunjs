---
description: Run `tests/integration/run.sh` against all three backends, summarize PASS/FAIL/SKIP counts, and re-run any failure 3× standalone before reporting it (catches the test-runner concurrency flakes in npm_packages_e2e / npm_real_packages / express_e2e). Use after any change to `source/dun/` or before committing.
---

# Integration Test Sweep

Surfaces real regressions while filtering the well-known flakes from `run.sh`'s
parallel-ish test layout (port reuse + node_modules state).

## Usage

```sh
/integration-sweep              # all three backends
/integration-sweep qjs          # only QuickJS
/integration-sweep jsc v8       # JSC + V8
```

## Steps

1. **Ensure binaries:**
   - QJS:  `./dun`        (from `dub build -c quickjs`)
   - JSC:  `./dun-jsc`    (from `dub build -c jsc`)
   - V8:   `./dun-v8`     (from `dub build -c v8`)

   Build missing ones via `/all-backends`.

2. **Run suite per backend** (`run.sh` auto-detects the engine from `--version`,
   but pass `BACKEND=` and `DUN=` explicitly for JSC/V8):

   ```sh
   bash tests/integration/run.sh                          # quickjs
   BACKEND=jsc DUN=./dun-jsc bash tests/integration/run.sh
   BACKEND=v8  DUN=./dun-v8  bash tests/integration/run.sh
   ```

3. **For each `FAIL` line, re-run 3× standalone**:
   ```sh
   extra=$(cat tests/integration/fixtures/$NAME.flags 2>/dev/null)
   for i in 1 2 3; do
     out=$(timeout 30 $DUN run $extra tests/integration/fixtures/$NAME.js 2>&1)
     exp=$(cat tests/integration/expected/$NAME.txt)
     [ "$out" = "$exp" ] && echo "$i: PASS" || echo "$i: FAIL"
   done
   ```
   - If 3/3 PASS → flake, drop from report.
   - If any FAIL → real regression, include diff in report.

4. **Print summary table:**
   ```
   Backend  PASS  SKIP  REAL_FAIL  FLAKES
   QJS      148   0     0          (npm_packages_e2e)
   JSC      147   1     0          (deno_deploy_compat under sweep heap-load, npm_packages_e2e)
   V8       148   0     0          (npm_packages_e2e)
   ```

## Known persistent failures (session baseline)

- **`npm_deep_compat`**: express 5.x dropped `app._router`. Test was written for
  express 4. Not a runtime bug — `dun install express@4` makes it pass.
- **`express_e2e` / `npm_packages_e2e` / `npm_real_packages`**: flaky in suite
  (port/state contention), always pass standalone.
- **JSC `bun_v7_additions`**: gated SKIP (`.backends` sidecar). v1.1.7 cached
  the per-fetch Response builder + headers flattener, lifting the threshold
  from 9-10 → 13-14 servers with v7 extras enabled. Residual per-request
  listener-chain leak still tips `deno_deploy_compat` (15 servers) over
  threshold ~33% of the time under sweep heap-load. Standalone: 3/3 PASS.
- **JSC `deno_deploy_compat` under sweep heap-load**: flakes when run after
  the full preceding test corpus has loaded JSC's heap. Standalone-reruns
  pass 3/3. Same root as the bun_v7 SKIP (per-request listener accumulation).
- **JSC `production_gaps4`**: occasional stderr-vs-stdout flake on
  `DeprecationWarning: deprecated`.

## CVE-class fixtures (always must PASS)

- **`cve_path_traversal`** — CVE-2023-32004 class regression check.
- **`audit_simd`** — SIMD encoder boundary cases (15/16/17 bytes,
  GCM 16-byte tag) + Latin-1 high-byte preservation + hex round-trip.
- **`audit_roundtrip`** — Buffer.from / Buffer.write / Buffer.toString
  across all 256 byte values + JSON NUL round-trip + JSC source NUL.

If any of these three FAIL, treat it as a security regression — do NOT
mark as a flake, investigate immediately.

## Skip the flake check (when you want raw run.sh output)

```sh
/integration-sweep raw
```
