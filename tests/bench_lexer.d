/// Throughput micro-bench for the TS lexer: tokens per second vs the
/// raw byte-scanner that strip.d used before the lexer wiring. The
/// TS-PARSER-PORT.md validation criterion is "stays within 2x of the
/// byte-scanner" — measure it.
///
/// Build:  ldc2 -O3 -release -of=bench_lexer tests/bench_lexer.d source/dun/ts/parser/{lexer,package}.d
/// Run:    ./bench_lexer [path/to/corpus.ts]   (defaults to a synthetic corpus)
module bench_lexer;

import std.datetime.stopwatch : StopWatch, AutoStart;
import std.file : readText, exists;
import std.stdio : writefln, writeln;
import std.format : format;

import dun.ts.parser.lexer;
import dun.ts.parser;

enum int WARMUP_ITERATIONS = 5;
enum int MEASURE_ITERATIONS = 100;

void main(string[] args) @safe
{
    string[] corpora;
    if (args.length > 1)
        corpora = args[1 .. $];
    else
    {
        // Default corpus: the ts_compat fixtures.
        static immutable string[] defaults = [
            "tests/benchmarks/ts_compat/bunapis.ts",
            "tests/benchmarks/ts_compat/denoapis.ts",
            "tests/benchmarks/ts_compat/nodeapis.ts",
            "tests/benchmarks/ts_compat/tsadvanced.ts",
            "tests/benchmarks/ts_compat/workerdemo.ts",
            "tests/benchmarks/ts_compat/reactapp.tsx",
        ];
        foreach (p; defaults) if (exists(p)) corpora ~= p;
    }

    writefln("%-46s %-14s %-14s %-14s",
        "file", "bytes", "lexer MB/s", "byte-scan MB/s");
    writefln("%s", "------------------------------------------------" ~
        "----------------------------------------");

    size_t totalBytes = 0;
    double totalLexMs = 0;
    double totalScanMs = 0;

    foreach (path; corpora)
    {
        auto src = readText(path);
        totalBytes += src.length;

        // Warmup.
        foreach (_; 0 .. WARMUP_ITERATIONS) runLexer(src);
        foreach (_; 0 .. WARMUP_ITERATIONS) runByteScan(src);

        // Lexer pass.
        auto sw = StopWatch(AutoStart.yes);
        foreach (_; 0 .. MEASURE_ITERATIONS) runLexer(src);
        sw.stop();
        auto lexMs = sw.peek().total!"usecs" / 1000.0;

        // Byte-scanner baseline.
        sw.reset(); sw.start();
        foreach (_; 0 .. MEASURE_ITERATIONS) runByteScan(src);
        sw.stop();
        auto scanMs = sw.peek().total!"usecs" / 1000.0;

        // MB/s based on total bytes processed across all iterations.
        auto totalMb = (cast(double) src.length * MEASURE_ITERATIONS) / (1024 * 1024);
        auto lexMBps = totalMb / (lexMs / 1000.0);
        auto scanMBps = totalMb / (scanMs / 1000.0);

        totalLexMs += lexMs;
        totalScanMs += scanMs;

        // Strip "tests/benchmarks/" prefix for readability if present.
        string label = path;
        immutable prefix = "tests/benchmarks/";
        if (label.length > prefix.length && label[0 .. prefix.length] == prefix)
            label = label[prefix.length .. $];

        writefln("%-46s %-14s %-14s %-14s",
            label,
            format("%d", src.length),
            format("%.1f", lexMBps),
            format("%.1f", scanMBps));
    }

    writeln();
    auto totalMb = (cast(double) totalBytes * MEASURE_ITERATIONS) / (1024 * 1024);
    auto lexAvg = totalMb / (totalLexMs / 1000.0);
    auto scanAvg = totalMb / (totalScanMs / 1000.0);
    writefln("Total: %.1f MB/iter,  lexer %.1f MB/s,  byte-scan %.1f MB/s,  ratio %.2fx",
        cast(double) totalBytes / (1024 * 1024),
        lexAvg, scanAvg, scanAvg / lexAvg);
    writefln("Target per TS-PARSER-PORT.md: lexer stays within 2x of byte-scanner.");
}

// Drive the full Lexer.next() loop until EOF. Returns the token count
// so the compiler can't optimise the call away.
size_t runLexer(const(char)[] src) @safe pure nothrow @nogc
{
    auto lx = Lexer(src);
    size_t n = 0;
    for (;;)
    {
        auto t = lx.next();
        n++;
        if (t.kind == T.eof) return n;
    }
}

// Mirror what dun.ts.strip's old top-level loop did: walk bytes,
// recognising strings / templates / line / block comments so we account
// for the same skip work the lexer does — otherwise the comparison is
// a "scanner that does nothing" vs "lexer that does everything".
size_t runByteScan(const(char)[] src) @safe pure nothrow @nogc
{
    size_t i = 0;
    size_t emitted = 0;
    while (i < src.length)
    {
        char c = src[i];
        if (c == '"' || c == '\'')
        {
            char q = c; i++;
            while (i < src.length)
            {
                if (src[i] == '\\' && i + 1 < src.length) { i += 2; continue; }
                if (src[i] == q) { i++; break; }
                i++;
            }
            emitted++;
            continue;
        }
        if (c == '`')
        {
            i++;
            while (i < src.length)
            {
                if (src[i] == '\\' && i + 1 < src.length) { i += 2; continue; }
                if (src[i] == '`') { i++; break; }
                i++;
            }
            emitted++;
            continue;
        }
        if (c == '/' && i + 1 < src.length && src[i + 1] == '/')
        {
            while (i < src.length && src[i] != '\n') i++;
            continue;
        }
        if (c == '/' && i + 1 < src.length && src[i + 1] == '*')
        {
            i += 2;
            while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) i++;
            if (i + 1 < src.length) i += 2;
            continue;
        }
        i++;
        emitted++;
    }
    return emitted;
}
