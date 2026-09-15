Objetivo: desenvolver um script em shell script bash para a versao 3.2 para ler a planilha e conseguir gerar um balanceamento entre servidores, entregaando no final no formato to_nomedoservidor.txt apenas com os nomes que estao em a2 em diante.

Explicando a planilha

Coluna A - nome de clientes
Coluna B - nome do servidor
Coluna C - Quantidade de devices

cada linha e vinculada a um cliente, o nome desse cliente esta na coluna A, na coluna B o servidor que esse cliente esta alocado e na coluna C a quantidade de devices que esse cliente tem.

Cada ambiente deve ter um arquivo de configuração para determinar quantidade maxima de clientes por servidor, servidores que nao devem receber novos clientes e servidor recebedor de cliente automatico.

O servidor recebedor de clientes nao deve entrar no balanceamento, pois ele esta reservado para receber novos clientes automaticamente.

Regras de balanceamento:

1 - nunca movimentar clientes maiores que 5000 de devices
2 - sempre minimizar a quantidade de movimentacoes.
3 - sempre dar preferencia para movimentar clientes menores em quantidade de devices 

