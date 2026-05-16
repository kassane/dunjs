#!/usr/bin/env bash
# Cross-runtime smoke test against real open-source TS projects. See
# README.md for project URLs / setup. Each project is probed via a
# minimal command (--help / --version); we report the exit code and
# the first line of output, not full execution.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DUN_ROOT="$HERE/../../.."
cd "$DUN_ROOT" || exit 1

RUNTIMES=(
  "bun:bun"
  "node:node"
  "deno:deno run -A"
  "dun-qjs:./dun-rel-qjs run --allow-all"
  "dun-jsc:./dun-rel-jsc run --allow-all"
  "dun-v8:./dun-rel-v8 run --allow-all"
)

# project: label, working-dir, entry-script, args
PROJECTS=(
  "n8n          | /tmp/n8n/packages/cli           | bin/n8n                      | --version"
  "gaia         | /tmp/gaia                       | scripts/bitcook/gaia.ts      | --help"
  "opencode     | /tmp/opencode/packages/opencode | src/index.ts                 | --version"
)

DUN_REL_QJS="$DUN_ROOT/dun-rel-qjs"
DUN_REL_JSC="$DUN_ROOT/dun-rel-jsc"
DUN_REL_V8="$DUN_ROOT/dun-rel-v8"

# Header
printf '%-12s' "project"
for rt in "${RUNTIMES[@]}"; do printf '%-12s' "${rt%%:*}"; done
echo
printf '%.0s-' {1..100}; echo

for p in "${PROJECTS[@]}"; do
  IFS='|' read -r label wd script args <<< "$p"
  # Trim whitespace without xargs (xargs misparses leading `--` as its
  # own flag and emits its --version banner).
  trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; echo "${s%"${s##*[![:space:]]}"}"; }
  label="$(trim "$label")"; wd="$(trim "$wd")"
  script="$(trim "$script")"; args="$(trim "$args")"
  if [ ! -d "$wd" ]; then
    printf '%-12s%s\n' "$label" "(not cloned, see README.md)"
    continue
  fi
  printf '%-12s' "$label"
  for rt in "${RUNTIMES[@]}"; do
    cmd="${rt#*:}"
    # Absolutize dun paths so cd doesn't break them
    cmd="${cmd//\.\/dun-rel-qjs/$DUN_REL_QJS}"
    cmd="${cmd//\.\/dun-rel-jsc/$DUN_REL_JSC}"
    cmd="${cmd//\.\/dun-rel-v8/$DUN_REL_V8}"
    binary="${cmd%% *}"
    if [ ! -x "$binary" ] && ! command -v "$binary" >/dev/null 2>&1; then
      printf '%-12s' "SKIP"; continue
    fi
    rc=0
    timeout 20 sh -c "cd '$wd' && $cmd '$script' $args" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "0" ]; then printf '%-12s' "PASS"
    else printf '%-12s' "FAIL"
    fi
  done
  echo
done
