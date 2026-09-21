#!/bin/bash
# balance.sh - gera plano de movimentacao de clientes entre servidores.
# Uso: ./balance.sh [--dry-run] <env> <caminho-do-csv>
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWK_SCRIPT="$SCRIPT_DIR/lib/balance.awk"
REPORT_SCRIPT="$SCRIPT_DIR/lib/report.awk"

error() {
    echo "ERROR: $1" >&2
    exit 1
}

format_moves() {
    if [ -s "$1" ]; then
        while IFS=',' read -r client source destination devices; do
            echo "  $client: $source -> $destination ($devices devices)"
        done < "$1"
    else
        echo "  (none)"
    fi
}

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    shift
fi

[ $# -eq 2 ] || error "usage: $0 [--dry-run] <env> <csv-path>"

ENV="$1"
CSV="$2"

CONFIG_DIR="$SCRIPT_DIR/configs/$ENV"
CONFIG_FILE="$CONFIG_DIR/config.conf"
RESULTS_DIR="$SCRIPT_DIR/results/$ENV"
LOGS_DIR="$SCRIPT_DIR/logs/$ENV"

[ -d "$CONFIG_DIR" ] || error "environment '$ENV' not found (expected $CONFIG_DIR)"
[ -f "$CONFIG_FILE" ] || error "config not found: $CONFIG_FILE"
[ -r "$CONFIG_FILE" ] || error "config not readable: $CONFIG_FILE"
[ -f "$CSV" ] || error "csv not found: $CSV"
[ -r "$CSV" ] || error "csv not readable: $CSV"

MAX_CLIENTS_PER_SERVER=""
EXCLUDED_SERVERS=""
RECEIVER_SERVER=""
MAX_DEVICES_PER_SERVER=""
# shellcheck disable=SC1090
. "$CONFIG_FILE"

[ -n "$MAX_CLIENTS_PER_SERVER" ] || error "invalid config: MAX_CLIENTS_PER_SERVER not defined in $CONFIG_FILE"
case "$MAX_CLIENTS_PER_SERVER" in
    ''|*[!0-9]*) error "invalid config: MAX_CLIENTS_PER_SERVER must be an integer (current value: '$MAX_CLIENTS_PER_SERVER')" ;;
esac
[ -n "$RECEIVER_SERVER" ] || error "invalid config: RECEIVER_SERVER not defined in $CONFIG_FILE"
if [ -n "$MAX_DEVICES_PER_SERVER" ]; then
    case "$MAX_DEVICES_PER_SERVER" in
        ''|*[!0-9]*) error "invalid config: MAX_DEVICES_PER_SERVER must be an integer (current value: '$MAX_DEVICES_PER_SERVER')" ;;
    esac
fi

MOVES_TMP=$(mktemp)
STDERR_TMP=$(mktemp)

awk -v max="$MAX_CLIENTS_PER_SERVER" \
    -v excluded_csv="$EXCLUDED_SERVERS" \
    -v receiver="$RECEIVER_SERVER" \
    -v max_devices="$MAX_DEVICES_PER_SERVER" \
    -f "$AWK_SCRIPT" "$CSV" > "$MOVES_TMP" 2> "$STDERR_TMP"

TOTAL_MOVED=$(wc -l < "$MOVES_TMP" | tr -d ' ')
TOTAL_WARNINGS=$(wc -l < "$STDERR_TMP" | tr -d ' ')

if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
    rm -f "$RESULTS_DIR"/to_*.txt

    DESTINATIONS=$(cut -d',' -f3 "$MOVES_TMP" | sort -u)
    for destination in $DESTINATIONS; do
        awk -F',' -v d="$destination" '$3==d {print $1}' "$MOVES_TMP" | sort > "$RESULTS_DIR/to_$destination.txt"
    done
fi

REPORT_TMP=$(mktemp)
awk -f "$REPORT_SCRIPT" "$CSV" "$MOVES_TMP" | sort > "$REPORT_TMP"

echo ""
echo "=== BEFORE ==="
{ echo "SERVER,CLIENTS,DEVICES"; cut -d',' -f1,2,3 "$REPORT_TMP"; } | column -t -s','

echo ""
echo "=== MOVES ==="
format_moves "$MOVES_TMP"

echo ""
echo "=== SUMMARY BY SERVER ==="
{
    echo "SERVER,LOST,RECEIVED"
    awk -F',' '{ lost[$2]++; received[$3]++; seen[$2]=1; seen[$3]=1 } END { for (s in seen) print s","(lost[s]+0)","(received[s]+0) }' "$MOVES_TMP" | sort
} | column -t -s','

echo ""
echo "=== AFTER ==="
{ echo "SERVER,CLIENTS,DEVICES"; cut -d',' -f1,4,5 "$REPORT_TMP"; } | column -t -s','

rm -f "$REPORT_TMP"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Summary: $TOTAL_MOVED client(s) would be moved in $ENV (dry-run: no file was written)."
    if [ "$TOTAL_WARNINGS" -gt 0 ]; then
        echo "$TOTAL_WARNINGS warning(s):"
        sed 's/^/  /' "$STDERR_TMP"
    fi
    rm -f "$MOVES_TMP" "$STDERR_TMP"
    exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/balance_${TIMESTAMP}.log"

{
    echo "Run: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Environment: $ENV"
    echo "CSV: $CSV"
    echo "Config: $CONFIG_FILE"
    echo ""
    echo "Moves:"
    format_moves "$MOVES_TMP"
    echo ""
    if [ "$TOTAL_WARNINGS" -gt 0 ]; then
        echo "Warnings:"
        sed 's/^/  /' "$STDERR_TMP"
        echo ""
    fi
    echo "Summary: $TOTAL_MOVED client(s) moved, $TOTAL_WARNINGS warning(s)"
} > "$LOG_FILE"

rm -f "$MOVES_TMP" "$STDERR_TMP"

echo ""
echo "Summary: $TOTAL_MOVED client(s) moved in $ENV. Full log: $LOG_FILE"
if [ "$TOTAL_WARNINGS" -gt 0 ]; then
    echo "$TOTAL_WARNINGS warning(s) - see $LOG_FILE"
fi

exit 0
