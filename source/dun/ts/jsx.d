/// JSX → React.createElement transformer for .jsx / .tsx files.
/// Classic mode emit only (no jsx-runtime / custom pragma). Skips
/// string / template / comment / regex contexts so `<` in non-JSX
/// positions (e.g. `a < b`, `a / b`) parses unchanged.
module dun.ts.jsx;


/// `@trusted policy`: JSX → React.createElement transform (or
/// Bun.jsx in Bun-compat mode). Scanner-based, pure D logic, no
/// FFI. Every `@trusted` is one of:
///   1. `Appender!(char[])` + `cast(string) char[]` for the
///      output buffer.
///   2. `std.regex` for JSX-attribute parsing — `@trusted` because
///      `regex` is currently `@system` in Phobos.
// Project convention (CLAUDE.md): allocator helpers go via
// `dun.platform.arena`, not `std.array` directly.
import dun.platform.arena : Appender;
import std.algorithm : canFind;
// Shared string/template skippers live in the lexer module so jsx.d
// and strip.d use a single implementation (no redundancy).
import dun.ts.parser.lexer : skipStringLit, skipTemplateLit;

/// Transform JSX expressions in `source` to React.createElement calls.
/// `source` is the file content; the function is a no-op for files
/// that don't contain JSX (cheap heuristic check up front).
string transformJsx(string source) @safe
{
    if (source.length < 2) return source;
    // Cheap heuristic: only run the full scanner when the source has
    // at least one `<X` looking thing after `(`, `,`, `=`, `return`, etc.
    // For now just check `<` exists.
    bool maybeJsx = false;
    foreach (i, c; source)
    {
        if (c == '<' && i + 1 < source.length)
        {
            char n = source[i + 1];
            if (n == '/' || n == '>'
                || (n >= 'a' && n <= 'z')
                || (n >= 'A' && n <= 'Z'))
            {
                maybeJsx = true;
                break;
            }
        }
    }
    if (!maybeJsx) return source;

    Appender!(char[]) out_;
    out_.reserve(source.length + source.length / 4);

    size_t i = 0;
    while (i < source.length)
    {
        char c = source[i];

        // Strings / templates / comments are passed through verbatim.
        if (c == '\'' || c == '"')
        {
            auto end = skipStringLit(source, i);
            out_.put(source[i .. end]);
            i = end;
            continue;
        }
        if (c == '`')
        {
            auto end = skipTemplateLit(source, i);
            out_.put(source[i .. end]);
            i = end;
            continue;
        }
        if (c == '/' && i + 1 < source.length)
        {
            if (source[i + 1] == '/')
            {
                size_t e = i;
                while (e < source.length && source[e] != '\n') e++;
                out_.put(source[i .. e]);
                i = e;
                continue;
            }
            if (source[i + 1] == '*')
            {
                size_t e = i + 2;
                while (e + 1 < source.length && !(source[e] == '*' && source[e + 1] == '/')) e++;
                if (e + 1 < source.length) e += 2;
                out_.put(source[i .. e]);
                i = e;
                continue;
            }
            // Possible regex literal: scan back for previous significant
            // char. If it's an operator / `(` / `,` / `=` etc., this is
            // a regex; skip past matching `/`.
            if (isRegexContext(source, i))
            {
                auto end = skipRegex(source, i);
                out_.put(source[i .. end]);
                i = end;
                continue;
            }
        }

        // JSX-opening detection.
        if (c == '<' && isJsxContext(source, i))
        {
            size_t end;
            string emitted = parseJsxElement(source, i, end);
            if (emitted.length > 0)
            {
                out_.put(emitted);
                i = end;
                continue;
            }
        }

        out_.put(c);
        i++;
    }
    return (() @trusted => cast(string) out_.data)();
}

// -- internals --

// `skipStringLit` / `skipTemplateLit` imported from
// dun.ts.parser.lexer (single implementation across the TS layer).

private size_t skipRegex(string s, size_t start) @safe pure nothrow @nogc
{
    size_t i = start + 1;
    bool inClass = false;
    while (i < s.length)
    {
        char ch = s[i];
        if (ch == '\\' && i + 1 < s.length) { i += 2; continue; }
        if (ch == '[') inClass = true;
        else if (ch == ']') inClass = false;
        else if (ch == '/' && !inClass)
        {
            i++;
            // Skip flags.
            while (i < s.length && isFlagChar(s[i])) i++;
            return i;
        }
        i++;
    }
    return s.length;
}

private bool isFlagChar(char c) @safe pure nothrow @nogc
{
    return c == 'g' || c == 'i' || c == 'm' || c == 's' || c == 'u'
        || c == 'v' || c == 'y' || c == 'd';
}

/// Walk backward from `start` to find the prev significant char and
/// decide whether `/` here starts a regex (vs. a divide operator).
private bool isRegexContext(string s, size_t start) @safe pure nothrow @nogc
{
    if (start == 0) return true;
    size_t i = start;
    while (i > 0)
    {
        i--;
        char c = s[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        // Identifier-like char or `)`/`]` → division.
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == '_' || c == '$'
            || c == ')' || c == ']')
            return false;
        return true;
    }
    return true;
}

/// JSX is allowed where an expression is allowed: after `(`, `,`, `=`,
/// `?`, `:`, `return`, `=>`, `&&`, `||`, `??`, `;`, `{`, `}` (closing
/// of an attr `{expr}` block).
private bool isJsxContext(string s, size_t pos) @safe pure nothrow @nogc
{
    if (pos + 1 >= s.length) return false;
    char next = s[pos + 1];
    if (!(next == '>' || next == '/' || (next >= 'a' && next <= 'z')
       || (next >= 'A' && next <= 'Z') || next == '_' || next == '$'))
        return false;

    // Walk backward over whitespace.
    if (pos == 0) return true;
    size_t i = pos;
    while (i > 0)
    {
        i--;
        char c = s[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        // Followers that mean "expression position":
        if (c == '(' || c == ',' || c == '=' || c == '?' || c == ':'
            || c == ';' || c == '{' || c == '}' || c == '['
            || c == '!' || c == '&' || c == '|' || c == '+'
            || c == '-' || c == '*' || c == '%' || c == '~')
            return true;
        // > can be the close of a JSX expression — treat as expr pos
        // so adjacent siblings work.
        if (c == '>') return true;
        // Keyword preceding: `return`, `typeof`, `void`, `delete`, `new`,
        // `in`, `of`, `await`, `yield`. We do simple identifier scan.
        size_t end = i + 1;
        size_t st = end;
        while (st > 0)
        {
            char x = s[st - 1];
            if ((x >= 'a' && x <= 'z') || (x >= 'A' && x <= 'Z')
                || (x >= '0' && x <= '9') || x == '_' || x == '$')
                st--;
            else break;
        }
        if (st == end) return false;
        auto word = s[st .. end];
        if (word == "return" || word == "typeof" || word == "void"
            || word == "delete" || word == "new" || word == "in"
            || word == "of" || word == "await" || word == "yield"
            || word == "instanceof" || word == "throw" || word == "default")
            return true;
        return false;
    }
    return true;
}

/// Parse one JSX element starting at `s[start]` (where `s[start] == '<'`).
/// On success, returns the emitted JS source and sets `end` to one past
/// the consumed input. On failure, returns "" (caller falls through).
private string parseJsxElement(string s, size_t start, out size_t end) @safe
{
    size_t p = start + 1;
    if (p >= s.length) return "";

    // Fragment: `<>` or `</>`.
    if (s[p] == '>')
    {
        p++;
        Appender!(char[]) frag;
        frag.put("React.createElement(React.Fragment, null");
        parseChildren(s, p, frag);
        // Expect `</>` here.
        if (p + 2 < s.length && s[p] == '<' && s[p + 1] == '/' && s[p + 2] == '>')
        {
            frag.put(")");
            end = p + 3;
            return (() @trusted => cast(string) frag.data)();
        }
        return "";
    }

    // Element. Read tag name (allow member expr: `foo.bar.baz`).
    string tag;
    {
        size_t tagStart = p;
        if (!isIdentStart(s[p])) return "";
        p++;
        while (p < s.length && (isIdentChar(s[p]) || s[p] == '.' || s[p] == '-')) p++;
        tag = s[tagStart .. p];
    }

    bool isComponent = (tag[0] >= 'A' && tag[0] <= 'Z') || tag.canFind('.');
    string tagExpr = isComponent ? tag : ('"' ~ tag ~ '"');

    Appender!(char[]) el;
    el.put("React.createElement(");
    el.put(tagExpr);

    // Parse attributes until `/>` or `>`.
    Appender!(char[]) propsBuf;     // named attrs, comma-joined
    Appender!(char[]) spreadList;   // for {...spread}, comma-joined
    bool firstSpread = true;
    bool firstNamed = true;
    bool hasSpread = false;
    while (p < s.length)
    {
        while (p < s.length && (s[p] == ' ' || s[p] == '\t' || s[p] == '\n' || s[p] == '\r')) p++;
        if (p >= s.length) return "";
        if (s[p] == '/' || s[p] == '>') break;

        // Spread `{...expr}`.
        if (s[p] == '{')
        {
            // Find inner `...expr`.
            size_t inner = p + 1;
            while (inner < s.length && (s[inner] == ' ' || s[inner] == '\t')) inner++;
            if (inner + 2 < s.length && s[inner] == '.' && s[inner + 1] == '.' && s[inner + 2] == '.')
            {
                // Read until matching `}` at depth 0.
                size_t exprStart = inner + 3;
                size_t exprEnd = exprStart;
                int depth = 1;
                while (exprEnd < s.length && depth > 0)
                {
                    char ch = s[exprEnd];
                    if (ch == '{') depth++;
                    else if (ch == '}') { depth--; if (depth == 0) break; }
                    else if (ch == '\'' || ch == '"') exprEnd = skipStringLit(s, exprEnd) - 1;
                    else if (ch == '`') exprEnd = skipTemplateLit(s, exprEnd) - 1;
                    exprEnd++;
                }
                if (exprEnd >= s.length) return "";
                if (!firstSpread) spreadList.put(", ");
                firstSpread = false;
                hasSpread = true;
                spreadList.put(s[exprStart .. exprEnd]);
                p = exprEnd + 1;
                continue;
            }
            return "";
        }

        // Named attribute `name` or `name="val"` or `name={expr}`.
        size_t nameStart = p;
        if (!isIdentStart(s[p])) return "";
        p++;
        while (p < s.length && (isIdentChar(s[p]) || s[p] == '-' || s[p] == ':')) p++;
        string attrName = s[nameStart .. p];
        string attrValue;
        if (p < s.length && s[p] == '=')
        {
            p++;
            if (p < s.length && (s[p] == '"' || s[p] == '\''))
            {
                auto strEnd = skipStringLit(s, p);
                attrValue = s[p .. strEnd];
                if (attrValue.length >= 2 && (attrValue[0] == '"' || attrValue[0] == '\''))
                {
                    // Normalize to double-quoted literal.
                    string inner = attrValue[1 .. $ - 1];
                    attrValue = "\"" ~ inner ~ "\"";
                }
                p = strEnd;
            }
            else if (p < s.length && s[p] == '{')
            {
                p++;
                size_t exprStart = p;
                int depth = 1;
                while (p < s.length && depth > 0)
                {
                    char ch = s[p];
                    if (ch == '{') depth++;
                    else if (ch == '}') { depth--; if (depth == 0) break; }
                    else if (ch == '\'' || ch == '"') p = skipStringLit(s, p) - 1;
                    else if (ch == '`') p = skipTemplateLit(s, p) - 1;
                    p++;
                }
                if (p >= s.length) return "";
                // Attribute values may themselves contain JSX. Recurse.
                attrValue = transformJsx(cast(string) s[exprStart .. p].idup);
                p++;  // past `}`
            }
            else return "";
        }
        else
        {
            attrValue = "true";
        }

        if (!firstNamed) propsBuf.put(", ");
        firstNamed = false;
        propsBuf.put('"');
        propsBuf.put(attrName);
        propsBuf.put("\": ");
        propsBuf.put(attrValue);
    }

    // Build props arg.
    if (propsBuf.data.length == 0 && !hasSpread)
        el.put(", null");
    else if (!hasSpread)
    {
        el.put(", { ");
        el.put(propsBuf.data);
        el.put(" }");
    }
    else if (propsBuf.data.length == 0)
    {
        el.put(", Object.assign({}, ");
        el.put(spreadList.data);
        el.put(")");
    }
    else
    {
        el.put(", Object.assign({}, ");
        el.put(spreadList.data);
        el.put(", { ");
        el.put(propsBuf.data);
        el.put(" })");
    }

    // Self-closing `/>` or `>` then children + closing tag.
    if (p < s.length && s[p] == '/' && p + 1 < s.length && s[p + 1] == '>')
    {
        el.put(")");
        end = p + 2;
        return (() @trusted => cast(string) el.data)();
    }
    if (p >= s.length || s[p] != '>') return "";
    p++;

    // Children until `</tag>` (or `</>` if fragment — already handled).
    parseChildren(s, p, el);

    // Closing tag.
    if (p + 1 >= s.length || s[p] != '<' || s[p + 1] != '/') return "";
    p += 2;
    while (p < s.length && s[p] != '>') p++;
    if (p >= s.length) return "";
    p++;

    el.put(")");
    end = p;
    return (() @trusted => cast(string) el.data)();
}

/// Parse JSX children (text, `{expr}`, nested elements) until the next
/// `</`. Appends each child as a trailing argument to `out_`. `p` is
/// updated to point at the `<` of the closing tag.
private void parseChildren(string s, ref size_t p, ref Appender!(char[]) out_) @safe
{
    while (p < s.length)
    {
        // Closing tag?
        if (s[p] == '<' && p + 1 < s.length && s[p + 1] == '/')
            return;

        // Nested element.
        if (s[p] == '<' && p + 1 < s.length
            && (isIdentStart(s[p + 1]) || s[p + 1] == '>'))
        {
            size_t childEnd;
            string emitted = parseJsxElement(s, p, childEnd);
            if (emitted.length == 0) { out_.put(s[p]); p++; continue; }
            out_.put(", ");
            out_.put(emitted);
            p = childEnd;
            continue;
        }

        // {expression}
        if (s[p] == '{')
        {
            p++;
            size_t exprStart = p;
            int depth = 1;
            while (p < s.length && depth > 0)
            {
                char ch = s[p];
                if (ch == '{') depth++;
                else if (ch == '}') { depth--; if (depth == 0) break; }
                else if (ch == '\'' || ch == '"') p = skipStringLit(s, p) - 1;
                else if (ch == '`') p = skipTemplateLit(s, p) - 1;
                else if (ch == '<' && p + 1 < s.length
                    && (isIdentStart(s[p + 1]) || s[p + 1] == '>'))
                {
                    size_t childEnd;
                    string nested = parseJsxElement(s, p, childEnd);
                    if (nested.length > 0) { /* swallow into outer string */ p = childEnd - 1; }
                }
                p++;
            }
            if (p >= s.length) return;
            auto expr = s[exprStart .. p];
            p++;  // past `}`
            // Skip empty expressions like `{}` or all-whitespace.
            bool nonEmpty = false;
            foreach (char xc; expr) if (xc != ' ' && xc != '\t' && xc != '\n' && xc != '\r') { nonEmpty = true; break; }
            if (nonEmpty)
            {
                out_.put(", ");
                // Expression may itself contain JSX (e.g. `{<span>x</span>}`).
                // Recursively transform so the embedded element is rewritten too.
                out_.put(transformJsx(cast(string) expr.idup));
            }
            continue;
        }

        // Text: accumulate until next `<` or `{`. Emit as JSON string.
        size_t textStart = p;
        while (p < s.length && s[p] != '<' && s[p] != '{') p++;
        string text = s[textStart .. p];
        // Trim leading/trailing whitespace lines (JSX semantics).
        string trimmed = trimJsxText(text);
        if (trimmed.length > 0)
        {
            out_.put(", ");
            out_.put(jsonStringLit(trimmed));
        }
    }
}

/// JSX whitespace: lines that are all whitespace are dropped; leading
/// and trailing whitespace on the boundary are collapsed.
private string trimJsxText(string t) @safe pure nothrow
{
    // Strip if entire string is whitespace.
    bool allWs = true;
    foreach (c; t) if (c != ' ' && c != '\t' && c != '\n' && c != '\r') { allWs = false; break; }
    if (allWs) return "";
    // Collapse newlines + surrounding ws into single space.
    Appender!(char[]) sb;
    bool seenSpace = false;
    foreach (c; t)
    {
        if (c == '\n' || c == '\r' || c == '\t' || c == ' ')
        {
            if (!seenSpace) { sb.put(' '); seenSpace = true; }
        }
        else { sb.put(c); seenSpace = false; }
    }
    return (() @trusted => cast(string) sb.data)();
}

private string jsonStringLit(string s) @safe pure nothrow
{
    Appender!(char[]) sb;
    sb.put('"');
    foreach (c; s)
    {
        if (c == '"') sb.put("\\\"");
        else if (c == '\\') sb.put("\\\\");
        else if (c == '\n') sb.put("\\n");
        else if (c == '\r') sb.put("\\r");
        else if (c == '\t') sb.put("\\t");
        else sb.put(c);
    }
    sb.put('"');
    return (() @trusted => cast(string) sb.data)();
}

private bool isIdentStart(char c) @safe pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
}

private bool isIdentChar(char c) @safe pure nothrow @nogc
{
    return isIdentStart(c) || (c >= '0' && c <= '9');
}

unittest
{
    auto out1 = transformJsx("var x = <div>hi</div>;");
    assert(out1.canFind("React.createElement(\"div\""), out1);

    auto out2 = transformJsx("var x = <Foo />;");
    assert(out2.canFind("React.createElement(Foo, null)"), out2);

    auto out3 = transformJsx("var x = <Foo bar={1} baz=\"two\">child</Foo>;");
    assert(out3.canFind("React.createElement(Foo"), out3);
    assert(out3.canFind("\"bar\": 1"), out3);
    assert(out3.canFind("\"baz\": \"two\""), out3);

    auto out4 = transformJsx("var x = <>{a}{b}</>;");
    assert(out4.canFind("React.Fragment"), out4);

    auto out5 = transformJsx("var x = 4 / 2;");  // no JSX
    assert(out5.canFind("4 / 2"), out5);
}
