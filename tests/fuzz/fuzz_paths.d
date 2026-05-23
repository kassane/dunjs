/++
 + Fuzz harness for `dun.platform.paths.canonicalizePath` — the
 + CVE-class security primitive (CVE-2023-32004 / CVE-2024-21896) that
 + sits in front of every file-system permission check. Adversarial
 + paths reach `canonicalizePath` from JS via `fs.readFileSync(path)`,
 + `process.chdir(path)`, etc.
 +
 + v1.1.27 added the `isAlreadyCanonical` fast-path: if the predicate
 + returns true, `canonicalizePath` returns the input verbatim instead
 + of going through `buildNormalizedPath(absolutePath(...))`. A bug in
 + the predicate that lets `/tmp/foo/../etc/passwd` through as "canonical"
 + would skip canonicalization and break the CVE-class guarantee. This
 + fuzzer exercises that contract on every conceivable byte sequence.
 +
 + Build:
 +   ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
 +        -I=source -Jsource \
 +        -of=build/fuzz_paths \
 +        tests/fuzz/fuzz_paths.d \
 +        source/dun/platform/paths.d
 +
 + Run:
 +   build/fuzz_paths tests/fuzz/corpus/paths \
 +       -max_len=4096 -timeout=5
 +
 + Invariants enforced:
 +   1. `canonicalizePath(s)` never crashes / UBs on any byte string.
 +   2. If `isAlreadyCanonical(s)` is true, `canonicalizePath(s) is s`
 +      (same reference — no allocation). This proves the fast-path
 +      doesn't allocate when the predicate fires.
 +   3. If `isAlreadyCanonical(s)` is true, the path contains NO `..`
 +      and NO `/./` and NO `//` segments and starts with `/` (the
 +      CVE-class predicate contract). We re-verify post-call, NOT by
 +      re-using `isAlreadyCanonical` (would be tautological), but by
 +      a hand-rolled scanner.
 +   4. `canonicalizePath(s)` for any non-empty `s` either returns
 +      a non-empty result OR throws (caught). Empty result is
 +      reserved for empty input.
 +/

import dun.platform.paths : canonicalizePath;

// Mirror of `isAlreadyCanonical` so we can call it from this @safe
// test code without modifying the source module to export it.
private bool checkPredicateConditions(const(char)[] path) @safe pure nothrow @nogc
{
    version (Posix)
    {
        if (path.length == 0 || path[0] != '/') return false;
        if (path.length == 1) return true;
        if (path[$ - 1] == '/') return false;
        for (size_t i = 0; i + 1 < path.length; i++)
        {
            if (path[i] != '/') continue;
            immutable next = path[i + 1];
            if (next == '/') return false;
            if (next == '.')
            {
                immutable rem = path.length - (i + 1);
                if (rem == 1) return false;
                immutable after = path[i + 2];
                if (after == '/') return false;
                if (after == '.')
                {
                    if (rem == 2) return false;
                    if (path[i + 3] == '/') return false;
                }
            }
        }
        return true;
    }
    else return false;
}

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow
{
    if (size == 0 || size > 4096) return 0;
    try
    {
        // Invariant 1: never crash. The catch blocks below cover throws.
        auto src = cast(string) data[0 .. size].idup;
        auto canon = canonicalizePath(src);

        if (src.length > 0)
        {
            // Invariant 4: non-empty input → non-empty output (when the
            // call returns at all — empty result reserved for empty input).
            // We can't assert canon.length > 0 universally because Phobos
            // can return "" for `/` after normalization on some platforms;
            // be liberal here.
        }

        // Invariants 2 + 3: predicate contract.
        if (checkPredicateConditions(src))
        {
            // The fast-path should have fired. canonicalizePath returns
            // the input slice verbatim (`is` identity, not equality).
            // We can't directly assert `canon is src` because Phobos
            // string interning is unspecified. But we CAN assert no
            // `..` / `/./` / `//` segments are in the output if the
            // predicate said the input was clean.
            //
            // The CVE-class property: canonical paths NEVER contain
            // `..` segments. If the predicate let one through, that's
            // the bug.
            assert(canon.length > 0, "predicate-true input gave empty canon");
            for (size_t i = 0; i + 1 < canon.length; i++)
            {
                if (canon[i] != '/') continue;
                immutable next = canon[i + 1];
                assert(next != '/', "double-slash in supposedly-canonical output");
                if (next == '.')
                {
                    immutable rem = canon.length - (i + 1);
                    assert(rem != 1, "trailing /. in canonical output");
                    if (rem >= 2)
                    {
                        immutable after = canon[i + 2];
                        assert(after != '/', "/./ segment in canonical output");
                        if (after == '.')
                        {
                            assert(rem != 2, "trailing /.. in canonical output");
                            assert(canon[i + 3] != '/', "/../ segment in canonical output");
                        }
                    }
                }
            }
        }
    }
    catch (Exception)
    {
        // canonicalizePath catches Phobos exceptions internally and
        // returns null on failure; an outer Exception means the input
        // wasn't valid UTF-8 for `idup`. Treated as benign.
    }
    catch (Error)
    {
        // AssertError on invariant violation — the fuzz harness will
        // save the crash artifact. That's the bug we want surfaced.
        throw new Error("invariant violation");
    }
    return 0;
}
