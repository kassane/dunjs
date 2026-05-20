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
- [**Module System**](./modules.md) — ES modules + CommonJS interop.
  Package resolution. npm install (with CVE audit). `dun:*` built-in
  modules

### Built-in Modules
- [**Built-ins Index**](./builtins/index.md) — all 30+ built-in modules
- [**Web APIs**](./web-apis.md) — `fetch`, `Request`, `Response`, `Headers`,
  `Blob`, `URL`, `TextEncoder`/`TextDecoder`, `AbortController`,
  `EventTarget`, `Web Streams`, `crypto.subtle` (WebCrypto)
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
- [**`dun test`**](./testing.md) — test runner (`*.test.{js,ts}`), Deno
  test API, `--filter`, `--concurrent`
- [**`dun bench`**](./bench.md) — benchmark runner (`*.bench.{js,ts}`),
  auto-calibrating iterations
- [**`dun lint`**](./lint.md) — lexer-based linter (no-eval, eqeqeq,
  no-debugger, no-var, no-empty-block, --fix)
- [**`dun fmt`**](./fmt.md) — code formatter
- [**`dun bundle`**](./bundle.md) — bundler with source maps + optional
  `--compile=PATH` for self-contained executables
- [**`dun audit`**](./audit.md) — npm CVE audit via OSV API
- [**`dun init`**](./init.md) — project scaffold

### Operations
- [**Configuration**](./config.md) — `package.json`, `tsconfig.json`,
  `dun.json` (future), env variables (`DUN_HOME`, `DUN_DISABLE_TSC`,
  `DUN_REPL_HISTORY`, etc.)
- [**GC Tuning**](./gc-tuning.md) — D-runtime GC options, when to bump
  `minPoolSize`, profile via `--DRT-gcopt=profile:1`
- [**Performance**](./performance.md) — backend selection, hot-path
  patterns, when to use Workers
- [**Migration from Node**](./migration-node.md) — running existing
  Node.js code, known incompatibilities
- [**Migration from Deno**](./migration-deno.md) — running existing
  Deno code

### Advanced
- [**N-API addons**](./napi.md) — Node-API support, 91 functions
  implemented, sharp + similar real addons work
- [**Workers**](./workers.md) — Web Workers, SharedArrayBuffer, Atomics
- [**HTTP/2 + HTTP/3**](./http2-http3.md) — server + client support,
  ALPN, QUIC
- [**TLS**](./tls.md) — OpenSSL bindings, cert/key loading, custom CA

### Project Internals (developer docs)
- [**Architecture Overview**](../ARCHITECTURE.md) — 7-layer design
- [**Engine Abstraction**](../CLAUDE.md#engine-abstraction-layer-2) —
  `IJSEngine` interface
- [**Contributing**](../CONTRIBUTING.md) — building, testing,
  PR workflow *(coming soon)*
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
   (`return scope`) and DIP1038 (`@mustuse`) enforced. Native code
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

## Performance snapshot (v1.1.16)

| Bench | Bun 1.3 | Node 22 | dun-jsc | dun-v8 | dun-qjs |
|---|---:|---:|---:|---:|---:|
| feature_bench | 533M | 162M | **552M (+4%)** | 151M | 20M |
| framework_bench | 250M | 169M | **292M (+17%)** | 163M | 16M |
| npm_compat | 145/145 | 145/145 | 145/145 | 145/145 | 145/145 |

DunJS JSC beats Bun on `feature_bench.js` since the v1.1.7 cached
Response builder + v1.1.9 handle pin landed; v1.1.16 fs stream
caching + `newUint8ArrayZeroedWithProto` fused primitive add
incremental wins. See
[performance.md](./performance.md) for the per-endpoint breakdown.
