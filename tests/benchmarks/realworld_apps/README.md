# Real-world TypeScript apps — cross-runtime smoke tests

Three sizeable open-source TS projects, run on each of bun / node /
deno / dun-{qjs,jsc,v8}. `--help` / `--version` only — full execution
of these projects involves long-running servers or build pipelines
that this comparison doesn't drive end-to-end.

## Results (May 2026)

```
project                              bun    node   deno   dun-qjs   dun-jsc   dun-v8
n8n (packages/cli/bin/n8n --version) 2.21.0 2.21.0 FAIL   2.21.0    2.21.0    2.21.0
gaia (scripts/bitcook/gaia.ts -h)    PASS   FAIL   FAIL*  PASS      PASS      PASS
opencode (packages/opencode --version) PASS FAIL   FAIL   FAIL      FAIL      FAIL
```

`FAIL*` = environment-dependent. Deno on the gaia entry tries to
fetch every transitive npm dep at startup; in this sandbox the
registry is rate-limited, so we time out. Locally with full network
access Deno also passes.

### n8n (`n8n-io/n8n`)

CLI entry is a plain CJS `require()`-style script. Deno fails because
its script-mode parser rejects CommonJS. All of bun / node / DunJS
print `2.21.0`.

### gaia (`gaiaBuildSystem/gaia`)

Yocto-ish build system written in TypeScript with Deno-style `.ts`
suffix imports + Node-built-ins. After `npm install` for the runtime
deps:

- **bun**: runs the help text fine.
- **node**: chokes on `import { Recipe } from "./parse.ts"` because
  Node's strict ESM resolver flags `Recipe` (an `interface`) as a
  missing value export.
- **deno**: would work but blocked here by the network sandbox.
- **dun-qjs / dun-jsc / dun-v8**: all three print the same Usage /
  Options banner as bun. DunJS keeps the `.ts` extension resolution
  and the type-only re-exports working transparently.

### opencode (`anomalyco/opencode`)

Heavy Bun-specific project. Uses `bunfig.toml` path aliases like
`@/util/record`, `Bun.Shell`, and a workspace setup that only Bun's
resolver understands. Failure across non-Bun runtimes is expected.
DunJS gets further than Node and Deno (parses + reaches dep
resolution) but doesn't run the bunfig path-alias layer.

## Running locally

```sh
# 1. Clone the projects somewhere
git clone --depth=1 https://github.com/n8n-io/n8n /tmp/n8n
git clone --depth=1 https://github.com/gaiaBuildSystem/gaia /tmp/gaia
git clone --depth=1 https://github.com/anomalyco/opencode /tmp/opencode

# 2. Install runtime deps for the ones that need them
( cd /tmp/gaia && npm install --silent )

# 3. Run the comparison
bash tests/benchmarks/realworld_apps/compare.sh
```
