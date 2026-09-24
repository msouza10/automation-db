#!/bin/bash
# balance.sh - gera plano de movimentacao de clientes entre servidores.
# Uso: ./balance.sh [--dry-run] <env> <caminho-do-csv>
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AWK_SCRIPT="$SCRIPT_DIR/lib/balance.awk"
REPORT_SCRIPT="$SCRIPT_DIR/lib/report.awk"
EXPORT_SCRIPT="$SCRIPT_DIR/lib/export_results.awk"

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
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_DIR="$SCRIPT_DIR/results/$ENV/$TIMESTAMP"
if [ -d "$RESULTS_DIR" ]; then
    # colisao de timestamp (duas execucoes no mesmo segundo): nunca reusar
    # uma pasta ja existente, desambigua com o PID desta execucao
    RESULTS_DIR="${RESULTS_DIR}_$$"
fi
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

RESULT_CSV="$RESULTS_DIR/result.csv"
PACKED_DIR="$SCRIPT_DIR/packed/$ENV"
ZIP_FILE="$PACKED_DIR/migration_${ENV}-$(date +%m-%d-%Y)_${TIMESTAMP#*_}.zip"
ZIP_CREATED=0

if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

    DESTINATIONS=$(cut -d',' -f3 "$MOVES_TMP" | sort -u)
    for destination in $DESTINATIONS; do
        awk -F',' -v d="$destination" '$3==d' "$MOVES_TMP" \
            | sort -t',' -k4,4nr -k1,1 \
            | cut -d',' -f1 > "$RESULTS_DIR/to_$destination.txt"
    done

    awk -f "$EXPORT_SCRIPT" "$CSV" "$MOVES_TMP" > "$RESULT_CSV"

    if [ "$TOTAL_MOVED" -gt 0 ]; then
        mkdir -p "$PACKED_DIR"
        if command -v zip >/dev/null 2>&1 && zip -j -q "$ZIP_FILE" "$RESULTS_DIR"/to_*.txt; then
            ZIP_CREATED=1
        else
            rm -f "$ZIP_FILE"
        fi
    fi
fi

REPORT_TMP=$(mktemp)
awk -f "$REPORT_SCRIPT" "$CSV" "$MOVES_TMP" | sort > "$REPORT_TMP"

SUMMARY_TMP=$(mktemp)
awk -F',' '
    NR == FNR {
        clients_before[$1] = $2
        devices_before[$1] = $3
        clients_after[$1] = $4
        devices_after[$1] = $5
        next
    }
    {
        lost[$2]++; received[$3]++
        seen[$2] = 1; seen[$3] = 1
    }
    END {
        for (s in seen) {
            change = devices_after[s] - devices_before[s]
            sign = (change > 0) ? "+" : ""
            print s "," clients_before[s] "," clients_after[s] "," (lost[s] + 0) "," (received[s] + 0) "," devices_before[s] "," devices_after[s] "," sign change
        }
    }
' "$REPORT_TMP" "$MOVES_TMP" | sort > "$SUMMARY_TMP"

SERVERS_AFFECTED=$(wc -l < "$SUMMARY_TMP" | tr -d ' ')
TOTAL_DEVICES_MOVED=$(awk -F',' '{sum += $4} END {print sum + 0}' "$MOVES_TMP")

# capturado num arquivo tambem, pra poder ser reaproveitado no log de execucao
REPORT_TXT_TMP=$(mktemp)
{
    echo ""
    echo "=== BEFORE ==="
    { echo "SERVER,CLIENTS,DEVICES"; cut -d',' -f1,2,3 "$REPORT_TMP"; } | column -t -s','

    echo ""
    echo "=== MOVES ==="
    format_moves "$MOVES_TMP"

    echo ""
    echo "=== AFTER ==="
    { echo "SERVER,CLIENTS,DEVICES"; cut -d',' -f1,4,5 "$REPORT_TMP"; } | column -t -s','

    echo ""
    echo "=== SUMMARY BY SERVER ==="
    {
        echo "SERVER,CLIENTS_BEFORE,CLIENTS_AFTER,LOST,RECEIVED,DEVICES_BEFORE,DEVICES_AFTER,DEVICES_CHANGE"
        cat "$SUMMARY_TMP"
    } | column -t -s','

    echo ""
    echo "TOTAL: $TOTAL_MOVED client(s) moved, $TOTAL_DEVICES_MOVED device(s) moved across $SERVERS_AFFECTED server(s) affected."

    echo ""
    echo "=== DESTINATIONS BY LARGEST CLIENT ==="
    if [ -s "$MOVES_TMP" ]; then
        {
            echo "SERVER,LARGEST_CLIENT,DEVICES"
            awk -F',' '
                {
                    d = $3; c = $1; dv = $4 + 0
                    if (!(d in maxdev) || dv > maxdev[d] || (dv == maxdev[d] && c < maxclient[d])) {
                        maxdev[d] = dv
                        maxclient[d] = c
                    }
                }
                END {
                    for (d in maxdev) print d "," maxclient[d] "," maxdev[d]
                }
            ' "$MOVES_TMP" | sort -t',' -k3,3nr -k1,1
        } | column -t -s','
    else
        echo "  (none)"
    fi
} | tee "$REPORT_TXT_TMP"

rm -f "$REPORT_TMP" "$SUMMARY_TMP"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    echo "Summary: $TOTAL_MOVED client(s) would be moved in $ENV (dry-run: no file was written)."
    if [ "$TOTAL_WARNINGS" -gt 0 ]; then
        echo "$TOTAL_WARNINGS warning(s):"
        sed 's/^/  /' "$STDERR_TMP"
    fi
    rm -f "$MOVES_TMP" "$STDERR_TMP" "$REPORT_TXT_TMP"
    exit 0
fi

LOG_FILE="$LOGS_DIR/balance_${TIMESTAMP}.log"

{
    echo "Run: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Environment: $ENV"
    echo "CSV: $CSV"
    echo "Config: $CONFIG_FILE"
    cat "$REPORT_TXT_TMP"
    echo ""
    if [ "$TOTAL_WARNINGS" -gt 0 ]; then
        echo "Warnings:"
        sed 's/^/  /' "$STDERR_TMP"
        echo ""
    fi
    echo "Summary: $TOTAL_MOVED client(s) moved, $TOTAL_WARNINGS warning(s)"
} > "$LOG_FILE"

rm -f "$MOVES_TMP" "$STDERR_TMP" "$REPORT_TXT_TMP"

echo ""
echo "Summary: $TOTAL_MOVED client(s) moved in $ENV. Full log: $LOG_FILE"
echo "Result CSV: $RESULT_CSV"
if [ "$TOTAL_MOVED" -gt 0 ]; then
    if [ "$ZIP_CREATED" -eq 1 ]; then
        echo "Zip: $ZIP_FILE"
    else
        echo "WARNING: could not create zip $ZIP_FILE (is 'zip' installed?)"
    fi
fi
if [ "$TOTAL_WARNINGS" -gt 0 ]; then
    echo "$TOTAL_WARNINGS warning(s) - see $LOG_FILE"
fi

exit 0
