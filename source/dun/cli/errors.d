module dun.cli.errors;

// Detect whether ANSI colors should be enabled on stderr.
// Respects https://no-color.org and the TERM=dumb convention.
bool isColorEnabled() @trusted nothrow
{
    version (Posix)
    {
        import core.sys.posix.unistd : isatty;
        try
        {
            import std.process : environment;
            if (environment.get("NO_COLOR", "").length > 0) return false;
            if (environment.get("TERM", "") == "dumb") return false;
        }
        catch (Exception) {}
        return isatty(2) != 0;
    }
    else version (Windows)
    {
        return false;
    }
    else
    {
        return false;
    }
}

private enum RESET = "\x1b[0m";
private enum BOLD  = "\x1b[1m";
private enum DIM   = "\x1b[2m";
private enum RED   = "\x1b[31m";

// Format an uncaught script error for stderr.
// msg may be "ErrorType: msg\n    at file.js:n:m\n..." from extractExceptionWithStack.
string formatUncaughtError(string msg, bool color) @safe pure
{
    if (!color) return "Uncaught " ~ msg ~ "\n";
    return formatWithPrefix("Uncaught ", msg);
}

// Format an unhandled promise rejection for stderr.
string formatRejection(string reason, bool color) @safe pure
{
    if (!color) return "Uncaught (in promise) " ~ reason ~ "\n";
    return formatWithPrefix("Uncaught (in promise) ", reason);
}

private string formatWithPrefix(string prefix, string msg) @safe pure
{
    import std.string : indexOf, splitLines, stripLeft;

    ptrdiff_t nl = indexOf(msg, '\n');
    string header = nl < 0 ? msg : msg[0 .. nl];
    string rest   = nl < 0 ? "" : msg[nl + 1 .. $];

    string result = BOLD ~ RED ~ prefix ~ RESET ~ BOLD ~ header ~ RESET ~ "\n";
    foreach (line; rest.splitLines())
    {
        auto trimmed = line.stripLeft();
        if (trimmed.length == 0) continue;
        if (trimmed.length >= 3 && trimmed[0 .. 3] == "at ")
            result ~= DIM ~ "    " ~ trimmed ~ RESET ~ "\n";
        else
            result ~= DIM ~ line ~ RESET ~ "\n";
    }
    return result;
}

unittest
{
    assert(formatUncaughtError("TypeError: x", false) == "Uncaught TypeError: x\n");
    auto s = formatUncaughtError("ReferenceError: y\n    at file.js:5:10", false);
    assert(s == "Uncaught ReferenceError: y\n    at file.js:5:10\n");
    assert(formatRejection("reason", false) == "Uncaught (in promise) reason\n");
}
