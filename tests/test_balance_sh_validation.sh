# tests/test_balance_sh_validation.sh - testa a validacao de entrada de balance.sh.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

# monta um "projeto" minimo e isolado em um dir temporario, copiando
# balance.sh + lib/ para dentro (SCRIPT_DIR dentro do script e' resolvido
# pelo caminho do proprio balance.sh, entao ele precisa estar acompanhado
# da sua propria lib/ e configs/)
new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

# Caso 1: numero errado de argumentos
out=$("$BALANCE_SH" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail with exit code 1 when arguments are missing"
assert_contains "$out" "ERROR" "should report a usage error when arguments are missing"

# Caso 2: ambiente inexistente
csv_tmp=$(mktemp)
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$BALANCE_SH" nonexistent-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when the environment does not exist"
assert_contains "$out" "not found" "should report that the environment was not found"
rm -f "$csv_tmp"

# Caso 3: csv inexistente com ambiente/config validos
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srvX
EOF
out=$("$proj/balance.sh" test-env "$proj/does-not-exist.csv" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when the csv does not exist"
assert_contains "$out" "csv not found" "should report that the csv was not found"
rm -rf "$proj"

# Caso 4: config sem MAX_CLIENTS_PER_SERVER
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
RECEIVER_SERVER=srvX
EOF
csv_tmp="$proj/data.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" test-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when MAX_CLIENTS_PER_SERVER is not defined"
assert_contains "$out" "MAX_CLIENTS_PER_SERVER" "should cite the missing key in the error"
rm -rf "$proj"

# Caso 5: MAX_CLIENTS_PER_SERVER nao numerico
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=abc
RECEIVER_SERVER=srvX
EOF
csv_tmp="$proj/data.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" test-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when MAX_CLIENTS_PER_SERVER is not an integer"
assert_contains "$out" "integer" "should report that the value must be an integer"
rm -rf "$proj"

# Caso 6b: MAX_DEVICES_PER_SERVER nao numerico (chave opcional, mas se
# presente precisa ser inteiro)
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srvX
MAX_DEVICES_PER_SERVER=abc
EOF
csv_tmp="$proj/data.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" test-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when MAX_DEVICES_PER_SERVER is not an integer"
assert_contains "$out" "MAX_DEVICES_PER_SERVER" "should cite the invalid key in the error"
rm -rf "$proj"

# Caso 6c: MAX_DEVICES_PER_SERVER ausente (opcional) nao deve falhar
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srvX
EOF
csv_tmp="$proj/data.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" test-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "0" "$rc" "MAX_DEVICES_PER_SERVER is optional, its absence should not cause an error"
rm -rf "$proj"

# Caso 6: config sem RECEIVER_SERVER
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
EOF
csv_tmp="$proj/data.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" test-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "should fail when RECEIVER_SERVER is not defined"
assert_contains "$out" "RECEIVER_SERVER" "should cite the missing key in the error"
rm -rf "$proj"
