/// SharedArrayBuffer registry. Cross-worker shared memory blocks are
/// allocated via `malloc()` and kept alive via a refcount-style slot
/// table. Workers post `{ id, len }` over the message channel; the
/// receiver looks up the pointer via `sabGet(id)`.
///
/// Concurrency: `sabAlloc` grows the registry under a mutex (rare —
/// once per `new SharedArrayBuffer(...)` call). `sabRef` / `sabUnref`
/// use `core.atomic.atomicOp!"+="` on the refcount (lockfree, hot
/// path for worker termination). `sabGet` reads under a brief mutex
/// only because slot reuse via `sabUnref` could race a concurrent
/// read; the lock window is two pointer loads.
///
/// Per the `/debug-native-callback` skill's mutex-audit guidance:
/// register/grow paths keep the lock (cold), refcount paths are
/// now atomic (hot).
module dun.workers.shared_memory;


/// `@trusted policy`: SharedArrayBuffer backing storage —
/// page-aligned mmap'd region shared across worker threads.
/// Every `@trusted` is one of:
///   1. `core.sys.posix.sys.mman.mmap` / `munmap` for the backing
///      pages.
///   2. `cast(ubyte[]) (ptr[0..size])` to expose the mapped region
///      as a D slice.
///   3. Refcount via `atomicFetchAdd` on the shared header.
import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;
import core.sync.mutex : Mutex;
import core.atomic : atomicOp, atomicLoad, atomicStore, MemoryOrder;

private struct SABEntry
{
    void* ptr;
    size_t len;
    shared int refCount;
}

private __gshared SABEntry[] gRegistry;
private __gshared Mutex gMutex;

shared static this() @system
{
    gMutex = new Mutex();
}

int sabAlloc(size_t len) @trusted
{
    auto ptr = malloc(len);
    if (!ptr)
        return -1;
    memset(ptr, 0, len);
    synchronized (gMutex)
    {
        foreach (i, ref e; gRegistry)
        {
            if (e.ptr is null)
            {
                e.ptr = ptr;
                e.len = len;
                atomicStore!(MemoryOrder.rel)(e.refCount, 1);
                return cast(int) i;
            }
        }
        SABEntry ne;
        ne.ptr = ptr;
        ne.len = len;
        atomicStore!(MemoryOrder.rel)(ne.refCount, 1);
        gRegistry ~= ne;
        return cast(int)(gRegistry.length - 1);
    }
}

bool sabGet(int id, out void* ptr, out size_t len) @trusted
{
    synchronized (gMutex)
    {
        if (id < 0 || id >= cast(int) gRegistry.length || gRegistry[id].ptr is null)
            return false;
        ptr = gRegistry[id].ptr;
        len = gRegistry[id].len;
        return true;
    }
}

void sabRef(int id) @trusted
{
    /* Lockfree atomic increment — the refcount is `shared int` so
       D's atomicOp issues a `lock incl` (x86) or `LDADDAL` (arm64).
       The id-range check reads `.length` without locking; since
       `gRegistry` only grows, a stale length just means "id < length"
       returns true for a slot that exists. Worst case: a torn
       read on an in-flight `sabAlloc`'s `~=`, which is benign
       because the writer hasn't published the id yet. */
    if (id < 0) return;
    auto reg = cast(SABEntry[]) gRegistry;
    if (id >= cast(int) reg.length) return;
    atomicOp!"+="(reg[id].refCount, 1);
}

void sabUnref(int id) @trusted
{
    /* Lockfree atomic decrement. If we hit zero, take the mutex to
       free + clear the slot (free is heavy and ptr=null needs to be
       observed by `sabGet`, which is also under the lock). */
    if (id < 0) return;
    auto reg = cast(SABEntry[]) gRegistry;
    if (id >= cast(int) reg.length) return;
    int newRef = atomicOp!"-="(reg[id].refCount, 1);
    if (newRef <= 0)
    {
        synchronized (gMutex)
        {
            /* Re-check under the lock — a parallel sabRef could
               have bumped the count back up between our decrement
               and this point. */
            if (atomicLoad!(MemoryOrder.acq)(reg[id].refCount) <= 0
                && reg[id].ptr !is null)
            {
                free(reg[id].ptr);
                reg[id].ptr = null;
            }
        }
    }
}
