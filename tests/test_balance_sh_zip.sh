# tests/test_balance_sh_zip.sh - testa a geracao do zip
# migration_<env>-<data>_<hora>.zip em packed/<env>/, contendo apenas os
# to_*.txt (sem estrutura de pastas), um zip por EXECUCAO (nao por dia).

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

proj=$(new_fake_project)
mkdir -p "$proj/configs/test-env"
cat > "$proj/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp="$proj/data.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

"$proj/balance.sh" test-env "$csv_tmp" > /dev/null 2>&1

# usa um glob (nao reconstroi a data/hora manualmente) pra nao arriscar
# flakiness se o teste rodar bem em cima da virada do segundo/meia-noite
zip_file=$(find "$proj/packed/test-env" -name 'migration_test-env-*.zip' 2>/dev/null | head -n1)

TESTS_RUN=$((TESTS_RUN + 1))
case "$(basename "${zip_file:-}")" in
    migration_test-env-[0-1][0-9]-[0-3][0-9]-[0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].zip)
        echo "PASS: should create packed/<env>/migration_<env>-<MM-DD-YYYY>_<HHMMSS>.zip"
        ;;
    *)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: should create packed/<env>/migration_<env>-<MM-DD-YYYY>_<HHMMSS>.zip"
        echo "  actual: ${zip_file:-<none found>}"
        ;;
esac

zip_listing=$(unzip -Z1 "$zip_file" 2>/dev/null | sort)
expected_listing=$(printf 'to_srv2.txt\n')
assert_eq "$expected_listing" "$zip_listing" "zip should contain only to_srv2.txt, flat (no folder inside)"

extracted=$(mktemp -d)
unzip -q -o "$zip_file" -d "$extracted" > /dev/null 2>&1
expected_content=$(mktemp)
echo "c2" > "$expected_content"
assert_file_eq "$expected_content" "$extracted/to_srv2.txt" "the to_srv2.txt inside the zip should have the same content as the generated file"
rm -f "$expected_content"
rm -rf "$extracted"

rm -rf "$proj"

# --dry-run nao deve gerar zip
proj2=$(new_fake_project)
mkdir -p "$proj2/configs/test-env"
cat > "$proj2/configs/test-env/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
"$proj2/balance.sh" --dry-run test-env "$csv_tmp" > /dev/null 2>&1
assert_file_missing "$(find_file "$proj2/packed" "*.zip")" "--dry-run should not create any zip"
rm -rf "$proj2"

# sem movimentacao -> sem to_*.txt -> nao deve gerar zip (vazio nao tem sentido)
proj3=$(new_fake_project)
mkdir -p "$proj3/configs/test-env3"
cat > "$proj3/configs/test-env3/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=10
RECEIVER_SERVER=srv9
EOF
csv_tmp3="$proj3/data3.csv"
cat > "$csv_tmp3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv2,10,-,2024-01-01
EOF
"$proj3/balance.sh" test-env3 "$csv_tmp3" > /dev/null 2>&1
assert_file_missing "$(find_file "$proj3/packed" "*.zip")" "with no moves (no to_*.txt), no zip should be generated"
rm -rf "$proj3"

# duas execucoes reais no mesmo dia nao devem se sobrescrever - cada
# execucao deve gerar seu proprio zip (nome inclui hora, nao so a data)
proj4=$(new_fake_project)
mkdir -p "$proj4/configs/test-env4"
cat > "$proj4/configs/test-env4/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp4="$proj4/data4.csv"
cat > "$csv_tmp4" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
"$proj4/balance.sh" test-env4 "$csv_tmp4" > /dev/null 2>&1
sleep 1
"$proj4/balance.sh" test-env4 "$csv_tmp4" > /dev/null 2>&1
zip_count=$(find "$proj4/packed/test-env4" -name '*.zip' | wc -l | tr -d ' ')
assert_eq "2" "$zip_count" "two real runs of the same env on the same day should produce two separate zips, not overwrite each other"
rm -rf "$proj4"

# se o binario 'zip' falhar (disco cheio, permissao, etc.), o script nao
# deve afirmar sucesso - deve avisar em vez de imprimir "Zip: ..."
proj5=$(new_fake_project)
mkdir -p "$proj5/configs/test-env5"
cat > "$proj5/configs/test-env5/config.conf" <<'EOF'
MAX_CLIENTS_PER_SERVER=2
RECEIVER_SERVER=srv9
EOF
csv_tmp5="$proj5/data5.csv"
cat > "$csv_tmp5" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
fakebin=$(mktemp -d)
cat > "$fakebin/zip" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$fakebin/zip"
stdout_tmp5=$(mktemp)
PATH="$fakebin:$PATH" "$proj5/balance.sh" test-env5 "$csv_tmp5" > "$stdout_tmp5" 2>&1
out5=$(cat "$stdout_tmp5")
assert_file_missing "$(find_file "$proj5/packed" "*.zip")" "when the zip command fails, no (partial/broken) zip file should be left behind"
assert_contains "$out5" "WARNING" "when the zip command fails, the console should warn instead of silently claiming success"
TESTS_RUN=$((TESTS_RUN + 1))
case "$out5" in
    *"Zip: "*)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: should not print a 'Zip: ...' success line when zip actually failed"
        ;;
    *)
        echo "PASS: should not print a 'Zip: ...' success line when zip actually failed"
        ;;
esac
rm -rf "$proj5" "$fakebin" "$stdout_tmp5"
