# tests/test_integration.sh - end-to-end: exercita todas as regras de
# negocio juntas atraves do balance.sh real (nao chama o awk diretamente).

BALANCE_SH="$PROJECT_ROOT/balance.sh"

proj=$(mktemp -d)
cp "$BALANCE_SH" "$proj/balance.sh"
cp -r "$PROJECT_ROOT/lib" "$proj/lib"
mkdir -p "$proj/configs/teste-integracao"
cat > "$proj/configs/teste-integracao/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=3
SERVIDORES_EXCLUIDOS="srv3"
SERVIDOR_RECEBEDOR="srv9"
EOF

csv_tmp="$proj/dados.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,100,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,20,-,2024-01-01
c4,srv1,15,-,2024-01-01
c5,srv3,50,-,2024-01-01
c6,srv3,5,-,2024-01-01
c7,srv3,7,-,2024-01-01
c8,srv3,9,-,2024-01-01
c9,srv2,1,-,2024-01-01
c10,srv9,1,-,2024-01-01
c11,srv9,1,-,2024-01-01
c12,srv9,1,-,2024-01-01
c13,srv9,1,-,2024-01-01
c14,srv9,1,-,2024-01-01
EOF
# srv1: 4 clientes (max=3) -> excedente 1, menor=c2(10)
# srv3: 4 clientes, EXCLUIDO de receber, mas pode perder -> excedente 1, menor=c6(5)
# srv2: 1 cliente -> capacidade 2, unico destino elegivel -> recebe c2 e c6
# srv9: 5 clientes, e' o SERVIDOR_RECEBEDOR -> fora do balanceamento, nao gera nada

stdout_tmp=$(mktemp)
"$proj/balance.sh" teste-integracao "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "execucao end-to-end deve terminar com sucesso"

expected_srv2=$(mktemp)
printf 'c2\nc6\n' > "$expected_srv2"
assert_file_eq "$expected_srv2" "$proj/results/teste-integracao/to_srv2.txt" "to_srv2.txt deve conter c2 e c6, em ordem alfabetica"
rm -f "$expected_srv2"

assert_file_missing "$proj/results/teste-integracao/to_srv1.txt" "srv1 nao deve receber ninguem"
assert_file_missing "$proj/results/teste-integracao/to_srv3.txt" "srv3 esta excluido de receber, nao deve ter arquivo"
assert_file_missing "$proj/results/teste-integracao/to_srv9.txt" "srv9 e' o recebedor, esta fora do balanceamento"

log_file=$(find "$proj/logs/teste-integracao" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content=$(cat "$log_file")
assert_contains "$log_content" "2 cliente(s) movido(s), 0 aviso(s)" "log deve resumir as 2 movimentacoes sem avisos"
case "$log_content" in
    *"srv9 ->"*|*"-> srv9"*)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: srv9 (recebedor) nao deveria aparecer em nenhuma movimentacao do log"
        ;;
    *)
        echo "PASS: srv9 (recebedor) nao aparece em nenhuma movimentacao do log"
        ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))

rm -rf "$proj" "$stdout_tmp"
