#!/usr/bin/env bash
# Fuzz harness runner. Builds + runs every target in tests/fuzz/.
# Usage: tests/fuzz/run.sh [seconds-per-target] [target-glob]
#
# Defaults: 60 seconds per target, all targets.
#
# Outputs:
#   build/fuzz_*       — built fuzzers
#   tests/fuzz/crashes — any saved crash artifacts (<target>-<sha1>)
#   tests/fuzz/corpus/<name>/<file>  — grown corpus from each run
#
# Failure mode:
#   - libFuzzer exit code 77 = found crash. Script exits non-zero.
#   - All other exits (timeout, normal completion) = pass.

set -euo pipefail

SECONDS_PER_TARGET=${1:-60}
TARGET_GLOB=${2:-fuzz_*.d}

export PATH=/opt/ldc/bin:${PATH}

cd "$(dirname "$0")/../.."
mkdir -p build tests/fuzz/crashes

fail=0
for fuzz_d in tests/fuzz/${TARGET_GLOB}; do
    [ -f "${fuzz_d}" ] || continue
    name=$(basename "${fuzz_d}" .d)
    target=${name#fuzz_}

    echo "=== Building ${name} ==="
    # Each target imports specific source modules — keep the build
    # invocations target-specific so we don't pull in unrelated code.
    case "${target}" in
        strip)
            ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
                 -I=source -Jsource \
                 -of=build/${name} \
                 "${fuzz_d}" \
                 source/dun/ts/strip.d \
                 source/dun/ts/parser/lexer.d
            ;;
        simd)
            ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
                 -I=source -Jsource \
                 -of=build/${name} \
                 "${fuzz_d}" \
                 source/dun/platform/simd.d \
                 source/dun/declarations.d
            ;;
        url)
            ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
                 -I=source -Jsource \
                 -of=build/${name} \
                 "${fuzz_d}" \
                 source/dun/platform/url_parser.d
            ;;
        lexer)
            ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
                 -I=source -Jsource \
                 -of=build/${name} \
                 "${fuzz_d}" \
                 source/dun/ts/parser/lexer.d
            ;;
        paths)
            ldc2 -fsanitize=fuzzer -fsanitize=address -O1 -g \
                 -I=source -Jsource \
                 -of=build/${name} \
                 "${fuzz_d}" \
                 source/dun/platform/paths.d
            ;;
        *)
            echo "ERROR: unknown fuzz target '${target}' — add a build case to tests/fuzz/run.sh"
            fail=1
            continue
            ;;
    esac

    mkdir -p tests/fuzz/corpus/${target}
    echo "=== Running ${name} for ${SECONDS_PER_TARGET}s ==="
    if timeout "$((SECONDS_PER_TARGET + 5))" build/${name} \
            tests/fuzz/corpus/${target} \
            -max_len=8192 -timeout=5 \
            -artifact_prefix=tests/fuzz/crashes/${target}- \
            -max_total_time=${SECONDS_PER_TARGET}; then
        echo "${name}: OK (no crashes found in ${SECONDS_PER_TARGET}s)"
    else
        rc=$?
        # libFuzzer exit 77 = found crash; 124 = timeout (which is
        # OK — we wanted it to stop after N seconds).
        if [ ${rc} -eq 124 ]; then
            echo "${name}: OK (timeout, no crashes)"
        else
            echo "${name}: FAIL (exit ${rc}) — check tests/fuzz/crashes/"
            fail=1
        fi
    fi
done

if [ ${fail} -ne 0 ]; then
    echo ""
    echo "FAIL: one or more fuzz targets crashed."
    ls tests/fuzz/crashes/
    exit 1
fi

echo ""
echo "PASS: all fuzz targets clean."
