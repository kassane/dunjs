#!/usr/bin/env bash
# Cross-runtime TS conformance check.
#
# Compares stdout of each .ts/.tsx fixture against the canonical
# `expected/<name>.txt` (generated via `tsc + node`) for every
# available runtime. PASS if output matches byte-for-byte after
# normalization (trim trailing newline; collapse CRLF -> LF).
#
# Usage:  bash tests/benchmarks/ts_parity/run.sh
#         GRID=1 bash tests/benchmarks/ts_parity/run.sh    # grid output
#
# Exit non-zero if any runtime fails any fixture.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../../.."
cd "$ROOT" || exit 1

readonly EXPECTED_DIR="$HERE/expected"
readonly TIMEOUT_SECS=20
readonly TMP_OUT_DIR="${TMPDIR:-/tmp}/dun-ts-parity-$$"
mkdir -p "$TMP_OUT_DIR"
trap 'rm -rf "$TMP_OUT_DIR"' EXIT

# Runtime entries:  label:command (file appended)
# tsc+node runs through a fresh transpile (the gold reference);
# bun/deno/dun-* run .ts directly via their built-in strippers.
RUNTIMES=(
  "tsc+node:__TSC_NODE__"
  "bun:bun run"
  "deno:deno run -A"
  "node-ts:node --experimental-strip-types"
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8:./dun-rel-v8 run --allow-all"
)

# Run tsc to transpile a single file into TMP_OUT_DIR, then node it.
# Cached on first call per file so the bench doesn't pay tsc cost twice.
tsc_node_run() {
  local src="$1"
  local stem
  stem=$(basename "${src%.*}")
  local cached="$TMP_OUT_DIR/$stem.js"
  if [ ! -f "$cached" ]; then
    tsc --target ES2022 --module ESNext --moduleResolution node \
        --jsx react --esModuleInterop --skipLibCheck \
        --strict false --ignoreDeprecations 6.0 \
        --outDir "$TMP_OUT_DIR" "$src" >/dev/null 2>&1
    if [ ! -f "$cached" ]; then return 1; fi
  fi
  node --input-type=module -e "$(cat "$cached")"
}

normalize() {
  # Strip trailing newlines + collapse CRLF
  sed 's/\r$//' | awk 'BEGIN{p=""} {if(NR>1)print p; p=$0} END{print p}'
}

is_runtime_available() {
  local entry="$1"
  local cmd="${entry#*:}"
  if [ "$cmd" = "__TSC_NODE__" ]; then
    command -v tsc >/dev/null && command -v node >/dev/null
  else
    local bin="${cmd%% *}"
    command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]
  fi
}

run_one() {
  local entry="$1" src="$2"
  local cmd="${entry#*:}"
  local out
  if [ "$cmd" = "__TSC_NODE__" ]; then
    out=$(timeout "$TIMEOUT_SECS" bash -c "$(declare -f tsc_node_run); TMP_OUT_DIR='$TMP_OUT_DIR' tsc_node_run '$src'" 2>&1)
  else
    out=$(timeout "$TIMEOUT_SECS" $cmd "$src" 2>&1)
  fi
  printf '%s' "$out"
}

# ---- harness ----
fixtures=()
for f in "$HERE"/*.ts "$HERE"/*.tsx; do
  [ -f "$f" ] || continue
  fixtures+=("$f")
done

total_pass=0
total_fail=0
total_skip=0
declare -A rt_pass rt_fail

if [ "${GRID:-0}" = "1" ]; then
  printf '%-26s' "fixture"
  for entry in "${RUNTIMES[@]}"; do printf '%-10s' "${entry%%:*}"; done
  echo
  printf -- '-%.0s' $(seq 1 $((26 + 10 * ${#RUNTIMES[@]})))
  echo
fi

for src in "${fixtures[@]}"; do
  name=$(basename "$src")
  stem="${name%.*}"
  expected_file="$EXPECTED_DIR/$stem.txt"

  if [ ! -f "$expected_file" ]; then
    printf 'WARN  %s : no expected/ file\n' "$name"
    continue
  fi
  expected=$(cat "$expected_file" | normalize)

  if [ "${GRID:-0}" = "1" ]; then printf '%-26s' "$name"; fi

  for entry in "${RUNTIMES[@]}"; do
    rt="${entry%%:*}"
    if ! is_runtime_available "$entry"; then
      [ "${GRID:-0}" = "1" ] && printf '%-10s' "SKIP"
      total_skip=$((total_skip + 1))
      continue
    fi
    actual=$(run_one "$entry" "$src" | normalize)
    if [ "$actual" = "$expected" ]; then
      [ "${GRID:-0}" = "1" ] && printf '%-10s' "PASS"
      rt_pass[$rt]=$((${rt_pass[$rt]:-0} + 1))
      total_pass=$((total_pass + 1))
    else
      [ "${GRID:-0}" = "1" ] && printf '%-10s' "FAIL"
      rt_fail[$rt]=$((${rt_fail[$rt]:-0} + 1))
      total_fail=$((total_fail + 1))
      if [ "${VERBOSE:-0}" = "1" ]; then
        echo
        echo "  --- $rt expected ---"
        echo "$expected" | head -5
        echo "  --- $rt actual ---"
        echo "$actual" | head -5
      fi
    fi
  done
  if [ "${GRID:-0}" = "1" ]; then echo; fi
done

echo
echo "Per-runtime totals:"
for entry in "${RUNTIMES[@]}"; do
  rt="${entry%%:*}"
  p=${rt_pass[$rt]:-0}
  f=${rt_fail[$rt]:-0}
  printf '  %-10s %d pass / %d fail\n' "$rt" "$p" "$f"
done
echo
echo "TOTAL  $total_pass pass / $total_fail fail / $total_skip skip"

[ "$total_fail" -eq 0 ]
