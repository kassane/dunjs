module dun.platform.memory;


/++
 + `@trusted policy`: low-level memory utilities (zero, copy, fill)
 + for the @nogc hot paths. Each function wraps `core.stdc.string`
 + `@system` calls with `@trusted` (length and overlap bounds are
 + asserted by the caller).
 +/
version (EngineQuickJS):

import core.stdc.stdlib : malloc, free, realloc;
import dun.engine.quickjs.bindings : JSMallocFunctions, JSMallocState;

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
        return 0;
    }
}
