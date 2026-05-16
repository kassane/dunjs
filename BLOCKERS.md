# Blockers preventing DunJS from fully replacing Node / Deno / Bun

Tracking document for the `claude/fix-node-deno-bun-blockers` branch.
Stacked on top of the runtime-parity sweep PR (#3).

The runtime-parity work in #3 closed every functional gap *within*
DunJS's existing surface area: 109 integration tests pass on all three
backends, 145/145 npm-package compat checks pass, JSC backend overtakes
Bun on framework_bench, V8 backend matches Node on framework_bench.

What still keeps DunJS from being a drop-in replacement for an
arbitrary Node / Deno / Bun project, in priority order:

## 1. N-API surface (~59 of 91 essential functions missing)

Current implementation in `source/dun/napi/napi.d` exposes 32
functions — enough for trivial native addons but nowhere near enough
for the long tail of npm packages that ship a `.node` binary.

Hot misses (used by very common addons):

| Group             | Missing                                              | Used by                          |
|-------------------|------------------------------------------------------|----------------------------------|
| Strings           | `create_string_utf16`, `create_string_latin1`        | nearly every addon                |
| Properties        | `get_property`, `set_property`, `has_property`,      | every wrapper                    |
|                   | `has_named_property`, `delete_property`,             |                                  |
|                   | `get_property_names`, `get_prototype`                |                                  |
| Functions         | `create_function`, `define_class`, `define_properties` | sharp, better-sqlite3, bcrypt   |
| TypedArrays       | `create_typedarray`, `get_typedarray_info`,          | sharp, canvas, bcrypt            |
|                   | `is_typedarray`, `create_dataview`, `get_dataview_info`|                                |
| ArrayBuffers      | `create_arraybuffer`, `create_external_arraybuffer`, | sharp, canvas                    |
|                   | `get_arraybuffer_info`, `is_arraybuffer`             |                                  |
| Buffers           | `create_buffer`, `create_buffer_copy`,               | nearly every Node addon          |
|                   | `create_external_buffer`, `is_buffer`, `get_buffer_info` |                              |
| Promises          | `create_promise`, `resolve_deferred`, `reject_deferred`, `is_promise` | async-heavy addons |
| Errors            | `create_error`, `create_type_error`, `create_range_error`, `throw`, `throw_range_error`, `is_error` | all addons |
| Wrap / instance   | `wrap`, `unwrap`, `remove_wrap`, `instanceof`,       | class-binding addons             |
|                   | `new_instance`                                        |                                  |
| Handle scopes     | `open_handle_scope`, `close_handle_scope`,           | all addons (V8 GC interaction)  |
|                   | `open_escapable_handle_scope`, `close_escapable_handle_scope`, `escape_handle` |        |
| References        | `reference_ref`, `reference_unref`                   | long-lived JS values             |
| BigInt            | `create_bigint_int64/uint64`, `get_value_bigint_int64/uint64` | crypto, large ints      |
| Symbols           | `create_symbol`                                       | well-known symbol APIs           |

**Acceptance**: `sharp`, `better-sqlite3`, `bcrypt`, and `node-canvas`
should `dun install <pkg>` and load without error. Functional tests
beyond load time are out of scope for this PR — those are addon-side
behavioral tests.

## 2. WebAssembly + WASI

Entirely missing. No `WebAssembly` global, no `.wasm` import via ESM
module attributes, no WASI shims.

Practical scope for the first cut:
- `WebAssembly` global with `Module`, `Instance`, `Memory`, `Table`,
  `compile`, `instantiate`, `validate`, `compileStreaming`,
  `instantiateStreaming` — wire to QuickJS / JSC / V8 built-in WASM
  engines (all three engines ship a Wasm runtime, just need to expose
  the JS API)
- `import attributes`: `import wasmMod from './x.wasm' with { type: 'wasm' }`
- WASI: `dun:wasi` or `wasi` module with `preview1` snapshot APIs
  (preopens, fd_read/write, args, env, exit). Look at how Bun /
  Node /  Deno layer this — Node's `wasi` module is the closest.

**Acceptance**: `dun run hello.wasm` works for a `wasi-libc`-built
binary. `WebAssembly.instantiate(bytes).then(...)` works.

## 3. V8 backend ICU data (1 test fail)

`libv8` prebuilt at v15.0.91 ships without `icudtl.dat`, so V8 reports
"Invalid property name in character class" for `/[\p{L}]/v` regex.
QuickJS / JSC handle Unicode property escapes natively.

Options:
1. Add an `i18n` profile request to `kassane/libv8` (the Justfile in
   that repo has the profile defined but no published asset for v15).
2. Build libv8 ourselves with `v8_enable_i18n_support=true` and ship
   the result in DunJS releases.
3. Lazy-load Chromium's `icudtl.dat` at runtime if available.

**Acceptance**: `tests/benchmarks/safe_features.js` reports 231/231
on the V8 backend.

## 4. Smaller follow-ups (low priority)

- `dun fmt` reaches Prettier-grade (currently token-aware indenter)
- HTTP/3 server (currently API stubs only — `http3` module exposes
  the constants and varint encoder but no listener)
- DevTools full Inspector protocol coverage (we expose `--inspect` and
  start a CDP server but only basic commands work)
- Express 5.x compat (`app._router` removed by express; our integration
  test was written for express 4)
