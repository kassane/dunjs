#!/usr/bin/env bash
set -euo pipefail
DUN=${DUN:-./build/dun}
# Auto-detect backend from dun --version output if not set explicitly
if [ -z "${BACKEND:-}" ]; then
  _engine=$("$DUN" --version 2>/dev/null | grep -oE '(QuickJS|JavaScriptCore|V8)' | head -1)
  case "$_engine" in
    JavaScriptCore) BACKEND=jsc ;;
    V8)             BACKEND=v8 ;;
    *)              BACKEND=quickjs ;;
  esac
fi
FIXTURES=tests/integration/fixtures
EXPECTED=tests/integration/expected
fails=0

for fixture in "$FIXTURES"/*.js "$FIXTURES"/*.ts "$FIXTURES"/*.mjs "$FIXTURES"/*.tsx "$FIXTURES"/*.jsx; do
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
  actual_out=$(timeout ${DUN_TEST_TIMEOUT:-30} "$DUN" run $extra_flags "$fixture" 2>/tmp/dun_stderr.txt || true)
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
echo "$repl_out" | grep -q 'a: 1' || { echo "FAIL repl_multiline"; repl_fails=1; }

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
echo "$repl_out" | grep -q "'yes'" || { echo "FAIL repl_eval_file"; repl_fails=1; }
rm -f /tmp/dun_repl_test_eval.js

# Test 7: .break cancels incomplete input
repl_out=$(printf 'let x = {\n.break\n1+1\n.exit\n' | "$DUN" repl 2>/dev/null || true)
echo "$repl_out" | grep -q '> 2' || { echo "FAIL repl_break"; repl_fails=1; }

if [ "$repl_fails" -eq 0 ]; then
  echo "PASS repl_commands (7 checks)"
else
  fails=$((fails+1))
fi

# --- CLI feature tests ---
cli_fails=0

# Test: dun eval
cli_out=$("$DUN" eval '1+2' 2>&1 || true)
echo "$cli_out" | grep -q '^3$' || { echo "FAIL cli_eval"; cli_fails=1; }

# Test: dun version
cli_out=$("$DUN" version 2>&1 || true)
echo "$cli_out" | grep -q 'dun 0\.' || { echo "FAIL cli_version"; cli_fails=1; }

# Test: dun --version
cli_out=$("$DUN" --version 2>&1 || true)
echo "$cli_out" | grep -q 'dun 0\.' || { echo "FAIL cli_version_flag"; cli_fails=1; }

# Test: dun help shows commands
cli_out=$("$DUN" help 2>&1 || true)
echo "$cli_out" | grep -q 'run <file>' && echo "$cli_out" | grep -q 'Permission flags' || { echo "FAIL cli_help"; cli_fails=1; }

# Test: bare filename (implicit run)
echo 'console.log("bare-file-test")' > /tmp/dun_cli_bare.js
cli_out=$("$DUN" /tmp/dun_cli_bare.js 2>&1 || true)
echo "$cli_out" | grep -q 'bare-file-test' || { echo "FAIL cli_bare_file"; cli_fails=1; }
rm -f /tmp/dun_cli_bare.js

# Test: -- argument separator passes args to script
echo 'console.log(process.argv.slice(2).join(","))' > /tmp/dun_cli_args.js
cli_out=$("$DUN" run /tmp/dun_cli_args.js -- foo bar 2>&1 || true)
echo "$cli_out" | grep -q 'foo,bar' || { echo "FAIL cli_arg_separator"; cli_fails=1; }
rm -f /tmp/dun_cli_args.js

# Test: no args starts REPL
cli_out=$(echo '.exit' | "$DUN" 2>&1 || true)
echo "$cli_out" | grep -q 'dun 0\.' || { echo "FAIL cli_no_args_repl"; cli_fails=1; }

# Test: dun init creates project
tmpdir=$(mktemp -d)
cli_out=$("$DUN" init "$tmpdir/testproj" 2>&1 || true)
echo "$cli_out" | grep -q 'Initialized' && [ -f "$tmpdir/testproj/main.ts" ] || { echo "FAIL cli_init"; cli_fails=1; }
rm -rf "$tmpdir"

# Test: dun clean (run from tmpdir to avoid side effects)
cli_cleandir=$(mktemp -d)
_absdun=$(cd "$(dirname "$DUN")" && pwd)/$(basename "$DUN")
cli_out=$(cd "$cli_cleandir" && "$_absdun" clean 2>&1 || true)
echo "$cli_out" | grep -qiE 'clean|nothing' || { echo "FAIL cli_clean"; cli_fails=1; }
rm -rf "$cli_cleandir"

# Test: fetch permission denied without --allow-net
echo 'try { fetch("http://localhost:9999"); console.log("FAIL_NO_DENY"); } catch(e) { console.log("PERM_DENIED"); }' > /tmp/dun_fetch_perm.js
cli_out=$("$DUN" run /tmp/dun_fetch_perm.js 2>&1 || true)
echo "$cli_out" | grep -q 'PERM_DENIED' || { echo "FAIL cli_fetch_perm"; cli_fails=1; }
rm -f /tmp/dun_fetch_perm.js

# Test: shell metachar rejected with scoped --allow-run
echo 'try { require("child_process").execSync("echo hi; cat /etc/passwd"); console.log("FAIL_NO_DENY"); } catch(e) { console.log("META_BLOCKED:" + e.message.includes("metachar")); }' > /tmp/dun_meta.js
cli_out=$("$DUN" run --allow-run=echo /tmp/dun_meta.js 2>&1 || true)
echo "$cli_out" | grep -q 'META_BLOCKED' || { echo "FAIL cli_shell_meta"; cli_fails=1; }
rm -f /tmp/dun_meta.js

# Test: unknown command
cli_out=$("$DUN" foobar 2>&1 || true)
echo "$cli_out" | grep -q "unknown command 'foobar'" || { echo "FAIL cli_unknown_cmd"; cli_fails=1; }

# Test: unknown flag
cli_out=$("$DUN" --foobar 2>&1 || true)
echo "$cli_out" | grep -q "unknown flag '--foobar'" || { echo "FAIL cli_unknown_flag"; cli_fails=1; }

# Test: unknown flag after run
cli_out=$("$DUN" run --badopt 2>&1 || true)
echo "$cli_out" | grep -q "unknown flag '--badopt'" || { echo "FAIL cli_unknown_flag_run"; cli_fails=1; }

if [ "$cli_fails" -eq 0 ]; then
  echo "PASS cli_features (14 checks)"
else
  fails=$((fails+1))
fi

# --- .env auto-loading tests ---
dotenv_fails=0

# Set up temp directory with .env file and test script
dotenv_dir=$(mktemp -d)
cat > "$dotenv_dir/.env" <<'ENVEOF'
# .env test file
DUN_TEST_FOO=hello_from_dotenv
DUN_TEST_BAR="quoted value"
DUN_TEST_BAZ='single quoted'
DUN_TEST_EMPTY=
DUN_TEST_SPACES=  spaced

  DUN_TEST_PADDED=padded_key
ENVEOF

cat > "$dotenv_dir/dotenv_test.js" <<'JSEOF'
// Verify .env variables were loaded into process.env
console.log("FOO:" + process.env.DUN_TEST_FOO);
console.log("BAR:" + process.env.DUN_TEST_BAR);
console.log("BAZ:" + process.env.DUN_TEST_BAZ);
console.log("EMPTY:" + (process.env.DUN_TEST_EMPTY === "" ? "empty" : "missing"));
console.log("SPACES:" + process.env.DUN_TEST_SPACES);
console.log("PADDED:" + process.env.DUN_TEST_PADDED);
JSEOF

dotenv_expected="FOO:hello_from_dotenv
BAR:quoted value
BAZ:single quoted
EMPTY:empty
SPACES:spaced
PADDED:padded_key"

dotenv_out=$(cd "$dotenv_dir" && "$_absdun" run --allow-env dotenv_test.js 2>/dev/null || true)
if [ "$dotenv_out" = "$dotenv_expected" ]; then
  : # pass
else
  echo "FAIL dotenv_load"
  diff -u <(printf '%s\n' "$dotenv_expected") <(printf '%s\n' "$dotenv_out") || true
  dotenv_fails=1
fi

# Test: existing env vars are NOT overridden by .env
export DUN_TEST_FOO="already_set"
dotenv_out2=$(cd "$dotenv_dir" && "$_absdun" run --allow-env dotenv_test.js 2>/dev/null || true)
echo "$dotenv_out2" | head -1 | grep -q "FOO:already_set" || { echo "FAIL dotenv_no_override"; dotenv_fails=1; }
unset DUN_TEST_FOO

# Test: no .env file does not cause error
no_env_dir=$(mktemp -d)
echo 'console.log("ok")' > "$no_env_dir/test.js"
no_env_out=$(cd "$no_env_dir" && "$_absdun" run "$no_env_dir/test.js" 2>/dev/null || true)
echo "$no_env_out" | grep -q "ok" || { echo "FAIL dotenv_missing_ok"; dotenv_fails=1; }
rm -rf "$no_env_dir"

rm -rf "$dotenv_dir"

if [ "$dotenv_fails" -eq 0 ]; then
  echo "PASS dotenv_loading (3 checks)"
else
  fails=$((fails+1))
fi

exit $((fails > 0 ? 1 : 0))
