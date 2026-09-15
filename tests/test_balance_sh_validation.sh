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
assert_eq "1" "$rc" "deve falhar com codigo 1 quando faltam argumentos"
assert_contains "$out" "ERRO" "deve informar erro de uso quando faltam argumentos"

# Caso 2: ambiente inexistente
csv_tmp=$(mktemp)
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$BALANCE_SH" ambiente-que-nao-existe "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando o ambiente nao existe"
assert_contains "$out" "nao encontrado" "deve informar que o ambiente nao foi encontrado"
rm -f "$csv_tmp"

# Caso 3: csv inexistente com ambiente/config validos
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
SERVIDOR_RECEBEDOR=srvX
EOF
out=$("$proj/balance.sh" teste-env "$proj/nao-existe.csv" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando o csv nao existe"
assert_contains "$out" "csv nao encontrado" "deve informar que o csv nao foi encontrado"
rm -rf "$proj"

# Caso 4: config sem MAX_CLIENTES_POR_SERVIDOR
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
SERVIDOR_RECEBEDOR=srvX
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando MAX_CLIENTES_POR_SERVIDOR nao esta definido"
assert_contains "$out" "MAX_CLIENTES_POR_SERVIDOR" "deve citar a chave faltante no erro"
rm -rf "$proj"

# Caso 5: MAX_CLIENTES_POR_SERVIDOR nao numerico
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=abc
SERVIDOR_RECEBEDOR=srvX
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando MAX_CLIENTES_POR_SERVIDOR nao e' um inteiro"
assert_contains "$out" "inteiro" "deve informar que o valor precisa ser um inteiro"
rm -rf "$proj"

# Caso 6: config sem SERVIDOR_RECEBEDOR
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando SERVIDOR_RECEBEDOR nao esta definido"
assert_contains "$out" "SERVIDOR_RECEBEDOR" "deve citar a chave faltante no erro"
rm -rf "$proj"
