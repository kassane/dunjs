module dun.workers.shared_memory;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset;
import core.sync.mutex : Mutex;

private struct SABEntry
{
    void* ptr;
    size_t len;
    int refCount;
}

private __gshared SABEntry[] gRegistry;
private __gshared Mutex gMutex;

shared static this()
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
                e = SABEntry(ptr, len, 1);
                return cast(int) i;
            }
        }
        gRegistry ~= SABEntry(ptr, len, 1);
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
    synchronized (gMutex)
    {
        if (id >= 0 && id < cast(int) gRegistry.length)
            gRegistry[id].refCount++;
    }
}

void sabUnref(int id) @trusted
{
    synchronized (gMutex)
    {
        if (id >= 0 && id < cast(int) gRegistry.length && gRegistry[id].ptr !is null)
        {
            gRegistry[id].refCount--;
            if (gRegistry[id].refCount <= 0)
            {
                free(gRegistry[id].ptr);
                gRegistry[id].ptr = null;
            }
        }
    }
}
