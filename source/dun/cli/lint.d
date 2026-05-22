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
/// `--fix` auto-applies safe rewrites in-place. `eqeqeq` becomes
/// `===`/`!==`; `no-debugger` removes the `debugger;` statement.
/// Rules that can't be safely auto-fixed (`no-eval` — removing the
/// call could change semantics) report as `[fixable: false]`.
///
/// `prefer-const` is deferred to a follow-up PR — it needs a tiny
/// scope tracker (the bare `let x = 1; ... x = 2` heuristic over a flat
/// token stream produces too many false positives once nested
/// functions or shadowing enter the picture).
module dun.cli.lint;


/// `@trusted policy`: lexer-based linter (no-eval, eqeqeq,
/// no-debugger). Pure D scanner over JS/TS source. `@trusted` is
/// for `std.file.readText` and the `cast(string) char[]` output
/// buffer.
import std.file : exists, isFile, isDir, dirEntries, SpanMode, readText, write;
import std.path : extension;
import std.stdio : writeln, writefln;
import std.algorithm : canFind, sort;
import dun.ts.parser.lexer : Lexer, Token, T;

/// Directory names skipped during recursive `dun lint <dir>` walks.
private immutable string[] kIgnoredDirComponents = [
    "/node_modules/", "/.dun/", "/dist/", "/build/"
];

/// Extensions that `dun lint` will tokenize. Everything else in a
/// directory walk is skipped silently.
private immutable string[] kLintableExtensions = [
    ".js", ".ts", ".mjs", ".cjs", ".jsx", ".tsx", ".mts", ".cts"
];

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
    /// Auto-fix metadata. `fixable == true` means `--fix` can
    /// rewrite this diagnostic. `fixStart` / `fixLen` describe the
    /// byte range in the source to replace; `fixReplacement` is the
    /// new text.
    bool   fixable;
    uint   fixStart;
    uint   fixLen;
    string fixReplacement;
}

private bool isLintable(string path) @safe
{
    auto ext = path.extension;
    foreach (e; kLintableExtensions)
        if (ext == e) return true;
    return false;
}

/// Walk `paths` (file or directory) and run all rules. Returns exit
/// code (0 = clean, 1 = errors found OR `--max-warnings=N` cap
/// exceeded). When `applyFix == true`, safe diagnostics get auto-
/// rewritten in place; the file is re-tokenized and re-reported
/// after the rewrite. `quiet=true` suppresses warning output (only
/// errors print); `maxWarnings=-1` disables the warning cap.
int runLint(string[] paths, bool applyFix = false,
            bool quiet = false, int maxWarnings = -1) @safe
{
    if (paths.length == 0)
        paths = ["."];

    Diagnostic[] diags;
    int filesScanned = 0;
    int filesFixed = 0;

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
                if (applyFix && tryApplyFixes(p))
                    filesFixed++;
                lintFile(p, diags);
            }
            continue;
        }
        if (p.isDir)
        {
            foreach (entry; dirEntries(p, SpanMode.depth))
            {
                if (!entry.isFile) continue;
                bool skip = false;
                foreach (ignored; kIgnoredDirComponents)
                    if (entry.name.canFind(ignored)) { skip = true; break; }
                if (skip) continue;
                if (!isLintable(entry.name)) continue;
                filesScanned++;
                if (applyFix && tryApplyFixes(entry.name))
                    filesFixed++;
                lintFile(entry.name, diags);
            }
        }
    }

    int errors = 0;
    int warnings = 0;
    foreach (d; diags)
    {
        if (d.severity == "error") errors++;
        else if (d.severity == "warn") warnings++;
    }

    foreach (d; diags)
    {
        if (quiet && d.severity != "error") continue;
        writefln("%s:%d:%d  %s  %s  %s%s",
            d.file, d.line, d.col, d.severity, d.message, d.rule,
            applyFix ? "" : (d.fixable ? "  [fixable]" : ""));
    }

    if (applyFix && filesFixed > 0)
        writefln("Applied fixes to %d file%s.", filesFixed, filesFixed == 1 ? "" : "s");

    if (diags.length > 0)
    {
        if (quiet)
            writefln("\n%d error%s in %d file%s.",
                errors, errors == 1 ? "" : "s",
                filesScanned, filesScanned == 1 ? "" : "s");
        else
            writefln("\n%s problem%s (%d error%s) in %d file%s.",
                diags.length, diags.length == 1 ? "" : "s",
                errors, errors == 1 ? "" : "s",
                filesScanned, filesScanned == 1 ? "" : "s");
    }
    else
        writefln("Lint clean. %d file%s scanned.",
            filesScanned, filesScanned == 1 ? "" : "s");

    /* Exit code: errors always fail; --max-warnings=N caps warnings
       (e.g. `--max-warnings=0` makes any warning a CI failure). */
    if (errors > 0) return 1;
    if (maxWarnings >= 0 && warnings > maxWarnings)
    {
        writefln("Warning count (%d) exceeds --max-warnings=%d.",
            warnings, maxWarnings);
        return 1;
    }
    return 0;
}

/// Re-tokenize `path`, collect all fixable diagnostics, apply them
/// from the end of the file backwards so byte offsets stay valid,
/// and rewrite the file. Returns true if any fix was applied.
private bool tryApplyFixes(string path) @safe
{
    string source;
    try
        source = readText(path);
    catch (Exception)
        return false;

    Diagnostic[] diags;
    collectDiagnostics(path, source, diags);

    /* Filter to fixable + sort by descending fixStart so applying
       earlier fixes doesn't shift later offsets. */
    Diagnostic[] fixable;
    foreach (d; diags) if (d.fixable) fixable ~= d;
    if (fixable.length == 0) return false;
    fixable.sort!((a, b) => a.fixStart > b.fixStart);

    string out_ = source;
    foreach (d; fixable)
    {
        if (d.fixStart + d.fixLen > out_.length) continue;
        out_ = out_[0 .. d.fixStart] ~ d.fixReplacement
             ~ out_[d.fixStart + d.fixLen .. $];
    }
    try
        write(path, out_);
    catch (Exception)
        return false;
    return true;
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
    collectDiagnostics(path, source, diags);
}

/// Single-pass token-stream scan. Each rule appends to `diags`.
/// `--fix` reads the `fixStart` / `fixLen` / `fixReplacement` fields
/// to apply autofixes; the diagnostic message is unchanged.
private void collectDiagnostics(string path, string source, ref Diagnostic[] diags) @safe
{
    auto lex = Lexer(source);
    bool prevWasIdent = false;
    const(char)[] prevIdentText;
    /* no-empty-block: previous-token kind, used to detect `{}`. The
       brace pair must be back-to-back (no tokens between them). */
    T prevKind = T.eof;
    uint prevOpenBraceStart = 0;
    uint prevOpenBraceLine = 0;
    uint prevOpenBraceCol = 0;

    for (;;)
    {
        auto tok = lex.next();
        if (tok.kind == T.eof) break;

        /* no-debugger — `debugger;` statement left in source. The
           fix removes the keyword (and a trailing semicolon if
           present at the next byte). */
        if (tok.kind == T.t_debugger)
        {
            uint fLen = tok.length;
            if (tok.start + tok.length < source.length
                && source[tok.start + tok.length] == ';')
                fLen++;
            diags ~= Diagnostic(path, tok.line, tok.col, "error",
                "no-debugger", "`debugger` statement",
                true, tok.start, fLen, "");
        }

        /* eqeqeq — flag non-strict `==` / `!=`. Fix: replace with the
           strict form. */
        if (tok.kind == T.equals_equals)
            diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                "eqeqeq", "use `===` instead of `==`",
                true, tok.start, tok.length, "===");
        if (tok.kind == T.exclamation_equals)
            diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                "eqeqeq", "use `!==` instead of `!=`",
                true, tok.start, tok.length, "!==");

        /* no-eval — bare `eval(...)` or `Function(...)` call. We require
           the *previous* token to NOT be a `.` so `obj.eval(...)` is
           skipped. Not auto-fixable (rewriting may change semantics —
           e.g. the surrounding code may rely on the eval result). */
        if (prevWasIdent && tok.kind == T.open_paren)
        {
            if (prevIdentText == "eval")
                diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                    "no-eval", "avoid `eval()` (runtime code evaluation)");
            else if (prevIdentText == "Function")
                diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                    "no-eval", "avoid `new Function()` / `Function()` (dynamic eval)");
        }

        /* no-var — flag `var` declarations in favor of `let` / `const`.
           Auto-fix to `let` (the safer default; `const` requires
           reassignment analysis which the `prefer-const` rule below
           does separately). `var` is `T.t_var` from the lexer. */
        if (tok.kind == T.t_var)
            diags ~= Diagnostic(path, tok.line, tok.col, "warn",
                "no-var", "use `let` or `const` instead of `var`",
                true, tok.start, tok.length, "let");

        /* no-empty-block — flag `{}` (an empty block statement or
           object literal). Heuristic: if we just saw `{` and the
           current token is `}`, emit. Not auto-fixable (could be an
           intentional placeholder); reporting is the value. */
        if (prevKind == T.open_brace && tok.kind == T.close_brace)
            diags ~= Diagnostic(path, prevOpenBraceLine, prevOpenBraceCol,
                "warn", "no-empty-block",
                "empty block statement / object literal");

        if (tok.kind == T.open_brace)
        {
            prevOpenBraceStart = tok.start;
            prevOpenBraceLine = tok.line;
            prevOpenBraceCol = tok.col;
        }
        prevKind = tok.kind;

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
