/// Global object setup and central runtime state.
///
/// DunState is the central state object stored as the JSContext opaque,
/// accessible from all extern(C) callbacks via JS_GetContextOpaque.
module dun.runtime.globals;

import dun.engine.bindings;
import dun.engine.context : Context;
import dun.loop.eventloop : EventLoop;
import dun.security.permissions : PermissionRegistry;

/// Central state accessible from JS native callbacks via context opaque.
struct DunState
{
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}

/// Install all global objects and functions into the context.
void installGlobals(ref Context ctx, DunState* state) @trusted
{
    // Store state as context opaque for access from extern(C) callbacks
    ctx.setOpaque(cast(void*) state);

    // Install console object
    import dun.runtime.console : installConsole;

    installConsole(ctx.handle());
}
