# tests/test_balance_sh_output.sh - testa a geracao dos to_<servidor>.txt.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env" "$proj/results/test-env"
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
# arquivo de um destino que nao deveria mais existir apos a execucao,
# pra provar que a limpeza de to_*.txt antigos funciona
echo "ghost-client" > "$proj/results/test-env/to_srv-old.txt"

"$proj/balance.sh" test-env "$csv_tmp" > /dev/null 2>&1

expected1=$(mktemp)
echo "c2" > "$expected1"
assert_file_eq "$expected1" "$proj/results/test-env/to_srv2.txt" "to_srv2.txt should contain only c2"
rm -f "$expected1"

assert_file_missing "$proj/results/test-env/to_srv1.txt" "srv1 received no one, should not have a destination file"
assert_file_missing "$proj/results/test-env/to_srv-old.txt" "to_*.txt from a previous run should be removed"

expected_result_csv=$(mktemp)
cat > "$expected_result_csv" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation,New Server,Qty New Server
c1,srv1,50,-,2024-01-01,,
c2,srv1,10,-,2024-01-01,srv2,10
c3,srv1,30,-,2024-01-01,,
c4,srv2,1,-,2024-01-01,,
EOF
assert_file_eq "$expected_result_csv" "$proj/results/test-env/result.csv" "result.csv should only fill New Server/Qty for clients that actually moved"
rm -f "$expected_result_csv"

rm -rf "$proj"

# Caso: nenhuma movimentacao necessaria -> nenhum arquivo to_*.txt gerado
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env2"
cat > "$proj/configs/test-env2/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srv9
EOF
csv_tmp2="$proj/data2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv2,10,-,2024-01-01
EOF
"$proj/balance.sh" test-env2 "$csv_tmp2" > /dev/null 2>&1
assert_file_missing "$proj/results/test-env2/to_srv1.txt" "with no excess, no to_*.txt should be generated (srv1)"
assert_file_missing "$proj/results/test-env2/to_srv2.txt" "with no excess, no to_*.txt should be generated (srv2)"
rm -rf "$proj"
