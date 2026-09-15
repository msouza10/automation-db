# lib/relatorio.awk
#
# Gera, por servidor, a contagem de clientes e o total de devices antes
# e depois de um plano de movimentacoes.
#
# Uso:
#   awk -f lib/relatorio.awk planilha.csv movimentacoes.csv
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
    if (!(s in antes_count)) { ordem_n++; ordem[ordem_n] = s }
    antes_count[s]++
    antes_dev[s] += d
    depois_count[s] = antes_count[s]
    depois_dev[s] = antes_dev[s]
    next
}

{
    sub(/\r$/, "", $0)
    if (NF < 4) next
    origem = $2
    destino = $3
    dv = $4 + 0
    depois_count[origem]--
    depois_dev[origem] -= dv
    depois_count[destino]++
    depois_dev[destino] += dv
}

END {
    for (i = 1; i <= ordem_n; i++) {
        s = ordem[i]
        print s "," antes_count[s] "," antes_dev[s] "," depois_count[s] "," depois_dev[s]
    }
}
