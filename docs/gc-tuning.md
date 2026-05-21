# GC Tuning

DunJS uses D's garbage collector for the runtime side (allocation
tracking, async task queues, etc.) — the JS engine has its own GC
that operates on JS values independently.

## Default settings

DunJS sets `rt_options = ["gcopt=minPoolSize:16"]` in `app.d`:

- **16 MiB minimum pool** — reduces GC collections ~11× vs D's
  default (1 MiB)
- D's default GC otherwise (conservative, parallel marking on 4+
  cores when stack-scan is needed)

## Per-run tuning

Override via `--DRT-gcopt=<options>`:

```sh
# Server workload — larger pools, fewer collections
dun "--DRT-gcopt=minPoolSize:32 maxPoolSize:512" run server.js

# Memory-constrained — smaller pools, more frequent collections
dun "--DRT-gcopt=minPoolSize:4 maxPoolSize:64" run script.js

# Precise GC (fewer false retentions, ~10% slower)
dun "--DRT-gcopt=gc:precise" run script.js

# Parallel marking on N cores
dun "--DRT-gcopt=parallel:4" run script.js

# Print GC stats at exit
dun "--DRT-gcopt=profile:1" run script.js

# Show all GC options
dun "--DRT-gcopt=help"
```

## Profile output

`--DRT-gcopt=profile:1` prints at exit:

```
        Number of collections:  6
        Total GC prep time:  0 milliseconds
        Total mark time:  2 milliseconds
        Total sweep time:  1 milliseconds
        Total page recovery time:  0 milliseconds
        Max Pause Time:  1 milliseconds
        Grand total GC time:  3 milliseconds
GC summary:     16 MB,      6 GC      3 ms, Pauses    3 ms <    1 ms
```

If `Grand total GC time` is > 5% of wall time, consider:

1. **Larger pools** — `minPoolSize:32` or higher
2. **Long-lived allocations** — reuse buffers via
   `dun.platform.arena.StackFallback` or `Region`
3. **Profile to find the allocator** — `perf record -g` and look for
   `_d_newclass` / `_d_array_*` hotspots

## Benchmark impact

Measured on `feature_bench.js` (release builds, 25 benchmarks):

| Config | dun-qjs | dun-jsc | dun-v8 | GCs |
|--------|--------:|--------:|-------:|----:|
| **Default (`minPoolSize:16`)** | 23.7M | 513M | 165M | 6-25 |
| `minPoolSize:32` | 23.5M | 497M | 169M | 3-12 |
| `minPoolSize:64` | 23.3M | 463M | 163M | 2-7 |
| `parallel:4` | 22.6M | 508M | 162M | 6-23 |
| `gc:precise` | 22.6M | 497M | 169M | 6-23 |

Takeaway: the 16 MiB default is at the throughput knee.
`minPoolSize:32` halves collection count but throughput barely
moves. `minPoolSize:64` regresses JSC ~10% (pool re-allocs cost
more than the saved collections).

**Don't change the default unless you have profile data showing
GC overhead.**

## Worker / Cluster

Each Worker / Cluster child has its own D runtime + GC. Tuning is
per-process. To apply to all workers:

```js
// in your main entry
const worker = new Worker("./worker.js", {
  execArgv: ["--DRT-gcopt=minPoolSize:32"]
});
```

## Engine GC

The JS engine (QJS / JSC / V8) has its own GC that operates on JS
values. Engine-level tuning:

- **`--max-memory=<bytes>`** — engine heap cap (default 256 MB)
- **`--max-stack=<bytes>`** — engine stack depth (default 8 MB)

Engine GCs are independent of D's GC. The two coordinate via
`engine.dupValue` / `engine.freeValue` (ref-counted on QJS,
protect-counted on JSC, refcounted-via-shim on V8).

## When to NOT tune

- **Short-lived scripts** (< 100 ms) — GC time is in the noise
- **CPU-bound code** without large heap turnover — defaults are fine
- **Servers with steady-state allocation** — defaults handle this well
- **You haven't profiled yet** — measure first, tune second

## See also

- [D Memory Management](https://dlang.org/spec/garbage.html) —
  upstream docs
- `core.memory.GC` — D's runtime GC API (used internally by DunJS)
- [Performance](./performance.md) — broader perf guide
- [Built-ins index](./builtins/index.md) — `dun:worker_threads`,
  `dun:cluster`, `dun:async_hooks` for multi-process / multi-thread
  patterns
