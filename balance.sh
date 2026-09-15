#!/bin/bash
# balance.sh - gera plano de movimentacao de clientes entre servidores.
# Uso: ./balance.sh [--dry-run] <env> <caminho-do-csv>
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWK_SCRIPT="$SCRIPT_DIR/lib/balance.awk"
RELATORIO_SCRIPT="$SCRIPT_DIR/lib/relatorio.awk"

erro() {
    echo "ERRO: $1" >&2
    exit 1
}

formatar_movimentacoes() {
    if [ -s "$1" ]; then
        while IFS=',' read -r cliente origem destino devices; do
            echo "  $cliente: $origem -> $destino ($devices devices)"
        done < "$1"
    else
        echo "  (nenhuma)"
    fi
}

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    shift
fi

[ $# -eq 2 ] || erro "uso: $0 [--dry-run] <env> <caminho-do-csv>"

ENV="$1"
CSV="$2"

CONFIG_DIR="$SCRIPT_DIR/configs/$ENV"
CONFIG_FILE="$CONFIG_DIR/config.conf"
RESULTS_DIR="$SCRIPT_DIR/results/$ENV"
LOGS_DIR="$SCRIPT_DIR/logs/$ENV"

[ -d "$CONFIG_DIR" ] || erro "ambiente '$ENV' nao encontrado (esperava $CONFIG_DIR)"
[ -f "$CONFIG_FILE" ] || erro "config nao encontrado: $CONFIG_FILE"
[ -r "$CONFIG_FILE" ] || erro "config sem permissao de leitura: $CONFIG_FILE"
[ -f "$CSV" ] || erro "csv nao encontrado: $CSV"
[ -r "$CSV" ] || erro "csv sem permissao de leitura: $CSV"

MAX_CLIENTES_POR_SERVIDOR=""
SERVIDORES_EXCLUIDOS=""
SERVIDOR_RECEBEDOR=""
MAX_DEVICES_POR_SERVIDOR=""
# shellcheck disable=SC1090
. "$CONFIG_FILE"

[ -n "$MAX_CLIENTES_POR_SERVIDOR" ] || erro "config invalido: MAX_CLIENTES_POR_SERVIDOR nao definido em $CONFIG_FILE"
case "$MAX_CLIENTES_POR_SERVIDOR" in
    ''|*[!0-9]*) erro "config invalido: MAX_CLIENTES_POR_SERVIDOR deve ser um inteiro (valor atual: '$MAX_CLIENTES_POR_SERVIDOR')" ;;
esac
[ -n "$SERVIDOR_RECEBEDOR" ] || erro "config invalido: SERVIDOR_RECEBEDOR nao definido em $CONFIG_FILE"
if [ -n "$MAX_DEVICES_POR_SERVIDOR" ]; then
    case "$MAX_DEVICES_POR_SERVIDOR" in
        ''|*[!0-9]*) erro "config invalido: MAX_DEVICES_POR_SERVIDOR deve ser um inteiro (valor atual: '$MAX_DEVICES_POR_SERVIDOR')" ;;
    esac
fi

MOVES_TMP=$(mktemp)
STDERR_TMP=$(mktemp)

awk -v max="$MAX_CLIENTES_POR_SERVIDOR" \
    -v excluded_csv="$SERVIDORES_EXCLUIDOS" \
    -v receiver="$SERVIDOR_RECEBEDOR" \
    -v max_devices="$MAX_DEVICES_POR_SERVIDOR" \
    -f "$AWK_SCRIPT" "$CSV" > "$MOVES_TMP" 2> "$STDERR_TMP"

TOTAL_MOVIDOS=$(wc -l < "$MOVES_TMP" | tr -d ' ')
TOTAL_AVISOS=$(wc -l < "$STDERR_TMP" | tr -d ' ')

if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    rm -f "$RESULTS_DIR"/to_*.txt

    DESTINOS=$(cut -d',' -f3 "$MOVES_TMP" | sort -u)
    for destino in $DESTINOS; do
        awk -F',' -v d="$destino" '$3==d {print $1}' "$MOVES_TMP" | sort > "$RESULTS_DIR/to_$destino.txt"
    done
fi

REPORT_TMP=$(mktemp)
awk -f "$RELATORIO_SCRIPT" "$CSV" "$MOVES_TMP" | sort > "$REPORT_TMP"

echo ""
echo "=== ANTES ==="
{ echo "SERVIDOR,CLIENTES,DEVICES"; cut -d',' -f1,2,3 "$REPORT_TMP"; } | column -t -s','

echo ""
echo "=== MOVIMENTACOES ==="
formatar_movimentacoes "$MOVES_TMP"

echo ""
echo "=== RESUMO POR SERVIDOR ==="
{
    echo "SERVIDOR,PERDEU,RECEBEU"
    awk -F',' '{ perdeu[$2]++; recebeu[$3]++; visto[$2]=1; visto[$3]=1 } END { for (s in visto) print s","(perdeu[s]+0)","(recebeu[s]+0) }' "$MOVES_TMP" | sort
} | column -t -s','

echo ""
echo "=== DEPOIS ==="
{ echo "SERVIDOR,CLIENTES,DEVICES"; cut -d',' -f1,4,5 "$REPORT_TMP"; } | column -t -s','

rm -f "$REPORT_TMP"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Resumo: $TOTAL_MOVIDOS cliente(s) seriam movido(s) em $ENV (dry-run: nenhum arquivo foi escrito)."
    if [ "$TOTAL_AVISOS" -gt 0 ]; then
        echo "$TOTAL_AVISOS aviso(s):"
        sed 's/^/  /' "$STDERR_TMP"
    fi
    rm -f "$MOVES_TMP" "$STDERR_TMP"
    exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/balance_${TIMESTAMP}.log"

{
    echo "Execucao: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Ambiente: $ENV"
    echo "CSV: $CSV"
    echo "Config: $CONFIG_FILE"
    echo ""
    echo "Movimentacoes:"
    formatar_movimentacoes "$MOVES_TMP"
    echo ""
    if [ "$TOTAL_AVISOS" -gt 0 ]; then
        echo "Avisos:"
        sed 's/^/  /' "$STDERR_TMP"
        echo ""
    fi
    echo "Resumo: $TOTAL_MOVIDOS cliente(s) movido(s), $TOTAL_AVISOS aviso(s)"
} > "$LOG_FILE"

rm -f "$MOVES_TMP" "$STDERR_TMP"

echo ""
echo "Resumo: $TOTAL_MOVIDOS cliente(s) movido(s) em $ENV. Log completo: $LOG_FILE"
if [ "$TOTAL_AVISOS" -gt 0 ]; then
    echo "$TOTAL_AVISOS aviso(s) - veja $LOG_FILE"
fi

exit 0
