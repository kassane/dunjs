# TypeScript Support

DunJS runs `.ts`, `.tsx`, `.mts`, `.cts` files directly — no `tsc`
required, no preconfiguration needed.

## How it works

By default, DunJS uses a **scanner-based type stripper** at runtime.
It tokenizes the TypeScript source and emits valid JavaScript by
removing type annotations, leaving the rest untouched.

```ts
// hello.ts
const greet = (name: string): string => `Hello, ${name}`;
console.log(greet("DunJS"));
```

```sh
dun run hello.ts
# Hello, DunJS
```

The strip pipeline (`source/dun/ts/strip.d`) handles:

- Type annotations on variables, params, returns
- `interface`, `type` aliases (erased)
- Generic params (`<T>`)
- `as` casts
- `satisfies`
- `import type` / `export type` (erased)
- `declare` blocks (erased)
- `enum` → IIFE (kept at runtime since it has semantics)
- Decorators (legacy + Stage 3 — see Decorators below)
- JSX (`.tsx` / `.jsx` files via `jsx.d`)
- `import.meta` features

Output passes `tsc` parity tests (12/12 `ts_parity` fixtures) — for
every test, `dun run` produces the same observable output as
`tsc + node`.

## Modes

### Scanner (default)

Fast, runs at first execution, cached on disk by SHA-256 of the
source. Cache lives at `$DUN_HOME/cache/tsc/<first-2-chars>/<full-hash>.js`.

Pros: zero install, ~30× faster than `tsc --noEmit`, no
configuration.

Cons: doesn't catch type errors — they're stripped, not checked.

### `--typecheck`

Runs `tsc --noEmit` before execution. Auto-installs `typescript` into
`$DUN_HOME/node_modules` if not present.

```sh
dun run --typecheck script.ts
# error TS2322: Type 'number' is not assignable to type 'string'
```

Use this in CI for safety; skip it in dev for speed.

### `--transpile=tsc`

Forces full `tsc` transpile (handles all TS features including
emit-decorators). Slower; useful when the scanner can't handle an
edge case.

## JSX

`.tsx` and `.jsx` files transform via `dun.ts.jsx`:

```tsx
// app.tsx
const Hello = ({ name }: { name: string }) => <div>Hi {name}</div>;
console.log(Hello({ name: "DunJS" }));
```

Default factory is `React.createElement`. Override via
`/** @jsx h */` pragma in the file, or `--jsx-factory=h` flag.

## Decorators

DunJS handles two variants:

### Stage 3 / TC39 decorators (TypeScript 5+ default)

```ts
function logged(value, { name, kind }) {
  if (kind === "method") {
    return function (...args) {
      console.log(`call ${name}`);
      return value.apply(this, args);
    };
  }
}

class C {
  @logged
  greet(name: string) { return `hello ${name}`; }
}
```

### Legacy decorators (experimentalDecorators)

```ts
function readonly(target, key, descriptor) {
  descriptor.writable = false;
}

class C {
  @readonly
  field = 42;
}
```

Both detected automatically.

## Transpile cache

DunJS persists transpiled output across runs:

- Path: `$DUN_HOME/cache/tsc/<first-2-chars>/<sha256>.js`
- Keyed by SHA-256 of source content (not path)
- Auto-trimmed:
  - `DUN_TSC_CACHE_MAX_ENTRIES` (default 2000)
  - `DUN_TSC_CACHE_MAX_MB` (default 64 MiB)
  - Trim runs at most every `DUN_TSC_CACHE_TRIM_INTERVAL_SECS`
    (default 300 s)

Cache hits are ~30× faster than re-transpiling. Cold cache:
~1-2 ms / file. Hot cache: ~30-50 µs / file.

Disable via `--no-transpile-cache` or wipe via `dun clean`
(removes the project `.dun/`) or `rm -rf $DUN_HOME/cache/tsc`
(global).

## Configuration

DunJS reads `tsconfig.json` for module resolution paths but
**ignores** most compiler options — the scanner doesn't need them.
Specifically:

- `compilerOptions.paths` — honored for module resolution
- `compilerOptions.baseUrl` — honored
- `compilerOptions.target` — ignored (output is always ES2025)
- `compilerOptions.module` — ignored
- `compilerOptions.jsx` — honored for `.tsx` files
- `compilerOptions.jsxFactory` — honored
- `compilerOptions.experimentalDecorators` — honored

For full `tsc` semantics (e.g., `strict`, `noImplicitAny`), run
`dun run --typecheck script.ts` or invoke `tsc --noEmit`
separately in CI.

## What's NOT supported

- **CommonJS-style `require()` in `.ts` files** — works, but you
  need either `import` or `module.exports = ...` for the type
  system to follow. The scanner doesn't care; `tsc --typecheck`
  may complain.
- **`namespace` blocks** — output as IIFE assignment, mostly works
  but edge cases with merging may behave differently than `tsc`
  emits.
- **`const enum`** — emitted as regular `enum` (no inlining
  optimization). Same observable behavior at runtime.

For exact `tsc` emit semantics, use `--transpile=tsc`.

## Comparison

| | scanner (default) | `--typecheck` | `--transpile=tsc` |
|---|---|---|---|
| Speed (cold) | ~1 ms / file | depends on tsc | depends on tsc |
| Speed (cached) | ~50 µs / file | ~50 µs / file | ~50 µs / file |
| Type checking | no | yes | no |
| Auto-installs tsc | no | yes | yes |
| Decorators | yes | yes | yes |
| Const enum inline | no | yes | yes |
| Recommended for | dev | CI | edge-case TS features |

## See also

- [tsc parity test suite](../tests/benchmarks/ts_parity/) — 12 fixtures
  validating `dun run` == `tsc + node`
- [transpile_cache.d](../source/dun/ts/transpile_cache.d) — cache
  implementation
- [strip.d](../source/dun/ts/strip.d) — scanner pipeline (~600 LoC,
  20 unit tests)
