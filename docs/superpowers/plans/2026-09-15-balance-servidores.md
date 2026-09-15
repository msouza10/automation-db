# Balanceamento de Clientes entre Servidores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `balance.sh`, a Bash 3.2-compatible script that reads a per-environment client CSV and generates `to_<servidor>.txt` move lists that bring every over-capacity server back to its configured client limit with the minimum number of movements.

**Architecture:** A single-file `awk` engine (`lib/balance.awk`) does all the data processing (grouping, classification, selection, greedy destination assignment) using awk's native associative arrays — this sidesteps the Bash 3.2 constraint entirely. A thin `balance.sh` orchestrates: argument/config validation, invoking the awk engine, splitting its output into per-destination files, and writing the execution log.

**Tech Stack:** Bash 3.2 (POSIX-ish constructs only — no `declare -A`, no `mapfile`, no `${var,,}`), `awk` (portable — no gawk-only builtins like `asort`), standard POSIX tools (`mktemp`, `sort`, `cut`, `sed`, `wc`, `date`).

**Spec:** `docs/superpowers/specs/2026-09-15-balance-servidores-design.md`

## Global Constraints

- Bash code must run under Bash 3.2: no `declare -A`, no `mapfile`/`readarray`, no `${var,,}`/`${var^^}`, no namerefs (`local -n`).
- `awk` code must be portable (no gawk-only extensions like `asort`/`asorti`) since the target `awk` may be BSD/nawk, not gawk.
- Rule: a client with `devices > 5000` is never a candidate to move. `devices == 5000` IS movable (spec §6.6).
- Rule: balancing only brings over-capacity servers down to the limit — never equalizes further (spec §6).
- `SERVIDOR_RECEBEDOR` is removed from the balancing universe entirely (never source, never destination), even if it already holds clients in the CSV (spec §6.2).
- `SERVIDORES_EXCLUIDOS` servers can be a source (lose clients) but never a destination (spec §6.3).
- No test may depend on `awk`'s hash iteration order (`for (k in array)`) for its expected result — construct fixtures so the outcome is unambiguous regardless of iteration order.
- All new files are Bash-3.2/portable-awk as above; no other language runtime is introduced.

---

## File Structure

- `lib/balance.awk` — the balancing engine (parsing, classification, selection, destination assignment). One file, one responsibility.
- `balance.sh` — orchestration: CLI validation, config loading, invoking `lib/balance.awk`, writing `results/<env>/to_*.txt`, writing `logs/<env>/balance_*.log`.
- `tests/harness.sh` — minimal assertion helpers (`assert_eq`, `assert_contains`, `assert_file_eq`, `assert_file_missing`).
- `tests/run_tests.sh` — discovers and runs every `tests/test_*.sh`, aggregates pass/fail counts.
- `tests/test_balance_awk.sh` — unit tests for `lib/balance.awk` (called directly with `awk -f`, no bash orchestration involved).
- `tests/test_balance_sh_validation.sh` — unit tests for `balance.sh`'s argument/config validation.
- `tests/test_balance_sh_output.sh` — unit tests for `balance.sh`'s output-file generation and stale-file cleanup.
- `tests/test_integration.sh` — end-to-end test running the full `balance.sh` against a multi-server fixture exercising every business rule together.

---

### Task 1: Test harness

**Files:**
- Create: `tests/harness.sh`
- Create: `tests/run_tests.sh`
- Test: `tests/test_harness_selfcheck.sh`

**Interfaces:**
- Produces: `assert_eq "$expected" "$actual" "$msg"`, `assert_contains "$haystack" "$needle" "$msg"`, `assert_file_eq "$expected_file" "$actual_file" "$msg"`, `assert_file_missing "$file" "$msg"` — each prints `PASS: $msg` or `FAIL: $msg` (+ details) to stdout, returns 0/1, and increments the global counters `$TESTS_RUN`/`$TESTS_FAILED`. `tests/run_tests.sh` sources `tests/harness.sh`, sources every `tests/test_*.sh` in turn (each file is plain top-level assertion calls, not wrapped in a function), and exports `PROJECT_ROOT` (absolute path to the repo root) for test files to use.

- [ ] **Step 1: Write `tests/harness.sh`**

```bash
#!/bin/bash
# tests/harness.sh - funcoes de asserção simples, Bash 3.2-compatível.
# Uso: sourced por tests/run_tests.sh antes de cada tests/test_*.sh.

TESTS_RUN=0
TESTS_FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" != "$actual" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  esperado: $expected"
        echo "  obtido:   $actual"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$haystack" in
        *"$needle"*)
            echo "PASS: $msg"
            return 0
            ;;
        *)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "FAIL: $msg"
            echo "  esperava conter: $needle"
            echo "  obtido:          $haystack"
            return 1
            ;;
    esac
}

assert_file_eq() {
    local expected_file="$1"
    local actual_file="$2"
    local msg="$3"
    local diff_output
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$actual_file" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  arquivo nao existe: $actual_file"
        return 1
    fi
    diff_output=$(diff -u "$expected_file" "$actual_file" 2>&1)
    if [ -n "$diff_output" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "$diff_output"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}

assert_file_missing() {
    local file="$1"
    local msg="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$file" ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: $msg"
        echo "  arquivo nao deveria existir: $file"
        return 1
    fi
    echo "PASS: $msg"
    return 0
}
```

- [ ] **Step 2: Write `tests/run_tests.sh`**

```bash
#!/bin/bash
# tests/run_tests.sh - roda todos os tests/test_*.sh e agrega o resultado.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export PROJECT_ROOT

# shellcheck disable=SC1090
. "$SCRIPT_DIR/harness.sh"

TOTAL_RUN=0
TOTAL_FAILED=0
OVERALL_FAIL=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue
    echo "--- $(basename "$test_file") ---"
    TESTS_RUN=0
    TESTS_FAILED=0
    # shellcheck disable=SC1090
    . "$test_file"
    TOTAL_RUN=$((TOTAL_RUN + TESTS_RUN))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))
    if [ "$TESTS_FAILED" -ne 0 ]; then
        OVERALL_FAIL=1
    fi
    echo ""
done

echo "===================================="
echo "TOTAL: $TOTAL_RUN teste(s), $TOTAL_FAILED falha(s)"
exit "$OVERALL_FAIL"
```

- [ ] **Step 3: Write the harness self-check test — `tests/test_harness_selfcheck.sh`**

```bash
# tests/test_harness_selfcheck.sh - valida o proprio harness antes de confiar nele.

assert_eq "5" "5" "assert_eq deve passar quando os valores sao iguais"
assert_contains "abcdef" "cde" "assert_contains deve passar quando a substring existe"

# roda em subshell para nao contaminar os contadores globais desta suite
# com a falha proposital abaixo
if (assert_eq "5" "6" "checagem interna" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_eq deveria retornar falha quando os valores diferem"
else
    echo "PASS: assert_eq retorna falha quando os valores diferem"
fi
TESTS_RUN=$((TESTS_RUN + 1))

if (assert_contains "abcdef" "zzz" "checagem interna" > /dev/null 2>&1); then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: assert_contains deveria retornar falha quando a substring nao existe"
else
    echo "PASS: assert_contains retorna falha quando a substring nao existe"
fi
TESTS_RUN=$((TESTS_RUN + 1))
```

- [ ] **Step 4: Make scripts executable and run the suite**

Run: `chmod +x tests/run_tests.sh && bash tests/run_tests.sh`
Expected: `TOTAL: 4 teste(s), 0 falha(s)` and exit code `0`.

- [ ] **Step 5: Commit**

```bash
git add tests/harness.sh tests/run_tests.sh tests/test_harness_selfcheck.sh
git commit -m "Add bash test harness and runner

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Motor de balanceamento em awk (`lib/balance.awk`)

**Files:**
- Create: `lib/balance.awk`
- Test: `tests/test_balance_awk.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks besides `tests/harness.sh` assertions (Task 1).
- Produces: `lib/balance.awk`, invoked as `awk -v max=N -v excluded_csv="a,b" -v receiver="r" -f lib/balance.awk arquivo.csv`. Stdout: one line per movement, `cliente,servidor_origem,servidor_destino,devices`. Stderr: warning lines prefixed `AVISO `. This exact invocation and output format is what Task 4 (`balance.sh`) will call.

- [ ] **Step 1: Write the full test suite — `tests/test_balance_awk.sh`**

```bash
# tests/test_balance_awk.sh - testa lib/balance.awk isoladamente.

AWK_SCRIPT="$PROJECT_ROOT/lib/balance.awk"

run_awk() {
    # $1=csv $2=max $3=excluded_csv $4=receiver
    awk -v max="$2" -v excluded_csv="$3" -v receiver="$4" -f "$AWK_SCRIPT" "$1"
}

# Caso 1: nenhum servidor acima do limite -> nenhuma movimentacao
csv1=$(mktemp)
cat > "$csv1" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv1,20,-,2024-01-01
c3,srv2,5,-,2024-01-01
EOF
out1=$(run_awk "$csv1" 5 "" "")
assert_eq "" "$out1" "sem servidor acima do limite, nao deve haver movimentacao"
rm -f "$csv1"

# Caso 2: um servidor acima do limite, outro com capacidade -> move o menor cliente
csv2=$(mktemp)
cat > "$csv2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
out2=$(run_awk "$csv2" 2 "" "")
assert_eq "c2,srv1,srv2,10" "$out2" "deve mover o cliente de menor devices (c2) de srv1 para srv2"
rm -f "$csv2"

# Caso 3: servidor recebedor fica inteiramente fora do balanceamento
csv3=$(mktemp)
cat > "$csv3" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,recv,1,-,2024-01-01
c4,recv,1,-,2024-01-01
c5,recv,1,-,2024-01-01
EOF
stderr3=$(mktemp)
out3=$(run_awk "$csv3" 1 "" "recv" 2>"$stderr3")
err3=$(cat "$stderr3")
assert_eq "" "$out3" "servidor recebedor nao deve receber nem gerar movimentacao"
assert_contains "$err3" "AVISO" "deve avisar que nao ha destino disponivel (recebedor esta fora do balanceamento)"
rm -f "$csv3" "$stderr3"

# Caso 4: servidor excluido pode ser origem mas nunca e' escolhido como destino,
# mesmo tendo mais folga que o unico destino elegivel
csv4=$(mktemp)
cat > "$csv4" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv1,40,-,2024-01-01
c5,srv2,1,-,2024-01-01
c6,srv3,1,-,2024-01-01
c7,srv3,1,-,2024-01-01
EOF
# max=3: srv1 tem 4 (excedente=1, menor=c2). srv2 tem 1 (capacidade=2, mas EXCLUIDO).
# srv3 tem 2 (capacidade=1, elegivel). Se a exclusao nao for respeitada, srv2 venceria
# por ter mais capacidade - este teste so passa se a exclusao for aplicada de verdade.
out4=$(run_awk "$csv4" 3 "srv2" "")
assert_eq "c2,srv1,srv3,10" "$out4" "servidor excluido nunca deve ser escolhido como destino, mesmo com mais folga"
rm -f "$csv4"

# Caso 5: atribuicao gulosa escolhe sempre o destino com mais capacidade disponivel
csv5=$(mktemp)
cat > "$csv5" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,100,-,2024-01-01
c2,srv1,5,-,2024-01-01
c3,srv1,7,-,2024-01-01
c4,srv1,9,-,2024-01-01
c5,srvA,1,-,2024-01-01
c6,srvA,1,-,2024-01-01
c7,srvB,1,-,2024-01-01
EOF
# max=3: srv1 tem 4 (excedente=1, menor=c2=5). srvA capacidade=1. srvB capacidade=2.
out5=$(run_awk "$csv5" 3 "" "")
assert_eq "c2,srv1,srvB,5" "$out5" "deve escolher o destino com mais capacidade disponivel (srvB) em vez de srvA"
rm -f "$csv5"

# Caso 6: todos os candidatos moviveis excedem 5000 devices -> aviso, nenhuma movimentacao
csv6=$(mktemp)
cat > "$csv6" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,7000,-,2024-01-01
EOF
stderr6=$(mktemp)
out6=$(run_awk "$csv6" 1 "" "" 2>"$stderr6")
err6=$(cat "$stderr6")
assert_eq "" "$out6" "nenhum cliente >5000 devices pode ser movido"
assert_contains "$err6" "permanece" "deve avisar que o servidor permanece acima do limite sem candidatos moviveis"
rm -f "$csv6" "$stderr6"

# Caso 7: cliente com devices == 5000 (limite exato) e' elegivel para mover
csv7=$(mktemp)
cat > "$csv7" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,5000,-,2024-01-01
c3,srv2,1,-,2024-01-01
EOF
out7=$(run_awk "$csv7" 1 "" "")
assert_eq "c2,srv1,srv2,5000" "$out7" "cliente com exatamente 5000 devices deve ser movivel (regra exclui apenas >5000)"
rm -f "$csv7"

# Caso 8: capacidade de destino insuficiente para todo o excedente -> move o que
# der e avisa sobre o restante
csv8=$(mktemp)
cat > "$csv8" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,10,-,2024-01-01
c2,srv1,20,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv1,40,-,2024-01-01
c5,srv2,1,-,2024-01-01
EOF
stderr8=$(mktemp)
out8=$(run_awk "$csv8" 2 "" "" 2>"$stderr8")
err8=$(cat "$stderr8")
assert_eq "c1,srv1,srv2,10" "$out8" "deve mover apenas o que a capacidade de destino permite (1 de 2 necessarios)"
assert_contains "$err8" "AVISO" "deve avisar sobre o cliente que nao coube em nenhum destino"
assert_contains "$err8" "c2" "o aviso deve identificar o cliente que nao pode ser movido"
rm -f "$csv8" "$stderr8"
```

- [ ] **Step 2: Run the suite and confirm every assertion fails (RED)**

Run: `bash tests/run_tests.sh`
Expected: every `test_balance_awk.sh` assertion FAILs with an awk error like `can't open file lib/balance.awk` (the file doesn't exist yet).

- [ ] **Step 3: Implement `lib/balance.awk`**

```awk
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
```

- [ ] **Step 4: Run the suite and confirm every assertion passes (GREEN)**

Run: `bash tests/run_tests.sh`
Expected: all 12 assertions in `test_balance_awk.sh` PASS (Casos 1,2,4,5,7 = 1 assertion each; Casos 3,6,8 = 2 assertions each). If any fail, fix `lib/balance.awk` and re-run until green — do not move on with red tests.

- [ ] **Step 5: Commit**

```bash
git add lib/balance.awk tests/test_balance_awk.sh
git commit -m "Add awk balancing engine with full unit test coverage

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `balance.sh` — validação de argumentos e config

**Files:**
- Create: `balance.sh`
- Test: `tests/test_balance_sh_validation.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks at runtime (this task only builds the validation prefix of `balance.sh`; Task 4 appends to the same file).
- Produces: `balance.sh <env> <csv>` — on invalid input, prints `ERRO: <msg>` to stderr and exits `1` without touching the filesystem. On valid input, it has sourced the config file and has `$MAX_CLIENTES_POR_SERVIDOR`, `$SERVIDORES_EXCLUIDOS`, `$SERVIDOR_RECEBEDOR`, `$ENV`, `$CSV`, `$CONFIG_FILE`, `$RESULTS_DIR`, `$LOGS_DIR`, `$SCRIPT_DIR`, `$AWK_SCRIPT` available as variables for Task 4 to use, and falls through (does not exit) to whatever code Task 4 appends next.

- [ ] **Step 1: Write `tests/test_balance_sh_validation.sh`**

```bash
# tests/test_balance_sh_validation.sh - testa a validacao de entrada de balance.sh.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

# monta um "projeto" minimo e isolado em um dir temporario, copiando
# balance.sh + lib/ para dentro (SCRIPT_DIR dentro do script e' resolvido
# pelo caminho do proprio balance.sh, entao ele precisa estar acompanhado
# da sua propria lib/ e configs/)
new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

# Caso 1: numero errado de argumentos
out=$("$BALANCE_SH" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar com codigo 1 quando faltam argumentos"
assert_contains "$out" "ERRO" "deve informar erro de uso quando faltam argumentos"

# Caso 2: ambiente inexistente
csv_tmp=$(mktemp)
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$BALANCE_SH" ambiente-que-nao-existe "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando o ambiente nao existe"
assert_contains "$out" "nao encontrado" "deve informar que o ambiente nao foi encontrado"
rm -f "$csv_tmp"

# Caso 3: csv inexistente com ambiente/config validos
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
SERVIDOR_RECEBEDOR=srvX
EOF
out=$("$proj/balance.sh" teste-env "$proj/nao-existe.csv" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando o csv nao existe"
assert_contains "$out" "csv nao encontrado" "deve informar que o csv nao foi encontrado"
rm -rf "$proj"

# Caso 4: config sem MAX_CLIENTES_POR_SERVIDOR
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
SERVIDOR_RECEBEDOR=srvX
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando MAX_CLIENTES_POR_SERVIDOR nao esta definido"
assert_contains "$out" "MAX_CLIENTES_POR_SERVIDOR" "deve citar a chave faltante no erro"
rm -rf "$proj"

# Caso 5: MAX_CLIENTES_POR_SERVIDOR nao numerico
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=abc
SERVIDOR_RECEBEDOR=srvX
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando MAX_CLIENTES_POR_SERVIDOR nao e' um inteiro"
assert_contains "$out" "inteiro" "deve informar que o valor precisa ser um inteiro"
rm -rf "$proj"

# Caso 6: config sem SERVIDOR_RECEBEDOR
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
EOF
csv_tmp="$proj/dados.csv"
echo "Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation" > "$csv_tmp"
out=$("$proj/balance.sh" teste-env "$csv_tmp" 2>&1)
rc=$?
assert_eq "1" "$rc" "deve falhar quando SERVIDOR_RECEBEDOR nao esta definido"
assert_contains "$out" "SERVIDOR_RECEBEDOR" "deve citar a chave faltante no erro"
rm -rf "$proj"
```

- [ ] **Step 2: Run the suite and confirm every assertion fails (RED)**

Run: `bash tests/run_tests.sh`
Expected: `test_balance_sh_validation.sh` assertions FAIL (`balance.sh: No such file or directory` or similar — the file doesn't exist yet).

- [ ] **Step 3: Implement `balance.sh` (validation prefix only)**

```bash
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
```

- [ ] **Step 4: Make executable, run the suite, confirm green (GREEN)**

Run: `chmod +x balance.sh && bash tests/run_tests.sh`
Expected: all 12 assertions in `test_balance_sh_validation.sh` PASS.

- [ ] **Step 5: Commit**

```bash
git add balance.sh tests/test_balance_sh_validation.sh
git commit -m "Add balance.sh CLI argument and config validation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Geração dos arquivos `to_<servidor>.txt`

**Files:**
- Modify: `balance.sh` (append after Task 3's validation block)
- Test: `tests/test_balance_sh_output.sh`

**Interfaces:**
- Consumes: `lib/balance.awk` (Task 2) via the exact invocation contract; `$MAX_CLIENTES_POR_SERVIDOR`/`$SERVIDORES_EXCLUIDOS`/`$SERVIDOR_RECEBEDOR`/`$CSV`/`$RESULTS_DIR`/`$AWK_SCRIPT` from Task 3's validated state.
- Produces: `results/<env>/to_<servidor>.txt` files (one per destination server that received at least one client, sorted alphabetically by client name, no header). Leaves `$MOVES_TMP` and `$STDERR_TMP` populated (awk's raw stdout/stderr) and `$TOTAL_MOVIDOS`/`$TOTAL_AVISOS` set as integers, for Task 5 to consume for logging. Exits `0` at the end of this task's code (Task 5 will remove this early exit when it appends logging).

- [ ] **Step 1: Write `tests/test_balance_sh_output.sh`**

```bash
# tests/test_balance_sh_output.sh - testa a geracao dos to_<servidor>.txt.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env" "$proj/results/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=2
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp="$proj/dados.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF
# arquivo de um destino que nao deveria mais existir apos a execucao,
# pra provar que a limpeza de to_*.txt antigos funciona
echo "cliente-fantasma" > "$proj/results/teste-env/to_srv-antigo.txt"

"$proj/balance.sh" teste-env "$csv_tmp" > /dev/null 2>&1

expected1=$(mktemp)
echo "c2" > "$expected1"
assert_file_eq "$expected1" "$proj/results/teste-env/to_srv2.txt" "to_srv2.txt deve conter apenas c2"
rm -f "$expected1"

assert_file_missing "$proj/results/teste-env/to_srv1.txt" "srv1 nao recebeu ninguem, nao deve ter arquivo de destino"
assert_file_missing "$proj/results/teste-env/to_srv-antigo.txt" "to_*.txt de execucao anterior deve ser removido"

rm -rf "$proj"

# Caso: nenhuma movimentacao necessaria -> nenhum arquivo to_*.txt gerado
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env2"
cat > "$proj/configs/teste-env2/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=10
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp2="$proj/dados2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv2,10,-,2024-01-01
EOF
"$proj/balance.sh" teste-env2 "$csv_tmp2" > /dev/null 2>&1
assert_file_missing "$proj/results/teste-env2/to_srv1.txt" "sem excedente, nenhum to_*.txt deve ser gerado (srv1)"
assert_file_missing "$proj/results/teste-env2/to_srv2.txt" "sem excedente, nenhum to_*.txt deve ser gerado (srv2)"
rm -rf "$proj"
```

- [ ] **Step 2: Run the suite and confirm the new assertions fail (RED)**

Run: `bash tests/run_tests.sh`
Expected: `test_balance_sh_output.sh` assertions FAIL — `results/teste-env/to_srv2.txt` is never created because `balance.sh` doesn't produce output yet.

- [ ] **Step 3: Append the output-generation block to `balance.sh`**

Add this immediately after the validation block from Task 3 (after the `SERVIDOR_RECEBEDOR` check):

```bash

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"
rm -f "$RESULTS_DIR"/to_*.txt

MOVES_TMP=$(mktemp)
STDERR_TMP=$(mktemp)

awk -v max="$MAX_CLIENTES_POR_SERVIDOR" \
    -v excluded_csv="$SERVIDORES_EXCLUIDOS" \
    -v receiver="$SERVIDOR_RECEBEDOR" \
    -f "$AWK_SCRIPT" "$CSV" > "$MOVES_TMP" 2> "$STDERR_TMP"

DESTINOS=$(cut -d',' -f3 "$MOVES_TMP" | sort -u)
for destino in $DESTINOS; do
    awk -F',' -v d="$destino" '$3==d {print $1}' "$MOVES_TMP" | sort > "$RESULTS_DIR/to_$destino.txt"
done

TOTAL_MOVIDOS=$(wc -l < "$MOVES_TMP" | tr -d ' ')
TOTAL_AVISOS=$(wc -l < "$STDERR_TMP" | tr -d ' ')

exit 0
```

- [ ] **Step 4: Run the suite and confirm green (GREEN)**

Run: `bash tests/run_tests.sh`
Expected: all assertions in `test_balance_sh_output.sh` PASS (5 assertions).

- [ ] **Step 5: Commit**

```bash
git add balance.sh tests/test_balance_sh_output.sh
git commit -m "Generate to_<servidor>.txt output files in balance.sh

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Log de execução

**Files:**
- Modify: `balance.sh` (replace the `exit 0` from Task 4 with the logging block below)
- Test: `tests/test_balance_sh_log.sh`

**Interfaces:**
- Consumes: `$MOVES_TMP`, `$STDERR_TMP`, `$TOTAL_MOVIDOS`, `$TOTAL_AVISOS`, `$ENV`, `$CSV`, `$CONFIG_FILE`, `$LOGS_DIR` from Task 4's state.
- Produces: `logs/<env>/balance_<timestamp>.log` (format: `YYYYMMDD_HHMMSS`), containing execution params, one line per movement (`cliente: origem -> destino (N devices)`), any `AVISO` lines, and a one-line summary. `balance.sh` prints a short summary to stdout and exits `0`.

- [ ] **Step 1: Write `tests/test_balance_sh_log.sh`**

```bash
# tests/test_balance_sh_log.sh - testa o log de execucao de balance.sh.

BALANCE_SH="$PROJECT_ROOT/balance.sh"

new_fake_project() {
    local dir
    dir=$(mktemp -d)
    cp "$BALANCE_SH" "$dir/balance.sh"
    cp -r "$PROJECT_ROOT/lib" "$dir/lib"
    echo "$dir"
}

proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=2
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp="$proj/dados.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,50,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,30,-,2024-01-01
c4,srv2,1,-,2024-01-01
EOF

stdout_tmp=$(mktemp)
"$proj/balance.sh" teste-env "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "execucao com sucesso deve retornar codigo 0"

log_file=$(find "$proj/logs/teste-env" -name 'balance_*.log' 2>/dev/null | head -n1)
assert_contains "$log_file" "balance_" "deve gerar um arquivo de log com o padrao balance_<timestamp>.log"

log_content=$(cat "$log_file")
assert_contains "$log_content" "c2: srv1 -> srv2 (10 devices)" "log deve descrever a movimentacao de c2"
assert_contains "$log_content" "1 cliente(s) movido(s), 0 aviso(s)" "log deve resumir total de movimentacoes e avisos"

stdout_content=$(cat "$stdout_tmp")
assert_contains "$stdout_content" "1 cliente(s) movido(s)" "stdout deve mostrar um resumo curto"

rm -rf "$proj" "$stdout_tmp"

# Caso: execucao que gera aviso deve refletir o aviso no log e no stdout
proj=$(new_fake_project)
mkdir -p "$proj/configs/teste-env"
cat > "$proj/configs/teste-env/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=1
SERVIDOR_RECEBEDOR=srv9
EOF
csv_tmp2="$proj/dados2.csv"
cat > "$csv_tmp2" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,6000,-,2024-01-01
c2,srv1,7000,-,2024-01-01
EOF
stdout_tmp2=$(mktemp)
"$proj/balance.sh" teste-env "$csv_tmp2" > "$stdout_tmp2" 2>&1
log_file2=$(find "$proj/logs/teste-env" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content2=$(cat "$log_file2")
assert_contains "$log_content2" "AVISO" "log deve conter o aviso quando um servidor nao pode ser totalmente resolvido"
stdout_content2=$(cat "$stdout_tmp2")
assert_contains "$stdout_content2" "aviso" "stdout deve sinalizar que houve aviso(s)"
rm -rf "$proj" "$stdout_tmp2"
```

- [ ] **Step 2: Run the suite and confirm the new assertions fail (RED)**

Run: `bash tests/run_tests.sh`
Expected: `test_balance_sh_log.sh` assertions FAIL — no `logs/teste-env/balance_*.log` is created yet (script exits before writing one).

- [ ] **Step 3: Replace the `exit 0` at the end of `balance.sh` with the logging block**

```bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOGS_DIR/balance_${TIMESTAMP}.log"

{
    echo "Execucao: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Ambiente: $ENV"
    echo "CSV: $CSV"
    echo "Config: $CONFIG_FILE"
    echo ""
    echo "Movimentacoes:"
    if [ -s "$MOVES_TMP" ]; then
        while IFS=',' read -r cliente origem destino devices; do
            echo "  $cliente: $origem -> $destino ($devices devices)"
        done < "$MOVES_TMP"
    else
        echo "  (nenhuma)"
    fi
    echo ""
    if [ "$TOTAL_AVISOS" -gt 0 ]; then
        echo "Avisos:"
        sed 's/^/  /' "$STDERR_TMP"
        echo ""
    fi
    echo "Resumo: $TOTAL_MOVIDOS cliente(s) movido(s), $TOTAL_AVISOS aviso(s)"
} > "$LOG_FILE"

rm -f "$MOVES_TMP" "$STDERR_TMP"

echo "Resumo: $TOTAL_MOVIDOS cliente(s) movido(s) em $ENV. Log completo: $LOG_FILE"
if [ "$TOTAL_AVISOS" -gt 0 ]; then
    echo "$TOTAL_AVISOS aviso(s) - veja $LOG_FILE"
fi

exit 0
```

- [ ] **Step 4: Run the suite and confirm green (GREEN)**

Run: `bash tests/run_tests.sh`
Expected: all assertions in `test_balance_sh_log.sh` PASS (7 assertions), and every earlier test file still passes (no regression).

- [ ] **Step 5: Commit**

```bash
git add balance.sh tests/test_balance_sh_log.sh
git commit -m "Add execution logging to balance.sh

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Teste de integração end-to-end

**Files:**
- Test: `tests/test_integration.sh`

**Interfaces:**
- Consumes: the complete `balance.sh` (Tasks 3-5) and `lib/balance.awk` (Task 2) together, treated as a black box (only CLI + filesystem, no internal knowledge).
- Produces: a regression test combining every business rule (receiver exclusion, excluded-as-source-only, greedy destination, minimal movement) in one fixture, exercised through the real CLI end-to-end.

- [ ] **Step 1: Write `tests/test_integration.sh`**

```bash
# tests/test_integration.sh - end-to-end: exercita todas as regras de
# negocio juntas atraves do balance.sh real (nao chama o awk diretamente).

BALANCE_SH="$PROJECT_ROOT/balance.sh"

proj=$(mktemp -d)
cp "$BALANCE_SH" "$proj/balance.sh"
cp -r "$PROJECT_ROOT/lib" "$proj/lib"
mkdir -p "$proj/configs/teste-integracao"
cat > "$proj/configs/teste-integracao/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=3
SERVIDORES_EXCLUIDOS="srv3"
SERVIDOR_RECEBEDOR="srv9"
EOF

csv_tmp="$proj/dados.csv"
cat > "$csv_tmp" <<'EOF'
Account ID,DBServer,Enrolled Devices,Licenses Purchased,Account Date Creation
c1,srv1,100,-,2024-01-01
c2,srv1,10,-,2024-01-01
c3,srv1,20,-,2024-01-01
c4,srv1,15,-,2024-01-01
c5,srv3,50,-,2024-01-01
c6,srv3,5,-,2024-01-01
c7,srv3,7,-,2024-01-01
c8,srv3,9,-,2024-01-01
c9,srv2,1,-,2024-01-01
c10,srv9,1,-,2024-01-01
c11,srv9,1,-,2024-01-01
c12,srv9,1,-,2024-01-01
c13,srv9,1,-,2024-01-01
c14,srv9,1,-,2024-01-01
EOF
# srv1: 4 clientes (max=3) -> excedente 1, menor=c2(10)
# srv3: 4 clientes, EXCLUIDO de receber, mas pode perder -> excedente 1, menor=c6(5)
# srv2: 1 cliente -> capacidade 2, unico destino elegivel -> recebe c2 e c6
# srv9: 5 clientes, e' o SERVIDOR_RECEBEDOR -> fora do balanceamento, nao gera nada

stdout_tmp=$(mktemp)
"$proj/balance.sh" teste-integracao "$csv_tmp" > "$stdout_tmp" 2>&1
rc=$?
assert_eq "0" "$rc" "execucao end-to-end deve terminar com sucesso"

expected_srv2=$(mktemp)
printf 'c2\nc6\n' > "$expected_srv2"
assert_file_eq "$expected_srv2" "$proj/results/teste-integracao/to_srv2.txt" "to_srv2.txt deve conter c2 e c6, em ordem alfabetica"
rm -f "$expected_srv2"

assert_file_missing "$proj/results/teste-integracao/to_srv1.txt" "srv1 nao deve receber ninguem"
assert_file_missing "$proj/results/teste-integracao/to_srv3.txt" "srv3 esta excluido de receber, nao deve ter arquivo"
assert_file_missing "$proj/results/teste-integracao/to_srv9.txt" "srv9 e' o recebedor, esta fora do balanceamento"

log_file=$(find "$proj/logs/teste-integracao" -name 'balance_*.log' 2>/dev/null | head -n1)
log_content=$(cat "$log_file")
assert_contains "$log_content" "2 cliente(s) movido(s), 0 aviso(s)" "log deve resumir as 2 movimentacoes sem avisos"
case "$log_content" in
    *"srv9 ->"*|*"-> srv9"*)
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: srv9 (recebedor) nao deveria aparecer em nenhuma movimentacao do log"
        ;;
    *)
        echo "PASS: srv9 (recebedor) nao aparece em nenhuma movimentacao do log"
        ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))

rm -rf "$proj" "$stdout_tmp"
```

- [ ] **Step 2: Run the suite and confirm the new assertions fail (RED)**

Run: `bash tests/run_tests.sh`
Expected: `test_integration.sh` FAILs only if `balance.sh`/`lib/balance.awk` have a defect — since Tasks 2-5 already implement everything this test exercises, this step is really a **regression check**: run it once before touching any code, note the result.

- [ ] **Step 3: If any assertion fails, fix the defect in `lib/balance.awk` or `balance.sh`**

Diagnose using the log file and stdout output captured in the test (`$log_content`, `$stdout_content`) — they contain the full execution trace. Fix the root cause, don't special-case the fixture.

- [ ] **Step 4: Run the full suite and confirm everything is green**

Run: `bash tests/run_tests.sh`
Expected: `TOTAL: 46 teste(s), 0 falha(s)` across every test file (4 harness self-check + 12 awk engine + 12 validation + 5 output + 7 log + 6 integration), including `test_integration.sh`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_integration.sh
git commit -m "Add end-to-end integration test covering all business rules together

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Smoke test contra o CSV real de produção

**Files:** none created or modified — this is a manual verification task, not a code change.

**Interfaces:**
- Consumes: the finished `balance.sh` + `lib/balance.awk`, and the real file `business-users-customer-20241008 - Sheet1.csv` (29444 linhas) already present in the project root.
- Produces: a verification report (performance + sanity), not new files in the tracked project.

- [ ] **Step 1: Build a throwaway smoke-test environment (not the real `configs/business-users/`)**

The real production limits for `business-users` aren't known yet — do not invent them into `configs/business-users/config.conf`. Instead:

```bash
smoke_dir=$(mktemp -d)
mkdir -p "$smoke_dir/configs/business-users"
cat > "$smoke_dir/configs/business-users/config.conf" <<'EOF'
MAX_CLIENTES_POR_SERVIDOR=1000
SERVIDORES_EXCLUIDOS=""
SERVIDOR_RECEBEDOR="bizdbusersazure17"
EOF
```

(`bizdbusersazure17` is picked as the illustrative receiver because the earlier data survey showed it has only 3 clients today — a plausible stand-in for "reserved for new clients." This whole `config.conf` is illustrative only, for timing/sanity purposes, and is discarded after this task.)

- [ ] **Step 2: Run it against the real CSV and time it**

```bash
cd /home/msouza/Projects/automation-db
time "$smoke_dir/../"*/balance.sh 2>/dev/null || true
cp balance.sh "$smoke_dir/balance.sh"
cp -r lib "$smoke_dir/lib"
time "$smoke_dir/balance.sh" business-users "business-users-customer-20241008 - Sheet1.csv"
```

Expected: completes without crashing, in well under 60 seconds (29k rows, largest server ~3948 clients to sort). Note the actual wall-clock time.

- [ ] **Step 3: Spot-check the output**

```bash
ls "$smoke_dir/results/business-users/" | head
cat "$smoke_dir/results/business-users/to_"*.txt | wc -l   # total de clientes movidos
find "$smoke_dir/logs/business-users" -name 'balance_*.log' -exec tail -5 {} \;
```

Confirm: the total moved count is plausible (servers with counts far above 1000 — `bizdbusersazure14` had 3948 — should shed roughly `count - 1000` clients each), no server ends up with more clients than it started with, and the log's summary line total matches `wc -l` across all `to_*.txt` files.

- [ ] **Step 4: Clean up and report**

```bash
rm -rf "$smoke_dir"
```

Report to the user: measured runtime, total clients that would move under the illustrative 1000-limit, and that real `configs/<env>/config.conf` files (for all four environments) with actual `MAX_CLIENTES_POR_SERVIDOR`, `SERVIDORES_EXCLUIDOS`, and `SERVIDOR_RECEBEDOR` values still need to be created by the user before this is used for a real balancing run — that data isn't something this plan can supply.

---

## Post-plan follow-up (not part of this implementation)

- Create real `configs/<env>/config.conf` for `manager-users`, `manager-mdm`, `business-mdm`, and `business-users` with actual production values.
- Nothing else from the spec is deferred — sections 1-11 are all covered by Tasks 1-6 above.
