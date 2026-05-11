#!/usr/bin/env bash
set -euo pipefail
DUN=${DUN:-./build/dun}
# Auto-detect backend from binary strings if not set explicitly
if [ -z "${BACKEND:-}" ]; then
  _engine=$(strings "$DUN" 2>/dev/null | grep -oE '\b(QuickJS|JavaScriptCore|V8)\b' | head -1)
  case "$_engine" in
    JavaScriptCore) BACKEND=jsc ;;
    V8)             BACKEND=v8 ;;
    *)              BACKEND=quickjs ;;
  esac
fi
FIXTURES=tests/integration/fixtures
EXPECTED=tests/integration/expected
fails=0

for fixture in "$FIXTURES"/*.js "$FIXTURES"/*.ts "$FIXTURES"/*.mjs; do
  [ -f "$fixture" ] || continue
  name=$(basename "${fixture%.*}")
  stdout_exp="$EXPECTED/${name}.txt"
  stderr_exp="$EXPECTED/${name}.stderr"
  flags_file="$FIXTURES/${name}.flags"
  backends_file="$FIXTURES/${name}.backends"

  # Skip fixtures that have neither expected stdout nor expected stderr
  { [ -f "$stdout_exp" ] || [ -f "$stderr_exp" ]; } || continue

  # Skip if this fixture is not supported by the current backend
  if [ -f "$backends_file" ]; then
    if ! grep -qw "$BACKEND" "$backends_file"; then
      echo "SKIP $name"
      continue
    fi
  fi

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
