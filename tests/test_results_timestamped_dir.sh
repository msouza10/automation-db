# tests/test_results_timestamped_dir.sh - cada execucao deve gravar em uma
# subpasta com timestamp (results/<env>/<timestamp>/), nao direto em
# results/<env>/, para nao sobrepor resultados de execucoes anteriores.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

only_subdir() {
    find "$1" -mindepth 1 -maxdepth 1 -type d
}

proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp="$proj/data.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

"$proj/balance.sh" test-env "$csv_tmp" > /dev/null 2>&1

run1_dir=$(only_subdir "$proj/results/test-env")
TESTS_RUN=$((TESTS_RUN + 1))
case "$(basename "$run1_dir")" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9])
        echo "PASS: results/test-env/ should contain a timestamped subfolder (YYYYMMDD_HHMMSS), not a fixed name"
        ;;
    *)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: results/test-env/ should contain a timestamped subfolder (YYYYMMDD_HHMMSS), not a fixed name"
        echo "  actual subfolder: $(basename "$run1_dir")"
        ;;
esac

assert_file_missing "$proj/results/test-env/to_srv2.txt" "to_srv2.txt should NOT be written directly under results/<env>/"

expected1=$(mktemp)
echo "c2" > "$expected1"
assert_file_eq "$expected1" "$run1_dir/to_srv2.txt" "to_srv2.txt should contain only c2, inside the run's timestamped folder"
rm -f "$expected1"

# segunda execucao (em outro timestamp) nao deve apagar/sobrescrever a primeira
sleep 1
"$proj/balance.sh" test-env "$csv_tmp" > /dev/null 2>&1
run2_dir=$(only_subdir "$proj/results/test-env" | grep -v "^$run1_dir\$")

TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "$run2_dir" ] && [ "$run2_dir" != "$run1_dir" ]; then
    echo "PASS: a second run should create a different timestamped folder"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: a second run should create a different timestamped folder"
    echo "  run1: $run1_dir"
    echo "  run2: $run2_dir"
fi

expected1b=$(mktemp)
echo "c2" > "$expected1b"
assert_file_eq "$expected1b" "$run1_dir/to_srv2.txt" "first run's to_srv2.txt should still exist and be untouched after the second run"
rm -f "$expected1b"

rm -rf "$proj"

# --- colisao forcada: simula duas execucoes caindo no MESMO segundo (a
# pasta com aquele timestamp ja existe antes mesmo do balance.sh rodar) -
# ele nao pode reusar/sobrescrever a pasta existente, tem que cair em outra ---
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/test-env2"
cat > "$proj2/configs/test-env2/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp2="$proj2/data2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

collision_ts=$(date +%Y%m%d_%H%M%S)
mkdir -p "$proj2/results/test-env2/$collision_ts"
echo "pre-existing-marker" > "$proj2/results/test-env2/$collision_ts/marker.txt"

"$proj2/balance.sh" test-env2 "$csv_tmp2" > /dev/null 2>&1

assert_file_missing "$proj2/results/test-env2/$collision_ts/to_srv2.txt" "on a timestamp collision, the pre-existing folder must be left untouched, not reused"

other_dir=$(find "$proj2/results/test-env2" -mindepth 1 -maxdepth 1 -type d ! -name "$collision_ts")
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "$other_dir" ] && [ -f "$other_dir/to_srv2.txt" ]; then
    echo "PASS: on a timestamp collision, balance.sh falls back to a disambiguated folder instead of reusing the existing one"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: on a timestamp collision, balance.sh falls back to a disambiguated folder instead of reusing the existing one"
    echo "  found: $other_dir"
fi

rm -rf "$proj2"
