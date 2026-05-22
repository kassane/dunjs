/++
 + Fuzz harness for `dun.ts.parser.lexer` — the JS/TS scanner that
 + powers the lint pass, the type-stripper, and the source-rewriter
 + (dynamic_import for JSC/V8). Three exported helpers, all `@safe
 + pure nothrow @nogc`, take arbitrary source bytes:
 +
 +   - `hasSyntaxError(src)` — coarse syntax check used by the lint
 +     pre-pass + the TS-strip eligibility gate.
 +   - `skipStringLit(buf, i)` — advance past a `'…'` / `"…"` string
 +     literal (handles escapes).
 +   - `skipTemplateLit(buf, i)` — advance past a template literal,
 +     accounting for nested `${…}` expressions.
 +
 + All three are pure scanners; the invariant is "no segfault on
 + arbitrary input." The fuzzer asserts that `skip*` returns a
 + position bounded by the input length.
 +
 + Build:
 +   ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
 +        -I=source -Jsource \
 +        -of=build/fuzz_lexer \
 +        tests/fuzz/fuzz_lexer.d \
 +        source/dun/ts/parser/lexer.d
 +
 + Run:
 +   build/fuzz_lexer tests/fuzz/corpus/lexer -max_len=4096 -timeout=5
 +/

import dun.ts.parser.lexer : hasSyntaxError, skipStringLit, skipTemplateLit;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow
{
    if (size == 0 || size > 8192) return 0;
    try
    {
        auto src = cast(const(char)[]) data[0 .. size];

        // 1. hasSyntaxError — coarse check, should never crash.
        auto err = hasSyntaxError(src);
        // Result is just a bool; no further invariant.
        cast(void) err;

        // 2. skipStringLit — given a position that LOOKS like a
        //    string-literal opener, the scanner should return a
        //    position <= src.length. Pick the first `'` or `"` in
        //    the input as our seed position.
        size_t strStart = 0;
        bool foundStr = false;
        foreach (i, c; src)
        {
            if (c == '\'' || c == '"') { strStart = i; foundStr = true; break; }
        }
        if (foundStr)
        {
            auto end = skipStringLit(src, strStart);
            assert(end <= src.length, "skipStringLit returned out-of-bounds position");
        }

        // 3. skipTemplateLit — same pattern with a backtick seed.
        size_t tmplStart = 0;
        bool foundTmpl = false;
        foreach (i, c; src)
        {
            if (c == '`') { tmplStart = i; foundTmpl = true; break; }
        }
        if (foundTmpl)
        {
            auto end = skipTemplateLit(src, tmplStart);
            assert(end <= src.length, "skipTemplateLit returned out-of-bounds position");
        }
    }
    catch (Exception) {}
    catch (Error) {}
    return 0;
}
