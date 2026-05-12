module dun.platform.arena;

public import std.experimental.allocator.building_blocks.region :
    Region, BorrowedRegion, InSituRegion;
public import std.experimental.allocator.mallocator : Mallocator;

alias BumpRegion = Region!Mallocator;

static assert(BumpRegion.alignment > 0);

BumpRegion makeBumpRegion(size_t capacity) @trusted pure nothrow @nogc
{
    assert(capacity > 0);
    return BumpRegion(capacity);
}

T[] regionAlloc(T, Alloc)(ref Alloc alloc, size_t count) @trusted pure nothrow @nogc
{
    assert(count > 0);
    auto bytes = alloc.allocate(T.sizeof * count);
    if (bytes is null) return null;
    return (cast(T*) bytes.ptr)[0 .. count];
}
