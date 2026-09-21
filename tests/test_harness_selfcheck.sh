# tests/test_harness_selfcheck.sh - valida o proprio harness antes de confiar nele.

assert_eq "5" "5" "assert_eq should pass when values are equal"
assert_contains "abcdef" "cde" "assert_contains should pass when the substring exists"

# roda em subshell para nao contaminar os contadores globais desta suite
# com a falha proposital abaixo
if (assert_eq "5" "6" "internal check" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_eq should return failure when values differ"
else
    echo "PASS: assert_eq returns failure when values differ"
fi
TESTS_RUN=$((TESTS_RUN + 1))

if (assert_contains "abcdef" "zzz" "internal check" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_contains should return failure when the substring does not exist"
else
    echo "PASS: assert_contains returns failure when the substring does not exist"
fi
TESTS_RUN=$((TESTS_RUN + 1))
