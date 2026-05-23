module dun.platform.arena;


/++
 + `@trusted policy`: arena/scratch-buffer wrappers for hot paths
 + that need `@nogc nothrow` allocation. The `@trusted` annotation
 + localizes the unsafe FFI-shaped boundary (raw `void[]` -> `T[]`
 + cast inside `StackFallback.allocate`); callers stay `@safe`.
 +
 + Public surface:
 +   - `Appender!T`  — wraps `std.array.Appender` via alias so the
 +     symbol is private to the arena's import graph (vs. `public
 +     import` which would transitively republish the entire
 +     `std.array.Appender` template chain).
 +   - `StackFallback!N` — first `N` bytes off the stack via
 +     `InSituRegion`, then GC heap spill. Mirrors Bun's
 +     `std.heap.stackFallback` pattern in node_*_binding.zig
 +     for per-call scratch buffers (paths, header values,
 +     /proc parsing).
 +/

import std.array : StdAppender = Appender;
alias Appender(A) = StdAppender!A;

private import std.experimental.allocator.building_blocks.region : InSituRegion;

/++
 + Stack-first, heap-fallback bulk allocator. The first `N` bytes
 + come off the function's stack via `InSituRegion!N`; once that
 + fills, allocations spill to the GC heap. The destructor resets
 + the stack region; GC-spilled blocks fall out of scope naturally.
 +
 + Usage (RAII, no manual cleanup):
 + ```
 + import dun.platform.arena : StackFallback;
 + StackFallback!4096 sfb;
 + auto buf = sfb.allocate(needed);
 + // destructor runs at scope exit
 + ```
 +/
struct StackFallback(size_t N)
{
    static assert(N > 0, "StackFallback!N requires N > 0");

    /++
     + `InSituRegion` is itself `@disable this(this)`, so the field
     + makes `StackFallback` non-copyable for free — no explicit
     + postblit disable needed.
     +/
    InSituRegion!N primary;

    /++
     + D structs don't have class-style inheritance, but `alias this`
     + forwards every `InSituRegion` method (`deallocateAll`,
     + `alignment`, the `empty` property…) to `primary`. Our own
     + `allocate` overload shadows the inherited one to add the
     + heap-fallback path. Callers can still reach the underlying
     + method explicitly via `sfb.primary.allocate(...)` if needed.
     +/
    alias primary this;

    /++
     + RAII reset. Runs at scope exit; callers should not retain
     + stack-portion slices past it. GC-spilled blocks the GC owns
     + and reclaims when the slice references drop.
     +/
    ~this() @trusted nothrow
    {
        primary.deallocateAll();
    }

    /++
     + Returns a slice of `bytes` from the stack region when it
     + fits, otherwise from the GC heap. Returns `null` only for a
     + 0-byte request or under GC `OutOfMemoryError`.
     +/
    void[] allocate(size_t bytes) @trusted nothrow
    {
        if (bytes == 0) return null;
        auto p = primary.allocate(bytes);
        if (p.length != 0) return p;
        try return new ubyte[bytes];
        catch (Exception) return null;
    }
}

version (unittest)
{
    @safe unittest
    {
        StackFallback!256 sfb;
        auto a = (() @trusted => sfb.allocate(64))();
        assert(a.length == 64);
        auto b = (() @trusted => sfb.allocate(4096))();
        assert(b.length == 4096);
        // RAII: ~this resets the stack region at scope exit.
    }

    @safe unittest
    {
        Appender!(char[]) buf;
        buf.reserve(8);
        buf ~= 'h';
        buf ~= 'i';
        assert(buf.data == "hi");
    }
}
