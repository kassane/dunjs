# Bun Compatibility

DunJS provides 25+ `Bun.*` APIs for drop-in compatibility with Bun
scripts. The full surface is validated via
[tests/benchmarks/ts_compat/](../tests/benchmarks/ts_compat/) and
[deno_deploy_compat.js](../tests/integration/fixtures/deno_deploy_compat.js).

## Quick example

```js
// works on both Bun and DunJS
const srv = Bun.serve({
  port: 3000,
  fetch(req) {
    return new Response("hello", { headers: { "x-runtime": "dun" } });
  }
});

console.log(`listening on http://localhost:${srv.port}/`);
```

```sh
dun run --allow-net script.js
```

## Implemented APIs

### Server

| API | Status |
|-----|--------|
| `Bun.serve(opts)` | full HTTP server + WebSocket upgrade |
| `srv.port` / `srv.hostname` | full |
| `srv.stop()` | graceful close |
| `srv.reload(opts)` | replace fetch handler |
| `opts.fetch(req)` | request handler |
| `opts.error(err)` | error handler |
| `opts.websocket` | WebSocket lifecycle (open/message/close) |

### File / Blob

| API | Status |
|-----|--------|
| `Bun.file(path)` | returns BunFile with `.text()`, `.json()`, `.arrayBuffer()`, `.bytes()`, `.exists()`, `.size`, `.type` |
| `Bun.write(dest, data)` | full — accepts path, Buffer, string, ArrayBuffer, Blob, Response |

### Build

| API | Status |
|-----|--------|
| `Bun.build({ entrypoints, outdir, ... })` | full via `dun bundle` internally |
| Source maps | external + inline |
| Code splitting | basic (single-bundle output) |
| Minification | deferred (currently no-op) |
| `naming` | full |

### Hashing

| API | Status |
|-----|--------|
| `Bun.hash(input)` | wyhash default |
| `Bun.hash.wyhash` | wyhash |
| `Bun.hash.adler32` | adler32 |
| `Bun.hash.crc32` | crc32 |
| `Bun.hash.cityHash32` / `cityHash64` | city hash variants |
| `Bun.hash.murmur32v3` / `murmur64v2` | murmur variants |
| `Bun.MD5`, `Bun.SHA1`, `Bun.SHA256`, `Bun.SHA512`, etc. | full |
| `Bun.MD4` | NOT supported (no real upstream — Bun.MD4 doesn't exist) |
| `Bun.password.hash(s, alg)` / `verify(s, hash, alg)` | bcrypt (argon2 deferred) |

### Misc utilities

| API | Status |
|-----|--------|
| `Bun.version` | `"1.3.14"` |
| `Bun.revision` | git-style revision string |
| `Bun.main` | path to main entry |
| `Bun.env` | alias for `process.env` |
| `Bun.argv` | `["dun", ...]` (alias for process.argv) |
| `Bun.gc(force?)` | trigger GC |
| `Bun.sleep(ms)` | promise-based sleep |
| `Bun.sleepSync(ms)` | synchronous sleep |
| `Bun.semver.satisfies(v, range)` | full semver |
| `Bun.semver.order(a, b)` | full semver compare |
| `Bun.glob(pattern, opts)` | full glob iterator |
| `Bun.color(input, format)` | color parsing (hex / rgb / hsl) |
| `Bun.escapeHTML(s)` | HTML entity escape |
| `Bun.indexOfLine(buf, lineStart)` | full |
| `Bun.deepEquals(a, b)` | deep equality |
| `Bun.fileURLToPath(url)` | full |
| `Bun.pathToFileURL(path)` | full |
| `Bun.openInEditor(path)` | full |
| `Bun.peek(promise)` | sync peek of resolved/rejected |
| `Bun.inspect(value, opts)` | util.inspect-style formatting |

### v7 additions

| API | Status |
|-----|--------|
| `Bun.deepMatch(a, b)` | full (b is subset of a) |
| `Bun.concatArrayBuffers(parts, max, asUint8)` | full |
| `Bun.arrayBufferToString(buf, enc)` | full |
| `Bun.randomUUIDv7(enc, ts)` | full |
| `Bun.nanoseconds()` | based on performance.now |
| `Bun.gcAggressionLevel(lvl)` | counter (no engine effect) |
| `Bun.shrink()` | calls `globalThis.gc()` if available |
| `Bun.generateHeapSnapshot(fmt)` | stub — returns empty snapshot |

### UDP socket

```js
Bun.udpSocket({
  port: 0,
  socket: {
    data(socket, data, port, addr) { /* ... */ }
  }
});
```

Full UDP support with v4 + v6.

## Quirks worth knowing

### `Bun.serve` vs `http.createServer`

`Bun.serve` accepts a `fetch(req)` handler that returns a
`Response`. `http.createServer` accepts a `(req, res)` callback
where you `res.end(data)`. Both work on DunJS — pick the style
you prefer.

`Bun.serve` is implemented as a thin shim over `http.createServer`
in DunJS. Performance is comparable.

### `Bun.file(path)` lazy loading

`Bun.file(path)` does NOT read the file. It returns an object
representing the file. Reading happens when you call `.text()`,
`.json()`, etc.:

```js
const f = Bun.file("/tmp/big.json");
console.log(f.size);              // stat — no read
const data = await f.json();      // actually reads
```

### Sync vs async

Many Bun APIs are sync where Node is async:

```js
Bun.sleepSync(100);                          // blocks
await Bun.sleep(100);                        // doesn't
```

DunJS implements both. Use `sleepSync` sparingly — it blocks the
event loop.

### `Bun.build` is `dun bundle`

`Bun.build({ entrypoints, ... })` internally calls `dun bundle`
under the hood. The Bun config shape is honored; output is
identical for basic cases. For DunJS-native bundling, prefer
`dun bundle <entry>` from the CLI.

### `Bun.hash` default

`Bun.hash(input)` uses **wyhash** by default. Match Bun. If you
need a different algorithm, use the named version
(`Bun.hash.crc32(input)` etc.).

## What's NOT supported

- **`Bun.spawn` with extensive options** — basic spawn works, but
  some options (`ipc: "node"`, custom `stdio` array elements like
  `Bun.file()`) are partially implemented
- **`Bun.dns` programmatic API** — use `dns` from node:dns
- **`Bun.plugin(plugin)`** for bundler — deferred
- **`Bun.SQLite`** — use `dun:sqlite` (same API surface)
- **`Bun.MD4`** — never existed in Bun upstream (verified — the
  parity test's miss isn't a real API)

## See also

- [Permissions](./permissions.md) — same model as Deno (NOT Bun's
  allow-all default)
- [Node compat](./node-compat.md) — Node APIs (DunJS supports
  both Node + Bun + Deno)
- [Deno compat](./deno-compat.md) — `Deno.*` APIs
- [tests/benchmarks/ts_compat/](../tests/benchmarks/ts_compat/) —
  cross-runtime parity tests
