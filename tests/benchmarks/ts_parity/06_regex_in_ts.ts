// Regex literal disambiguation across TS contexts where the
// stripper must NOT confuse `<` (generic) with regex `/` boundary.
function parseHex<T extends string>(s: T): number {
  const m = s.match(/^0x([0-9a-fA-F]+)$/);
  return m ? parseInt(m[1], 16) : NaN;
}

// Regex containing `:` and `<` and `>` and `/`
const re = /^(?<scheme>[a-z]+):\/\/(?<host>[^/]+)\/(?<path>.*)$/;
const u = "https://example.com/foo/bar";
const m = re.exec(u);
console.log(m?.groups?.scheme, m?.groups?.host, m?.groups?.path);

// Generic call after a regex - confusing for naive scanners
const v = /(\d+)/.exec("abc 42 xyz");
const wrap = <T,>(x: T) => x;
console.log(v?.[1], wrap<number>(3));

// Division vs regex disambiguation
const x = 100;
const y = 4;
const div = x / y / 2;
console.log(div, parseHex("0xFF"));
