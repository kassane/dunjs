# Plan: TS parser path forward (research outcome + kickoff)

**Status**: research complete + lexer lift complete + strip.d
wiring landed + cross-runtime conformance validated + ASan-clean
on every fixture. Phase 1/2/3/4 of the lexer are in tree
(`source/dun/ts/parser/`); the strip-mode main loop consults the
lexer for regex disambiguation; the corpus-validation unittest
runs the lexer over every `ts_compat/` AND `ts_parity/` fixture.
**Recommendation**: **NO-GO** on a full Bun-parser port still
stands. The lexer-only lift captured the high-ROI fraction of
the value (~80% of correctness wins for ~30% of the effort).
The deferred items in the original plan were re-evaluated; the
ones with concrete user-observable wins landed (private
identifiers, nested-template brace balancing); the others remain
deferred per the "observable correctness already met" rationale.

## What's in the tree so far

- `vendor/bun-parser/zig/src/js_parser/{lexer,lexer_tables}.zig` —
  upstream Zig sources vendored for diff reference. MIT-licensed.
- `source/dun/ts/parser/lexer.d` — D port (phases 1 + 2 + 3 landed):
  * Full `T : ubyte` token enum (matches Bun's `pub const T = enum(u8)`)
  * `Lexer` struct with `next()` + line/col tracking
  * Identifiers (ASCII + `$` / `_` + permissive UTF-8 high bytes),
    keywords (35 reserved-word table), numeric literals (decimal, hex,
    oct, bin, numeric separators, `.`, exponent, BigInt `n` suffix),
    strings (`"…"`, `'…'` with `\` escape), single-line + block
    comments, hashbang
  * Template literals (`` ` `` + `${…}`) -- head / middle / tail /
    no-substitution variants with `templateDepth` interpolation guard
  * Regex vs divide disambiguation via `Lexer.allowsRegex(lastKind)` --
    same trick Bun uses to avoid parser feedback
  * All single-char punctuation + the multi-char operator set
    `=== !== ??= ??. ?. **= >>>= …` (~40 operators)
  * 16+ inline unittests covering every category above
- `source/dun/ts/parser/package.d` — public `tokenize()` /
  `hasSyntaxError()` API + corpus-validation unittest over the
  `tests/benchmarks/ts_compat/` real-world fixtures (asserts every
  fixture lexes cleanly, catches regressions in scanner state).

First lexer-into-strip wiring landed:

- `source/dun/ts/strip.d` imports `skipRegexLit`, `charAllowsRegex`,
  and `regexAllowingKeywordEndsAt` from the lexer; the main-loop `/`
  branch now consumes regex literals instead of falling through to
  byte-by-byte walking. Closes the class of bugs where regex bodies
  containing `:` / `<` / `>` could trip the strip-mode heuristics
  (verified by `tests/integration/fixtures/ts_regex.ts`).

### Landed in this round

- **Private identifiers (`#name`)**. ES2022 class-private fields
  (`class C { #x = 0 }`) and references (`this.#x`) now produce a
  dedicated `T.private_identifier` token. Without this the lexer
  emitted `T.syntax_error` on every real `#x` reference; the
  `ts_parity/01_class_fields.ts` fixture wouldn't even tokenize.

- **Nested-template brace balancing**. The lexer now tracks brace
  depth per active template substitution (small fixed array
  `templateBraces[16]`) so `` `${ {x:1, y:2} }` `` correctly
  treats the inner `}` as object-literal close, not template
  terminator. Caps nesting at 16 (more than any real-world
  template chain).

- **Bun.spawn variadic + JSX-in-scope + bare-name module
  declarations** in the `--typecheck` ambient `.d.ts`
  (`source/dun/ts/globals_dts.d`). `Deno.*`, `Bun.*`,
  `require`, `process`, `Buffer`, `React`, and every
  `dun:` / `node:` / bare module specifier now typecheck
  cleanly without forcing the user to install `@types/node`.

- **Top-level await + JSX support** in the `--typecheck`
  driver (`opts.module = ESNext`, `moduleDetection = Force`,
  `jsx = React`). Without these, `denoapis.ts` and
  `reactapp.tsx` failed `--typecheck` with TS1375 / TS17004
  regardless of code correctness.

- **Lexer test coverage expansion**: 13 new unit-tests covering
  BigInt forms, all-escape strings, nested-template, recursive
  template, CRLF line tracking, multi-line block comments,
  multi-char operators, position tracking, reserved-word
  coverage, regex-after-reserved-word, all /v / /d / /y flag
  combos, multi-byte identifiers with combining marks,
  unterminated string / block-comment guards.

- **Cross-runtime conformance harness** at
  `tests/benchmarks/ts_parity/` (12 fixtures + `run.sh`)
  comparing DunJS output against `tsc + node`, Bun, Deno,
  and `node --experimental-strip-types`. DunJS (all 3
  backends) currently scores **12/12** matching the
  `tsc + node` gold standard, surpassing Bun (11/12, JSX
  config gap) and Node-ts (3/12, strip-only mode rejects
  enums/decorators/namespaces).

- **Lexer throughput micro-bench** (`tests/bench_lexer.d`).
  Measures the full `Lexer.next()` path against a naive
  byte-scanner. Current: lexer 184 MB/s vs scanner 1012 MB/s
  → **5.5× slower than the byte-scanner**, above the "2×"
  aspirational target. The cost is acceptable in absolute
  terms (≈0.1 ms per 20 KB file load); the gap reflects the
  real work the tokenizer does that the byte-scanner skips
  (keyword lookup, regex disambiguation, position emit).

### Still deferred

- Full Unicode ID_Start / ID_Continue tables (the permissive
  `>= 0x80` acceptance covers every valid identifier in real-world
  TS files; tightening to the spec ranges only matters when the
  lexer becomes the *validation* layer instead of the stripping
  layer).
- JSX/TSX expression-vs-tag mode switching (deferred until strip.d
  actually drives the tokenizer for JSX -- currently jsx.d has its
  own scanner).
- Replacing strip.d's nested `skipStringLit` / `skipTemplateLit`
  call sites (15+ inner scans inside namespace / interface / type
  alias handlers) with lexer-driven literal skipping. The
  top-level main-loop wiring is enough for observable correctness;
  the nested sites are TS-only declaration bodies that don't host
  regex literals in practice.

## Why we considered porting

DunJS today: `source/dun/ts/strip.d` is a **2,164-LOC scanner**
that erases TypeScript by whitespace-blanking ranges. Three more
scanner passes layer on top: `dun/ts/jsx.d` (JSX → React.createElement),
`dun/modules/esm_shim.d` (ESM ↔ CJS rewrite), and an upcoming
fourth would be needed for any further codegen work. Every
real-world TS file users have thrown at this codebase has surfaced
another scanner edge case — class fields, intra-enum refs,
multi-line conditional types, generic call sites, `satisfies`,
inline `type` modifiers in import lists, `this:` params, generic
arrows, `import = require()`, return-type `(…)=>T`, destructure
annotations, multi-line param props, etc. Cycle of scan → fix →
test → scan with no clear end.

Question: is replacing the scanner with a real parser worth the
investment?

## Source extent (Bun's parser, MIT, on `e750984`)

| Path | LOC |
|------|----:|
| `src/js_parser/p.zig` (Parser struct, ~400 methods) | 6,966 |
| `src/js_parser/lexer.zig` | 3,401 |
| `src/js_parser/parser.zig` (orchestration) | 1,277 |
| `src/js_parser/parse/parse_stmt.zig` | 1,407 |
| `src/js_parser/parse/parse_entry.zig` | 1,627 |
| `src/js_parser/parse/parse_prefix.zig` | 831 |
| `src/js_parser/parse/parse_suffix.zig` | 957 |
| `src/js_parser/parse/parse_property.zig` | 591 |
| `src/js_parser/parse/parse_fn.zig` | 508 |
| `src/js_parser/parse/parse_skip_typescript.zig` | **1,317** |
| `src/js_parser/parse/parse_typescript.zig` | **549** |
| `src/js_parser/parse/parse_jsx.zig` | **319** |
| `src/js_parser/typescript.zig` | **472** |
| `src/ast/{e,s,b,g,expr,stmt,op,ts,symbol,scope,logger}.zig` | ~13,000 |
| `src/js_printer/js_printer.zig` | 6,422 |
| **Total Zig parser + printer + AST** | **~44,600** |

(esbuild Go original: ~38,553 LOC. Bun is +15% due to comptime
parser specialization across the `(typescript, jsx, scan_only)`
matrix.)

**TS-only subset**: `parse_skip_typescript.zig` + `parse_typescript.zig`
+ `typescript.zig` + `ts.zig` + TS-tagged paths in `p.zig`/`parse_stmt.zig`
= **~4,500 LOC** of Zig.

**Minimum viable port** (strip-only, no bundler, no source maps):
~18,500 LOC Zig → **~22–25k LOC D** after idiom translation.

## License compatibility

All clean. Bun MIT, esbuild MIT, DunJS MIT. SWC alternative is
Apache-2 (NOTICE-file propagation needed).

## D porting hazards

The Zig→D direction is reasonably gentle. Translations:

| Zig | D | Notes |
|-----|---|------|
| Tagged union `union(enum)` | `std.sumtype.SumType` or hand-rolled tag + `union` | D's `std.variant.Algebraic` allocates — avoid; `sumtype` library or hand-roll |
| `comptime fn` returning a type | `template struct` with `bool`/`enum` params | One-to-one |
| `anyerror!T` | throw or `Result!T` sumtype | DunJS uses both depending on context |
| `std.mem.Allocator` | `std.experimental.allocator.Region!Mallocator` | Already in `dun.platform.arena` |
| `bun.BabyList(T)` | hand-roll 16-byte SBO list or `Appender!T` | `dun.platform.arena` has `Appender` |
| `packed struct(u8)` | `align(1)` + `std.bitmanip` or LDC bitfields | Verify size with `static assert` |
| String slices `[]const u8` | `const(char)[]` | DunJS convention matches |

Two real risks:
1. **Allocator discipline.** Bun arenas per file. Without the same
   discipline in D, the GC will allocate megabytes of AST per
   compilation. `dun.platform.arena.Region!Mallocator` is the
   right tool.
2. **Mutual recursion mass.** `p.zig` has ~400 methods on `P` —
   one giant struct. D needs either a single struct of 6–8k lines
   or `mixin template` splits.

## Effort (one engineer, knows JS spec)

| Task | Person-weeks |
|------|-------------:|
| Lexer port (Unicode tables, JSX/regex/template modes) | 2 |
| AST node definitions | 1 |
| Core parser (prefix/suffix/stmt/property/fn) | 3 |
| TS skipping path (~30 mutually-recursive `skipTypeScriptType*`) | 2 |
| TS lowering (enum/namespace/param-prop/`import = require`) | 1.5 |
| JSX/TSX parsing | 0.5 |
| Decorators (legacy + 2022) | 1 (or skip → 0) |
| Minimal printer | 1 |
| Integration + regression on `ts_compat` suite | 2 |
| **Total** | **~13–14 person-weeks** |

Plus 30–40% buffer for unknowns / ASan / triple-backend
validation → **3–5 calendar months** for one full-time engineer.

## SWC alternative

~38k LOC Rust across 51 files. Apache-2. Lifetimes + `Arc<Mutex>`
+ trait dispatch + macros don't translate cleanly to D — **port
distance is roughly 2× the Bun route**. Deno chose SWC because
both ends are Rust; that advantage doesn't transfer to D.

Reject SWC.

## Decision

**Full Bun parser port: NO-GO** for now. Reasoning:
- Scanner-only strip passes every fixture in the repo, every
  fixture the user supplied, and matches Bun on 4 of 6 entries in
  the ts_compat grid.
- ROI is poor: 3–5 months of work to replace a working component
  with one that produces the same observable output.
- Risk: new ~25k-LOC subsystem with arena lifetime constraints
  on every code path.

**Lexer-only lift: GO** as a follow-up project. Specifically:
1. Port `src/js_parser/lexer.zig` + `lexer_tables.zig` +
   `lexer/identifier.zig` → `source/dun/ts/parser/lexer.d`
   (~5,000 Zig → ~6,500 D).
2. Replace `strip.d`'s ad-hoc regex/divide/template-literal
   disambiguation with the real tokenizer.
3. Keep the existing whitespace-blanking strategy on top of the
   token stream — `strip.d` shrinks ~30% and becomes principled
   about token boundaries instead of byte boundaries.
4. ~5 person-weeks. Captures 80% of the correctness win for 30%
   of the effort.

**When to revisit a full AST port**:
- DunJS gets a bundling story (a printer is then non-optional).
- A user file lands that `strip.d` provably cannot fix in the
  scanner architecture (so far, every reported case has been
  patchable in <100 lines).

## Concrete vendor layout (if/when we proceed)

Following `vendor/lsquic/` pattern:

```
vendor/bun-parser/
  LICENSE.md          # copy from oven-sh/bun, MIT
  README.md           # provenance + pinned commit SHA
  zig/                # upstream reference, untouched
    src/js_parser/{lexer,lexer_tables}.zig
    src/js_parser/lexer/identifier.zig
    src/js_parser/parse/{parse_skip_typescript,parse_typescript,parse_jsx}.zig
    src/js_parser/{p,parser,typescript}.zig
    src/js_parser/parse/{parse_stmt,parse_prefix,parse_suffix,parse_property,parse_fn,parse_import_export,parse_entry}.zig
    src/ast/{e,s,b,g,op,expr,stmt,ts,symbol,scope,logger}.zig
```

Port destination:

```
source/dun/ts/parser/
  package.d            # public facade
  lexer.d              # ~3,500 LOC port (PHASE 1 — lexer-only)
  identifier_tables.d  # auto-generated Unicode tables
  # ── below this line is the full-port future state ──
  ast.d
  parser.d
  parse_stmt.d / parse_expr.d / parse_property.d / parse_fn.d
  skip_typescript.d
  ts_lower.d
  jsx.d                # subsumes the existing source/dun/ts/jsx.d
  emit.d
```

## Validation if proceeding (phase 1: lexer-only)

1. `bash tests/integration/run.sh` → 127/127 on QJS/JSC/V8.
2. `bash tests/benchmarks/ts_compat/compare.sh` → no regression on
   the 6 user fixtures.
3. New unit tests in `source/dun/ts/parser/lexer.d` ported from
   Bun's `lexer_test.zig` — aim for 30% test-LOC coverage.
4. ASan build (`dub build -c quickjs -b asan`) clean on
   `ts_compat`.
5. Bench: token-throughput stays within 2× of the byte-scanner
   (we expect a real lexer to be slower; document the cost).

## Files referenced

- `/home/user/dunjs/source/dun/ts/strip.d` (current scanner, 2,164 LOC)
- `/home/user/dunjs/source/dun/ts/jsx.d`
- `/home/user/dunjs/source/dun/ts/package.d`
- `/home/user/dunjs/source/dun/platform/arena.d` (allocator infra)
- `/home/user/dunjs/tests/benchmarks/ts_compat/{bunapis,denoapis,nodeapis,reactapp,tsadvanced,workerdemo}.{ts,tsx}` (1,883 LOC validation corpus)
- `/home/user/dunjs/vendor/lsquic/` (pattern to follow for vendoring)
