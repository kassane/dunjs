# Vendored Bun parser sources

Reference copies of the Zig sources we're porting to D. Tracked in
git so the D port (`source/dun/ts/parser/`) can be diffed against
the upstream as Bun evolves.

**Source**: https://github.com/oven-sh/bun (MIT, see LICENSE.md)

**Fetched**: 2026-05-17 from `main`

## Files

| Vendored file | Upstream path | Status of D port |
|---------------|---------------|------------------|
| `zig/src/js_parser/lexer.zig` | `src/js_parser/lexer.zig` | partial (`source/dun/ts/parser/lexer.d`) |
| `zig/src/js_parser/lexer_tables.zig` | `src/js_parser/lexer_tables.zig` | partial (token enum, keyword table) |

See `TS-PARSER-PORT.md` at the repo root for the multi-phase plan
and effort estimate.

## Update recipe

```sh
curl -L https://github.com/oven-sh/bun/raw/main/src/js_parser/lexer.zig \
    -o vendor/bun-parser/zig/src/js_parser/lexer.zig
curl -L https://github.com/oven-sh/bun/raw/main/src/js_parser/lexer_tables.zig \
    -o vendor/bun-parser/zig/src/js_parser/lexer_tables.zig
```

After updating, diff the D port against the new Zig and add any new
token kinds / lexer states to `source/dun/ts/parser/lexer.d`.
