# Migrating from Node.js

Most Node.js scripts run unchanged on DunJS. This guide covers what
to expect, what to change, and what won't work.

## tl;dr

```sh
# Replace `node` with `dun run` (and add permission flags)
node script.js          → dun run script.js
node -e "1+1"           → dun eval "1+1"
node --inspect script   → dun-v8 run --inspect script.js

# npm + package management
npm install pkg         → dun install pkg
npm test                → dun test
```

For most production code, the change is:

```diff
- node server.js
+ dun run --allow-net --allow-read --allow-env server.js
```

## What works without changes

If your code uses:

- `require("fs")`, `require("path")`, `require("crypto")`,
  `require("http")`, `require("net")`, etc. — all standard Node
  built-ins
- ES modules with `import` / `export` / dynamic `import()`
- `Buffer.*`
- `process.argv`, `process.env`, `process.exit`
- `EventEmitter`, streams, async iterators
- `worker_threads`, `cluster`
- TypeScript (`.ts` files run directly — see
  [TypeScript Support](./typescript.md))
- npm packages installed via `npm install` (DunJS reads
  `node_modules/` and `package.json`)
- N-API native addons (sharp, bcrypt, etc. — see
  [N-API addons](./napi.md))

…then DunJS runs it. Drop in `dun run` + the right `--allow-*` flags.

## What you need to add

### Permission flags

The big difference vs Node is **default-deny**. Your code needs the
right flags or you'll see `Requires --allow-X` errors. Common
combinations:

```sh
# Read-only CLI tool
dun run --allow-read script.js

# Web server
dun run --allow-net --allow-read --allow-env server.js

# Build tool
dun run --allow-read --allow-write=./dist --allow-run=tsc build.js

# Everything (easy mode for migration)
dun run -A script.js
```

Start with `-A` to verify the script works, then tighten down.

See [Permissions](./permissions.md) for details.

## What's different

### `process.version`

Node returns `"v22.x.x"`; DunJS returns `"v22.0.0"` (we report
22.0.0 for compatibility with version-sniffing addons). To get
the real DunJS version:

```js
process.versions.dun     // "1.1.11"
process.versions.node    // "22.0.0" (compat-reported)
process.versions.v8      // "15.0.91" or the JSC/QJS version
```

### `process.binding(...)`

This is a private Node API for accessing C++ bindings. Not
implemented. If a package uses it, file an issue — we can usually
provide the surface via a public API.

### `fs.realpath` quirks

Both Node and DunJS use the OS `realpath(3)`. Behavior should
match. If you see differences with symlinked paths, file an issue.

### Worker thread `MessagePort.postMessage(value, transferList)`

DunJS supports `ArrayBuffer` / `SharedArrayBuffer` in the transfer
list. Other transferables (`MessagePort`, `ReadableStream`,
`OffscreenCanvas`) work but may have edge cases — file an issue
with a reproducer.

### `--inspect` (Chrome DevTools protocol)

Only on `dun-v8` (uses V8's built-in inspector). On QuickJS / JSC,
use `console.log` + the REPL.

```sh
dun-v8 run --inspect server.js
```

### Crypto random output

Both Node and DunJS read `/dev/urandom` (or `getrandom(2)` on
Linux). Behavior is identical, but DunJS's pool is shared across
the process for performance — 64 UUIDs per syscall.

## What doesn't work yet

### Some `--experimental-*` features

Node's experimental flags are Node-specific. DunJS doesn't recognize
them; they're silently ignored. Use stable APIs.

### `node:test` reporter format

DunJS's `dun test` has its own reporter. The TAP variant
(node 22+) is partially supported. For CI, use:

```sh
dun test --reporter=tap > tap.out
```

### `vm.compileFunction({ cachedData: ... })`

Works, but the cache binary format is V8-specific. JSC / QJS will
re-compile every time.

## What absolutely won't work

### Native `.node` addons that bypass N-API

If a `.node` file calls into V8 / libuv internals directly (not
through N-API), it can't work on any non-Node runtime. Things that
DON'T work:

- Addons that `dlsym("v8::Isolate::GetCurrent")` directly
- Addons that wrap `uv_loop_t` access

Things that DO work (via N-API):

- sharp (image processing)
- bcrypt (password hashing)
- bufferutil (WebSocket extension)
- node-sass / sass-embedded
- @parcel/source-map

DunJS ships 91 N-API functions plus real `napi_wrap` /
`napi_create_external`. If an addon uses pure N-API, it works.

### Internal node module imports

```js
const { customInspectSymbol } = require("util");   // works
const _internalUtil = require("internal/util");    // ✗ won't work
```

DunJS exposes only the public Node surface — internal modules
(`internal/*`) are intentionally not exposed.

## Common pitfalls

### "Cannot find module"

Make sure you've run `dun install` (or `npm install`) and that
`node_modules/` is in the cwd or a parent dir.

### "Permission denied"

You forgot a `--allow-*` flag. Check the error message — it tells
you which permission is missing and for which resource.

### "EPERM: operation not permitted"

A `--deny-*` flag is winning over an `--allow-*`. Check both.

### `process.platform === "darwin"` returns `"linux"`

You're running on Linux. DunJS reports the actual OS, not the
emulated one (no Rosetta-style transparent platform translation).

## Migration checklist

1. **Pick a backend** — `dun-v8` is the closest to Node behavior.
   See [Backends](./backends.md).
2. **Test with `-A`** — `dun-v8 run -A your-app.js`. If it crashes,
   file an issue.
3. **Tighten permissions** — drop `-A` and add specific `--allow-*`
   flags one at a time.
4. **Test npm packages** — `dun install` your `dependencies`. If
   any package fails to load, file an issue.
5. **Replace `node` in scripts** — update `package.json` `scripts`
   to use `dun run` instead of `node`.
6. **Run your test suite** — `dun test` runs `*.test.{js,ts}` and
   files using `node:test` API.

## Comparison

| Feature | Node 22 | DunJS |
|---------|---------|-------|
| Default permissions | allow-all | deny-all |
| Native addons | full | N-API only |
| TypeScript | requires loader | native |
| Built-in test runner | yes | yes |
| Built-in bundler | no | yes |
| Web APIs (fetch, etc.) | yes | yes |
| Worker threads | yes | yes |
| Cluster | yes | yes |
| HTTP/2 | yes | yes |
| HTTP/3 | no | yes |
| SQLite | yes (built-in) | yes (`dun:sqlite`) |
| WASI | preview1 | preview1 |

## See also

- [Permissions](./permissions.md) — full security model
- [N-API addons](./napi.md) — native addon details
- [TypeScript Support](./typescript.md) — `.ts` files directly
- [Node compat](./node-compat.md) — module-by-module status
