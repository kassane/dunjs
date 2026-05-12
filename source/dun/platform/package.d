/// Platform abstraction (memory, threading, OS I/O).
module dun.platform;

version (EngineQuickJS)
{
    public import dun.platform.memory;
}
public import dun.platform.paths;
public import dun.platform.arena;
