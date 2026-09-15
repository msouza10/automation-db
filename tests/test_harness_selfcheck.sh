# tests/test_harness_selfcheck.sh - valida o proprio harness antes de confiar nele.

assert_eq "5" "5" "assert_eq deve passar quando os valores sao iguais"
assert_contains "abcdef" "cde" "assert_contains deve passar quando a substring existe"

# roda em subshell para nao contaminar os contadores globais desta suite
# com a falha proposital abaixo
if (assert_eq "5" "6" "checagem interna" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_eq deveria retornar falha quando os valores diferem"
else
    echo "PASS: assert_eq retorna falha quando os valores diferem"
fi
TESTS_RUN=$((TESTS_RUN + 1))

if (assert_contains "abcdef" "zzz" "checagem interna" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_contains deveria retornar falha quando a substring nao existe"
else
    echo "PASS: assert_contains retorna falha quando a substring nao existe"
fi
TESTS_RUN=$((TESTS_RUN + 1))
