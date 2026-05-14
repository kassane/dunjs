/// POSIX signal handling for process.on('SIGTERM'/'SIGINT').
module dun.runtime.signals;

import dun.engine.iface : IJSEngine, JSHandle;

/// Signal types supported by process.on().
enum SignalType { SIGTERM, SIGINT }
static assert(__traits(allMembers, SignalType).length == 2, "Update signal handler arrays when adding new SignalType");

/// Maximum number of signal handlers per signal type.
private enum MAX_SIGNAL_HANDLERS = 16;

version (Posix)
{
    private enum POSIX_SIGINT = 2;
    private enum POSIX_SIGTERM = 15;
}

private __gshared bool sigTermReceived = false;
private __gshared bool sigIntReceived = false;
private __gshared bool signalsInstalled = false;

private __gshared JSHandle[MAX_SIGNAL_HANDLERS] sigTermHandlers;
private __gshared int sigTermHandlerCount = 0;
private __gshared JSHandle[MAX_SIGNAL_HANDLERS] sigIntHandlers;
private __gshared int sigIntHandlerCount = 0;
private __gshared IJSEngine sigEngine;

/// Install POSIX signal handlers (idempotent).
void installSignalHandlers() nothrow @trusted
{
    if (signalsInstalled) return;
    signalsInstalled = true;

    version (Posix)
    {
        import core.sys.posix.signal : sigaction, sigaction_t, SA_RESTART;

        sigaction_t sa;
        sa.sa_handler = &handleSigTerm;
        sa.sa_flags = SA_RESTART;
        sigaction(POSIX_SIGTERM, &sa, null);

        sigaction_t sa2;
        sa2.sa_handler = &handleSigInt;
        sa2.sa_flags = SA_RESTART;
        sigaction(POSIX_SIGINT, &sa2, null);
    }
}

version (Posix)
{
    private extern (C) void handleSigTerm(int) nothrow @system
    {
        sigTermReceived = true;
    }

    private extern (C) void handleSigInt(int) nothrow @system
    {
        sigIntReceived = true;
    }
}

/// Register a JS callback for a signal type.
void registerSignalHandler(IJSEngine engine, SignalType sig, JSHandle handler) @trusted
{
    assert(engine !is null, "Null engine in registerSignalHandler");
    sigEngine = engine;

    final switch (sig)
    {
        case SignalType.SIGTERM:
            if (sigTermHandlerCount < MAX_SIGNAL_HANDLERS)
            {
                sigTermHandlers[sigTermHandlerCount] = engine.dupValue(handler);
                sigTermHandlerCount++;
            }
            break;
        case SignalType.SIGINT:
            if (sigIntHandlerCount < MAX_SIGNAL_HANDLERS)
            {
                sigIntHandlers[sigIntHandlerCount] = engine.dupValue(handler);
                sigIntHandlerCount++;
            }
            break;
    }
}

/// Check if any signals have been received (non-blocking).
bool checkSignals() nothrow @trusted
{
    return sigTermReceived || sigIntReceived;
}

/// Returns true if any signal handlers are registered.
bool hasSignalHandlers() nothrow @trusted
{
    return sigTermHandlerCount > 0 || sigIntHandlerCount > 0;
}

/// Drain received signals and invoke JS callbacks.
void drainSignals() nothrow @trusted
{
    if (sigEngine is null) return;

    if (sigTermReceived)
    {
        sigTermReceived = false;
        foreach (i; 0 .. sigTermHandlerCount)
        {
            try
            {
                JSHandle[] args;
                sigEngine.callFunction(sigTermHandlers[i], sigEngine.newUndefined(), args);
            }
            catch (Exception) {}
        }
    }

    if (sigIntReceived)
    {
        sigIntReceived = false;
        foreach (i; 0 .. sigIntHandlerCount)
        {
            try
            {
                JSHandle[] args;
                sigEngine.callFunction(sigIntHandlers[i], sigEngine.newUndefined(), args);
            }
            catch (Exception) {}
        }
    }
}
