# lib/balance.awk
#
# Motor de balanceamento de clientes entre servidores.
#
# Uso:
#   awk -v max=100 -v excluded_csv="srvA,srvB" -v receiver="srvC" \
#       -f lib/balance.awk planilha.csv
#
# Entrada: CSV com header na 1a linha; coluna A = cliente, coluna B =
# servidor atual, coluna C = quantidade de devices. Colunas extras sao
# ignoradas.
#
# Saida (stdout): uma linha por movimentacao decidida:
#   cliente,servidor_origem,servidor_destino,devices
#
# Avisos (stderr), prefixados com "AVISO ", quando um servidor excedente
# nao pode ser totalmente resolvido (falta de clientes moviveis e/ou
# falta de capacidade de destino).

BEGIN {
    FS = ","
    n_excluded = split(excluded_csv, excluded_list, ",")
    for (i = 1; i <= n_excluded; i++) {
        if (excluded_list[i] != "") is_excluded[excluded_list[i]] = 1
    }
}

{ sub(/\r$/, "", $0) }

NR == 1 { next }

receiver != "" && $2 == receiver { next }

{
    cliente[NR] = $1
    servidor[NR] = $2
    devices[NR] = ($3 == "" ? 0 : $3) + 0
    count[$2]++
    n_clientes[$2]++
    clientes_de[$2, n_clientes[$2]] = NR
}

END {
    for (s in count) {
        if (count[s] > max) {
            excesso[s] = count[s] - max
        } else if (count[s] < max && !(s in is_excluded)) {
            capacidade[s] = max - count[s]
            destinos_n++
            destinos[destinos_n] = s
        }
    }

    for (s in excesso) {
        m = n_clientes[s]
        for (i = 1; i <= m; i++) ordem[i] = clientes_de[s, i]
        qsort(ordem, 1, m)

        faltam = excesso[s]
        for (i = 1; i <= m && faltam > 0; i++) {
            idx = ordem[i]
            if (devices[idx] > 5000) continue
            faltam--
            n_mover++
            mover[n_mover] = idx
        }
        if (faltam > 0) {
            print "AVISO " s " permanece " faltam " cliente(s) acima do limite (sem candidatos moviveis)" > "/dev/stderr"
        }
        delete ordem
    }

    for (i = 1; i <= n_mover; i++) {
        idx = mover[i]
        melhor = ""
        melhor_cap = 0
        for (j = 1; j <= destinos_n; j++) {
            d = destinos[j]
            if (d in capacidade && capacidade[d] > melhor_cap) {
                melhor = d
                melhor_cap = capacidade[d]
            }
        }
        if (melhor == "") {
            print "AVISO " servidor[idx] " nao conseguiu mover cliente " cliente[idx] " (sem capacidade de destino disponivel)" > "/dev/stderr"
            continue
        }
        capacidade[melhor]--
        if (capacidade[melhor] == 0) delete capacidade[melhor]
        print cliente[idx] "," servidor[idx] "," melhor "," devices[idx]
    }
}

function qsort(A, left, right,    i, last) {
    if (left >= right) return
    swap(A, left, int((left + right) / 2))
    last = left
    for (i = left + 1; i <= right; i++) {
        if (devices[A[i]] < devices[A[left]]) {
            last++
            swap(A, last, i)
        }
    }
    swap(A, left, last)
    qsort(A, left, last - 1)
    qsort(A, last + 1, right)
}

function swap(A, i, j,   t) {
    t = A[i]
    A[i] = A[j]
    A[j] = t
}
