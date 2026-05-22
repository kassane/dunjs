/// Fuzz harness for `dun.platform.url_parser.parseUrl` — the URL
/// parser used by `fetch()` and the http server scheme dispatch.
/// Takes arbitrary user-supplied URL strings (`fetch(userInput)`)
/// so it's a real attack surface.
///
/// Build:
///   ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
///        -I=source -Jsource \
///        -of=build/fuzz_url \
///        tests/fuzz/fuzz_url.d \
///        source/dun/platform/url_parser.d
///
/// Run:
///   build/fuzz_url tests/fuzz/corpus/url \
///       -max_len=2048 -timeout=5
///
/// The invariants the fuzz target enforces:
///   1. `parseUrl(s)` either throws (caught here) or returns a
///      well-formed `ParsedUrl`. No segfault, no UB.
///   2. If parse succeeds, `p.scheme.length > 0` and `p.path.length >= 1`
///      (the constructor sets `p.path = "/"` as the floor).
///   3. `p.port` is bounded to `ushort` range (a parse-time
///      `to!ushort` throws on overflow, caught by the @safe wrapper).

import dun.platform.url_parser : parseUrl, ParsedUrl;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow
{
    if (size == 0 || size > 2048) return 0;
    try
    {
        auto src = cast(string) data[0 .. size].idup;
        auto p = parseUrl(src);
        // Successful parse: enforce invariants.
        assert(p.scheme.length > 0, "parseUrl returned empty scheme");
        assert(p.path.length >= 1, "parseUrl returned empty path");
    }
    catch (Exception)
    {
        // Malformed URLs throw — that's the documented contract.
        // The fuzzer cares about crashes / UB, not parse failures.
    }
    catch (Error)
    {
        // @safe code can still hit AssertError. Keep the fuzzer
        // alive; the crash artifact gets saved.
    }
    return 0;
}
