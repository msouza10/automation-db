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
mkdir -p "$proj/configs/teste-env" "$proj/results/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=2
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp="$proj/dados.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
# arquivo de um destino que nao deveria mais existir apos a execucao,
# pra provar que a limpeza de to_*.txt antigos funciona
echo "cliente-fantasma" > "$proj/results/teste-env/to_srv-antigo.txt"

"$proj/balance.sh" teste-env "$csv_tmp" > /dev/null 2>&1

expected1=$(mktemp)
echo "c2" > "$expected1"
assert_file_eq "$expected1" "$proj/results/teste-env/to_srv2.txt" "to_srv2.txt deve conter apenas c2"
rm -f "$expected1"

assert_file_missing "$proj/results/teste-env/to_srv1.txt" "srv1 nao recebeu ninguem, nao deve ter arquivo de destino"
assert_file_missing "$proj/results/teste-env/to_srv-antigo.txt" "to_*.txt de execucao anterior deve ser removido"

rm -rf "$proj"

# Caso: nenhuma movimentacao necessaria -> nenhum arquivo to_*.txt gerado
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env2"
cat > "$proj/configs/teste-env2/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp2="$proj/dados2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv2,10,-,2024-01-01
EOF
"$proj/balance.sh" teste-env2 "$csv_tmp2" > /dev/null 2>&1
assert_file_missing "$proj/results/teste-env2/to_srv1.txt" "sem excedente, nenhum to_*.txt deve ser gerado (srv1)"
assert_file_missing "$proj/results/teste-env2/to_srv2.txt" "sem excedente, nenhum to_*.txt deve ser gerado (srv2)"
rm -rf "$proj"
