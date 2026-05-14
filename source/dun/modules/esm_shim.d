module dun.modules.esm_shim;

import dun.platform.arena : Appender;

string transpileESM(string source, string filename) @safe pure
{

    Appender!(char[]) result;
    result.reserve(source.length);
    string[] preamble;
    string[] exportNames;
    bool hasDefaultExport;
    bool usesImportMeta;

    auto lines = splitLines(source);
    foreach (line; lines)
    {
        auto trimmed = stripLeft(line);
        if (trimmed.length == 0 || trimmed[0] == '/' || trimmed[0] == '*')
        {
            result ~= line;
            result ~= '\n';
            continue;
        }

        if (startsWith(trimmed, "import "))
        {
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
            if (startsWith(rest, "function "))
            {
                auto name = extractIdent(rest[9 .. $]);
                if (name.length > 0)
                    exportNames ~= name;
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
                    exportNames ~= name;
                result ~= rest;
                result ~= '\n';
                continue;
            }
            if (startsWith(rest, "class "))
            {
                auto name = extractIdent(rest[6 .. $]);
                if (name.length > 0)
                    exportNames ~= name;
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

    // Inject import.meta polyfill if used
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
            output ~= "',";
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
    if (exportNames.length > 0 || hasDefaultExport)
    {
        output ~= "\nif(typeof module!=='undefined'){";
        if (hasDefaultExport && exportNames.length == 0)
        {
            output ~= "module.exports=__esm_default__;";
        }
        else
        {
            output ~= "module.exports={";
            foreach (i, name; exportNames)
            {
                if (i > 0) output ~= ',';
                output ~= name;
            }
            if (hasDefaultExport)
            {
                if (exportNames.length > 0) output ~= ',';
                output ~= "default:__esm_default__";
            }
            output ~= "};";
        }
        output ~= "}\n";
    }

    return (() @trusted => cast(string) output[])();
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
        name = bindingPart;
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
        buf ~= "const ";
        buf ~= name;
        buf ~= " = require('";
        buf ~= specifier;
        buf ~= "');";
    }
    else
    {
        buf ~= "require('";
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
    if (specifier == "dun:assert" || specifier == "node:assert" || specifier == "assert") return "__dun_cjs_assert__";
    if (specifier == "dun:querystring" || specifier == "node:querystring" || specifier == "querystring") return "__dun_cjs_querystring__";
    if (specifier == "dun:string_decoder" || specifier == "node:string_decoder" || specifier == "string_decoder") return "__dun_cjs_string_decoder__";
    if (specifier == "dun:timers/promises" || specifier == "node:timers/promises" || specifier == "timers/promises") return "__dun_cjs_timers_promises__";
    if (specifier == "dun:fs/promises" || specifier == "node:fs/promises" || specifier == "fs/promises") return "__dun_cjs_fs_promises__";
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
    return "";
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

private string extractBraceNames(string s) @safe pure nothrow
{
    return s;
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

private bool startsWith(string s, string prefix) @safe pure nothrow
{
    if (s.length < prefix.length) return false;
    return s[0 .. prefix.length] == prefix;
}
