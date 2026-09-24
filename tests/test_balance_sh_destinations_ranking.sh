# tests/test_balance_sh_destinations_ranking.sh - testa a nova secao do
# relatorio (console + log) com a lista de servidores de destino ordenada
# pelo maior cliente individual que cada um recebeu.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

# --- cenario com 2 servidores de destino, cada um recebendo um cliente de
# tamanho diferente: srv4 recebe eBig (600, o maior movido), srv3 recebe
# eMed (550). srv4 deve aparecer primeiro na lista. ---
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=100
MAX_DEVICES_PER_SERVER=1000
RECEIVER_SERVER=srv9
EOF
csv_tmp="$proj/data.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
eBig,srv1,600,-,2024-01-01
filler1,srv1,500,-,2024-01-01
eMed,srv2,550,-,2024-01-01
filler2,srv2,500,-,2024-01-01
keepX,srv3,450,-,2024-01-01
keepY,srv4,1,-,2024-01-01
EOF

stdout_tmp=$(mktemp)
"$proj/balance.sh" test-env "$csv_tmp" > "$stdout_tmp" 2>&1
out=$(cat "$stdout_tmp")

assert_contains "$out" "=== DESTINATIONS BY LARGEST CLIENT ===" "stdout should show the new destinations-by-largest-client section"

# srv4 (recebeu eBig=600) deve vir antes de srv3 (recebeu eMed=550), dentro
# da nova secao especificamente (srv3/srv4 tambem aparecem nas tabelas
# BEFORE/AFTER, entao o trecho precisa ser isolado antes de comparar)
ranking_section=$(printf '%s\n' "$out" | awk '/=== DESTINATIONS BY LARGEST CLIENT ===/{flag=1; next} flag')

TESTS_RUN=$((TESTS_RUN + 1))
pos_srv4=$(printf '%s\n' "$ranking_section" | grep -n "^srv4" | head -n1 | cut -d: -f1)
pos_srv3=$(printf '%s\n' "$ranking_section" | grep -n "^srv3" | head -n1 | cut -d: -f1)
if [ -n "$pos_srv4" ] && [ -n "$pos_srv3" ] && [ "$pos_srv4" -lt "$pos_srv3" ]; then
    echo "PASS: srv4 (largest client received: eBig, 600 devices) should be listed before srv3 (eMed, 550 devices)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: srv4 (largest client received: eBig, 600 devices) should be listed before srv3 (eMed, 550 devices)"
    echo "  stdout was:"
    echo "$out"
fi

assert_contains "$out" "eBig" "stdout section should cite the largest client received by srv4 (eBig)"
assert_contains "$out" "eMed" "stdout section should cite the largest client received by srv3 (eMed)"

log_file=$(find "$proj/logs/test-env" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content=$(cat "$log_file")
assert_contains "$log_content" "=== DESTINATIONS BY LARGEST CLIENT ===" "log should also include the destinations-by-largest-client section, not just stdout"

ranking_section_log=$(printf '%s\n' "$log_content" | awk '/=== DESTINATIONS BY LARGEST CLIENT ===/{flag=1; next} flag')

TESTS_RUN=$((TESTS_RUN + 1))
pos_srv4_log=$(printf '%s\n' "$ranking_section_log" | grep -n "^srv4" | head -n1 | cut -d: -f1)
pos_srv3_log=$(printf '%s\n' "$ranking_section_log" | grep -n "^srv3" | head -n1 | cut -d: -f1)
if [ -n "$pos_srv4_log" ] && [ -n "$pos_srv3_log" ] && [ "$pos_srv4_log" -lt "$pos_srv3_log" ]; then
    echo "PASS: log should keep srv4 listed before srv3, same order as stdout"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: log should keep srv4 listed before srv3, same order as stdout"
fi

rm -rf "$proj" "$stdout_tmp"

# --- cenario sem nenhuma movimentacao -> secao deve indicar "(none)" e nao
# quebrar nada ---
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/test-env2"
cat > "$proj2/configs/test-env2/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srv9
EOF
csv_tmp2="$proj2/data2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv2,10,-,2024-01-01
EOF
stdout_tmp2=$(mktemp)
"$proj2/balance.sh" test-env2 "$csv_tmp2" > "$stdout_tmp2" 2>&1
out2=$(cat "$stdout_tmp2")
assert_contains "$out2" "=== DESTINATIONS BY LARGEST CLIENT ===" "section header should still be shown even with no moves"
assert_contains "$out2" "(none)" "with no moves, the section should say (none) instead of an empty table"

rm -rf "$proj2" "$stdout_tmp2"

# --- cenario com devices empatados: o "maior cliente" citado nesta secao
# precisa ser o MESMO cliente que aparece como primeira linha do
# to_<servidor>.txt daquele destino (mesmo criterio de desempate -
# alfabetico - nas duas vitrines do mesmo dado) ---
proj3=$(new_fake_project)
mkdir -p "$proj3/configs/test-env3"
cat > "$proj3/configs/test-env3/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=5
RECEIVER_SERVER=srv9
EOF
csv_tmp3="$proj3/data3.csv"
cat > "$csv_tmp3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
charlie,srv1,10,-,2024-01-01
bravo,srv1,10,-,2024-01-01
alfa,srv1,10,-,2024-01-01
big1,srv1,500,-,2024-01-01
big2,srv1,600,-,2024-01-01
big3,srv1,700,-,2024-01-01
big4,srv1,800,-,2024-01-01
big5,srv1,900,-,2024-01-01
seed,srv2,1,-,2024-01-01
EOF
stdout_tmp3=$(mktemp)
"$proj3/balance.sh" test-env3 "$csv_tmp3" > "$stdout_tmp3" 2>&1
out3=$(cat "$stdout_tmp3")
ranking_section3=$(printf '%s\n' "$out3" | awk '/=== DESTINATIONS BY LARGEST CLIENT ===/{flag=1; next} flag')

TESTS_RUN=$((TESTS_RUN + 1))
if printf '%s\n' "$ranking_section3" | grep -q "^srv2 *alfa"; then
    echo "PASS: on a devices tie, the ranking section should cite 'alfa' (same alphabetical tie-break as to_srv2.txt's first line), not whichever client happened to be processed first"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: on a devices tie, the ranking section should cite 'alfa' (same alphabetical tie-break as to_srv2.txt's first line), not whichever client happened to be processed first"
    echo "  ranking section was:"
    echo "$ranking_section3"
fi

rm -rf "$proj3" "$stdout_tmp3"
