# DunJS Documentation

User-facing documentation for [DunJS](https://github.com/kassane/dunjs) — a
secure JavaScript / TypeScript runtime written in D with a pluggable engine
architecture (QuickJS-NG / JavaScriptCore / V8).

## Table of Contents

### Getting Started
- [**Installation**](./installation.md) — install from source or prebuilt
  binary, pick a backend, verify the install
- [**Quick Start**](./quick-start.md) — `dun run script.js`, `dun repl`,
  `dun eval`, `dun test`, `dun bench`
- [**CLI Reference**](./cli-reference.md) — every subcommand + flag

### Core Concepts
- [**Backends**](./backends.md) — QuickJS-NG (default, interpreter),
  JavaScriptCore (JIT, Safari/Bun), V8 (JIT, Chrome/Node). When to pick
  which, perf trade-offs, binary sizes
- [**Permission Model**](./permissions.md) — default-deny security model
  inherited from Deno. `--allow-read`, `--allow-write`, `--allow-net`,
  `--allow-env`, `--allow-run`, `--allow-ffi`, `--allow-all`. Scoped
  grants. `--deny-*` overrides

### Built-in Modules
- [**Built-ins Index**](./builtins/index.md) — all 30+ built-in modules
  (fs, path, net, http, http2, http3, crypto, os, buffer, events, url,
  zlib, dns, ws, sqlite, child_process, stream, util, vm, cluster,
  async_hooks, worker_threads, fs/promises, readline, tls, dgram,
  perf_hooks, wasi, yaml, ...), plus web globals (`fetch`, `Request`,
  `Response`, `Headers`, `Blob`, `URL`, `TextEncoder`/`TextDecoder`,
  `AbortController`, `EventTarget`, `Web Streams`, `crypto.subtle`)
- [**Node compat**](./node-compat.md) — which Node.js APIs work, which
  don't, the won't-fix list (`.node` native addons that bypass N-API)
- [**Deno compat**](./deno-compat.md) — `Deno.serve`, `Deno.Command`,
  `Deno.openKv`, fs/env/permissions APIs
- [**Bun compat**](./bun-compat.md) — `Bun.serve`, `Bun.file`, `Bun.write`,
  `Bun.hash`, `Bun.password`, `Bun.semver`, `Bun.glob`, etc.

### TypeScript
- [**TypeScript Support**](./typescript.md) — type stripping (default),
  optional `tsc` transpile, transpile cache, JSX, decorators

### Tooling
The [CLI Reference](./cli-reference.md) covers every subcommand in
detail: `dun run`, `dun test`, `dun bench`, `dun lint`, `dun fmt`,
`dun bundle`, `dun audit`, `dun install`, `dun init`, `dun clean`,
`dun repl`, `dun eval`.

### Operations
- [**GC Tuning**](./gc-tuning.md) — D-runtime GC options, when to bump
  `minPoolSize`, profile via `--DRT-gcopt=profile:1`
- [**Performance**](./performance.md) — backend selection, hot-path
  patterns, when to use Workers
- [**Migration from Node**](./migration-node.md) — running existing
  Node.js code, known incompatibilities

### Project Internals (developer docs)
- [**Architecture Overview**](../ARCHITECTURE.md) — 7-layer design
- [**Engine Abstraction**](../CLAUDE.md) — `IJSEngine` interface,
  development guide, code style, GC tuning, won't-fix design
  constraints
- [**Security Policy**](../SECURITY.md) — permission model, fixed CVE
  classes, `/security-review` workflow
- [**Testing**](../TESTING.md) — full test inventory, integration
  sweep recipe
- [**Changelog**](../CHANGELOG.md) — release notes, phase deliveries

## What's special about DunJS?

1. **Three real engines, one runtime.** Same script runs identically on
   QuickJS-NG (default, 10 MB binary, interpreter), JavaScriptCore (JIT,
   Safari/Bun engine), and V8 (JIT, Chrome/Node engine). Pick at build
   time; ship one binary.

2. **Secure by default.** Inherits Deno's permission model — every I/O
   operation requires an explicit `--allow-*` flag. Default-deny. Path
   canonicalization protects against CVE-2023-32004 class traversals.

3. **Built on D.** Memory-safe (`@safe` by default with the `safer`
   preview), `nothrow` callbacks at every FFI boundary, DIP1000
   (`return scope`), DIP1038 (`@mustuse`), DIP1008 (`@nogc throw`),
   DIP1051 (bitfields) all enabled. `--edition=2025` rolls forward
   to D's post-Zero-Edition feature defaults (DIP 1052). Native code
   without the C unsafety footguns.

4. **Comprehensive Node / Deno / Bun compat.** All 30+ Node built-in
   modules, 30+ Deno APIs, 25+ Bun APIs. 145/145 npm-compat. Real
   N-API for native addons.

5. **Audit-driven correctness.** Every CVE-class fix carries a permanent
   regression-test fixture. UTF-8 / Latin-1 round-trip tested across all
   256 byte values. JSC NUL-truncation gone. See [SECURITY.md](../SECURITY.md).

## Quick example

```sh
# Run a script
dun run hello.ts

# Allow only the data dir
dun run --allow-read=./data script.js

# Self-contained executable
dun bundle entry.ts --compile=./myapp
./myapp                                  # standalone, no `dun` needed

# Bench across runtimes
bash tests/benchmarks/http_bench/run.sh
```

```js
// hello.ts
const greet = (name: string): string => `Hello, ${name}!`;
console.log(greet("DunJS"));
```

## Performance snapshot (v1.1.26)

| Bench | Bun 1.3 | Node 22 | Deno 2.7 | dun-jsc | dun-v8 | dun-qjs |
|---|---:|---:|---:|---:|---:|---:|
| feature_bench | 501M | 162M | 160M | **500M (~par)** | 161M | 23M |
| framework_bench | 300M | 178M | 159M | **266M** | 164M | 17M |
| npm_compat | 145/145 | 145/145 | 145/145 | 145/145 | 145/145 | 145/145 |

DunJS JSC is at parity with Bun on `feature_bench.js` since the
v1.1.7 cached Response builder + v1.1.9 handle pin. v1.1.16-v1.1.20
added fs stream caching + dgram cache + cluster cache + v8shim
hot-path opts + jscpd-driven dedup. See
[performance.md](./performance.md) for the per-endpoint breakdown.
