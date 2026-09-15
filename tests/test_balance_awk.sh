# tests/test_balance_awk.sh - testa lib/balance.awk isoladamente.

AWK_SCRIPT="$PROJECT_ROOT/lib/balance.awk"

run_awk() {
    # $1=csv $2=max $3=excluded_csv $4=receiver $5=max_devices (opcional)
    awk -v max="$2" -v excluded_csv="$3" -v receiver="$4" -v max_devices="${5:-}" -f "$AWK_SCRIPT" "$1"
}

# Caso 1: nenhum servidor acima do limite -> nenhuma movimentacao
csv1=$(mktemp)
cat > "$csv1" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv1,20,-,2024-01-01
c3,srv2,5,-,2024-01-01
EOF
out1=$(run_awk "$csv1" 5 "" "")
assert_eq "" "$out1" "sem servidor acima do limite, nao deve haver movimentacao"
rm -f "$csv1"

# Caso 2: um servidor acima do limite, outro com capacidade -> move o menor cliente
csv2=$(mktemp)
cat > "$csv2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
out2=$(run_awk "$csv2" 2 "" "")
assert_eq "c2,srv1,srv2,10" "$out2" "deve mover o cliente de menor devices (c2) de srv1 para srv2"
rm -f "$csv2"

# Caso 3: servidor recebedor fica inteiramente fora do balanceamento
csv3=$(mktemp)
cat > "$csv3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,recv,1,-,2024-01-01
c4,recv,1,-,2024-01-01
c5,recv,1,-,2024-01-01
EOF
stderr3=$(mktemp)
out3=$(run_awk "$csv3" 1 "" "recv" 2>"$stderr3")
err3=$(cat "$stderr3")
assert_eq "" "$out3" "servidor recebedor nao deve receber nem gerar movimentacao"
assert_contains "$err3" "AVISO" "deve avisar que nao ha destino disponivel (recebedor esta fora do balanceamento)"
rm -f "$csv3" "$stderr3"

# Caso 4: servidor excluido pode ser origem mas nunca e' escolhido como destino,
# mesmo tendo mais folga que o unico destino elegivel
csv4=$(mktemp)
cat > "$csv4" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv1,40,-,2024-01-01
c5,srv2,1,-,2024-01-01
c6,srv3,1,-,2024-01-01
c7,srv3,1,-,2024-01-01
EOF
# max=3: srv1 tem 4 (excedente=1, menor=c2). srv2 tem 1 (capacidade=2, mas EXCLUIDO).
# srv3 tem 2 (capacidade=1, elegivel). Se a exclusao nao for respeitada, srv2 venceria
# por ter mais capacidade - este teste so passa se a exclusao for aplicada de verdade.
out4=$(run_awk "$csv4" 3 "srv2" "")
assert_eq "c2,srv1,srv3,10" "$out4" "servidor excluido nunca deve ser escolhido como destino, mesmo com mais folga"
rm -f "$csv4"

# Caso 5: atribuicao gulosa escolhe sempre o destino com mais capacidade disponivel
csv5=$(mktemp)
cat > "$csv5" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,100,-,2024-01-01
c2,srv1,5,-,2024-01-01
c3,srv1,7,-,2024-01-01
c4,srv1,9,-,2024-01-01
c5,srvA,1,-,2024-01-01
c6,srvA,1,-,2024-01-01
c7,srvB,1,-,2024-01-01
EOF
# max=3: srv1 tem 4 (excedente=1, menor=c2=5). srvA capacidade=1. srvB capacidade=2.
out5=$(run_awk "$csv5" 3 "" "")
assert_eq "c2,srv1,srvB,5" "$out5" "deve escolher o destino com mais capacidade disponivel (srvB) em vez de srvA"
rm -f "$csv5"

# Caso 6: todos os candidatos moviveis excedem 5000 devices -> aviso, nenhuma movimentacao
csv6=$(mktemp)
cat > "$csv6" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,7000,-,2024-01-01
EOF
stderr6=$(mktemp)
out6=$(run_awk "$csv6" 1 "" "" 2>"$stderr6")
err6=$(cat "$stderr6")
assert_eq "" "$out6" "nenhum cliente >5000 devices pode ser movido"
assert_contains "$err6" "permanece" "deve avisar que o servidor permanece acima do limite sem candidatos moviveis"
rm -f "$csv6" "$stderr6"

# Caso 7: cliente com devices == 5000 (limite exato) e' elegivel para mover
csv7=$(mktemp)
cat > "$csv7" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,5000,-,2024-01-01
c3,srv1,8000,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
# max=2: srv1 tem 3 (excedente=1). Todos os candidatos tem >=5000 devices; apenas
# c2 (exatamente 5000) e' elegivel, os outros dois (6000, 8000) excedem o limite.
out7=$(run_awk "$csv7" 2 "" "")
assert_eq "c2,srv1,srv2,5000" "$out7" "cliente com exatamente 5000 devices deve ser movivel (regra exclui apenas >5000)"
rm -f "$csv7"

# Caso 8: capacidade de destino insuficiente para todo o excedente -> move o que
# der e avisa sobre o restante
csv8=$(mktemp)
cat > "$csv8" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv1,20,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv1,40,-,2024-01-01
c5,srv2,1,-,2024-01-01
EOF
stderr8=$(mktemp)
out8=$(run_awk "$csv8" 2 "" "" 2>"$stderr8")
err8=$(cat "$stderr8")
assert_eq "c1,srv1,srv2,10" "$out8" "deve mover apenas o que a capacidade de destino permite (1 de 2 necessarios)"
assert_contains "$err8" "AVISO" "deve avisar sobre o cliente que nao coube em nenhum destino"
assert_contains "$err8" "c2" "o aviso deve identificar o cliente que nao pode ser movido"
rm -f "$csv8" "$stderr8"

# Caso 9: excedente causado so pelo limite de DEVICES (contagem de clientes ok) ->
# move o MAIOR cliente primeiro, minimizando o numero de movimentacoes
csv9=$(mktemp)
cat > "$csv9" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,4000,-,2024-01-01
c2,srv1,2000,-,2024-01-01
c3,srv1,100,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
# max_clientes=10 (count=3, nao excede). max_devices=5000 (total=6100, excesso=1100).
# ordenando por devices decrescente, o maior (c1=4000) sozinho ja cobre o excesso.
out9=$(run_awk "$csv9" 10 "" "" 5000)
assert_eq "c1,srv1,srv2,4000" "$out9" "excedente por devices deve mover o maior cliente primeiro, resolvendo em 1 movimentacao"
rm -f "$csv9"

# Caso 10: destino precisa ter folga tanto em contagem quanto em devices - um
# destino com mais vagas de cliente mas sem devices suficientes deve ser
# ignorado em favor de outro com menos vagas mas devices suficientes
csv10=$(mktemp)
cat > "$csv10" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,4000,-,2024-01-01
c2,srv1,3000,-,2024-01-01
c3,srvA,4800,-,2024-01-01
c4,srvB,20,-,2024-01-01
c5,srvB,20,-,2024-01-01
c6,srvB,20,-,2024-01-01
c7,srvB,20,-,2024-01-01
c8,srvB,20,-,2024-01-01
EOF
# max_clientes=10, max_devices=5000.
# srv1: count=2 (ok), devices=7000 (excesso=2000) -> move c1(4000), resolve em 1.
# srvA: count=1 (capacidade_count=9, MUITA vaga), devices=4800 (capacidade_devices=200, NAO cabe c1)
# srvB: count=5 (capacidade_count=5, menos vaga que srvA), devices=100 (capacidade_devices=4900, CABE c1)
out10=$(run_awk "$csv10" 10 "" "" 5000)
assert_eq "c1,srv1,srvB,4000" "$out10" "deve escolher srvB (cabe em devices) e ignorar srvA (mais vagas mas sem devices suficientes)"
rm -f "$csv10"

# Caso 11: com max_devices configurado, um servidor que NAO excede devices
# (so excede contagem) continua usando a regra antiga: move o MENOR primeiro
csv11=$(mktemp)
cat > "$csv11" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
# max_clientes=2 (excedente=1). max_devices=1000 (total srv1=90, bem abaixo - sem excesso de devices)
out11=$(run_awk "$csv11" 2 "" "" 1000)
assert_eq "c2,srv1,srv2,10" "$out11" "sem excesso de devices, continua movendo o menor cliente primeiro mesmo com max_devices configurado"
rm -f "$csv11"

# Caso 12: excedente por devices sem candidato movivel (unico cliente >5000) ->
# aviso deve citar tambem a quantidade de devices que ficou acima do limite
csv12=$(mktemp)
cat > "$csv12" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
EOF
stderr12=$(mktemp)
out12=$(run_awk "$csv12" 10 "" "" 1000 2>"$stderr12")
err12=$(cat "$stderr12")
assert_eq "" "$out12" "cliente >5000 devices nao pode ser movido mesmo quando o excedente e' de devices"
assert_contains "$err12" "5000 devices" "aviso deve citar a quantidade de devices que permanece acima do limite"
rm -f "$csv12" "$stderr12"
