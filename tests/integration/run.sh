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

# --- REPL integration tests (piped input, non-TTY mode) ---
repl_fails=0

# Test 1: Basic eval + TypeScript type stripping
repl_out=$(printf '1+1\nlet x: number = 42; x\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q '> 2' && echo "$repl_out" | grep -q '> 42' || { echo "FAIL repl_eval"; repl_fails=1; }

# Test 2: _error captures errors
repl_out=$(printf 'badvar\n_error\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q 'ReferenceError' || { echo "FAIL repl_error"; repl_fails=1; }

# Test 3: Multi-line input with bracket matching
repl_out=$(printf 'let obj = {\na: 1,\nb: 2\n}\nobj\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q '"a": 1' || { echo "FAIL repl_multiline"; repl_fails=1; }

# Test 4: .help shows commands
repl_out=$(printf '.help\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q '.editor' && echo "$repl_out" | grep -q 'Ctrl+A' || { echo "FAIL repl_help"; repl_fails=1; }

# Test 5: .load + .save
echo 'const Z = 99;' > /tmp/dun_repl_test_load.js
repl_out=$(printf '.load /tmp/dun_repl_test_load.js\nZ\n.save /tmp/dun_repl_test_save.txt\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q 'Loaded' && echo "$repl_out" | grep -q '99' && echo "$repl_out" | grep -q 'saved' || { echo "FAIL repl_load_save"; repl_fails=1; }
rm -f /tmp/dun_repl_test_load.js /tmp/dun_repl_test_save.txt

# Test 6: --eval-file flag
echo 'const PRELOADED = "yes";' > /tmp/dun_repl_test_eval.js
repl_out=$(printf 'PRELOADED\n.exit\n' | "$DUN" repl --eval-file=/tmp/dun_repl_test_eval.js 2>/dev/null || true)
echo "$repl_out" | grep -q '"yes"' || { echo "FAIL repl_eval_file"; repl_fails=1; }
rm -f /tmp/dun_repl_test_eval.js

# Test 7: .break cancels incomplete input
repl_out=$(printf 'let x = {\n.break\n1+1\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q '> 2' || { echo "FAIL repl_break"; repl_fails=1; }

if [ "$repl_fails" -eq 0 ]; then
  echo "PASS repl_commands (7 checks)"
else
  fails=$((fails+1))
fi

exit $((fails > 0 ? 1 : 0))
