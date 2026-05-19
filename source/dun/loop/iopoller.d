module dun.loop.iopoller;

private enum MAX_FD_WATCHES = 64;

/// IORING_OP_POLL_REMOVE ignores the SQE.fd field — the kernel
/// matches the request to cancel by SQE.addr (the original ADD's
/// user_data). We pass `-1` to make the "no fd" intent explicit.
private enum int POLL_REMOVE_FD = -1;

struct IOEvent
{
    int fd;
    bool readable;
    bool writable;
}

struct IOPoller
{
    version (linux)
    {
        private int epfd    = -1;
        private int uringFd = -1;
        private bool useUring = false;
        // io_uring ring pointers (valid only when useUring)
        private void*       sqRingPtr;
        private size_t      sqRingMapSize;
        private void*       cqRingPtr;
        private size_t      cqRingMapSize;
        private IORingSQE*  sqesPtr;
        private size_t      sqesMapSize;
        private uint*       sqHead;
        private uint*       sqTail;
        private uint        sqRingMask;
        private uint*       sqArray;
        private uint*       cqHead;
        private uint*       cqTail;
        private uint        cqRingMask;
        private IORingCQE*  cqes;
        private bool        singleMmap;
        // per-fd state for one-shot re-arming
        private FdWatch[MAX_FD_WATCHES] fdWatches;
    }
    else version (FreeBSD)
    {
        private int kqfd = -1;
    }
    else version (OSX)
    {
        private int kqfd = -1;
    }
    else version (Posix)
    {
        import core.sys.posix.poll : pollfd;
        private pollfd[] pollfds;
    }
    else version (Windows)
    {
        // Stub — IOCP integration planned for Phase 6b.
    }

    private int watchCount = 0;

    // ── Lifecycle ────────────────────────────────────────────────

    void initialize() @trusted nothrow
    {
        version (linux)
        {
            /* io_uring vs epoll. Bun walks the same path and chose
               epoll exclusively — their `bun.zig` `is_missing_io_uring`
               helper exists only to skip native I/O ops on older
               kernels; their event loop is epoll-only on Linux
               (`src/io/posix_event_loop.zig` / `lib.rs`). The single
               io_uring mention in their tree is a TODO marker in
               package install.

               We follow Bun's lead for the JSC backend specifically —
               io_uring's POLL_ADD lifecycle interacts poorly with
               JSC's concurrent GC under repeated server-restart
               workloads (gdb confirms `dun.loop.iopoller.uringPoll`
               hangs after ~9 `Deno.serve+shutdown` cycles). QJS / V8
               keep io_uring because they don't trigger the
               interaction. The runtime override `DUN_DISABLE_URING=1`
               forces epoll on every backend (matches Bun behavior). */
            bool forceEpoll = false;
            try
            {
                import core.sys.posix.stdlib : getenv;
                auto e = getenv("DUN_DISABLE_URING");
                if (e !is null && *e != 0) forceEpoll = true;
            }
            catch (Exception) {}
            version (EngineJSC) forceEpoll = true;

            if (!forceEpoll)
            {
                // Try io_uring first; fall back to epoll on older kernels.
                uringFd = uringSetup(64, &sqRingPtr, &sqRingMapSize,
                    &cqRingPtr, &cqRingMapSize, &sqesPtr, &sqesMapSize,
                    &sqHead, &sqTail, &sqRingMask, &sqArray,
                    &cqHead, &cqTail, &cqRingMask, &cqes, &singleMmap);
            }
            if (!forceEpoll && uringFd >= 0)
            {
                useUring = true;
            }
            else
            {
                import core.sys.linux.epoll : epoll_create1;
                epfd = epoll_create1(0);
            }
        }
        else version (FreeBSD)
        {
            kqfd = kqueueCreate();
        }
        else version (OSX)
        {
            kqfd = kqueueCreate();
        }
    }

    void shutdown() @trusted nothrow
    {
        version (linux)
        {
            if (useUring)
            {
                uringShutdown(uringFd, sqRingPtr, sqRingMapSize,
                    cqRingPtr, cqRingMapSize, sqesPtr, sqesMapSize, singleMmap);
                uringFd = -1;
                useUring = false;
                watchCount = 0;
            }
            else if (epfd >= 0)
            {
                import core.sys.posix.unistd : close;
                close(epfd);
                epfd = -1;
                watchCount = 0;
            }
        }
        else version (FreeBSD)
        {
            kqueueShutdown(kqfd, watchCount);
            kqfd = -1;
            watchCount = 0;
        }
        else version (OSX)
        {
            kqueueShutdown(kqfd, watchCount);
            kqfd = -1;
            watchCount = 0;
        }
        else version (Posix)
        {
            pollfds = null;
            watchCount = 0;
        }
    }

    // ── Watch / Modify / Unwatch ────────────────────────────────

    void watch(int fd, bool forRead = true, bool forWrite = false) @trusted nothrow
    {
        version (linux)
        {
            if (useUring)
            {
                if (uringWatch(uringFd, fd, forRead, forWrite,
                    sqHead, sqTail, sqRingMask, sqArray, sqesPtr))
                    watchCount++;
                uringTrackFd(fdWatches, fd, forRead, forWrite);
                return;
            }
            import core.sys.linux.epoll;
            if (epfd < 0) return;
            epoll_event ev;
            if (forRead)  ev.events |= EPOLLIN;
            if (forWrite) ev.events |= EPOLLOUT;
            ev.events |= EPOLLHUP | EPOLLERR;
            ev.data.fd = fd;
            if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) == 0)
                watchCount++;
        }
        else version (FreeBSD)
        {
            if (kqueueWatch(kqfd, fd, forRead, forWrite))
                watchCount++;
        }
        else version (OSX)
        {
            if (kqueueWatch(kqfd, fd, forRead, forWrite))
                watchCount++;
        }
        else version (Posix)
        {
            pollAdd(pollfds, fd, forRead, forWrite);
            watchCount++;
        }
    }

    void modify(int fd, bool forRead, bool forWrite) @trusted nothrow
    {
        version (linux)
        {
            if (useUring)
            {
                // Remove pending poll, re-add with new events. Use the
                // tracked fdWatch entry's events to compute the ADD's
                // user_data so POLL_REMOVE matches in the kernel.
                auto w = uringLookupFd(fdWatches, fd);
                if (w.fd == fd)
                    uringRemove(uringFd, fd,
                        uringUserData(fd, fdWatchEvents(w)),
                        sqHead, sqTail, sqRingMask, sqArray, sqesPtr);
                uringWatch(uringFd, fd, forRead, forWrite,
                    sqHead, sqTail, sqRingMask, sqArray, sqesPtr);
                uringTrackFd(fdWatches, fd, forRead, forWrite);
                return;
            }
            import core.sys.linux.epoll;
            if (epfd < 0) return;
            epoll_event ev;
            if (forRead)  ev.events |= EPOLLIN;
            if (forWrite) ev.events |= EPOLLOUT;
            ev.events |= EPOLLHUP | EPOLLERR;
            ev.data.fd = fd;
            epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev);
        }
        else version (FreeBSD)
        {
            kqueueModify(kqfd, fd, forRead, forWrite);
        }
        else version (OSX)
        {
            kqueueModify(kqfd, fd, forRead, forWrite);
        }
        else version (Posix)
        {
            pollModify(pollfds, fd, forRead, forWrite);
        }
    }

    void unwatch(int fd) @trusted nothrow
    {
        version (linux)
        {
            if (useUring)
            {
                // Look up the original watch BEFORE untracking — we need
                // its events to compute the original ADD's user_data so
                // POLL_REMOVE matches in the kernel.
                auto w = uringLookupFd(fdWatches, fd);
                if (w.fd == fd)
                    uringRemove(uringFd, fd,
                        uringUserData(fd, fdWatchEvents(w)),
                        sqHead, sqTail, sqRingMask, sqArray, sqesPtr);
                uringUntrackFd(fdWatches, fd);
                if (watchCount > 0) watchCount--;
                return;
            }
            import core.sys.linux.epoll;
            if (epfd < 0) return;
            if (epoll_ctl(epfd, EPOLL_CTL_DEL, fd, null) == 0 && watchCount > 0)
                watchCount--;
        }
        else version (FreeBSD)
        {
            if (kqueueUnwatch(kqfd, fd) && watchCount > 0)
                watchCount--;
        }
        else version (OSX)
        {
            if (kqueueUnwatch(kqfd, fd) && watchCount > 0)
                watchCount--;
        }
        else version (Posix)
        {
            pollRemove(pollfds, fd);
            if (watchCount > 0) watchCount--;
        }
    }

    // ── Poll ────────────────────────────────────────────────────

    IOEvent[] poll(int timeoutMs, IOEvent[] buf) @trusted nothrow
    {
        version (linux)
        {
            if (useUring)
                return uringPoll(uringFd, timeoutMs, buf,
                    cqHead, cqTail, cqRingMask, cqes,
                    sqHead, sqTail, sqRingMask, sqArray, sqesPtr, fdWatches[]);
            return epollPoll(epfd, watchCount, timeoutMs, buf);
        }
        else version (FreeBSD)
        {
            return kqueuePoll(kqfd, watchCount, timeoutMs, buf);
        }
        else version (OSX)
        {
            return kqueuePoll(kqfd, watchCount, timeoutMs, buf);
        }
        else version (Posix)
        {
            return pollPoll(pollfds, timeoutMs, buf);
        }
        else
        {
            return null;
        }
    }

    bool empty() const @safe nothrow { return watchCount == 0; }
}

// ═══════════════════════════════════════════════════════════════
// Backend: io_uring (Linux ≥ 5.1, IORING_OP_POLL_ADD one-shot)
// Falls back to epoll if io_uring_setup returns ENOSYS/EPERM.
// ═══════════════════════════════════════════════════════════════

version (linux)
{
    private extern (C) long syscall(long nr, ...) nothrow @nogc;

    private enum SYS_io_uring_setup = 425;
    private enum SYS_io_uring_enter = 426;

    private enum IORING_OP_POLL_ADD    = 6;
    private enum IORING_OP_POLL_REMOVE = 7;
    private enum IORING_ENTER_GETEVENTS = 1u;
    private enum IORING_OFF_SQ_RING    = 0UL;
    private enum IORING_OFF_CQ_RING    = 0x8000000UL;
    private enum IORING_OFF_SQES       = 0x10000000UL;
    private enum IORING_FEAT_SINGLE_MMAP = 1u << 0;

    private enum POLL_IN  = 0x0001u;
    private enum POLL_OUT = 0x0004u;
    private enum POLL_ERR = 0x0008u;
    private enum POLL_HUP = 0x0010u;

    private struct IORingSQOffsets {
        uint head, tail, ring_mask, ring_entries, flags, dropped, array, resv;
        ulong user_addr;
    }
    private struct IORingCQOffsets {
        uint head, tail, ring_mask, ring_entries, overflow, cqes, flags, resv;
        ulong user_addr;
    }
    private struct IORingParams {
        uint sq_entries, cq_entries, flags, sq_thread_cpu, sq_thread_idle, features, wq_fd;
        uint[3] resv;
        IORingSQOffsets sq_off;
        IORingCQOffsets cq_off;
    }
    // IMPORTANT: keep field layout in sync with kernel ABI (64 bytes)
    private struct IORingSQE {
        ubyte  opcode, flags;
        ushort ioprio;
        int    fd;
        ulong  off;
        ulong  addr;
        uint   len;
        uint   poll_events;
        ulong  user_data;
        ushort buf_index, personality;
        int    splice_fd_in;
        ulong[2] pad;
    }
    private struct IORingCQE {
        ulong user_data;
        int   res;
        uint  flags;
    }
    private struct FdWatch {
        int  fd       = -1;
        bool readable = false;
        bool writable = false;
    }

    // encode fd+events into SQE user_data
    private ulong uringUserData(int fd, uint events) @safe pure nothrow @nogc
    {
        return (cast(ulong) cast(uint) fd) | ((cast(ulong) events) << 32);
    }
    private int uringUDFd(ulong ud) @safe pure nothrow @nogc
    {
        return cast(int) cast(uint)(ud & 0xFFFF_FFFF);
    }

    private int uringSetup(
        uint entries,
        void** sqRingOut, size_t* sqSzOut,
        void** cqRingOut, size_t* cqSzOut,
        IORingSQE** sqesOut, size_t* sqesSzOut,
        uint** sqHead, uint** sqTail, uint* sqMask, uint** sqArray,
        uint** cqHead, uint** cqTail, uint* cqMask, IORingCQE** cqesOut,
        bool* singleMmap) @trusted nothrow
    {
        import core.sys.posix.sys.mman : mmap, PROT_READ, PROT_WRITE,
                                         MAP_SHARED, MAP_FAILED;
        enum MAP_POPULATE = 0x8000;
        IORingParams params;
        long fd = syscall(SYS_io_uring_setup, cast(long) entries, &params);
        if (fd < 0) return -1;
        int ringFd = cast(int) fd;

        *singleMmap = (params.features & IORING_FEAT_SINGLE_MMAP) != 0;

        // Map SQ ring
        size_t sqOff = params.sq_off.array + params.sq_entries * uint.sizeof;
        void* sqPtr = mmap(null, sqOff, PROT_READ | PROT_WRITE,
                           MAP_SHARED | MAP_POPULATE, ringFd, IORING_OFF_SQ_RING);
        if (sqPtr == MAP_FAILED) { import core.sys.posix.unistd : close; close(ringFd); return -1; }
        *sqRingOut = sqPtr;
        *sqSzOut   = sqOff;

        // Map CQ ring (separate mmap unless SINGLE_MMAP)
        size_t cqOff = params.cq_off.cqes + params.cq_entries * IORingCQE.sizeof;
        if (*singleMmap)
        {
            *cqRingOut = sqPtr;
            *cqSzOut   = 0; // not separately munmapped
        }
        else
        {
            void* cqPtr = mmap(null, cqOff, PROT_READ | PROT_WRITE,
                               MAP_SHARED | MAP_POPULATE, ringFd, IORING_OFF_CQ_RING);
            if (cqPtr == MAP_FAILED)
            {
                import core.sys.posix.sys.mman : munmap;
                import core.sys.posix.unistd : close;
                munmap(sqPtr, sqOff);
                close(ringFd);
                return -1;
            }
            *cqRingOut = cqPtr;
            *cqSzOut   = cqOff;
        }

        // Map SQEs
        size_t sqesSz = params.sq_entries * IORingSQE.sizeof;
        void* sqesPtr_ = mmap(null, sqesSz, PROT_READ | PROT_WRITE,
                              MAP_SHARED | MAP_POPULATE, ringFd, IORING_OFF_SQES);
        if (sqesPtr_ == MAP_FAILED)
        {
            import core.sys.posix.sys.mman : munmap;
            import core.sys.posix.unistd : close;
            munmap(sqPtr, sqOff);
            if (!(*singleMmap)) munmap(*cqRingOut, *cqSzOut);
            close(ringFd);
            return -1;
        }
        *sqesOut   = cast(IORingSQE*) sqesPtr_;
        *sqesSzOut = sqesSz;

        // Wire up ring pointers
        *sqHead  = cast(uint*)(sqPtr + params.sq_off.head);
        *sqTail  = cast(uint*)(sqPtr + params.sq_off.tail);
        *sqMask  = *(cast(uint*)(sqPtr + params.sq_off.ring_mask));
        *sqArray = cast(uint*)(sqPtr + params.sq_off.array);

        void* cq = *cqRingOut;
        *cqHead  = cast(uint*)(cq + params.cq_off.head);
        *cqTail  = cast(uint*)(cq + params.cq_off.tail);
        *cqMask  = *(cast(uint*)(cq + params.cq_off.ring_mask));
        *cqesOut = cast(IORingCQE*)(cq + params.cq_off.cqes);

        return ringFd;
    }

    private void uringShutdown(int ringFd,
        void* sqPtr, size_t sqSz,
        void* cqPtr, size_t cqSz,
        IORingSQE* sqesPtr_, size_t sqesSz,
        bool singleMmap) @trusted nothrow
    {
        import core.sys.posix.sys.mman : munmap;
        import core.sys.posix.unistd : close;
        if (sqesPtr_) munmap(sqesPtr_, sqesSz);
        if (!singleMmap && cqPtr) munmap(cqPtr, cqSz);
        if (sqPtr) munmap(sqPtr, sqSz);
        if (ringFd >= 0) close(ringFd);
    }

    private bool uringSubmitSQE(int ringFd, ubyte opcode, int fd, uint events, ulong userData,
        uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @trusted nothrow
    {
        import core.atomic : atomicLoad, atomicStore, MemoryOrder;
        uint tail = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) sqTail);
        uint head = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) sqHead);
        if ((tail - head) > sqMask) return false; // ring full

        uint idx = tail & sqMask;
        sqes[idx] = IORingSQE.init;
        sqes[idx].opcode      = opcode;
        sqes[idx].fd          = fd;
        sqes[idx].poll_events = events;
        sqes[idx].user_data   = userData;
        sqArray[idx]          = idx;
        atomicStore!(MemoryOrder.rel)(*cast(shared uint*) sqTail, tail + 1);

        syscall(SYS_io_uring_enter, cast(long) ringFd, 1L, 0L,
                cast(long) IORING_ENTER_GETEVENTS, null, 0L);
        return true;
    }

    private bool uringWatch(int ringFd, int fd, bool forRead, bool forWrite,
        uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @trusted nothrow
    {
        uint ev = 0;
        if (forRead)  ev |= POLL_IN | POLL_HUP | POLL_ERR;
        if (forWrite) ev |= POLL_OUT;
        return uringSubmitSQE(ringFd, IORING_OP_POLL_ADD, fd, ev,
            uringUserData(fd, ev), sqHead, sqTail, sqMask, sqArray, sqes);
    }

    private void uringRemove(int ringFd, int fd, ulong targetUserData,
        uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes) @trusted nothrow
    {
        // POLL_REMOVE per the io_uring man page: the kernel cancels
        // the ADD whose user_data matches SQE.addr (NOT
        // SQE.user_data — the kernel looks them up by addr). The
        // pre-fix path passed 0 in both fields, which doesn't match
        // the (fd, events)-encoded user_data we put on POLL_ADD; on
        // newer kernels the cancellation silently no-ops, leaving
        // stale ADD registrations behind. Bisected via gdb after
        // tests/integration/fixtures/deno_deploy_compat case 7
        // showed Deno.serve hangs after the v0.7.0 install grew.
        import core.atomic : atomicLoad, atomicStore, MemoryOrder;
        uint tail = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) sqTail);
        uint head = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) sqHead);
        if ((tail - head) > sqMask) return;

        uint idx = tail & sqMask;
        sqes[idx] = IORingSQE.init;
        sqes[idx].opcode     = IORING_OP_POLL_REMOVE;
        sqes[idx].fd         = POLL_REMOVE_FD;
        sqes[idx].addr       = targetUserData;
        sqes[idx].user_data  = 0;
        sqArray[idx]         = idx;
        atomicStore!(MemoryOrder.rel)(*cast(shared uint*) sqTail, tail + 1);

        syscall(SYS_io_uring_enter, cast(long) ringFd, 1L, 0L,
                cast(long) IORING_ENTER_GETEVENTS, null, 0L);
    }

    /// Reconstruct the events bitmask we passed to the original
    /// POLL_ADD so its user_data can be computed for POLL_REMOVE.
    private uint fdWatchEvents(const ref FdWatch w) @safe pure nothrow @nogc
    {
        uint ev = 0;
        if (w.readable) ev |= POLL_IN | POLL_HUP | POLL_ERR;
        if (w.writable) ev |= POLL_OUT;
        return ev;
    }

    private void uringTrackFd(ref FdWatch[MAX_FD_WATCHES] watches, int fd,
        bool forRead, bool forWrite) @trusted nothrow
    {
        foreach (ref w; watches)
        {
            if (w.fd == fd || w.fd == -1)
            {
                w = FdWatch(fd, forRead, forWrite);
                return;
            }
        }
    }

    private void uringUntrackFd(ref FdWatch[MAX_FD_WATCHES] watches, int fd) @trusted nothrow
    {
        foreach (ref w; watches)
        {
            if (w.fd == fd) { w.fd = -1; return; }
        }
    }

    private FdWatch uringLookupFd(ref FdWatch[MAX_FD_WATCHES] watches, int fd) @trusted nothrow
    {
        foreach (ref w; watches)
            if (w.fd == fd) return w;
        return FdWatch(-1, false, false);
    }

    private IOEvent[] uringPoll(int ringFd, int timeoutMs, IOEvent[] buf,
        uint* cqHead, uint* cqTail, uint cqMask, IORingCQE* cqes,
        uint* sqHead, uint* sqTail, uint sqMask, uint* sqArray, IORingSQE* sqes,
        FdWatch[] watches) @trusted nothrow
    {
        import core.atomic : atomicLoad, atomicStore, MemoryOrder;
        // Submit with wait
        uint minComplete = (timeoutMs != 0) ? 1u : 0u;
        syscall(SYS_io_uring_enter, cast(long) ringFd,
                0L, cast(long) minComplete,
                cast(long) IORING_ENTER_GETEVENTS, null, 0L);

        uint head = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) cqHead);
        uint tail = atomicLoad!(MemoryOrder.acq)(*cast(shared uint*) cqTail);

        int count = 0;
        while (head != tail && count < cast(int) buf.length)
        {
            IORingCQE cqe = cqes[head & cqMask];
            head++;

            if (cqe.res < 0) continue; // error on fd

            int fd      = uringUDFd(cqe.user_data);
            uint events = cast(uint)(cqe.user_data >> 32);
            if (fd < 0) continue;

            buf[count++] = IOEvent(
                fd,
                (events & (POLL_IN | POLL_HUP | POLL_ERR)) != 0,
                (events & POLL_OUT) != 0,
            );

            // Re-arm the fd (one-shot → must resubmit)
            FdWatch w;
            foreach (ref fw; watches)
                if (fw.fd == fd) { w = fw; break; }
            if (w.fd >= 0)
                uringWatch(ringFd, fd, w.readable, w.writable,
                    sqHead, sqTail, sqMask, sqArray, sqes);
        }
        atomicStore!(MemoryOrder.rel)(*cast(shared uint*) cqHead, head);
        return buf[0 .. count];
    }
}

// ═══════════════════════════════════════════════════════════════
// Backend: epoll (Linux)
// ═══════════════════════════════════════════════════════════════

version (linux)
{
    private IOEvent[] epollPoll(int epfd, int watchCount,
        int timeoutMs, IOEvent[] buf) @trusted nothrow
    {
        import core.sys.linux.epoll;
        if (epfd < 0 || watchCount == 0) return null;
        epoll_event[64] events;
        int n = epoll_wait(epfd, events.ptr, 64, timeoutMs);
        if (n <= 0) return null;
        int count = 0;
        foreach (i; 0 .. n)
        {
            if (count >= cast(int) buf.length) break;
            uint ev = events[i].events;
            buf[count++] = IOEvent(
                events[i].data.fd,
                (ev & (EPOLLIN | EPOLLHUP | EPOLLERR)) != 0,
                (ev & EPOLLOUT) != 0,
            );
        }
        return buf[0 .. count];
    }
}

// ═══════════════════════════════════════════════════════════════
// Backend: kqueue (macOS, FreeBSD)
// ═══════════════════════════════════════════════════════════════

version (FreeBSD) { version = Kqueue; }
version (OSX)     { version = Kqueue; }

version (Kqueue)
{
    import core.sys.posix.unistd : close;

    // kqueue structs/functions are not in druntime for all platforms,
    // so we declare them here.
    private extern (C) nothrow @nogc
    {
        alias uintptr_t = size_t;

        struct kevent_t
        {
            uintptr_t ident;
            short     filter;
            ushort    flags;
            uint      fflags;
            long      data;
            void*     udata;
        }

        enum : short
        {
            EVFILT_READ  = -1,
            EVFILT_WRITE = -2,
        }

        enum : ushort
        {
            EV_ADD     = 0x0001,
            EV_DELETE  = 0x0002,
            EV_ENABLE  = 0x0004,
            EV_DISABLE = 0x0008,
            EV_EOF     = 0x8000,
            EV_ERROR   = 0x4000,
        }

        int kqueue();
        int kevent(int kq, const(kevent_t)* changelist, int nchanges,
            kevent_t* eventlist, int nevents,
            const(timespec)* timeout);

        struct timespec
        {
            long tv_sec;
            long tv_nsec;
        }
    }

    private int kqueueCreate() @trusted nothrow
    {
        return kqueue();
    }

    private void kqueueShutdown(int kqfd, ref int watchCount) @trusted nothrow
    {
        if (kqfd >= 0)
        {
            close(kqfd);
        }
    }

    private bool kqueueWatch(int kqfd, int fd, bool forRead, bool forWrite) @trusted nothrow
    {
        if (kqfd < 0) return false;
        kevent_t[2] changes;
        int n = 0;
        if (forRead)
        {
            changes[n].ident  = cast(uintptr_t) fd;
            changes[n].filter = EVFILT_READ;
            changes[n].flags  = EV_ADD | EV_ENABLE;
            n++;
        }
        if (forWrite)
        {
            changes[n].ident  = cast(uintptr_t) fd;
            changes[n].filter = EVFILT_WRITE;
            changes[n].flags  = EV_ADD | EV_ENABLE;
            n++;
        }
        if (n == 0) return false;
        return kevent(kqfd, changes.ptr, n, null, 0, null) == 0;
    }

    private void kqueueModify(int kqfd, int fd, bool forRead, bool forWrite) @trusted nothrow
    {
        if (kqfd < 0) return;
        kevent_t[4] changes;
        int n = 0;
        // Remove both first, then add back what's needed
        changes[n] = kevent_t.init;
        changes[n].ident  = cast(uintptr_t) fd;
        changes[n].filter = EVFILT_READ;
        changes[n].flags  = forRead ? (EV_ADD | EV_ENABLE) : EV_DELETE;
        n++;
        changes[n] = kevent_t.init;
        changes[n].ident  = cast(uintptr_t) fd;
        changes[n].filter = EVFILT_WRITE;
        changes[n].flags  = forWrite ? (EV_ADD | EV_ENABLE) : EV_DELETE;
        n++;
        kevent(kqfd, changes.ptr, n, null, 0, null);
    }

    private bool kqueueUnwatch(int kqfd, int fd) @trusted nothrow
    {
        if (kqfd < 0) return false;
        kevent_t[2] changes;
        changes[0].ident  = cast(uintptr_t) fd;
        changes[0].filter = EVFILT_READ;
        changes[0].flags  = EV_DELETE;
        changes[1].ident  = cast(uintptr_t) fd;
        changes[1].filter = EVFILT_WRITE;
        changes[1].flags  = EV_DELETE;
        // EV_DELETE on a non-watched filter returns ENOENT — harmless.
        kevent(kqfd, changes.ptr, 2, null, 0, null);
        return true;
    }

    private IOEvent[] kqueuePoll(int kqfd, int watchCount,
        int timeoutMs, IOEvent[] buf) @trusted nothrow
    {
        if (kqfd < 0 || watchCount == 0) return null;
        kevent_t[64] events;
        timespec ts;
        ts.tv_sec  = timeoutMs / 1000;
        ts.tv_nsec = (timeoutMs % 1000) * 1_000_000;
        int n = kevent(kqfd, null, 0, events.ptr, 64, &ts);
        if (n <= 0) return null;

        // kqueue returns one event per filter per fd. Merge read+write for
        // the same fd into a single IOEvent.
        int count = 0;
        foreach (i; 0 .. n)
        {
            if (count >= cast(int) buf.length) break;
            int fd = cast(int) events[i].ident;
            bool isRead  = events[i].filter == EVFILT_READ;
            bool isWrite = events[i].filter == EVFILT_WRITE;
            bool isErr   = (events[i].flags & (EV_EOF | EV_ERROR)) != 0;

            // Try to merge with the previous entry if same fd
            if (count > 0 && buf[count - 1].fd == fd)
            {
                buf[count - 1].readable = buf[count - 1].readable || isRead || isErr;
                buf[count - 1].writable = buf[count - 1].writable || isWrite;
            }
            else
            {
                buf[count++] = IOEvent(
                    fd,
                    isRead || isErr,
                    isWrite,
                );
            }
        }
        return buf[0 .. count];
    }
}

// ═══════════════════════════════════════════════════════════════
// Backend: poll(2) (generic POSIX fallback)
// ═══════════════════════════════════════════════════════════════

version (linux) {}
else version (FreeBSD) {}
else version (OSX) {}
else version (Posix)
{
    import core.sys.posix.poll;

    private void pollAdd(ref pollfd[] fds, int fd,
        bool forRead, bool forWrite) @trusted nothrow
    {
        short ev = 0;
        if (forRead)  ev |= POLLIN;
        if (forWrite) ev |= POLLOUT;
        try
        {
            fds ~= pollfd(fd, ev, 0);
        }
        catch (Exception) {}
    }

    private void pollModify(ref pollfd[] fds, int fd,
        bool forRead, bool forWrite) @trusted nothrow
    {
        foreach (ref pfd; fds)
        {
            if (pfd.fd == fd)
            {
                pfd.events = 0;
                if (forRead)  pfd.events |= POLLIN;
                if (forWrite) pfd.events |= POLLOUT;
                return;
            }
        }
    }

    private void pollRemove(ref pollfd[] fds, int fd) @trusted nothrow
    {
        foreach (i, ref pfd; fds)
        {
            if (pfd.fd == fd)
            {
                // Swap with last and shrink
                if (i < fds.length - 1)
                    fds[i] = fds[$ - 1];
                try
                {
                    fds = fds[0 .. $ - 1];
                }
                catch (Exception) {}
                return;
            }
        }
    }

    private IOEvent[] pollPoll(pollfd[] fds, int timeoutMs,
        IOEvent[] buf) @trusted nothrow
    {
        if (fds.length == 0) return null;
        int n = core.sys.posix.poll.poll(fds.ptr, cast(uint) fds.length, timeoutMs);
        if (n <= 0) return null;
        int count = 0;
        foreach (ref pfd; fds)
        {
            if (count >= cast(int) buf.length) break;
            if (pfd.revents == 0) continue;
            buf[count++] = IOEvent(
                pfd.fd,
                (pfd.revents & (POLLIN | POLLHUP | POLLERR)) != 0,
                (pfd.revents & POLLOUT) != 0,
            );
        }
        return buf[0 .. count];
    }
}
