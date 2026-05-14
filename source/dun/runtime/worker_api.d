module dun.runtime.worker_api;

import dun.engine.iface : IJSEngine, JSHandle;
import dun.runtime.globals : DunState;

version (linux)
{
    extern (C) long syscall(long nr, ...) nothrow @nogc;

    private enum {
        FUTEX_WAIT = 0,
        FUTEX_WAKE = 1,
    }

    version (X86_64)
        private enum SYS_futex = 202;
    else version (X86)
        private enum SYS_futex = 240;
    else version (AArch64)
        private enum SYS_futex = 98;
    else version (ARM)
        private enum SYS_futex = 240;
    else
        static assert(false, "SYS_futex not defined for this architecture");
}
else
{
    import core.sync.mutex : Mutex;
    import core.sync.condition : Condition;

    private struct WaitEntry
    {
        Condition cond;
        bool notified;
    }

    private __gshared Mutex gWaitMutex;
    private __gshared WaitEntry[][size_t] gWaiters;

    shared static this() @trusted
    {
        gWaitMutex = new Mutex();
    }
}

void installWorkerAPI(IJSEngine engine, DunState* state) @trusted
{
    assert(engine !is null, "Null engine in installWorkerAPI");
    assert(state !is null, "Null DunState in installWorkerAPI");

    auto global = engine.getGlobal();

    engine.setProperty(global, "__workerCreate",
        engine.newFunction(&_workerCtor, "__workerCreate", 1));
    engine.setProperty(global, "__sabCreate",
        engine.newFunction(&_sabCtor, "__sabCreate", 1));
    engine.setProperty(global, "__int32ArrayCreate",
        engine.newFunction(&_int32ArrayCtor, "__int32ArrayCreate", 1));

    engine.eval(
        `globalThis.Worker = function Worker(p) { return __workerCreate(p); };`
        ~ `var __NativeInt32Array = globalThis.Int32Array;`
        ~ `var __NativeSAB = globalThis.SharedArrayBuffer;`
        ~ `globalThis.SharedArrayBuffer = function SharedArrayBuffer(n) { return __sabCreate(n); };`
        ~ `globalThis.Int32Array = function Int32Array(a) {`
        ~ `  if (a && a.__isSAB) return __int32ArrayCreate(a);`
        ~ `  return new __NativeInt32Array(a);`
        ~ `};`
        ~ `globalThis.Int32Array.BYTES_PER_ELEMENT = 4;`
        ~ `globalThis.Int32Array.prototype = __NativeInt32Array.prototype;`,
        "<worker-init>");

    auto atomics = engine.newObject();
    engine.setProperty(atomics, "load",            engine.newFunction(&_atomicsLoad,  "load",  2));
    engine.setProperty(atomics, "store",           engine.newFunction(&_atomicsStore, "store", 3));
    engine.setProperty(atomics, "add",             engine.newFunction(&_atomicsAdd,   "add",   3));
    engine.setProperty(atomics, "sub",             engine.newFunction(&_atomicsSub,   "sub",   3));
    engine.setProperty(atomics, "and",             engine.newFunction(&_atomicsAnd,   "and",   3));
    engine.setProperty(atomics, "or",              engine.newFunction(&_atomicsOr,    "or",    3));
    engine.setProperty(atomics, "xor",             engine.newFunction(&_atomicsXor,   "xor",   3));
    engine.setProperty(atomics, "exchange",         engine.newFunction(&_atomicsExchange,"exchange", 3));
    engine.setProperty(atomics, "compareExchange", engine.newFunction(&_atomicsCmpXch,"compareExchange", 4));
    engine.setProperty(atomics, "isLockFree",      engine.newFunction(&_atomicsIsLockFree,"isLockFree", 1));
    engine.setProperty(atomics, "wait",            engine.newFunction(&_atomicsWait,  "wait",  4));
    engine.setProperty(atomics, "waitAsync",       engine.newFunction(&_atomicsWaitAsync, "waitAsync", 4));
    engine.setProperty(atomics, "notify",          engine.newFunction(&_atomicsNotify,"notify", 3));
    engine.setProperty(global, "Atomics", atomics);

    auto suppressRes = engine.eval(suppressedErrorPolyfill(), "<suppressed-error>");
    if (!suppressRes.isError)
        engine.freeValue(suppressRes.value);

    engine.freeValue(global);
}

// --- Worker constructor ---

private JSHandle _workerCtor(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Worker constructor");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in Worker constructor");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("Worker(path) requires a script path");

    auto scriptPath = engine.extractString(args[0]);

    import dun.security.permissions : Permission;
    if (!state.permissions.check(Permission.read, scriptPath))
        return engine.throwTypeError("Worker: requires --allow-read");

    auto workerObj = engine.newObject();
    engine.setProperty(workerObj, "postMessage",
        engine.newFunction(&_workerPostMessage, "postMessage", 1));

    import dun.workers.worker : WorkerState, registerWorker, spawnWorker;
    WorkerState wst;
    try { wst = new WorkerState(scriptPath, engine); }
    catch (Throwable) { return engine.throwTypeError("Worker: failed to create state"); }

    import std.format : format;
    string ptrStr;
    try { ptrStr = format!"%x"(cast(size_t) cast(void*) wst); }
    catch (Throwable) { return engine.throwTypeError("Worker: internal error"); }
    engine.setProperty(workerObj, "__wst__", engine.newString(ptrStr));

    wst.jsWorkerVal = engine.dupValue(workerObj);
    wst.jsWorkerValSet = true;

    try
    {
        registerWorker(wst);
        spawnWorker(wst);
    }
    catch (Throwable)
    {
        return engine.throwTypeError("Worker: failed to spawn");
    }

    return workerObj;
}

private JSHandle _workerPostMessage(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Worker.postMessage");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in Worker.postMessage");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newUndefined();

    auto wstProp = engine.getProperty(thisVal, "__wst__");
    auto ptrHex = engine.extractString(wstProp);
    engine.freeValue(wstProp);

    if (ptrHex.length == 0)
        return engine.newUndefined();

    import core.stdc.stdlib : strtoul;
    import std.string : toStringz;
    size_t ptrVal = cast(size_t) strtoul(ptrHex.toStringz, null, 16);

    import dun.workers.worker : WorkerState, jsonStringify;
    auto wst = cast(WorkerState) cast(void*) ptrVal;
    if (!wst)
        return engine.newUndefined();

    auto jsonStr = jsonStringify(engine, args[0]);
    if (jsonStr is null)
        return engine.newUndefined();

    try { wst.toWorker.send(jsonStr); }
    catch (Throwable) {}

    return engine.newUndefined();
}

// --- SharedArrayBuffer constructor ---

private JSHandle _sabCtor(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in SharedArrayBuffer constructor");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in SharedArrayBuffer");
    auto engine = state.engine;

    int size = 0;
    if (args.length >= 1)
        size = engine.extractInt(args[0]);
    if (size < 0) size = 0;

    import dun.workers.shared_memory : sabAlloc;
    int sabId = sabAlloc(cast(size_t) size);
    if (sabId < 0)
        return engine.throwTypeError("SharedArrayBuffer: out of memory");

    auto obj = engine.newObject();
    engine.setProperty(obj, "byteLength", engine.newInt(size));
    engine.setProperty(obj, "__sabId", engine.newInt(sabId));
    engine.setProperty(obj, "__isSAB", engine.newBool(true));
    return obj;
}

// --- Int32Array constructor (SharedArrayBuffer-aware) ---

private JSHandle _int32ArrayCtor(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Int32Array constructor");
    auto state = cast(DunState*) ctx;
    assert(state !is null && state.engine !is null, "Invalid DunState in Int32Array");
    auto engine = state.engine;

    if (args.length < 1)
    {
        auto obj = engine.newObject();
        engine.setProperty(obj, "length", engine.newInt(0));
        engine.setProperty(obj, "BYTES_PER_ELEMENT", engine.newInt(4));
        return obj;
    }

    auto isSAB = engine.getProperty(args[0], "__isSAB");
    bool isSabObj = engine.isBool(isSAB) && engine.extractBool(isSAB);
    engine.freeValue(isSAB);

    if (isSabObj)
    {
        auto sabIdH = engine.getProperty(args[0], "__sabId");
        int sabId = engine.extractInt(sabIdH);
        engine.freeValue(sabIdH);

        auto byteLenH = engine.getProperty(args[0], "byteLength");
        int byteLen = engine.extractInt(byteLenH);
        engine.freeValue(byteLenH);

        int elemLen = byteLen / 4;

        import dun.workers.shared_memory : sabRef;
        sabRef(sabId);

        auto obj = engine.newObject();
        engine.setProperty(obj, "__sabId", engine.newInt(sabId));
        engine.setProperty(obj, "__byteOffset", engine.newInt(0));
        engine.setProperty(obj, "buffer", engine.dupValue(args[0]));
        engine.setProperty(obj, "length", engine.newInt(elemLen));
        engine.setProperty(obj, "byteLength", engine.newInt(byteLen));
        engine.setProperty(obj, "byteOffset", engine.newInt(0));
        engine.setProperty(obj, "BYTES_PER_ELEMENT", engine.newInt(4));
        engine.setProperty(obj, "__isInt32Array", engine.newBool(true));
        return obj;
    }

    if (engine.isNumber(args[0]))
    {
        int len = engine.extractInt(args[0]);
        if (len < 0) len = 0;
        auto obj = engine.newObject();
        engine.setProperty(obj, "length", engine.newInt(len));
        engine.setProperty(obj, "BYTES_PER_ELEMENT", engine.newInt(4));
        return obj;
    }

    return engine.newObject();
}

// --- Atomics helpers ---

private int* _getAtomicPtr(IJSEngine engine, JSHandle ta, int idx) @trusted
{
    assert(engine !is null, "Null engine in Atomics typed array access");

    auto sabIdH = engine.getProperty(ta, "__sabId");
    if (engine.isUndefined(sabIdH) || engine.isNull(sabIdH))
    {
        engine.freeValue(sabIdH);
        return null;
    }
    int sabId = engine.extractInt(sabIdH);
    engine.freeValue(sabIdH);

    import dun.workers.shared_memory : sabGet;
    void* ptr;
    size_t len;
    if (!sabGet(sabId, ptr, len))
        return null;

    auto offH = engine.getProperty(ta, "__byteOffset");
    int byteOff = engine.isNumber(offH) ? engine.extractInt(offH) : 0;
    engine.freeValue(offH);

    size_t byteIdx = cast(size_t)(byteOff + idx * 4);
    if (byteIdx + 4 > len)
        return null;

    return cast(int*)(cast(ubyte*) ptr + byteIdx);
}

private JSHandle _atomicsLoad(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.load");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, MemoryOrder;
    return engine.newInt(atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr));
}

private JSHandle _atomicsStore(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.store");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicStore, MemoryOrder;
    atomicStore!(MemoryOrder.seq)(*cast(shared(int)*) ptr, val);
    return engine.newInt(val);
}

private JSHandle _atomicsAdd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.add");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicFetchAdd;
    return engine.newInt(atomicFetchAdd(*cast(shared(int)*) ptr, val));
}

private JSHandle _atomicsSub(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.sub");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicFetchAdd;
    return engine.newInt(atomicFetchAdd(*cast(shared(int)*) ptr, -val));
}

private JSHandle _atomicsAnd(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.and");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old & val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return engine.newInt(old);
}

private JSHandle _atomicsOr(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.or");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old | val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return engine.newInt(old);
}

private JSHandle _atomicsXor(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.xor");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, old ^ val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return engine.newInt(old);
}

private JSHandle _atomicsExchange(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.exchange");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int val = engine.extractInt(args[2]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    while (!cas(sptr, old, val))
        old = atomicLoad!(MemoryOrder.seq)(*sptr);
    return engine.newInt(old);
}

private JSHandle _atomicsIsLockFree(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.isLockFree");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 1) return engine.newBool(false);
    int sz = engine.extractInt(args[0]);
    return engine.newBool(sz == 1 || sz == 2 || sz == 4 || sz == 8);
}

private JSHandle _atomicsCmpXch(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.compareExchange");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 4) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int expected = engine.extractInt(args[2]);
    int replacement = engine.extractInt(args[3]);
    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();
    import core.atomic : atomicLoad, cas, MemoryOrder;
    auto sptr = cast(shared(int)*) ptr;
    int old = atomicLoad!(MemoryOrder.seq)(*sptr);
    cas(sptr, expected, replacement);
    return engine.newInt(old);
}

private JSHandle _atomicsWait(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.wait");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    import dun.workers.worker : gIsWorkerThread;
    if (!gIsWorkerThread)
        return engine.newString("not-allowed");

    if (args.length < 3) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int expected = engine.extractInt(args[2]);
    int timeoutMs = -1;
    if (args.length >= 4)
        timeoutMs = engine.extractInt(args[3]);

    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();

    import core.atomic : atomicLoad, MemoryOrder;
    if (atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) != expected)
        return engine.newString("not-equal");

    version (linux)
    {
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
        auto addr = cast(size_t) ptr;
        auto entry = WaitEntry(new Condition(gWaitMutex), false);

        gWaitMutex.lock();
        if (addr !in gWaiters) gWaiters[addr] = [];
        gWaiters[addr] ~= entry;
        gWaitMutex.unlock();

        scope(exit)
        {
            gWaitMutex.lock();
            if (auto arr = addr in gWaiters)
            {
                import std.algorithm : remove;
                foreach (i, ref e; *arr)
                    if (e.cond is entry.cond) { *arr = (*arr).remove(i); break; }
            }
            gWaitMutex.unlock();
        }

        gWaitMutex.lock();
        if (timeoutMs < 0)
        {
            while (!entry.notified &&
                   atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) == expected)
                entry.cond.wait();
        }
        else
        {
            import core.time : dur;
            while (!entry.notified &&
                   atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) == expected)
            {
                if (!entry.cond.wait(dur!"msecs"(timeoutMs)))
                    break;
            }
        }
        gWaitMutex.unlock();

        if (atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr) != expected)
            return engine.newString("ok");
        if (entry.notified)
            return engine.newString("ok");
        return engine.newString("timed-out");
    }

    return engine.newString("ok");
}

private JSHandle _atomicsNotify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.notify");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;
    if (args.length < 2) return engine.newUndefined();
    int idx = engine.extractInt(args[1]);
    int count = (args.length >= 3) ? engine.extractInt(args[2]) : int.max;

    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr) return engine.newUndefined();

    version (linux)
    {
        long woken = syscall(SYS_futex, ptr, FUTEX_WAKE, count, null, null, 0);
        return engine.newInt(cast(int) woken);
    }
    else
    {
        auto addr = cast(size_t) ptr;
        int woken = 0;
        gWaitMutex.lock();
        if (auto arr = addr in gWaiters)
        {
            foreach (ref e; *arr)
            {
                if (woken >= count) break;
                e.notified = true;
                e.cond.notify();
                woken++;
            }
        }
        gWaitMutex.unlock();
        return engine.newInt(woken);
    }
}

private JSHandle _atomicsWaitAsync(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in Atomics.waitAsync");
    auto state = cast(DunState*) ctx;
    auto engine = state.engine;

    if (args.length < 3)
        return engine.throwTypeError("Atomics.waitAsync requires 3 arguments");

    int idx = engine.extractInt(args[1]);
    int expected = engine.extractInt(args[2]);

    auto ptr = _getAtomicPtr(engine, args[0], idx);
    if (!ptr)
        return engine.throwTypeError("Atomics.waitAsync: invalid typed array");

    import core.atomic : atomicLoad, MemoryOrder;
    int current = atomicLoad!(MemoryOrder.seq)(*cast(shared(int)*) ptr);

    auto result = engine.newObject();
    if (current != expected)
    {
        auto resolvedPromise = engine.eval(
            `Promise.resolve("not-equal")`, "<atomics-waitAsync>");
        engine.setProperty(result, "async", engine.newBool(true));
        engine.setProperty(result, "value", resolvedPromise.value);
    }
    else
    {
        auto resolvedPromise = engine.eval(
            `Promise.resolve("ok")`, "<atomics-waitAsync>");
        engine.setProperty(result, "async", engine.newBool(true));
        engine.setProperty(result, "value", resolvedPromise.value);
    }
    return result;
}

string suppressedErrorPolyfill() @safe pure nothrow @nogc
{
    return `(function() {
  if (typeof globalThis.SuppressedError === 'undefined') {
    globalThis.SuppressedError = function SuppressedError(error, suppressed, message) {
      var e = new Error(message);
      e.name = 'SuppressedError';
      e.error = error;
      e.suppressed = suppressed;
      Object.setPrototypeOf(e, SuppressedError.prototype);
      return e;
    };
    SuppressedError.prototype = Object.create(Error.prototype);
    SuppressedError.prototype.constructor = SuppressedError;
    SuppressedError.prototype.name = 'SuppressedError';
  }
})();`;
}
