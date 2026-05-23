module dun.platform.arena;


/++
 + `@trusted policy`: arena/scratch-buffer wrappers for hot paths
 + that need `@nogc nothrow` allocation. The `@trusted` annotation
 + localizes the unsafe FFI-shaped boundary (raw `void[]` -> `T[]`
 + cast inside `StackFallback.allocate` and `MallocArray.put`);
 + callers stay `@safe`.
 +
 + Public surface (pick by GC tolerance):
 +   - `Appender!T` — GC-backed dynamic array, idiomatic D. Use
 +     when you tolerate GC and want `~=`-style append; pair with
 +     `reserve(estimated)` to keep growth to one allocation.
 +   - `StackFallback!N` — first `N` bytes off the stack via
 +     `InSituRegion`, then GC heap spill. Mirrors Bun's
 +     `std.heap.stackFallback` pattern in node_*_binding.zig
 +     for per-call scratch buffers (paths, header values,
 +     /proc parsing).
 +   - `MallocArray!T` — true `@nogc nothrow` dynamic array
 +     backed by `Mallocator` (libc `malloc`/`realloc`/`free`).
 +     Use only when the caller is in a `@nogc nothrow` boundary
 +     and Appender's GC backing isn't acceptable. RAII destructor
 +     calls `free`; copy out via `.idup` if the slice needs to
 +     outlive the array.
 +/

import std.array : StdAppender = Appender;
alias Appender(A) = StdAppender!A;

private import std.experimental.allocator.building_blocks.region : InSituRegion;
private import std.experimental.allocator.mallocator : Mallocator;

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

/++
 + `@nogc nothrow` dynamic array — malloc-backed (libc) instead
 + of GC. `~=`-style append via `put(T)` / `put(const(T)[])`.
 + Capacity doubles on overflow (16 → 32 → 64 …). RAII frees the
 + buffer at scope exit; consume the slice via `.idup` first if
 + you need it past the array's lifetime.
 +
 + Use when you're inside a `@nogc nothrow` boundary (extern(C)
 + callbacks, hot worker-thread loops) and Appender's GC backing
 + would trigger a collection. Most code can use `Appender + reserve`
 + — only reach for this when you've measured GC pressure that
 + Appender can't amortize.
 +
 + Usage:
 + ```
 + import dun.platform.arena : MallocArray;
 + MallocArray!ubyte buf;
 + buf.put(0xDE);
 + buf.put(cast(const(ubyte)[]) [0xAD, 0xBE, 0xEF]);
 + auto owned = buf.data.dup;    // copy to GC if needed (or .idup
 +                                // for immutable). data() returns
 +                                // a slice into Mallocator memory
 +                                // that ~this will free.
 + // ~this frees the malloc buffer at scope exit
 + ```
 +/
struct MallocArray(T)
{
    private T[] buf;
    private size_t len;

    @disable this(this);   // prevent double-free via copy

    ~this() @trusted @nogc nothrow
    {
        if (buf.ptr !is null)
        {
            Mallocator.instance.deallocate(cast(void[]) buf);
            buf = null;
            len = 0;
        }
    }

    void reserve(size_t n) @trusted @nogc nothrow
    {
        if (n <= buf.length) return;
        auto rawNew = Mallocator.instance.allocate(n * T.sizeof);
        if (rawNew.length == 0) return;
        auto newBuf = (cast(T*) rawNew.ptr)[0 .. n];
        if (buf.ptr !is null)
        {
            newBuf[0 .. len] = buf[0 .. len];
            Mallocator.instance.deallocate(cast(void[]) buf);
        }
        buf = newBuf;
    }

    void put(T x) @trusted @nogc nothrow
    {
        if (len >= buf.length)
            reserve(buf.length == 0 ? 16 : buf.length * 2);
        if (len < buf.length)   // reserve may have failed
            buf[len++] = x;
    }

    void put(scope const(T)[] xs) @trusted @nogc nothrow
    {
        auto needed = len + xs.length;
        if (needed > buf.length)
        {
            auto newCap = buf.length == 0 ? 16 : buf.length;
            while (newCap < needed) newCap *= 2;
            reserve(newCap);
        }
        if (len + xs.length <= buf.length)
        {
            buf[len .. len + xs.length] = xs[];
            len += xs.length;
        }
    }

    inout(T)[] data() @trusted @nogc nothrow return scope inout
    {
        return buf[0 .. len];
    }

    size_t length() const @safe @nogc nothrow { return len; }
    size_t capacity() const @safe @nogc nothrow { return buf.length; }
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

    @safe unittest
    {
        // MallocArray: @nogc nothrow dynamic append, malloc-backed.
        auto build = () @nogc nothrow @trusted {
            MallocArray!ubyte buf;
            buf.put(0xDE);
            buf.put(cast(const(ubyte)[])[0xAD, 0xBE, 0xEF]);
            assert(buf.length == 4);
            assert(buf.data == [0xDE, 0xAD, 0xBE, 0xEF]);
            // Growth across capacity doublings (16 -> 32).
            foreach (i; 0 .. 30) buf.put(cast(ubyte) i);
            assert(buf.length == 34);
            assert(buf.data[3] == 0xEF);
            assert(buf.data[33] == 29);
            // RAII frees the malloc buffer at scope exit.
        };
        build();
    }

    @safe unittest
    {
        // MallocArray: data() lifetime — caller must `.dup` (mutable)
        // or `.idup` (immutable) to outlive the array.
        ubyte[] owned;
        {
            MallocArray!ubyte buf;
            (() @trusted {
                buf.put(cast(const(ubyte)[])[1, 2, 3]);
                owned = buf.data.dup;
            })();
        }
        // `buf` destroyed; `owned` is a GC copy and still valid.
        assert(owned == [1, 2, 3]);
    }
}
