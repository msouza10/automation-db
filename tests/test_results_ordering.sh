# tests/test_results_ordering.sh - dentro de cada to_<servidor>.txt, os
# clientes devem vir ordenados por quantidade de devices, do maior pro menor
# (nao alfabetico, nao aleatorio).

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

# --- caso 1: ordem alfabetica dos nomes seria diferente da ordem por devices,
# prova que a ordenacao e' por devices e nao por nome ---
proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=5
RECEIVER_SERVER=srv9
EOF
csv_tmp="$proj/data.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
z1,srv1,5,-,2024-01-01
z2,srv1,50,-,2024-01-01
z3,srv1,20,-,2024-01-01
big1,srv1,500,-,2024-01-01
big2,srv1,600,-,2024-01-01
big3,srv1,700,-,2024-01-01
big4,srv1,800,-,2024-01-01
big5,srv1,900,-,2024-01-01
seed,srv2,1,-,2024-01-01
EOF

"$proj/balance.sh" test-env "$csv_tmp" > /dev/null 2>&1

expected1=$(mktemp)
printf 'z2\nz3\nz1\n' > "$expected1"
assert_file_eq "$expected1" "$(find_file "$proj/results/test-env" to_srv2.txt)" "clients should be ordered by devices, largest first (z2=50, z3=20, z1=5), not alphabetically (which would be z1,z2,z3)"
rm -f "$expected1"

rm -rf "$proj"

# --- caso 2: devices empatados -> desempate alfabetico, pra saida ficar
# deterministica ---
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/test-env2"
cat > "$proj2/configs/test-env2/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=5
RECEIVER_SERVER=srv9
EOF
csv_tmp2="$proj2/data2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
bravo,srv1,10,-,2024-01-01
alfa,srv1,10,-,2024-01-01
charlie,srv1,10,-,2024-01-01
big1,srv1,500,-,2024-01-01
big2,srv1,600,-,2024-01-01
big3,srv1,700,-,2024-01-01
big4,srv1,800,-,2024-01-01
big5,srv1,900,-,2024-01-01
seed,srv2,1,-,2024-01-01
EOF

"$proj2/balance.sh" test-env2 "$csv_tmp2" > /dev/null 2>&1

expected2=$(mktemp)
printf 'alfa\nbravo\ncharlie\n' > "$expected2"
assert_file_eq "$expected2" "$(find_file "$proj2/results/test-env2" to_srv2.txt)" "with tied device counts, order should fall back to alphabetical (deterministic output)"
rm -f "$expected2"

rm -rf "$proj2"
