# Plan: TS parser path forward (research outcome + kickoff)

**Status**: research complete + lexer kickoff landed. Decision
documented; first slice of D code in `source/dun/ts/parser/`.
**Recommendation**: **NO-GO** on a full Bun-parser port now.
**GO** on a focused **lexer-only lift** as a follow-up (~5
person-weeks, kills the parsing edge cases scanner-strip keeps
re-discovering, leaves the door open for a full AST port later).

## What's in the tree so far

- `vendor/bun-parser/zig/src/js_parser/{lexer,lexer_tables}.zig` —
  upstream Zig sources vendored for diff reference. MIT-licensed.
- `source/dun/ts/parser/lexer.d` — partial D port:
  * Full `T : ubyte` token enum (matches Bun's `pub const T = enum(u8)`)
  * `Lexer` struct with `next()` + line/col tracking
  * Identifiers (ASCII + `$` / `_`), keywords (35 reserved-word table),
    numeric literals (decimal, hex, oct, bin, numeric separators, `.`,
    exponent), strings (`"…"`, `'…'` with `\` escape), single-line +
    block comments, hashbang
  * All single-char punctuation + the multi-char operator set
    `=== !== ??= ??. ?. **= >>>= …` (~40 operators)
  * 6 inline unittests covering every category above
- `source/dun/ts/parser/package.d` — re-export.

Not yet in this slice (next chunks):
- Template literals (`` ` `` + `${…}`)
- Regex vs divide disambiguation (needs parser feedback signal)
- Unicode identifier ranges beyond ASCII
- JSX/TSX mode switching
- BigInt suffix `n`

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

1. `bash tests/integration/run.sh` → 121/121 on QJS/JSC/V8.
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
