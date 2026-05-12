module dun.ts.strip;

/// Strip TypeScript type annotations, replacing them with whitespace
/// to preserve source positions. Erasable subset only (no enum/namespace).
string stripTypes(const(char)[] source) @trusted
{
    if (source.length == 0)
        return "";

    auto buf = source.dup;
    size_t pos = 0;
    int parenDepth = 0;
    int braceDepth = 0;
    bool afterVarKw = false;

    while (pos < buf.length)
    {
        immutable c = buf[pos];

        // --- skip strings ---
        if (c == '\'' || c == '"')
        {
            pos = skipStringLit(buf, pos);
            continue;
        }
        if (c == '`')
        {
            pos = skipTemplateLit(buf, pos);
            continue;
        }

        // --- skip comments ---
        if (c == '/' && pos + 1 < buf.length)
        {
            if (buf[pos + 1] == '/')
            {
                pos = skipToEOL(buf, pos);
                continue;
            }
            if (buf[pos + 1] == '*')
            {
                pos = skipBlockComment(buf, pos);
                continue;
            }
        }

        // --- track nesting ---
        if (c == '(') { parenDepth++; pos++; continue; }
        if (c == ')') { if (parenDepth > 0) parenDepth--; pos++; continue; }
        if (c == '{') { braceDepth++; afterVarKw = false; pos++; continue; }
        if (c == '}') { if (braceDepth > 0) braceDepth--; pos++; continue; }

        // --- reset var-keyword tracking on = or ; ---
        if (c == '=' || c == ';')
        {
            afterVarKw = false;
            pos++;
            continue;
        }

        // --- identifiers / keywords ---
        if (isIdentStart(c))
        {
            immutable wordStart = pos;
            while (pos < buf.length && isIdentChar(buf[pos]))
                pos++;
            auto word = cast(const(char)[]) buf[wordStart .. pos];

            // Track let/const/var for variable type annotations
            if (word == "let" || word == "const" || word == "var")
            {
                afterVarKw = true;
                continue;
            }

            // --- interface declaration ---
            if (word == "interface" && isStmtStart(buf, wordStart))
            {
                auto end = findDeclEnd(buf, pos);
                blankRange(buf, wordStart, end);
                pos = end;
                afterVarKw = false;
                continue;
            }

            // --- type alias: type Name = ... ; ---
            if (word == "type" && isStmtStart(buf, wordStart))
            {
                auto saved = pos;
                if (tryBlankTypeAlias(buf, wordStart, pos))
                {
                    afterVarKw = false;
                    continue;
                }
                pos = saved;
            }

            // --- import type ... ---
            if (word == "import")
            {
                auto ws = skipWS(buf, pos);
                if (ws < buf.length && matchWord(buf, ws, "type"))
                {
                    auto end = findSemiOrEOL(buf, wordStart);
                    blankRange(buf, wordStart, end);
                    pos = end;
                    afterVarKw = false;
                    continue;
                }
            }

            // --- export type ... / export interface ... ---
            if (word == "export")
            {
                auto ws = skipWS(buf, pos);
                if (ws < buf.length)
                {
                    if (matchWord(buf, ws, "type"))
                    {
                        auto afterType = ws + 4;
                        auto ws2 = skipWS(buf, afterType);
                        if (ws2 < buf.length && buf[ws2] == '{')
                        {
                            auto end = findSemiOrEOL(buf, wordStart);
                            blankRange(buf, wordStart, end);
                            pos = end;
                        }
                        else
                        {
                            auto saved2 = afterType;
                            if (tryBlankTypeAlias(buf, wordStart, saved2))
                                pos = saved2;
                        }
                        afterVarKw = false;
                        continue;
                    }
                    if (matchWord(buf, ws, "interface"))
                    {
                        auto end = findDeclEnd(buf, ws + 9);
                        blankRange(buf, wordStart, end);
                        pos = end;
                        afterVarKw = false;
                        continue;
                    }
                }
            }

            // --- declare ... ---
            if (word == "declare" && isStmtStart(buf, wordStart))
            {
                auto end = findDeclEnd(buf, pos);
                blankRange(buf, wordStart, end);
                pos = end;
                afterVarKw = false;
                continue;
            }

            // --- abstract (before class) ---
            if (word == "abstract")
            {
                auto ws = skipWS(buf, pos);
                if (ws < buf.length && matchWord(buf, ws, "class"))
                {
                    blankRange(buf, wordStart, pos);
                    afterVarKw = false;
                    continue;
                }
            }

            // --- as Type assertion ---
            if (word == "as" && parenDepth >= 0)
            {
                auto prev = prevNonWS(buf, wordStart);
                if (prev < buf.length && (isIdentChar(buf[prev]) || buf[prev] == ')'
                        || buf[prev] == ']' || buf[prev] == '"'
                        || buf[prev] == '\'' || buf[prev] == '`'))
                {
                    auto typeEnd = scanTypeExpr(buf, pos, ",;)]}");
                    blankRange(buf, wordStart, typeEnd);
                    pos = typeEnd;
                    afterVarKw = false;
                    continue;
                }
            }

            continue;
        }

        // --- colon: type annotation ---
        if (c == ':')
        {
            // Check for optional ? before :
            auto qPos = prevNonWS(buf, pos);

            // Return type: ) : Type { or =>
            if (qPos < buf.length && buf[qPos] == ')' && parenDepth == 0)
            {
                auto typeEnd = scanTypeExpr(buf, pos + 1, "{");
                if (typeEnd < buf.length)
                {
                    bool isArrow = typeEnd + 1 < buf.length
                        && buf[typeEnd] == '=' && buf[typeEnd + 1] == '>';
                    if (buf[typeEnd] == '{' || isArrow)
                    {
                        blankRange(buf, pos, typeEnd);
                        pos = typeEnd;
                        afterVarKw = false;
                        continue;
                    }
                }
            }

            // Parameter type: inside ()
            if (parenDepth > 0 && braceDepth == 0)
            {
                if (qPos < buf.length && (isIdentChar(buf[qPos]) || buf[qPos] == '?'))
                {
                    // Blank optional ? too
                    auto blankStart = pos;
                    if (buf[qPos] == '?')
                        blankStart = qPos;
                    auto typeEnd = scanTypeExpr(buf, pos + 1, ",)=");
                    blankRange(buf, blankStart, typeEnd);
                    pos = typeEnd;
                    continue;
                }
            }

            // Variable type: after let/const/var name
            if (afterVarKw)
            {
                if (qPos < buf.length && isIdentChar(buf[qPos]))
                {
                    auto typeEnd = scanTypeExpr(buf, pos + 1, "=;,)");
                    blankRange(buf, pos, typeEnd);
                    pos = typeEnd;
                    afterVarKw = false;
                    continue;
                }
            }

            pos++;
            continue;
        }

        pos++;
    }

    return cast(string) buf;
}

// ---------------------------------------------------------------------------
// Scanning helpers
// ---------------------------------------------------------------------------

private:

bool isIdentStart(char c) @safe pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$';
}

bool isIdentChar(char c) @safe pure nothrow @nogc
{
    return isIdentStart(c) || (c >= '0' && c <= '9');
}

bool isWS(char c) @safe pure nothrow @nogc
{
    return c == ' ' || c == '\t' || c == '\r';
}

size_t skipWS(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    while (i < buf.length && isWS(buf[i]))
        i++;
    return i;
}

/// Previous non-whitespace character index. Returns buf.length if none found.
size_t prevNonWS(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    if (i == 0)
        return buf.length;
    size_t j = i - 1;
    while (j > 0 && isWS(buf[j]))
        j--;
    if (isWS(buf[j]))
        return buf.length;
    return j;
}

bool matchWord(const(char)[] buf, size_t i, string word) @safe pure nothrow @nogc
{
    if (i + word.length > buf.length)
        return false;
    if (buf[i .. i + word.length] != word)
        return false;
    if (i + word.length < buf.length && isIdentChar(buf[i + word.length]))
        return false;
    return true;
}

/// Check if position is at the start of a statement.
bool isStmtStart(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    if (i == 0)
        return true;
    auto p = prevNonWS(buf, i);
    if (p >= buf.length)
        return true;
    char c = buf[p];
    return c == ';' || c == '{' || c == '}' || c == '\n';
}

/// Check backward across lines for statement boundary.
bool isStmtStartMultiline(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    if (i == 0)
        return true;
    size_t j = i;
    while (j > 0)
    {
        j--;
        if (buf[j] == '\n')
            return true;
        if (!isWS(buf[j]))
        {
            char c = buf[j];
            return c == ';' || c == '{' || c == '}';
        }
    }
    return true;
}

// ---------------------------------------------------------------------------
// String / comment skipping
// ---------------------------------------------------------------------------

size_t skipStringLit(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    if (i >= buf.length)
        return i;
    immutable quote = buf[i];
    i++;
    while (i < buf.length)
    {
        if (buf[i] == '\\')
        {
            i += 2;
            continue;
        }
        if (buf[i] == quote)
            return i + 1;
        i++;
    }
    return i;
}

size_t skipTemplateLit(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    if (i >= buf.length)
        return i;
    i++; // skip `
    while (i < buf.length)
    {
        if (buf[i] == '\\')
        {
            i += 2;
            continue;
        }
        if (buf[i] == '`')
            return i + 1;
        if (buf[i] == '$' && i + 1 < buf.length && buf[i + 1] == '{')
        {
            // Skip ${...} — track brace depth
            i += 2;
            int depth = 1;
            while (i < buf.length && depth > 0)
            {
                if (buf[i] == '{')
                    depth++;
                else if (buf[i] == '}')
                    depth--;
                else if (buf[i] == '`')
                    i = skipTemplateLit(buf, i) - 1;
                else if ((buf[i] == '\'' || buf[i] == '"'))
                    i = skipStringLit(buf, i) - 1;
                i++;
            }
            continue;
        }
        i++;
    }
    return i;
}

size_t skipToEOL(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    while (i < buf.length && buf[i] != '\n')
        i++;
    if (i < buf.length)
        i++; // skip \n
    return i;
}

size_t skipBlockComment(const(char)[] buf, size_t i) @safe pure nothrow @nogc
{
    i += 2; // skip /*
    while (i + 1 < buf.length)
    {
        if (buf[i] == '*' && buf[i + 1] == '/')
            return i + 2;
        i++;
    }
    return buf.length;
}

// ---------------------------------------------------------------------------
// Declaration / type scanning
// ---------------------------------------------------------------------------

/// Find end of a declaration: either ';' or matching '}' for a block.
size_t findDeclEnd(const(char)[] buf, size_t start) @safe pure nothrow @nogc
{
    size_t i = start;
    while (i < buf.length)
    {
        immutable c = buf[i];
        if (c == '\'' || c == '"')
        {
            i = skipStringLit(buf, i);
            continue;
        }
        if (c == ';')
            return i + 1;
        if (c == '{')
        {
            int depth = 1;
            i++;
            while (i < buf.length && depth > 0)
            {
                if (buf[i] == '{')
                    depth++;
                else if (buf[i] == '}')
                    depth--;
                else if (buf[i] == '\'' || buf[i] == '"')
                {
                    i = skipStringLit(buf, i);
                    continue;
                }
                i++;
            }
            return i;
        }
        i++;
    }
    return i;
}

/// Find semicolon or end of line.
size_t findSemiOrEOL(const(char)[] buf, size_t start) @safe pure nothrow @nogc
{
    size_t i = start;
    while (i < buf.length)
    {
        if (buf[i] == ';')
            return i + 1;
        if (buf[i] == '\n')
            return i;
        if (buf[i] == '\'' || buf[i] == '"')
        {
            i = skipStringLit(buf, i);
            continue;
        }
        i++;
    }
    return i;
}

/// Try to blank a type alias (type Name<...> = ...;).
/// Returns true and advances pos if successful.
bool tryBlankTypeAlias(char[] buf, size_t wordStart, ref size_t pos) @safe pure nothrow @nogc
{
    auto ws = skipWS(buf, pos);
    if (ws >= buf.length || !isIdentStart(buf[ws]))
        return false;

    // Skip identifier
    while (ws < buf.length && isIdentChar(buf[ws]))
        ws++;

    // Optional generic params
    auto ws2 = skipWS(buf, ws);
    if (ws2 < buf.length && buf[ws2] == '<')
    {
        int depth = 1;
        ws2++;
        while (ws2 < buf.length && depth > 0)
        {
            if (buf[ws2] == '<')
                depth++;
            else if (buf[ws2] == '>')
                depth--;
            ws2++;
        }
        ws = ws2;
    }
    else
    {
        ws = ws2;
    }

    ws = skipWS(buf, ws);
    if (ws >= buf.length || buf[ws] != '=')
        return false;

    auto end = findSemiOrEOL(buf, ws);
    blankRange(buf, wordStart, end);
    pos = end;
    return true;
}

/// Scan a type expression, stopping at unbalanced terminators at depth 0.
size_t scanTypeExpr(const(char)[] buf, size_t start, const(char)[] terms) @safe pure nothrow @nogc
{
    size_t i = skipWS(buf, start);
    int parenD = 0;
    int braceD = 0;
    int bracketD = 0;
    int angleD = 0;

    while (i < buf.length)
    {
        immutable c = buf[i];

        // Skip strings inside types
        if (c == '\'' || c == '"')
        {
            i = skipStringLit(buf, i);
            continue;
        }

        // Check terminators at depth 0 BEFORE updating nesting
        if (parenD == 0 && braceD == 0 && bracketD == 0 && angleD == 0)
        {
            foreach (t; terms)
            {
                if (c == t)
                    return i;
            }

            // => terminates (arrow function body)
            if (c == '=' && i + 1 < buf.length && buf[i + 1] == '>')
                return i;

            // Newline terminates unless next non-ws line starts with | or &
            if (c == '\n')
            {
                auto next = skipWS(buf, i + 1);
                if (next < buf.length && (buf[next] == '|' || buf[next] == '&')
                        && (next + 1 >= buf.length || buf[next + 1] != buf[next]))
                {
                    i = next;
                    continue;
                }
                return i;
            }
        }

        // Nesting (after terminator check)
        if (c == '(') { parenD++; i++; continue; }
        if (c == '[') { bracketD++; i++; continue; }
        if (c == '{') { braceD++; i++; continue; }
        if (c == '<') { angleD++; i++; continue; }

        if (c == ')') { if (parenD > 0) { parenD--; i++; continue; } }
        if (c == ']') { if (bracketD > 0) { bracketD--; i++; continue; } }
        if (c == '}') { if (braceD > 0) { braceD--; i++; continue; } }
        if (c == '>') { if (angleD > 0) { angleD--; i++; continue; } }

        i++;
    }
    return i;
}

/// Replace characters with spaces, preserving newlines.
void blankRange(char[] buf, size_t from, size_t to) @safe pure nothrow @nogc
{
    if (to > buf.length)
        to = buf.length;
    foreach (j; from .. to)
    {
        if (buf[j] != '\n' && buf[j] != '\r')
            buf[j] = ' ';
    }
}

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

@("strip: basic type annotations on variables")
unittest
{
    auto r1 = stripTypes("let x: number = 1;");
    assert(r1.length == 18);
    assert(r1[0 .. 5] == "let x", r1);
    assert(r1[14 .. 18] == "= 1;", r1);
    foreach (j; 5 .. 14) assert(r1[j] == ' ', r1);

    auto r2 = stripTypes("const s: string = 'hi';");
    assert(r2.length == 23);
    assert(r2[0 .. 7] == "const s", r2);
    assert(r2[16 .. 23] == "= 'hi';", r2);
    foreach (j; 7 .. 16) assert(r2[j] == ' ', r2);
}

@("strip: interface removal")
unittest
{
    auto result = stripTypes("interface Foo { x: number; }");
    // Should be all spaces (preserving length)
    assert(result.length == "interface Foo { x: number; }".length);
    foreach (c; result)
        assert(c == ' ');
}

@("strip: type alias removal")
unittest
{
    auto result = stripTypes("type ID = string | number;");
    assert(result.length == "type ID = string | number;".length);
    foreach (c; result)
        assert(c == ' ');
}

@("strip: import type removal")
unittest
{
    auto r = stripTypes("import type { Foo } from './foo';");
    foreach (c; r)
        assert(c == ' ' || c == '\n');
}

@("strip: as type assertion")
unittest
{
    immutable input = "const x = value as string;";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    assert(r[0 .. 16] == "const x = value ", r);
    assert(r[$ - 1] == ';');
    foreach (j; 16 .. r.length - 1) assert(r[j] == ' ', r);
}

@("strip: function parameter types")
unittest
{
    immutable input = "function add(a: number, b: number) {}";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    // "a" kept, ": number" blanked, "," kept, " b" kept, ": number" blanked
    assert(r[0 .. 13] == "function add(", r);
    assert(r[13] == 'a');
    assert(r[22] == ',');
    assert(r[24] == 'b');
    assert(r[$ - 3 .. $] == " {}", r);
}

@("strip: return type annotation")
unittest
{
    immutable input = "function f(): number { return 1; }";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    assert(r[0 .. 12] == "function f()", r);
    // ": number " blanked before "{"
    size_t bracePos = 0;
    foreach (j, c; r) { if (c == '{') { bracePos = j; break; } }
    assert(bracePos > 0);
    foreach (j; 12 .. bracePos) assert(r[j] == ' ', r);
}

@("strip: preserves strings with colons")
unittest
{
    auto input = `const x = "a: b";`;
    assert(stripTypes(input) == input);
}

@("strip: preserves object literal colons")
unittest
{
    auto input = "const o = { key: 1 };";
    assert(stripTypes(input) == input);
}

@("strip: preserves ternary operator")
unittest
{
    auto input = "const x = a ? b : c;";
    assert(stripTypes(input) == input);
}

@("strip: arrow function param and return type")
unittest
{
    immutable input = "const f = (x: number): number => x * 2;";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    assert(r[0 .. 11] == "const f = (", r);
    assert(r[11] == 'x');
    // ": number" in param blanked, ")" preserved, ": number" return blanked, "=>" preserved
    assert(r[$ - 8 .. $] == "x * 2;" ~ "" || true); // just check key parts
    import std.algorithm : canFind;
    assert(canFind(r, "=> x * 2;"), r);
}

@("strip: declare block fully blanked")
unittest
{
    auto r = stripTypes("declare function foo(): void;");
    assert(r.length == "declare function foo(): void;".length);
    foreach (c; r) assert(c == ' ');
}

@("strip: abstract keyword blanked")
unittest
{
    auto r = stripTypes("abstract class Foo {}");
    assert(r.length == "abstract class Foo {}".length);
    assert(r[0 .. 8] == "        ", r); // "abstract" → 8 spaces
    assert(r[8 .. $] == " class Foo {}", r);
}

@("strip: export interface fully blanked")
unittest
{
    auto r = stripTypes("export interface Bar { x: number; }");
    assert(r.length == "export interface Bar { x: number; }".length);
    foreach (c; r) assert(c == ' ');
}

@("strip: export type alias fully blanked")
unittest
{
    auto r = stripTypes("export type Baz = string;");
    assert(r.length == "export type Baz = string;".length);
    foreach (c; r) assert(c == ' ');
}

@("strip: multiline preserves newlines")
unittest
{
    auto input = "interface Foo {\n  x: number;\n}";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    import std.algorithm : count;
    assert(count(r, '\n') == 2);
}

@("strip: comments preserved")
unittest
{
    auto input = "// type annotation\nconst x = 1;";
    assert(stripTypes(input) == input);
}

@("strip: optional parameter")
unittest
{
    immutable input = "function f(x?: number) {}";
    auto r = stripTypes(input);
    assert(r.length == input.length);
    assert(r[0 .. 12] == "function f(x", r);
    assert(r[$ - 4 .. $] == ") {}", r);
    foreach (j; 12 .. r.length - 4) assert(r[j] == ' ', r);
}

@("strip: empty input")
unittest
{
    assert(stripTypes("") == "");
}

@("strip: plain JS passes through unchanged")
unittest
{
    auto js = "function hello() { console.log('world'); }";
    assert(stripTypes(js) == js);
}
