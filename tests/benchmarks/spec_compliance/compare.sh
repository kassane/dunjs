#!/usr/bin/env bash
# Cross-runtime ECMAScript + TypeScript compliance audit. Runs the two
# fixture files under this directory on Bun, Node, Deno, and the three
# DunJS backends, then prints a grid of `passed/total`.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/../../.." || exit 1

RUNTIMES=(
  "bun:bun run"
  "node:node"
  "deno:deno run -A"
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8:./dun-rel-v8 run --allow-all"
)

run_one() {
  local cmd="$1"; local file="$2"; local marker="$3"
  local out
  if ! command -v "${cmd%% *}" >/dev/null 2>&1 && [ ! -x "${cmd%% *}" ]; then
    echo "SKIP"; return
  fi
  out=$(timeout 30 $cmd "$file" 2>&1 | grep -E "^${marker}:" | head -1)
  if [ -n "$out" ]; then
    echo "$out" | sed -E "s/^${marker}: //; s/ passed$//"
  else
    echo "FAIL"
  fi
}

printf '%-10s' "file"
for rt in "${RUNTIMES[@]}"; do printf '%-10s' "${rt%%:*}"; done
echo
printf '%.0s-' {1..70}; echo

printf '%-10s' "ecma"
for rt in "${RUNTIMES[@]}"; do
  printf '%-10s' "$(run_one "${rt#*:}" "$HERE/ecmascript.js" ecmascript_compliance)"
done
echo

printf '%-10s' "ts"
for rt in "${RUNTIMES[@]}"; do
  printf '%-10s' "$(run_one "${rt#*:}" "$HERE/typescript.ts" typescript_compliance)"
done
echo
