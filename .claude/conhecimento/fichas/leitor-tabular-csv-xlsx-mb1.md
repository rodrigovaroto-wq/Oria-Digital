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
ancora_sha: fe813ad0eaa7
substitui: []
---

# Leitor tabular (MB1): CSV e XLSX de 1M de linhas no navegador, toda linha com destino

Termos de busca: contas a receber, contas a pagar, aging, razão, planilha grande, CSV grande,
XLSX grande, milhões de linhas, leitor em fluxo, sharedStrings, inlineStr, windows-1252, cp1252,
BOM, UTF-16, date1904, linha de total, largura divergente, MB1, PLANO_MVP.

**O que é.** `lerTabela(blob, { aoLinha })` em `Leitor/lib/tabela.mjs`. Lê CSV ou XLSX em fluxo, o
mesmo código no Node e no navegador. Dá a TODA linha um destino (`antes_do_cabecalho`,
`cabecalho`, `dado`, `total`, `em_branco`, `fora_da_tabela`, `largura_divergente`). Não sabe o que
cada coluna significa: isso é a MB2.

## Medido em 11/11/2026 (sintéticos de `Dados de Teste/volume`)

| Arquivo de 1M de linhas | Chromium | heap JS | Node 22 |
|---|---|---|---|
| CSV, 133 MB | 2,1 s | 44 MB | 2,8 a 5,5 s, 11 MB |
| XLSX, 57 MB (622 mil strings compartilhadas) | 15,2 s | 67 MB | 22,7 s, 73 MB |

O resumo do navegador é IDÊNTICO ao do Node nos 7 arquivos medidos (`navegador-tabela.mjs`). Medido
na página, não no Web Worker do portal (o CDP dá o heap da página); o código é o mesmo.

## O que surpreende

- **No Node 22, `TextDecoder('latin1')` JÁ é windows-1252** (0x96 → "–"), como no navegador. A nota
  de `campos.mjs#latin1` ("o Node devolve U+0096") fala do `Buffer.toString('latin1')` do SPED, não
  do `TextDecoder`. Uma troca manual dos caracteres C1 foi escrita e saiu: desligada, 0 testes
  reprovavam. O `TextDecoder` também descarta o BOM sozinho (mesma medição).
- **XLSX real tem `sharedStrings.xml`** (`t="s"`); o openpyxl em write_only grava `inlineStr`. O
  leitor lê os dois e AVISA quando não há tabela de strings. A tabela de 622 mil strings é o que
  pesa no heap do XLSX.
- **Linha de total**: a primeira célula começa com "total" E a seguinte está vazia. Só pela
  contagem de células, "TOTAL GERAL;;;5,00" de um relatório de 4 colunas virava dado e somava o
  total a si mesmo. Um cliente chamado "TOTAL DISTRIBUIDORA" preenche a linha e continua dado.
- **`largura_divergente`**: separador sem aspas dentro de um nome desloca as colunas. A linha nunca
  vira dado em silêncio.
- **O separador vem do `formaDoTexto` do n8n**, que quebra linha sem respeitar aspas. Arquivo com
  muitas células multilinha nas primeiras 50 linhas é RECUSADO com o motivo (nunca lido errado).
- **Releitura**: CSV que parecia UTF-8 nos primeiros 64 KB e não era é relido como windows-1252, e
  `aoLinha({ reinicio: true })` avisa quem agrega para zerar. Quem agrega TEM de tratar isso.
- **Só a primeira aba visível** do XLSX é lida; as outras são nomeadas nos avisos.

## Medido não-vazio (regra 2)

Cada correção desligada, `node --test Leitor/test/tabela.test.mjs`: aspas nas células 1; quebra
dentro de aspas 1; largura divergente 1; total desligado 3; total sem exigir a célula seguinte
vazia 1; calendário 1904 1; formato de data próprio 1; leitura fonética 1; linha ausente do XML 2;
`\r` no fim da fatia 1; releitura em windows-1252 1; aba oculta 1; última linha sem quebra 1.

**Quem desmente isto:** rodar `navegador-tabela.mjs` de novo noutra versão do Chromium ou do Node, e
um arquivo REAL de ERP (DM7 do PLANO_MVP), que os sintéticos não substituem.
