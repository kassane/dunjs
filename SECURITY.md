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

1. **Default deny** -- Without permission flags, all I/O throws `PermissionError`
2. **Deny overrides allow** -- `--deny-write=/etc` always wins over `--allow-write`
3. **Immutable at runtime** -- Permissions are set once from CLI args, cannot be changed by JS
4. **Path canonicalization** -- Symlinks resolved and paths normalized before checking
5. **No ambient authority** -- Child contexts inherit parent permissions, cannot escalate

### Unit Tests (38+ tests + 5/5 CVE fixture)

The `PermissionRegistry` is tested in `source/dun/security/test.d`:
- Default deny for all permission types
- Global grant and revocation
- `--allow-all` grants all permissions
- Scoped allow lists (path/host granularity)
- Deny overrides allow (scoped deny wins over global grant)
- `parseFlag` for all CLI flag formats
- Edge cases (empty scopes, overlapping paths)
- Path canonicalization (CVE-2023-32004 class) — `tests/integration/fixtures/cve_path_traversal.js`

## Fixed Vulnerabilities

CVE-class fixes shipped with reference to the Node / Deno advisory that
inspired the audit. Each is regression-tested by a permanent fixture.

| Version | Class | Description | Test |
|---------|-------|-------------|------|
| v1.1.0 | Path-traversal permission bypass (CVE-2023-32004 / CVE-2024-21896 class) | `Permission.check` was comparing the raw user-supplied path against the scope via `startsWith`, so `/tmp/safe/../../etc/hostname` matched a `--allow-read=/tmp/safe` scope (literal prefix match) but the OS opened `/etc/hostname`. Fix: canonicalize the resource via `dun.platform.paths.canonicalizePath` (`buildNormalizedPath(absolutePath(...))`) BEFORE `isSubpathOf`. Also canonicalize the scope patterns at parse time | `cve_path_traversal.js` (5/5) |
| v1.1.3 | Latin-1 high-byte truncation (correctness) | `Buffer.toString('latin1')` cast each byte directly to `char` and handed it to `engine.newString` (UTF-8). Bytes 0x80-0xFF are invalid as 1-byte UTF-8, so the engine silently dropped them. Fix: `dun.platform.simd.latin1ToUtf8Buf` encodes each high byte as a 2-byte UTF-8 sequence (`0xC2 0x80` .. `0xC3 0xBF`) | `audit_simd.js` (25/25) |
| v1.1.3 | JSC `newString` NUL truncation | `JSStringCreateWithUTF8CString` is NUL-terminated — strings containing 0x00 got cut at the first NUL. Fix: NUL detection via SIMD `findByte`, fallback to length-explicit `JSStringCreateWithCharacters` with full UTF-8 → UTF-16 surrogate handling. Factored as `createJSStringFromD` (private helper used by `newString` + `eval`) | `audit_roundtrip.js` (16/16) |
| v1.1.4 | `Buffer.write(str, ..., 'latin1')` ignored encoding | The implementation only sniffed `args[1]` as a numeric offset and treated the JS string's UTF-8 bytes as a Latin-1 byte sequence — so `buf.write("\x80", 0, 1, "latin1")` wrote `0xC2` (UTF-8 lead byte) instead of `0x80`. Fix: proper Node-style argument parsing + `utf8ToLatin1Buf` for latin1 decoding | `audit_roundtrip.js` (16/16) |
| v1.1.4 | JSC `eval(source)` NUL truncation | Same root cause as `newString` (UTF8CString constructor). Source code containing literal `\0` was silently chopped, producing `Uncaught SyntaxError: Unexpected EOF`. Fix: route through the same `createJSStringFromD` helper | covered by audit_roundtrip |
| v1.1.26 | Privileged-path sandbox bypass (CVE-2024-34346 / GHSA-23rx-c3g5-hv9w class — Deno 1.43 fix) | Global `--allow-read` (or `--allow-write`) silently granted access to `/proc/self/environ`, `/proc/self/maps`, `/etc/passwd`, `/etc/hostname`, `/dev/*`, `/sys/*`. Reading `/proc/self/environ` escalates `--allow-read` to `--allow-env` (env-var leak); writing `/proc/self/mem` escalates to full `--allow-all` (process memory write). Fix: `Permission.check` now consults `isPrivilegedPath(canonical)` after canonicalization. For `read`/`write`, the global grant short-circuit is bypassed when the canonical resource matches `/proc/* /sys/* /dev/* /etc/*` (POSIX) or `\\?\* \\.\*` (Windows). Explicit scoped grants (`--allow-read=/etc/myapp.conf`) still work — they're deliberate per-path intent. `--allow-all` continues to bypass the guard (explicit sandbox-escape opt-in) | `cve_priv_files.js` (8/8) |

When fixing a CVE class, the inline code comment must cite the
specific upstream advisory + the symptom the next investigator would
see if they tried to remove the fix.

## npm Package Auditing (CVE)

DunJS audits npm packages against [Google's OSV database](https://osv.dev) (Open Source
Vulnerabilities). Results are cached locally in `.dun/audit-cache.json` and auto-refresh
every 24 hours. When offline, the cached data is used as a fallback.

### Audit Modes

| Mode | Flag | Behavior |
|------|------|----------|
| **warn** (default) | `--audit=warn` | Print CVE warnings, continue install |
| **block** | `--audit=block` | Refuse to install packages with critical/high CVEs |
| **off** | `--audit=off` | Skip vulnerability checking |

### Usage

```sh
# Scan existing node_modules for known CVEs
dun audit

# Install with blocking mode (refuses vulnerable packages)
dun install jsonpath --audit=block

# Install with warnings (default)
dun install lodash

# Disable audit during install
dun install cross-spawn --audit=off
```

### Data Source: OSV API

All vulnerability data comes from the [OSV API](https://api.osv.dev):
- `POST https://api.osv.dev/v1/query` with package name, version, and `"ecosystem":"npm"`
- Results are parsed for CVE IDs (prefers CVE aliases over GHSA IDs), severity (CVSS or
  database_specific), fixed versions, and summaries
- Covers all npm advisories from GitHub Security Advisories, NVD, and other sources

### Local Cache (Auto-Refresh)

- **Location**: `.dun/audit-cache.json` (auto-created, gitignored)
- **TTL**: 24 hours — entries older than 24h are re-fetched from OSV API
- **Offline fallback**: If the API is unreachable, expired cache entries are used
- **Format**: JSON keyed by `"package@version"`, each entry has `timestamp` and `vulns` array

### Implementation

- **Pre-download check**: After version resolution, before download — blocks early in `--audit=block` mode
- **Post-install scan**: `dun audit` walks `node_modules/`, reads each `package.json`, queries OSV per package
- **OSV parsing**: Extracts CVE aliases, CVSS severity, fixed versions from affected[].ranges[].events[]
- **Semver comparison**: Custom pure D implementation (`compareSemver`) with pre-release handling
- **CVSS parsing**: Extracts severity from `database_specific.severity` or CVSS score vectors
- **8 unit tests**: Semver parsing, CVSS parsing, severity mapping, JSON escaping, cache round-trip

## Resource Limits

| Resource | Limit | Flag | Default |
|----------|-------|------|---------|
| JS heap memory | Engine-specific | `--max-memory` | 256 MB |
| Stack depth | Engine-specific | `--max-stack` | 8 MB |
| Execution time | Interrupt handler | `--timeout` | None (no limit) |

Resource limits are enforced per-engine:
- **QuickJS**: `JS_SetMemoryLimit`, `JS_SetMaxStackSize`, `JS_SetInterruptHandler`
- **JSC**: System-managed (JSC manages its own heap)
- **V8**: `ResourceConstraints` at isolate creation, `dun_v8_set_memory_limit`

## Threat Model

| Threat | Mitigation |
|--------|-----------|
| **File system traversal** | Path canonicalization + permission scoping |
| **Network exfiltration** | `--allow-net` with host:port granularity |
| **Env variable leakage** | `--allow-env` with variable name granularity |
| **Arbitrary command execution** | `--allow-run` with command name allowlist |
| **Infinite loops / DoS** | Engine interrupt handler with configurable timeout |
| **Memory exhaustion** | Engine memory limits + D-side buffer bounds |
| **Stack overflow** | Engine stack limits |
| **Code injection via eval** | `eval()` processes string literals only; no network eval by default |
| **Supply chain attacks** | CVE audit on install (`--audit=block`), `dun audit` scan |
| **Native code execution** | `--allow-ffi` required; disabled by default |

## Memory Safety

DunJS leverages D's memory safety system:

- **`@safe`**: Compiler-verified memory safety (no pointer arithmetic, no invalid casts)
- **`@trusted`**: Manually verified safe code at FFI boundaries
- **`@system`**: Only in platform abstraction layer for raw OS calls
- **`@nogc`**: Zero garbage collection in hot paths
- **`nothrow`**: All `extern(C)` callbacks (C cannot handle D exceptions)
- **DIP1000 (`return scope`)**: Engine APIs returning slices into engine-owned
  memory (`IJSEngine.getTypedArrayBytes`, `builtins.buffer.extractBytes`) carry
  the `return scope` qualifier on the virtual method + every backend override;
  the compiler refuses to let a caller leak the slice past the source
  JSHandle's lifetime without an explicit `.dup`
- **DIP1038 (`@mustuse`)**: `JSResult` (eval result) and `AsyncResult` (async
  worker result) are `@mustuse` structs — the compiler refuses to drop them
  silently, catching at compile time the bug class where an `engine.eval(...)`
  failure gets swallowed and the symptom surfaces seconds later as
  `Worker is undefined` with no stderr diagnostic

### Per-Engine Memory Management

| Engine | GC Strategy | D Bridge | Release |
|--------|-------------|----------|---------|
| QuickJS | Reference counting | RAII wrappers (`JSVal`, `Runtime`, `Context`) | `JS_FreeValue(ctx, val)` |
| JSC | Tracing GC (WebKit) | `JSValueProtect` / `JSValueUnprotect` | Unprotect allows GC |
| V8 | Generational GC | Ref-counted `DunV8Value*` via C++ shim | `dun_v8_value_unref` |

The D <-> C/C++ boundary is carefully managed to ensure deterministic cleanup and prevent use-after-free.

## Reporting Vulnerabilities

Please report security vulnerabilities **privately** via one of these channels:

1. [GitHub Security Advisories](https://github.com/kassane/dunjs/security/advisories/new)
2. Email to the maintainer (see repository profile)

**Do not** open public issues for security bugs. We will acknowledge reports
within 48 hours and aim to release patches within 7 days for critical issues.

## Security Review Workflow

The `/security-review` skill (Claude Code) runs an audit of the pending
changes on the current branch. It checks for the OWASP top-10 classes
applicable to this codebase:

- **Command injection** — `child_process.exec*` / `spawn` arguments
- **Path traversal** — file ops via `fs.*` (canonicalization gate
  in `Permission.check` is the line of defense)
- **XSS** — HTML output via `Response`, template strings injected
  into headers
- **SQL injection** — `sqlite3` bindings (parameterized queries
  enforced)
- **Prototype pollution** — `Object.assign` / spread on untrusted
  input
- **ReDoS** — regex literals on user input (lexer + linter flag
  catastrophic patterns)
- **Supply chain** — `dun install` checks each package against OSV
  before download in `--audit=block` mode

Run before opening a PR that touches `source/dun/security/`,
`source/dun/builtins/fs.d` / `net.d` / `http*.d` / `child_process.d`,
or any new `IJSEngine` callback that takes user input.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.x.x | Development -- best effort |
| 1.x.x | Active security support — CVE-class fixes backported |
