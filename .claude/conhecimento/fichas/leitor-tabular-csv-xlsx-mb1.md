---
id: leitor-tabular-csv-xlsx-mb1
tipo: numero
toca:
  - Leitor/lib/tabela.mjs
  - Leitor/test/tabela.test.mjs
  - Leitor/medicao-n8n/navegador-tabela.mjs
  - Dados de Teste/volume/gerar_volume.py
prova: Leitor/test/*.test.mjs
ancora: Leitor/lib/tabela.mjs#decodificador
ancora_sha: b14000b172a5
substitui: []
---

# Leitor tabular (MB1): CSV e XLSX de 1M de linhas no navegador, toda linha com destino ESTRUTURAL

Termos de busca: contas a receber, contas a pagar, aging, razão, planilha grande, CSV grande,
XLSX grande, milhões de linhas, leitor em fluxo, sharedStrings, inlineStr, windows-1252, cp1252,
BOM, UTF-16, date1904, linha de total, subtotal, cabeçalho repetido, aspa solta, largura
divergente, corpo, sinais, MB1, PLANO_MVP.

**O que é.** `lerTabela(blob, { aoLinha })` em `Leitor/lib/tabela.mjs`. Lê CSV ou XLSX em fluxo, o
mesmo código no Node e no navegador. Dá a TODA linha um destino ESTRUTURAL (`antes_do_cabecalho`,
`cabecalho` — inclusive o repetido a cada página —, `corpo`, `em_branco`, `largura_divergente`) e
SINAIS (`rotulo_de_total`, `poucas_celulas`). **Não diz se uma linha do corpo é título, subtotal ou
lixo**: isso é a MB2, com o mapeamento de colunas.

## A lição que custou uma revisão

A primeira versão decidia "dado", "total" e "fora da tabela" pela contagem de células. A revisão
independente de 11/11/2026 mostrou que isso erra SEM erro nos dois sentidos: o título EM ABERTO (as
colunas de pagamento vazias, 5 de 12) ia para fora da tabela enquanto o pago virava dado, e
"Sub-Total;;;10,00", "Totais", "Total do cliente" na 2ª coluna viravam dado (soma em dobro).
**Sem saber o que cada coluna é, classificar linha é palpite.** A MB2 decide com o mapeamento:
título é a linha cujo vencimento é data e cujo saldo é número. Pelo mesmo motivo, o deslocamento
de coluna que CABE na largura (a última coluna vazia absorve) não é pego aqui: é a MB2 que o pega,
porque o saldo deslocado deixa de ser número.

## Medido em 11/11/2026 (sintéticos de `Dados de Teste/volume`, depois da revisão)

| Arquivo de 1M de linhas | Chromium | heap JS | Node 22 |
|---|---|---|---|
| CSV, 133 MB | 2,7 s | 45 MB | 3,3 a 3,6 s |
| XLSX, 57 MB (622 mil strings compartilhadas) | 18,7 s | 69 MB | 29,4 s |

Resumo do navegador IDÊNTICO ao do Node (`navegador-tabela.mjs`). Medido na página, não no Web
Worker do portal (o CDP dá o heap da página); o código é o mesmo.

## O que surpreende

- **No Node 22, `TextDecoder('latin1')` JÁ é windows-1252** (0x96 → "–"), como no navegador. A nota
  de `campos.mjs#latin1` ("o Node devolve U+0096") fala do `Buffer.toString('latin1')` do SPED, não
  do `TextDecoder`. Uma troca manual dos caracteres C1 foi escrita e saiu: desligada, 0 testes
  reprovavam. O `TextDecoder` também descarta o BOM sozinho.
- **Codificação decidida ANTES de entregar a primeira linha.** Se os 64 KB iniciais são ASCII puro,
  uma passada só de decodificação UTF-8 estrita no arquivo inteiro decide. A primeira versão relia
  no meio do caminho e já tinha entregue 199.863 linhas (CSV de 5 MB em fatias de 64 KB): quem
  agregava somava em dobro.
- **Aspa só abre no começo da célula** (RFC 4180): `MONITOR 15"` é texto. Aspa que não fecha em 50
  linhas físicas volta cada linha a um registro, com aviso. O estado das aspas passa de uma linha
  para a outra (antes, revarrer o pendente era quadrático: 40 mil linhas, 22 s).
- **XLSX real tem `sharedStrings.xml`** (`t="s"`); o openpyxl em write_only grava `inlineStr`. O
  leitor aceita prefixo de namespace (`<x:row>`), aspas simples, comentário e CDATA, acha a aba
  pelo id da relação com qualquer prefixo e, sem relação, ERRA (antes lia `sheet1.xml`, que podia
  ser a aba oculta, com o nome da visível).
- **O separador vem do `formaDoTexto` do n8n**, que quebra linha sem respeitar aspas. Arquivo com
  muitas células multilinha nas primeiras 50 linhas é RECUSADO com o motivo.
- **Número do XLSX sai como o texto do XML**: pode vir "1.5E-2" ou "1234.5599999999999". Quem
  converte (MB2/MB3) arredonda e declara.

## Medido não-vazio (regra 2)

29 correções, cada uma desligada: todas reprovam de 1 a 4 testes de `Leitor/test/tabela.test.mjs`
(31 testes). A do teto de 50 linhas passava vazia até ganhar o teste da aspa solta que fecha 100
linhas depois.

**Quem desmente isto:** um arquivo REAL de ERP (DM7 do PLANO_MVP), que os sintéticos não substituem,
e `navegador-tabela.mjs` noutra versão do Chromium ou do Node.
