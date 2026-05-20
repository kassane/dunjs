# Quick Start

After [installing DunJS](./installation.md), you have a `dun` binary
that runs JavaScript and TypeScript directly.

## Run a script

```sh
echo 'console.log("hello dun")' > hello.js
dun run hello.js
# hello dun
```

TypeScript works without configuration — type annotations are stripped
on the fly:

```sh
echo 'const x: number = 42; console.log(x);' > hello.ts
dun run hello.ts
# 42
```

## Interactive REPL

```sh
dun repl
> const greet = (name) => `Hello, ${name}`
undefined
> greet("DunJS")
'Hello, DunJS'
> .exit
```

REPL history persists in `~/.dun_repl_history` (configurable via
`DUN_REPL_HISTORY`).

## Inline eval

```sh
dun eval "Math.sqrt(2)"
# 1.4142135623730951

dun eval "for (let i = 0; i < 3; i++) console.log(i)"
# 0
# 1
# 2
```

## Permissions

By default, DunJS denies all I/O. Grant access explicitly:

```sh
# Read access
dun run --allow-read script.js
dun run --allow-read=./data,/tmp script.js   # scoped

# Network access
dun run --allow-net script.js
dun run --allow-net=api.example.com:443 script.js

# Everything (use with caution)
dun run --allow-all script.js
dun run -A script.js                          # short form
```

Without the right `--allow-*` flag, you'll see:
```
Uncaught TypeError: Requires --allow-read for /etc/hostname
```

See [Permissions](./permissions.md) for the full model.

## Run tests

DunJS includes a built-in test runner — no jest/vitest needed:

```js
// math.test.js
import { test } from "node:test";
import assert from "node:assert";

test("addition works", () => {
  assert.strictEqual(1 + 1, 2);
});

test("async test", async () => {
  const x = await Promise.resolve(42);
  assert.strictEqual(x, 42);
});
```

```sh
dun test                          # runs all *.test.{js,ts}
dun test math.test.js             # specific file
dun test --filter=addition        # filter by name
dun test --concurrent             # parallel (Bun parity)
```

The Deno-style `Deno.test(name, fn)` API works too.

## Run benchmarks

```js
// hash.bench.js
import { bench } from "node:test";
import crypto from "node:crypto";

bench("sha256", () => {
  crypto.createHash("sha256").update("hello").digest("hex");
});
```

```sh
dun bench
# sha256                      ~3.2M ops/sec  ±0.4%
```

Iterations auto-calibrate for ~1 second per bench.

## Install npm packages

```sh
dun install express                         # install + add to package.json
dun install --audit=block lodash            # refuse if CRITICAL CVE
dun install --audit=warn @types/node        # warn but continue (default)
```

Packages land in `node_modules/` and resolve via standard Node.js
resolution. The audit gate queries [OSV](https://osv.dev) for known
CVEs before download.

## Bundle for distribution

```sh
# Bundle to a single .js file with source maps
dun bundle entry.ts --output=app.js --sourcemap

# Self-contained executable (no `dun` needed at runtime)
dun bundle entry.ts --compile=./myapp
./myapp
# ...runs your script standalone
```

## Format + lint

```sh
dun fmt                                     # format all *.{js,ts} in cwd
dun lint src/                               # lint a directory
dun lint --fix script.js                    # auto-fix eqeqeq + no-debugger
```

## Pick a backend at runtime

Each backend ships as a separate binary:

```sh
./dun-quickjs run script.js                 # interpreter (fastest startup)
./dun-jsc     run script.js                 # JIT (best throughput)
./dun-v8      run script.js                 # JIT (best Node parity)
```

For programmatic selection at build time, see [Backends](./backends.md).

## What's next?

- [Built-in modules](./builtins/index.md) — `fs`, `path`, `crypto`,
  `http`, `sqlite`, ...
- [Node.js compat](./node-compat.md) — drop existing Node code in
- [TypeScript support](./typescript.md) — decorators, JSX, transpile cache
- [Performance tuning](./performance.md) — GC, hot paths, Workers
