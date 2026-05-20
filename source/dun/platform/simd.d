module dun.platform.simd;

/// SIMD-accelerated primitives for hot paths.
/// Uses LDC intrinsics (loadUnaligned, storeUnaligned, shufflevector) when
/// available; falls back to core.simd pointer casts, then scalar.

version (D_SIMD)
{
    import core.simd : ubyte16, byte16;

    version (LDC)
    {
        import ldc.simd : loadUnaligned, storeUnaligned, shufflevector;
        import ldc.intrinsics : llvm_cttz, llvm_prefetch;

        pragma(inline, true)
        private ubyte16 simdLoad(const(ubyte)* p) pure nothrow @nogc @trusted
        {
            return loadUnaligned!ubyte16(p);
        }

        pragma(inline, true)
        private void simdStore(ubyte* p, ubyte16 v) pure nothrow @nogc @trusted
        {
            storeUnaligned!ubyte16(v, p);
        }
    }
    else
    {
        pragma(inline, true)
        private ubyte16 simdLoad(const(ubyte)* p) pure nothrow @nogc @trusted
        {
            return *cast(const(ubyte16)*) p;
        }

        pragma(inline, true)
        private void simdStore(ubyte* p, ubyte16 v) pure nothrow @nogc @trusted
        {
            *cast(ubyte16*) p = v;
        }
    }

    pragma(inline, true)
    private ubyte16 splat(ubyte val) pure nothrow @nogc @trusted
    {
        ubyte[16] a = val;
        return *cast(ubyte16*) a.ptr;
    }

    pragma(inline, true)
    ubyte16 toLower16(ubyte16 v) pure nothrow @nogc @trusted
    {
        auto mask = cast(ubyte16)((v >= splat('A')) & (v <= splat('Z')));
        return v | (mask & splat(0x20));
    }

    pragma(inline, true)
    ubyte16 toUpper16(ubyte16 v) pure nothrow @nogc @trusted
    {
        auto mask = cast(ubyte16)((v >= splat('a')) & (v <= splat('z')));
        return v & ~(mask & splat(0x20));
    }

    pragma(inline, true)
    ubyte16 nibblesToHex16(ubyte16 nibbles) pure nothrow @nogc @trusted
    {
        auto gt9 = cast(ubyte16)(nibbles > splat(9));
        auto digitBase = (~gt9) & splat('0');
        auto alphaBase = gt9 & splat(cast(ubyte)('a' - 10));
        return nibbles + (digitBase | alphaBase);
    }

    void asciiToLowerBuf(char[] buf) pure nothrow @nogc @trusted
    {
        size_t i = 0;
        for (; i + 16 <= buf.length; i += 16)
        {
            auto v = simdLoad(cast(const(ubyte)*)(buf.ptr + i));
            simdStore(cast(ubyte*)(buf.ptr + i), toLower16(v));
        }
        for (; i < buf.length; i++)
            if (buf[i] >= 'A' && buf[i] <= 'Z')
                buf[i] |= 0x20;
    }

    void hexEncodeBuf(const(ubyte)[] src, char[] dst) pure nothrow @nogc @trusted
    {
        assert(dst.length >= src.length * 2, "dst too small for hex encoding");
        size_t i = 0;
        for (; i + 16 <= src.length; i += 16)
        {
            auto input = simdLoad(src.ptr + i);
            auto hi = input >> 4;
            auto lo = input & splat(0x0F);
            auto hiHex = nibblesToHex16(hi);
            auto loHex = nibblesToHex16(lo);

            version (LDC)
            {
                // SIMD interleave: [h0,l0,h1,l1,...,h7,l7] then [h8,l8,...,h15,l15]
                auto interLo = shufflevector!(ubyte16,
                    0,16, 1,17, 2,18, 3,19, 4,20, 5,21, 6,22, 7,23)(hiHex, loHex);
                auto interHi = shufflevector!(ubyte16,
                    8,24, 9,25, 10,26, 11,27, 12,28, 13,29, 14,30, 15,31)(hiHex, loHex);
                simdStore(cast(ubyte*)(dst.ptr + i * 2), interLo);
                simdStore(cast(ubyte*)(dst.ptr + i * 2 + 16), interHi);
            }
            else
            {
                auto hPtr = cast(const(ubyte)*) &hiHex;
                auto lPtr = cast(const(ubyte)*) &loHex;
                foreach (j; 0 .. 16)
                {
                    dst[(i + j) * 2]     = cast(char) hPtr[j];
                    dst[(i + j) * 2 + 1] = cast(char) lPtr[j];
                }
            }
        }
        enum lut = "0123456789abcdef";
        for (; i < src.length; i++)
        {
            dst[i * 2]     = lut[src[i] >> 4];
            dst[i * 2 + 1] = lut[src[i] & 0xF];
        }
    }

    size_t findByte(const(ubyte)[] buf, ubyte needle) pure nothrow @nogc @trusted
    {
        auto target = splat(needle);
        size_t i = 0;
        for (; i + 16 <= buf.length; i += 16)
        {
            auto v = simdLoad(buf.ptr + i);
            auto eq = cast(ubyte16)(v == target);

            version (LDC)
            {
                // Convert SIMD mask to bitmask via movemask-equivalent
                auto eqBytes = cast(ubyte[16]) eq;
                ulong lo = *cast(ulong*)(eqBytes.ptr);
                ulong hi = *cast(ulong*)(eqBytes.ptr + 8);
                if (lo != 0)
                    return i + llvm_cttz(lo, true) / 8;
                if (hi != 0)
                    return i + 8 + llvm_cttz(hi, true) / 8;
            }
            else
            {
                auto eqPtr = cast(const(ubyte)*) &eq;
                foreach (j; 0 .. 16)
                    if (eqPtr[j] != 0) return i + j;
            }
        }
        for (; i < buf.length; i++)
            if (buf[i] == needle) return i;
        return buf.length;
    }

    void prefetchRead(const(void)* ptr) pure nothrow @nogc @trusted
    {
        version (LDC)
            llvm_prefetch(ptr, 0, 3, 1);
    }
}
else
{
    void asciiToLowerBuf(char[] buf) pure nothrow @nogc @safe
    {
        foreach (ref c; buf)
            if (c >= 'A' && c <= 'Z')
                c |= 0x20;
    }

    void hexEncodeBuf(const(ubyte)[] src, char[] dst) pure nothrow @nogc @trusted
    {
        assert(dst.length >= src.length * 2);
        enum lut = "0123456789abcdef";
        foreach (i, b; src)
        {
            dst[i * 2]     = lut[b >> 4];
            dst[i * 2 + 1] = lut[b & 0xF];
        }
    }

    size_t findByte(const(ubyte)[] buf, ubyte needle) pure nothrow @nogc @safe
    {
        foreach (i, b; buf)
            if (b == needle) return i;
        return buf.length;
    }
}

// Byte-swap intrinsics (LDC: single bswap instruction; fallback: manual shift)
ushort bswap16(ushort val) pure nothrow @nogc @safe
{
    version (LDC)
    {
        import ldc.intrinsics : llvm_bswap;
        return llvm_bswap(val);
    }
    else
        return cast(ushort)((val >> 8) | (val << 8));
}

uint bswap32(uint val) pure nothrow @nogc @safe
{
    version (LDC)
    {
        import ldc.intrinsics : llvm_bswap;
        return llvm_bswap(val);
    }
    else
        return (val >> 24) | ((val >> 8) & 0xFF00) |
               ((val << 8) & 0xFF_0000) | (val << 24);
}

ulong bswap64(ulong val) pure nothrow @nogc @safe
{
    version (LDC)
    {
        import ldc.intrinsics : llvm_bswap;
        return llvm_bswap(val);
    }
    else
        return (val >> 56) | ((val >> 40) & 0xFF00) |
               ((val >> 24) & 0xFF_0000) | ((val >> 8) & 0xFF00_0000) |
               ((val << 8) & 0xFF_0000_0000) | ((val << 24) & 0xFF00_0000_0000) |
               ((val << 40) & 0xFF_0000_0000_0000) | (val << 56);
}

/// SIMD-accelerated hex encoder returning a heap-allocated char[].
/// Single allocation + SIMD path (when LDC) for sizes ≥ 16. Use this
/// in place of `std.digest.toHexString!(LetterCase.lower)(buf).idup`
/// — saves one allocation (no `.idup` immutable copy) and uses the
/// 16-byte/cycle SIMD interleave path.
char[] hexEncode(const(ubyte)[] src) @trusted
{
    auto dst = new char[src.length * 2];
    hexEncodeBuf(src, dst);
    return dst;
}

/// Compile-time-sized variant: stack-allocates the destination so
/// callers with a known-N input (GCM tag = 16 bytes, SHA-256 = 32,
/// etc.) skip the GC allocation entirely. Returns by value; callers
/// can either keep the returned `char[2*N]` array on the stack or
/// hand the slice straight to `engine.newString` (copies into engine
/// storage synchronously, before the stack frame unwinds).
char[2 * N] hexEncodeFixed(size_t N)(scope const ubyte[N] src)
    pure nothrow @nogc @trusted
{
    char[2 * N] dst = void;
    hexEncodeBuf(src[], dst[]);
    return dst;
}

unittest
{
    // toLower
    char[32] buf = "Content-Type: Application/JSON\r\n";
    asciiToLowerBuf(buf[]);
    assert(buf[] == "content-type: application/json\r\n");

    // hexEncode
    const(ubyte)[4] data = [0xDE, 0xAD, 0xBE, 0xEF];
    char[8] hex;
    hexEncodeBuf(data[], hex[]);
    assert(hex[] == "deadbeef");

    // hexEncode 16+ bytes (SIMD path)
    ubyte[20] big;
    foreach (i, ref b; big) b = cast(ubyte) i;
    char[40] bigHex;
    hexEncodeBuf(big[], bigHex[]);
    assert(bigHex[0 .. 8] == "00010203");
    assert(bigHex[32 .. 40] == "10111213");

    // hexEncode heap variant
    const(ubyte)[] dynData = [0xDE, 0xAD, 0xBE, 0xEF];
    assert(hexEncode(dynData) == "deadbeef");

    // hexEncodeFixed CTFE-sized variant
    ubyte[4] fxData = [0xDE, 0xAD, 0xBE, 0xEF];
    auto fxHex = hexEncodeFixed(fxData);
    assert(fxHex[] == "deadbeef");

    // findByte
    const(ubyte)[] haystack = cast(const(ubyte)[]) "hello\nworld";
    assert(findByte(haystack, '\n') == 5);
    assert(findByte(haystack, 'z') == haystack.length);

    // bswap
    assert(bswap16(0x0102) == 0x0201);
    assert(bswap16(0xDEAD) == 0xADDE);
    assert(bswap32(0x01020304) == 0x04030201);
    assert(bswap32(0xDEADBEEF) == 0xEFBEADDE);
    assert(bswap64(0x0102030405060708) == 0x0807060504030201);
}
