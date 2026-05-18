module dun.loop.async;

import dun.engine.iface : IJSEngine, JSHandle;
import core.atomic : atomicStore, atomicLoad, MemoryOrder;

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

private AsyncTask*[] tasks;

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
    auto task = new AsyncTask();
    task.engine = engine;
    task.resolve = resolve;
    task.reject = reject;
    task.transform = transform;
    atomicStore!(MemoryOrder.rel)(task.completed, false);

    tasks ~= task;

    import core.thread : Thread;
    auto t = new Thread({
        auto r = work();
        task.result = r.value;
        task.error = r.error;
        atomicStore!(MemoryOrder.rel)(task.completed, true);
    });
    t.isDaemon = true;
    t.start();
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
                engine.callFunction(task.reject, engine.newUndefined(), [errVal]);
                engine.freeValue(errVal);
            }
            else if (task.transform !is null)
            {
                auto val = task.transform(engine, task.result);
                engine.callFunction(task.resolve, engine.newUndefined(), [val]);
                engine.freeValue(val);
            }
            else
            {
                auto val = engine.newString(task.result);
                engine.callFunction(task.resolve, engine.newUndefined(), [val]);
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
