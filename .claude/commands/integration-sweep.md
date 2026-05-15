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
   QJS      107   1     0          (npm_packages_e2e)
   JSC      103   3     0          (npm_packages_e2e, npm_real_packages, production_gaps4)
   V8       104   2     1          npm_deep_compat
   ```

## Known persistent failures (session baseline)

- **`npm_deep_compat`**: express 5.x dropped `app._router`. Test was written for
  express 4. Not a runtime bug — `dun install express@4` makes it pass.
- **`express_e2e` / `npm_packages_e2e` / `npm_real_packages`**: flaky in suite
  (port/state contention), always pass standalone.
- **JSC `production_gaps4`**: occasional stderr-vs-stdout flake on
  `DeprecationWarning: deprecated`.

## Skip the flake check (when you want raw run.sh output)

```sh
/integration-sweep raw
```
