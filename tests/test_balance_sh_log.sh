# tests/test_balance_sh_log.sh - testa o log de execucao de balance.sh.

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

stdout_tmp=$(mktemp)
"$proj/balance.sh" teste-env "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "execucao com sucesso deve retornar codigo 0"

log_file=$(find "$proj/logs/teste-env" -name 'balance_*.log' 2>/dev/null | head -n1)
assert_contains "$log_file" "balance_" "deve gerar um arquivo de log com o padrao balance_<timestamp>.log"

log_content=$(cat "$log_file")
assert_contains "$log_content" "c2: srv1 -> srv2 (10 devices)" "log deve descrever a movimentacao de c2"
assert_contains "$log_content" "1 cliente(s) movido(s), 0 aviso(s)" "log deve resumir total de movimentacoes e avisos"

stdout_content=$(cat "$stdout_tmp")
assert_contains "$stdout_content" "1 cliente(s) movido(s)" "stdout deve mostrar um resumo curto"

rm -rf "$proj" "$stdout_tmp"

# Caso: execucao que gera aviso deve refletir o aviso no log e no stdout
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=1
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp2="$proj/dados2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,7000,-,2024-01-01
EOF
stdout_tmp2=$(mktemp)
"$proj/balance.sh" teste-env "$csv_tmp2" > "$stdout_tmp2" 2>&1
log_file2=$(find "$proj/logs/teste-env" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content2=$(cat "$log_file2")
assert_contains "$log_content2" "AVISO" "log deve conter o aviso quando um servidor nao pode ser totalmente resolvido"
stdout_content2=$(cat "$stdout_tmp2")
assert_contains "$stdout_content2" "aviso" "stdout deve sinalizar que houve aviso(s)"
rm -rf "$proj" "$stdout_tmp2"
