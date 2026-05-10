module dun.runtime.globals;

import dun.engine.iface : IJSEngine;
import dun.loop.eventloop : EventLoop;
import dun.security.permissions : PermissionRegistry;

struct DunState
{
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}

void installGlobals(IJSEngine engine, DunState* state) @trusted
{
    engine.setContextOpaque(cast(void*) state);

    import dun.runtime.console : installConsole;
    installConsole(engine);
}
