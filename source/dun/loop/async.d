module dun.loop.async;

import dun.engine.iface : IJSEngine, JSHandle;
import core.atomic : atomicStore, atomicLoad, MemoryOrder;

alias ResultTransform = JSHandle delegate(IJSEngine engine, string result) @trusted;

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
    auto task = new AsyncTask();
    task.engine = engine;
    task.resolve = resolve;
    task.reject = reject;
    task.transform = transform;
    atomicStore!(MemoryOrder.rel)(task.completed, false);

    tasks ~= task;

    import core.thread : Thread;
    auto t = new Thread({
        try
        {
            task.result = work();
        }
        catch (Exception e)
        {
            try { task.error = e.msg; }
            catch (Exception) { task.error = "async operation failed"; }
        }
        atomicStore!(MemoryOrder.rel)(task.completed, true);
    });
    t.isDaemon = true;
    t.start();
}

int asyncDrain() @trusted
{
    int drained = 0;
    AsyncTask*[] remaining;

    foreach (task; tasks)
    {
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
            remaining ~= task;
        }
    }
    tasks = remaining;
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
