module dun.platform.simd;

/// SIMD-accelerated primitives for hot paths.
/// Maps to SSE2 (x86-64) or NEON (AArch64) via core.simd.
/// Scalar fallback when SIMD is unavailable.

version (D_SIMD)
{
    import core.simd : ubyte16, byte16;

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
            auto v = *cast(ubyte16*)(buf.ptr + i);
            *cast(ubyte16*)(buf.ptr + i) = toLower16(v);
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
            auto input = *cast(const(ubyte16)*)(src.ptr + i);
            auto hi = input >> 4;
            auto lo = input & splat(0x0F);
            auto hiHex = nibblesToHex16(hi);
            auto loHex = nibblesToHex16(lo);
            auto hPtr = cast(const(ubyte)*) &hiHex;
            auto lPtr = cast(const(ubyte)*) &loHex;
            foreach (j; 0 .. 16)
            {
                dst[(i + j) * 2]     = cast(char) hPtr[j];
                dst[(i + j) * 2 + 1] = cast(char) lPtr[j];
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
            auto v = *cast(const(ubyte16)*)(buf.ptr + i);
            auto eq = cast(ubyte16)(v == target);
            auto eqPtr = cast(const(ubyte)*) &eq;
            foreach (j; 0 .. 16)
                if (eqPtr[j] != 0) return i + j;
        }
        for (; i < buf.length; i++)
            if (buf[i] == needle) return i;
        return buf.length;
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

    // findByte
    const(ubyte)[] haystack = cast(const(ubyte)[]) "hello\nworld";
    assert(findByte(haystack, '\n') == 5);
    assert(findByte(haystack, 'z') == haystack.length);
}
