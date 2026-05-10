/// Layer 1: Platform abstraction.
///
/// OS-specific operations: memory allocation bridges, threading,
/// I/O primitives, and path handling.
module dun.platform;

version (EngineQuickJS)
{
    public import dun.platform.memory;
}
public import dun.platform.paths;
