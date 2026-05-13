=== Cross-Runtime Benchmark Results ===
Date: 2026-05-13 (post kassane/libv8 v14.9, vendor/crt removal, LDC 1.42.0)

### Runtimes
- Node.js v22.22.2
- Bun 1.3.11
- Deno 2.7.14
- DunJS QuickJS, JSC, V8 (debug + release builds)

### Feature Benchmarks (25 tests, ops/sec)
| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.11 | 761M | 1.00x |
| DunJS V8 (debug) | 545M | 0.72x |
| DunJS JSC (debug) | 540M | 0.71x |
| DunJS JSC (release) | 534M | 0.70x |
| Node.js v22 | 158M | 0.21x |
| Deno 2.7.14 | 136M | 0.18x |
| DunJS V8 (release) | 117M | 0.15x |
| DunJS QuickJS | 9.5M | 0.01x |

### Framework Benchmarks (39 tests, ops/sec)
| Runtime | Total Throughput | Relative |
|---------|-----------------|----------|
| Bun 1.3.11 | 373M | 1.00x |
| DunJS JSC (debug) | 318M | 0.85x |
| DunJS JSC (release) | 249M | 0.67x |
| DunJS V8 (debug) | 161M | 0.43x |
| Node.js v22 | 160M | 0.43x |
| Deno 2.7.14 | 159M | 0.43x |
| DunJS V8 (release) | 157M | 0.42x |

### React/Framework Compat (81 checks)
All 6 runtimes: 81/81 pass

### Stress Tests (240 comprehensive JS tests)
| Runtime | Wall Time | Pass |
|---------|-----------|------|
| DunJS JSC | 78s | 240/240 |
| Bun | 78s | 240/240 |
| Node.js | 147s | 240/240 |
| Deno | 160s | 240/240 |
| DunJS V8 | 172s | 240/240 |

### npm Compat Test (145 simulated packages)
All 6 runtimes: 145/145 pass

### Integration Tests (62 fixtures)
All 3 DunJS backends: 62/62 pass (QuickJS, JSC, V8)

### Unit Tests (49 per backend)
All 3 DunJS backends: 49/49 pass (unittest, unittest-jsc, unittest-v8)

### Workers (all backends)
All 3 DunJS backends pass worker tests (postMessage/onmessage,
SharedArrayBuffer, Atomics).
