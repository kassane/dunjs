=== Cross-Runtime Benchmark Results ===
Date: 2026-05-12 (post workers-all-backends + react compat)

### Runtimes
- Node.js v22.22.2
- Bun 1.3.11
- Deno 2.7.14
- DunJS QuickJS, JSC, V8 (release builds)

### Feature Benchmarks (25 tests, ops/sec)
| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| DunJS JSC | 536M | 1.00x (fastest) |
| Bun | 477M | 0.89x |
| Node.js | 175M | 0.33x |
| Deno | 172M | 0.32x |
| DunJS V8 | 141M | 0.26x |
| DunJS QuickJS | 11M | 0.02x |

### Framework Benchmarks (39 tests, ops/sec)
| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| DunJS JSC | 319M | 1.00x (fastest) |
| Bun | 279M | 0.87x |
| Node.js | 196M | 0.62x |
| DunJS V8 | 190M | 0.60x |
| Deno | 187M | 0.59x |

### React/Framework Compat (81 checks)
All 6 runtimes: 81/81 pass
(VDOM, SSR, hooks, signals, Proxy reactivity, Redux, router, CSS-in-JS, reconciliation)

### React/Framework Perf Benchmark (ops/sec)
| Runtime | Total Throughput |
|---------|-----------------|
| Deno | 123M |
| Node.js | 108M |
| DunJS V8 | 99M |
| DunJS JSC | 24M |
| Bun | 21M |
| DunJS QuickJS | 3M |

### Stress Tests (240 comprehensive JS tests)
| Runtime | Wall Time |
|---------|-----------|
| Bun | 78s |
| Node.js | 147s |
| Deno | 160s |
| DunJS V8 | 169s |

### npm Compat Test (145 simulated packages)
All 6 runtimes: 145/145 pass

### Workers (all backends)
All 3 DunJS backends pass worker tests (postMessage/onmessage,
SharedArrayBuffer, Atomics). Previously QuickJS-only.
