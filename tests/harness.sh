#!/bin/bash
# tests/harness.sh - funcoes de asserção simples, Bash 3.2-compatível.
# Uso: sourced por tests/run_tests.sh antes de cada tests/test_*.sh.

TESTS_RUN=0
TESTS_FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" != "$actual" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$haystack" in
        *"$needle"*)
            echo "PASS: $msg"
            return 0
            ;;
        *)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "FAIL: $msg"
            echo "  expected to contain: $needle"
            echo "  actual:              $haystack"
            return 1
            ;;
    esac
}

assert_file_eq() {
    local expected_file="$1"
    local actual_file="$2"
    local msg="$3"
    local diff_output
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$actual_file" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  file does not exist: $actual_file"
        return 1
    fi
    diff_output=$(diff -u "$expected_file" "$actual_file" 2>&1)
    if [ -n "$diff_output" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "$diff_output"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}

assert_file_missing() {
    local file="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$file" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  file should not exist: $file"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}

# find_file DIR NAME - localiza um arquivo por nome em qualquer subpasta de DIR
# (usado quando o caminho exato contem uma subpasta gerada em runtime, como
# o timestamp de results/<env>/<timestamp>/). Imprime o primeiro caminho
# encontrado, ou nada se nao existir.
find_file() {
    find "$1" -type f -name "$2" 2>/dev/null | head -n1
}
