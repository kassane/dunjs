// Regex literals next to TS type annotations. Before strip.d became
// regex-aware (via dun.ts.parser.lexer), a `/` inside the right-hand
// side of an assignment was walked byte-by-byte, so a body like
// `/a:b<c>/` could collide with the strip-mode heuristics for class
// fields or generic call sites.

function isEmail(s: string): boolean {
    // `return /.../` -- the regex-allowing keyword path. Before the
    // keyword check, "return" ended in `n` (an ident-cont byte) and
    // strip would have treated `/` as divide.
    return /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/.test(s);
}

function isHHMM(t: string): boolean {
    // Regex body contains `:` -- mustn't be mistaken for a type colon.
    return /^[0-2][0-9]:[0-5][0-9]$/.test(t);
}

function hasTag(html: string): boolean {
    // Regex with `<...>` -- mustn't trip the generic-call detector.
    return /<[a-z]+>/.test(html);
}

const re1: RegExp = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/;
const re2 = /\b(?:foo|bar)\b/gi;

// Multiline: regex on RHS over multiple lines.
const match: RegExpMatchArray | null = "abc"
    .match(/[a-c]/);

console.log(JSON.stringify({
    email: isEmail("a@b.co"),
    hhmm: isHHMM("12:34"),
    html: hasTag("<p>hi</p>"),
    year: "2026-05-17".match(re1)?.groups?.year,
    foos: "foo bar Foo".match(re2)?.length,
    matchLen: match?.length,
}));
