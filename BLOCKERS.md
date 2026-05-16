# Production-readiness blockers (status)

What still keeps DunJS from being a drop-in replacement for an
arbitrary Node / Deno / Bun project. Items are kept here only while
they're actionable; closed items are referenced in CHANGELOG/PRs
instead.

## Closed

- **N-API call surface** — 91 functions including
  `napi_create_function`, `napi_define_class`, `napi_create_async_work`,
  `napi_queue_async_work`, `napi_create_threadsafe_function`. Real
  finalizer side-table for `napi_wrap` / `napi_create_external` (no
  more dummy address-as-string). Acceptance: 8 checks across
  `tests/integration/fixtures/napi_async.js` and
  `tests/integration/fixtures/napi_wrap.js`, both green on all three
  backends.

- **WebAssembly + WASI** — JSC and V8 have native `WebAssembly` plus a
  microtask polyfill for `compile`/`instantiate`/`compileStreaming`/
  `instantiateStreaming`. `dun:wasi` covers preview1, `dun run x.wasm`
  bootstraps `_start`. QuickJS prints a clear "use --backend=jsc/v8"
  error rather than failing weirdly.

- **V8 backend ICU data / Unicode property regexes** — Two-layer
  workaround in `runtime/globals.d` + `runtime/unicode_props.d`
  rewrites `\p{Name}` regex literals before V8 parses them. Express 5
  loads, 231/231 on safe_features.

- **TS strip** — class fields, intra-enum member refs, multi-line
  union/intersection type aliases, function generic params, derived-
  class constructor param-properties (super injection point),
  multi-line parameter properties. `const enum` no longer hits the
  let/const fast-path. Nested `export namespace Inner` attaches to
  parent `__ns`.

- **Vendor isolation** — brotli and lsquic vendored (build.d
  downloads + CMake/header-only). No more `libbrotli-dev` system
  dependency; lsquic ImportC bridge cross-checks the manual
  extern(C) bindings.

- **CLI sharp edges** — `dun test -ignored-any-flag` now errors
  instead of silently running everything. `--max-memory=64` = 64 MiB
  (was 64 *bytes*). `--eval-file <path>` accepts both `=` and space
  forms.

## Still open

### Lower-impact gaps

- **dun fmt** — token-aware indenter, not yet Prettier-grade.
- **DevTools full Inspector protocol** — only basic CDP commands work
  beyond `--inspect` / `--inspect-brk`.
- **TS strip: generic call sites** — `tryParse<number>(...)` parses as
  `(tryParse < number) > (...)`. Bun/Deno/Node strip modes hit the
  same wall; a real TS compiler is required.
- **Decorator runtime semantics** — we strip the `@expr` annotation
  but don't dispatch it. Same as Bun/Deno/Node strip modes.

### Won't-fix

- **Constructor parameter properties on classes that don't extend
  anything but reference `this` before any user statement** — works
  fine when injection lands at body open. The "after super()"
  detector only kicks in when `extends` is present.
- **Native `.node` addons that need `node-gyp` bindings to V8/Node
  internals** — covered for things that stick to the N-API surface;
  not covered for addons that dlopen `node` itself.
