/// Layer 6: Runtime API.
///
/// Global objects and functions exposed to JavaScript:
/// console, timers (setTimeout/setInterval), process, encoding.
module dun.runtime;

public import dun.runtime.globals;

version (EngineQuickJS)
{
    public import dun.runtime.console;
}
