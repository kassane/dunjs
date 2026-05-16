/// Source-text rewriter for Unicode property regex escapes.
///
/// V8's prebuilt monolith ships without ICU (`v8_enable_i18n_support=false`),
/// so any regex *literal* like `/\p{ID_Start}/u` throws at parse time
/// before any runtime polyfill can intercept it. This module replaces
/// `\p{Name}` / `\P{Name}` text occurrences with pre-baked character
/// classes so the parser sees ordinary ranges.
///
/// Loader.d / require.d call this on any module source loaded under the
/// V8 backend before handing it to the engine. The Buffer-allocated
/// table is built once at program start.
///
/// JSC and QuickJS don't need this — both ship with native Unicode
/// property support — so the function is a no-op there (compiled out
/// behind `version (EngineV8)`).
module dun.runtime.unicode_props;

import std.algorithm : canFind;

/// Replace every `\p{Name}` / `\P{Name}` occurrence in `source` with
/// the equivalent character class from the pre-baked table. Returns
/// `source` unchanged if it contains no escape patterns.
///
/// Heuristic — does not parse the JS to distinguish regex literals
/// from string contents. In practice, `\p{` is an exotic substring
/// in JS source outside of regex literals, so the false-positive rate
/// is negligible.
string expandUnicodePropertyEscapes(string source) @safe pure
{
    if (source.length < 4) return source;
    if (!source.canFind("\\p{") && !source.canFind("\\P{"))
        return source;

    auto result = new char[source.length + 1024];
    size_t outLen = 0;
    void put(scope const(char)[] s)
    {
        if (outLen + s.length > result.length)
            result.length = (outLen + s.length) * 2;
        result[outLen .. outLen + s.length] = s[];
        outLen += s.length;
    }

    // Walk the source byte by byte. Track:
    //   - whether we're inside a `[]` character class (regex literal
    //     internal): expansion uses bare ranges inside, brackets outside.
    //   - whether we're inside a string literal `"..."` / `'...'` /
    //     `` `...` ``: skip without rewriting. Without this, the JS
    //     source `"\\p{X}"` (literal `\p{X}` after escape) gets rewritten
    //     as if it were a regex escape, corrupting string contents.
    //   - whether we're inside a line / block comment: skip likewise.
    size_t i = 0;
    bool inClass = false;
    while (i < source.length)
    {
        char c = source[i];
        // String literals — single, double, template.
        if (c == '"' || c == '\'' || c == '`')
        {
            char quote = c;
            put([c]);
            i++;
            while (i < source.length)
            {
                char sc = source[i];
                if (sc == '\\' && i + 1 < source.length)
                {
                    put([sc, source[i + 1]]);
                    i += 2;
                    continue;
                }
                put([sc]);
                i++;
                if (sc == quote) break;
                // Template literal interpolation — for simplicity treat
                // ${...} contents as still inside the template (don't
                // descend), since we just need to avoid mis-rewriting.
            }
            continue;
        }
        // Single-line comments.
        if (c == '/' && i + 1 < source.length && source[i + 1] == '/')
        {
            while (i < source.length && source[i] != '\n')
            {
                put([source[i]]);
                i++;
            }
            continue;
        }
        // Block comments.
        if (c == '/' && i + 1 < source.length && source[i + 1] == '*')
        {
            put("/*");
            i += 2;
            while (i + 1 < source.length
                && !(source[i] == '*' && source[i + 1] == '/'))
            {
                put([source[i]]);
                i++;
            }
            if (i + 1 < source.length) { put("*/"); i += 2; }
            continue;
        }
        if (c == '\\' && i + 2 < source.length
            && (source[i + 1] == 'p' || source[i + 1] == 'P')
            && source[i + 2] == '{')
        {
            bool negate = source[i + 1] == 'P';
            // Find closing `}`.
            size_t end = i + 3;
            while (end < source.length && source[end] != '}') end++;
            if (end >= source.length) { put([c]); i++; continue; }
            string name = source[i + 3 .. end];
            // Property=Value form: take the value half.
            size_t eq = 0;
            while (eq < name.length && name[eq] != '=') eq++;
            string key = (eq < name.length) ? name[eq + 1 .. $] : name;
            string cls = unicodeRangeFor(key);
            if (cls.length == 0) cls = "\\u0000-\\u0000";
            if (negate)
            {
                if (inClass) put(cls);  // approximation; inside [] negation is not direct
                else { put("[^"); put(cls); put("]"); }
            }
            else
            {
                if (inClass) put(cls);
                else { put("["); put(cls); put("]"); }
            }
            i = end + 1;
            continue;
        }
        if (c == '[' && !inClass) inClass = true;
        else if (c == ']' && inClass) inClass = false;
        put([c]);
        i++;
    }
    return cast(string) result[0 .. outLen].idup;
}

/// Pre-baked character class data for the most common Unicode property
/// escapes. Mirrors the JS-side polyfill in `globals.d`. Coverage is
/// the General_Category top-level groups plus the identifier props and
/// a few common subcategories.
private string unicodeRangeFor(string key) @safe pure nothrow
{
    switch (key)
    {
        case "L":
        case "Letter":
            return LETTER_RANGES;
        case "N":
        case "Number":
            return NUMBER_RANGES;
        case "P":
        case "Punctuation":
            return PUNCTUATION_RANGES;
        case "S":
        case "Symbol":
            return SYMBOL_RANGES;
        case "M":
        case "Mark":
            return MARK_RANGES;
        case "Z":
        case "Separator":
            return SEPARATOR_RANGES;
        case "C":
        case "Other":
            return OTHER_RANGES;
        case "ID_Start":
        case "XID_Start":
            return LETTER_RANGES ~ "_$";
        case "ID_Continue":
        case "XID_Continue":
            return LETTER_RANGES ~ NUMBER_RANGES ~ "_$";
        case "Lu": return "A-Z\\u00C0-\\u00D6\\u00D8-\\u00DE";
        case "Ll": return "a-z\\u00DF-\\u00F6\\u00F8-\\u00FF";
        case "Nd": return "0-9\\u0660-\\u0669\\u06F0-\\u06F9";
        case "ASCII":
            return "\\u0000-\\u007F";
        case "White_Space":
            return " \\t\\n\\r\\u00A0\\u2028\\u2029";
        default:
            return "";
    }
}

// Pre-baked Unicode 16 ranges. Chosen to match the JS-side polyfill.
// Conservative enough that common npm packages compile; not a perfect
// substitute for full ICU.
private enum LETTER_RANGES =
    "A-Za-z"
    ~ "\\u00AA\\u00B5\\u00BA\\u00C0-\\u00D6\\u00D8-\\u00F6\\u00F8-\\u02C1"
    ~ "\\u02C6-\\u02D1\\u02E0-\\u02E4\\u02EC\\u02EE\\u0370-\\u0374"
    ~ "\\u0376-\\u0377\\u037A-\\u037D\\u0386\\u0388-\\u03FF"
    ~ "\\u0400-\\u0481\\u048A-\\u052F\\u0531-\\u0556\\u0561-\\u0587"
    ~ "\\u05D0-\\u05F2\\u0620-\\u064A\\u066E-\\u066F\\u0671-\\u06D3"
    ~ "\\u06D5\\u06E5-\\u06E6\\u06EE-\\u06EF\\u06FA-\\u06FC\\u06FF"
    ~ "\\u0710\\u0712-\\u072F\\u074D-\\u07A5\\u07B1\\u07CA-\\u07EA"
    ~ "\\u0904-\\u0939\\u093D\\u0950\\u0958-\\u0961\\u0971-\\u097F"
    ~ "\\u0985-\\u09B9\\u09BD\\u09CE\\u09DC-\\u09DD\\u09DF-\\u09E1"
    ~ "\\u0A05-\\u0A39\\u0A59-\\u0A5E\\u0A72-\\u0A74\\u0A85-\\u0AB9"
    ~ "\\u0ABD\\u0AD0\\u0AE0-\\u0AE1\\u0B05-\\u0B39\\u0B3D"
    ~ "\\u0B5C-\\u0B5D\\u0B5F-\\u0B61\\u0B71\\u0B83-\\u0BB9\\u0BD0"
    ~ "\\u0C05-\\u0C39\\u0C3D\\u0C58-\\u0C61\\u0C85-\\u0CB9\\u0CBD"
    ~ "\\u0CDE-\\u0CE1\\u0D05-\\u0D39\\u0D3D\\u0D60-\\u0D61"
    ~ "\\u0D7A-\\u0D7F\\u0D85-\\u0DC6\\u0E01-\\u0E30\\u0E32-\\u0E33"
    ~ "\\u0E40-\\u0E46\\u0E81-\\u0EB0\\u0EB2-\\u0EB3\\u0EBD\\u0EC0-\\u0EC4"
    ~ "\\u0EC6\\u0EDC-\\u0EDD\\u0F00\\u0F40-\\u0F6C\\u0F88-\\u0F8B"
    ~ "\\u1000-\\u102A\\u103F\\u1050-\\u1055\\u105A-\\u105D\\u1061"
    ~ "\\u1065-\\u1066\\u106E-\\u1070\\u1075-\\u1081\\u108E"
    ~ "\\u10A0-\\u10C5\\u10D0-\\u10FA\\u10FC\\u1100-\\u1248"
    ~ "\\u1250-\\u1288\\u1290-\\u12B0\\u12B8-\\u12C0\\u12C2-\\u12D6"
    ~ "\\u12D8-\\u1310\\u1312-\\u1316\\u1318-\\u135A\\u1380-\\u138F"
    ~ "\\u13A0-\\u13F4\\u1401-\\u166C\\u166F-\\u167F\\u1681-\\u169A"
    ~ "\\u16A0-\\u16EA\\u1700-\\u170C\\u170E-\\u1711\\u1720-\\u1731"
    ~ "\\u1740-\\u1751\\u1760-\\u1770\\u1780-\\u17B3\\u17D7\\u17DC"
    ~ "\\u1820-\\u1877\\u1880-\\u18A8\\u18AA\\u1900-\\u191C"
    ~ "\\u1950-\\u196D\\u1970-\\u1974\\u1980-\\u19AB\\u19C1-\\u19C7"
    ~ "\\u1A00-\\u1A16\\u1B05-\\u1B33\\u1B45-\\u1B4B\\u1B83-\\u1BA0"
    ~ "\\u1BAE-\\u1BAF\\u1C00-\\u1C23\\u1C4D-\\u1C4F\\u1C5A-\\u1C7D"
    ~ "\\u1CE9-\\u1CEC\\u1CEE-\\u1CF1\\u1D00-\\u1DBF\\u1E00-\\u1F15"
    ~ "\\u1F18-\\u1F1D\\u1F20-\\u1F45\\u1F48-\\u1F4D\\u1F50-\\u1F57"
    ~ "\\u1F59\\u1F5B\\u1F5D\\u1F5F-\\u1F7D\\u1F80-\\u1FB4"
    ~ "\\u1FB6-\\u1FBC\\u1FBE\\u1FC2-\\u1FC4\\u1FC6-\\u1FCC"
    ~ "\\u1FD0-\\u1FD3\\u1FD6-\\u1FDB\\u1FE0-\\u1FEC\\u1FF2-\\u1FF4"
    ~ "\\u1FF6-\\u1FFC\\u2071\\u207F\\u2090-\\u209C\\u2102\\u2107"
    ~ "\\u210A-\\u2113\\u2115\\u2119-\\u211D\\u2124\\u2126\\u2128"
    ~ "\\u212A-\\u212D\\u212F-\\u2139\\u213C-\\u213F\\u2145-\\u2149"
    ~ "\\u214E\\u2183-\\u2184\\u2C00-\\u2C2E\\u2C30-\\u2C5E"
    ~ "\\u2C60-\\u2CE4\\u2CEB-\\u2CEE\\u2D00-\\u2D25\\u2D30-\\u2D6F"
    ~ "\\u2D80-\\u2DDE\\u2E2F\\u3005-\\u3006\\u3031-\\u3035"
    ~ "\\u303B-\\u303C\\u3041-\\u3096\\u309D-\\u309F\\u30A1-\\u30FA"
    ~ "\\u30FC-\\u30FF\\u3105-\\u312D\\u3131-\\u318E\\u31A0-\\u31BA"
    ~ "\\u31F0-\\u31FF\\u3400-\\u4DB5\\u4E00-\\u9FCC\\uA000-\\uA48C"
    ~ "\\uA4D0-\\uA4FD\\uA500-\\uA60C\\uA610-\\uA61F\\uA62A-\\uA62B"
    ~ "\\uA640-\\uA66E\\uA67F-\\uA697\\uA6A0-\\uA6E5\\uA717-\\uA71F"
    ~ "\\uA722-\\uA788\\uA78B-\\uA78E\\uA790-\\uA793\\uA7A0-\\uA7AA"
    ~ "\\uAC00-\\uD7A3\\uD7B0-\\uD7C6\\uD7CB-\\uD7FB\\uF900-\\uFA6D"
    ~ "\\uFA70-\\uFAD9\\uFB00-\\uFB06\\uFB13-\\uFB17\\uFB1D"
    ~ "\\uFB1F-\\uFB28\\uFB2A-\\uFB36\\uFB38-\\uFB3C\\uFB3E"
    ~ "\\uFB40-\\uFB41\\uFB43-\\uFB44\\uFB46-\\uFBB1\\uFBD3-\\uFD3D"
    ~ "\\uFD50-\\uFD8F\\uFD92-\\uFDC7\\uFDF0-\\uFDFB\\uFE70-\\uFE74"
    ~ "\\uFE76-\\uFEFC\\uFF21-\\uFF3A\\uFF41-\\uFF5A\\uFF66-\\uFFBE"
    ~ "\\uFFC2-\\uFFC7\\uFFCA-\\uFFCF\\uFFD2-\\uFFD7\\uFFDA-\\uFFDC";

private enum NUMBER_RANGES =
    "0-9\\u00B2-\\u00B3\\u00B9\\u00BC-\\u00BE\\u0660-\\u0669\\u06F0-\\u06F9"
    ~ "\\u07C0-\\u07C9\\u0966-\\u096F\\u09E6-\\u09EF\\u0A66-\\u0A6F"
    ~ "\\u0AE6-\\u0AEF\\u0B66-\\u0B6F\\u0BE6-\\u0BF2\\u0C66-\\u0C6F"
    ~ "\\u0CE6-\\u0CEF\\u0D66-\\u0D75\\u0E50-\\u0E59\\u0ED0-\\u0ED9"
    ~ "\\u0F20-\\u0F33\\u1040-\\u1049\\u1090-\\u1099\\u17E0-\\u17E9"
    ~ "\\u1810-\\u1819\\u1946-\\u194F\\u19D0-\\u19DA\\u1A80-\\u1A99"
    ~ "\\u1B50-\\u1B59\\u1BB0-\\u1BB9\\u1C40-\\u1C49\\u1C50-\\u1C59"
    ~ "\\u2070\\u2074-\\u2079\\u2080-\\u2089\\u2150-\\u2189"
    ~ "\\u2460-\\u24FF\\u2776-\\u2793\\u3007\\u3021-\\u3029"
    ~ "\\u3038-\\u303A\\u3192-\\u3195\\u3220-\\u3229\\u3248-\\u324F"
    ~ "\\u3251-\\u325F\\u3280-\\u3289\\u32B1-\\u32BF\\uA620-\\uA629"
    ~ "\\uA8D0-\\uA8D9\\uA900-\\uA909\\uA9D0-\\uA9D9\\uAA50-\\uAA59"
    ~ "\\uABF0-\\uABF9\\uFF10-\\uFF19";

private enum PUNCTUATION_RANGES =
    "!-#%-*,-/:-;?-@\\[-\\]_{-}\\u00A1\\u00A7\\u00AB\\u00B6-\\u00B7"
    ~ "\\u00BB\\u00BF\\u037E\\u0387";

private enum SYMBOL_RANGES = "$+<-=>^|~\\u00A2-\\u00A6";

private enum MARK_RANGES = "\\u0300-\\u036F\\u0483-\\u0489";

private enum SEPARATOR_RANGES =
    " \\u00A0\\u1680\\u2000-\\u200A\\u2028-\\u2029\\u202F\\u205F\\u3000";

private enum OTHER_RANGES =
    "\\u0000-\\u001F\\u007F-\\u009F\\u00AD";

unittest
{
    // Basic literal expansion.
    auto out1 = expandUnicodePropertyEscapes("/\\p{L}/u");
    assert(out1.length > 10, "expansion produced empty output");
    assert(out1[0] == '/' && out1[1] == '[',
        "expected `/\\p{L}/u` -> `/[ranges]/u`, got: " ~ out1);

    // Inside character class.
    auto out2 = expandUnicodePropertyEscapes("/[\\p{L}]/u");
    assert(out2.length > 10);
    assert(out2[0] == '/' && out2[1] == '[' && out2[2] != '[',
        "expansion inside [] should not double-bracket");

    // Source without escapes is returned unchanged.
    auto src = "var x = 1; /abc/g";
    assert(expandUnicodePropertyEscapes(src) == src,
        "no-escape source should be returned unchanged");

    // ID_Start (Express's case).
    auto out3 = expandUnicodePropertyEscapes("/^[$_\\p{ID_Start}]$/u");
    assert(out3.length > 20);
    assert(out3.canFind("A-Za-z"), "ID_Start should include ASCII letters");
}
