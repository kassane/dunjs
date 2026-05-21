/// Experimental passthrough GC backend (Design C3-lite in
/// docs/research/custom-gc-v8-jsc.md §6). Selection:
/// `dun "--DRT-gcopt=gc:arena" run script.js`. Behind
/// `version (DunCustomGC)` — default builds never see it.
///
/// Note: druntime ALREADY ships an equivalent malloc-passthrough
/// GC at `core.internal.gc.impl.manual.gc.ManualGC`, registered
/// as `gc:manual`. For pure A/B perf measurement just use that.
/// This module exists to (a) prove `registerGCFactory` is reachable
/// from user code and (b) document the factory-recursion gotcha in
/// `createArenaGC` (research doc §9.1) — the value is the gdb-
/// captured fix, not novel GC semantics.

module dun.platform.gc_arena;

version (DunCustomGC):

import core.gc.gcinterface;
import core.gc.registry;
static import core.memory;
import core.thread.threadbase : ThreadBase;
import core.stdc.stdlib : cmalloc = malloc, cfree = free, crealloc = realloc;
import core.stdc.string : memcpy, memset;
import core.atomic : atomicOp, atomicLoad;

alias BlkAttr = core.memory.GC.BlkAttr;
alias BlkInfo = core.memory.GC.BlkInfo;

private enum GC_NAME = "arena";

extern (C) pragma(crt_constructor) void registerArenaGC()
{
    registerGCFactory(GC_NAME, &createArenaGC);
}

/// Factory MUST C-heap-allocate (malloc + emplace) — using D's `new`
/// recurses via ProtoGC.malloc → gc_init → factory → new and hangs
/// on the SpinLock. See research doc §9.1 for the gdb trace.
GC createArenaGC() @trusted
{
    import core.stdc.stdlib : malloc;
    import core.lifetime : emplace;
    enum size = __traits(classInstanceSize, ArenaGC);
    auto raw = malloc(size);
    if (raw is null) return null;
    auto instance = emplace!ArenaGC(raw[0 .. size]);
    instance.initialize();
    return instance;
}

private struct Block
{
    void* ptr;
    size_t size;
    uint attr;
    Block* next;
    Block* prev;
}

class ArenaGC : GC
{
    private static shared size_t _allocCount;
    private static shared size_t _bytesLive;
    private __gshared Block* _head;

    // No mutex on the block list — the experimental GC documents itself
    // as single-threaded only (the module header says "experimental
    // measurement vehicle, not a production GC"). The reasons:
    //   - `new Mutex()` here recurses through ProtoGC.malloc → gc_init
    //     → createArenaGC → initialize → new Mutex → ... → SpinLock hang.
    //     Same gotcha as §9.1 in the research doc (factory-recursion).
    //     Caught via /debug-native-callback audit after a prior review-
    //     fix attempt introduced exactly that recursion.
    //   - A `pthread_mutex_t` value would work (no D heap), but adding
    //     POSIX-only code to a research module isn't worth the surface.
    //   - Counter writes use `atomicOp!"+="` against `shared size_t`,
    //     so the most-visible stats remain correct under contention.
    //     Only the doubly-linked-list mutations race, and the experiment
    //     bench runs single-threaded.
    // Production successor (research doc §9.5) needs a hash-keyed side-
    // table; pthread_mutex_t or lock-free CAS layout solves the
    // thread-safety on the way to that.
    void initialize() nothrow @trusted {}

    void enable() {}
    void disable() {}
    void collect() nothrow {}
    void minimize() nothrow {}

    void* malloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        return allocBlock(size, bits, false);
    }

    BlkInfo qalloc(size_t size, uint bits, const scope TypeInfo ti) nothrow
    {
        BlkInfo info;
        info.base = allocBlock(size, bits, false);
        info.size = size;
        info.attr = bits;
        return info;
    }

    void* calloc(size_t size, uint bits, const TypeInfo ti) nothrow
    {
        return allocBlock(size, bits, true);
    }

    void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow @trusted
    {
        if (p is null) return malloc(size, bits, ti);
        if (size == 0) { free(p); return null; }
        auto b = findBlock(p);
        if (b is null) return null;
        auto fresh = crealloc(p, size);
        if (fresh is null) return null;
        if (size > b.size) atomicOp!"+="(_bytesLive, size - b.size);
        else if (size < b.size) atomicOp!"-="(_bytesLive, b.size - size);
        b.ptr = fresh;
        b.size = size;
        b.attr = bits;
        return fresh;
    }

    size_t extend(void* p, size_t minsize, size_t maxsize, const TypeInfo ti) nothrow
    {
        return 0;
    }

    size_t reserve(size_t size) nothrow
    {
        return 0;
    }

    void free(void* p) nothrow @nogc @trusted
    {
        if (p is null) return;
        auto b = findBlock(p);
        if (b is null) return;
        unlinkBlock(b);
        cfree(p);
        cfree(b);
    }

    uint getAttr(void* p) nothrow
    {
        auto b = findBlock(p);
        return b is null ? 0 : b.attr;
    }

    uint setAttr(void* p, uint mask) nothrow
    {
        auto b = findBlock(p);
        if (b is null) return 0;
        b.attr |= mask;
        return b.attr;
    }

    uint clrAttr(void* p, uint mask) nothrow
    {
        auto b = findBlock(p);
        if (b is null) return 0;
        b.attr &= ~mask;
        return b.attr;
    }

    void* addrOf(void* p) nothrow @nogc
    {
        auto b = findBlock(p);
        return b is null ? null : b.ptr;
    }

    size_t sizeOf(void* p) nothrow @nogc
    {
        auto b = findBlock(p);
        return b is null ? 0 : b.size;
    }

    BlkInfo query(void* p) nothrow
    {
        BlkInfo info;
        auto b = findBlock(p);
        if (b !is null)
        {
            info.base = b.ptr;
            info.size = b.size;
            info.attr = b.attr;
        }
        return info;
    }

    core.memory.GC.Stats stats() @trusted nothrow @nogc
    {
        core.memory.GC.Stats s;
        s.usedSize = atomicLoad(_bytesLive);
        return s;
    }

    core.memory.GC.ProfileStats profileStats() @safe nothrow @nogc
    {
        core.memory.GC.ProfileStats s;
        return s;
    }

    /// Per the `core.memory.GC.Stats.allocatedInCurrentThread` contract
    /// this returns BYTES, not allocation count. We don't track per-
    /// thread so the global `_bytesLive` is the closest approximation.
    ulong allocatedInCurrentThread() nothrow @trusted
    {
        return atomicLoad(_bytesLive);
    }

    void addRoot(void* p) nothrow @nogc {}
    void removeRoot(void* p) nothrow @nogc {}

    @property RootIterator rootIter() @nogc { return &iterRoots; }
    private int iterRoots(scope int delegate(ref Root) nothrow dg) nothrow @trusted { return 0; }

    void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc {}
    void removeRange(void* p) nothrow @nogc {}

    @property RangeIterator rangeIter() @nogc { return &iterRanges; }
    private int iterRanges(scope int delegate(ref Range) nothrow dg) nothrow @trusted { return 0; }

    void runFinalizers(const scope void[] segment) nothrow {}
    bool inFinalizer() nothrow @nogc @safe { return false; }

    void initThread(ThreadBase t) nothrow @nogc {}
    void cleanupThread(ThreadBase t) nothrow @nogc {}

    void[] getArrayUsed(void* ptr, bool atomic = false) nothrow @trusted
    {
        auto b = findBlock(ptr);
        if (b is null) return null;
        return b.ptr[0 .. b.size];
    }

    bool expandArrayUsed(void[] slice, size_t newUsed, bool atomic = false) nothrow @safe
    {
        return false;
    }

    size_t reserveArrayCapacity(void[] slice, size_t request, bool atomic = false) nothrow @safe
    {
        return 0;
    }

    bool shrinkArrayUsed(void[] slice, size_t existingUsed, bool atomic = false) nothrow
    {
        return false;
    }

    private void* allocBlock(size_t size, uint attr, bool zero) nothrow @trusted
    {
        auto ptr = cmalloc(size);
        if (ptr is null) return null;
        if (zero) memset(ptr, 0, size);
        auto b = cast(Block*) cmalloc(Block.sizeof);
        if (b is null) { cfree(ptr); return null; }
        b.ptr = ptr;
        b.size = size;
        b.attr = attr;
        linkBlock(b);
        atomicOp!"+="(_allocCount, cast(size_t) 1);
        atomicOp!"+="(_bytesLive, size);
        return ptr;
    }

    private void linkBlock(Block* b) nothrow @trusted
    {
        b.prev = null;
        b.next = _head;
        if (_head !is null) _head.prev = b;
        _head = b;
    }

    private void unlinkBlock(Block* b) nothrow @nogc @trusted
    {
        atomicOp!"-="(_bytesLive, b.size);
        if (b.prev !is null) b.prev.next = b.next;
        else _head = b.next;
        if (b.next !is null) b.next.prev = b.prev;
    }

    /// O(n) linear scan — production arena would use a hash-keyed
    /// side-table (research doc §9.5). Acceptable for the experiment
    /// because the smoke fixture allocates few blocks; production use
    /// regresses quadratically.
    private Block* findBlock(void* p) nothrow @nogc @trusted
    {
        if (p is null) return null;
        for (auto b = _head; b !is null; b = b.next)
        {
            if (b.ptr <= p && p < b.ptr + b.size)
                return b;
        }
        return null;
    }
}
