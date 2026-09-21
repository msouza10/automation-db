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
# Avisos (stderr), prefixados com "WARNING ", quando um servidor excedente
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
    client[NR] = $1
    server[NR] = $2
    devices[NR] = ($3 == "" ? 0 : $3) + 0
    count[$2]++
    total_devices[$2] += devices[NR]
    n_clients[$2]++
    clients_of[$2, n_clients[$2]] = NR
}

END {
    for (s in count) {
        excess_count = (count[s] > max) ? count[s] - max : 0
        excess_devices = 0
        if (max_devices != "" && total_devices[s] > max_devices) {
            excess_devices = total_devices[s] - max_devices
        }

        if (excess_count > 0 || excess_devices > 0) {
            excess[s] = excess_count
            excess_dev[s] = excess_devices
        } else if (count[s] < max && !(s in is_excluded) &&
                   (max_devices == "" || total_devices[s] < max_devices)) {
            capacity_count[s] = max - count[s]
            capacity_devices[s] = (max_devices != "") ? max_devices - total_devices[s] : -1
            destinations_n++
            destinations[destinations_n] = s
        }
    }

    for (s in excess) {
        m = n_clients[s]
        for (i = 1; i <= m; i++) order[i] = clients_of[s, i]
        SORT_DESC = (max_devices != "" && excess_dev[s] > 0) ? 1 : 0
        qsort(order, 1, m)

        remaining_count = excess[s]
        remaining_devices = excess_dev[s]
        for (i = 1; i <= m && (remaining_count > 0 || remaining_devices > 0); i++) {
            idx = order[i]
            if (devices[idx] > 5000) continue
            n_move++
            move[n_move] = idx
            if (remaining_count > 0) remaining_count--
            remaining_devices -= devices[idx]
            if (remaining_devices < 0) remaining_devices = 0
        }
        if (remaining_count > 0 || remaining_devices > 0) {
            if (max_devices != "") {
                print "WARNING " s " remains " remaining_count " client(s) and " remaining_devices " devices above the limit (no movable candidates)" > "/dev/stderr"
            } else {
                print "WARNING " s " remains " remaining_count " client(s) above the limit (no movable candidates)" > "/dev/stderr"
            }
        }
        delete order
    }

    for (i = 1; i <= n_move; i++) {
        idx = move[i]
        best = ""
        best_capacity = 0
        for (j = 1; j <= destinations_n; j++) {
            d = destinations[j]
            if (!(d in capacity_count)) continue
            if (capacity_devices[d] != -1 && capacity_devices[d] < devices[idx]) continue
            if (capacity_count[d] > best_capacity) {
                best = d
                best_capacity = capacity_count[d]
            }
        }
        if (best == "") {
            print "WARNING " server[idx] " could not move client " client[idx] " (no destination capacity available)" > "/dev/stderr"
            continue
        }
        capacity_count[best]--
        if (capacity_count[best] == 0) delete capacity_count[best]
        if (capacity_devices[best] != -1) capacity_devices[best] -= devices[idx]
        print client[idx] "," server[idx] "," best "," devices[idx]
    }
}

function less_than(a, b) {
    return SORT_DESC ? (a > b) : (a < b)
}

function qsort(A, left, right,    i, last) {
    if (left >= right) return
    swap(A, left, int((left + right) / 2))
    last = left
    for (i = left + 1; i <= right; i++) {
        if (less_than(devices[A[i]], devices[A[left]])) {
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
