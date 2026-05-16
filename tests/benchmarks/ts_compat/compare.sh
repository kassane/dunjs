#!/usr/bin/env bash
# Cross-runtime TS compat comparison. Runs each .ts/.tsx under this
# directory on Bun, Node, Deno, and the three DunJS backends, then
# prints a per-file pass/fail grid plus the runtime's last line of
# output (typically the "all OK" sentinel or the first error).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../../.." || exit 1
DIR="$HERE"
RUNTIMES=(
  "bun:bun run"
  "node:node"
  "deno:deno run -A"
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8:./dun-rel-v8 run --allow-all"
)
# Header
printf '%-18s' "file"
for rt in "${RUNTIMES[@]}"; do printf '%-10s' "${rt%%:*}"; done
echo
printf '%.0s-' {1..82}; echo
for f in "$DIR"/*.ts "$DIR"/*.tsx; do
  [ -f "$f" ] || continue
  printf '%-18s' "$(basename "$f")"
  for rt in "${RUNTIMES[@]}"; do
    cmd="${rt#*:}"
    if ! command -v "${cmd%% *}" >/dev/null 2>&1 && [ ! -x "${cmd%% *}" ]; then
      printf '%-10s' "SKIP"; continue
    fi
    out=$(timeout 20 $cmd "$f" 2>&1)
    rc=$?
    # Treat exit-0 as PASS. If the last line of output contains the
    # canonical "all OK" / "All ... OK" / "✓" sentinel, count it as
    # PASS too -- some scripts test optional APIs and exit non-zero
    # while still demonstrating "the rest works".
    last=$(echo "$out" | tail -1)
    if [ "$rc" = "0" ]; then
      printf '%-10s' "PASS"
    elif echo "$last" | grep -qiE "(all OK|all .* OK|✓ )"; then
      printf '%-10s' "PARTIAL"
    else
      printf '%-10s' "FAIL"
    fi
  done
  echo
done
