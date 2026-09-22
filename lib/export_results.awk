# lib/export_results.awk
#
# Gera a planilha final: a mesma planilha de entrada, com duas colunas
# adicionadas no final - o servidor de destino de cada cliente que foi
# movido e a quantidade de devices dele la. Cliente que nao foi movido
# fica com as duas colunas em branco.
#
# Uso:
#   awk -f lib/export_results.awk planilha.csv movimentacoes.csv
#
# planilha.csv: mesma entrada usada pelo balance.awk (header na 1a linha;
# coluna A=cliente, B=servidor, C=devices).
# movimentacoes.csv: saida do balance.awk (cliente,origem,destino,devices);
# pode estar vazio (nenhuma movimentacao) - a planilha e' lida primeiro e
# guardada em memoria justamente para nao depender do idiom FNR==NR (que
# quebra quando o PRIMEIRO arquivo passado esta vazio).
#
# Saida (stdout): cada linha da planilha original (com todas as colunas
# originais preservadas), mais "New Server,Qty New Server" no final.

BEGIN { FS = "," }

FNR == NR {
    sub(/\r$/, "", $0)
    n_lines++
    line[n_lines] = $0
    if (FNR > 1) client_of[n_lines] = $1
    next
}

{
    sub(/\r$/, "", $0)
    if (NF < 4) next
    new_server[$1] = $3
    new_qty[$1] = $4
}

END {
    for (i = 1; i <= n_lines; i++) {
        if (i == 1) {
            print line[i] ",New Server,Qty New Server"
            continue
        }
        c = client_of[i]
        if (c in new_server) {
            print line[i] "," new_server[c] "," new_qty[c]
        } else {
            print line[i] ",,"
        }
    }
}
