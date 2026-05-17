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
// Scope (phases 1 + 2 + 3 landed):
//   * Single-line + block comments + shebang
//   * Identifiers + numeric literals (decimal, hex, oct, bin) +
//     keywords table; permissive Unicode (any byte >= 0x80 is
//     identifier-class -- see `isIdentStart` below)
//   * Single + double quoted strings (no escapes beyond \\ \r \n)
//   * Common punctuation + multi-char operators (`==`, `===`, `=>`,
//     `??`, `?.`, `**`, `**=`, `<<`, `<<=`, `>>`, `>>=`, `>>>`,
//     `>>>=`, `&&`, `||`, `&=`, `|=`, `^=`, `+=`, `-=`, `/=`,
//     `*=`, `%=`, `??=`, `&&=`, `||=`)
//   * Template literals: `` ` `` plain + `${expr}` substitution
//     (head / middle / tail / no-substitution variants)
//   * Regex literals: lexer-internal heuristic on whether the last
//     emitted token allows an expression-start (`return /x/`) vs
//     a divide operator (`a / b`).
//   * BigInt suffix `n` on integer literals.
//   * Public `skipRegexLit` / `charAllowsRegex` /
//     `regexAllowingKeywordEndsAt` helpers so byte-level scanners
//     (currently `dun.ts.strip`) can defer regex disambiguation
//     to the lexer without spinning up a full token stream.
//
// Still deferred:
//   * Full Unicode ID_Start / ID_Continue tables (the permissive
//     >=0x80 acceptance covers every valid identifier in real-world
//     TS files; tightening to the spec ranges only matters when
//     the lexer becomes the *validation* layer instead of the
//     stripping layer.)
//   * JSX/TSX expression-vs-tag mode switching (deferred until
//     strip.d drives the tokenizer for JSX -- currently jsx.d has
//     its own scanner).

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
    private_identifier,    // `#x` class-private fields / methods (ES2022)

    no_substitution_template_literal,
    numeric_literal,
    string_literal,
    big_integer_literal,

    template_head,
    template_middle,
    template_tail,
    regex_literal,

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
    /// Track the kind of the previously emitted token so we can decide
    /// whether `/` is a regex-literal start or a divide operator.
    /// Initialised to a non-expression so a leading `/` parses as regex.
    private T lastKind = T.eof;
    /// Stack of template-literal contexts. When non-empty, `}` after a
    /// `${...}` interpolation re-enters template scanning instead of
    /// emitting a close-brace token.
    private int templateDepth = 0;

    // Brace balance per active template substitution. Without this,
    // `${ {x:1} }` would close the substitution at the first `}` --
    // the lexer can't tell an object literal `}` from a substitution
    // terminator without counting balanced braces inside the
    // expression. Bumped on `{`, dropped on `}` while > 0 inside an
    // active interpolation; only when the count reaches 0 does the
    // `}` resume template scanning.
    enum size_t MAX_TEMPLATE_NESTING = 16;
    private uint[MAX_TEMPLATE_NESTING] templateBraces;

    // `src` is stored into a struct member -- DIP1000 forbids
    // `scope` on it because the slice outlives the function. Caller
    // discipline: the Lexer must not outlive the source buffer.
    this(const(char)[] src) @safe pure nothrow @nogc
    {
        // TIGER_STYLE: positions are `uint`, so a 4-GiB+ source would
        // silently truncate. Fail fast at the boundary instead.
        assert(src.length < uint.max,
            "Lexer source exceeds uint position space (>= 4 GiB)");
        source = src;
    }

    /// Read the next token, advancing the cursor past it.
    Token next() @safe pure nothrow @nogc
    {
        skipTrivia();
        if (pos >= source.length)
            return emit(T.eof, pos, 0);

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

        // Template literal head / no-substitution
        if (c == '`')
            return scanTemplate(startPos, startLine, startCol, /*atBacktick=*/true);

        // `}` while inside a template substitution. If the enclosing
        // expression has unbalanced `{`s (e.g. an object literal),
        // this `}` closes one of those first; only the *outermost* `}`
        // resumes template scanning. See `templateBraces` for the
        // counter rationale.
        if (c == '}' && templateDepth > 0)
        {
            uint* depth = &templateBraces[templateDepth - 1];
            if (*depth > 0) { (*depth)--; /* fall through to scanPunctuation */ }
            else
                return scanTemplate(startPos, startLine, startCol, /*atBacktick=*/false);
        }
        // `{` inside a template substitution bumps the brace counter
        // for the current substitution so the matching `}` doesn't
        // prematurely close it.
        if (c == '{' && templateDepth > 0)
            templateBraces[templateDepth - 1]++;

        // Regex literal: `/` is a regex start when the previous token
        // doesn't allow a division operator (e.g. after `return`,
        // `=`, `,`, `(`, `[`, `;`).
        if (c == '/' && allowsRegex(lastKind))
            return scanRegex(startPos, startLine, startCol);

        // Hashbang at file start
        if (c == '#' && pos == 0 && pos + 1 < source.length && source[pos + 1] == '!')
            return scanLineThenToken(T.hashbang, startPos, startLine, startCol);

        // Private identifier `#name` — only valid inside a class body
        // per spec, but the lexer doesn't track that context. Emit as
        // `T.private_identifier` whenever `#` is followed by an
        // identifier-start byte; downstream consumers can reject if
        // they care about position. Without this every `this.#x`
        // reference in real code lexes as a syntax_error.
        if (c == '#' && pos + 1 < source.length
            && (isIdentStart(source[pos + 1])
                || cast(ubyte) source[pos + 1] >= 0x80))
        {
            advance();  // skip '#'
            while (pos < source.length && isIdentCont(source[pos]))
                advance();
            return emit(T.private_identifier, startPos,
                cast(uint)(pos - startPos), startLine, startCol);
        }

        return scanPunctuation(startPos, startLine, startCol, c);
    }

private:

    // Build a Token, update lastKind, and return. The lastKind feed
    // drives regex-vs-divide disambiguation on the next call.
    Token emit(T kind, uint start, uint length,
        uint line_ = 0, uint col_ = 0,
        const(char)[] text = null) @safe pure nothrow @nogc
    {
        // TIGER_STYLE: every scanner should produce a slice that
        // fits in the source buffer. A miscount in a scan_*
        // routine would otherwise propagate to the caller as an
        // out-of-range token slice.
        assert(start <= source.length && start + length <= source.length,
            "emit: token slice escapes source buffer");
        Token t;
        t.kind = kind;
        t.start = start;
        t.length = length;
        t.line = line_;
        t.col = col_;
        t.text = text.length ? text : source[start .. start + length];
        lastKind = kind;
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
        return emit(kind, startPos, pos - startPos, startLine, startCol);
    }

    Token scanIdent(uint startPos, uint startLine, uint startCol)
        @safe pure nothrow @nogc
    {
        while (pos < source.length && isIdentCont(source[pos])) advance();
        auto slice = source[startPos .. pos];
        immutable kw = keywordKind(slice);
        if (kw != T.identifier)
            return emit(kw, startPos, cast(uint)(pos - startPos), startLine, startCol, slice);
        return emit(T.identifier, startPos, cast(uint)(pos - startPos),
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
            // BigInt suffix `n` (e.g. `0xffn`).
            if (pos < source.length && source[pos] == 'n')
            {
                advance();
                return emit(T.big_integer_literal, startPos, cast(uint)(pos - startPos),
                    startLine, startCol);
            }
            return emit(T.numeric_literal, startPos, cast(uint)(pos - startPos),
                startLine, startCol);
        }
        // Decimal int/float with optional `.` / `e±`
        bool sawFractionOrExp = false;
        while (pos < source.length && (isDigit(source[pos]) || source[pos] == '_'))
            advance();
        if (pos < source.length && source[pos] == '.')
        {
            sawFractionOrExp = true;
            advance();
            while (pos < source.length && (isDigit(source[pos]) || source[pos] == '_'))
                advance();
        }
        if (pos < source.length && (source[pos] == 'e' || source[pos] == 'E'))
        {
            sawFractionOrExp = true;
            advance();
            if (pos < source.length && (source[pos] == '+' || source[pos] == '-'))
                advance();
            while (pos < source.length && isDigit(source[pos])) advance();
        }
        // BigInt suffix only valid on plain decimal integers (no `.`/`e`).
        if (!sawFractionOrExp && pos < source.length && source[pos] == 'n')
        {
            advance();
            return emit(T.big_integer_literal, startPos, cast(uint)(pos - startPos),
                startLine, startCol);
        }
        return emit(T.numeric_literal, startPos, cast(uint)(pos - startPos),
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
        return emit(T.string_literal, startPos, cast(uint)(pos - startPos),
            startLine, startCol);
    }

    /// Template literal scanner. Two entry modes:
    ///   atBacktick=true  -- `pos` points at the opening backtick.
    ///   atBacktick=false -- `pos` points at the `}` closing a
    ///                       `${expr}` interpolation; we resume the
    ///                       enclosing template literal.
    /// Returns one of the template_* tokens. Updates `templateDepth`.
    Token scanTemplate(uint startPos, uint startLine, uint startCol, bool atBacktick)
        @safe pure nothrow @nogc
    {
        advance();  // consume opening `` ` `` or `}`
        while (pos < source.length)
        {
            char c = source[pos];
            if (c == '`')
            {
                advance();
                // Closing backtick. If atBacktick, this is a
                // no-substitution template; otherwise it's the tail
                // of a substitution.
                auto kind = atBacktick ? T.no_substitution_template_literal
                                       : T.template_tail;
                if (!atBacktick && templateDepth > 0) templateDepth--;
                return emit(kind, startPos, cast(uint)(pos - startPos),
                    startLine, startCol);
            }
            if (c == '$' && pos + 1 < source.length && source[pos + 1] == '{')
            {
                advance(); advance();
                // Interpolation start. Caller will see expression
                // tokens next; the `}` that ends the expression
                // returns us to template mode. atBacktick=true means
                // we're opening a NEW substitution; atBacktick=false
                // (template_middle) means we're re-opening one inside
                // an existing template -- the depth was already
                // incremented when we entered the outer template.
                if (atBacktick)
                {
                    if (templateDepth < cast(int) MAX_TEMPLATE_NESTING)
                    {
                        templateBraces[templateDepth] = 0;
                        templateDepth++;
                    }
                }
                else
                {
                    // template_middle case: reset the brace counter for
                    // the substitution we just re-entered.
                    if (templateDepth > 0)
                        templateBraces[templateDepth - 1] = 0;
                }
                auto kind = atBacktick ? T.template_head : T.template_middle;
                return emit(kind, startPos, cast(uint)(pos - startPos),
                    startLine, startCol);
            }
            if (c == '\\' && pos + 1 < source.length)
            {
                advance(); advance();
                continue;
            }
            advance();
        }
        // Unterminated -- return what we have as a tail; parser flags.
        return emit(atBacktick ? T.no_substitution_template_literal : T.template_tail,
            startPos, cast(uint)(pos - startPos), startLine, startCol);
    }

    /// Regex literal scanner. Caller has already determined the `/`
    /// at `pos` starts a regex (via `allowsRegex(lastKind)`). Walks
    /// the body (with `\` escapes + character classes `[...]` where
    /// `/` is literal) plus any trailing flag chars.
    Token scanRegex(uint startPos, uint startLine, uint startCol)
        @safe pure nothrow @nogc
    {
        advance();  // opening /
        bool inClass = false;
        while (pos < source.length)
        {
            char c = source[pos];
            if (c == '\n') break;  // unterminated
            if (c == '\\' && pos + 1 < source.length)
            {
                advance(); advance();
                continue;
            }
            if (c == '[') { inClass = true; advance(); continue; }
            if (c == ']') { inClass = false; advance(); continue; }
            if (c == '/' && !inClass) { advance(); break; }
            advance();
        }
        // Trailing flags (g, i, m, s, u, v, y, d)
        while (pos < source.length && isIdentCont(source[pos])) advance();
        return emit(T.regex_literal, startPos, cast(uint)(pos - startPos),
            startLine, startCol);
    }

    /// Whether the previous token's kind allows a regex literal here.
    /// A regex starts after operators / keywords that introduce a new
    /// expression; a divide is only legal after a value-producing
    /// token (literal, identifier, `)`, `]`, `++`, `--`).
    static bool allowsRegex(T prev) @safe pure nothrow @nogc
    {
        switch (prev)
        {
            case T.identifier:
            case T.numeric_literal:
            case T.big_integer_literal:
            case T.string_literal:
            case T.no_substitution_template_literal:
            case T.template_tail:
            case T.close_paren:
            case T.close_bracket:
            case T.plus_plus:
            case T.minus_minus:
            case T.t_this:
            case T.t_super:
            case T.t_null:
            case T.t_true:
            case T.t_false:
                return false;
            default:
                return true;
        }
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
        return emit(kind, startPos, width, startLine, startCol);
    }

    static bool isDigit(char c) @safe pure nothrow @nogc { return c >= '0' && c <= '9'; }
    static bool isHexDigit(char c) @safe pure nothrow @nogc
    {
        return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
    // Identifier classification. We don't ship the full Unicode
    // ID_Start / ID_Continue tables (~3000 ranges, 60 KB); instead we
    // accept any byte >= 0x80 as part of an identifier. That covers
    // every valid ID_Start/ID_Continue code point in UTF-8 (their
    // leading bytes are all >= 0xC2) plus all UTF-8 continuation
    // bytes. The trade-off: we'd also accept some non-identifier
    // code points (e.g. emoji). For a strip-mode tokenizer that's
    // fine -- the engine is the final arbiter of identifier validity.
    static bool isIdentStart(char c) @safe pure nothrow @nogc
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || c == '_' || c == '$' || cast(ubyte) c >= 0x80;
    }
    static bool isIdentCont(char c) @safe pure nothrow @nogc
    {
        return isIdentStart(c) || isDigit(c);
    }
}

// ---------------------------------------------------------------------------
// Public token-stream helpers. `tokenize` allocates so its body lives
// in a nested function that escapes the module-level `@nogc` colon.
// ---------------------------------------------------------------------------

/// Whether the source contains any `syntax_error` tokens. Useful for
/// corpus-validation tests: a clean file should never hit one. The
/// lexer treats unknown punctuation as `T.syntax_error` (single byte
/// width) so an offending position can be located by walking the stream.
// `src` isn't `scope` because the inner `Lexer` stores the slice in a
// non-scope member (see `Lexer.this`). DIP1000 propagation would
// require the whole Lexer to be `scope`, which complicates the API
// without observable gain for the strip-time short-lived usage.
bool hasSyntaxError(const(char)[] src) @safe pure nothrow @nogc
{
    auto lx = Lexer(src);
    for (;;)
    {
        auto tk = lx.next();
        if (tk.kind == T.syntax_error) return true;
        if (tk.kind == T.eof) return false;
    }
}

/// Skip past a regex literal starting at `buf[pos]` (which the caller
/// has already determined to be `/` in a regex-allowed position).
/// Returns the byte index just past the closing `/` and flag chars.
/// Lifts the same body+class+flag logic the lexer's `scanRegex` uses,
/// so callers don't have to spin up a full `Lexer` for one-off skips
/// (e.g. `strip.d` walking past a regex on its main scan).
///
/// Same flag set as ECMA-262 + V8: `g i m s u v y d`. Any
/// `isIdentCont` byte at the tail is consumed -- the caller is
/// presumed to have validated the slash already.
size_t skipRegexLit(const(char)[] buf, size_t pos) @safe pure nothrow @nogc
{
    assert(pos < buf.length && buf[pos] == '/',
        "skipRegexLit called without a `/` at pos");
    pos++;  // opening /
    bool inClass = false;
    while (pos < buf.length)
    {
        immutable c = buf[pos];
        if (c == '\n') break;  // unterminated -- bail
        if (c == '\\' && pos + 1 < buf.length)
        {
            pos += 2;
            continue;
        }
        if (c == '[') { inClass = true; pos++; continue; }
        if (c == ']') { inClass = false; pos++; continue; }
        if (c == '/' && !inClass) { pos++; break; }
        pos++;
    }
    // Trailing flags. Use Lexer.isIdentCont so the set stays in sync
    // with the lexer's identifier classification.
    while (pos < buf.length && Lexer.isIdentCont(buf[pos])) pos++;
    return pos;
}

/// Whether a `/` at `prevChar`'s following position starts a regex
/// literal or a divide. The caller passes the previous non-whitespace
/// byte. Mirrors `Lexer.allowsRegex` but operates on raw chars so
/// strip-mode callers don't need a token stream.
///
/// Returns true (regex) when prev is one of:
///   - structural / operator: `(` `,` `;` `[` `{` `}` `:` `?` `=`
///     `+` `-` `*` `/` `%` `&` `|` `^` `~` `!` `<` `>`
///   - end-of-line (newline) or buffer start
/// Returns false (divide) when prev is identifier-continuing,
/// `)`, `]`, or backtick (template_tail-equivalent).
///
/// Caller should special-case identifier-keyword-then-slash (e.g.
/// `return /x/`) via `regexAllowingKeywordEndsAt` before calling this:
/// after `return` the previous byte is `n`, an ident-cont, which
/// would otherwise say divide. See the strip.d main-loop wiring.
bool charAllowsRegex(char prev) @safe pure nothrow @nogc
{
    if (Lexer.isIdentCont(prev)) return false;  // ident / digit / `_`
    switch (prev)
    {
        case ')':
        case ']':
        case '`':
            return false;
        default:
            return true;
    }
}

/// If `buf[..endExclusive]` ends in a regex-allowing keyword (`return`,
/// `typeof`, `void`, `delete`, `throw`, `in`, `instanceof`, `new`,
/// `yield`, `await`, `do`, `else`), returns the byte offset where that
/// keyword starts; otherwise returns `endExclusive` (caller should
/// fall through to `charAllowsRegex`). The check requires the byte
/// just before the keyword to be a non-ident byte (or buffer start) so
/// `myreturn` doesn't match `return`.
size_t regexAllowingKeywordEndsAt(const(char)[] buf, size_t endExclusive)
    @safe pure nothrow @nogc
{
    if (endExclusive == 0) return endExclusive;
    // Walk back through ident-continuing bytes to find the word start.
    size_t start = endExclusive;
    while (start > 0 && Lexer.isIdentCont(buf[start - 1])) start--;
    if (start == endExclusive) return endExclusive;
    const s = buf[start .. endExclusive];
    // Same set as ECMA-262 RegularExpressionLiteral lookahead rules
    // plus the common JS expression-start keywords.
    switch (s)
    {
        case "return":
        case "typeof":
        case "void":
        case "delete":
        case "throw":
        case "in":
        case "instanceof":
        case "new":
        case "yield":
        case "await":
        case "do":
        case "else":
        case "case":
            return start;
        default:
            return endExclusive;
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

unittest
{
    // Template literals: no-substitution
    auto l = Lexer("`hello world`");
    auto t = l.next();
    assert(t.kind == T.no_substitution_template_literal);
    assert(t.text == "`hello world`");
    assert(l.next().kind == T.eof);
}

unittest
{
    // Template literals: substitution head + tail
    auto l = Lexer("`a${1}b`");
    auto a = l.next(); assert(a.kind == T.template_head && a.text == "`a${");
    auto b = l.next(); assert(b.kind == T.numeric_literal && b.text == "1");
    auto c = l.next(); assert(c.kind == T.template_tail && c.text == "}b`");
    assert(l.next().kind == T.eof);
}

unittest
{
    // Template literals: middle (two interpolations)
    auto l = Lexer("`a${1}b${2}c`");
    assert(l.next().kind == T.template_head);
    assert(l.next().kind == T.numeric_literal);
    auto m = l.next(); assert(m.kind == T.template_middle);
    assert(l.next().kind == T.numeric_literal);
    assert(l.next().kind == T.template_tail);
}

unittest
{
    // BigInt literals
    auto l = Lexer("42n 0xffn");
    auto a = l.next(); assert(a.kind == T.big_integer_literal && a.text == "42n");
    auto b = l.next(); assert(b.kind == T.big_integer_literal && b.text == "0xffn");
}

unittest
{
    // Regex literal vs divide -- regex after `=`
    auto l = Lexer("const x = /foo/g; const y = a / b;");
    foreach (_; 0 .. 3) l.next();                  // const x =
    auto r = l.next();
    assert(r.kind == T.regex_literal && r.text == "/foo/g");
    // After the regex, `;` then identifiers, then `/` should be slash.
    foreach (_; 0 .. 5) l.next();                  // ; const y = a
    auto d = l.next();
    assert(d.kind == T.slash);
}

unittest
{
    // Regex with character class containing `/`
    auto l = Lexer("return /[a/b]/i;");
    assert(l.next().kind == T.t_return);
    auto r = l.next();
    assert(r.kind == T.regex_literal && r.text == "/[a/b]/i");
}

unittest
{
    // Non-ASCII identifier (Greek `pi`). Permissive Unicode -- accepts
    // any byte >= 0x80 as identifier-class. Catches `let π = 3.14;` /
    // `const λ = x => x;` patterns that real-world libraries use.
    immutable src = "let \xCF\x80 = 3.14;";  // π is U+03C0 = CF 80
    auto l = Lexer(src);
    assert(l.next().kind == T.identifier);   // let -> identifier? no, it's not reserved
    auto id = l.next();
    assert(id.kind == T.identifier);
    assert(id.text == "\xCF\x80");
    assert(l.next().kind == T.equals);
    assert(l.next().kind == T.numeric_literal);
    assert(l.next().kind == T.semicolon);
    assert(l.next().kind == T.eof);
}

unittest
{
    // Public hasSyntaxError on clean source.
    assert(!hasSyntaxError("const x = 1;"));
    // ... and on a source with a stray byte that doesn't match any token.
    assert(hasSyntaxError("let \x01 = 1;"));  // control byte
}

unittest
{
    // skipRegexLit + charAllowsRegex.
    assert(charAllowsRegex('='));
    assert(charAllowsRegex(','));
    assert(charAllowsRegex('('));
    assert(charAllowsRegex(' '));   // whitespace -> regex
    assert(charAllowsRegex('\n'));
    assert(!charAllowsRegex(')'));
    assert(!charAllowsRegex(']'));
    assert(!charAllowsRegex('a'));
    assert(!charAllowsRegex('5'));

    // skipRegexLit walks to end of the slash + flags.
    auto src1 = "/abc/g xyz";
    auto end1 = skipRegexLit(src1, 0);
    assert(end1 == 6 && src1[0 .. end1] == "/abc/g");

    // Regex with `/` inside a `[...]` class -- class context keeps
    // the inner slash literal.
    auto src2 = "/[a/b]/i;";
    auto end2 = skipRegexLit(src2, 0);
    assert(end2 == 8 && src2[0 .. end2] == "/[a/b]/i");

    // Regex with escape sequences.
    auto src3 = "/\\d+\\s*/g";
    auto end3 = skipRegexLit(src3, 0);
    assert(end3 == src3.length);

    // Keyword-aware regex disambiguation. `return /` is regex; `foo /`
    // (after a non-keyword identifier) is divide.
    immutable src4 = "return /x/";
    auto kw = regexAllowingKeywordEndsAt(src4, 6);  // end of "return"
    assert(kw == 0, "expected keyword start at 0");

    immutable src5 = "foo /x";
    auto kw2 = regexAllowingKeywordEndsAt(src5, 3);  // end of "foo"
    assert(kw2 == 3, "non-keyword identifier should not match");

    // Word boundary: `myreturn` should not match `return`.
    immutable src6 = "myreturn";
    auto kw3 = regexAllowingKeywordEndsAt(src6, 8);
    assert(kw3 == 8, "suffix of keyword must not match");
}

// ─────────── Expanded coverage (ported from Bun's lexer_test.zig) ──────────
//
// Bun's lexer_test.zig has ~80 test functions; we don't need exhaustive
// parity here, but the gaps below were what the strip.d fixtures kept
// stumbling on. Each unittest is ≤30 lines so they're greppable and the
// failures point at one tokenizer state.

unittest
{
    // Numeric forms strip.d relies on: exponent + decimal + BigInt +
    // leading-dot. BigInt literals are emitted as `big_integer_literal`,
    // not `numeric_literal`.
    auto l = Lexer("3.14e10 .5 1e-3 99999n 0xDEADn 0b101n");
    assert(l.next().kind == T.numeric_literal);     // 3.14e10
    assert(l.next().kind == T.numeric_literal);     // .5
    assert(l.next().kind == T.numeric_literal);     // 1e-3
    assert(l.next().kind == T.big_integer_literal); // 99999n
    assert(l.next().kind == T.big_integer_literal); // 0xDEADn
    assert(l.next().kind == T.big_integer_literal); // 0b101n
    assert(l.next().kind == T.eof);
}

unittest
{
    // Strings with every escape category (Bun uses these in stripper).
    auto l = Lexer(`"\n" "\t" "\r" "\\\\" "\"" "ÿ" '\x41' '\0'`);
    foreach (_; 0 .. 8) assert(l.next().kind == T.string_literal);
}

unittest
{
    // Template with NESTED braces inside ${...} — depth tracking must
    // not bail out on the first `}`.
    auto l = Lexer("`a${ {x:1, y:2} }b`");
    assert(l.next().kind == T.template_head);   // `a${
    assert(l.next().kind == T.open_brace);      // {
    assert(l.next().kind == T.identifier);      // x
    assert(l.next().kind == T.colon);
    assert(l.next().kind == T.numeric_literal); // 1
    assert(l.next().kind == T.comma);
    assert(l.next().kind == T.identifier);      // y
    assert(l.next().kind == T.colon);
    assert(l.next().kind == T.numeric_literal); // 2
    assert(l.next().kind == T.close_brace);     // }
    assert(l.next().kind == T.template_tail);   // }b`
}

unittest
{
    // Template inside template (recursive interpolation).
    auto l = Lexer("`a${`x${1}y`}b`");
    assert(l.next().kind == T.template_head);
    assert(l.next().kind == T.template_head);
    assert(l.next().kind == T.numeric_literal);
    assert(l.next().kind == T.template_tail);
    assert(l.next().kind == T.template_tail);
}

unittest
{
    // CRLF line tracking: line counter advances exactly once per \r\n.
    auto l = Lexer("a\r\nb\r\nc");
    auto a = l.next(); assert(a.line == 1 && a.col == 1);
    auto b = l.next(); assert(b.line == 2 && b.col == 1);
    auto c = l.next(); assert(c.line == 3 && c.col == 1);
}

unittest
{
    // Block comment spanning multiple lines bumps line counter.
    auto l = Lexer("a /* x\ny\nz */ b");
    auto a = l.next(); assert(a.kind == T.identifier && a.line == 1);
    auto b = l.next(); assert(b.kind == T.identifier && b.text == "b");
    assert(b.line == 3, "comment with 2 newlines should leave b on line 3");
}

unittest
{
    // Verify every multi-char operator round-trips as a single token.
    // Sources are wrapped in `(...)` so the operator never sits at a
    // regex-allowing position; otherwise `*/` etc. would be lexed as
    // a regex.
    static immutable string[] forms = [
        "===", "!==", "??=", "??", "?.", "**=", ">>>=",
        ">>>", ">>=", "<<=", "<<", ">>",
        "==", "!=", "<=", ">=", "&&", "||", "**",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
        "&&=", "||=",
        "++", "--", "=>", "..."
    ];
    // Pre-built input strings — `~` concat would allocate inside the
    // module's `@nogc` colon. `forms` and `sources` line up.
    static immutable string[] sources = [
        "a === b;", "a !== b;", "a ??= b;", "a ?? b;", "a ?. b;",
        "a **= b;", "a >>>= b;",
        "a >>> b;", "a >>= b;", "a <<= b;", "a << b;", "a >> b;",
        "a == b;", "a != b;", "a <= b;", "a >= b;", "a && b;",
        "a || b;", "a ** b;",
        "a += b;", "a -= b;", "a *= b;", "a /= b;", "a %= b;",
        "a &= b;", "a |= b;", "a ^= b;",
        "a &&= b;", "a ||= b;",
        "a++;", "a--;", "() => b;", "[...a];"
    ];
    static assert(forms.length == sources.length,
        "forms/sources arrays must line up");
    foreach (i, op; forms)
    {
        auto l = Lexer(sources[i]);
        // Walk until we find the operator token (skip the leading
        // expression tokens — `a`, `(`, `[`, etc.).
        while (true)
        {
            auto t = l.next();
            if (t.kind == T.eof) { assert(false, "operator missing"); break; }
            if (t.text == op) break;
        }
    }
}

unittest
{
    // Position tracking: Token.start + .length cover the original byte
    // span exactly. strip.d depends on this for whitespace-blanking.
    immutable src = "const xyz = 'abc';";
    auto l = Lexer(src);
    auto t1 = l.next();  // const
    assert(t1.kind == T.t_const);
    assert(src[t1.start .. t1.start + t1.length] == "const");
    auto t2 = l.next();  // xyz
    assert(t2.kind == T.identifier);
    assert(src[t2.start .. t2.start + t2.length] == "xyz");
    auto t3 = l.next();  // =
    assert(src[t3.start .. t3.start + t3.length] == "=");
    auto t4 = l.next();  // 'abc'
    assert(t4.kind == T.string_literal);
    assert(src[t4.start .. t4.start + t4.length] == "'abc'");
}

unittest
{
    // Reserved-word table covers the full ES2023+ set used by strip.d.
    // Bun's lexer_tables.zig is the source; if a new keyword lands
    // upstream, strip.d's heuristics ride the same enum.
    immutable kws = "var let const if else for while do break continue "
                  ~ "return function class extends super this new yield "
                  ~ "await async typeof instanceof in of try catch finally "
                  ~ "throw switch case default delete void null true false";
    auto l = Lexer(kws);
    while (true)
    {
        auto t = l.next();
        if (t.kind == T.eof) break;
        // Every word above is a recognised keyword OR identifier — never
        // a syntax error.
        assert(t.kind != T.syntax_error, "unexpected syntax error");
    }
}

unittest
{
    // Regex disambiguation after the reserved-word set. Contextual
    // keywords (yield, await, of) lex as `T.identifier` here -- after
    // an identifier the lexer treats `/` as divide. strip.d compensates
    // via `regexAllowingKeywordEndsAt` which inspects raw bytes.
    static immutable string[] tail = ["return /x/",
        "void /x/", "typeof /x/", "delete /x/", "throw /x/",
        "case /x/", "in /x/", "instanceof /x/", "new /x/"];
    foreach (s; tail)
    {
        auto l = Lexer(s);
        l.next();                  // keyword
        auto r = l.next();
        assert(r.kind == T.regex_literal,
            "regex after reserved-word should lex as regex");
    }
}

unittest
{
    // Regex with sticky / unicode-sets / hasIndices flag combos.
    auto l = Lexer("/abc/dgimsuvy ; /x/v ; /y/d");
    assert(l.next().kind == T.regex_literal);
    assert(l.next().kind == T.semicolon);
    assert(l.next().kind == T.regex_literal);
    assert(l.next().kind == T.semicolon);
    assert(l.next().kind == T.regex_literal);
}

unittest
{
    // Multi-byte identifier with combining marks (UTF-8 surrogate pair).
    // π + acute = U+03C0 U+0301 → cf 80 cc 81. The lexer's >=0x80
    // policy accepts both bytes as identifier-class. (`let` is a
    // contextual keyword in JS, lexed as `T.identifier`, not `T.t_let`.)
    auto l = Lexer("let \xCF\x80\xCC\x81 = 1");
    assert(l.next().kind == T.identifier);   // let
    auto t = l.next();
    assert(t.kind == T.identifier);
    assert(t.text == "\xCF\x80\xCC\x81");
    assert(l.next().kind == T.equals);
    assert(l.next().kind == T.numeric_literal);
}

unittest
{
    // Unterminated string -> syntax error token, not infinite loop.
    auto l = Lexer(`"oops`);
    auto t = l.next();
    assert(t.kind == T.syntax_error
        || t.kind == T.string_literal,  // some implementations terminate at EOF
        "unterminated string must not infinite-loop");
}

unittest
{
    // Unterminated block comment -> ditto.
    auto l = Lexer("/* never closed");
    while (true)
    {
        auto t = l.next();
        if (t.kind == T.eof || t.kind == T.syntax_error) break;
    }
}

// (Corpus-walk lives in dun.ts.parser package.d — it uses CTFE
// `import("…")` which needs to escape this module's `@nogc pure`
// defaults.)
