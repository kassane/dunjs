# Blockers preventing DunJS from fully replacing Node / Deno / Bun

Tracking document for the `claude/fix-node-deno-bun-blockers` branch.
Stacked on top of the runtime-parity sweep PR (#3).

The runtime-parity work in #3 closed every functional gap *within*
DunJS's existing surface area: 109 integration tests pass on all three
backends, 145/145 npm-package compat checks pass, JSC backend overtakes
Bun on framework_bench, V8 backend matches Node on framework_bench.

What still keeps DunJS from being a drop-in replacement for an
arbitrary Node / Deno / Bun project, in priority order:

## 1. N-API surface

**Status**: DONE for the call surface. 91 N-API functions implemented
in `source/dun/napi/napi.d`, covering everything in the BLOCKERS-§1
table (strings/properties/functions/typedarrays/arraybuffers/buffers/
promises/errors/wrap/handle scopes/references/bigint/symbols).

Critically, `napi_create_function` and `napi_define_class` now actually
dispatch the C callback (previously they returned a no-op stub). The
implementation uses a JS shim that captures the napi-fn slot ID and
forwards through a single shared D `napiDispatch` trampoline:

```js
(function(__slot){return function(){
  return globalThis.__dun_napi_dispatch__(__slot, this, arguments);
};})(SLOT_ID)
```

This avoids burning one D-side `NativeCallback` slot per napi function
(of which the engine only has 32k) while still giving each napi fn its
own per-instance data pointer.

`--export-dynamic` is added to the linker flags so dlopen'd .node files
can resolve `napi_*` symbols against the host process. QuickJS's
`bindings.d` is excluded from JSC and V8 builds so undefined-symbol
references don't leak through.

**Acceptance check**: a hand-built N-API addon (`add(a,b)` + `hello()`
both via `napi_create_function`) loads via `require('./addon.node')`
on all three backends and returns the correct values. See
`/tmp/napi_test.c` test pattern.

Still TODO for full sharp / bcrypt / canvas support:
- `napi_get_value_string_utf8` returns dummy length when `buf == NULL`
- async work APIs (`napi_create_async_work`, `napi_queue_async_work`)
- threadsafe functions (`napi_create_threadsafe_function`)
- finalizer callbacks for `napi_create_external` actually firing
- script-friendly errno → napi_status mappings

## 2. WebAssembly + WASI

**Status**: DONE for JSC and V8. QuickJS has no WASM engine — fails with
a clear error message pointing at `--backend=jsc`/`--backend=v8`.

Shipped in this branch:
- `WebAssembly` global exists natively on JSC and V8. The engine's
  internal async task scheduler isn't pumped by our event loop, so a
  microtask-based polyfill replaces `WebAssembly.compile`,
  `WebAssembly.instantiate`, `compileStreaming`, and
  `instantiateStreaming` with `Promise.resolve().then(...)` wrappers
  around the synchronous `new Module()` / `new Instance()` constructors.
  See `installGlobals` in `source/dun/runtime/globals.d`.
- `dun:wasi` module (`source/dun/builtins/wasi.d`) implements WASI
  preview1: `args_get/sizes_get`, `environ_get/sizes_get`,
  `clock_time_get`, `random_get`, `proc_exit`, `fd_{close,read,write,seek,
  tell,fdstat_get,filestat_get,prestat_get,prestat_dir_name}`, and the
  `path_*` family (open, create_directory, filestat_get,
  remove_directory, unlink_file). Unsupported syscalls return `ENOSYS`.
- `dun run hello.wasm` extension dispatch (`source/dun/app.d`)
  synthesizes a WASI bootstrap that reads the bytes, instantiates the
  module against `wasi_snapshot_preview1`, and calls `_start`.
- `process.stdout.write` / `process.stderr.write` learned to handle
  `Uint8Array` / `Buffer` so binary `fd_write` output reaches the
  terminal unmangled.

**Acceptance check**: a hand-coded `hello.wasm` calling
`wasi_snapshot_preview1.fd_write` prints `"Hello, WASI!"` and exits
0 on both `./dun-jsc` and `./dun-v8`.

Still missing (low priority for first cut):
- `import wasmMod from './x.wasm' with { type: 'wasm' }` import attributes
- `WebAssembly.Module.{exports,imports,customSections}` consistency
  (works because we delegate to the engine, but no validation tests)
- Async `WebAssembly.compile()` returning streaming-style benefits —
  ours always resolves on the next microtask

## 3. V8 backend ICU data

**Status**: DONE via Unicode-property polyfill (option 4 below — none
of the original three options were feasible from inside this repo).

Approach is a two-layer workaround:

1. **Runtime polyfill** in `runtime/globals.d`'s `unicodePropPolyfillSource`:
   wraps `RegExp` so `new RegExp('\\p{L}', 'u')` retries with bare
   character classes when the engine throws on the property escape.

2. **Source-level rewriter** in `runtime/unicode_props.d`: before V8
   parses a module, walks the source bytes and rewrites `\p{Name}` /
   `\P{Name}` to the equivalent `[ranges]` literal. Required because
   regex *literals* like `/^[$_\p{ID_Start}]$/u` (Express 5 uses one)
   throw at parse time, before the runtime polyfill could intercept.

Pre-baked tables cover General_Category groups (L/N/P/S/M/Z/C),
identifier props (ID_Start/Continue, XID_*), Lu/Ll/Nd, ASCII, and
White_Space. Properties not in the table fall back to a "match
nothing" range — a degraded but non-throwing result.

**Acceptance**: `tests/benchmarks/safe_features.js` reports 231/231
on V8. Express 5 (`/[$_\p{ID_Start}]$/u`) loads. `npm_deep_compat`,
`npm_real_packages`, and `express_e2e` integration tests pass.

## 4. Smaller follow-ups (low priority)

- `dun fmt` reaches Prettier-grade (currently token-aware indenter)
- HTTP/3 server (currently API stubs only — `http3` module exposes
  the constants and varint encoder but no listener)
- DevTools full Inspector protocol coverage (we expose `--inspect` and
  start a CDP server but only basic commands work)
- Express 5.x compat (`app._router` removed by express; our integration
  test was written for express 4)
