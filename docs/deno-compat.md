# Deno Compatibility

DunJS provides 30+ `Deno.*` APIs for drop-in compatibility with
Deno scripts. The full surface passes 12/12 checks on
`tests/integration/fixtures/deno_deploy_compat.js`
([Deno 2.7 parity](../tests/integration/fixtures/deno_deploy_compat.js)).

## Quick example

```js
// works on both Deno and DunJS
const srv = Deno.serve({ port: 0 }, (req) =>
  new Response("hello", { headers: { "x-runtime": "dun" } }));

console.log(`listening on http://${srv.addr.hostname}:${srv.addr.port}/`);
await srv.finished;
```

```sh
dun run --allow-net script.js
```

## Implemented APIs

### Server

| API | Status |
|-----|--------|
| `Deno.serve(opts, handler)` | full |
| `Deno.serve(handler)` | shorthand |
| `Deno.serve(opts)` (handler in opts) | full |
| `srv.addr` | `{ hostname, port, transport: "tcp" }` |
| `srv.finished` | resolves on shutdown |
| `srv.shutdown()` | graceful close |
| `srv.ref()` / `srv.unref()` | no-op (event-loop control) |
| `opts.onListen` | full |
| `opts.onError` | full |

### Filesystem

| API | Status |
|-----|--------|
| `Deno.readTextFile(path)` / `readTextFileSync` | full |
| `Deno.writeTextFile(path, data)` / `writeTextFileSync` | full |
| `Deno.readFile(path)` / `readFileSync` | full (returns Uint8Array) |
| `Deno.writeFile(path, data)` / `writeFileSync` | full |
| `Deno.stat(path)` / `lstat(path)` | full |
| `Deno.mkdir(path, opts)` | full |
| `Deno.remove(path, opts)` | full |
| `Deno.rename(from, to)` | full |
| `Deno.copyFile(from, to)` | full |
| `Deno.readDir(path)` | async iterator |
| `Deno.realPath(path)` | full |
| `Deno.cwd()` / `chdir(dir)` | full |
| `Deno.makeTempDir(opts)` / `makeTempFile(opts)` | full |
| `Deno.symlink(target, path)` | full |
| `Deno.readLink(path)` | full |
| `Deno.utime(path, atime, mtime)` | full |
| `Deno.chmod(path, mode)` / `chown(path, uid, gid)` | full (Posix only) |
| `Deno.truncate(path, len)` | full |
| `Deno.create(path)` / `open(path, opts)` | full |
| `Deno.FsFile` | `read`, `write`, `seek`, `stat`, `close`, `readable`, `writable` |

### Network

| API | Status |
|-----|--------|
| `Deno.listen(opts)` (TCP) | full |
| `Deno.connect(opts)` (TCP) | full |
| `Deno.listenTls(opts)` | full |
| `Deno.connectTls(opts)` | full |

### Subprocess

| API | Status |
|-----|--------|
| `Deno.Command(cmd, opts)` | full |
| `.output()` / `.outputSync()` | full |
| `.spawn()` (returns ChildProcess) | full |
| `.status` / `.pid` / `.stdin` / `.stdout` / `.stderr` | full |

### Env

| API | Status |
|-----|--------|
| `Deno.env.get(key)` | full |
| `Deno.env.set(key, value)` | full |
| `Deno.env.delete(key)` | full |
| `Deno.env.has(key)` | full |
| `Deno.env.toObject()` | full |

### Permissions

| API | Status |
|-----|--------|
| `Deno.permissions.query({ name, ...scope })` | full |
| `Deno.permissions.request(...)` | no-op (returns current state — interactive prompts deferred) |
| `Deno.permissions.revoke(...)` | full |
| Names: `read`, `write`, `net`, `env`, `run`, `ffi`, `sys`, `hrtime` | all supported |

### Errors

```js
import { errors } from "deno";
// or globally available as Deno.errors

errors.NotFound
errors.PermissionDenied
errors.ConnectionRefused
errors.ConnectionReset
errors.ConnectionAborted
errors.NotConnected
errors.AddrInUse
errors.AddrNotAvailable
errors.BrokenPipe
errors.AlreadyExists
errors.InvalidData
errors.TimedOut
errors.Interrupted
errors.UnexpectedEof
errors.BadResource
errors.Http
errors.Busy
errors.NotSupported
```

All Deno error classes with `name`/`code`/`message` shape.

### Runtime info

| API | Status |
|-----|--------|
| `Deno.version` | `{ deno: "2.7.0", v8: "...", typescript: "..." }` |
| `Deno.build` | `{ target, arch, os, vendor, env }` |
| `Deno.execPath()` | path to `dun` binary |
| `Deno.pid` | process pid |
| `Deno.ppid` | parent pid |
| `Deno.hostname()` | (requires `--allow-sys=hostname`) |
| `Deno.osRelease()` | (requires `--allow-sys`) |
| `Deno.osUptime()` | uptime in seconds |
| `Deno.memoryUsage()` | `{ rss, heapTotal, heapUsed, external }` |
| `Deno.uid()` / `Deno.gid()` | Posix uid/gid |
| `Deno.loadavg()` | `[1min, 5min, 15min]` |
| `Deno.systemMemoryInfo()` | full memory info |
| `Deno.networkInterfaces()` | full |
| `Deno.consoleSize()` | terminal size |
| `Deno.isatty(fd)` | tty detection |
| `Deno.cron(name, schedule, handler)` | cron job registration |

### KV (minimal in-memory implementation)

```js
const kv = await Deno.openKv();
await kv.set(["users", "alice"], { name: "Alice" });
const { value } = await kv.get(["users", "alice"]);
// { name: "Alice" }
```

The DunJS KV is an in-memory `Map` keyed by canonical key strings.
Real Deno KV is persistent + transactional + has consistency
levels — those features are deferred. For real persistence, use
`dun:sqlite`.

### Test runner

```js
Deno.test("addition works", () => {
  if (1 + 1 !== 2) throw new Error("math broken");
});

Deno.test({
  name: "async test",
  async fn() {
    const x = await Promise.resolve(42);
    if (x !== 42) throw new Error("nope");
  }
});
```

```sh
dun test     # runs Deno.test + node:test files
```

## Quirks worth knowing

### `Deno.serve` shutdown behavior

DunJS's `Deno.serve` returns from `srv.shutdown()` only after the
HTTP server has closed all connections. Same as Deno 2.x.

### `Deno.Command` exit code

`.output()` returns `{ code, stdout, stderr, success, signal }`.
The `signal` is `null` on normal exit, `"SIGTERM"` etc. on signal.

### `Deno.test` filter

Works via CLI:
```sh
dun test --filter="user creation"
```

Not via `Deno.test({ only: true })` (a Deno 1.x feature — Deno 2
removed it; DunJS follows Deno 2).

### `Deno.openKv` persistence

In-memory only, per-process. The 1st arg (path) is ignored. For
persistent KV, use `dun:sqlite`.

## What's NOT supported

- **JSR (jsr.io)** modules — only `npm:` + `https:` + local paths
  for now
- **`Deno.upgradeWebSocket(req)`** — partial; basic WebSocket
  upgrade works, full event semantics being improved
- **`Deno.bench`** — use `dun bench` instead (different API,
  same `node:test` `bench` registration works)
- **Vendor directory** (`--vendor`) — use `npm:` resolution

## See also

- [Permissions](./permissions.md) — same model as Deno
- [Node compat](./node-compat.md) — Node APIs (DunJS supports both)
- [Bun compat](./bun-compat.md) — `Bun.*` APIs
- [tests/integration/fixtures/deno_deploy_compat.js](../tests/integration/fixtures/deno_deploy_compat.js)
  — 12-check parity suite
