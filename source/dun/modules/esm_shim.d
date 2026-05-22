module dun.modules.esm_shim;


/// `@trusted policy`: ESM-to-CJS interop shim — wraps each ESM
/// module in a CJS factory so the require() resolver can load it.
/// Every `@trusted` is one of:
///   1. `engine.eval` of the wrapped source — one eval per module
///      at load time (cached afterwards).
///   2. `Appender!(char[])` pre-reserved string building for the
///      shim wrapper. Pure D, but the `cast(string) char[]` to
///      build the final source is `@trusted`-by-pattern.
import dun.platform.arena : Appender;

struct ExportEntry
{
    string original;
    string alias_;
}

string transpileESM(string source, string filename) @safe pure
{
    // Shebang line — `#!/usr/bin/env -S deno run --allow-all` style.
    // Comment it out so JSC/V8 don't choke on `#`.
    if (source.length >= 2 && source[0] == '#' && source[1] == '!')
        source = "//" ~ source[2 .. $];

    Appender!(char[]) result;
    result.reserve(source.length);
    string[] preamble;
    ExportEntry[] exportEntries;
    bool hasDefaultExport;
    bool usesImportMeta;

    auto lines = splitLines(source);
    string pendingImport;  // Accumulates multi-line imports
    string pendingExport;  // Accumulates multi-line exports
    foreach (line; lines)
    {
        // Handle multi-line import accumulation
        if (pendingImport.length > 0)
        {
            pendingImport ~= " " ~ stripLeft(line);
            // Strip inline comments from accumulated line
            auto commentIdx = findInlineComment(pendingImport);
            if (commentIdx >= 0)
                pendingImport = pendingImport[0 .. commentIdx];
            if (findChar(pendingImport, '}') >= 0)
            {
                // Complete multi-line import — parse it
                auto parsed = parseImportLine(pendingImport[7 .. $].length > 0 ? pendingImport : pendingImport);
                if (parsed.length == 0)
                    parsed = parseImportLine(stripLeft(pendingImport));
                if (parsed.length > 0)
                    preamble ~= parsed;
                pendingImport = "";
            }
            continue;
        }

        // Handle multi-line export accumulation
        if (pendingExport.length > 0)
        {
            auto stripped = stripLeft(line);
            // Strip comments
            auto cIdx = findInlineComment(stripped);
            if (cIdx >= 0) stripped = stripped[0 .. cIdx];
            pendingExport ~= " " ~ stripped;
            if (findChar(line, '}') >= 0)
            {
                // Complete multi-line export — process it
                auto fromIdx = findFrom(pendingExport);
                if (fromIdx >= 0)
                {
                    auto reexport = parseReexport(pendingExport);
                    if (reexport.length > 0)
                    {
                        preamble ~= reexport;
                        auto reNames = parseBraceNames(pendingExport[7 .. $]);
                        foreach (n; reNames) exportEntries ~= ExportEntry(n, n);
                    }
                }
                else
                {
                    auto entries = parseBraceEntries(pendingExport[7 .. $]);
                    foreach (e; entries) exportEntries ~= e;
                }
                pendingExport = "";
            }
            continue;
        }

        auto trimmed = stripLeft(line);
        if (trimmed.length == 0 || trimmed[0] == '/' || trimmed[0] == '*')
        {
            result ~= line;
            result ~= '\n';
            continue;
        }

        if (startsWith(trimmed, "import "))
        {
            // Check for multi-line import: has '{' but no '}' on same line
            auto braceOpen = findChar(trimmed, '{');
            auto braceClose = findChar(trimmed, '}');
            if (braceOpen >= 0 && braceClose < 0)
            {
                // Strip inline comment before accumulating
                pendingImport = trimmed;
                auto commentIdx = findInlineComment(pendingImport);
                if (commentIdx >= 0)
                    pendingImport = pendingImport[0 .. commentIdx];
                continue;
            }

            auto parsed = parseImportLine(trimmed);
            if (parsed.length > 0)
            {
                preamble ~= parsed;
                auto trailing = importTrailing(trimmed);
                if (trailing.length > 0)
                {
                    result ~= trailing;
                    result ~= '\n';
                }
                continue;
            }
        }

        if (startsWith(trimmed, "export default "))
        {
            hasDefaultExport = true;
            result ~= "var __esm_default__ = ";
            result ~= trimmed[15 .. $];
            result ~= '\n';
            continue;
        }

        if (startsWith(trimmed, "export "))
        {
            auto rest = trimmed[7 .. $];

            // export { X, Y } from './module.js'  (re-export)
            // export { default as X } from './module.js'
            if (startsWith(rest, "{") || startsWith(rest, "{ "))
            {
                // Check if this is a multi-line export block
                auto braceClose = findChar(trimmed, '}');
                if (braceClose < 0)
                {
                    // Multi-line export — accumulate
                    pendingExport = trimmed;
                    continue;
                }

                auto fromIdx = findFrom(trimmed);
                if (fromIdx >= 0)
                {
                    auto reexport = parseReexport(trimmed);
                    if (reexport.length > 0)
                    {
                        preamble ~= reexport;
                        auto reNames = parseBraceNames(trimmed[7 .. $]);
                        foreach (n; reNames)
                            exportEntries ~= ExportEntry(n, n);
                        continue;
                    }
                }
                // export { X, Y } or export { X as Y } without from
                auto entries = parseBraceEntries(rest);
                foreach (e; entries)
                    exportEntries ~= e;
                continue;
            }

            // export * from './module.js'
            if (startsWith(rest, "* from ") || startsWith(rest, "*from "))
            {
                auto starReexport = parseStarReexport(trimmed);
                if (starReexport.length > 0)
                {
                    preamble ~= starReexport;
                    continue;
                }
            }

            if (startsWith(rest, "function "))
            {
                auto name = extractIdent(rest[9 .. $]);
                if (name.length > 0)
                    exportEntries ~= ExportEntry(name, name);
                result ~= rest;
                result ~= '\n';
                continue;
            }
            if (startsWith(rest, "const ") || startsWith(rest, "let ") || startsWith(rest, "var "))
            {
                auto declStart = startsWith(rest, "const ") ? 6 :
                                 startsWith(rest, "let ") ? 4 : 4;
                auto name = extractIdent(rest[declStart .. $]);
                if (name.length > 0)
                    exportEntries ~= ExportEntry(name, name);
                result ~= rest;
                result ~= '\n';
                continue;
            }
            if (startsWith(rest, "class "))
            {
                auto name = extractIdent(rest[6 .. $]);
                if (name.length > 0)
                    exportEntries ~= ExportEntry(name, name);
                result ~= rest;
                result ~= '\n';
                continue;
            }
            result ~= rest;
            result ~= '\n';
            continue;
        }

        result ~= line;
        result ~= '\n';
    }

    // Replace import.meta references with __import_meta__
    auto body_ = (() @trusted => cast(string) result[])();
    if (containsImportMeta(body_))
    {
        usesImportMeta = true;
        body_ = replaceImportMeta(body_);
    }

    Appender!(char[]) output;
    output.reserve(source.length + 256);

    // Inject import.meta polyfill if used. `resolve()` is closure-bound
    // to the importing module's directory so relative specifiers resolve
    // the same way `import` itself would (matches Node ESM spec). For
    // bare specifiers we fall back to constructing a `file://` URL
    // against the importing dir + node_modules walk via require.resolve
    // when available — full Node semantics live in the C-level loader.
    if (usesImportMeta)
    {
        output ~= "var __import_meta__={";
        if (filename.length > 0)
        {
            auto absPath = toAbsPath(filename);
            output ~= "url:'file://";
            output ~= escapeJsString(absPath);
            output ~= "',filename:'";
            output ~= escapeJsString(absPath);
            output ~= "',dirname:'";
            output ~= escapeJsString(dirOfPath(absPath));
            output ~= "',resolve:function(spec){";
            output ~= "if(typeof spec!=='string')throw new TypeError('import.meta.resolve: spec must be a string');";
            output ~= "if(spec.indexOf('://')!==-1)return spec;";
            output ~= "var dir='" ~ escapeJsString(dirOfPath(absPath)) ~ "';";
            output ~= "if(spec[0]==='/')return 'file://'+spec;";
            output ~= "if(spec[0]==='.'){";
            output ~= "var parts=(dir+'/'+spec).split('/'),out=[];";
            output ~= "for(var i=0;i<parts.length;i++){if(parts[i]==='..')out.pop();else if(parts[i]&&parts[i]!=='.')out.push(parts[i]);}";
            output ~= "return 'file:///'+out.join('/');}";
            // Bare specifier: try `require.resolve` if we're in CJS-interop
            // mode, else assume it resolves to the bare name (Node returns
            // a `node:` URL for builtins).
            output ~= "try{if(typeof require!=='undefined'&&require.resolve)return 'file://'+require.resolve(spec);}catch(e){}";
            output ~= "return spec;";
            output ~= "},";
        }
        output ~= "main:false};\n";
    }

    foreach (p; preamble)
    {
        output ~= p;
        output ~= '\n';
    }
    output ~= body_;

    // Emit module.exports for CJS interop (require() of .mjs files)
    if (exportEntries.length > 0 || hasDefaultExport)
    {
        // Check for `export { X as 'module.exports' }` — Node.js CJS interop
        string moduleExportsName;
        ExportEntry[] normalEntries;
        foreach (e; exportEntries)
        {
            if (e.alias_ == "module.exports")
                moduleExportsName = e.original;
            else
                normalEntries ~= e;
        }

        output ~= "\nif(typeof module!=='undefined'){";
        if (moduleExportsName.length > 0)
        {
            // `export { X as 'module.exports' }` means X IS the module export
            output ~= "module.exports=";
            output ~= moduleExportsName;
            output ~= ";";
        }
        else if (hasDefaultExport && normalEntries.length == 0)
        {
            output ~= "module.exports=__esm_default__;";
        }
        else
        {
            output ~= "module.exports={";
            foreach (i, e; normalEntries)
            {
                if (i > 0) output ~= ',';
                if (e.original == e.alias_)
                    output ~= e.alias_;
                else
                {
                    // Quote alias if it contains non-identifier chars
                    if (containsDot(e.alias_))
                    {
                        output ~= '\'';
                        output ~= e.alias_;
                        output ~= '\'';
                    }
                    else
                        output ~= e.alias_;
                    output ~= ':';
                    output ~= e.original;
                }
            }
            if (hasDefaultExport)
            {
                if (normalEntries.length > 0) output ~= ',';
                output ~= "default:__esm_default__";
            }
            output ~= "};";
        }
        output ~= "}\n";
    }

    auto transpiled = (() @trusted => cast(string) output[])();

    // V8/JSC backends evaluate the transpiled module as a script, but
    // top-level `await` only parses in a module context. Detect a
    // top-level `await` in the source and wrap the whole body in an
    // async IIFE so the runtime accepts it. Errors propagate via
    // `.catch` so the host's promise rejection handler sees them.
    if (hasTopLevelAwait(transpiled))
        transpiled = "(async()=>{" ~ transpiled
            ~ "\n})().catch(e=>{ if(typeof process!=='undefined'&&process.exit)"
            ~ "{try{console.error(e&&e.stack||e);}catch(_){};process.exit(1);}"
            ~ "else{throw e;}});";

    return transpiled;
}

/// True if `await` appears at top-level (outside string/comment/
/// function/class). Block statements don't count as scopes, so
/// `try { await … }` still qualifies. Decides whether to wrap in an
/// async IIFE.
private bool hasTopLevelAwait(string s) @safe pure nothrow
{
    // Stack of brace "kinds": true = function/method/class body (await
    // inside is *not* top-level), false = block body (try / if / for /
    // while / switch). Plus a running counter of how many "true" entries
    // are on the stack so the inner top-level check stays O(1) instead
    // of walking the whole stack on every byte.
    bool[64] fnStackBuf;
    bool[] fnStack = fnStackBuf[0 .. 0];
    int fnDepth = 0;
    int parenD = 0, bracketD = 0;
    size_t i = 0;
    while (i < s.length)
    {
        char c = s[i];
        if (c == '\'' || c == '"')
        {
            char q = c; i++;
            while (i < s.length && s[i] != q)
            {
                if (s[i] == '\\' && i + 1 < s.length) i += 2;
                else i++;
            }
            if (i < s.length) i++;
            continue;
        }
        if (c == '`')
        {
            i++;
            while (i < s.length && s[i] != '`')
            {
                if (s[i] == '\\' && i + 1 < s.length) i += 2;
                else i++;
            }
            if (i < s.length) i++;
            continue;
        }
        if (c == '/' && i + 1 < s.length)
        {
            if (s[i + 1] == '/')
            {
                while (i < s.length && s[i] != '\n') i++;
                continue;
            }
            if (s[i + 1] == '*')
            {
                i += 2;
                while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) i++;
                if (i + 1 < s.length) i += 2;
                continue;
            }
        }
        if (c == '{')
        {
            // Decide if this `{` opens a function / class body. The
            // unambiguous shapes:
            //   `)` `{`        -- function / method / arrow with params
            //   `=>` `{`       -- arrow without params (e.g. `() => {`)
            //   `class X {`    -- class body
            //   `class X extends Y {` (`Y` is an ident before `{`)
            // Everything else is a block.
            bool isFn = false;
            size_t back = i;
            while (back > 0 && (s[back - 1] == ' ' || s[back - 1] == '\t'
                    || s[back - 1] == '\n' || s[back - 1] == '\r')) back--;
            if (back > 0)
            {
                if (s[back - 1] == ')') isFn = true;
                else if (back >= 2 && s[back - 2] == '=' && s[back - 1] == '>') isFn = true;
            }
            // class declarations / expressions
            if (!isFn && i >= 7)
            {
                size_t j = i;
                while (j > 0 && (s[j - 1] == ' ' || s[j - 1] == '\t'
                        || s[j - 1] == '\n' || s[j - 1] == '\r'
                        || isIdentChar2(s[j - 1]))) j--;
                // Now j is at the start of the prior keyword/ident
                // (or whitespace boundary). Walk forward to check for
                // `class` token.
                while (j < i && (s[j] == ' ' || s[j] == '\t'
                        || s[j] == '\n' || s[j] == '\r')) j++;
                if (j + 5 <= i && s[j .. j + 5] == "class") isFn = true;
            }
            // Stack-buffer-first, GC-spill fallback: keeps the common
            // case (depth <= 64) GC-free.
            if (fnStack.length < fnStackBuf.length)
                fnStack = fnStackBuf[0 .. fnStack.length + 1];
            else
                fnStack.length = fnStack.length + 1;
            fnStack[$ - 1] = isFn;
            if (isFn) fnDepth++;
            i++;
            continue;
        }
        if (c == '}')
        {
            if (fnStack.length > 0)
            {
                if (fnStack[$ - 1] && fnDepth > 0) fnDepth--;
                fnStack = fnStack[0 .. $ - 1];
            }
            i++;
            continue;
        }
        if (c == '(') { parenD++; i++; continue; }
        if (c == ')') { if (parenD > 0) parenD--; i++; continue; }
        if (c == '[') { bracketD++; i++; continue; }
        if (c == ']') { if (bracketD > 0) bracketD--; i++; continue; }

        // "Top-level" = depth-0 parens/brackets AND no enclosing
        // function/class scope.
        if (fnDepth == 0 && parenD == 0 && bracketD == 0)
        {
            if (i + 6 <= s.length && s[i .. i + 5] == "await"
                && (s[i + 5] == ' ' || s[i + 5] == '\t' || s[i + 5] == '\n'
                    || s[i + 5] == '(' || s[i + 5] == '\r')
                && (i == 0 || !isIdentChar2(s[i - 1])))
                return true;
        }
        i++;
    }
    return false;
}

private bool isIdentChar2(char c) @safe pure nothrow @nogc
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9') || c == '_' || c == '$';
}

private bool containsImportMeta(string s) @safe pure nothrow
{
    if (s.length < 11) return false;
    foreach (i; 0 .. s.length - 10)
    {
        if (s[i .. i + 11] == "import.meta")
            return true;
    }
    return false;
}

private string replaceImportMeta(string s) @safe pure
{
    Appender!(char[]) out_;
    out_.reserve(s.length);
    size_t i = 0;
    while (i < s.length)
    {
        // Skip string literals
        if (s[i] == '\'' || s[i] == '"' || s[i] == '`')
        {
            char q = s[i];
            out_ ~= s[i];
            i++;
            while (i < s.length)
            {
                if (s[i] == '\\' && i + 1 < s.length)
                {
                    out_ ~= s[i];
                    out_ ~= s[i + 1];
                    i += 2;
                }
                else if (s[i] == q)
                {
                    out_ ~= s[i];
                    i++;
                    break;
                }
                else if (q == '`' && s[i] == '$' && i + 1 < s.length && s[i + 1] == '{')
                {
                    // Template literal expression — copy ${ and recurse into brace-balanced expression
                    out_ ~= s[i];
                    out_ ~= s[i + 1];
                    i += 2;
                    int depth = 1;
                    while (i < s.length && depth > 0)
                    {
                        if (s[i] == '{') depth++;
                        else if (s[i] == '}') { depth--; if (depth == 0) break; }

                        if (i + 11 <= s.length && s[i .. i + 11] == "import.meta")
                        {
                            out_ ~= "__import_meta__";
                            i += 11;
                        }
                        else
                        {
                            out_ ~= s[i];
                            i++;
                        }
                    }
                    if (i < s.length && s[i] == '}')
                    {
                        out_ ~= s[i];
                        i++;
                    }
                }
                else
                {
                    out_ ~= s[i];
                    i++;
                }
            }
            continue;
        }

        // Skip line comments
        if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '/')
        {
            while (i < s.length && s[i] != '\n')
            {
                out_ ~= s[i];
                i++;
            }
            continue;
        }

        // Skip block comments
        if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '*')
        {
            out_ ~= s[i];
            out_ ~= s[i + 1];
            i += 2;
            while (i + 1 < s.length)
            {
                if (s[i] == '*' && s[i + 1] == '/')
                {
                    out_ ~= s[i];
                    out_ ~= s[i + 1];
                    i += 2;
                    break;
                }
                out_ ~= s[i];
                i++;
            }
            continue;
        }

        // Replace import.meta in code context
        if (i + 11 <= s.length && s[i .. i + 11] == "import.meta")
        {
            out_ ~= "__import_meta__";
            i += 11;
        }
        else
        {
            out_ ~= s[i];
            i++;
        }
    }
    return (() @trusted => cast(string) out_[])();
}

private string escapeJsString(string s) @safe pure
{
    Appender!(char[]) buf;
    buf.reserve(s.length + s.length / 8);
    foreach (c; s)
    {
        if (c == '\'') { buf ~= '\\'; buf ~= '\''; }
        else if (c == '\\') { buf ~= '\\'; buf ~= '\\'; }
        else buf ~= c;
    }
    return (() @trusted => cast(string) buf[])();
}

private string toAbsPath(string path) @safe pure nothrow
{
    if (path.length > 0 && path[0] == '/')
        return path;
    return path;
}

private string dirOfPath(string path) @safe pure nothrow
{
    // Find last '/' and return everything before it
    size_t lastSlash = 0;
    bool found = false;
    foreach (i, c; path)
    {
        if (c == '/')
        {
            lastSlash = i;
            found = true;
        }
    }
    if (found)
        return path[0 .. lastSlash];
    return ".";
}

private string importTrailing(string line) @safe pure nothrow
{
    auto rest = line[7 .. $];
    auto fromIdx = findFrom(rest);
    if (fromIdx < 0) return "";
    auto afterFrom = rest[fromIdx + 4 .. $];
    auto t = stripLeft(afterFrom);
    if (t.length < 2) return "";
    char q = t[0];
    if (q != '\'' && q != '"') return "";
    foreach (i; 1 .. t.length)
    {
        if (t[i] == q)
        {
            auto afterQuote = stripLeft(t[i + 1 .. $]);
            if (afterQuote.length > 0 && afterQuote[0] == ';')
                afterQuote = stripLeft(afterQuote[1 .. $]);
            // Skip import attributes: with {...} or assert {...}
            if (startsWith(afterQuote, "with ") || startsWith(afterQuote, "assert "))
            {
                auto braceStart = findChar(afterQuote, '{');
                if (braceStart >= 0)
                {
                    auto braceEnd = findChar(afterQuote[braceStart .. $], '}');
                    if (braceEnd >= 0)
                    {
                        afterQuote = stripLeft(afterQuote[braceStart + braceEnd + 1 .. $]);
                        if (afterQuote.length > 0 && afterQuote[0] == ';')
                            afterQuote = stripLeft(afterQuote[1 .. $]);
                    }
                }
            }
            return afterQuote;
        }
    }
    return "";
}

private int findChar(string s, char c) @safe pure nothrow
{
    foreach (i, ch; s)
        if (ch == c) return cast(int) i;
    return -1;
}

private string parseImportLine(string line) @safe pure
{
    if (line.length < 7) return "";
    auto rest = line[7 .. $];

    auto fromIdx = findFrom(rest);
    if (fromIdx < 0) return "";

    auto specifier = extractStringLiteral(rest[fromIdx + 4 .. $]);
    if (specifier.length == 0) return "";

    auto bindingPart = stripRight(rest[0 .. fromIdx]);
    auto globalProp = builtinGlobalProp(specifier);

    Appender!(char[]) buf;
    buf.reserve(80);

    string name;
    if (bindingPart.length > 0 && bindingPart[0] == '{')
        name = rewriteBraceAs(bindingPart);
    else if (bindingPart.length > 0 && bindingPart[0] == '*')
    {
        auto asIdx = findAs(bindingPart);
        if (asIdx >= 0)
            name = stripLeft(bindingPart[asIdx + 2 .. $]);
    }
    else if (bindingPart.length > 0)
        name = extractIdent(bindingPart);

    if (globalProp.length > 0)
    {
        if (name.length == 0)
            return "";
        buf ~= "const ";
        buf ~= name;
        buf ~= " = globalThis.";
        buf ~= globalProp;
        buf ~= ";";
        return (() @trusted => cast(string) buf[])();
    }

    if (name.length > 0)
    {
        // Use globalThis.require to avoid TDZ if module redeclares `const require = ...`
        buf ~= "const ";
        buf ~= name;
        buf ~= " = globalThis.require('";
        buf ~= specifier;
        buf ~= "');";
    }
    else
    {
        buf ~= "globalThis.require('";
        buf ~= specifier;
        buf ~= "');";
    }
    return (() @trusted => cast(string) buf[])();
}

private string builtinGlobalProp(string specifier) @safe pure nothrow
{
    if (specifier == "dun:fs" || specifier == "node:fs" || specifier == "fs") return "__dun_cjs_fs__";
    if (specifier == "dun:path" || specifier == "node:path" || specifier == "path") return "__dun_cjs_path__";
    if (specifier == "dun:crypto" || specifier == "node:crypto" || specifier == "crypto") return "__dun_cjs_crypto__";
    if (specifier == "dun:net" || specifier == "node:net" || specifier == "net") return "__dun_cjs_net__";
    if (specifier == "dun:http" || specifier == "node:http" || specifier == "http") return "__dun_cjs_http__";
    if (specifier == "dun:https" || specifier == "node:https" || specifier == "https") return "__dun_cjs_https__";
    if (specifier == "dun:http2" || specifier == "node:http2" || specifier == "http2") return "__dun_cjs_http2__";
    if (specifier == "dun:http3" || specifier == "node:http3" || specifier == "http3") return "__dun_cjs_http3__";
    if (specifier == "dun:os" || specifier == "node:os" || specifier == "os") return "__dun_cjs_os__";
    if (specifier == "dun:buffer" || specifier == "node:buffer" || specifier == "buffer") return "__dun_cjs_buffer__";
    if (specifier == "dun:events" || specifier == "node:events" || specifier == "events") return "__dun_cjs_events__";
    if (specifier == "dun:url" || specifier == "node:url" || specifier == "url") return "__dun_cjs_url__";
    if (specifier == "dun:util" || specifier == "node:util" || specifier == "util") return "__dun_cjs_util__";
    if (specifier == "dun:assert" || specifier == "node:assert" || specifier == "assert"
     || specifier == "dun:assert/strict" || specifier == "node:assert/strict" || specifier == "assert/strict")
        return "__dun_cjs_assert__";
    if (specifier == "dun:test" || specifier == "node:test" || specifier == "test")
        return "__dun_cjs_node_test__";
    if (specifier == "dun:querystring" || specifier == "node:querystring" || specifier == "querystring") return "__dun_cjs_querystring__";
    if (specifier == "dun:string_decoder" || specifier == "node:string_decoder" || specifier == "string_decoder") return "__dun_cjs_string_decoder__";
    if (specifier == "dun:timers/promises" || specifier == "node:timers/promises" || specifier == "timers/promises") return "__dun_cjs_timers_promises__";
    if (specifier == "dun:fs/promises" || specifier == "node:fs/promises" || specifier == "fs/promises") return "__dun_cjs_fs_promises__";
    if (specifier == "dun:dns/promises" || specifier == "node:dns/promises" || specifier == "dns/promises") return "__dun_cjs_dns_promises__";
    if (specifier == "dun:tls" || specifier == "node:tls" || specifier == "tls") return "__dun_cjs_tls__";
    if (specifier == "dun:dgram" || specifier == "node:dgram" || specifier == "dgram") return "__dun_cjs_dgram__";
    if (specifier == "dun:perf_hooks" || specifier == "node:perf_hooks" || specifier == "perf_hooks") return "__dun_cjs_perf_hooks__";
    if (specifier == "dun:readline" || specifier == "node:readline" || specifier == "readline") return "__dun_cjs_readline__";
    if (specifier == "dun:punycode" || specifier == "node:punycode" || specifier == "punycode") return "__dun_cjs_punycode__";
    if (specifier == "dun:diagnostics_channel" || specifier == "node:diagnostics_channel" || specifier == "diagnostics_channel") return "__dun_cjs_diagnostics_channel__";
    if (specifier == "dun:domain" || specifier == "node:domain" || specifier == "domain") return "__dun_cjs_domain__";
    if (specifier == "dun:tty" || specifier == "node:tty" || specifier == "tty") return "__dun_cjs_tty__";
    if (specifier == "dun:constants" || specifier == "node:constants" || specifier == "constants") return "__dun_cjs_constants__";
    if (specifier == "dun:module" || specifier == "node:module" || specifier == "module") return "__dun_cjs_module__";
    if (specifier == "dun:timers" || specifier == "node:timers" || specifier == "timers") return "__dun_cjs_timers__";
    if (specifier == "dun:process" || specifier == "node:process" || specifier == "process") return "__dun_cjs_process__";
    if (specifier == "dun:console" || specifier == "node:console" || specifier == "console") return "__dun_cjs_console__";
    if (specifier == "dun:child_process" || specifier == "node:child_process" || specifier == "child_process") return "__dun_cjs_child_process__";
    if (specifier == "dun:stream" || specifier == "node:stream" || specifier == "stream") return "__dun_cjs_stream__";
    if (specifier == "dun:zlib" || specifier == "node:zlib" || specifier == "zlib") return "__dun_cjs_zlib__";
    if (specifier == "dun:dns" || specifier == "node:dns" || specifier == "dns") return "__dun_cjs_dns__";
    if (specifier == "dun:ws" || specifier == "node:ws" || specifier == "ws") return "__dun_cjs_ws__";
    if (specifier == "dun:sqlite" || specifier == "node:sqlite" || specifier == "sqlite") return "__dun_cjs_sqlite__";
    if (specifier == "dun:worker_threads" || specifier == "node:worker_threads" || specifier == "worker_threads") return "__dun_cjs_worker_threads__";
    if (specifier == "dun:cluster" || specifier == "node:cluster" || specifier == "cluster") return "__dun_cjs_cluster__";
    if (specifier == "dun:vm" || specifier == "node:vm" || specifier == "vm") return "__dun_cjs_vm__";
    if (specifier == "dun:async_hooks" || specifier == "node:async_hooks" || specifier == "async_hooks") return "__dun_cjs_async_hooks__";
    if (specifier == "dun:wasi" || specifier == "node:wasi" || specifier == "wasi") return "__dun_cjs_wasi__";
    return "";
}

private int findInlineComment(string s) @safe pure nothrow
{
    // Find '//' that's not inside a string
    bool inStr = false;
    char strChar = 0;
    foreach (i; 0 .. s.length)
    {
        if (inStr)
        {
            if (s[i] == strChar && (i == 0 || s[i-1] != '\\'))
                inStr = false;
        }
        else
        {
            if (s[i] == '\'' || s[i] == '"')
            {
                inStr = true;
                strChar = s[i];
            }
            else if (i + 1 < s.length && s[i] == '/' && s[i+1] == '/')
                return cast(int) i;
        }
    }
    return -1;
}

private int findFrom(string s) @safe pure nothrow
{
    if (s.length < 4) return -1;
    foreach (i; 0 .. s.length - 3)
    {
        if (s[i .. i + 4] == "from" &&
            (i == 0 || s[i-1] == ' ' || s[i-1] == '\t') &&
            (i + 4 >= s.length || s[i+4] == ' ' || s[i+4] == '\t' || s[i+4] == '\'' || s[i+4] == '"'))
            return cast(int) i;
    }
    return -1;
}

private int findAs(string s) @safe pure nothrow
{
    if (s.length < 2) return -1;
    foreach (i; 0 .. s.length - 1)
    {
        if (s[i .. i + 2] == "as" &&
            (i == 0 || s[i-1] == ' ') &&
            (i + 2 >= s.length || s[i+2] == ' '))
            return cast(int) i;
    }
    return -1;
}

private string extractStringLiteral(string s) @safe pure nothrow
{
    auto t = stripLeft(s);
    if (t.length < 2) return "";
    char q = t[0];
    if (q != '\'' && q != '"') return "";
    foreach (i; 1 .. t.length)
    {
        if (t[i] == q)
            return t[1 .. i];
    }
    return "";
}

// Rewrite ESM-style `{ A as X, B, C as Y }` into JS destructuring `{ A: X, B, C: Y }`.
// Also handles mixed default/named: `{ default as X, B }` -> `{ default: X, B }`.
private string rewriteBraceAs(string brace) @safe pure
{
    // brace is `{...}` with possibly nested whitespace
    if (brace.length < 2 || brace[0] != '{') return brace;
    auto closeIdx = -1;
    foreach_reverse (i; 0 .. brace.length)
    {
        if (brace[i] == '}') { closeIdx = cast(int) i; break; }
    }
    if (closeIdx < 0) return brace;

    auto inner = brace[1 .. closeIdx];
    auto tail = closeIdx + 1 < brace.length ? brace[closeIdx + 1 .. $] : "";

    Appender!(char[]) buf;
    buf.reserve(brace.length + 8);
    buf ~= "{";

    auto parts = splitByComma(inner);
    bool first = true;
    foreach (raw; parts)
    {
        auto p = stripLeft(stripRight(raw));
        if (p.length == 0) continue;
        if (!first) buf ~= ", ";
        first = false;

        // look for `as` keyword separating original/alias
        auto asIdx = findAs(p);
        if (asIdx > 0)
        {
            auto orig = stripRight(p[0 .. asIdx]);
            auto alias_ = stripLeft(p[asIdx + 2 .. $]);
            // strip string-quote aliases (export { X as 'module.exports' })
            if (alias_.length >= 2 && (alias_[0] == '\'' || alias_[0] == '"'))
                alias_ = alias_[1 .. $ - 1];
            buf ~= orig;
            buf ~= ": ";
            buf ~= alias_;
        }
        else
        {
            buf ~= p;
        }
    }
    buf ~= "}";
    buf ~= tail;
    return (() @trusted => cast(string) buf[])();
}

// Parse "export { X, Y, default as Z } from './mod.js'" into require + assignment
private string parseReexport(string line) @safe pure
{
    // Find the braced part and the from specifier
    auto braceStart = findChar(line, '{');
    auto braceEnd = findChar(line, '}');
    if (braceStart < 0 || braceEnd < 0 || braceEnd <= braceStart) return "";

    auto fromIdx = findFrom(line);
    if (fromIdx < 0) return "";
    auto specifier = extractStringLiteral(line[fromIdx + 4 .. $]);
    if (specifier.length == 0) return "";

    auto braceContent = line[braceStart + 1 .. braceEnd];

    // Parse comma-separated names: "default as MAX, parse, default as NIL"
    Appender!(char[]) output;
    output.reserve(256);
    output ~= "var __reexport_tmp__ = globalThis.require('";
    output ~= escapeJsString(specifier);
    output ~= "');\n";

    auto names = splitByComma(braceContent);
    foreach (name; names)
    {
        auto trimmedName = stripLeft(name);
        if (trimmedName.length == 0) continue;

        auto asIdx = findAs(trimmedName);
        if (asIdx >= 0)
        {
            auto srcName = stripRight(trimmedName[0 .. asIdx]);
            auto dstName = extractIdent(trimmedName[asIdx + 3 .. $]);
            if (dstName.length == 0) continue;
            if (srcName == "default")
                output ~= "var " ~ dstName ~ " = __reexport_tmp__.default !== undefined ? __reexport_tmp__.default : __reexport_tmp__;\n";
            else
                output ~= "var " ~ dstName ~ " = __reexport_tmp__." ~ srcName ~ ";\n";
        }
        else
        {
            auto ident = extractIdent(trimmedName);
            if (ident.length == 0) continue;
            output ~= "var " ~ ident ~ " = __reexport_tmp__." ~ ident ~ ";\n";
        }
    }

    return (() @trusted => cast(string) output[])();
}

// Parse "export * from './mod.js'" into Object.assign
private string parseStarReexport(string line) @safe pure
{
    auto fromIdx = findFrom(line);
    if (fromIdx < 0) return "";
    auto specifier = extractStringLiteral(line[fromIdx + 4 .. $]);
    if (specifier.length == 0) return "";
    return "Object.assign(module.exports, globalThis.require('" ~ escapeJsString(specifier) ~ "'));\n";
}

// Parse brace content "{ X, Y, Z }" into alias names (for re-exports, uses alias)
private string[] parseBraceNames(string s) @safe pure
{
    auto braceStart = findChar(s, '{');
    auto braceEnd = findChar(s, '}');
    if (braceStart < 0 || braceEnd < 0) return null;
    auto content = s[braceStart + 1 .. braceEnd];
    string[] names;
    foreach (part; splitByComma(content))
    {
        auto trimmed = stripLeft(part);
        auto asIdx = findAs(trimmed);
        if (asIdx >= 0)
        {
            auto dstName = extractIdent(trimmed[asIdx + 3 .. $]);
            if (dstName.length > 0) names ~= dstName;
        }
        else
        {
            auto ident = extractIdent(trimmed);
            if (ident.length > 0) names ~= ident;
        }
    }
    return names;
}

// Parse brace content "{ X, Y as Z }" into ExportEntry[] preserving original->alias mapping
private ExportEntry[] parseBraceEntries(string s) @safe pure
{
    auto braceStart = findChar(s, '{');
    auto braceEnd = findChar(s, '}');
    if (braceStart < 0 || braceEnd < 0) return null;
    auto content = s[braceStart + 1 .. braceEnd];
    ExportEntry[] entries;
    foreach (part; splitByComma(content))
    {
        auto trimmed = stripLeft(part);
        auto asIdx = findAs(trimmed);
        if (asIdx >= 0)
        {
            auto srcName = stripRight(extractIdent(trimmed));
            auto afterAs = stripLeft(trimmed[asIdx + 3 .. $]);
            // Handle string literal alias: `X as 'module.exports'`
            if (afterAs.length > 0 && (afterAs[0] == '\'' || afterAs[0] == '"'))
            {
                auto strName = extractStringLiteral(afterAs);
                if (srcName.length > 0 && strName.length > 0)
                    entries ~= ExportEntry(srcName, strName);
            }
            else
            {
                auto dstName = extractIdent(afterAs);
                if (srcName.length > 0 && dstName.length > 0)
                    entries ~= ExportEntry(srcName, dstName);
            }
        }
        else
        {
            auto ident = extractIdent(trimmed);
            if (ident.length > 0)
                entries ~= ExportEntry(ident, ident);
        }
    }
    return entries;
}

private string[] splitByComma(string s) @safe pure
{
    string[] parts;
    size_t start = 0;
    foreach (i, c; s)
    {
        if (c == ',')
        {
            parts ~= s[start .. i];
            start = i + 1;
        }
    }
    if (start <= s.length)
        parts ~= s[start .. $];
    return parts;
}


private string extractIdent(string s) @safe pure nothrow
{
    auto t = stripLeft(s);
    size_t end = 0;
    foreach (i, c; t)
    {
        if (c == '_' || c == '$' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (i > 0 && c >= '0' && c <= '9'))
            end = i + 1;
        else
            break;
    }
    return t[0 .. end];
}

private string[] splitLines(string s) @safe pure
{
    Appender!(string[]) result;
    if (s.length > 0)
        result.reserve(s.length / 40 + 1);
    size_t start = 0;
    foreach (i, c; s)
    {
        if (c == '\n')
        {
            result ~= s[start .. i];
            start = i + 1;
        }
    }
    if (start < s.length)
        result ~= s[start .. $];
    return result[];
}

private string stripLeft(string s) @safe pure nothrow
{
    size_t i = 0;
    while (i < s.length && (s[i] == ' ' || s[i] == '\t'))
        i++;
    return s[i .. $];
}

private string stripRight(string s) @safe pure nothrow
{
    auto len = s.length;
    while (len > 0 && (s[len - 1] == ' ' || s[len - 1] == '\t'))
        len--;
    return s[0 .. len];
}

private bool containsDot(string s) @safe pure nothrow
{
    foreach (c; s)
        if (c == '.') return true;
    return false;
}

private bool startsWith(string s, string prefix) @safe pure nothrow
{
    if (s.length < prefix.length) return false;
    return s[0 .. prefix.length] == prefix;
}
