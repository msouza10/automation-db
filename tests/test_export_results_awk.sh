# tests/test_export_results_awk.sh - testa lib/export_results.awk isoladamente.

EXPORT_SCRIPT="$PROJECT_ROOT/lib/export_results.awk"

run_export() {
    # $1=csv $2=movimentacoes
    awk -f "$EXPORT_SCRIPT" "$1" "$2"
}

# Caso 1: sem movimentacoes -> todo mundo repete o proprio servidor/qty
csv1=$(mktemp)
cat > "$csv1" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv2,5,-,2024-01-01
EOF
moves1=$(mktemp)
: > "$moves1"
out1=$(run_export "$csv1" "$moves1")
expected1=$(printf 'Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation,New Server,Qty New Server\nc1,srv1,10,-,2024-01-01,srv1,10\nc2,srv2,5,-,2024-01-01,srv2,5')
assert_eq "$expected1" "$out1" "with no moves, New Server/Qty should repeat the client's own server/devices"
rm -f "$csv1" "$moves1"

# Caso 2: cliente movido -> New Server/Qty refletem o destino, nao movido mantem o original
csv2=$(mktemp)
cat > "$csv2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv2,1,-,2024-01-01
EOF
moves2=$(mktemp)
printf 'c2,srv1,srv2,10\n' > "$moves2"
out2=$(run_export "$csv2" "$moves2")
expected2=$(printf 'Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation,New Server,Qty New Server\nc1,srv1,50,-,2024-01-01,srv1,50\nc2,srv1,10,-,2024-01-01,srv2,10\nc3,srv2,1,-,2024-01-01,srv2,1')
assert_eq "$expected2" "$out2" "moved client should show the destination server/devices, others keep their own"
rm -f "$csv2" "$moves2"

# Caso 3: colunas extras da planilha original devem ser preservadas intactas
csv3=$(mktemp)
cat > "$csv3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,100,5 licenses,2020-05-01
EOF
moves3=$(mktemp)
: > "$moves3"
out3=$(run_export "$csv3" "$moves3")
expected3=$(printf 'Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation,New Server,Qty New Server\nc1,srv1,100,5 licenses,2020-05-01,srv1,100')
assert_eq "$expected3" "$out3" "original columns (including free-text ones) should be preserved as-is"
rm -f "$csv3" "$moves3"
