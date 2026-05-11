module dun.loop.iopoller;

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
        private int epfd = -1;
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
            import core.sys.linux.epoll : epoll_create1;
            epfd = epoll_create1(0);
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
            if (epfd >= 0)
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
