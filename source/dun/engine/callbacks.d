module dun.engine.callbacks;


/++
 + `@trusted policy`: global NativeCallback registry — slot ID →
 + function pointer table. Every `@trusted` is one of:
 +   1. `__gshared` table mutation under the writer mutex.
 +   2. Lockfree read on the array.length (see `get()` for the
 +     append-only invariant).
 +/
import dun.engine.iface : NativeCallback;
import core.sync.mutex : Mutex;

// Global slot registry shared across all engines + worker threads in
// the same process. Worker threads each spin up their own engine and
// call `register()` concurrently, so the registry needs locking even
// though it's mostly write-once-per-callback.
//
// `get()` is on every native dispatch so we trade a TOCTOU race
// (table grew after we read .length) for atomic-load-only on the
// fast path: the table only grows (never shrinks), so a stale length
// just means we miss a freshly-registered slot, which can never be
// dispatched-to before its writer publishes the id back out.
private __gshared NativeCallback[] _table;
private __gshared int _nextId;
private __gshared Mutex _registerMu;

enum MAX_CALLBACK_SLOTS = 32_767;
enum CALLBACK_TABLE_GROWTH = 64;

shared static this() @trusted
{
    _registerMu = new Mutex();
}

int register(NativeCallback cb) nothrow @trusted
{
    try
    {
        _registerMu.lock_nothrow();
        scope (exit) _registerMu.unlock_nothrow();
        // TIGER_STYLE: int16 magic values in QJS mean we cap at 32767.
        // Overflowing here corrupts dispatch -- fail loud at the source.
        assert(_nextId < MAX_CALLBACK_SLOTS,
            "NativeCallback slot exhaustion -- cache function handles instead of creating per-call");
        if (_nextId >= cast(int) _table.length)
            _table.length = _table.length + CALLBACK_TABLE_GROWTH;
        _table[_nextId] = cb;
        return _nextId++;
    }
    catch (Exception)
    {
        return -1;
    }
}

/++
 + `@trusted`: lockfree read from an append-only global table.
 + The lock-free justification is in the function body comment;
 + the @trusted is for the read of `_table` which is `__gshared`
 + (D's @safe forbids access to module-level mutable state, even
 + when the access is provably race-free).
 +/
NativeCallback get(int id) nothrow @nogc @trusted
{
    // No lock on the read path: the table only grows, so reading a
    // valid id is safe -- worst case is a torn `.length` that's
    // smaller than the actual one (harmless: the id won't be in scope
    // yet for any thread that hasn't seen the writer's id return).
    if (id >= 0 && id < cast(int) _table.length)
        return _table[id];
    return null;
}
