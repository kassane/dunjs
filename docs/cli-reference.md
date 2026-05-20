# CLI Reference

Complete `dun` subcommand + flag reference. Run `dun help` for the
in-binary version (always reflects the build).

## Subcommands

| Command | Purpose |
|---------|---------|
| `dun run <file>` | Execute a script (`.js`, `.ts`, `.mjs`, `.cjs`) |
| `dun eval <code>` | Execute inline JS/TS |
| `dun repl` | Interactive REPL |
| `dun test [pattern]` | Run test files (`*.test.{js,ts}`, `*_test.{js,ts}`) |
| `dun bench [pattern]` | Run benchmark files (`*.bench.{js,ts}`) |
| `dun lint [paths...]` | Lex-based linter (6 rules) |
| `dun fmt [paths...]` | Format JS/TS files |
| `dun bundle <entry>` | Bundle to single file, optional `--compile=PATH` |
| `dun install <pkg>` | Install npm package (with CVE audit) |
| `dun audit` | Scan `node_modules/` for known CVEs |
| `dun init <name>` | Scaffold a new project |
| `dun clean` | Remove local `.dun/` + `node_modules/` |
| `dun help` | Print help |
| `dun --version` | Print version + engine backend |

## Permission flags (run, eval, test, bench)

Default-deny — every I/O operation requires explicit permission.

| Flag | Scope | Example |
|------|-------|---------|
| `--allow-read[=paths]` | File reads | `--allow-read=./data,/tmp` |
| `--allow-write[=paths]` | File writes | `--allow-write=./out` |
| `--allow-net[=hosts]` | Network | `--allow-net=api.example.com:443` |
| `--allow-env[=vars]` | Env vars | `--allow-env=NODE_ENV,PATH` |
| `--allow-run[=cmds]` | Child processes | `--allow-run=git,npm` |
| `--allow-ffi[=libs]` | FFI / dlopen | `--allow-ffi=./mylib.so` |
| `--allow-hrtime` | High-res timing | (no scope) |
| `--allow-sys[=cats]` | System info | `--allow-sys=cpus,hostname` |
| `--allow-all`, `-A` | Everything | (escape hatch) |
| `--deny-read[=paths]` | Override allow | `--deny-read=/etc/shadow` |
| `--deny-write[=paths]` | Override allow | |
| `--deny-net[=hosts]` | Override allow | |

Paths are canonicalized before scope matching — `..` traversals
can't escape a scope (CVE-2023-32004 class fix, v1.1.0+).

## Resource flags

| Flag | Default | Purpose |
|------|---------|---------|
| `--max-memory=<bytes>` | 256 MB | JS heap cap |
| `--max-stack=<bytes>` | 8 MB | JS stack depth |
| `--timeout=<seconds>` | (no limit) | Execution time cap |

## TypeScript flags

| Flag | Purpose |
|------|---------|
| `--typecheck` | Run `tsc --noEmit` before execution (auto-installs tsc if needed) |
| `--no-transpile-cache` | Disable persistent transpile cache |
| `--inspect` | Open debugger port (V8 backend only) |

## Test runner flags

| Flag | Purpose |
|------|---------|
| `--filter=<name>` | Run only tests matching name |
| `--concurrent` | Parallel execution (Bun parity) |
| `--max-concurrency=<n>` | Default 20 in-flight |
| `--no-deno` | Disable `Deno.test()` registration |

## Lint flags

| Flag | Purpose |
|------|---------|
| `--fix` | Auto-fix where safe (`eqeqeq`, `no-debugger`) |
| `--quiet` | Only print errors (suppress warnings) |
| `--max-warnings=<n>` | Exit non-zero if more than N warnings (CI gate) |

## Bundle flags

| Flag | Purpose |
|------|---------|
| `--output=<path>` | Output file (default: stdout) |
| `--sourcemap` | Emit external `.map` (V3) |
| `--sourcemap=inline` | Inline data URI source map |
| `--compile=<path>` | Self-contained executable (no `dun` needed at runtime) |
| `--minify` | Currently a no-op (deferred) |

## npm install flags

| Flag | Purpose |
|------|---------|
| `--audit=warn` | Print CVE warnings, continue (default) |
| `--audit=block` | Refuse install if CRITICAL/HIGH CVE present |
| `--audit=off` | Skip vulnerability checking |
| `--save` | Add to `package.json` `dependencies` (default) |
| `--save-dev` | Add to `devDependencies` |

## Global flags

| Flag | Purpose |
|------|---------|
| `--help`, `-h` | Print help for subcommand |
| `--version`, `-V` | Print version + engine backend |
| `--DRT-gcopt=...` | D-runtime GC options ([GC Tuning](./gc-tuning.md)) |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DUN_HOME` | `~/.dun` (Posix) or `%LOCALAPPDATA%\dun` (Win) | User-global store + transpile cache root |
| `DUN_DISABLE_TSC` | unset | Force scanner stripper instead of tsc transpile |
| `DUN_AUTO_INSTALL_TSC` | unset | Auto-install typescript when needed |
| `DUN_TSC_CACHE_MAX_ENTRIES` | 2000 | Transpile cache size cap |
| `DUN_TSC_CACHE_MAX_MB` | 64 | Transpile cache disk cap |
| `DUN_TSC_CACHE_DEBUG` | unset | Print cache write/trim errors |
| `DUN_TSC_QUIET` | unset | Suppress "tsc transpile failed; using scanner" warning |
| `DUN_TYPECHECK_DEBUG` | unset | Dump --typecheck driver to /tmp on engine error |
| `DUN_REPL_HISTORY` | `~/.dun_repl_history` | REPL history path |
| `DUN_REPL_HISTORY_SIZE` | 1000 | Max history entries |
| `DUN_TEST_TIMEOUT` | 30 | Per-fixture timeout (seconds) for integration runner |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Uncaught error (JS exception or D throw) |
| 2 | Failed assertion (`dun test`) or compile error |
| 124 | Timeout (when wrapped in `timeout`) |
| 130 | SIGINT (Ctrl-C) |
| 134 | SIGABRT (D-side assertion or memory corruption) |
| 137 | SIGKILL or OOM kill |
| 139 | SIGSEGV (file a bug — DunJS shouldn't segfault) |
