---
id: mapeamento-de-colunas-mb2
tipo: numero
toca:
  - Leitor/lib/mapeamento.mjs
  - Leitor/lib/tabela.mjs
  - Leitor/test/mapeamento.test.mjs
  - Leitor/medicao-n8n/navegador-tabela.mjs
prova: Leitor/test/*.test.mjs
ancora: Leitor/lib/mapeamento.mjs#RE_TOTAL
ancora_sha: 80e614c37e68
substitui: []
---

# Mapeamento de colunas (MB2): título × subtotal × rejeitada decidido COM o significado das colunas

Termos de busca: mapeamento de colunas, aging, contas a receber, contas a pagar, subtotal,
título, total por data, coluna deslocada, vírgula decimal, ponto decimal, milhar, dia/mês,
mês/dia, impressão do cabeçalho, ERP, confirmação do analista, soAmostra, saldo negativo,
adiantamento, MB2, PLANO_MVP, 0272.

**O que é.** `Leitor/lib/mapeamento.mjs`: `proporMapeamento` (colunas por sinônimo do nome E tipo
dos valores; DEPOIS o formato, votado só nas colunas de valor e de data), `validarMapeamento`,
`aplicadorDeMapeamento` (cada linha do `aoLinha` da MB1 vira `titulo`, `subtotal` ou `rejeitada`
contada por motivo COM o saldo que ficou de fora), `impressaoDoCabecalho` (a chave com que a 0272
guarda o mapeamento confirmado, recalculada pelo banco). Sem autor, data e formato confirmados, o
aplicador RECUSA.

## A regra

Título = contraparte + vencimento que É data + saldo que É número + NENHUM sinal de total.
Subtotal = saldo número, vencimento não-data, e sinal de total (MB1 ou contraparte) ou nenhuma
contraparte. Linha com sinal de total E vencimento data é REJEITADA, visível com o saldo: "Total
ACME; 02/01/2025; 30,00" (total por data) e "TOTAL DISTRIBUIDORA LTDA" (cliente chamado Total)
não se distinguem sem o analista. A revisão de 11/11/2026 mediu a 1ª versão somando os totais por
data como título: aging triplicado (105,00 em vez de 35,00), conferência "sem total". Somar errado
em silêncio é pior que deixar de fora com o saldo na tela.

## O que surpreende

- **O formato é do ARQUIVO** ("1.250", "03/04/2025") e é votado SÓ nas colunas de valor e de data
  escolhidas. Votando em todas, uma data "15.03.25" virava "prova" de ponto decimal e "1.234" saía
  12,34 (revisão). "1.234" sem decimal prova que o ponto é milhar; "1,000" prova que a vírgula é.
- **`casas_extras`**: valor com mais de 2 casas, mesmo zeros ("1,000" lido com vírgula), é contado
  em `saldos_com_mais_de_2_casas`: é o sinal do formato trocado (16.500,00 virando 16,50).
- **O aplicador confere sozinho a linha de cabeçalho** que passa por ele (inclusive a repetida):
  coluna inserida pelo ERP é ERRO, não saldo lido da coluna vizinha.
- **Conferência com o total do arquivo**: `confere` se ALGUM subtotal = Σ títulos (o total geral
  pode estar no topo ou antes do subtotal do último cliente); senão `diverge` com o maior.
- **Campo opcional inválido** ("00/00/0000", "-") não derruba o título: fica ausente, contado em
  `opcionais_invalidos`. Só os obrigatórios rejeitam.
- **Saldo negativo** entra na soma e a REDUZ; `titulos_com_saldo_negativo` conta, com o efeito. A
  MB3 decide se a conciliação é contra Clientes ou Clientes menos Adiantamentos.
- **A IA não propõe o mapeamento** (o plano previa): sinônimo + tipo acerta as 11 colunas dos
  sintéticos; colunas em inglês o analista mapeia à mão. Volta com arquivo real (DM7) se preciso.
- **A lista dos 11 campos está duplicada** na 0272 (`fn_mapeamento_erros`), copiada à mão; nenhum
  portão compara as duas.

## Medido em 11/11/2026 (Chromium, sintéticos de 1M de linhas, idêntico ao Node)

Caminho inteiro da tela (1ª leitura `soAmostra` + proposta + 2ª leitura aplicando): CSV 5,8 s e
53 MB de heap; XLSX 22,5 s e 85 MB. 999.995 títulos, 1 subtotal, 0 rejeitadas, Σ saldo =
24.917.000,00 = Clientes do BP; total do arquivo `confere`. Contas a pagar: 14.900.000,00.

## Medido não-vazio (regra 2)

43 correções desligadas uma a uma: todas reprovam de 1 a 7 dos 35 testes de
`Leitor/test/mapeamento.test.mjs`. Passavam vazias e ganharam teste: subtotal sem exigir sinal,
vencimento não-data, emissão impossível (1ª rodada); `arredondados`, contraparte vazia, total na
contraparte, código numérico na contraparte e o voto em todas as colunas (revisão).

**Quem desmente isto:** um arquivo REAL de ERP (DM7), que os sintéticos não substituem.
