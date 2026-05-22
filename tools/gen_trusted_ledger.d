/// Generates `docs/research/trusted-ledger.md` — the public audit
/// ledger of every `@trusted` block in the DunJS source tree.
///
/// Mirrors the role of Bun's https://bun.com/bun-unsafe-audit page:
/// every unsafe escape has a row with the file:line, the surrounding
/// declaration, the inline rationale (if any), and a category bucket.
///
/// Build + run:
///   ldc2 -run tools/gen_trusted_ledger.d
///   git diff docs/research/trusted-ledger.md   # see updated rows
///
/// The script is idempotent — running it after a refactor regenerates
/// the ledger to match the current tree.

module gen_trusted_ledger;

import std.file : dirEntries, SpanMode, readText, write;
import std.path : extension, baseName, dirName, asRelativePath;
import std.string : strip, indexOf, splitLines;
import std.algorithm : count, startsWith, canFind, sort;
import std.array : appender, array;
import std.regex : regex, matchFirst, Captures;
import std.conv : to;
import std.stdio : writeln;

struct TrustedSite
{
    string file;
    size_t line;
    string declaration;  // function/method signature line
    string rationale;    // line preceding the @trusted, if it's a doc comment
    string category;     // one of: FFI, GC-helper, hot-path, IO, crypto, lifecycle, other
}

string categorize(string file, string decl, string rationale) @safe
{
    auto sig = decl;
    if (file.canFind("engine/quickjs/") || file.canFind("engine/jsc/") || file.canFind("engine/v8/"))
        return "engine-FFI";
    if (file.canFind("platform/openssl") || file.canFind("builtins/crypto") || file.canFind("builtins/tls"))
        return "crypto-FFI";
    if (file.canFind("builtins/sqlite"))
        return "sqlite-FFI";
    if (file.canFind("platform/lsquic") || file.canFind("builtins/http3"))
        return "quic-FFI";
    if (file.canFind("napi/"))
        return "napi-FFI";
    if (file.canFind("platform/simd"))
        return "SIMD/hot-path";
    if (file.canFind("loop/iopoller") || file.canFind("loop/timers") || file.canFind("loop/async"))
        return "event-loop";
    if (file.canFind("builtins/net") || file.canFind("builtins/http") || file.canFind("builtins/http2")
        || file.canFind("builtins/dgram") || file.canFind("builtins/dns") || file.canFind("builtins/ws")
        || file.canFind("builtins/fetch"))
        return "network-IO";
    if (file.canFind("builtins/fs") || file.canFind("builtins/child_process"))
        return "fs-IO";
    if (sig.canFind("ctxState") || sig.canFind("makeBuffer") || sig.canFind("extractBytes"))
        return "engine-bridge";
    if (sig.canFind("nothrow") && sig.canFind("@nogc"))
        return "hot-path";
    return "other";
}

void main(string[] args)
{
    auto rx = regex(r"@trusted\b");
    auto declRx = regex(r"^\s*(?:private|public|package|extern\([^)]+\))?\s*(?:nothrow|@\w+|return\s+scope|scope|static|ref|const|immutable|pure|abstract|override)*\s*(?:[\w!]+\s+)?(?:[\w_][\w\d_]*)\s*\(");
    TrustedSite[][string] byCategory;
    int total = 0;

    foreach (string path; dirEntries("source", SpanMode.depth))
    {
        if (path.extension != ".d") continue;
        auto content = readText(path);
        auto lines = content.splitLines;
        foreach (i, line; lines)
        {
            if (!matchFirst(line, rx)) continue;
            // Skip @trusted inside a string literal or inside a comment.
            auto stripped = line.strip;
            if (stripped.startsWith("//") || stripped.startsWith("*") || stripped.startsWith("/*"))
                continue;
            if (stripped.canFind(`"@trusted"`) || stripped.canFind(`'@trusted'`))
                continue;

            TrustedSite s;
            s.file = path;
            s.line = i + 1;
            s.declaration = line.strip;

            // Look upward for a doc comment line. The @trusted may be:
            //   (a) on its own line at the end of a function signature
            //   (b) on the first line of a function signature with the
            //       declaration wrapping onto multiple lines
            // Walk upward skipping attribute-only lines, signature
            // continuation lines (start with `,` or contain only
            // qualifiers), and blank lines until we find either a `///`
            // doc comment (the rationale) or non-comment code (no
            // rationale).
            string rationale;
            ptrdiff_t scan = cast(ptrdiff_t) i - 1;
            while (scan >= 0)
            {
                auto prev = lines[scan].strip;
                if (prev.length == 0) { scan--; continue; }
                if (prev.startsWith("///"))
                {
                    // Accumulate consecutive `///` lines for the rationale.
                    rationale = prev;
                    auto walkUp = scan - 1;
                    while (walkUp >= 0)
                    {
                        auto p = lines[walkUp].strip;
                        if (p.startsWith("///")) { rationale = p ~ " " ~ rationale; walkUp--; }
                        else break;
                    }
                    break;
                }
                if (prev.startsWith("//"))
                {
                    // Non-doc comment isn't a rationale per the convention
                    // (rationale must be `///`). Stop without crediting.
                    break;
                }
                // Lines that are part of a continued signature:
                //   - start with a paren/bracket/comma
                //   - end with a comma or opening bracket
                //   - are pure attribute lines
                //   - are `else` / `version (...) { ... }` blocks
                if (prev.startsWith("(") || prev.startsWith(",")
                    || prev.startsWith("else") || prev.startsWith("version")
                    || prev.startsWith("@") || prev.startsWith("pragma")
                    || prev.startsWith("const(") || prev.startsWith("ref ")
                    || prev[$ - 1] == ',' || prev[$ - 1] == '('
                    || prev[$ - 1] == '{' || prev[$ - 1] == ')')
                {
                    scan--;
                    continue;
                }
                break;
            }
            s.rationale = rationale;
            s.category = categorize(path, s.declaration, rationale);
            byCategory[s.category] ~= s;
            total++;
        }
    }

    TrustedSite[][string] grouped = byCategory;

    auto md = appender!string;
    md.put("# DunJS `@trusted` ledger — public audit\n\n");
    md.put("**Auto-generated**: `ldc2 -run tools/gen_trusted_ledger.d`. Do not edit by hand.\n\n");
    md.put("This is DunJS's analogue of [bun.com/bun-unsafe-audit](https://bun.com/bun-unsafe-audit) — every `@trusted` block in the source tree, bucketed by reason. Adding new `@trusted` annotations should come with a doc-comment rationale (`/// ...`) on the line above; this ledger surfaces blocks that lack one.\n\n");

    md.put("## Summary\n\n");
    import std.format : format;
    md.put(format("- **Total `@trusted` sites**: %d\n", total));
    md.put(format("- **Categories**: %d\n", grouped.length));
    md.put(format("- **Generated**: ledger snapshot of `source/` tree at this commit.\n\n"));

    md.put("| Category | Count | What it is |\n");
    md.put("|---|---:|---|\n");
    string[] cats = grouped.keys.array;
    cats.sort();
    foreach (cat; cats)
    {
        md.put(format("| `%s` | %d | %s |\n", cat, grouped[cat].length, descriptionFor(cat)));
    }
    md.put("\n");

    foreach (cat; cats)
    {
        md.put(format("## %s (%d sites)\n\n", cat, grouped[cat].length));
        auto sites = grouped[cat];
        // Sort by file then line
        sort!((a, b) {
            if (a.file != b.file) return a.file < b.file;
            return a.line < b.line;
        })(sites);

        md.put("| File:Line | Declaration | Rationale |\n");
        md.put("|---|---|---|\n");
        foreach (s; sites)
        {
            string decl = s.declaration;
            if (decl.length > 80) decl = decl[0 .. 77] ~ "...";
            decl = decl.escape;
            string r = s.rationale.length > 0 ? s.rationale.escape : "_(missing)_";
            if (r.length > 80) r = r[0 .. 77] ~ "...";
            md.put(format("| [`%s:%d`](../../%s#L%d) | `%s` | %s |\n",
                s.file, s.line, s.file, s.line, decl, r));
        }
        md.put("\n");
    }

    md.put("## Missing-rationale audit\n\n");
    int missing = 0;
    foreach (cat; cats)
        foreach (s; grouped[cat])
            if (s.rationale.length == 0) missing++;
    md.put(format("- **Sites without an inline rationale comment**: %d / %d (%.1f%%)\n", missing, total, missing * 100.0 / total));
    md.put("- Goal: every `@trusted` block has a `///` doc comment on the preceding line explaining why the trust is justified. Use this ledger to find the gaps.\n");
    md.put("- Process: when adding a new `@trusted` annotation, add a `///` line above it with the form `/// <why this @trusted is safe — invariant being asserted by the programmer>`.\n\n");

    md.put("## Regenerating\n\n");
    md.put("```sh\nldc2 -run tools/gen_trusted_ledger.d\n```\n\n");
    md.put("Re-run after any change that adds, removes, or moves a `@trusted` annotation. The script walks `source/`, groups by category (derived from the file path + signature), and writes this file.\n");

    write("docs/research/trusted-ledger.md", md.data);
    writeln("Wrote docs/research/trusted-ledger.md (", total, " sites, ", grouped.length, " categories, ", missing, " missing rationale)");
}

string descriptionFor(string cat) @safe
{
    switch (cat)
    {
    case "engine-FFI": return "Backend bindings (QuickJS / JSC / V8). `extern(C)` + `JSValueRef` value handles.";
    case "crypto-FFI": return "OpenSSL FFI — `@trusted` is the security signal for crypto code.";
    case "sqlite-FFI": return "ImportC bindings to libsqlite3.";
    case "quic-FFI": return "lsquic / QUIC + HTTP/3.";
    case "napi-FFI": return "N-API bindings (Node-compatible native addons).";
    case "SIMD/hot-path": return "`core.simd` + LDC intrinsics. Pointer arithmetic for codec hot paths.";
    case "event-loop": return "Cross-platform I/O poller, timer wheel, async work queue.";
    case "network-IO": return "POSIX socket syscalls, HTTP/HTTP2/WebSocket builtins, fetch.";
    case "fs-IO": return "POSIX file syscalls, child_process spawn / exec.";
    case "engine-bridge": return "Helpers that bridge `void* ctx` callbacks to typed `DunState*`.";
    case "hot-path": return "`@nogc nothrow` hot paths where `@safe` would block needed operations.";
    case "other": return "Miscellaneous — review for re-categorization opportunities.";
    default: return "";
    }
}

string escape(string s) @safe
{
    auto a = appender!string;
    foreach (c; s)
    {
        if (c == '|') a.put("\\|");
        else if (c == '`') a.put("\\`");
        else a.put(c);
    }
    return a.data;
}
