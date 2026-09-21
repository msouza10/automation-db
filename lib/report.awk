# lib/report.awk
#
# Gera, por servidor, a contagem de clientes e o total de devices antes
# e depois de um plano de movimentacoes.
#
# Uso:
#   awk -f lib/report.awk planilha.csv movimentacoes.csv
#
# planilha.csv: mesmo formato de entrada do balance.awk (header na 1a
# linha; coluna A=cliente, B=servidor, C=devices).
# movimentacoes.csv: saida do balance.awk (cliente,origem,destino,devices);
# pode estar vazio (nenhuma movimentacao).
#
# Saida (stdout), uma linha por servidor que aparece na planilha:
#   servidor,clientes_antes,devices_antes,clientes_depois,devices_depois

BEGIN { FS = "," }

FNR == NR {
    if (FNR == 1) next
    sub(/\r$/, "", $0)
    s = $2
    d = ($3 == "" ? 0 : $3) + 0
    if (!(s in before_count)) { order_n++; order[order_n] = s }
    before_count[s]++
    before_dev[s] += d
    after_count[s] = before_count[s]
    after_dev[s] = before_dev[s]
    next
}

{
    sub(/\r$/, "", $0)
    if (NF < 4) next
    source = $2
    destination = $3
    dv = $4 + 0
    after_count[source]--
    after_dev[source] -= dv
    after_count[destination]++
    after_dev[destination] += dv
}

END {
    for (i = 1; i <= order_n; i++) {
        s = order[i]
        print s "," before_count[s] "," before_dev[s] "," after_count[s] "," after_dev[s]
    }
}
