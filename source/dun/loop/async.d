module dun.loop.async;


/// `@trusted policy`: async work pool (CPU-bound work runs on a
/// worker thread, result resolves the promise on the main thread).
/// Every `@trusted` is one of:
///
///   1. `new Thread` + `Semaphore` + `Mutex` for the worker pool
///      (lazy-initialized on first `asyncSubmit`). 8 workers.
///   2. `atomicLoad` / `atomicStore` on `task.completed` for
///      cross-thread signalling.
///   3. `cast(JSHandle)` of resolve/reject handles passed across
///      to the worker thread (the worker doesn't touch JSC; only
///      stores `task.result` / `task.error`; main thread calls
///      `callFunction` to resolve).
import dun.engine.iface : IJSEngine, JSHandle;
import core.atomic : atomicStore, atomicLoad, MemoryOrder;
import core.sync.mutex : Mutex;
import core.sync.semaphore : Semaphore;
import core.thread : Thread;

alias ResultTransform = JSHandle delegate(IJSEngine engine, string result) @trusted;

/// `@mustuse` (DIP 1038) catches the silent-drop bug where the
/// async result is built but never delivered to its promise.
import core.attribute : mustuse;
@mustuse
struct AsyncResult
{
    string value;
    string error;

    static AsyncResult ok(string v) nothrow @safe { return AsyncResult(v, ""); }
    static AsyncResult fail(string e) nothrow @safe { return AsyncResult("", e); }
}

private struct AsyncTask
{
    IJSEngine engine;
    JSHandle resolve;
    JSHandle reject;
    string result;
    string error;
    ResultTransform transform;
    shared bool completed;
}

private struct WorkItem
{
    AsyncTask* task;
    AsyncResult delegate() @trusted nothrow work;
}

private __gshared AsyncTask*[] tasks;
private __gshared WorkItem[] workQueue;
private __gshared Mutex queueMutex;
private __gshared Semaphore queueSem;
private __gshared Thread[] poolThreads;
private __gshared bool poolInitialized;

/// Thread pool size. Most fetches are I/O-bound (TCP connect +
/// HTTP roundtrip + TLS handshake). 8 workers handles sustained
/// concurrent load while keeping the resident memory + GC pressure
/// from per-thread Thread objects low.
///
/// v1.1.26 (this commit): per-fetch `new Thread()` accumulation
/// was the JSC `deno_deploy_compat` flake root cause. After ~20-30
/// fetches, the cumulative D GC + JSC concurrent-GC pressure tipped
/// fetch into 5s+ stalls. Pooling eliminates the Thread allocation
/// path; the workers sleep on the semaphore between jobs.
private enum POOL_SIZE = 8;

private void initPool() @trusted nothrow
{
    if (poolInitialized) return;
    try
    {
        queueMutex = new Mutex();
        queueSem = new Semaphore(0);
        for (size_t i = 0; i < POOL_SIZE; i++)
        {
            auto t = new Thread(&poolWorker);
            t.isDaemon = true;
            t.start();
            poolThreads ~= t;
        }
        poolInitialized = true;
    }
    catch (Throwable) {}
}

private void poolWorker() @trusted nothrow
{
    while (true)
    {
        try
        {
            queueSem.wait();
            WorkItem item;
            bool got = false;
            synchronized (queueMutex)
            {
                if (workQueue.length > 0)
                {
                    item = workQueue[0];
                    workQueue = workQueue[1 .. $];
                    got = true;
                }
            }
            if (!got) continue;

            auto r = item.work();
            item.task.result = r.value;
            item.task.error = r.error;
            atomicStore!(MemoryOrder.rel)(item.task.completed, true);
        }
        catch (Throwable) {}
    }
}

void asyncSubmit(IJSEngine engine, JSHandle resolve, JSHandle reject,
    string delegate() @trusted work,
    ResultTransform transform = null) @trusted
{
    asyncSubmitSafe(engine, resolve, reject, () @trusted nothrow {
        try
        {
            return AsyncResult.ok(work());
        }
        catch (Exception e)
        {
            try { return AsyncResult.fail(e.msg); }
            catch (Exception) { return AsyncResult.fail("async operation failed"); }
        }
    }, transform);
}

void asyncSubmitSafe(IJSEngine engine, JSHandle resolve, JSHandle reject,
    AsyncResult delegate() @trusted nothrow work,
    ResultTransform transform = null) @trusted
{
    initPool();

    auto task = new AsyncTask();
    task.engine = engine;
    task.resolve = resolve;
    task.reject = reject;
    task.transform = transform;
    atomicStore!(MemoryOrder.rel)(task.completed, false);

    tasks ~= task;

    synchronized (queueMutex)
    {
        workQueue ~= WorkItem(task, work);
    }
    queueSem.notify();
}

int asyncDrain() @trusted
{
    int drained = 0;

    // Snapshot the current length — resolving a task may submit new tasks
    // via .then() handlers, appending to `tasks`. Process only the snapshot;
    // newly added tasks are picked up on the next drain cycle.
    auto snapshot = tasks.length;
    size_t writeIdx = 0;

    foreach (i; 0 .. snapshot)
    {
        auto task = tasks[i];
        if (atomicLoad!(MemoryOrder.acq)(task.completed))
        {
            auto engine = task.engine;
            if (task.error.length > 0)
            {
                auto errResult = engine.eval(
                    "new Error('" ~ escapeForEval(task.error) ~ "')", "<async>");
                auto errVal = errResult.isError
                    ? engine.newString(task.error) : errResult.value;
                /* `callFunction` returns an owned protected value per
                   the cross-backend contract — discard via freeValue.
                   v1.1.7: previously discarded directly, leaking one
                   JSValueProtect per promise resolution × N fetches
                   on JSC. `newUndefined()` returns the JSC singleton
                   which doesn't need freeing. */
                engine.freeValue(engine.callFunction(task.reject, engine.newUndefined(), [errVal]));
                engine.freeValue(errVal);
            }
            else if (task.transform !is null)
            {
                auto val = task.transform(engine, task.result);
                engine.freeValue(engine.callFunction(task.resolve, engine.newUndefined(), [val]));
                engine.freeValue(val);
            }
            else
            {
                auto val = engine.newString(task.result);
                engine.freeValue(engine.callFunction(task.resolve, engine.newUndefined(), [val]));
                engine.freeValue(val);
            }
            engine.freeValue(task.resolve);
            engine.freeValue(task.reject);
            drained++;
        }
        else
        {
            tasks[writeIdx++] = task;
        }
    }

    // Compact: keep incomplete tasks from snapshot + any newly appended tasks
    if (tasks.length > snapshot)
    {
        auto newTasks = tasks[snapshot .. $];
        foreach (j, t; newTasks)
            tasks[writeIdx + j] = t;
        tasks.length = writeIdx + newTasks.length;
    }
    else
    {
        tasks.length = writeIdx;
    }
    tasks.assumeSafeAppend();

    return drained;
}

bool asyncHasWork() @trusted nothrow
{
    return tasks.length > 0;
}

private string escapeForEval(string s) @safe
{
    string r;
    foreach (c; s)
    {
        if (c == '\'') r ~= "\\'";
        else if (c == '\\') r ~= "\\\\";
        else if (c == '\n') r ~= "\\n";
        else if (c == '\r') r ~= "\\r";
        else r ~= c;
    }
    return r;
}
