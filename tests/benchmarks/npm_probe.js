const pkgs = [
  "lodash", "underscore", "ramda", "moment", "ms", "escape-html", "bytes",
  "cookie", "content-type", "validator", "depd", "fast-deep-equal",
  "is-plain-object", "deepmerge", "retry", "eventemitter3",
  "fast-json-stable-stringify", "punycode", "he",
  "sprintf-js", "js-yaml", "toml", "ini",
  "lz-string", "pako", "object-hash", "murmurhash-js", "fnv-plus",
  "safe-stable-stringify", "json5", "hjson", "diff",
  "string-similarity", "rfdc", "kind-of", "is-number",
  "slugify", "pluralize", "cssesc", "clean-css",
  "html-entities", "color-convert", "color-string",
  "lru-cache", "json-schema-traverse", "clone-deep",
  "linkify-it", "color-name", "media-typer", "mime-types",
  "mime-db", "js-beautify"
];
let ok = 0, fail = 0;
for (const name of pkgs) {
  try {
    const m = require(name);
    const t = typeof m;
    if (t === "function" || t === "object") { ok++; }
    else { fail++; console.log("WRONG TYPE: " + name + " = " + t); }
  } catch(e) {
    fail++;
    console.log("FAIL: " + name + " (" + (e.message || "").substring(0, 50) + ")");
  }
}
console.log("\n" + ok + "/" + (ok+fail) + " packages load successfully");
