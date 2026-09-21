#!/bin/bash
# tests/run_tests.sh - roda todos os tests/test_*.sh e agrega o resultado.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PROJECT_ROOT

# shellcheck disable=SC1090
. "$SCRIPT_DIR/harness.sh"

TOTAL_RUN=0
TOTAL_FAILED=0
OVERALL_FAIL=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue
    echo "--- $(basename "$test_file") ---"
    TESTS_RUN=0
    TESTS_FAILED=0
    # shellcheck disable=SC1090
    . "$test_file"
    TOTAL_RUN=$((TOTAL_RUN + TESTS_RUN))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))
    if [ "$TESTS_FAILED" -ne 0 ]; then
        OVERALL_FAIL=1
    fi
    echo ""
done

echo "===================================="
echo "TOTAL: $TOTAL_RUN test(s), $TOTAL_FAILED failure(s)"
exit "$OVERALL_FAIL"
