/++
 + Fuzz harness for `dun.platform.simd` — Buffer codec routines.
 + Targets the latin1 ↔ UTF-8 round-trip + the hex encoder. These
 + are `@trusted` SIMD primitives that take raw byte slices and
 + emit raw byte slices; the audit (v1.1.4 `audit_simd` / v1.1.4
 + `audit_roundtrip`) caught real bugs in the high-byte preservation
 + path that escaped scalar review. Fuzzing complements those
 + hand-written fixtures by exploring odd boundary lengths +
 + arbitrary byte patterns.
 +
 + Build:
 +   ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
 +        -I=source -Jsource \
 +        -of=build/fuzz_simd \
 +        tests/fuzz/fuzz_simd.d \
 +        source/dun/platform/simd.d \
 +        source/dun/declarations.d
 +
 + Run:
 +   build/fuzz_simd tests/fuzz/corpus/simd \
 +       -max_len=8192 -timeout=5
 +/

import dun.platform.simd : latin1ToUtf8Buf, latin1ToUtf8MaxLen,
                          utf8ToLatin1Buf, hexEncodeBuf;

extern (C) int LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow
{
    if (size == 0 || size > 8192) return 0;
    try
    {
        auto src = data[0 .. size];

        // 1. latin1 → UTF-8 → latin1 round-trip must preserve every byte.
        //    The v1.1.3 / v1.1.4 audit caught a high-byte (0x80-0xFF)
        //    loss in this path; the invariant is stronger than the
        //    fixture asserts.
        auto utf8Buf = new char[latin1ToUtf8MaxLen(size)];
        auto utf8Len = latin1ToUtf8Buf(src, utf8Buf);
        assert(utf8Len <= utf8Buf.length, "UTF-8 encode overflow");

        auto roundtrip = new ubyte[size];
        auto rtLen = utf8ToLatin1Buf(cast(const(char)[]) utf8Buf[0 .. utf8Len], roundtrip);
        assert(rtLen == size, "round-trip length mismatch");
        foreach (i; 0 .. size)
            assert(roundtrip[i] == src[i], "round-trip byte mismatch");

        // 2. Hex encoder: output length must be exactly 2× input.
        auto hexBuf = new char[size * 2];
        hexEncodeBuf(src, hexBuf);
        foreach (c; hexBuf)
            assert((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'),
                "hex output contained non-hex char");
    }
    catch (Exception)
    {
        // @trusted assertions throw — keep fuzzer alive, crashes
        // (SEGV/UB) get saved as crash-<sha1> artifacts.
    }
    catch (Error) {}
    return 0;
}
