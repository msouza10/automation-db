#!/bin/bash
# balance.sh - gera plano de movimentacao de clientes entre servidores.
# Uso: ./balance.sh <env> <caminho-do-csv>
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWK_SCRIPT="$SCRIPT_DIR/lib/balance.awk"

erro() {
    echo "ERRO: $1" >&2
    exit 1
}

[ $# -eq 2 ] || erro "uso: $0 <env> <caminho-do-csv>"

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
# shellcheck disable=SC1090
. "$CONFIG_FILE"

[ -n "$MAX_CLIENTES_POR_SERVIDOR" ] || erro "config invalido: MAX_CLIENTES_POR_SERVIDOR nao definido em $CONFIG_FILE"
case "$MAX_CLIENTES_POR_SERVIDOR" in
    ''|*[!0-9]*) erro "config invalido: MAX_CLIENTES_POR_SERVIDOR deve ser um inteiro (valor atual: '$MAX_CLIENTES_POR_SERVIDOR')" ;;
esac
[ -n "$SERVIDOR_RECEBEDOR" ] || erro "config invalido: SERVIDOR_RECEBEDOR nao definido em $CONFIG_FILE"
