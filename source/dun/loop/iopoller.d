module dun.loop.iopoller;

// Minimal I/O readiness poller.
// Linux: epoll (level-triggered). Other platforms: stub (timer-only mode).

struct IOEvent
{
    int fd;
    bool readable;
    bool writable;
}

struct IOPoller
{
    private int epfd = -1;
    private int watchCount = 0;

    void initialize() @trusted nothrow
    {
        version (linux)
        {
            import core.sys.linux.epoll : epoll_create1;
            epfd = epoll_create1(0);
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
    }

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
    }

    // Modify an already-watched fd's interest set.
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
    }

    // Blocks up to timeoutMs. Fills buf with ready events; returns used slice.
    IOEvent[] poll(int timeoutMs, IOEvent[] buf) @trusted nothrow
    {
        version (linux)
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
        else
        {
            return null;
        }
    }

    bool empty() const @safe nothrow { return watchCount == 0; }
}
