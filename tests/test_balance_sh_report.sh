# tests/test_balance_sh_report.sh - testa as tabelas antes/depois e o --dry-run.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
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

# --- execucao normal: deve imprimir as tabelas E escrever os arquivos ---
stdout_tmp=$(mktemp)
"$proj/balance.sh" test-env "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "normal run with report should finish successfully"

out=$(cat "$stdout_tmp")
assert_contains "$out" "=== BEFORE ===" "should print the BEFORE table header"
assert_contains "$out" "=== AFTER ===" "should print the AFTER table header"
assert_contains "$out" "=== MOVES ===" "should print the list of moves"
assert_contains "$out" "=== SUMMARY BY SERVER ===" "should print the per-server lost/received summary"
assert_contains "$out" "srv1" "table should mention srv1"
assert_contains "$out" "srv2" "table should mention srv2"
assert_contains "$out" "c2: srv1 -> srv2 (10 devices)" "move list should mention the move of c2"
assert_contains "$out" "DEVICES_BEFORE" "summary should include the devices-before column"
assert_contains "$out" "DEVICES_AFTER" "summary should include the devices-after column"
assert_contains "$out" "DEVICES_CHANGE" "summary should include the signed devices-change column"
assert_contains "$out" "-10" "summary should show srv1 losing 10 devices with a minus sign"
assert_contains "$out" "+10" "summary should show srv2 gaining 10 devices with a plus sign"
assert_contains "$out" "TOTAL: 1 client(s) moved, 10 device(s) moved across 2 server(s) affected." "should print the aggregate totals line"

expected_srv2=$(mktemp)
echo "c2" > "$expected_srv2"
assert_file_eq "$expected_srv2" "$proj/results/test-env/to_srv2.txt" "normal run should still write the output files"
rm -f "$expected_srv2"

log_file=$(find "$proj/logs/test-env" -name 'balance_*.log' 2>/dev/null | head -n1)
assert_contains "$log_file" "balance_" "normal run should still write the log"

rm -rf "$proj" "$stdout_tmp"

# --- --dry-run: deve imprimir as mesmas tabelas SEM escrever nenhum arquivo ---
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/test-env"
cat > "$proj2/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp2="$proj2/data.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

stdout_tmp2=$(mktemp)
"$proj2/balance.sh" --dry-run test-env "$csv_tmp2" > "$stdout_tmp2" 2>&1
rc2=$?
assert_eq "0" "$rc2" "--dry-run should finish successfully"

out2=$(cat "$stdout_tmp2")
assert_contains "$out2" "=== BEFORE ===" "--dry-run should print the BEFORE table"
assert_contains "$out2" "=== AFTER ===" "--dry-run should print the AFTER table"
assert_contains "$out2" "c2: srv1 -> srv2 (10 devices)" "--dry-run should show the planned move"
assert_contains "$out2" "dry-run" "--dry-run should make clear that nothing was written"

assert_file_missing "$proj2/results/test-env/to_srv2.txt" "--dry-run should not create result files"
[ -d "$proj2/logs/test-env" ] && log_count=$(find "$proj2/logs/test-env" -name 'balance_*.log' 2>/dev/null | wc -l) || log_count=0
assert_eq "0" "$log_count" "--dry-run should not write any log file"

rm -rf "$proj2" "$stdout_tmp2"

# --- --dry-run continua validando normalmente (ambiente inexistente) ---
out3=$("$BALANCE_SH" --dry-run nonexistent-env /dev/null 2>&1)
rc3=$?
assert_eq "1" "$rc3" "--dry-run with an invalid environment should still fail"
assert_contains "$out3" "not found" "--dry-run with an invalid environment should still report the error"
