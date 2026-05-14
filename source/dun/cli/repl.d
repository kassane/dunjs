module dun.cli.repl;

import dun.engine.iface : IJSEngine, EngineConfig;
import dun.runtime.globals : DunState, installGlobals;
import dun.cli.errors : isColorEnabled, formatUncaughtError;

private enum INSPECTOR_INIT = `
globalThis.__dun_repl_inspect__ = function(v) {
    if (v === undefined) return undefined;
    if (v === null) return 'null';
    if (typeof v === 'string') return JSON.stringify(v);
    if (typeof v === 'function')
        return '[Function: ' + (v.name || '(anonymous)') + ']';
    if (typeof v === 'symbol') return v.toString();
    if (typeof v === 'bigint') return String(v) + 'n';
    if (typeof v === 'object') {
        try { return JSON.stringify(v, null, 2); } catch(e) { return '[Object]'; }
    }
    return String(v);
};
`;

private enum : size_t {
    DEFAULT_HISTORY_SIZE = 1000,
    LINE_BUF_RESERVE     = 256,
    COMPLETIONS_MAX      = 64,
}

int runReplImpl(T)(T config)
{
    import std.stdio : write, writeln, writef, stdout, stderr;
    import dun.engine.iface : createEngine;

    auto engine = createEngine();
    engine.initialize(EngineConfig(config.memoryLimit, config.stackSize));

    DunState state;
    state.engine = engine;
    state.permissions = &config.permissions;
    state.eventLoop.initialize(engine);
    installGlobals(engine, &state);

    auto initResult = engine.eval(INSPECTOR_INIT, "<repl:init>");
    if (!initResult.isError) engine.freeValue(initResult.value);

    // Run --eval-file if provided
    if (config.evalFile.length > 0)
    {
        try
        {
            import std.file : readText;
            auto src = readText(config.evalFile);

            // Strip types if .ts file
            import std.string : endsWith;
            if (config.evalFile.endsWith(".ts") || config.evalFile.endsWith(".mts"))
            {
                import dun.ts.strip : stripTypes;
                src = stripTypes(src);
            }

            auto r = engine.eval(src, config.evalFile);
            state.eventLoop.drainMicrotasks();
            if (r.isError)
            {
                stderr.write(formatUncaughtError(r.errorMessage, isColorEnabled()));
                try { stderr.flush(); } catch (Exception) {}
            }
            else
                engine.freeValue(r.value);
        }
        catch (Exception e)
        {
            stderr.writeln("Error loading eval-file: ", e.msg);
        }
    }

    auto global = engine.getGlobal();

    bool color = isColorEnabled();
    bool isTTY = isTtyStdin();

    auto lineEd = LineEditor(color);
    lineEd.loadHistory();

    writeln("dun 0.2.0  (type .help for commands, .exit or Ctrl-D to quit)");

    string accumulator;
    string[] sessionLines;

    while (true)
    {
        string prompt;
        if (accumulator.length == 0)
            prompt = color ? "\x1b[32m> \x1b[0m" : "> ";
        else
            prompt = color ? "\x1b[90m... \x1b[0m" : "... ";

        string line;
        if (isTTY)
            line = lineEd.readLine(prompt);
        else
        {
            import std.stdio : readln;
            write(prompt);
            try { stdout.flush(); } catch (Exception) {}
            line = readln();
            if (line is null) { writeln(); break; }
            while (line.length > 0 && (line[$ - 1] == '\n' || line[$ - 1] == '\r'))
                line = line[0 .. $ - 1];
        }

        if (line is null) { writeln(); break; }

        // .break cancels multi-line accumulation from any state
        {
            import std.string : strip;
            if (line.strip() == ".break")
            {
                accumulator = "";
                continue;
            }
        }

        if (accumulator.length == 0)
        {
            import std.string : strip, startsWith;
            auto cmd = line.strip();
            if (cmd == ".exit" || cmd == ".quit") break;

            if (cmd == ".help")
            {
                printHelp(color);
                continue;
            }
            if (cmd == ".clear")
            {
                write("\x1b[2J\x1b[H");
                try { stdout.flush(); } catch (Exception) {}
                continue;
            }
            if (cmd == ".history")
            {
                foreach (i, h; lineEd.history)
                    writef("  %4d  %s\n", i + 1, h);
                continue;
            }
            if (cmd.startsWith(".load "))
            {
                auto path = cmd[6 .. $].strip();
                doLoad(engine, &state, path, color);
                continue;
            }
            if (cmd.startsWith(".save "))
            {
                auto path = cmd[6 .. $].strip();
                doSave(sessionLines, path, color);
                continue;
            }
            if (cmd.startsWith(".copy"))
            {
                auto arg = cmd.length > 5 ? cmd[5 .. $].strip() : "";
                doCopy(engine, arg, color);
                continue;
            }
            if (cmd == ".editor")
            {
                doEditor(engine, &state, &lineEd, sessionLines, color);
                continue;
            }
            if (cmd.length == 0) continue;
        }

        accumulator ~= (accumulator.length > 0 ? "\n" : "") ~ line;

        if (!isComplete(accumulator)) continue;

        string code = accumulator;
        accumulator = "";
        sessionLines ~= code;

        // TypeScript type stripping
        import dun.ts.strip : stripTypes;
        string evalCode;
        try { evalCode = stripTypes(code); }
        catch (Exception) { evalCode = code; }

        auto result = engine.eval(evalCode, "<repl>");
        state.eventLoop.drainMicrotasks();

        if (result.isError)
        {
            engine.setProperty(global, "_error",
                engine.newString(result.errorMessage));
            try
            {
                stderr.write(formatUncaughtError(result.errorMessage, color));
                stderr.flush();
            }
            catch (Exception) {}
        }
        else
        {
            if (!engine.isUndefined(result.value))
            {
                engine.setProperty(global, "_", engine.dupValue(result.value));
                engine.setProperty(global, "__dun_v__", engine.dupValue(result.value));
                auto inspR = engine.eval("__dun_repl_inspect__(__dun_v__)", "<repl:inspect>");
                if (!inspR.isError && !engine.isUndefined(inspR.value))
                {
                    auto s = engine.extractString(inspR.value);
                    writeln(color ? "\x1b[36m" ~ s ~ "\x1b[0m" : s);
                    engine.freeValue(inspR.value);
                }
            }
            engine.freeValue(result.value);
        }

        state.eventLoop.flushUnhandledRejections();
    }

    lineEd.saveHistory();
    engine.freeValue(global);
    engine.shutdown();
    return 0;
}

private void printHelp(bool color) @trusted
{
    import std.stdio : writeln;
    writeln("REPL Commands:");
    writeln("  .help        Print this help message");
    writeln("  .exit        Exit the REPL (also .quit or Ctrl-D)");
    writeln("  .clear       Clear the screen");
    writeln("  .copy        Copy result to clipboard (.copy [expr])");
    writeln("  .load <file> Load a file into the REPL session");
    writeln("  .save <file> Save REPL history to a file");
    writeln("  .editor      Enter multi-line editor mode");
    writeln("  .break       Cancel current input");
    writeln("  .history     Show command history");
    writeln();
    writeln("Keybindings:");
    writeln("  Ctrl+A       Move to start of line");
    writeln("  Ctrl+E       Move to end of line");
    writeln("  Ctrl+B/F     Move backward/forward one character");
    writeln("  Alt+B/F      Move backward/forward one word");
    writeln("  Ctrl+U       Delete to start of line");
    writeln("  Ctrl+K       Delete to end of line");
    writeln("  Ctrl+W       Delete word backward");
    writeln("  Ctrl+D       Delete character / Exit if line empty");
    writeln("  Ctrl+L       Clear screen");
    writeln("  Ctrl+T       Swap characters");
    writeln("  Up/Down      Navigate history");
    writeln("  Tab          Auto-complete");
    writeln();
    writeln("Special Variables:");
    writeln("  _            Last expression result");
    writeln("  _error       Last error");
}

private void doLoad(IJSEngine engine, DunState* state, string path, bool color) @trusted
{
    import std.stdio : writeln, stderr;
    try
    {
        import std.file : readText;
        auto src = readText(path);

        import std.string : endsWith;
        if (path.endsWith(".ts") || path.endsWith(".mts"))
        {
            import dun.ts.strip : stripTypes;
            src = stripTypes(src);
        }

        auto r = engine.eval(src, path);
        state.eventLoop.drainMicrotasks();
        if (r.isError)
        {
            stderr.write(formatUncaughtError(r.errorMessage, color));
            try { stderr.flush(); } catch (Exception) {}
        }
        else
        {
            writeln(color ? "\x1b[90mLoaded " ~ path ~ "\x1b[0m"
                          : "Loaded " ~ path);
            engine.freeValue(r.value);
        }
    }
    catch (Exception e)
    {
        stderr.writeln("Error loading file: ", e.msg);
    }
}

private void doSave(string[] sessionLines, string path, bool color) @trusted
{
    import std.stdio : writeln, stderr;
    try
    {
        import std.file : write;
        import std.array : join;
        write(path, sessionLines.join("\n") ~ "\n");
        writeln(color ? "\x1b[90mSession saved to " ~ path ~ "\x1b[0m"
                      : "Session saved to " ~ path);
    }
    catch (Exception e)
    {
        stderr.writeln("Error saving file: ", e.msg);
    }
}

private void doCopy(IJSEngine engine, string expr, bool color) @trusted
{
    import std.stdio : writeln, stderr;
    string text;
    if (expr.length > 0)
    {
        auto r = engine.eval(expr, "<repl:copy>");
        if (!r.isError)
        {
            text = engine.extractString(r.value);
            engine.freeValue(r.value);
        }
        else
        {
            stderr.writeln("Error: ", r.errorMessage);
            return;
        }
    }
    else
    {
        auto r = engine.eval("typeof _ !== 'undefined' ? __dun_repl_inspect__(_) : ''", "<repl:copy>");
        if (!r.isError)
        {
            text = engine.extractString(r.value);
            engine.freeValue(r.value);
        }
    }

    version (Posix)
    {
        import core.sys.posix.unistd : access, F_OK;
        import std.process : pipeShell, Redirect, wait;
        try
        {
            string[] cmds = ["xclip -selection clipboard", "xsel --clipboard --input",
                             "pbcopy", "wl-copy"];
            foreach (cmd; cmds)
            {
                auto parts = cmd.split(" ");
                try
                {
                    auto p = pipeShell(cmd, Redirect.stdin);
                    p.stdin.write(text);
                    p.stdin.flush();
                    p.stdin.close();
                    if (wait(p.pid) == 0)
                    {
                        writeln(color ? "\x1b[90mCopied to clipboard\x1b[0m"
                                      : "Copied to clipboard");
                        return;
                    }
                }
                catch (Exception) {}
            }
            stderr.writeln("No clipboard utility found (tried xclip, xsel, pbcopy, wl-copy)");
        }
        catch (Exception e)
        {
            stderr.writeln("Error copying: ", e.msg);
        }
    }
    else
    {
        stderr.writeln("Clipboard not supported on this platform");
    }
}

private string[] split(string s, string delim) @safe pure
{
    string[] result;
    size_t start = 0;
    for (size_t i = 0; i + delim.length <= s.length; i++)
    {
        if (s[i .. i + delim.length] == delim)
        {
            result ~= s[start .. i];
            start = i + delim.length;
            i = start - 1;
        }
    }
    result ~= s[start .. $];
    return result;
}

private void doEditor(IJSEngine engine, DunState* state,
    LineEditor* lineEd, ref string[] sessionLines, bool color) @trusted
{
    import std.stdio : write, writeln, readln, stdout, stderr;
    writeln(color ? "\x1b[90m// Entering editor mode (Ctrl-D to execute, .break to cancel)\x1b[0m"
                  : "// Entering editor mode (Ctrl-D to execute, .break to cancel)");

    string[] lines;
    while (true)
    {
        write(color ? "\x1b[90m> \x1b[0m" : "> ");
        try { stdout.flush(); } catch (Exception) {}
        auto line = readln();
        if (line is null) break;
        while (line.length > 0 && (line[$ - 1] == '\n' || line[$ - 1] == '\r'))
            line = line[0 .. $ - 1];

        import std.string : strip;
        if (line.strip() == ".break")
        {
            writeln(color ? "\x1b[90m// Editor cancelled\x1b[0m" : "// Editor cancelled");
            return;
        }
        lines ~= line;
    }

    if (lines.length == 0) return;

    import std.array : join;
    auto code = lines.join("\n");
    sessionLines ~= code;
    lineEd.addHistory(code);

    import dun.ts.strip : stripTypes;
    string evalCode;
    try { evalCode = stripTypes(code); }
    catch (Exception) { evalCode = code; }

    auto result = engine.eval(evalCode, "<repl:editor>");
    state.eventLoop.drainMicrotasks();

    auto edGlobal = engine.getGlobal();
    if (result.isError)
    {
        engine.setProperty(edGlobal, "_error",
            engine.newString(result.errorMessage));
        try
        {
            stderr.write(formatUncaughtError(result.errorMessage, color));
            stderr.flush();
        }
        catch (Exception) {}
    }
    else
    {
        if (!engine.isUndefined(result.value))
        {
            engine.setProperty(edGlobal, "_", engine.dupValue(result.value));
            engine.setProperty(edGlobal, "__dun_v__", engine.dupValue(result.value));
            auto inspR = engine.eval("__dun_repl_inspect__(__dun_v__)", "<repl:inspect>");
            if (!inspR.isError && !engine.isUndefined(inspR.value))
            {
                auto s = engine.extractString(inspR.value);
                writeln(color ? "\x1b[36m" ~ s ~ "\x1b[0m" : s);
                engine.freeValue(inspR.value);
            }
        }
        engine.freeValue(result.value);
    }
    engine.freeValue(edGlobal);
    state.eventLoop.flushUnhandledRejections();
}

// --- Raw terminal line editor ---

private bool isTtyStdin() @trusted nothrow
{
    version (Posix)
    {
        import core.sys.posix.unistd : isatty;
        return isatty(0) != 0;
    }
    else
        return false;
}

version (Posix)
{

private struct Termios
{
    uint c_iflag;
    uint c_oflag;
    uint c_cflag;
    uint c_lflag;
    ubyte[20] c_cc;
    uint c_ispeed;
    uint c_ospeed;
}

private extern (C) nothrow @nogc
{
    int tcgetattr(int fd, Termios* t);
    int tcsetattr(int fd, int action, const Termios* t);

    enum TCSAFLUSH = 2;
    enum ICANON    = 0x000002;
    enum ECHO      = 0x000008;
    enum ISIG      = 0x000001;
    enum IEXTEN    = 0x008000;
    enum ICRNL     = 0x000100;
    enum IXON      = 0x000400;
    enum OPOST     = 0x000001;
    enum VMIN      = 6;
    enum VTIME     = 5;
}

struct LineEditor
{
    private bool color;
    private string[] _history;
    private size_t maxHistory;
    private string historyPath;

    @disable this();

    this(bool color) @trusted
    {
        this.color = color;
        this.maxHistory = historySize();
        this.historyPath = historyFilePath();
    }

    string[] history() @safe nothrow { return _history; }

    string readLine(string prompt) @trusted
    {
        import core.sys.posix.unistd : read;

        Termios orig;
        if (tcgetattr(0, &orig) < 0) return readFallback(prompt);

        Termios raw = orig;
        raw.c_iflag &= ~(ICRNL | IXON);
        raw.c_oflag &= ~OPOST;
        raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;

        if (tcsetattr(0, TCSAFLUSH, &raw) < 0) return readFallback(prompt);

        scope(exit) tcsetattr(0, TCSAFLUSH, &orig);

        char[] buf;
        buf.reserve(LINE_BUF_RESERVE);
        size_t cursor = 0;
        int histIdx = cast(int) _history.length;
        string savedLine;

        writeStr(prompt);

        while (true)
        {
            ubyte[4] seq;
            auto n = read(0, seq.ptr, 1);
            if (n <= 0) return null;

            ubyte c = seq[0];

            if (c == '\r' || c == '\n')
            {
                writeStr("\r\n");
                string line = buf.idup;
                if (line.length > 0)
                    addHistory(line);
                return line;
            }

            if (c == 4) // Ctrl-D
            {
                if (buf.length == 0) return null;
                // Delete char under cursor
                if (cursor < buf.length)
                {
                    deleteCharAt(buf, cursor);
                    refreshLine(prompt, buf, cursor);
                }
                continue;
            }

            if (c == 1) // Ctrl-A: home
            {
                cursor = 0;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 5) // Ctrl-E: end
            {
                cursor = buf.length;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 2) // Ctrl-B: back
            {
                if (cursor > 0) cursor--;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 6) // Ctrl-F: forward
            {
                if (cursor < buf.length) cursor++;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 21) // Ctrl-U: delete to start
            {
                buf = buf[cursor .. $].dup;
                cursor = 0;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 11) // Ctrl-K: delete to end
            {
                buf = buf[0 .. cursor].dup;
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 23) // Ctrl-W: delete word backward
            {
                if (cursor > 0)
                {
                    size_t end = cursor;
                    while (cursor > 0 && buf[cursor - 1] == ' ') cursor--;
                    while (cursor > 0 && buf[cursor - 1] != ' ') cursor--;
                    buf = (buf[0 .. cursor] ~ buf[end .. $]).dup;
                    refreshLine(prompt, buf, cursor);
                }
                continue;
            }

            if (c == 20) // Ctrl-T: swap chars
            {
                if (cursor > 0 && buf.length > 1)
                {
                    size_t pos = cursor;
                    if (pos >= buf.length) pos = buf.length - 1;
                    auto tmp = buf[pos - 1];
                    buf[pos - 1] = buf[pos];
                    buf[pos] = tmp;
                    if (cursor < buf.length) cursor++;
                    refreshLine(prompt, buf, cursor);
                }
                continue;
            }

            if (c == 12) // Ctrl-L: clear screen
            {
                writeStr("\x1b[2J\x1b[H");
                refreshLine(prompt, buf, cursor);
                continue;
            }

            if (c == 3) // Ctrl-C
            {
                writeStr("^C\r\n");
                buf.length = 0;
                cursor = 0;
                return "";
            }

            if (c == 9) // Tab
            {
                doTabComplete(buf, cursor, prompt);
                continue;
            }

            if (c == 127 || c == 8) // Backspace
            {
                if (cursor > 0)
                {
                    cursor--;
                    deleteCharAt(buf, cursor);
                    refreshLine(prompt, buf, cursor);
                }
                continue;
            }

            if (c == 27) // Escape sequence
            {
                auto n2 = read(0, seq.ptr + 1, 1);
                if (n2 <= 0) continue;

                if (seq[1] == '[')
                {
                    auto n3 = read(0, seq.ptr + 2, 1);
                    if (n3 <= 0) continue;

                    if (seq[2] == 'A') // Up
                    {
                        if (histIdx > 0)
                        {
                            if (histIdx == cast(int) _history.length)
                                savedLine = buf.idup;
                            histIdx--;
                            buf = _history[histIdx].dup;
                            cursor = buf.length;
                            refreshLine(prompt, buf, cursor);
                        }
                        continue;
                    }
                    if (seq[2] == 'B') // Down
                    {
                        if (histIdx < cast(int) _history.length)
                        {
                            histIdx++;
                            if (histIdx == cast(int) _history.length)
                                buf = savedLine.dup;
                            else
                                buf = _history[histIdx].dup;
                            cursor = buf.length;
                            refreshLine(prompt, buf, cursor);
                        }
                        continue;
                    }
                    if (seq[2] == 'C') // Right
                    {
                        if (cursor < buf.length) cursor++;
                        refreshLine(prompt, buf, cursor);
                        continue;
                    }
                    if (seq[2] == 'D') // Left
                    {
                        if (cursor > 0) cursor--;
                        refreshLine(prompt, buf, cursor);
                        continue;
                    }
                    if (seq[2] == 'H') // Home
                    {
                        cursor = 0;
                        refreshLine(prompt, buf, cursor);
                        continue;
                    }
                    if (seq[2] == 'F') // End
                    {
                        cursor = buf.length;
                        refreshLine(prompt, buf, cursor);
                        continue;
                    }
                    if (seq[2] == '3') // Delete key: ESC [ 3 ~
                    {
                        auto n4 = read(0, seq.ptr + 3, 1);
                        if (n4 > 0 && seq[3] == '~' && cursor < buf.length)
                        {
                            deleteCharAt(buf, cursor);
                            refreshLine(prompt, buf, cursor);
                        }
                        continue;
                    }
                }
                else if (seq[1] == 'b') // Alt-B: word backward
                {
                    while (cursor > 0 && buf[cursor - 1] == ' ') cursor--;
                    while (cursor > 0 && buf[cursor - 1] != ' ') cursor--;
                    refreshLine(prompt, buf, cursor);
                    continue;
                }
                else if (seq[1] == 'f') // Alt-F: word forward
                {
                    while (cursor < buf.length && buf[cursor] == ' ') cursor++;
                    while (cursor < buf.length && buf[cursor] != ' ') cursor++;
                    refreshLine(prompt, buf, cursor);
                    continue;
                }
                continue;
            }

            if (c >= 32) // Printable
            {
                insertCharAt(buf, cursor, cast(char) c);
                cursor++;
                refreshLine(prompt, buf, cursor);
            }
        }
    }

    void addHistory(string line) @safe
    {
        if (line.length == 0) return;
        if (_history.length > 0 && _history[$ - 1] == line) return;
        _history ~= line;
        if (_history.length > maxHistory)
            _history = _history[$ - maxHistory .. $];
    }

    void loadHistory() @trusted
    {
        if (historyPath.length == 0) return;
        try
        {
            import std.file : readText, exists;
            if (!exists(historyPath)) return;
            auto content = readText(historyPath);
            foreach (line; content.splitByNewline())
            {
                if (line.length > 0)
                    _history ~= line;
            }
            if (_history.length > maxHistory)
                _history = _history[$ - maxHistory .. $];
        }
        catch (Exception) {}
    }

    void saveHistory() @trusted
    {
        if (historyPath.length == 0) return;
        try
        {
            import std.file : write, mkdirRecurse;
            import std.path : dirName;
            auto dir = dirName(historyPath);
            if (dir.length > 0) mkdirRecurse(dir);
            import std.array : join;
            write(historyPath, _history.join("\n") ~ "\n");
        }
        catch (Exception) {}
    }

    private void doTabComplete(ref char[] buf, ref size_t cursor, string prompt) @trusted
    {
        // Extract word at cursor for completion
        size_t wordStart = cursor;
        bool hasDot = false;
        while (wordStart > 0)
        {
            char ch = buf[wordStart - 1];
            if (ch == '.')
            {
                hasDot = true;
                wordStart--;
            }
            else if (isIdentChar(ch))
                wordStart--;
            else
                break;
        }

        auto prefix = buf[wordStart .. cursor].idup;
        if (prefix.length == 0) return;

        auto completions = getCompletions(prefix);
        if (completions.length == 0) return;

        if (completions.length == 1)
        {
            auto suffix = completions[0][prefix.length .. $];
            foreach (ch; suffix)
            {
                insertCharAt(buf, cursor, ch);
                cursor++;
            }
            refreshLine(prompt, buf, cursor);
        }
        else
        {
            // Show completions
            writeStr("\r\n");
            import std.stdio : writef, writeln;
            foreach (c; completions)
                writef("  %s", c);
            writeln();
            refreshLine(prompt, buf, cursor);
        }
    }

    private string[] getCompletions(string prefix) @safe
    {
        import std.algorithm : startsWith, sort;

        string[] results;

        // JS keywords and globals
        static immutable string[] keywords = [
            "async", "await", "break", "case", "catch", "class", "const",
            "continue", "debugger", "default", "delete", "do", "else",
            "export", "extends", "false", "finally", "for", "function",
            "if", "import", "in", "instanceof", "let", "new", "null",
            "of", "return", "static", "super", "switch", "this",
            "throw", "true", "try", "typeof", "undefined", "var",
            "void", "while", "with", "yield",
            "console", "globalThis", "process", "Buffer", "URL",
            "URLSearchParams", "TextEncoder", "TextDecoder",
            "setTimeout", "setInterval", "clearTimeout", "clearInterval",
            "setImmediate", "clearImmediate", "queueMicrotask",
            "fetch", "Request", "Response", "Headers",
            "AbortController", "AbortSignal",
            "EventTarget", "Event", "CustomEvent",
            "Blob", "File", "FormData",
            "ReadableStream", "WritableStream", "TransformStream",
            "MessageChannel", "MessagePort", "BroadcastChannel",
            "atob", "btoa", "structuredClone",
            "performance", "navigator", "crypto",
            "Promise", "JSON", "Math", "Date", "RegExp",
            "Array", "Object", "String", "Number", "Boolean",
            "Map", "Set", "WeakMap", "WeakSet",
            "Symbol", "Proxy", "Reflect",
            "Error", "TypeError", "RangeError", "SyntaxError",
            "parseInt", "parseFloat", "isNaN", "isFinite",
            "encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent",
            "require", "module", "exports", "__filename", "__dirname",
            "Deno", "_", "_error",
        ];

        // REPL dot commands
        static immutable string[] dotCommands = [
            ".help", ".exit", ".quit", ".clear", ".load", ".save",
            ".editor", ".break", ".history", ".copy",
        ];

        if (prefix.length > 0 && prefix[0] == '.')
        {
            foreach (dc; dotCommands)
                if (dc.length >= prefix.length && dc[0 .. prefix.length] == prefix)
                    results ~= dc;
        }
        else
        {
            foreach (kw; keywords)
                if (kw.length >= prefix.length && kw[0 .. prefix.length] == prefix)
                    results ~= kw;
        }

        if (results.length > COMPLETIONS_MAX)
            results = results[0 .. COMPLETIONS_MAX];

        return results;
    }

    private static void writeStr(const(char)[] s) @trusted nothrow
    {
        import core.sys.posix.unistd : write;
        if (s.length > 0)
            write(1, s.ptr, s.length);
    }

    private static void refreshLine(string prompt, const(char)[] buf, size_t cursor) @trusted nothrow
    {
        // Calculate visible prompt length (strip ANSI)
        size_t promptLen = visibleLength(prompt);

        char[512] tmp = void;
        size_t pos = 0;

        // \r, clear line
        tmp[pos++] = '\r';
        tmp[pos++] = '\x1b'; tmp[pos++] = '['; tmp[pos++] = '0'; tmp[pos++] = 'K';

        // Write prompt
        foreach (ch; prompt)
        {
            if (pos < tmp.length) tmp[pos++] = ch;
        }

        // Write buffer
        foreach (ch; buf)
        {
            if (pos < tmp.length) tmp[pos++] = ch;
        }

        // Position cursor
        size_t cursorPos = promptLen + cursor + 1;
        auto posStr = uintToStr(cursorPos);
        tmp[pos++] = '\r';
        tmp[pos++] = '\x1b'; tmp[pos++] = '[';
        foreach (ch; posStr)
        {
            if (pos < tmp.length) tmp[pos++] = ch;
        }
        if (pos < tmp.length) tmp[pos++] = 'G';

        writeStr(tmp[0 .. pos]);
    }

    private static size_t visibleLength(const(char)[] s) @safe pure nothrow
    {
        size_t len = 0;
        bool inEsc = false;
        foreach (ch; s)
        {
            if (inEsc)
            {
                if (ch == 'm') inEsc = false;
            }
            else if (ch == '\x1b')
                inEsc = true;
            else
                len++;
        }
        return len;
    }

    private static char[20] uintToStr(size_t val) @safe pure nothrow
    {
        char[20] buf = void;
        int pos = 19;
        if (val == 0)
        {
            buf[pos] = '0';
            return buf;
        }
        while (val > 0 && pos >= 0)
        {
            buf[pos--] = cast(char)('0' + val % 10);
            val /= 10;
        }
        // Left-pad with zeros to make a fixed array
        char[20] result = 0;
        int len = 19 - pos;
        result[0 .. len] = buf[pos + 1 .. 20];
        return result;
    }

    private string readFallback(string prompt) @trusted
    {
        import std.stdio : write, readln, stdout;
        write(prompt);
        try { stdout.flush(); } catch (Exception) {}
        auto line = readln();
        if (line is null) return null;
        while (line.length > 0 && (line[$ - 1] == '\n' || line[$ - 1] == '\r'))
            line = line[0 .. $ - 1];
        if (line.length > 0) addHistory(line);
        return line;
    }

    private static void insertCharAt(ref char[] buf, size_t pos, char ch) @safe
    {
        buf.length++;
        for (size_t i = buf.length - 1; i > pos; i--)
            buf[i] = buf[i - 1];
        buf[pos] = ch;
    }

    private static void deleteCharAt(ref char[] buf, size_t pos) @safe
    {
        if (pos >= buf.length) return;
        for (size_t i = pos; i + 1 < buf.length; i++)
            buf[i] = buf[i + 1];
        buf.length--;
    }

    private static bool isIdentChar(char c) @safe pure nothrow
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '$';
    }
}

} // version(Posix)
else
{
    struct LineEditor
    {
        private bool color;
        private string[] _history;

        @disable this();

        this(bool c) @safe { this.color = c; }
        string[] history() @safe nothrow { return _history; }

        string readLine(string prompt) @trusted
        {
            import std.stdio : write, readln, stdout;
            write(prompt);
            try { stdout.flush(); } catch (Exception) {}
            auto line = readln();
            if (line is null) return null;
            while (line.length > 0 && (line[$ - 1] == '\n' || line[$ - 1] == '\r'))
                line = line[0 .. $ - 1];
            return line;
        }

        void loadHistory() @safe {}
        void saveHistory() @safe {}
    }
}

// History file path: DUN_REPL_HISTORY env or ~/.dun_repl_history
private string historyFilePath() @trusted
{
    try
    {
        import std.process : environment;
        auto envPath = environment.get("DUN_REPL_HISTORY", "");
        if (envPath.length > 0)
        {
            if (envPath == "0" || envPath == "false" || envPath == "")
                return "";
            return envPath;
        }

        auto home = environment.get("HOME", "");
        if (home.length == 0)
            home = environment.get("USERPROFILE", "");
        if (home.length > 0)
            return home ~ "/.dun_repl_history";
    }
    catch (Exception) {}
    return "";
}

// History size: DUN_REPL_HISTORY_SIZE env or default 1000
private size_t historySize() @trusted
{
    try
    {
        import std.process : environment;
        import std.conv : to;
        auto envSize = environment.get("DUN_REPL_HISTORY_SIZE", "");
        if (envSize.length > 0)
            return envSize.to!size_t;
    }
    catch (Exception) {}
    return DEFAULT_HISTORY_SIZE;
}

private string[] splitByNewline(string s) @safe pure
{
    string[] result;
    size_t start = 0;
    for (size_t i = 0; i < s.length; i++)
    {
        if (s[i] == '\n')
        {
            auto line = s[start .. i];
            if (line.length > 0 && line[$ - 1] == '\r')
                line = line[0 .. $ - 1];
            result ~= line;
            start = i + 1;
        }
    }
    if (start < s.length)
    {
        auto line = s[start .. $];
        if (line.length > 0 && line[$ - 1] == '\r')
            line = line[0 .. $ - 1];
        result ~= line;
    }
    return result;
}

bool isComplete(string code) @safe pure nothrow
{
    int braces, brackets, parens;
    bool inSQ, inDQ, inTpl, escape;

    foreach (char c; code)
    {
        if (escape) { escape = false; continue; }
        if (c == '\\') { escape = true; continue; }

        if (!inSQ && !inDQ && !inTpl)
        {
            switch (c)
            {
                case '\'': inSQ = true;   break;
                case '"':  inDQ = true;   break;
                case '`':  inTpl = true;  break;
                case '{':  braces++;      break;
                case '}':  braces--;      break;
                case '[':  brackets++;    break;
                case ']':  brackets--;    break;
                case '(':  parens++;      break;
                case ')':  parens--;      break;
                default: break;
            }
        }
        else if (inSQ && c == '\'') inSQ = false;
        else if (inDQ && c == '"')  inDQ = false;
        else if (inTpl && c == '`') inTpl = false;
    }

    return braces <= 0 && brackets <= 0 && parens <= 0;
}

unittest
{
    assert(isComplete("1 + 2"));
    assert(isComplete("let x = { a: 1 }"));
    assert(!isComplete("let x = {"));
    assert(!isComplete("foo("));
    assert(isComplete("'hello'"));
}
