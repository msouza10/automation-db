# tests/test_relatorio_awk.sh - testa lib/relatorio.awk isoladamente.

RELATORIO_SCRIPT="$PROJECT_ROOT/lib/relatorio.awk"

run_relatorio() {
    # $1=csv $2=movimentacoes
    awk -f "$RELATORIO_SCRIPT" "$1" "$2"
}

# Caso 1: sem movimentacoes -> antes e depois sao identicos
csv1=$(mktemp)
cat > "$csv1" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv1,20,-,2024-01-01
c3,srv2,5,-,2024-01-01
EOF
moves1=$(mktemp)
: > "$moves1"
out1=$(run_relatorio "$csv1" "$moves1" | sort)
expected1=$(printf 'srv1,2,30,2,30\nsrv2,1,5,1,5\n')
assert_eq "$expected1" "$out1" "sem movimentacoes, antes e depois devem ser identicos para cada servidor"
rm -f "$csv1" "$moves1"

# Caso 2: uma movimentacao -> origem perde, destino ganha, nos dois campos
csv2=$(mktemp)
cat > "$csv2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv2,1,-,2024-01-01
EOF
moves2=$(mktemp)
printf 'c2,srv1,srv2,10\n' > "$moves2"
out2=$(run_relatorio "$csv2" "$moves2" | sort)
expected2=$(printf 'srv1,2,60,1,50\nsrv2,1,1,2,11\n')
assert_eq "$expected2" "$out2" "movimentacao deve refletir na contagem e nos devices de origem e destino"
rm -f "$csv2" "$moves2"

# Caso 3: servidor que so aparece como destino permanece coerente (ja existia no csv)
csv3=$(mktemp)
cat > "$csv3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,4000,-,2024-01-01
c2,srv1,2000,-,2024-01-01
c3,srv2,1,-,2024-01-01
EOF
moves3=$(mktemp)
printf 'c1,srv1,srv2,4000\n' > "$moves3"
out3=$(run_relatorio "$csv3" "$moves3" | sort)
expected3=$(printf 'srv1,2,6000,1,2000\nsrv2,1,1,2,4001\n')
assert_eq "$expected3" "$out3" "servidor de destino deve somar corretamente clientes e devices recebidos"
rm -f "$csv3" "$moves3"
