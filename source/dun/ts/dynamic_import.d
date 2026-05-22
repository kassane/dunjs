/// Rewrite `import("x")` → `__dunImport__("x")` so JSC/V8 (which
/// don't wire `HostImportModuleDynamically`) can service dynamic
/// import. Static `import x from "y"` and `import.meta` are left
/// alone; string/template/comment/regex contexts are skipped.
module dun.ts.dynamic_import;


/// `@trusted policy`: source-rewriter that turns `import(x)` into
/// `__dunImport__(x)` for JSC/V8 (which don't expose dynamic-import
/// at the engine level). Pure D scanner; `@trusted` is for the
/// `cast(string) char[]` on the output buffer.
import dun.platform.arena : Appender;
import dun.ts.parser.lexer : skipRegexLit, charAllowsRegex,
    regexAllowingKeywordEndsAt;

// String / template literal skippers. Inlined here (not imported from
// `dun.ts.strip`) because that module's helpers live under a
// `private:` colon. Same shape as strip.d's versions.
private size_t skipStringLit(string buf, size_t i) @safe pure nothrow @nogc
{
    if (i >= buf.length) return i;
    immutable quote = buf[i];
    i++;
    while (i < buf.length)
    {
        if (buf[i] == '\\') { i += 2; continue; }
        if (buf[i] == quote) return i + 1;
        i++;
    }
    return i;
}

private size_t skipTemplateLit(string buf, size_t i) @safe pure nothrow @nogc
{
    if (i >= buf.length) return i;
    i++;
    while (i < buf.length)
    {
        if (buf[i] == '\\') { i += 2; continue; }
        if (buf[i] == '`') return i + 1;
        if (buf[i] == '$' && i + 1 < buf.length && buf[i + 1] == '{')
        {
            i += 2;
            int depth = 1;
            while (i < buf.length && depth > 0)
            {
                if (buf[i] == '{') depth++;
                else if (buf[i] == '}') depth--;
                else if (buf[i] == '`') i = skipTemplateLit(buf, i) - 1;
                else if (buf[i] == '\'' || buf[i] == '"')
                    i = skipStringLit(buf, i) - 1;
                i++;
            }
            continue;
        }
        i++;
    }
    return i;
}

/// Rewrite all dynamic `import(...)` calls in `src` to
/// `__dunImport__(...)`. Returns a new string with the rewrites
/// applied; returns `src` unchanged if no rewrites needed.
string rewriteDynamicImport(string src) @trusted
{
    if (src.length < 8 || !hasImportCall(src))
        return src;

    Appender!(char[]) out_;
    out_.reserve(src.length + 64);
    size_t i = 0;
    while (i < src.length)
    {
        immutable c = src[i];
        if (c == '\'' || c == '"')
        {
            auto end = skipStringLit(src, i);
            out_ ~= src[i .. end];
            i = end;
            continue;
        }
        if (c == '`')
        {
            auto end = skipTemplateLit(src, i);
            out_ ~= src[i .. end];
            i = end;
            continue;
        }
        if (c == '/' && i + 1 < src.length)
        {
            if (src[i + 1] == '/')
            {
                while (i < src.length && src[i] != '\n') { out_ ~= src[i]; i++; }
                continue;
            }
            if (src[i + 1] == '*')
            {
                auto end = i + 2;
                while (end + 1 < src.length && !(src[end] == '*' && src[end + 1] == '/'))
                    end++;
                if (end + 1 < src.length) end += 2;
                out_ ~= src[i .. end];
                i = end;
                continue;
            }
            // Regex literal: needs caller-context to disambiguate. Use the
            // same trick strip.d uses (prev-byte + keyword check).
            size_t prevIdx = i;
            while (prevIdx > 0 && (src[prevIdx - 1] == ' ' || src[prevIdx - 1] == '\t'
                || src[prevIdx - 1] == '\n' || src[prevIdx - 1] == '\r'))
                prevIdx--;
            immutable prevCh = prevIdx > 0 ? src[prevIdx - 1] : '\n';
            bool isRegex = charAllowsRegex(prevCh);
            if (!isRegex && prevIdx > 0)
            {
                immutable kwStart = regexAllowingKeywordEndsAt(src, prevIdx);
                isRegex = kwStart < prevIdx;
            }
            if (isRegex)
            {
                auto end = skipRegexLit(src, i);
                out_ ~= src[i .. end];
                i = end;
                continue;
            }
        }
        // Match `import` followed by optional whitespace then `(`.
        if (c == 'i' && i + 6 < src.length && src[i .. i + 6] == "import"
            && !isIdentCont(i + 6 < src.length ? src[i + 6] : ' '))
        {
            // Skip if preceded by `.` (member access like `obj.import(`).
            // Or by ident-cont (so `foo_import(` doesn't match).
            if (i > 0)
            {
                immutable p = src[i - 1];
                if (p == '.' || isIdentCont(p))
                {
                    out_ ~= c;
                    i++;
                    continue;
                }
            }
            // Look ahead past whitespace for `(`. If found, rewrite.
            size_t after = i + 6;
            while (after < src.length && (src[after] == ' ' || src[after] == '\t'))
                after++;
            if (after < src.length && src[after] == '(')
            {
                out_ ~= "__dunImport__";
                out_ ~= src[i + 6 .. after + 1];  // preserve whitespace + `(`
                i = after + 1;
                continue;
            }
            // `import.meta` or static `import x from`. Pass through.
            out_ ~= c;
            i++;
            continue;
        }
        out_ ~= c;
        i++;
    }
    return (() @trusted => cast(string) out_[])();
}

/// Cheap pre-check so the common no-`import(` case avoids the full
/// scanner pass. Looks for the substring `import(` or `import (`.
private bool hasImportCall(string src) @safe pure nothrow @nogc
{
    if (src.length < 7) return false;
    for (size_t i = 0; i + 7 <= src.length; i++)
    {
        if (src[i] != 'i') continue;
        if (i + 6 < src.length && src[i .. i + 6] == "import")
        {
            size_t j = i + 6;
            while (j < src.length && (src[j] == ' ' || src[j] == '\t')) j++;
            if (j < src.length && src[j] == '(') return true;
        }
    }
    return false;
}

private bool isIdentCont(char c) @safe pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c == '_' || c == '$';
}

/// JS source for the runtime helper. Installed once at engine boot;
/// the rewriter above redirects all dynamic-import call sites here.
/// Wraps `require(specifier)` so the CJS namespace becomes a resolved
/// Promise -- matches the typical `await import("fs")` usage that
/// only cares about the CJS namespace shape.
string dunImportShimSource() pure nothrow @safe
{
    return
    "globalThis.__dunImport__ = function(specifier) {" ~
    "  try {" ~
    "    var mod = require(specifier);" ~
    "    /* CJS modules with __esModule already mimic ESM shape. " ~
    "       Plain CJS namespaces also work for `await import('fs')` " ~
    "       because callers destructure `const { x } = await import(p)`. */" ~
    "    return Promise.resolve(mod);" ~
    "  } catch (e) {" ~
    "    return Promise.reject(e);" ~
    "  }" ~
    "};";
}

unittest
{
    // No-op when no dynamic import present.
    auto s1 = rewriteDynamicImport("const x = 1;");
    assert(s1 == "const x = 1;");

    // Static import + import.meta untouched.
    auto s2 = rewriteDynamicImport(`import x from "y"; console.log(import.meta.url);`);
    assert(s2 == `import x from "y"; console.log(import.meta.url);`);

    // Function-call form rewritten.
    auto s3 = rewriteDynamicImport(`const fs = await import("fs");`);
    assert(s3 == `const fs = await __dunImport__("fs");`,
        "got: " ~ s3);

    // Strings preserved.
    auto s4 = rewriteDynamicImport(`const s = "import(\"x\")";`);
    assert(s4 == `const s = "import(\"x\")";`);

    // Member access untouched: `obj.import(x)`.
    auto s5 = rewriteDynamicImport(`obj.import("y");`);
    assert(s5 == `obj.import("y");`);

    // With whitespace.
    auto s6 = rewriteDynamicImport(`import  ("y")`);
    assert(s6 == `__dunImport__  ("y")`,
        "got: " ~ s6);
}
