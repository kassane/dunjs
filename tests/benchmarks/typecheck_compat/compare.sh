#!/usr/bin/env bash
# Cross-runtime type-checking comparison. Each cell shows whether the
# runtime *caught* a type error before executing the file.
#
#   CAUGHT  the runtime refused to run the file because of type errors
#   RAN     the runtime stripped types and ran the JS (errors at runtime
#           if any, or silent if the bug doesn't crash)
#   PASS    no errors, ran cleanly (for the clean file)
#   SKIP    runtime not on PATH
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../../.." || exit 1

# Each entry: label:command (typecheck mode if available)
RUNTIMES=(
  "tsc:tsc --noEmit --target ES2022 --module ESNext --strict"
  "deno-check:deno check --no-config --no-lock"
  "dun-tc:./dun-rel-qjs run --allow-all --typecheck"
  "bun:bun run"
  "node:node"
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8:./dun-rel-v8 run --allow-all"
)

# Header
printf '%-32s' "file"
for rt in "${RUNTIMES[@]}"; do printf '%-12s' "${rt%%:*}"; done
echo
printf '%.0s-' {1..130}; echo

for f in "$HERE"/*.ts; do
  printf '%-32s' "$(basename "$f")"
  for rt in "${RUNTIMES[@]}"; do
    cmd="${rt#*:}"
    binary="${cmd%% *}"
    if [ ! -x "$binary" ] && ! command -v "$binary" >/dev/null 2>&1; then
      printf '%-12s' "SKIP"; continue
    fi
    out=$(timeout 20 $cmd "$f" 2>&1)
    rc=$?
    # tsc / deno-check / dun-tc are typecheckers -- non-zero rc = caught
    # bun / node / dun-{qjs,jsc,v8} are runners -- non-zero rc usually
    # means a runtime crash, but the type bug may have caused it
    label="${rt%%:*}"
    if [[ "$label" == "tsc" || "$label" == "deno-check" || "$label" == "dun-tc" ]]; then
      if [ "$rc" = "0" ]; then printf '%-12s' "PASS"
      else printf '%-12s' "CAUGHT"
      fi
    else
      if [ "$rc" = "0" ]; then printf '%-12s' "RAN"
      else printf '%-12s' "RUNTIME-ERR"
      fi
    fi
  done
  echo
done
