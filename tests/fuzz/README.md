# DunJS fuzz harness

LDC's `-fsanitize=fuzzer` (libFuzzer, LLVM-backed) wired up for the
audit-surface modules most likely to take arbitrary user-supplied
bytes:

| Target | Source under test | What it asserts |
|---|---|---|
| `fuzz_strip` | `source/dun/ts/strip.d` + `source/dun/ts/parser/lexer.d` | TS type stripper preserves source positions (`stripped.length == src.length`) |
| `fuzz_simd` | `source/dun/platform/simd.d` (codecs) | latin1↔UTF-8 round-trip byte-exact + hex encoder output well-formed |
| `fuzz_url` | `source/dun/platform/url_parser.d` | `parseUrl(s)` returns a well-formed `ParsedUrl` or throws — never UB. `scheme.length > 0`, `path.length >= 1` |
| `fuzz_lexer` | `source/dun/ts/parser/lexer.d` | `hasSyntaxError`, `skipStringLit`, `skipTemplateLit` never read past `src.length` |
| `fuzz_paths` | `source/dun/platform/paths.d` (`canonicalizePath` + `isAlreadyCanonical` fast-path) | CVE-2023-32004 class — predicate's "canonical" verdict matches the full `buildNormalizedPath(absolutePath(...))` result on every input |

## Quick start

```sh
# Run every target for 60 seconds each (default)
tests/fuzz/run.sh

# Per-target time + glob filter
tests/fuzz/run.sh 300                 # 5 minutes per target
tests/fuzz/run.sh 60 fuzz_strip.d     # only strip
```

The runner builds each target with `-fsanitize=fuzzer,address`, runs it
against `tests/fuzz/corpus/<name>/`, and saves any crash artifact to
`tests/fuzz/crashes/<target>-<sha1>` for replay.

Exit code 0 = clean. Non-zero = at least one target found a crash (the
script will list the artifact paths).

## Adding a new target

1. Create `tests/fuzz/fuzz_<name>.d` with an `extern(C) int
   LLVMFuzzerTestOneInput(const(ubyte)* data, size_t size) nothrow`
   entry point. Catch `Exception` and `Error` to keep the fuzzer
   alive across assertion failures (crashes still get saved).
2. Add the seed corpus under `tests/fuzz/corpus/<name>/` (small
   example inputs that cover the expected shape).
3. Extend the `case` block in `tests/fuzz/run.sh` with the
   module dependencies the target needs:
   ```sh
   <name>)
       ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
            -I=source -Jsource \
            -of=build/${name} \
            "${fuzz_d}" \
            source/dun/<module>.d
       ;;
   ```

## Why these targets

Per the [v1.1.26 audit](../../docs/research/bun-unsafe-audit-vs-dunjs.md)
§7 "where DunJS would fail Bun's audit," the highest-leverage
fuzz targets shipped are:

- **Type stripper** — parses untrusted source. Position-tracking bugs
  silently corrupt source maps + stack traces. Audit pass already
  covered the scanner-level lexer, but fuzzing explores combinations
  of generics + decorators + JSX + nullish coalescing that hand-written
  fixtures can't enumerate.
- **SIMD codec** — `@trusted` pointer arithmetic, takes arbitrary
  byte slices. The v1.1.3 + v1.1.4 audits caught real high-byte
  preservation bugs in this path (`audit_simd`, `audit_roundtrip`
  fixtures). Fuzz the same surface with random byte patterns +
  SIMD-boundary lengths (15/16/17/31/32/33 bytes).
- **Path canonicalization** — `dun.platform.paths.canonicalizePath`
  is the CVE-2023-32004 / CVE-2024-21896 gate. v1.1.27 added an
  `isAlreadyCanonical` predicate fast-path; `fuzz_paths` asserts the
  predicate's verdict matches `buildNormalizedPath(absolutePath(...))`
  on every input — a false-positive in the predicate would skip the
  canonicalize step and break the CVE class.
- **URL + lexer** — adversarial inputs reach the URL parser via every
  `fetch(...)` and the lexer via every `.ts` load. Both already passed
  hand-written audits; fuzzing fills the long-tail combinations.

Future targets (call-out for follow-up PRs):

- `fuzz_json` — `source/dun/builtins/json*` if any custom
  serialization ships. (Phobos's `std.json` is the reference, but
  if DunJS adds a Fast-JSON path, it'd want coverage.)
- `fuzz_buffer` — `Buffer.from(str, encoding)` across all 6
  encodings + `Buffer.write/slice/concat`. Some of this is covered
  by the `audit_roundtrip` integration fixture; fuzzing would
  extend it.

## Reference

Johan Engelen's writeup is the canonical D-fuzzing reference:
<https://johanengelen.github.io/posts/2018-01-14-fuzzing-with-ldc/>

LLVM libFuzzer flags reference:
<https://llvm.org/docs/LibFuzzer.html>
