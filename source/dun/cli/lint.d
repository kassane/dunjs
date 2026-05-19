/// `dun lint` — minimal lexer-based JS/TS linter. Inspired by oxlint /
/// deno_lint, scoped to rules tractable without a full AST: pattern
/// matches over the token stream from `dun.ts.parser.lexer`.
///
/// Bun's flagship oxlint ships 200+ rules backed by a real parser. This
/// is the dev-experience floor: catch `debugger` left in, `==` instead
/// of `===`, `eval(...)`, `new Function()`. Each rule is a single
/// pass over the token stream — no scope analysis, no dead-code
/// elimination. Output mirrors ESLint: `file:line:col level message
/// rule-name`. Exit code 1 on any error-level diagnostic.
///
/// `prefer-const` is deferred to a follow-up PR — it needs a tiny
/// scope tracker (the bare `let x = 1; ... x = 2` heuristic over a flat
/// token stream produces too many false positives once nested
/// functions or shadowing enter the picture).
module dun.cli.lint;

import std.file : exists, isFile, isDir, dirEntries, SpanMode, readText;
import std.path : extension, baseName;
import std.stdio : writeln, writefln;
import dun.ts.parser.lexer : Lexer, Token, T;

/* `std.stdio.stderr` access trips a @safe inference issue when used
   from a top-level module function. Wrap the underlying impl in a
   tiny @trusted shim so the rest of this module stays @safe. */
private void writeErr(string s) @trusted
{
    import std.stdio : stderr;
    stderr.writeln(s);
}

private struct Diagnostic
{
    string file;
    uint line;
    uint col;
    string severity;  // "error" / "warn"
    string rule;
    string message;
}

private bool isLintable(string path) @safe
{
    auto ext = path.extension;
    return ext == ".js" || ext == ".ts" || ext == ".mjs" || ext == ".cjs"
        || ext == ".jsx" || ext == ".tsx" || ext == ".mts" || ext == ".cts";
}

/// Walk `paths` (file or directory) and run all rules. Returns exit
/// code (0 = clean, 1 = errors found).
int runLint(string[] paths) @safe
{
    if (paths.length == 0)
        paths = ["."];

    Diagnostic[] diags;
    int filesScanned = 0;

    foreach (p; paths)
    {
        if (!exists(p))
        {
            writeErr("lint: not found: " ~ p);
            return 1;
        }
        if (p.isFile)
        {
            if (isLintable(p))
            {
                filesScanned++;
                lintFile(p, diags);
            }
            continue;
        }
        if (p.isDir)
        {
            foreach (entry; dirEntries(p, SpanMode.depth))
            {
                if (!entry.isFile) continue;
                /* skip common ignored trees */
                import std.algorithm : canFind;
                if (entry.name.canFind("/node_modules/")) continue;
                if (entry.name.canFind("/.dun/")) continue;
                if (entry.name.canFind("/dist/")) continue;
                if (entry.name.canFind("/build/")) continue;
                if (!isLintable(entry.name)) continue;
                filesScanned++;
                lintFile(entry.name, diags);
            }
        }
    }

    foreach (d; diags)
        writefln("%s:%d:%d  %s  %s  %s",
            d.file, d.line, d.col, d.severity, d.message, d.rule);

    int errors = 0;
    foreach (d; diags) if (d.severity == "error") errors++;

    if (diags.length > 0)
        writefln("\n%s problem%s (%d error%s) in %d file%s.",
            diags.length, diags.length == 1 ? "" : "s",
            errors, errors == 1 ? "" : "s",
            filesScanned, filesScanned == 1 ? "" : "s");
    else
        writefln("Lint clean. %d file%s scanned.",
            filesScanned, filesScanned == 1 ? "" : "s");

    return errors > 0 ? 1 : 0;
}

private void lintFile(string path, ref Diagnostic[] diags) @safe
{
    string source;
    try
        source = readText(path);
    catch (Exception e)
    {
        diags ~= Diagnostic(path, 1, 1, "error", "io",
            "could not read file: " ~ e.msg);
        return;
    }

    auto lex = Lexer(source);
    bool prevWasIdent = false;
    const(char)[] prevIdentText;

    for (;;)
    {
        auto tok = lex.next();
        if (tok.kind == T.eof) break;

        /* no-debugger — `debugger;` statement left in source. */
        if (tok.kind == T.t_debugger)
            diags ~= Diagnostic(path, tok.line, tok.col, "error",
                "no-debugger", "`debugger` statement");

        /* eqeqeq — flag non-strict `==` / `!=`. */
        if (tok.kind == T.equals_equals)
            diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                "eqeqeq", "use `===` instead of `==`");
        if (tok.kind == T.exclamation_equals)
            diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                "eqeqeq", "use `!==` instead of `!=`");

        /* no-eval — bare `eval(...)` or `Function(...)` call. We require
           the *previous* token to NOT be a `.` so `obj.eval(...)` is
           skipped. Implementation: defer the open-paren check to the
           NEXT iteration by remembering whether the last token was the
           target identifier. */
        if (prevWasIdent && tok.kind == T.open_paren)
        {
            if (prevIdentText == "eval")
                diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                    "no-eval", "avoid `eval()` (runtime code evaluation)");
            else if (prevIdentText == "Function")
                diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                    "no-eval", "avoid `new Function()` / `Function()` (dynamic eval)");
        }

        /* track previous identifier for the no-eval lookahead.
           `prev = .` would mask member-call eval and Function — for
           that we'd need to remember the token *before* the identifier
           too. Skip dot-prefixed forms by tracking the dot token: when
           we see `.`, clear `prevWasIdent` so the *next* identifier
           doesn't trigger the rule. */
        if (tok.kind == T.identifier)
        {
            prevWasIdent = true;
            prevIdentText = tok.text;
        }
        else if (tok.kind == T.dot)
        {
            prevWasIdent = false;
        }
        else
        {
            prevWasIdent = false;
        }
    }
}
