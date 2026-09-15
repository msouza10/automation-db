# lib/balance.awk
#
# Motor de balanceamento de clientes entre servidores.
#
# Uso:
#   awk -v max=100 -v excluded_csv="srvA,srvB" -v receiver="srvC" \
#       -v max_devices=5000 -f lib/balance.awk planilha.csv
#
# max_devices e' opcional: se omitido/vazio, nenhum limite de devices por
# servidor e' aplicado (so o limite de contagem de clientes, "max").
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
#
# Um servidor fica excedente se ultrapassar QUALQUER um dos dois
# limites (contagem de clientes OU total de devices). Quando o excesso
# e' causado (tambem) pelo limite de devices, os clientes sao
# selecionados do MAIOR para o menor (minimiza o numero de
# movimentacoes); quando o excesso e' so de contagem, continua sendo do
# menor para o maior, como antes. Um servidor so e' destino elegivel se
# tiver folga tanto em contagem quanto (quando configurado) em devices
# suficiente para o cliente especifico sendo movido.

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
    total_devices[$2] += devices[NR]
    n_clientes[$2]++
    clientes_de[$2, n_clientes[$2]] = NR
}

END {
    for (s in count) {
        excesso_count = (count[s] > max) ? count[s] - max : 0
        excesso_devices = 0
        if (max_devices != "" && total_devices[s] > max_devices) {
            excesso_devices = total_devices[s] - max_devices
        }

        if (excesso_count > 0 || excesso_devices > 0) {
            excesso[s] = excesso_count
            excesso_dev[s] = excesso_devices
        } else if (count[s] < max && !(s in is_excluded) &&
                   (max_devices == "" || total_devices[s] < max_devices)) {
            capacidade_count[s] = max - count[s]
            capacidade_devices[s] = (max_devices != "") ? max_devices - total_devices[s] : -1
            destinos_n++
            destinos[destinos_n] = s
        }
    }

    for (s in excesso) {
        m = n_clientes[s]
        for (i = 1; i <= m; i++) ordem[i] = clientes_de[s, i]
        SORT_DESC = (max_devices != "" && excesso_dev[s] > 0) ? 1 : 0
        qsort(ordem, 1, m)

        faltam_count = excesso[s]
        faltam_devices = excesso_dev[s]
        for (i = 1; i <= m && (faltam_count > 0 || faltam_devices > 0); i++) {
            idx = ordem[i]
            if (devices[idx] > 5000) continue
            n_mover++
            mover[n_mover] = idx
            if (faltam_count > 0) faltam_count--
            faltam_devices -= devices[idx]
            if (faltam_devices < 0) faltam_devices = 0
        }
        if (faltam_count > 0 || faltam_devices > 0) {
            if (max_devices != "") {
                print "AVISO " s " permanece " faltam_count " cliente(s) e " faltam_devices " devices acima do limite (sem candidatos moviveis)" > "/dev/stderr"
            } else {
                print "AVISO " s " permanece " faltam_count " cliente(s) acima do limite (sem candidatos moviveis)" > "/dev/stderr"
            }
        }
        delete ordem
    }

    for (i = 1; i <= n_mover; i++) {
        idx = mover[i]
        melhor = ""
        melhor_cap = 0
        for (j = 1; j <= destinos_n; j++) {
            d = destinos[j]
            if (!(d in capacidade_count)) continue
            if (capacidade_devices[d] != -1 && capacidade_devices[d] < devices[idx]) continue
            if (capacidade_count[d] > melhor_cap) {
                melhor = d
                melhor_cap = capacidade_count[d]
            }
        }
        if (melhor == "") {
            print "AVISO " servidor[idx] " nao conseguiu mover cliente " cliente[idx] " (sem capacidade de destino disponivel)" > "/dev/stderr"
            continue
        }
        capacidade_count[melhor]--
        if (capacidade_count[melhor] == 0) delete capacidade_count[melhor]
        if (capacidade_devices[melhor] != -1) capacidade_devices[melhor] -= devices[idx]
        print cliente[idx] "," servidor[idx] "," melhor "," devices[idx]
    }
}

function menor(a, b) {
    return SORT_DESC ? (a > b) : (a < b)
}

function qsort(A, left, right,    i, last) {
    if (left >= right) return
    swap(A, left, int((left + right) / 2))
    last = left
    for (i = left + 1; i <= right; i++) {
        if (menor(devices[A[i]], devices[A[left]])) {
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
