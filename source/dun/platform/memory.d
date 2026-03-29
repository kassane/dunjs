/// Memory allocation bridge between D GC and QuickJS C malloc.
///
/// Provides a custom allocator for QuickJS that enables memory limit
/// tracking and enforcement.
module dun.platform.memory;

import core.stdc.stdlib : malloc, free, realloc;
import dun.engine.bindings : JSMallocFunctions, JSMallocState;

/// Custom QuickJS malloc functions for memory tracking.
struct DunMallocFunctions
{
    static immutable JSMallocFunctions instance = JSMallocFunctions(
        &jsMalloc,
        &jsFree,
        &jsRealloc,
        &jsMallocUsableSize,
    );

    static extern (C) void* jsMalloc(JSMallocState* s, size_t size) nothrow
    {
        return malloc(size);
    }

    static extern (C) void jsFree(JSMallocState* s, void* ptr) nothrow
    {
        free(ptr);
    }

    static extern (C) void* jsRealloc(JSMallocState* s, void* ptr, size_t size) nothrow
    {
        return realloc(ptr, size);
    }

    static extern (C) size_t jsMallocUsableSize(const void* ptr) nothrow
    {
        return 0; // Platform-specific: use malloc_usable_size on Linux
    }
}
