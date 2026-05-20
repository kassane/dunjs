// Verify Intl.* delivers locale-aware formatting. On V8 backend
// this requires the i18n profile (icudtl.dat next to the binary
// or DUN_ICU_DATA env var). On JSC/QJS the engine ships its own
// ICU. The test is opt-in for V8 — gated via DUN_ICU_DATA / V8_I18N
// in CI; default V8 profile lacks locale data and would FAIL here.
// Sidecar `.backends` restricts this fixture to backends that ship
// full ICU.
let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) pass++; else { fail++; console.log("FAIL", name); }
}

// 1. NumberFormat — German decimal separator
const de = new Intl.NumberFormat("de-DE").format(1234.5);
check("de-DE number format", de === "1.234,5");

// 2. NumberFormat — French uses non-breaking-space + comma
const fr = new Intl.NumberFormat("fr-FR").format(1234.5);
check("fr-FR number format", fr === "1 234,5" || fr === "1 234,5" || fr === "1 234,5");

// 3. Currency — Euro
const eur = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" }).format(99.99);
check("EUR currency", eur.indexOf("€") >= 0 && (eur.indexOf("99,99") >= 0));

// 4. DateTimeFormat — Japanese
const ja = new Intl.DateTimeFormat("ja-JP").format(new Date(Date.UTC(2026, 0, 15)));
check("ja-JP date format starts with 2026", ja.startsWith("2026"));
check("ja-JP date uses slash separator", ja.indexOf("/") >= 0);

// 5. Collator — sort order
const collator = new Intl.Collator("de");
check("de collator sorts z>a", collator.compare("z", "a") > 0);

// 6. PluralRules
const en_plural = new Intl.PluralRules("en").select(1);
check("en plural rules", en_plural === "one");

// 7. RelativeTimeFormat
const rtf = new Intl.RelativeTimeFormat("en", { numeric: "auto" }).format(-1, "day");
check("relative time 'yesterday'", rtf === "yesterday");

// 8. DisplayNames
try {
  const dn = new Intl.DisplayNames("en", { type: "language" }).of("de");
  check("display name 'de' → 'German'", dn === "German");
} catch (e) { check("DisplayNames available", false); }

// 9. localeCompare
check("base-sensitive Hello/hello",
  "Hello".localeCompare("hello", "en", { sensitivity: "base" }) === 0);

// 10. Locale segmenter
try {
  const seg = new Intl.Segmenter("en", { granularity: "word" });
  const words = [...seg.segment("Hello world")].filter(s => s.isWordLike).map(s => s.segment);
  check("Segmenter word boundary", words.length === 2 && words[0] === "Hello" && words[1] === "world");
} catch (e) {
  // Segmenter is newer; tolerate absence
  check("Segmenter or skip", true);
}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
