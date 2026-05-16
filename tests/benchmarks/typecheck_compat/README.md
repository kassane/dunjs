# `dun run --typecheck` cross-runtime comparison

Seven TypeScript files probing distinct type-error categories, run
against the type-checkers (`tsc`, `deno check`, `dun --typecheck`)
and the runners (`bun`, `node`, `dun` without `--typecheck`).

## Result table

```
file                            tsc       deno-check  dun-tc    bun         node        dun-qjs   dun-jsc   dun-v8
----------------------------------------------------------------------------------------------------------------------
01_primitive_mismatch.ts        CAUGHT    CAUGHT      CAUGHT    RAN         RAN         RAN       RAN       RAN
02_function_argcount.ts         CAUGHT    CAUGHT      CAUGHT    RAN         RAN         RAN       RAN       RAN
03_missing_property.ts          CAUGHT    CAUGHT      CAUGHT    RAN         RAN         RAN       RAN       RAN
04_discriminated_union.ts       PASS      PASS        PASS      RAN         RAN         RAN       RAN       RAN
05_generic_constraint.ts        CAUGHT    CAUGHT      CAUGHT    RAN         RAN         RAN       RAN       RAN
06_null_unchecked.ts            CAUGHT    CAUGHT      CAUGHT    RUNTIME-ERR RUNTIME-ERR RUNTIME-ERR RUNTIME-ERR RUNTIME-ERR
07_clean.ts                     PASS      PASS        PASS      RAN         RAN         RAN       RAN       RAN
```

Legend:
- **CAUGHT** — type-checker refused to compile/run because of type errors
- **PASS** — type-checker accepted the file (no errors)
- **RAN** — runtime stripped types and executed the JS
- **RUNTIME-ERR** — runtime crashed at execution (the type bug surfaced as a runtime error)
- **SKIP** — runtime not on PATH

## Reading the grid

| Column | What it tells you |
|--------|-------------------|
| `tsc` | The gold standard. Catches every static type error. |
| `deno-check` | Deno's built-in type-checker (`deno check`), uses tsc internally. |
| `dun-tc` | `dun run --typecheck`, our new feature. Auto-installs `typescript` via `dun install` on first use. |
| `bun` / `node` / `dun` (no flag) | Runners. Strip types and execute; type bugs become runtime errors *if* they crash, or silent if they don't. |

The bottom line: **`dun --typecheck` matches tsc on all seven probes.**
It catches every static type error tsc catches, accepts the cases tsc
accepts, and refuses to execute the JS when type-checking fails.
No file mismatched.

## How `--typecheck` works

1. Walk upward from the script's directory looking for
   `node_modules/typescript/lib/typescript.js`.
2. If absent, call `dun install typescript` (DunJS's own resolver,
   not npm). One-time cost; cached forever in the project's
   `node_modules/`.
3. Spin up a short-lived JS engine, `require('typescript')`, build a
   compiler host that proxies tsc's fs reads through DunJS's
   `node:fs`, call `ts.createProgram() + getPreEmitDiagnostics()`,
   pick up the user's `tsconfig.json` from cwd if present.
4. If there are diagnostics with `category === Error`, print them
   with `ts.formatDiagnosticsWithColorAndContext()` (same colored
   output as tsc itself) and exit 1.
5. Otherwise, `ts.transpileModule()` the source and feed the emitted
   JS to the existing runner pipeline.

## Running locally

```sh
bash tests/benchmarks/typecheck_compat/compare.sh
```

Requires `tsc` (`npm i -g typescript`), `deno`, `bun`, `node` on
PATH, plus the three DunJS release binaries (`./dun-rel-{qjs,jsc,v8}`).
Missing runtimes get `SKIP` in their column.

## Adding cases

Drop a new `NN_*.ts` in this directory. Convention:
- Files ending `_clean.ts` should type-check cleanly.
- Everything else should be a single deliberate type error.
- The runner doesn't read the file content — it just runs each
  runtime and checks exit code.
