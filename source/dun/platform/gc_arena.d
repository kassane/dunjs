// Experimental "arena" GC backend — case-study companion to
// docs/research/custom-gc-v8-jsc.md (Design C3 sketch).
//
// Strategy: delegate every allocation to core.stdc.stdlib.malloc.
// No mark phase, no sweep phase, no collection. `collect()` is a
// no-op. `free` actually returns memory immediately. This is the
// simplest custom GC that satisfies the 32-method
// `core.gc.gcinterface.GC` contract.
//
// What this proves:
//   1.  The `pragma(crt_constructor)` + `registerGCFactory` pattern
//       actually works end-to-end against LDC 1.42's druntime.
//   2.  D's `core.gc.gcinterface.GC` is satisfiable with ~200 LOC
//       of mostly trivial overrides.
//   3.  We can compare bench numbers against the default
//       conservative GC to quantify "what fraction of throughput
//       is the GC's bookkeeping costing us."
//
// What this DOESN'T prove:
//   - That a real production GC is feasible. This thing leaks
//     every allocation (no `collect()` ever runs) and is unsafe
//     for long-running processes. It's an experimental
//     measurement vehicle, not a production GC.
//
// Selection: `dun "--DRT-gcopt=gc:arena" run script.js`.
// The default `conservative` GC is used otherwise — this module
// only LOG-registers; it doesn't replace anything.

module dun.platform.gc_arena;

version (DunCustomGC):

import core.gc.gcinterface;
import core.gc.registry;
static import core.memory;
import core.thread.threadbase : ThreadBase;
import core.stdc.stdlib : cmalloc = malloc, cfree = free, crealloc = realloc;
import core.stdc.string : memcpy, memset;
import core.atomic : atomicOp;

alias BlkAttr = core.memory.GC.BlkAttr;
alias BlkInfo = core.memory.GC.BlkInfo;

extern (C) pragma(crt_constructor) void registerArenaGC()
{
    registerGCFactory("arena", &createArenaGC);
}

GC createArenaGC() @trusted
{
    // CRITICAL: we cannot use `new ArenaGC` here. The factory runs
    // *inside* `gc_init`, which is called from ProtoGC.malloc on the
    // first allocation. If our factory then allocates via `new`, the
    // ProtoGC.malloc → gc_init → factory → new → ProtoGC.malloc loop
    // hits the SpinLock recursion and the process hangs at startup.
    // (Found via /debug-native-callback gdb attach — see CHANGELOG
    // entry for this PR.)
    //
    // Solution per `core.gc.registry` docs: allocate the GC instance
    // on the C heap (malloc + emplace), and the instance is responsible
    // for freeing itself in its destructor.
    import core.stdc.stdlib : malloc;
    import core.lifetime : emplace;
    enum size = __traits(classInstanceSize, ArenaGC);
    auto raw = malloc(size);
    if (raw is null) return null;
    auto instance = emplace!ArenaGC(raw[0 .. size]);
    instance.initialize();
    return instance;
}

/// Side-table entry tracking each allocated block.
/// Stored in a doubly-linked list so `addrOf`/`sizeOf`/`query` work.
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
    private __gshared Block* _head;
    private __gshared size_t _allocCount;
    private __gshared size_t _bytesLive;

    // Roots and ranges are NEVER scanned (we don't have a mark phase)
    // but we have to store them for interface contract — `rootIter` /
    // `rangeIter` are called by debug tools.
    private __gshared Root[] _roots;
    private __gshared Range[] _ranges;

    void initialize() nothrow
    {
        // No state to set up — malloc is process-global.
    }

    // ─── Lifecycle ──────────────────────────────────────────────

    void enable() {}
    void disable() {}
    void collect() nothrow {}
    void minimize() nothrow {}

    // ─── Allocation ─────────────────────────────────────────────

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

    void* realloc(void* p, size_t size, uint bits, const TypeInfo ti) nothrow
    {
        if (p is null) return malloc(size, bits, ti);
        auto b = findBlock(p);
        if (b is null) return null;
        if (size == 0) { free(p); return null; }
        // Allocate new block, copy, free old.
        auto fresh = allocBlock(size, bits, false);
        if (fresh !is null && b.size > 0)
            memcpy(fresh, p, b.size < size ? b.size : size);
        free(p);
        return fresh;
    }

    size_t extend(void* p, size_t minsize, size_t maxsize, const TypeInfo ti) nothrow
    {
        // We don't grow in-place; signal "couldn't extend".
        return 0;
    }

    size_t reserve(size_t size) nothrow
    {
        // No pool to reserve into.
        return 0;
    }

    void free(void* p) nothrow @nogc
    {
        if (p is null) return;
        auto b = findBlock(p);
        if (b is null) return;
        unlinkBlock(b);
        cfree(p);
        cfree(b);
    }

    // ─── Block metadata ─────────────────────────────────────────

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

    // ─── Stats ──────────────────────────────────────────────────

    core.memory.GC.Stats stats() @trusted nothrow @nogc
    {
        core.memory.GC.Stats s;
        s.usedSize = _bytesLive;
        s.freeSize = 0;
        return s;
    }

    core.memory.GC.ProfileStats profileStats() @safe nothrow @nogc
    {
        core.memory.GC.ProfileStats s;
        return s;  // zero — we don't profile
    }

    ulong allocatedInCurrentThread() nothrow @trusted
    {
        // Approximation — we don't track per-thread. Return the
        // global count, which is monotonically increasing.
        return _allocCount;
    }

    // ─── Roots ──────────────────────────────────────────────────

    void addRoot(void* p) nothrow @nogc
    {
        // No-op semantics; we don't collect.
    }

    void removeRoot(void* p) nothrow @nogc {}

    @property RootIterator rootIter() @nogc
    {
        return &iterRoots;
    }

    private int iterRoots(scope int delegate(ref Root) nothrow dg) nothrow @trusted
    {
        return 0;  // We don't track roots — we never collect.
    }

    void addRange(void* p, size_t sz, const TypeInfo ti) nothrow @nogc {}
    void removeRange(void* p) nothrow @nogc {}

    @property RangeIterator rangeIter() @nogc
    {
        return &iterRanges;
    }

    private int iterRanges(scope int delegate(ref Range) nothrow dg) nothrow @trusted
    {
        return 0;
    }

    // ─── Finalization ───────────────────────────────────────────

    void runFinalizers(const scope void[] segment) nothrow
    {
        // We never collect — finalizers never run automatically.
        // Programs that depend on destruction must call dispose
        // explicitly. This is the same contract as `manual` GC.
    }

    bool inFinalizer() nothrow @nogc @safe { return false; }

    // ─── Thread hooks ───────────────────────────────────────────

    void initThread(ThreadBase t) nothrow @nogc {}
    void cleanupThread(ThreadBase t) nothrow @nogc {}

    // ─── Array operations ───────────────────────────────────────

    void[] getArrayUsed(void* ptr, bool atomic = false) nothrow @trusted
    {
        auto b = findBlock(ptr);
        if (b is null) return null;
        return b.ptr[0 .. b.size];
    }

    bool expandArrayUsed(void[] slice, size_t newUsed, bool atomic = false)
        nothrow @safe
    {
        // Without a capacity-tracking layer we can't expand in place.
        return false;
    }

    size_t reserveArrayCapacity(void[] slice, size_t request, bool atomic = false)
        nothrow @safe
    {
        return 0;
    }

    bool shrinkArrayUsed(void[] slice, size_t existingUsed, bool atomic = false)
        nothrow
    {
        // Shrinking is a no-op — the block stays the same size.
        return false;
    }

    // ─── Private helpers ────────────────────────────────────────

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
        ++_allocCount;
        _bytesLive += size;
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
        _bytesLive -= b.size;
        if (b.prev !is null) b.prev.next = b.next;
        else _head = b.next;
        if (b.next !is null) b.next.prev = b.prev;
    }

    private Block* findBlock(void* p) nothrow @nogc @trusted
    {
        // O(n) linear scan over the live block list. Real GCs use
        // a hash by page address — but this is an experimental
        // measurement vehicle, not a production GC.
        auto b = _head;
        while (b !is null)
        {
            if (b.ptr <= p && p < b.ptr + b.size)
                return b;
            b = b.next;
        }
        return null;
    }
}
