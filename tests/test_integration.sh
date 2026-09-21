# tests/test_integration.sh - end-to-end: exercita todas as regras de
# negocio juntas atraves do balance.sh real (nao chama o awk diretamente).

BALANCE_SH="$PROJECT_ROOT/balance.sh"

proj=$(mktemp -d)
cp "$BALANCE_SH" "$proj/balance.sh"
cp -r "$PROJECT_ROOT/lib" "$proj/lib"
mkdir -p "$proj/configs/test-integration"
cat > "$proj/configs/test-integration/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=3
EXCLUDED_SERVERS="srv3"
RECEIVER_SERVER="srv9"
EOF

csv_tmp="$proj/data.csv"
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
# srv9: 5 clientes, e' o RECEIVER_SERVER -> fora do balanceamento, nao gera nada

stdout_tmp=$(mktemp)
"$proj/balance.sh" test-integration "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "end-to-end run should finish successfully"

expected_srv2=$(mktemp)
printf 'c2\nc6\n' > "$expected_srv2"
assert_file_eq "$expected_srv2" "$proj/results/test-integration/to_srv2.txt" "to_srv2.txt should contain c2 and c6, in alphabetical order"
rm -f "$expected_srv2"

assert_file_missing "$proj/results/test-integration/to_srv1.txt" "srv1 should not receive anyone"
assert_file_missing "$proj/results/test-integration/to_srv3.txt" "srv3 is excluded from receiving, should have no file"
assert_file_missing "$proj/results/test-integration/to_srv9.txt" "srv9 is the receiver, it is out of the balancing"

log_file=$(find "$proj/logs/test-integration" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content=$(cat "$log_file")
assert_contains "$log_content" "2 client(s) moved, 0 warning(s)" "log should summarize the 2 moves with no warnings"
case "$log_content" in
    *"srv9 ->"*|*"-> srv9"*)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: srv9 (receiver) should not appear in any move in the log"
        ;;
    *)
        echo "PASS: srv9 (receiver) does not appear in any move in the log"
        ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))

rm -rf "$proj" "$stdout_tmp"

# --- caso 2: MAX_DEVICES_PER_SERVER fluindo pelo balance.sh real ---

proj2=$(mktemp -d)
cp "$BALANCE_SH" "$proj2/balance.sh"
cp -r "$PROJECT_ROOT/lib" "$proj2/lib"
mkdir -p "$proj2/configs/test-devices"
cat > "$proj2/configs/test-devices/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
MAX_DEVICES_PER_SERVER=5000
RECEIVER_SERVER="srv9"
EOF

csv_tmp2="$proj2/data.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,4000,-,2024-01-01
c2,srv1,2000,-,2024-01-01
c3,srv1,100,-,2024-01-01
c4,srv2,1,-,2024-01-01
c5,srv9,1,-,2024-01-01
EOF
# srv1: count=3 (ok), devices=6100 (>5000, excesso=1100) -> move o MAIOR (c1=4000),
# resolve em 1 movimentacao. srv2: capacidade de sobra em ambos os limites.
# srv9: recebedor, fora do balanceamento.

stdout_tmp2=$(mktemp)
"$proj2/balance.sh" test-devices "$csv_tmp2" > "$stdout_tmp2" 2>&1
rc2=$?
assert_eq "0" "$rc2" "run with MAX_DEVICES_PER_SERVER should finish successfully"

expected_srv2_2=$(mktemp)
printf 'c1\n' > "$expected_srv2_2"
assert_file_eq "$expected_srv2_2" "$proj2/results/test-devices/to_srv2.txt" "to_srv2.txt should contain only c1 (device excess resolved with 1 move)"
rm -f "$expected_srv2_2"

log_file2=$(find "$proj2/logs/test-devices" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content2=$(cat "$log_file2")
assert_contains "$log_content2" "c1: srv1 -> srv2 (4000 devices)" "log should describe the move of c1 caused by the device excess"

rm -rf "$proj2" "$stdout_tmp2"
