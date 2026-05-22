module dun.ts.parser;

// Lexer port from oven-sh/bun's `src/js_parser/` (Zig, MIT). The
// scanner pipeline (strip.d + jsx.d) consumes this for regex/divide
// disambiguation and shared string/template skipping. A full AST
// port is intentionally not pursued -- see `CLAUDE.md ## Won't-fix
// design constraints`.
public import dun.ts.parser.lexer;

/++
 + Tokenize the entire source into a GC-allocated array. Random-access
 + convenience for callers that want to look at the token stream as a
 + whole. Hot paths in the runtime should stream via `Lexer.next()` so
 + they stay `@nogc`. Lives here (not lexer.d) so it escapes the
 + module-level `@nogc` colon on the lexer.
 +/
Token[] tokenize(const(char)[] src) @safe pure nothrow
{
    Token[] o;
    o.reserve(src.length / 4 + 16);  // ~4 chars per token avg
    auto lx = Lexer(src);
    for (;;)
    {
        auto tk = lx.next();
        o ~= tk;
        if (tk.kind == T.eof) return o;
    }
}

unittest
{
    auto toks = tokenize("const x = 1 + 2;");
    // `const` `x` `=` `1` `+` `2` `;` `eof` = 8.
    assert(toks.length == 8);
    assert(toks[0].kind == T.t_const);
    assert(toks[1].kind == T.identifier && toks[1].text == "x");
    assert(toks[2].kind == T.equals);
    assert(toks[$ - 1].kind == T.eof);
    assert(!hasSyntaxError("const x = 1;"));
}

// Corpus validation -- run the lexer over the real-world TS fixtures
// from `tests/benchmarks/ts_compat/`. Each file must produce zero
// `syntax_error` tokens. This catches regressions where a new operator
// or escape sequence breaks tokenization on actual TS files we ship
// support for. The .tsx file is included; JSX tags are not yet
// lexed specially (deferred), so we only run it through up to the
// first `<` and back out -- but a `<` after a value-producing token
// is `T.less_than`, so even reactapp.tsx tokenizes through cleanly.
unittest
{
    static immutable string[] fixtures = [
        "bunapis.ts",
        "denoapis.ts",
        "nodeapis.ts",
        "tsadvanced.ts",
        "workerdemo.ts",
        "reactapp.tsx",
        // ts_parity/ conformance fixtures (added 2026-05-17).
        "01_class_fields.ts",
        "02_enum_namespace.ts",
        "03_generics.ts",
        "04_destructure_types.ts",
        "05_modifiers.ts",
        "06_regex_in_ts.ts",
        "07_typeonly_imports.ts",
        "08_template_types.ts",
        "09_async_iter.ts",
        "10_decorators.ts",
        "11_using.ts",
        "12_jsx.tsx",
    ];
    static foreach (name; fixtures)
    {{
        auto src = import(name);
        assert(!hasSyntaxError(src),
            "lexer produced syntax_error tokens on " ~ name);
        // Also make sure the stream terminates and the token count
        // grows roughly linearly with source size (catches infinite
        // loops in scanner state machines).
        auto toks = tokenize(src);
        assert(toks.length > src.length / 64,
            "suspiciously few tokens on " ~ name);
        assert(toks[$ - 1].kind == T.eof);
    }}
}
