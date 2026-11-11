---
id: mapeamento-de-colunas-mb2
tipo: numero
toca:
  - Leitor/lib/mapeamento.mjs
  - Leitor/lib/tabela.mjs
  - Leitor/test/mapeamento.test.mjs
  - Leitor/medicao-n8n/navegador-tabela.mjs
prova: Leitor/test/*.test.mjs
ancora: Leitor/lib/mapeamento.mjs#aplicadorDeMapeamento
ancora_sha: 6e4c778f668a
substitui: []
---

# Mapeamento de colunas (MB2): título × subtotal × rejeitada decidido COM o significado das colunas

Termos de busca: mapeamento de colunas, aging, contas a receber, contas a pagar, subtotal,
título, coluna deslocada, vírgula decimal, ponto decimal, dia/mês, mês/dia, impressão do
cabeçalho, ERP, confirmação do analista, soAmostra, MB2, PLANO_MVP.

**O que é.** `Leitor/lib/mapeamento.mjs`: `proporMapeamento` (por sinônimo do nome E tipo dos
valores da amostra), `validarMapeamento`, `aplicadorDeMapeamento` (cada linha do `aoLinha` da MB1
vira `titulo`, `subtotal` ou `rejeitada` com o campo e o valor), `impressaoDoCabecalho` (a chave
com que o banco guarda o mapeamento confirmado). Sem autor, data e formato confirmados, o aplicador
RECUSA: arquivo sem confirmação não vira dado.

## A regra, e por que ela é aqui e não na MB1

Título = contraparte preenchida + vencimento que É data + saldo que É número. Subtotal = saldo
número, vencimento não-data, e o sinal de total (da MB1 ou na contraparte) ou nenhuma contraparte.
O resto é rejeitada, contada por motivo. Na MB1, sem saber o que cada coluna é, a decisão pela
contagem de células errava nos dois sentidos (ficha `leitor-tabular-csv-xlsx-mb1`). Aqui a coluna
deslocada que cabe na largura aparece sozinha: "saldo não é número: '01/01/2025'".

## O que surpreende

- **O formato é do ARQUIVO, não do valor.** "1.250" é mil duzentos e cinquenta (vírgula decimal)
  ou um e vinte e cinco (ponto); "03/04/2025" é 3 de abril ou 4 de março. A primeira versão
  decidia valor a valor e erraria sem erro. Agora `formatoDaAmostra` propõe com a EVIDÊNCIA ("1 data
  prova dia/mês" ou "SEM prova") e o analista confirma junto com as colunas; o banco guarda.
- **No XLSX, o número do XML tem ponto** ("15172.12"): sem o tipo da célula, a proposta concluía
  "ponto decimal" para o arquivo. A MB1 passou a devolver `amostra_tipos`.
- **A IA não propõe o mapeamento** (o plano previa). Sinônimo + tipo da amostra acerta as 11
  colunas dos sintéticos sem custo nem rede; o analista confirma de qualquer jeito. Volta se
  arquivos reais (DM7) mostrarem cabeçalhos fora dos sinônimos (o teste do arquivo americano
  mostra o caso: colunas em inglês o analista mapeia à mão).
- **Conferência positiva dentro do arquivo**: o último subtotal (o total geral) contra a soma dos
  títulos lidos: `confere`, `diverge` ou `sem_total_no_arquivo` com o efeito.
- **Impressão do cabeçalho sem minúsculas**: o `lower()` do Postgres depende do LC_CTYPE, e o banco
  recalcula a impressão em vez de aceitá-la do navegador.

## Medido em 11/11/2026 (Chromium, sintéticos de 1M de linhas, idêntico ao Node)

Caminho inteiro da tela: 1ª leitura `soAmostra` + proposta + 2ª leitura aplicando a toda linha.
CSV de contas a receber: 5,5 s, 58 MB de heap; XLSX: 22,0 s, 78 MB. 999.995 títulos, 1 subtotal,
0 rejeitadas, Σ saldo = 24.917.000,00 = Clientes do BP; conferência com o total do arquivo:
`confere`. Sem `soAmostra` (duas leituras inteiras): 8,1 s e 40,8 s.

## Medido não-vazio (regra 2)

27 correções desligadas uma a uma: todas reprovam de 1 a 5 testes de `Leitor/test/mapeamento.test.mjs`
(23 testes). Três passavam vazias na primeira rodada (subtotal sem exigir o sinal, vencimento
não-data virando título, emissão impossível aceita) e ganharam teste.

**Quem desmente isto:** um arquivo REAL de ERP (DM7), que os sintéticos não substituem.
