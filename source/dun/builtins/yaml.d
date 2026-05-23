/++
 + YAML parser + emitter (subset: block + flow style, no anchors/tags/
 + directives, no `node:yaml`-style document streams). Targets the
 + ~80% of YAML used in config files (CI manifests, k8s, package.yaml,
 + docker-compose). Mirrors Bun's `Bun.YAML.parse` / `.stringify` API
 + shape; export the same shape as `dun:yaml` so scripts can do
 + `import { parse, stringify } from "dun:yaml"`.
 +
 + Scope (what's IN):
 +   - Block mappings (`key: value` with indentation)
 +   - Block sequences (`- item` with indentation)
 +   - Flow mappings (`{a: 1, b: 2}`) and flow sequences (`[1, 2]`)
 +   - Scalars: int, float, bool (true/false/yes/no), null (~ or null), string
 +   - String quoting: bare, single-quoted, double-quoted (with escapes)
 +   - Comments (`#` to end-of-line)
 +   - Multi-line strings: `|` (literal) and `>` (folded), with
 +     chomping indicators (`-` / `+`)
 +   - Empty lines + document separator (`---`)
 +
 + Scope (what's OUT — throws or treated as plain string):
 +   - Anchors / aliases / tags (`&`, `*`, `!`)
 +   - YAML directives (`%YAML`, `%TAG`)
 +   - Multiple documents in one stream (only the first parses)
 +   - Complex keys (only scalar keys supported)
 +   - Binary base64 blocks
 +/
module dun.builtins.yaml;


/++
 + `@trusted policy`: YAML parser (subset compatible with
 + js-yaml). Every `@trusted` is one of:
 +   1. `Appender!(char[])` + `cast(string)` for building output —
 +      pure D parser, no FFI.
 +   2. `cast(DunState*) ctx` via `ctxState(ctx)` in callbacks.
 +/
import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState, ctxState;
import dun.platform.arena : Appender;

void registerYamlModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in registerYamlModule");
    auto obj = engine.newObject();
    engine.setProperty(obj, "parse", engine.newFunction(&jsYamlParse, "parse", 1));
    engine.setProperty(obj, "stringify", engine.newFunction(&jsYamlStringify, "stringify", 1));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_yaml__", obj);
    engine.freeValue(global);
}

// ── JS entry points ───────────────────────────────────────────────────

private JSHandle jsYamlParse(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in jsYamlParse");
    auto engine = state.engine;

    if (args.length < 1 || !engine.isString(args[0]))
        return engine.throwTypeError("yaml.parse(s) requires a string");

    auto src = engine.extractString(args[0]);
    try
    {
        auto parser = Parser(src);
        auto node = parser.parseDocument();
        return nodeToJs(engine, node);
    }
    catch (Exception e)
    {
        return engine.throwTypeError("yaml.parse: " ~ e.msg);
    }
}

private JSHandle jsYamlStringify(void* ctx, JSHandle thisVal, scope JSHandle[] args) @trusted
{
    auto state = ctxState(ctx);
    assert(state.engine !is null, "Null engine in jsYamlStringify");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.newString("null\n");

    Appender!string out_;
    out_.reserve(STRINGIFY_RESERVE);
    emitValue(engine, args[0], 0, out_);
    return engine.newString(out_.data);
}

// ── Constants (no magic numbers) ──────────────────────────────────────

private enum : size_t {
    STRINGIFY_RESERVE = 256,
}

// ── Node model (D-side AST) ───────────────────────────────────────────

private enum NodeKind : ubyte { scalar, sequence, mapping, nullVal }
private enum ScalarType : ubyte { str, intVal, floatVal, boolVal, nullVal }

private struct Node
{
    NodeKind kind;
    ScalarType scalarType;
    string scalarStr;       // string / int / float text
    bool boolVal;
    Node[] seq;             // for sequence
    string[] mapKeys;       // for mapping (ordered)
    Node[] mapVals;         //   parallel to mapKeys
}

// ── Parser ────────────────────────────────────────────────────────────

private struct Parser
{
    string src;
    size_t pos;

    Node parseDocument()
    {
        skipBlankAndComments();
        if (pos < src.length && src[pos .. $].length >= 3
            && src[pos .. pos + 3] == "---")
        {
            pos += 3;
            skipToNextLine();
            skipBlankAndComments();
        }
        if (pos >= src.length)
            return Node(NodeKind.nullVal);
        return parseNode(0);
    }

    // Parse a node starting at column `minIndent`. Decides block vs flow
    // vs scalar based on the next non-space char. `pos` must be at the
    // start of a line on entry.
    Node parseNode(size_t minIndent)
    {
        size_t indent = countIndent();
        if (indent < minIndent)
            return Node(NodeKind.nullVal);

        // Peek at the first non-space char without consuming indent —
        // parseBlockSeq / parseBlockMap need pos at line-start so they
        // can re-count indent on every iteration.
        size_t peek = pos + indent;
        if (peek >= src.length || src[peek] == '\n' || src[peek] == '#')
        {
            skipToNextLine();
            return Node(NodeKind.nullVal);
        }

        // Block sequence starts with `- ` at exactly `indent`. Both
        // parseBlockSeq and parseBlockMap re-count indent on every
        // iteration; pos must be at line-start.
        if (src[peek] == '-' && peek + 1 < src.length
            && (src[peek + 1] == ' ' || src[peek + 1] == '\n'))
            return parseBlockSeq(indent);

        // Flow style? Skip past indent to peek.
        if (src[peek] == '[')
        {
            pos += indent;
            return parseFlowSeq();
        }
        if (src[peek] == '{')
        {
            pos += indent;
            return parseFlowMap();
        }

        // Save pos for parseBlockMap (which expects line-start).
        size_t lineStart = pos;
        pos += indent;
        if (lineHasMapColon())
        {
            pos = lineStart;
            return parseBlockMap(indent);
        }

        // Plain scalar (rest of line)
        return parseScalarLine();
    }

    Node parseBlockSeq(size_t indent)
    {
        Node n;
        n.kind = NodeKind.sequence;
        while (pos < src.length)
        {
            size_t lineIndent = countIndentAt(pos);
            if (lineIndent < indent) break;
            if (lineIndent != indent || pos + lineIndent >= src.length
                || src[pos + lineIndent] != '-') break;
            pos += lineIndent + 1; // past '-'
            // Optional space after '-'
            if (pos < src.length && src[pos] == ' ') pos++;
            if (pos < src.length && src[pos] == '\n')
            {
                // Nested block on next line
                pos++;
                skipBlankAndComments();
                n.seq ~= parseNode(indent + 1);
            }
            else if (pos < src.length && src[pos] == '\n')
                n.seq ~= Node(NodeKind.nullVal);
            else
            {
                // Inline element on the same line as the '-'
                // It might be a mapping (`- key: val`) or scalar.
                auto inlineIndent = indent + 2;  // assumed `- ` then content
                if (lineHasMapColon())
                    n.seq ~= parseBlockMap(inlineIndent);
                else
                    n.seq ~= parseScalarLine();
            }
            skipBlankAndComments();
        }
        return n;
    }

    Node parseBlockMap(size_t indent)
    {
        Node n;
        n.kind = NodeKind.mapping;
        while (pos < src.length)
        {
            size_t lineIndent = countIndentAt(pos);
            if (lineIndent < indent) break;
            if (lineIndent != indent) break;
            pos += lineIndent;
            if (pos >= src.length || src[pos] == '\n' || src[pos] == '#')
            { skipToNextLine(); continue; }

            string key = parseKey();
            if (pos >= src.length || src[pos] != ':')
            {
                // No colon — bail (caller will treat as scalar)
                break;
            }
            pos++; // past ':'
            // skip spaces but not newline
            while (pos < src.length && src[pos] == ' ') pos++;

            Node val;
            if (pos < src.length && (src[pos] == '|' || src[pos] == '>'))
            {
                val = parseBlockScalar(indent + 1);
            }
            else if (pos < src.length && src[pos] == '\n')
            {
                // Nested value on next line(s)
                pos++; // past newline
                skipBlankAndComments();
                size_t childIndent = countIndentAt(pos);
                if (childIndent > indent && pos < src.length)
                    val = parseNode(childIndent);
                else
                    val = Node(NodeKind.nullVal);
            }
            else if (pos < src.length && src[pos] == '[')
            {
                val = parseFlowSeq();
                skipToNextLine();
            }
            else if (pos < src.length && src[pos] == '{')
            {
                val = parseFlowMap();
                skipToNextLine();
            }
            else
            {
                val = parseScalarLine();
            }
            n.mapKeys ~= key;
            n.mapVals ~= val;
            skipBlankAndComments();
        }
        return n;
    }

    Node parseFlowSeq()
    {
        Node n;
        n.kind = NodeKind.sequence;
        assert(src[pos] == '[');
        pos++; // past '['
        skipFlowWhitespace();
        while (pos < src.length && src[pos] != ']')
        {
            n.seq ~= parseFlowNode();
            skipFlowWhitespace();
            if (pos < src.length && src[pos] == ',')
            { pos++; skipFlowWhitespace(); }
        }
        if (pos < src.length && src[pos] == ']') pos++;
        return n;
    }

    Node parseFlowMap()
    {
        Node n;
        n.kind = NodeKind.mapping;
        assert(src[pos] == '{');
        pos++; // past '{'
        skipFlowWhitespace();
        while (pos < src.length && src[pos] != '}')
        {
            string k = parseFlowKey();
            skipFlowWhitespace();
            if (pos < src.length && src[pos] == ':')
            {
                pos++; skipFlowWhitespace();
                n.mapKeys ~= k;
                n.mapVals ~= parseFlowNode();
            }
            else
            {
                n.mapKeys ~= k;
                n.mapVals ~= Node(NodeKind.nullVal);
            }
            skipFlowWhitespace();
            if (pos < src.length && src[pos] == ',')
            { pos++; skipFlowWhitespace(); }
        }
        if (pos < src.length && src[pos] == '}') pos++;
        return n;
    }

    Node parseFlowNode()
    {
        if (pos >= src.length) return Node(NodeKind.nullVal);
        if (src[pos] == '[') return parseFlowSeq();
        if (src[pos] == '{') return parseFlowMap();
        return parseFlowScalar();
    }

    string parseFlowKey()
    {
        return parseFlowScalarRaw(":,]}");
    }

    Node parseFlowScalar()
    {
        string s = parseFlowScalarRaw(",]}");
        return classifyScalar(s);
    }

    // Read until any char in `stopChars` (top level of flow context).
    // Strips trailing whitespace before the stop char.
    string parseFlowScalarRaw(string stopChars)
    {
        if (pos < src.length && (src[pos] == '"' || src[pos] == '\''))
            return parseQuotedString();
        size_t start = pos;
        while (pos < src.length)
        {
            char c = src[pos];
            bool isStop = false;
            foreach (sc; stopChars) if (c == sc) { isStop = true; break; }
            if (isStop || c == '\n') break;
            pos++;
        }
        // strip trailing whitespace
        size_t end = pos;
        while (end > start && (src[end - 1] == ' ' || src[end - 1] == '\t'))
            end--;
        return src[start .. end];
    }

    Node parseScalarLine()
    {
        if (pos < src.length && (src[pos] == '"' || src[pos] == '\''))
        {
            string s = parseQuotedString();
            // skip rest of line (incl. trailing whitespace + newline)
            skipToNextLine();
            return Node(NodeKind.scalar, ScalarType.str, s);
        }
        size_t start = pos;
        while (pos < src.length && src[pos] != '\n' && src[pos] != '#')
            pos++;
        size_t end = pos;
        while (end > start && (src[end - 1] == ' ' || src[end - 1] == '\t'))
            end--;
        string raw = src[start .. end];
        skipToNextLine();
        return classifyScalar(raw);
    }

    Node parseBlockScalar(size_t baseIndent)
    {
        // `|` literal — preserve newlines; `>` folded — newlines→spaces.
        // Chomping: `-` strip trailing, `+` keep all, default = single \n.
        char indicator = src[pos]; // | or >
        pos++;
        char chomp = ' ';
        if (pos < src.length && (src[pos] == '-' || src[pos] == '+'))
        { chomp = src[pos]; pos++; }
        // Optional explicit indent indicator (digit) — ignored, we infer.
        while (pos < src.length && src[pos] >= '0' && src[pos] <= '9') pos++;
        skipToNextLine();

        Appender!string out_;
        size_t blockIndent = 0;
        bool sawAnyLine = false;
        while (pos < src.length)
        {
            size_t lineStart = pos;
            size_t lineIndent = countIndentAt(pos);
            // empty line → still part of block (will be normalised below)
            if (pos + lineIndent >= src.length || src[pos + lineIndent] == '\n')
            {
                out_.put('\n');
                skipToNextLine();
                continue;
            }
            if (!sawAnyLine)
            {
                blockIndent = lineIndent;
                sawAnyLine = true;
            }
            if (lineIndent < blockIndent || lineIndent < baseIndent) break;
            pos += blockIndent;
            size_t contentStart = pos;
            while (pos < src.length && src[pos] != '\n') pos++;
            out_.put(src[contentStart .. pos]);
            if (indicator == '|') out_.put('\n');
            else                   out_.put(' '); // folded
            if (pos < src.length) pos++; // past newline
        }
        string s = out_.data;
        // Apply chomping to trailing newlines
        if (chomp == '-')
        {
            while (s.length > 0 && (s[$ - 1] == '\n' || s[$ - 1] == ' '))
                s = s[0 .. $ - 1];
        }
        else if (chomp == '+')
        {
            // keep all trailing newlines
        }
        else
        {
            // default: single trailing newline
            while (s.length > 1 && s[$ - 1] == '\n' && s[$ - 2] == '\n')
                s = s[0 .. $ - 1];
            if (s.length > 0 && s[$ - 1] == ' ') s = s[0 .. $ - 1] ~ "\n";
            if (s.length > 0 && s[$ - 1] != '\n') s ~= "\n";
        }
        return Node(NodeKind.scalar, ScalarType.str, s);
    }

    string parseKey()
    {
        if (pos < src.length && (src[pos] == '"' || src[pos] == '\''))
            return parseQuotedString();
        size_t start = pos;
        while (pos < src.length && src[pos] != ':' && src[pos] != '\n')
            pos++;
        size_t end = pos;
        while (end > start && (src[end - 1] == ' ' || src[end - 1] == '\t'))
            end--;
        return src[start .. end];
    }

    string parseQuotedString()
    {
        char q = src[pos];
        pos++; // past opening quote
        Appender!string out_;
        while (pos < src.length && src[pos] != q)
        {
            char c = src[pos];
            if (c == '\\' && q == '"' && pos + 1 < src.length)
            {
                char esc = src[pos + 1];
                switch (esc)
                {
                    case 'n': out_.put('\n'); break;
                    case 't': out_.put('\t'); break;
                    case 'r': out_.put('\r'); break;
                    case '\\': out_.put('\\'); break;
                    case '"': out_.put('"'); break;
                    case '0': out_.put('\0'); break;
                    default: out_.put(c); out_.put(esc); break;
                }
                pos += 2;
            }
            else
            {
                out_.put(c);
                pos++;
            }
        }
        if (pos < src.length) pos++; // past closing quote
        return out_.data;
    }

    bool lineHasMapColon()
    {
        // Scan current line for ` : ` or `: ` or trailing `:`
        // without crossing a quoted-string boundary at top level.
        size_t i = pos;
        bool inSingle = false, inDouble = false;
        while (i < src.length && src[i] != '\n')
        {
            char c = src[i];
            if (!inDouble && c == '\'') inSingle = !inSingle;
            else if (!inSingle && c == '"') inDouble = !inDouble;
            else if (!inSingle && !inDouble && c == '#') return false;
            else if (!inSingle && !inDouble && c == ':')
            {
                if (i + 1 >= src.length || src[i + 1] == ' '
                    || src[i + 1] == '\n')
                    return true;
            }
            i++;
        }
        return false;
    }

    size_t countIndent()
    {
        size_t n = 0;
        while (pos + n < src.length && src[pos + n] == ' ') n++;
        return n;
    }

    size_t countIndentAt(size_t p)
    {
        size_t n = 0;
        while (p + n < src.length && src[p + n] == ' ') n++;
        return n;
    }

    void skipToNextLine()
    {
        while (pos < src.length && src[pos] != '\n') pos++;
        if (pos < src.length) pos++; // past newline
    }

    void skipBlankAndComments()
    {
        while (pos < src.length)
        {
            size_t lineStart = pos;
            size_t indent = countIndent();
            if (pos + indent < src.length)
            {
                char c = src[pos + indent];
                if (c == '\n') { pos += indent + 1; continue; }
                if (c == '#') { skipToNextLine(); continue; }
            }
            else if (pos + indent == src.length)
            {
                pos += indent;
                break;
            }
            break;
        }
    }

    void skipFlowWhitespace()
    {
        while (pos < src.length)
        {
            char c = src[pos];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') pos++;
            else if (c == '#') skipToNextLine();
            else break;
        }
    }
}

// ── Scalar classification ─────────────────────────────────────────────

private Node classifyScalar(string raw)
{
    if (raw.length == 0) return Node(NodeKind.scalar, ScalarType.str, "");

    // Quoted strings classified as plain string (caller already stripped quotes)
    // null
    if (raw == "null" || raw == "~" || raw == "Null" || raw == "NULL")
        return Node(NodeKind.scalar, ScalarType.nullVal);

    // bool — YAML 1.1 boolean keywords (Bun + js-yaml accept these)
    bool b;
    if (parseBool(raw, b))
        return Node(NodeKind.scalar, ScalarType.boolVal, "", b);

    // int
    if (looksLikeInt(raw))
        return Node(NodeKind.scalar, ScalarType.intVal, raw);

    // float
    if (looksLikeFloat(raw))
        return Node(NodeKind.scalar, ScalarType.floatVal, raw);

    // string fallback
    return Node(NodeKind.scalar, ScalarType.str, raw);
}

private bool parseBool(string s, out bool b) @safe pure nothrow
{
    switch (s)
    {
        case "true": case "True": case "TRUE":
        case "yes":  case "Yes":  case "YES":
        case "on":   case "On":   case "ON":
            b = true; return true;
        case "false": case "False": case "FALSE":
        case "no":    case "No":    case "NO":
        case "off":   case "Off":   case "OFF":
            b = false; return true;
        default: return false;
    }
}

private bool looksLikeInt(string s) @safe pure nothrow
{
    if (s.length == 0) return false;
    size_t i = 0;
    if (s[0] == '-' || s[0] == '+') i = 1;
    if (i >= s.length) return false;
    for (; i < s.length; i++)
        if (s[i] < '0' || s[i] > '9') return false;
    return true;
}

private bool looksLikeFloat(string s) @safe pure nothrow
{
    if (s.length == 0) return false;
    bool sawDot = false, sawExp = false, sawDigit = false;
    size_t i = 0;
    if (s[0] == '-' || s[0] == '+') i = 1;
    for (; i < s.length; i++)
    {
        char c = s[i];
        if (c >= '0' && c <= '9') sawDigit = true;
        else if (c == '.' && !sawDot && !sawExp) sawDot = true;
        else if ((c == 'e' || c == 'E') && !sawExp && sawDigit)
        {
            sawExp = true;
            if (i + 1 < s.length && (s[i + 1] == '+' || s[i + 1] == '-')) i++;
        }
        else return false;
    }
    return sawDigit && (sawDot || sawExp);
}

// ── Node → JS conversion ──────────────────────────────────────────────

private JSHandle nodeToJs(IJSEngine engine, Node n) @trusted
{
    assert(engine !is null, "Null engine in nodeToJs");
    final switch (n.kind)
    {
        case NodeKind.nullVal:
            return engine.newNull();
        case NodeKind.scalar:
            final switch (n.scalarType)
            {
                case ScalarType.nullVal: return engine.newNull();
                case ScalarType.boolVal: return engine.newBool(n.boolVal);
                case ScalarType.str:     return engine.newString(n.scalarStr);
                case ScalarType.intVal:
                    import std.conv : to;
                    try return engine.newFloat(to!double(n.scalarStr));
                    catch (Exception) return engine.newString(n.scalarStr);
                case ScalarType.floatVal:
                    import std.conv : to;
                    try return engine.newFloat(to!double(n.scalarStr));
                    catch (Exception) return engine.newString(n.scalarStr);
            }
        case NodeKind.sequence:
            auto arr = engine.newArray();
            foreach (i, child; n.seq)
            {
                auto childVal = nodeToJs(engine, child);
                engine.setPropertyIndex(arr, cast(uint) i, childVal);
                // setPropertyIndex consumes on QJS, doesn't on JSC/V8
                version (EngineQuickJS) {}
                else engine.freeValue(childVal);
            }
            return arr;
        case NodeKind.mapping:
            auto obj = engine.newObject();
            foreach (i, k; n.mapKeys)
            {
                auto childVal = nodeToJs(engine, n.mapVals[i]);
                engine.setProperty(obj, k, childVal);
                version (EngineQuickJS) {}
                else engine.freeValue(childVal);
            }
            return obj;
    }
}

// ── Emitter (stringify) ───────────────────────────────────────────────

private enum string INDENT_UNIT = "  ";

private void emitValue(IJSEngine engine, JSHandle val, size_t depth,
    ref Appender!string out_) @trusted
{
    assert(engine !is null, "Null engine in emitValue");
    if (engine.isNull(val) || engine.isUndefined(val))
    {
        out_.put("null\n");
        return;
    }
    if (engine.isBool(val))
    {
        out_.put(engine.extractBool(val) ? "true\n" : "false\n");
        return;
    }
    if (engine.isNumber(val))
    {
        import std.conv : to;
        out_.put(to!string(engine.extractFloat(val)));
        out_.put('\n');
        return;
    }
    if (engine.isString(val))
    {
        emitScalarString(engine.extractString(val), out_);
        return;
    }
    if (engine.isArray(val))
    {
        int n = engine.getArrayLength(val);
        if (n == 0) { out_.put("[]\n"); return; }
        out_.put('\n');
        foreach (i; 0 .. n)
        {
            foreach (_; 0 .. depth) out_.put(INDENT_UNIT);
            out_.put("- ");
            auto elem = engine.getPropertyIndex(val, cast(uint) i);
            emitInlineOrNested(engine, elem, depth + 1, out_);
            engine.freeValue(elem);
        }
        return;
    }
    if (engine.isObject(val))
    {
        // List keys via a JS-side helper (no `Object.keys` on IJSEngine)
        auto keysFn = lookupKeysFn(engine);
        if (keysFn == JSHandle.init)
        {
            out_.put("{}\n");
            return;
        }
        JSHandle[1] callArgs = [val];
        auto keysArr = engine.callFunction(keysFn, engine.newUndefined(), callArgs[]);
        int n = engine.getArrayLength(keysArr);
        if (n == 0) { out_.put("{}\n"); engine.freeValue(keysArr); return; }
        out_.put('\n');
        foreach (i; 0 .. n)
        {
            foreach (_; 0 .. depth) out_.put(INDENT_UNIT);
            auto keyH = engine.getPropertyIndex(keysArr, cast(uint) i);
            string k = engine.extractString(keyH);
            engine.freeValue(keyH);
            emitKey(k, out_);
            out_.put(": ");
            auto childVal = engine.getProperty(val, k);
            emitInlineOrNested(engine, childVal, depth + 1, out_);
            engine.freeValue(childVal);
        }
        engine.freeValue(keysArr);
        return;
    }
    out_.put("null\n");
}

private void emitInlineOrNested(IJSEngine engine, JSHandle val, size_t depth,
    ref Appender!string out_) @trusted
{
    assert(engine !is null, "Null engine in emitInlineOrNested");
    // Scalars on the same line; arrays/objects start on the next line
    // (handled by emitValue's leading '\n' for non-empty containers).
    if (engine.isObject(val) && !engine.isArray(val))
    {
        emitValue(engine, val, depth, out_);
    }
    else if (engine.isArray(val))
    {
        emitValue(engine, val, depth, out_);
    }
    else
    {
        emitValue(engine, val, depth, out_);
    }
}

private void emitScalarString(string s, ref Appender!string out_) @safe
{
    // Quote if the string would be ambiguous as a YAML scalar.
    if (needsQuoting(s))
    {
        out_.put('"');
        foreach (c; s)
        {
            switch (c)
            {
                case '"':  out_.put("\\\""); break;
                case '\\': out_.put("\\\\"); break;
                case '\n': out_.put("\\n");  break;
                case '\t': out_.put("\\t");  break;
                case '\r': out_.put("\\r");  break;
                default:   out_.put(c);      break;
            }
        }
        out_.put('"');
    }
    else
        out_.put(s);
    out_.put('\n');
}

private void emitKey(string k, ref Appender!string out_) @safe
{
    if (needsQuoting(k))
    {
        out_.put('"');
        foreach (c; k)
        {
            switch (c)
            {
                case '"':  out_.put("\\\""); break;
                case '\\': out_.put("\\\\"); break;
                default:   out_.put(c);      break;
            }
        }
        out_.put('"');
    }
    else
        out_.put(k);
}

private bool needsQuoting(string s) @safe pure nothrow
{
    if (s.length == 0) return true;
    // Reserved words that classifyScalar would mis-type
    if (s == "null" || s == "Null" || s == "NULL" || s == "~"
        || s == "true" || s == "True" || s == "TRUE"
        || s == "false" || s == "False" || s == "FALSE"
        || s == "yes" || s == "no" || s == "on" || s == "off")
        return true;
    if (looksLikeInt(s) || looksLikeFloat(s)) return true;
    foreach (c; s)
        if (c == ':' || c == '#' || c == '\n' || c == '\r' || c == '\t'
         || c == '"' || c == '\'' || c == '\\' || c == '{' || c == '['
         || c == ',' || c == '&' || c == '*' || c == '!' || c == '|'
         || c == '>' || c == '%' || c == '@' || c == '`')
            return true;
    if (s[0] == ' ' || s[$ - 1] == ' ') return true;
    if (s[0] == '-' && s.length > 1 && s[1] == ' ') return true;
    return false;
}

// Cache `Object.keys` lookup via a one-time eval. Avoids per-stringify-call
// engine.eval which on JSC would compile fresh bytecode per call
// (same anti-pattern fix as fetch.d's `_fetchResponseBuilder`).
private __gshared JSHandle _yamlKeysFn;
private __gshared bool _yamlKeysFnCached = false;

private JSHandle lookupKeysFn(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null engine in lookupKeysFn");
    if (_yamlKeysFnCached) return _yamlKeysFn;
    auto r = engine.eval("(o => Object.keys(o))", "<yaml-keys>");
    if (!r.isError && engine.isFunction(r.value))
    {
        // Double-dup so the cached __gshared handle survives the
        // freeValue below — JSC's eval returns an unprotected
        // JSValueRef. Same pattern as fetch.d's _fetchResponseBuilder.
        engine.dupValue(r.value);
        _yamlKeysFn = engine.dupValue(r.value);
        _yamlKeysFnCached = true;
    }
    engine.freeValue(r.value);
    return _yamlKeysFn;
}

// ── Unit tests ────────────────────────────────────────────────────────

version (unittest)
{
    @safe unittest
    {
        // bool / null detection
        assert(parseBool("true",  *new bool));
        assert(parseBool("no",   *new bool) == true);  // parsed = true, val = false
        assert(!parseBool("nope", *new bool));

        // int / float classification
        assert(looksLikeInt("42"));
        assert(looksLikeInt("-17"));
        assert(!looksLikeInt("1.5"));
        assert(looksLikeFloat("1.5"));
        assert(looksLikeFloat("-3.14e2"));
        assert(!looksLikeFloat("abc"));
    }

    unittest
    {
        // Parse a simple mapping
        auto p = Parser("name: alice\nage: 30\n");
        auto n = p.parseDocument();
        assert(n.kind == NodeKind.mapping);
        assert(n.mapKeys == ["name", "age"]);
        assert(n.mapVals[0].scalarStr == "alice");
        assert(n.mapVals[1].scalarStr == "30");
        assert(n.mapVals[1].scalarType == ScalarType.intVal);
    }

    unittest
    {
        // Parse a block sequence
        auto p = Parser("- 1\n- 2\n- 3\n");
        auto n = p.parseDocument();
        assert(n.kind == NodeKind.sequence);
        assert(n.seq.length == 3);
        assert(n.seq[0].scalarStr == "1");
        assert(n.seq[2].scalarStr == "3");
    }

    unittest
    {
        // Parse flow style
        auto p = Parser("colors: [red, green, blue]\n");
        auto n = p.parseDocument();
        assert(n.kind == NodeKind.mapping);
        assert(n.mapKeys[0] == "colors");
        assert(n.mapVals[0].kind == NodeKind.sequence);
        assert(n.mapVals[0].seq.length == 3);
        assert(n.mapVals[0].seq[0].scalarStr == "red");
    }

    unittest
    {
        // Comments + null + quoted
        auto p = Parser("# comment\nfoo: \"bar baz\"\nnothing: ~\n");
        auto n = p.parseDocument();
        assert(n.mapKeys[0] == "foo");
        assert(n.mapVals[0].scalarStr == "bar baz");
        assert(n.mapVals[1].scalarType == ScalarType.nullVal);
    }
}
