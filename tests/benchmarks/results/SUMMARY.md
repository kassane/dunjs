=== Cross-Runtime Benchmark Results ===
Date: 2026-05-12

### Runtimes
- Node.js v22.22.2
- Bun 1.3.11
- Deno 2.7.14
- DunJS QuickJS, JSC, V8 (debug builds)

### Feature Benchmarks (25 tests, ops/sec)
| Runtime | Total Throughput |
|---------|-----------------|
| Bun | 458M |
| DunJS JSC (release) | 426M |
| DunJS JSC (debug) | 412M |
| Node.js | 177M |
| Deno | 172M |
| DunJS V8 | 141M |
| DunJS QuickJS | 7.4M |

### npm Compat Test (145 assertions)
All 6 runtimes: 145/145 pass

### Framework Benchmarks (39 tests, ops/sec)
| Runtime | Total Throughput |
|---------|-----------------|
| DunJS JSC | 332M |
| Bun | 323M |
| Node.js | 193M |
| DunJS V8 | 192M |
| Deno | 180M |
