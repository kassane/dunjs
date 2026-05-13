module dun.workers.channel;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;

final class Channel(T)
{
    private T[] queue;
    private Mutex mutex;
    private Condition cond;
    private bool closed_;

    this()
    {
        mutex = new Mutex();
        cond = new Condition(mutex);
    }

    void send(T item) nothrow @trusted
    {
        try
        {
            synchronized (mutex)
            {
                if (!closed_)
                {
                    queue ~= item;
                    cond.notify();
                }
            }
        }
        catch (Throwable) {}
    }

    bool tryRecv(out T item) nothrow @trusted
    {
        try
        {
            synchronized (mutex)
            {
                if (queue.length == 0)
                    return false;
                item = queue[0];
                queue = queue[1 .. $];
                return true;
            }
        }
        catch (Throwable) { return false; }
    }

    void close() nothrow @trusted
    {
        try { synchronized (mutex) { closed_ = true; cond.notifyAll(); } }
        catch (Throwable) {}
    }

    bool isClosed() nothrow @trusted
    {
        try { synchronized (mutex) return closed_; } catch (Throwable) { return true; }
    }
    bool empty() nothrow @trusted
    {
        try { synchronized (mutex) return queue.length == 0; } catch (Throwable) { return true; }
    }
}

alias MessageChannel = Channel!string;
