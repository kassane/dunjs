module dun.engine.callbacks;

import dun.engine.iface : NativeCallback;

private __gshared NativeCallback[] _table;
private __gshared int _nextId;

int register(NativeCallback cb) nothrow @trusted
{
    try
    {
        if (_nextId >= cast(int) _table.length)
            _table.length = _table.length + 64;
        _table[_nextId] = cb;
        return _nextId++;
    }
    catch (Exception)
    {
        return -1;
    }
}

NativeCallback get(int id) nothrow @nogc @trusted
{
    if (id >= 0 && id < cast(int) _table.length)
        return _table[id];
    return null;
}
