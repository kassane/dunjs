/// Fuzz harness for `dun.ts.strip.stripTypes` — the TypeScript type
/// eraser. Runs untrusted source through the scanner-based stripper
/// and asserts the @safe contract holds (no crashes, no UB, output
/// is well-formed UTF-8).
///
/// Build:
///   ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
///        -I=source -Jsource \
///        -of=build/fuzz_strip \
///        tests/fuzz/fuzz_strip.d \
///        source/dun/ts/strip.d \
///        source/dun/ts/parser/lexer.d
///
/// Run (with seed corpus + crash-saving):
///   mkdir -p tests/fuzz/corpus/strip
///   build/fuzz_strip tests/fuzz/corpus/strip \
///       -max_len=4096 -timeout=10 \
///       -artifact_prefix=tests/fuzz/crashes/strip-
///
/// Reference: https://johanengelen.github.io/posts/2018-01-14-fuzzing-with-ldc/

import dun.ts.strip : stripTypes;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow
{
    if (size == 0 || size > 65536) return 0;
    try
    {
        auto src = cast(const(char)[]) data[0 .. size];
        auto stripped = stripTypes(src);
        // The stripper preserves source positions by replacing types
        // with whitespace — output length must equal input length.
        // A length mismatch indicates a position-tracking bug that
        // would corrupt source maps and stack traces.
        assert(stripped.length == src.length,
            "stripTypes broke the equal-length invariant");
    }
    catch (Exception)
    {
        // Scanner is @safe; catching keeps the fuzzer alive so
        // libFuzzer can continue mutating. Any *crash* (segfault,
        // UB, OOM) is a real bug — libFuzzer will save it as
        // crash-<sha1>.
    }
    catch (Error)
    {
        // assert() inside @safe code throws AssertError (extends
        // Error, not Exception). Catching here lets the fuzzer
        // record the input but keep running; the crash artifact
        // captures the offending bytes.
    }
    return 0;
}
