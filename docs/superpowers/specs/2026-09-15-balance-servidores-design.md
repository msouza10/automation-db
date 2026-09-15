# Design: `balance.sh` — Balanceamento de clientes entre servidores

Data: 2026-09-15
Status: aprovado para implementação

## 1. Objetivo

Script em Bash **3.2-compatível** que lê uma planilha (CSV) de clientes
alocados em servidores e gera, por ambiente, uma lista de movimentações
mínimas necessárias para trazer todo servidor de volta a um limite máximo
de clientes, respeitando as regras de negócio definidas em `rules.md`.

A saída final é um conjunto de arquivos `to_<nomedoservidor>.txt`, cada um
contendo apenas os nomes dos clientes (coluna A da planilha, a partir da
linha 2) que devem ser movidos para aquele servidor.

## 2. Ambientes e estrutura de diretórios

Reaproveita a estrutura já criada por `build.sh`:

```
csv/                              # CSVs de entrada, apontados via argumento
configs/<env>/config.conf         # um config por ambiente
results/<env>/to_<servidor>.txt   # saída do balanceamento
logs/<env>/balance_<timestamp>.log
packed/<env>/                     # não usado por este script
```

Ambientes válidos (definidos por `build.sh`): `manager-users`,
`manager-mdm`, `business-mdm`, `business-users`. Um ambiente é válido se
`configs/<env>/` existir.

## 3. Invocação

```
./balance.sh <env> <caminho-do-csv>
```

- `<env>`: nome do ambiente. Deve existir `configs/<env>/config.conf`.
- `<caminho-do-csv>`: caminho para o CSV de entrada (normalmente dentro de
  `csv/`, mas o script aceita qualquer caminho válido).
- Validações antes de rodar: `env` informado, diretório `configs/<env>/`
  existe, `config.conf` existe e é legível, CSV informado existe e é
  legível, `config.conf` define as três chaves obrigatórias (seção 4).
  Qualquer falha aqui aborta com mensagem de erro clara e código de saída
  != 0, sem gerar nenhum arquivo de saída.

## 4. Formato da planilha (CSV) de entrada

Header na primeira linha (ignorado). Colunas relevantes, por posição:

| Coluna | Conteúdo                    |
|--------|------------------------------|
| A      | Nome do cliente (Account ID) |
| B      | Servidor atual (DBServer)    |
| C      | Enrolled Devices (quantidade de devices) |

Colunas adicionais (ex: `Licenses Purchased`, `Account Date Creation`) são
ignoradas. Linhas com campo de devices vazio ou não numérico são tratadas
como `0` devices.

## 5. Config por ambiente

`configs/<env>/config.conf`, formato Bash `KEY=VALUE`, carregado via
`source` (arquivo é código — deve ser tratado com a mesma confiança que o
próprio script; não é entrada de usuário não-confiável).

```bash
MAX_CLIENTES_POR_SERVIDOR=100
SERVIDORES_EXCLUIDOS="srvA,srvB"   # não recebem clientes novos no balanceamento
SERVIDOR_RECEBEDOR="srvC"          # fora do balanceamento inteiramente
```

- `MAX_CLIENTES_POR_SERVIDOR`: inteiro único, vale igualmente para todo
  servidor do ambiente (exceto o recebedor, que é ignorado).
- `SERVIDORES_EXCLUIDOS`: lista separada por vírgula. Esses servidores
  **podem perder clientes** (contam como origem se estiverem acima do
  limite) mas **nunca recebem** clientes movidos.
- `SERVIDOR_RECEBEDOR`: exatamente um nome de servidor. É removido do
  balanceamento por completo — não é avaliado como origem nem destino,
  mesmo que já tenha clientes na planilha ou esteja acima/abaixo do
  limite.
- Se `SERVIDOR_RECEBEDOR` também aparecer em `SERVIDORES_EXCLUIDOS`, isso
  é redundante mas não é erro (o recebedor já está fora do balanceamento).

## 6. Algoritmo de balanceamento

Objetivo: **trazer cada servidor excedente de volta ao limite, com o
mínimo de movimentações possível** — nunca busca equalizar além disso.

1. Agrupa clientes por servidor a partir do CSV.
2. Remove `SERVIDOR_RECEBEDOR` do conjunto de servidores avaliados.
3. Para cada servidor restante, calcula `contagem_atual` (nº de clientes).
   - **Excedente**: `contagem_atual > MAX_CLIENTES_POR_SERVIDOR`. Precisa
     perder `contagem_atual - MAX_CLIENTES_POR_SERVIDOR` clientes.
   - **Elegível como destino**: `contagem_atual < MAX_CLIENTES_POR_SERVIDOR`
     **e** o servidor não está em `SERVIDORES_EXCLUIDOS`. Capacidade
     disponível = `MAX_CLIENTES_POR_SERVIDOR - contagem_atual`.
4. Para cada servidor excedente, ordena seus clientes por `devices`
   crescente e seleciona, em ordem, os menores clientes até cobrir o
   excedente necessário — **pulando qualquer cliente com
   `devices > 5000`** (esse cliente nunca é candidato a mover, mesmo que
   seja o menor disponível).
   - Se não houver clientes elegíveis suficientes para cobrir o
     excedente inteiro, move os que der e registra aviso (seção 8) — não
     aborta a execução.
5. Atribuição de destino (greedy, global entre todos os servidores
   excedentes): a cada cliente selecionado para mover, escolhe o
   servidor elegível com **maior capacidade disponível no momento**;
   decrementa a capacidade desse servidor em 1 após a atribuição.
   - Se a capacidade total disponível entre os servidores elegíveis se
     esgotar antes de todos os clientes necessários serem movidos, os
     clientes restantes ficam sem destino — registra aviso (seção 8) e
     não são incluídos em nenhum `to_*.txt`.
6. `devices == 5000` é movível (a regra exclui apenas `> 5000`).

## 7. Saída

Para cada servidor de destino que recebeu pelo menos um cliente, gera
`results/<env>/to_<servidor>.txt`: nomes dos clientes movidos para ele,
um por linha, ordenados alfabeticamente. Nenhum header, nenhuma coluna
extra. Servidores que não receberam ninguém não geram arquivo (o
diretório `results/<env>/` é limpo de `to_*.txt` de execuções anteriores
antes de escrever os novos, para não deixar arquivos obsoletos).

## 8. Log

`logs/<env>/balance_<timestamp>.log` (timestamp formato
`YYYYMMDD_HHMMSS`), contendo:

- Parâmetros da execução (env, csv, config usado).
- Uma linha por movimentação: `cliente: origem -> destino (devices)`.
- Um aviso por servidor que permaneceu acima do limite ao final,
  explicando a causa (clientes remanescentes todos > 5000 devices, e/ou
  falta de capacidade de destino), com a contagem final e o excedente
  não resolvido.
- Resumo final: total de clientes movidos, total de servidores ainda
  acima do limite.

O script também imprime na saída padrão um resumo curto (movimentos
totais + avisos, se houver) e escreve o log completo em arquivo.

## 9. Implementação

- Bash 3.2: sem `declare -A`, sem `mapfile`/`readarray`, sem
  `${var,,}`/`${var^^}`, sem namerefs (`local -n`).
- Processamento pesado (parsing do CSV, agrupamento, ordenação, cálculo
  de excedente/capacidade, atribuição gulosa de destino) feito em `awk`
  — que tem arrays associativos nativos independente da versão do bash.
  Um único script `awk` recebe o CSV + os parâmetros do config (via
  `-v`) e emite as movimentações decididas (`cliente,origem,destino,devices`)
  em stdout; o Bash consome essa saída para gerar os arquivos `to_*.txt`
  e o log.
- Bash cuida de: parsing de argumentos, validação de ambiente/config/CSV,
  `source` do config, invocação do awk, distribuição das linhas de saída
  do awk nos arquivos `to_<servidor>.txt` corretos, geração do log,
  limpeza de `to_*.txt` antigos em `results/<env>/`.

## 10. Testes

- CSV pequeno sintético (poucos servidores, casos: servidor exatamente
  no limite, servidor 1 acima, servidor muito acima, cliente > 5000
  devices sozinho num servidor excedente, servidor recebedor com
  clientes que não deve mexer, servidor excluído de receber que está
  acima do limite).
- Casos de erro: env inexistente, config faltando chave obrigatória, CSV
  inexistente.
- Caso de capacidade insuficiente (para validar o aviso no log em vez de
  abort).
- Rodar contra o CSV real (`business-users-customer-20241008 - Sheet1.csv`,
  ~29k linhas) para checar performance e sanidade dos números antes de
  considerar pronto.

## 11. Fora de escopo

- Não gera arquivo de "quem saiu" por servidor de origem — apenas os
  `to_<servidor>.txt` de destino, conforme pedido original.
- Não escreve de volta na planilha nem em nenhum sistema externo — é
  puramente uma ferramenta de geração de plano de movimentação.
- Não lida com múltiplos arquivos de config por ambiente — um único
  `config.conf` por ambiente.
