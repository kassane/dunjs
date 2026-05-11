#!/usr/bin/env bash
set -euo pipefail
DUN=${DUN:-./build/dun}
FIXTURES=tests/integration/fixtures
EXPECTED=tests/integration/expected
fails=0

for fixture in "$FIXTURES"/*.js "$FIXTURES"/*.ts "$FIXTURES"/*.mjs; do
  [ -f "$fixture" ] || continue
  name=$(basename "${fixture%.*}")
  stdout_exp="$EXPECTED/${name}.txt"
  stderr_exp="$EXPECTED/${name}.stderr"
  flags_file="$FIXTURES/${name}.flags"

  # Skip fixtures that have neither expected stdout nor expected stderr
  { [ -f "$stdout_exp" ] || [ -f "$stderr_exp" ]; } || continue

  # Read per-fixture flags (e.g. --allow-read)
  extra_flags=""
  if [ -f "$flags_file" ]; then
    extra_flags=$(cat "$flags_file")
  fi

  # shellcheck disable=SC2086
  actual_out=$("$DUN" run $extra_flags "$fixture" 2>/tmp/dun_stderr.txt || true)
  actual_err=$(cat /tmp/dun_stderr.txt)

  if [ -f "$stderr_exp" ]; then
    # stderr sidecar present: assert stderr matches, accept any exit code
    if ! diff -u "$stderr_exp" <(printf '%s\n' "$actual_err") >/dev/null 2>&1; then
      echo "FAIL (stderr) $name"
      diff -u "$stderr_exp" <(printf '%s\n' "$actual_err") || true
      fails=$((fails+1)); continue
    fi
  fi

  if [ -f "$stdout_exp" ]; then
    if ! diff -u "$stdout_exp" <(printf '%s\n' "$actual_out") >/dev/null 2>&1; then
      echo "FAIL (stdout) $name"
      diff -u "$stdout_exp" <(printf '%s\n' "$actual_out") || true
      fails=$((fails+1)); continue
    fi
  fi

  echo "PASS $name"
done

exit $((fails > 0 ? 1 : 0))
