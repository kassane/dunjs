# Security Policy

## Permission Model

DunJS follows a **default-deny** security model inspired by Deno. No script has
access to the file system, network, environment variables, or child processes
unless explicitly granted via CLI flags.

### Permission Flags

| Flag | Scope | Description |
|------|-------|-------------|
| `--allow-read[=paths]` | File paths | Read access to file system |
| `--allow-write[=paths]` | File paths | Write access to file system |
| `--allow-net[=hosts]` | Host:port | Network access (TCP, UDP, HTTP) |
| `--allow-env[=vars]` | Env var names | Access to environment variables |
| `--allow-run[=cmds]` | Command names | Execute child processes |
| `--allow-ffi` | Global | Load dynamic libraries via FFI |
| `--allow-hrtime` | Global | High-resolution time measurement |
| `--allow-all` / `-A` | Global | Grant all permissions |
| `--deny-read[=paths]` | File paths | Explicitly deny (overrides allow) |
| `--deny-write[=paths]` | File paths | Explicitly deny (overrides allow) |
| `--deny-net[=hosts]` | Host:port | Explicitly deny (overrides allow) |

### Examples

```sh
# Run with no I/O permissions (safe sandbox)
dun run script.js

# Allow reading only from ./data and /tmp
dun run --allow-read=./data,/tmp script.js

# Allow all network access
dun run --allow-net script.js

# Allow specific network hosts
dun run --allow-net=api.example.com:443,cdn.example.com:443 script.js

# Grant all permissions (use with caution)
dun run --allow-all script.js
dun run -A script.js

# Deny overrides allow
dun run --allow-read --deny-read=/etc/shadow script.js
```

### Enforcement Architecture

Permissions are enforced at the **D native layer**, not the JavaScript layer.
Every built-in module that performs I/O calls `PermissionRegistry.check()` before
executing the operation. JavaScript code cannot bypass these checks.

| Module | Permission Required | Resource Scope |
|--------|--------------------|-----------------------|
| `dun:fs` | `read` / `write` | File/directory path |
| `dun:net` | `net` | `host:port` |
| `dun:http` | `net` | URL host |
| `process.env` | `env` | Variable name |
| `Dun.run()` | `run` | Command name |
| `dun:crypto` | _(none)_ | Pure computation |
| `dun:path` | _(none)_ | Pure computation |

### Enforcement Rules

1. **Default deny** — Without permission flags, all I/O throws `PermissionError`
2. **Deny overrides allow** — `--deny-write=/etc` always wins over `--allow-write`
3. **Immutable at runtime** — Permissions are set once from CLI args, cannot be changed by JS
4. **Path canonicalization** — Symlinks resolved and paths normalized before checking
5. **No ambient authority** — Child contexts inherit parent permissions, cannot escalate

## Resource Limits

| Resource | Limit | Flag | Default |
|----------|-------|------|---------|
| JS heap memory | `JS_SetMemoryLimit` | `--max-memory` | 256 MB |
| Stack depth | `JS_SetMaxStackSize` | `--max-stack` | 8 MB |
| Execution time | `JS_SetInterruptHandler` | `--timeout` | None (no limit) |

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| **File system traversal** | Path canonicalization + permission scoping |
| **Network exfiltration** | `--allow-net` with host:port granularity |
| **Env variable leakage** | `--allow-env` with variable name granularity |
| **Arbitrary command execution** | `--allow-run` with command name allowlist |
| **Infinite loops / DoS** | `JS_SetInterruptHandler` with configurable timeout |
| **Memory exhaustion** | `JS_SetMemoryLimit` + D-side buffer bounds |
| **Stack overflow** | `JS_SetMaxStackSize` |
| **Code injection via eval** | `eval()` processes string literals only; no network eval by default |
| **Supply chain attacks** | Future: subresource integrity checks, lockfiles |
| **Native code execution** | `--allow-ffi` required; disabled by default |

## Memory Safety

DunJS leverages D's memory safety system:

- **`@safe`**: Compiler-verified memory safety (no pointer arithmetic, no invalid casts)
- **`@trusted`**: Manually verified safe code at FFI boundaries
- **`@system`**: Only in platform abstraction layer for raw OS calls
- **`@nogc`**: Zero garbage collection in hot paths
- **`nothrow`**: All `extern(C)` callbacks (C cannot handle D exceptions)

The QuickJS engine itself is written in C with its own reference counting GC.
The D ↔ C boundary is carefully managed via RAII wrappers (`JSVal`, `Runtime`, `Context`)
that ensure deterministic cleanup and prevent use-after-free.

## Reporting Vulnerabilities

Please report security vulnerabilities **privately** via one of these channels:

1. [GitHub Security Advisories](https://github.com/kassane/dunjs/security/advisories/new)
2. Email to the maintainer (see repository profile)

**Do not** open public issues for security bugs. We will acknowledge reports
within 48 hours and aim to release patches within 7 days for critical issues.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.x.x | Development — best effort |
| 1.x.x | (future) Full security support |
