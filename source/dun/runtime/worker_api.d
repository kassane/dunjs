module dun.runtime.worker_api;

version (EngineQuickJS):

import dun.engine.quickjs.bindings;
import dun.runtime.globals : DunState;

version (linux)
    extern (C) long syscall(long nr, ...) nothrow @nogc;

void installWorkerAPI(JSContext* ctx, DunState* state) @trusted
{
    auto global = JS_GetGlobalObject(ctx);

    auto workerCtor = JS_NewCFunction2(ctx, &_workerCtor, "Worker", 1,
        JS_CFUNC_constructor, 0);
    JS_SetPropertyStr(ctx, global, "Worker", workerCtor);

    auto sabCtor = JS_NewCFunction2(ctx, &_sabCtor, "SharedArrayBuffer", 1,
        JS_CFUNC_constructor, 0);
    JS_SetPropertyStr(ctx, global, "SharedArrayBuffer", sabCtor);

    auto atomics = JS_NewObject(ctx);
    _addFn(ctx, atomics, "load",           &_atomicsLoad,  2);
    _addFn(ctx, atomics, "store",          &_atomicsStore, 3);
    _addFn(ctx, atomics, "add",            &_atomicsAdd,   3);
    _addFn(ctx, atomics, "sub",            &_atomicsSub,   3);
    _addFn(ctx, atomics, "and",            &_atomicsAnd,   3);
    _addFn(ctx, atomics, "or",             &_atomicsOr,    3);
    _addFn(ctx, atomics, "xor",            &_atomicsXor,   3);
    _addFn(ctx, atomics, "compareExchange",&_atomicsCmpXch,4);
    _addFn(ctx, atomics, "wait",           &_atomicsWait,  4);
    _addFn(ctx, atomics, "notify",         &_atomicsNotify,3);
    JS_SetPropertyStr(ctx, global, "Atomics", atomics);

    JS_FreeValue(ctx, global);
}

// --- Worker constructor ---

private extern (C) JSValue _workerCtor(JSContext* ctx,
    JSValueConst new_target, int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return JS_ThrowTypeError(ctx, "Worker(path) requires a script path");

    size_t pathLen;
    const(char)* pathCstr = JS_ToCStringLen2(ctx, &pathLen, argv[0], false);
    if (!pathCstr)
        return JS_EXCEPTION();
    string scriptPath;
    try { scriptPath = pathCstr[0 .. pathLen].idup; }
    catch (Throwable) { JS_FreeCString(ctx, pathCstr); return JS_EXCEPTION(); }
    JS_FreeCString(ctx, pathCstr);

    auto state = cast(DunState*) JS_GetContextOpaque(ctx);
    try
    {
        import dun.security.permissions : Permission;
        if (!state.permissions.check(Permission.read, scriptPath))
            return JS_ThrowTypeError(ctx, "Worker: requires --allow-read");
    }
    catch (Exception) { return JS_ThrowTypeError(ctx, "Worker: permission check failed"); }

    auto workerObj = JS_NewObject(ctx);
    auto postMsg = JS_NewCFunction(ctx, &_workerPostMessage, "postMessage", 1);
    JS_SetPropertyStr(ctx, workerObj, "postMessage", postMsg);

    import dun.workers.worker : WorkerState, registerWorker, spawnWorker;
    WorkerState wst;
    try { wst = new WorkerState(scriptPath, ctx); }
    catch (Throwable) { JS_FreeValue(ctx, workerObj); return JS_EXCEPTION(); }

    // Store pointer on the object so postMessage can find it
    import std.format : format;
    string ptrStr;
    try { ptrStr = format!"%x"(cast(size_t) cast(void*) wst); }
    catch (Throwable) { JS_FreeValue(ctx, workerObj); return JS_EXCEPTION(); }
    JS_SetPropertyStr(ctx, workerObj, "__wst__",
        JS_NewStringLen(ctx, ptrStr.ptr, ptrStr.length));

    // Store duped worker object in wst for main-side message delivery
    wst.jsWorkerVal = JS_DupValue(ctx, workerObj);
    wst.jsWorkerValSet = true;

    try
    {
        registerWorker(wst);
        spawnWorker(wst);
    }
    catch (Throwable)
    {
        JS_FreeValue(ctx, workerObj);
        return JS_EXCEPTION();
    }

    return workerObj;
}

private extern (C) JSValue _workerPostMessage(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 1)
        return JS_UNDEFINED();

    auto wstProp = JS_GetPropertyStr(ctx, this_val, "__wst__");
    scope (exit) JS_FreeValue(ctx, wstProp);

    size_t len;
    const(char)* cstr = JS_ToCStringLen2(ctx, &len, wstProp, false);
    if (!cstr)
        return JS_UNDEFINED();

    import core.stdc.stdlib : strtoul;
    size_t ptrVal = cast(size_t) strtoul(cstr, null, 16);
    JS_FreeCString(ctx, cstr);

    import dun.workers.worker : WorkerState;
    auto wst = cast(WorkerState) cast(void*) ptrVal;
    if (!wst)
        return JS_UNDEFINED();

    auto jsonStr = JS_JSONStringify(ctx, argv[0], JS_UNDEFINED(), JS_UNDEFINED());
    if (JS_IsException(jsonStr))
        return JS_UNDEFINED();
    scope (exit) JS_FreeValue(ctx, jsonStr);

    size_t jsonLen;
    const(char)* jsonCstr = JS_ToCStringLen2(ctx, &jsonLen, jsonStr, false);
    if (!jsonCstr)
        return JS_UNDEFINED();
    scope (exit) JS_FreeCString(ctx, jsonCstr);

    try { wst.toWorker.send(jsonCstr[0 .. jsonLen].idup); }
    catch (Throwable) {}

    return JS_UNDEFINED();
}

// --- SharedArrayBuffer constructor ---

private extern (C) void _sabFree(JSRuntime* rt, void* opaque, void* ptr) nothrow @nogc
{
    import core.stdc.stdlib : free;
    free(ptr);
}

private extern (C) JSValue _sabCtor(JSContext* ctx,
    JSValueConst new_target, int argc, JSValueConst* argv) nothrow
{
    uint size = 0;
    if (argc >= 1)
        JS_ToUint32(ctx, &size, argv[0]);

    import core.stdc.stdlib : malloc;
    import core.stdc.string : memset;
    auto ptr = cast(ubyte*) malloc(size > 0 ? size : 1);
    if (!ptr)
        return JS_ThrowTypeError(ctx, "SharedArrayBuffer: out of memory");
    memset(ptr, 0, size);

    return JS_NewArrayBuffer(ctx, ptr, size, &_sabFree, null, true);
}

// --- Atomics helpers ---

private int* _taPtr(JSContext* ctx, JSValueConst ta, int idx) nothrow @trusted
{
    size_t byteOff, byteLen, bytesPerElem;
    auto abuf = JS_GetTypedArrayBuffer(ctx, ta, &byteOff, &byteLen, &bytesPerElem);
    scope (exit) JS_FreeValue(ctx, abuf);

    size_t abufSize;
    ubyte* raw = JS_GetArrayBuffer(ctx, &abufSize, abuf);
    if (!raw)
        return null;

    size_t byteIdx = byteOff + cast(size_t) idx * bytesPerElem;
    if (byteIdx + bytesPerElem > abufSize)
        return null;

    return cast(int*)(raw + byteIdx);
}

private int _toI32(JSContext* ctx, JSValueConst v) nothrow @trusted
{
    int i;
    JS_ToInt32(ctx, &i, v);
    return i;
}

private extern (C) JSValue _atomicsLoad(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 2) return JS_UNDEFINED();
    int idx;
    JS_ToInt32(ctx, &idx, argv[1]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicLoad, MemoryOrder;
    return JS_NewInt32(ctx, atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr));
}

private extern (C) JSValue _atomicsStore(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicStore, MemoryOrder;
    atomicStore!(MemoryOrder.seq)(*cast(shared(int)*) ptr, val);
    return JS_NewInt32(ctx, val);
}

private extern (C) JSValue _atomicsAdd(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicFetchAdd;
    return JS_NewInt32(ctx, atomicFetchAdd(*cast(shared(int)*) ptr, val));
}

private extern (C) JSValue _atomicsSub(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicFetchAdd;
    return JS_NewInt32(ctx, atomicFetchAdd(*cast(shared(int)*) ptr, -val));
}

private int _casLoop(int* rawPtr, int function(int) nothrow @safe pure op) nothrow @trusted
{
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) rawPtr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, op(old)))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return old;
}

private extern (C) JSValue _atomicsAnd(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old & val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return JS_NewInt32(ctx, old);
}

private extern (C) JSValue _atomicsOr(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old | val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return JS_NewInt32(ctx, old);
}

private extern (C) JSValue _atomicsXor(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int val = _toI32(ctx, argv[2]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old ^ val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return JS_NewInt32(ctx, old);
}

private extern (C) JSValue _atomicsCmpXch(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 4) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int expected = _toI32(ctx, argv[2]);
    int replacement = _toI32(ctx, argv[3]);
    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    cas(sptr, expected, replacement);
    return JS_NewInt32(ctx, old);
}

private extern (C) JSValue _atomicsWait(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    // Per spec: Atomics.wait is not allowed on the main thread
    import dun.workers.worker : gIsWorkerThread;
    if (!gIsWorkerThread)
    {
        auto s = "not-allowed";
        return JS_NewStringLen(ctx, s.ptr, s.length);
    }

    if (argc < 3) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int expected = _toI32(ctx, argv[2]);
    int timeoutMs = -1;
    if (argc >= 4) JS_ToInt32(ctx, &timeoutMs, argv[3]);

    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();

    import core.atomic : atomicLoad, MemoryOrder;
    if (atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) != expected)
    {
        auto s = "not-equal";
        return JS_NewStringLen(ctx, s.ptr, s.length);
    }

    version (linux)
    {
        enum FUTEX_WAIT = 0;
        enum SYS_futex  = 202; // x86_64

        if (timeoutMs < 0)
        {
            syscall(SYS_futex, ptr, FUTEX_WAIT, expected, null, null, 0);
        }
        else
        {
            import core.sys.posix.time : timespec;
            timespec ts;
            ts.tv_sec  = timeoutMs / 1000;
            ts.tv_nsec = (timeoutMs % 1000) * 1_000_000;
            syscall(SYS_futex, ptr, FUTEX_WAIT, expected, &ts, null, 0);
        }
    }
    else
    {
        // Fallback: spin-sleep
        import core.thread : Thread;
        import core.time : dur;
        long elapsed;
        while (true)
        {
            import core.atomic : atomicLoad;
            if (atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) != expected)
                break;
            if (timeoutMs >= 0 && elapsed >= timeoutMs)
                break;
            Thread.sleep(dur!"msecs"(1));
            elapsed++;
        }
    }

    auto s = "ok";
    return JS_NewStringLen(ctx, s.ptr, s.length);
}

private extern (C) JSValue _atomicsNotify(JSContext* ctx,
    JSValueConst this_val, int argc, JSValueConst* argv) nothrow
{
    if (argc < 2) return JS_UNDEFINED();
    int idx; JS_ToInt32(ctx, &idx, argv[1]);
    int count = (argc >= 3) ? _toI32(ctx, argv[2]) : int.max;

    auto ptr = _taPtr(ctx, argv[0], idx);
    if (!ptr) return JS_UNDEFINED();

    version (linux)
    {
        enum FUTEX_WAKE = 1;
        enum SYS_futex  = 202;
        long woken = syscall(SYS_futex, ptr, FUTEX_WAKE, count, null, null, 0);
        return JS_NewInt32(ctx, cast(int) woken);
    }
    else
    {
        return JS_NewInt32(ctx, 0);
    }
}

// --- Utilities ---

private void _addFn(JSContext* ctx, JSValue obj, const(char)* name,
    JSCFunction fn, int length) nothrow @trusted
{
    JS_SetPropertyStr(ctx, obj, name, JS_NewCFunction(ctx, fn, name, length));
}
