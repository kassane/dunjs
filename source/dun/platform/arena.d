module dun.platform.arena;


/++
 + `@trusted policy`: arena/bump allocator wrappers — re-exports
 + `std.experimental.allocator` primitives with the `@nogc pure
 + nothrow` decorations the hot paths need. The `@trusted` is to
 + localize the @nogc boundary; see `dun.builtins.crypto` and
 + `dun.builtins.buffer` for callers.
 +/
public import std.experimental.allocator.building_blocks.region :
    Region, BorrowedRegion, InSituRegion;
public import std.experimental.allocator.mallocator : Mallocator;
public import std.array : Appender;

alias BumpRegion = Region!Mallocator;

static assert(BumpRegion.alignment > 0);

/++
 + `@trusted`: `Region!Mallocator` constructor is @safe in Phobos; the
 + wrapper exists to localize the `@nogc` boundary so callers can stay
 + in `@nogc nothrow` hot paths without a separate trusted lambda.
 +/
BumpRegion makeBumpRegion(size_t capacity) @trusted pure nothrow @nogc
{
    assert(capacity > 0);
    return BumpRegion(capacity);
}

/++
 + `@trusted`: pointer-cast from `void[]` to `T[]` after a successful
 + allocator call. The allocator guarantees `bytes.length >= T.sizeof * count`
 + and the cast preserves the byte sequence — well-defined per
 + `std.experimental.allocator` documentation. The early `null` return
 + shortcuts a degenerate alloc-failure path.
 +/
T[] regionAlloc(T, Alloc)(ref Alloc alloc, size_t count) @trusted pure nothrow @nogc
{
    assert(count > 0);
    auto bytes = alloc.allocate(T.sizeof * count);
    if (bytes is null) return null;
    return (cast(T*) bytes.ptr)[0 .. count];
}

Appender!(T[]) makeAppender(T)(size_t reserveCapacity = 0)
{
    Appender!(T[]) app;
    if (reserveCapacity > 0)
        app.reserve(reserveCapacity);
    return app;
}

/++
 + Stack-first, heap-fallback bulk allocator — mirrors the
 + `std.heap.stackFallback(N, default_allocator)` pattern Bun uses
 + across its node bindings (`node_assert_binding.zig`,
 + `node_os.zig`, `node_process.zig`, etc.) for per-call scratch
 + buffers. The first `N` bytes come off the function's stack via
 + `InSituRegion!N`; once that fills, allocations spill to the GC
 + heap. Per-call scopes that allocate a few small strings (paths,
 + header values, /proc/* parsing) stay entirely on the stack for
 + the common case, and silently grow to heap when the input is
 + unusually large.
 +
 + We pair `InSituRegion` with GC `new[]` overflow (rather than
 + `FallbackAllocator!(InSituRegion, Mallocator)`) so that the
 + caller doesn't have to bookkeep heap-spilled blocks individually
 + — the GC reclaims them when the slice references drop. Calling
 + `deallocateAll()` resets the stack region; GC-spilled blocks fall
 + out of scope naturally.
 +
 + Usage:
 + ```
 + import dun.platform.arena : StackFallback;
 + StackFallback!4096 sfb;
 + scope(exit) sfb.deallocateAll();
 + auto buf = sfb.allocate(needed);
 + // ... use `buf` ...
 + ```
 +/
struct StackFallback(size_t N)
{
    static assert(N > 0, "StackFallback!N requires N > 0");

    /++
     + Non-copyable: copying would alias the stack region across
     + frames and the GC heap pointer, defeating the whole point
     + of the type. Pass by `ref` if you need to share.
     +/
    @disable this(this);

    InSituRegion!N primary;

    /++
     + Returns a slice of `bytes` from the stack region when it
     + fits, otherwise from the GC heap. Returns `null` only for a
     + 0-byte request or under GC `OutOfMemoryError`. Caller must
     + not retain the stack-portion slice past `deallocateAll()` /
     + scope exit.
     +/
    void[] allocate(size_t bytes) @trusted nothrow
    {
        if (bytes == 0) return null;
        auto p = primary.allocate(bytes);
        if (p.length != 0) return p;
        try return new ubyte[bytes];
        catch (Exception) return null;
    }

    /++
     + Reset the stack region. GC-spilled blocks fall out of scope
     + naturally when the caller stops referencing them.
     +/
    void deallocateAll() @trusted nothrow
    {
        primary.deallocateAll();
    }
}

version (unittest)
{
    @safe unittest
    {
        // StackFallback: first N bytes on the stack, then GC fallback.
        StackFallback!256 sfb;
        // Allocate within stack budget.
        auto a = (() @trusted => sfb.allocate(64))();
        assert(a.length == 64);
        // Overflow the stack region — spills to GC heap.
        auto b = (() @trusted => sfb.allocate(4096))();
        assert(b.length == 4096);
        // Reset stack region. GC blocks fall out of scope.
        (() @trusted => sfb.deallocateAll())();
    }
}
