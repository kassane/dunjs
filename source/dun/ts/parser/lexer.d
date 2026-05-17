module dun.ts.parser.lexer;

// Token stream over a JS/TS source buffer.
//
// Ported from oven-sh/bun's `src/js_parser/lexer.zig` and
// `src/js_parser/lexer_tables.zig`. Same token set + same name
// convention (`t_*`) so the upstream parser code can be ported
// alongside without renaming. MIT licensed both ends. See
// TS-PARSER-PORT.md for the project plan; this is the lexer-only
// lift it recommended.
//
// Scope of this initial slice (see TODO markers for the rest):
//   * Single-line + block comments + shebang
//   * Identifiers + numeric literals (decimal, hex, oct, bin) +
//     keywords table
//   * Single + double quoted strings (no escapes beyond \\ \r \n)
//   * Common punctuation + multi-char operators (`==`, `===`, `=>`,
//     `??`, `?.`, `**`, `**=`, `<<`, `<<=`, `>>`, `>>=`, `>>>`,
//     `>>>=`, `&&`, `||`, `&=`, `|=`, `^=`, `+=`, `-=`, `/=`,
//     `*=`, `%=`, `??=`, `&&=`, `||=`)
//
// Not yet in this slice (deferred):
//   * Template literals (backtick + `${...}`)
//   * Regex vs divide disambiguation (needs parser feedback)
//   * Unicode identifier ranges (we accept ASCII + `$` + `_` for now)
//   * JSX/TSX mode switching
//   * BigInt literal suffix `n`
//   * Numeric separators inside literals

@safe pure nothrow @nogc:

/// One-byte tag matching Bun's `pub const T = enum(u8)`.
/// Order is significant -- `isCloseBraceOrEOF` etc. compare numerically.
enum T : ubyte
{
    eof,
    close_brace,         // ordered first after eof so EOF/close-brace
                         // comparisons fit in one branch (matches Bun)

    syntax_error,
    hashbang,

    no_substitution_template_literal,
    numeric_literal,
    string_literal,
    big_integer_literal,

    template_head,
    template_middle,
    template_tail,

    // punctuation
    ampersand,
    ampersand_ampersand,
    asterisk,
    asterisk_asterisk,
    at,
    bar,
    bar_bar,
    caret,
    close_bracket,
    close_paren,
    colon,
    comma,
    dot,
    dot_dot_dot,
    equals_equals,
    equals_equals_equals,
    equals_greater_than,
    exclamation,
    exclamation_equals,
    exclamation_equals_equals,
    greater_than,
    greater_than_equals,
    greater_than_greater_than,
    greater_than_greater_than_greater_than,
    less_than,
    less_than_equals,
    less_than_less_than,
    minus,
    minus_minus,
    open_brace,
    open_bracket,
    open_paren,
    percent,
    plus,
    plus_plus,
    question,
    question_question,
    question_dot,
    semicolon,
    slash,
    tilde,

    // assignments
    ampersand_ampersand_equals,
    ampersand_equals,
    asterisk_asterisk_equals,
    asterisk_equals,
    bar_bar_equals,
    bar_equals,
    caret_equals,
    equals,
    greater_than_greater_than_equals,
    greater_than_greater_than_greater_than_equals,
    less_than_less_than_equals,
    minus_equals,
    percent_equals,
    plus_equals,
    question_question_equals,
    slash_equals,

    // identifiers + keywords
    identifier,
    escaped_keyword,

    // reserved words
    t_break,
    t_case,
    t_catch,
    t_class,
    t_const,
    t_continue,
    t_debugger,
    t_default,
    t_delete,
    t_do,
    t_else,
    t_enum,
    t_export,
    t_extends,
    t_false,
    t_finally,
    t_for,
    t_function,
    t_if,
    t_import,
    t_in,
    t_instanceof,
    t_new,
    t_null,
    t_return,
    t_super,
    t_switch,
    t_this,
    t_throw,
    t_true,
    t_try,
    t_typeof,
    t_var,
    t_void,
    t_while,
    t_with,
}

/// One token's location + payload. Strings / numbers live in slices of
/// the source buffer or in `text`, so the token itself stays POD.
struct Token
{
    T kind;
    uint start;     // byte offset into source
    uint length;
    uint line;      // 1-based for human reporting
    uint col;       // 1-based
    /// For `string_literal` / `template_*` / `identifier` /
    /// `numeric_literal`: the raw slice from the source (no decoding
    /// of escapes -- the parser handles JSON-like decode for the few
    /// cases it needs the cooked value).
    const(char)[] text;
}

/// Scanner over a string. Position-only -- `next()` produces the next
/// token from the current position.
struct Lexer
{
    const(char)[] source;
    uint pos;
    uint line = 1;
    uint col = 1;

    this(const(char)[] src) @safe pure nothrow @nogc
    {
        source = src;
    }

    /// Read the next token, advancing the cursor past it.
    Token next() @safe pure nothrow @nogc
    {
        skipTrivia();
        if (pos >= source.length)
            return token(T.eof, pos, 0);

        immutable startLine = line;
        immutable startCol  = col;
        immutable startPos  = pos;
        immutable c = source[pos];

        // Numeric literal (decimal, hex, oct, bin)
        if (isDigit(c) || (c == '.' && pos + 1 < source.length && isDigit(source[pos + 1])))
            return scanNumber(startPos, startLine, startCol);

        // Identifier / keyword
        if (isIdentStart(c))
            return scanIdent(startPos, startLine, startCol);

        // String literal
        if (c == '"' || c == '\'')
            return scanString(startPos, startLine, startCol, c);

        // Hashbang at file start
        if (c == '#' && pos == 0 && pos + 1 < source.length && source[pos + 1] == '!')
            return scanLineThenToken(T.hashbang, startPos, startLine, startCol);

        return scanPunctuation(startPos, startLine, startCol, c);
    }

private:

    Token token(T kind, uint start, uint length,
        uint line_ = 0, uint col_ = 0,
        const(char)[] text = null) @safe pure nothrow @nogc
    {
        Token t;
        t.kind = kind;
        t.start = start;
        t.length = length;
        t.line = line_;
        t.col = col_;
        t.text = text.length ? text : source[start .. start + length];
        return t;
    }

    void advance() @safe pure nothrow @nogc
    {
        if (pos < source.length)
        {
            if (source[pos] == '\n') { line++; col = 1; }
            else col++;
            pos++;
        }
    }

    void skipTrivia() @safe pure nothrow @nogc
    {
        while (pos < source.length)
        {
            immutable c = source[pos];
            if (c == ' ' || c == '\t' || c == '\r' || c == '\n')
            {
                advance();
                continue;
            }
            if (c == '/' && pos + 1 < source.length)
            {
                if (source[pos + 1] == '/')
                {
                    while (pos < source.length && source[pos] != '\n') advance();
                    continue;
                }
                if (source[pos + 1] == '*')
                {
                    advance(); advance();
                    while (pos + 1 < source.length
                        && !(source[pos] == '*' && source[pos + 1] == '/'))
                        advance();
                    if (pos + 1 < source.length) { advance(); advance(); }
                    continue;
                }
            }
            return;
        }
    }

    Token scanLineThenToken(T kind, uint startPos, uint startLine, uint startCol)
        @safe pure nothrow @nogc
    {
        while (pos < source.length && source[pos] != '\n') advance();
        return token(kind, startPos, pos - startPos, startLine, startCol);
    }

    Token scanIdent(uint startPos, uint startLine, uint startCol)
        @safe pure nothrow @nogc
    {
        while (pos < source.length && isIdentCont(source[pos])) advance();
        auto slice = source[startPos .. pos];
        immutable kw = keywordKind(slice);
        if (kw != T.identifier)
            return token(kw, startPos, cast(uint)(pos - startPos), startLine, startCol, slice);
        return token(T.identifier, startPos, cast(uint)(pos - startPos),
            startLine, startCol, slice);
    }

    Token scanNumber(uint startPos, uint startLine, uint startCol)
        @safe pure nothrow @nogc
    {
        // 0x / 0o / 0b prefixed integers
        if (pos + 1 < source.length && source[pos] == '0'
            && (source[pos + 1] == 'x' || source[pos + 1] == 'X'
                || source[pos + 1] == 'o' || source[pos + 1] == 'O'
                || source[pos + 1] == 'b' || source[pos + 1] == 'B'))
        {
            advance(); advance();
            while (pos < source.length && (isHexDigit(source[pos]) || source[pos] == '_'))
                advance();
            return token(T.numeric_literal, startPos, cast(uint)(pos - startPos),
                startLine, startCol);
        }
        // Decimal int/float with optional `.` / `e±`
        while (pos < source.length && (isDigit(source[pos]) || source[pos] == '_'))
            advance();
        if (pos < source.length && source[pos] == '.')
        {
            advance();
            while (pos < source.length && (isDigit(source[pos]) || source[pos] == '_'))
                advance();
        }
        if (pos < source.length && (source[pos] == 'e' || source[pos] == 'E'))
        {
            advance();
            if (pos < source.length && (source[pos] == '+' || source[pos] == '-'))
                advance();
            while (pos < source.length && isDigit(source[pos])) advance();
        }
        return token(T.numeric_literal, startPos, cast(uint)(pos - startPos),
            startLine, startCol);
    }

    Token scanString(uint startPos, uint startLine, uint startCol, char quote)
        @safe pure nothrow @nogc
    {
        advance();  // opening quote
        while (pos < source.length && source[pos] != quote)
        {
            if (source[pos] == '\\' && pos + 1 < source.length)
            {
                advance(); advance();
                continue;
            }
            if (source[pos] == '\n') break;  // unterminated; let caller flag
            advance();
        }
        if (pos < source.length) advance();  // closing quote
        return token(T.string_literal, startPos, cast(uint)(pos - startPos),
            startLine, startCol);
    }

    Token scanPunctuation(uint startPos, uint startLine, uint startCol, char c)
        @safe pure nothrow @nogc
    {
        T kind = T.syntax_error;
        uint width = 1;
        // Look ahead up to 3 chars to match multi-char operators.
        immutable c1 = pos + 1 < source.length ? source[pos + 1] : '\0';
        immutable c2 = pos + 2 < source.length ? source[pos + 2] : '\0';
        immutable c3 = pos + 3 < source.length ? source[pos + 3] : '\0';

        switch (c)
        {
            case '(': kind = T.open_paren; break;
            case ')': kind = T.close_paren; break;
            case '{': kind = T.open_brace; break;
            case '}': kind = T.close_brace; break;
            case '[': kind = T.open_bracket; break;
            case ']': kind = T.close_bracket; break;
            case ',': kind = T.comma; break;
            case ';': kind = T.semicolon; break;
            case ':': kind = T.colon; break;
            case '~': kind = T.tilde; break;
            case '@': kind = T.at; break;
            case '.':
                if (c1 == '.' && c2 == '.') { kind = T.dot_dot_dot; width = 3; }
                else kind = T.dot;
                break;
            case '?':
                if (c1 == '?' && c2 == '=') { kind = T.question_question_equals; width = 3; }
                else if (c1 == '?') { kind = T.question_question; width = 2; }
                else if (c1 == '.') { kind = T.question_dot; width = 2; }
                else kind = T.question;
                break;
            case '=':
                if (c1 == '=' && c2 == '=') { kind = T.equals_equals_equals; width = 3; }
                else if (c1 == '=') { kind = T.equals_equals; width = 2; }
                else if (c1 == '>') { kind = T.equals_greater_than; width = 2; }
                else kind = T.equals;
                break;
            case '!':
                if (c1 == '=' && c2 == '=') { kind = T.exclamation_equals_equals; width = 3; }
                else if (c1 == '=') { kind = T.exclamation_equals; width = 2; }
                else kind = T.exclamation;
                break;
            case '+':
                if (c1 == '+') { kind = T.plus_plus; width = 2; }
                else if (c1 == '=') { kind = T.plus_equals; width = 2; }
                else kind = T.plus;
                break;
            case '-':
                if (c1 == '-') { kind = T.minus_minus; width = 2; }
                else if (c1 == '=') { kind = T.minus_equals; width = 2; }
                else kind = T.minus;
                break;
            case '*':
                if (c1 == '*' && c2 == '=') { kind = T.asterisk_asterisk_equals; width = 3; }
                else if (c1 == '*') { kind = T.asterisk_asterisk; width = 2; }
                else if (c1 == '=') { kind = T.asterisk_equals; width = 2; }
                else kind = T.asterisk;
                break;
            case '/':
                if (c1 == '=') { kind = T.slash_equals; width = 2; }
                else kind = T.slash;  // regex disambiguation deferred
                break;
            case '%':
                if (c1 == '=') { kind = T.percent_equals; width = 2; }
                else kind = T.percent;
                break;
            case '^':
                if (c1 == '=') { kind = T.caret_equals; width = 2; }
                else kind = T.caret;
                break;
            case '&':
                if (c1 == '&' && c2 == '=') { kind = T.ampersand_ampersand_equals; width = 3; }
                else if (c1 == '&') { kind = T.ampersand_ampersand; width = 2; }
                else if (c1 == '=') { kind = T.ampersand_equals; width = 2; }
                else kind = T.ampersand;
                break;
            case '|':
                if (c1 == '|' && c2 == '=') { kind = T.bar_bar_equals; width = 3; }
                else if (c1 == '|') { kind = T.bar_bar; width = 2; }
                else if (c1 == '=') { kind = T.bar_equals; width = 2; }
                else kind = T.bar;
                break;
            case '<':
                if (c1 == '<' && c2 == '=') { kind = T.less_than_less_than_equals; width = 3; }
                else if (c1 == '<') { kind = T.less_than_less_than; width = 2; }
                else if (c1 == '=') { kind = T.less_than_equals; width = 2; }
                else kind = T.less_than;
                break;
            case '>':
                if (c1 == '>' && c2 == '>' && c3 == '=')
                    { kind = T.greater_than_greater_than_greater_than_equals; width = 4; }
                else if (c1 == '>' && c2 == '>')
                    { kind = T.greater_than_greater_than_greater_than; width = 3; }
                else if (c1 == '>' && c2 == '=')
                    { kind = T.greater_than_greater_than_equals; width = 3; }
                else if (c1 == '>') { kind = T.greater_than_greater_than; width = 2; }
                else if (c1 == '=') { kind = T.greater_than_equals; width = 2; }
                else kind = T.greater_than;
                break;
            default:
                kind = T.syntax_error;
                width = 1;
        }
        foreach (_; 0 .. width) advance();
        return token(kind, startPos, width, startLine, startCol);
    }

    static bool isDigit(char c) @safe pure nothrow @nogc { return c >= '0' && c <= '9'; }
    static bool isHexDigit(char c) @safe pure nothrow @nogc
    {
        return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
    static bool isIdentStart(char c) @safe pure nothrow @nogc
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || c == '_' || c == '$';
    }
    static bool isIdentCont(char c) @safe pure nothrow @nogc
    {
        return isIdentStart(c) || isDigit(c);
    }
}

/// Map an identifier slice to its keyword token if it's a reserved
/// word, else `T.identifier`. Mirrors Bun's Keywords table (only the
/// ES-spec reserved words; TS-only keywords like `type` / `interface`
/// are treated as identifiers and disambiguated by the parser).
T keywordKind(const(char)[] s) @safe pure nothrow @nogc
{
    switch (s)
    {
        case "break":      return T.t_break;
        case "case":       return T.t_case;
        case "catch":      return T.t_catch;
        case "class":      return T.t_class;
        case "const":      return T.t_const;
        case "continue":   return T.t_continue;
        case "debugger":   return T.t_debugger;
        case "default":    return T.t_default;
        case "delete":     return T.t_delete;
        case "do":         return T.t_do;
        case "else":       return T.t_else;
        case "enum":       return T.t_enum;
        case "export":     return T.t_export;
        case "extends":    return T.t_extends;
        case "false":      return T.t_false;
        case "finally":    return T.t_finally;
        case "for":        return T.t_for;
        case "function":   return T.t_function;
        case "if":         return T.t_if;
        case "import":     return T.t_import;
        case "in":         return T.t_in;
        case "instanceof": return T.t_instanceof;
        case "new":        return T.t_new;
        case "null":       return T.t_null;
        case "return":     return T.t_return;
        case "super":      return T.t_super;
        case "switch":     return T.t_switch;
        case "this":       return T.t_this;
        case "throw":      return T.t_throw;
        case "true":       return T.t_true;
        case "try":        return T.t_try;
        case "typeof":     return T.t_typeof;
        case "var":        return T.t_var;
        case "void":       return T.t_void;
        case "while":      return T.t_while;
        case "with":       return T.t_with;
        default:           return T.identifier;
    }
}

unittest
{
    auto l = Lexer("const x = 42;");
    auto a = l.next(); assert(a.kind == T.t_const);
    auto b = l.next(); assert(b.kind == T.identifier && b.text == "x");
    auto c = l.next(); assert(c.kind == T.equals);
    auto d = l.next(); assert(d.kind == T.numeric_literal && d.text == "42");
    auto e = l.next(); assert(e.kind == T.semicolon);
    auto f = l.next(); assert(f.kind == T.eof);
}

unittest
{
    // Hex / oct / bin / numeric separators
    auto l = Lexer("0xff 0o77 0b101 1_000");
    foreach (_; 0 .. 4) assert(l.next().kind == T.numeric_literal);
    assert(l.next().kind == T.eof);
}

unittest
{
    // Strings + escapes
    auto l = Lexer(`"hi" 'world' "with \" quote"`);
    foreach (_; 0 .. 3) assert(l.next().kind == T.string_literal);
}

unittest
{
    // Multi-char operators
    auto l = Lexer("=== !== ??= ??. ?. **= >>>=");
    assert(l.next().kind == T.equals_equals_equals);
    assert(l.next().kind == T.exclamation_equals_equals);
    assert(l.next().kind == T.question_question_equals);
    assert(l.next().kind == T.question_question);  // `??` then `.`
    assert(l.next().kind == T.dot);
    assert(l.next().kind == T.question_dot);
    assert(l.next().kind == T.asterisk_asterisk_equals);
    assert(l.next().kind == T.greater_than_greater_than_greater_than_equals);
}

unittest
{
    // Comments + shebang
    auto l = Lexer("#!/usr/bin/env dun\n// line\nconst /* block */ x");
    assert(l.next().kind == T.hashbang);
    assert(l.next().kind == T.t_const);
    auto id = l.next();
    assert(id.kind == T.identifier && id.text == "x");
}

unittest
{
    // Line/col tracking
    auto l = Lexer("a\n  b");
    auto a = l.next(); assert(a.line == 1 && a.col == 1);
    auto b = l.next(); assert(b.line == 2 && b.col == 3);
}
