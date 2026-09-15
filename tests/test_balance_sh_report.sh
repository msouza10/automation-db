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
mkdir -p "$proj/configs/teste-env"
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

# --- execucao normal: deve imprimir as tabelas E escrever os arquivos ---
stdout_tmp=$(mktemp)
"$proj/balance.sh" teste-env "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "execucao normal com relatorio deve terminar com sucesso"

out=$(cat "$stdout_tmp")
assert_contains "$out" "=== ANTES ===" "deve imprimir o cabecalho da tabela ANTES"
assert_contains "$out" "=== DEPOIS ===" "deve imprimir o cabecalho da tabela DEPOIS"
assert_contains "$out" "=== MOVIMENTACOES ===" "deve imprimir a lista de movimentacoes"
assert_contains "$out" "=== RESUMO POR SERVIDOR ===" "deve imprimir o resumo de perdas/ganhos por servidor"
assert_contains "$out" "srv1" "tabela deve citar srv1"
assert_contains "$out" "srv2" "tabela deve citar srv2"
assert_contains "$out" "c2: srv1 -> srv2 (10 devices)" "lista de movimentacoes deve citar a movimentacao de c2"

expected_srv2=$(mktemp)
echo "c2" > "$expected_srv2"
assert_file_eq "$expected_srv2" "$proj/results/teste-env/to_srv2.txt" "execucao normal ainda deve escrever os arquivos de saida"
rm -f "$expected_srv2"

log_file=$(find "$proj/logs/teste-env" -name 'balance_*.log' 2>/dev/null | head -n1)
assert_contains "$log_file" "balance_" "execucao normal ainda deve escrever o log"

rm -rf "$proj" "$stdout_tmp"

# --- --dry-run: deve imprimir as mesmas tabelas SEM escrever nenhum arquivo ---
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/teste-env"
cat > "$proj2/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=2
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp2="$proj2/dados.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

stdout_tmp2=$(mktemp)
"$proj2/balance.sh" --dry-run teste-env "$csv_tmp2" > "$stdout_tmp2" 2>&1
rc2=$?
assert_eq "0" "$rc2" "--dry-run deve terminar com sucesso"

out2=$(cat "$stdout_tmp2")
assert_contains "$out2" "=== ANTES ===" "--dry-run deve imprimir a tabela ANTES"
assert_contains "$out2" "=== DEPOIS ===" "--dry-run deve imprimir a tabela DEPOIS"
assert_contains "$out2" "c2: srv1 -> srv2 (10 devices)" "--dry-run deve mostrar a movimentacao planejada"
assert_contains "$out2" "dry-run" "--dry-run deve deixar claro que nada foi escrito"

assert_file_missing "$proj2/results/teste-env/to_srv2.txt" "--dry-run nao deve criar arquivos de resultado"
[ -d "$proj2/logs/teste-env" ] && log_count=$(find "$proj2/logs/teste-env" -name 'balance_*.log' 2>/dev/null | wc -l) || log_count=0
assert_eq "0" "$log_count" "--dry-run nao deve escrever nenhum arquivo de log"

rm -rf "$proj2" "$stdout_tmp2"

# --- --dry-run continua validando normalmente (ambiente inexistente) ---
out3=$("$BALANCE_SH" --dry-run ambiente-que-nao-existe /dev/null 2>&1)
rc3=$?
assert_eq "1" "$rc3" "--dry-run com ambiente invalido ainda deve falhar"
assert_contains "$out3" "nao encontrado" "--dry-run com ambiente invalido ainda deve informar o erro"
