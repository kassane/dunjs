# Permissions

DunJS inherits [Deno](https://deno.land)'s default-deny security model.
No script has access to the file system, network, environment, or
child processes unless explicitly granted via CLI flags.

## Quick examples

```sh
# Safe sandbox — no I/O at all
dun run script.js

# Read access scoped to ./data and /tmp
dun run --allow-read=./data,/tmp script.js

# Network only
dun run --allow-net script.js

# Network restricted to specific hosts:ports
dun run --allow-net=api.example.com:443,cdn.example.com:443 script.js

# Everything (escape hatch — use only when needed)
dun run -A script.js
dun run --allow-all script.js

# Deny overrides allow
dun run --allow-read --deny-read=/etc/shadow script.js
```

## The permission flags

| Flag | Resource | Scope grammar |
|------|----------|---------------|
| `--allow-read[=paths]` | File reads | comma-separated paths |
| `--allow-write[=paths]` | File writes | comma-separated paths |
| `--allow-net[=hosts]` | Network | `host[:port]` (port optional means any) |
| `--allow-env[=vars]` | env vars | comma-separated var names |
| `--allow-run[=cmds]` | child processes | comma-separated command names |
| `--allow-ffi[=libs]` | dlopen / FFI | comma-separated lib paths |
| `--allow-sys[=cats]` | system info | `cpus,networkInterfaces,uid,gid,hostname,...` |
| `--allow-hrtime` | high-res timer | no scope (boolean) |
| `--allow-all`, `-A` | everything | no scope |
| `--deny-*` | (any of above) | Overrides matching `--allow-*` |

## Enforcement architecture

Permission checks happen at the **D native layer**, not in JavaScript.
Every built-in module that performs I/O calls
`PermissionRegistry.check()` before executing. JS code cannot bypass.

| Module | Permission | Resource scope |
|--------|------------|----------------|
| `dun:fs` | `read` / `write` | file path |
| `dun:net` | `net` | `host:port` |
| `dun:http`, `dun:https`, `dun:http2`, `dun:http3` | `net` | URL host |
| `process.env` | `env` | variable name |
| `Deno.run`, `child_process.*` | `run` | command name |
| `dun:dns` | `net` | hostname being resolved |
| `dun:crypto` | _(none — pure compute)_ | |
| `dun:path` | _(none — pure compute)_ | |

## Rules

1. **Default deny.** Without permission flags, all I/O throws
   `PermissionError` immediately at the call site.

2. **Deny overrides allow.** `--deny-write=/etc` always wins, even
   with `--allow-write` (or `--allow-all`).

3. **Immutable at runtime.** Permissions are locked in once main()
   parses CLI args. JS code cannot grant or revoke them.

4. **Path canonicalization.** Both the requested path AND the scope
   patterns are canonicalized via `realpath`-style normalization
   before the subpath check. Closes CVE-2023-32004 class — a path
   like `/tmp/safe/../../etc/hostname` doesn't match a
   `--allow-read=/tmp/safe` scope because the canonical form is
   `/etc/hostname` (outside the scope).

5. **Subpath matching.** Path grants are recursive —
   `--allow-read=./data` grants `./data/foo.txt` and
   `./data/sub/bar.txt`.

6. **No ambient authority.** Child processes (spawned via
   `--allow-run`) inherit parent permissions but cannot escalate.

7. **Net scope grammar.** `host[:port]`:
   - `example.com` — any port on example.com
   - `example.com:443` — only port 443
   - `*` — any host (rare, prefer specific)

## Scoped grants in practice

```js
// script.js
const fs = require('fs');

// Without --allow-read flag:
fs.readFileSync('/etc/hostname')
// → Uncaught TypeError: Requires --allow-read for /etc/hostname

// With --allow-read=/tmp:
fs.readFileSync('/etc/hostname')
// → still denied (outside scope)

fs.readFileSync('/tmp/data.txt')
// → ok
```

```js
// network scoping
const res1 = await fetch('https://api.example.com/');
// With --allow-net=api.example.com:443 → ok
// With --allow-net=api.example.com     → ok (any port)
// With --allow-net=cdn.example.com:443 → denied (different host)
```

## CVE-class fixes

| Version | Class | What was wrong |
|---------|-------|----------------|
| v1.1.0 | Path traversal (CVE-2023-32004 class) | Permission scope comparison was a raw `startsWith`, so `/tmp/safe/../../etc/hostname` matched `--allow-read=/tmp/safe` (literal prefix) but the OS opened `/etc/hostname`. Fix: canonicalize both sides via `buildNormalizedPath(absolutePath(...))` before the subpath check |

All CVE-class fixes are regression-tested by permanent fixtures
in `tests/integration/fixtures/cve_*.js`. See
[SECURITY.md](../SECURITY.md) for the full table.

## Comparison with other runtimes

| Runtime | Default | Granularity |
|---------|---------|-------------|
| **Node.js** | Allow-all | None (process-level) |
| **Deno** | Deny-all | Path / host / env var (Deno 1.0+) |
| **Bun** | Allow-all | None (process-level — `Bun.serve` etc. require nothing) |
| **DunJS** | Deny-all | Path / host / env var / command — same shape as Deno |

DunJS chose Deno's model deliberately. If you're porting Bun code
that doesn't specify permissions, use `--allow-all` as a first
pass, then tighten down.

## What's NOT in the model

- **No CPU / memory quotas per JS context.** Use `--max-memory`,
  `--max-stack`, `--timeout` (process-level).
- **No syscall filter (seccomp).** D-side I/O is gated, but if you
  load a `.node` addon with `--allow-ffi`, it can do whatever the
  process can.
- **No network egress filter beyond host:port.** No path-based
  filter for HTTP requests (e.g., "GET only").

For the design-level rationale on these, see
[CLAUDE.md Won't-fix design constraints](../CLAUDE.md#wont-fix-design-constraints).

## Programmatic checks (Deno compat)

```js
// Check without making the call
const status = await Deno.permissions.query({ name: "read", path: "/tmp" });
if (status.state === "granted") {
  // safe to read /tmp
}

// Request — currently a no-op (interactive prompts deferred)
// Returns the current state without prompting
await Deno.permissions.request({ name: "net" });
```

See [Deno compat](./deno-compat.md) for the full `Deno.permissions`
surface.
