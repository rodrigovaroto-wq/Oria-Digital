# Book de teste — GRUPO SERRA DO ESPELHO (gerador, a FORMA dos documentos reais que falharam)

Quarto book do repositório (P4 do plano: linha de base da leitura por IA). **11 documentos: 7 PDFs
e 4 planilhas .xlsx**, de uma concessionária de máquinas agrícolas fictícia.

```bash
cd "Dados de Teste/book-espelho" && PYTHONPATH=. python3 gerar.py   # reportlab 5.0.1 + openpyxl 3.1.5
node N8N/medir-custo-book.mjs "Dados de Teste/book-espelho/pdf"      # da raiz do repositório
node N8N/medir-regua-cobertura.mjs "Dados de Teste/book-espelho/pdf"
```

## Por que existe

Os documentos reais dos clientes que falharam não estão mais disponíveis. Os três books anteriores
são PDFs pequenos, com no máximo 3 colunas de período e nenhuma planilha. Os reais que falharam
tinham outra forma: muitas colunas lado a lado, centenas de linhas, quatro colunas de balancete,
planilhas com cabeçalho fora da linha 1, e valores repetidos de forma legítima. Este book reproduz
essa forma.

> **Ele reproduz a FORMA, não os documentos reais** (regra 4 do `CLAUDE.md`). A empresa, os nomes,
> os CPFs e os números são fictícios, e todo documento traz "dados sintéticos" no rodapé. Uma
> falha aqui **não prova** o bug de produção. Este book é um corpus de regressão com a mesma forma
> dos reais. Uma extração que passa aqui deixa de ter desculpa na forma, e nada além disso.

## Documento → caso real → falha que mira

| Documento | Caso real (forma) | Falha real que mira |
|---|---|---|
| `DRE_janaago26.pdf` — 432 linhas de conta, 9 colunas (jan–ago + acumulado), paisagem 5,4pt | `DRE_janaago26.pdf` e `DRE Krauspenhar 2025 - Ass.pdf` (493 linhas) | "conta(s) descartada(s) por desalinhamento entre colunas e valores"; "Extração INCOMPLETA: 223 de 493 (45%)" |
| `DRE Sintética 2025 x 2024.pdf` — 91 linhas, 2 colunas | Controle do caso acima | Se esta passa e a analítica falha, o problema é a largura, não o vocabulário |
| `balancete_janaago26.pdf` — 614 linhas, 4 colunas, código `1.01.01.001`, D/C colado | `balancete_janaago26.pdf`, `Balancete 1º semestre 2025.pdf` (~1.500 pares, 11+ blocos) | Fatiamento em muitos blocos; limite de pedidos por minuto do provedor |
| `BALANÇO SERRA DO ESPELHO 2025.pdf` — 178 linhas × 12 meses, paisagem 4,7pt | `BALANÇO MOTO AGRICOLA 2023.pdf` (~2.500 pares, 24+ blocos) | Volume de blocos; mês trocado de coluna |
| `Balanço Patrimonial Espelho Implementos 2025 - Ass.pdf` — 79 linhas, 2 colunas | Balanço com 4× "EMPRÉSTIMOS E FINANCIAMENTOS - LP" de mesmo valor | Guarda "padrão típico de fabricação" em repetição legítima; deduplicação por rótulo |
| `Alteração Contratual Consolidada nº 12 - Serra do Espelho.pdf` | Contrato com o capital repetido em 4 contas | A mesma guarda: o capital aparece 4× no texto (+1 no quadro) e as 4 quotas são iguais |
| `Procuração ad negotia - Serra do Espelho.pdf` | Controle | Documento sem dado financeiro (só CPF, OAB, CEP, datas): zero linha é o certo |
| `Extrato cc 41.207-3 agosto 2026.xlsx` | Extrato .xlsx real: **0 campos** | Cabeçalho na linha 6, título mesclado, data como texto, D/C em coluna própria |
| `MAPA DE DÍVIDA 31.08.2026.xlsx` | Mapa de dívida .xlsx real: **0 campos** | Idem; total da LINHA por fórmula; aba de premissas com números |
| `estoque peças ago26 (2).xlsx` | Estoque com "1 rótulo com número colado" | Código colado no nome: `10234-X`, `10234 - X`, `849X` |
| `Contingências jurídicas - posição ago-26.xlsx` | Contingências .xlsx real (86 campos) | Nº CNJ ao lado do valor; valor da causa como TEXTO `R$ 1.234,56` |

Todas as planilhas têm: título mesclado (linhas 1–2), cabeçalho na **linha 6**, uma aba extra
irrelevante (sempre a segunda), total por **fórmula** e total por **valor**, e formato numérico
`#,##0.00`, que o Excel em pt-BR mostra como `1.234,56`.

## Como os números se sustentam

Tudo em **centavos inteiros** (`motor.py`). Assim, "acumulado = soma dos meses" e
"débito = crédito" fecham no centavo, e os asserts não mentem por arredondamento.

- DRE analítica: acumulado = soma dos meses em **toda** linha impressa. O resultado bate com o
  motor.
- Balanço mensal: Ativo = Passivo + PL nos 12 meses. A conta movimento do Banco Meridional é a
  única que fecha, e o assert exige que ela fique positiva.
- O resultado de dezembro de 2025 no balanço é o resultado da DRE sintética de 2025.
- Balancete: o saldo anterior é dezembro de 2025 depois do encerramento. O saldo atual das contas 3
  e 4 é o acumulado da DRE analítica. Débito = crédito.
- Planilhas, todas lidas do balancete de agosto de 2026:
  - O saldo final do extrato é a conta movimento do Banco do Planalto.
  - O mapa de dívida soma 2.01.02 + 2.02.01.
  - O estoque soma as folhas "Peças - …".
  - O provisionado das contingências soma 2.02.03 (só o prognóstico provável).

Os asserts do balancete, da DRE analítica e do balanço mensal foram **medidos**: com +1 centavo
em uma célula, cada um reprova. As amarrações dos anexos valem **por construção**, porque eles
leem o próprio balancete. O assert delas protege o código do gerador, não os dados (mesma ressalva
do `book-distress`).

## A verdade (`METRICAS.json`)

- **PDFs**, em `documentos`: a contagem de `comum/contagem.py`, a mesma dos outros books, mais o
  campo `espelha`. Pela regra comum, a coluna de código do balancete conta como célula de valor.
  Por isso o cabeçalho dos meses vai sem o ano ("JAN", não "Jan/2026"). Com o ano, o cabeçalho
  viraria uma conta a mais (medido: 433 em vez de 432).
- **Planilhas**, numa lista própria (`planilhas`). Usam a MESMA regra de linha
  (`_conta_uma_linha`) sobre o que o openpyxl lê de volta da primeira aba.
  - A célula de fórmula conta como **vazia**. O openpyxl não grava valor em cache, então um leitor
    sem motor de cálculo a vê em branco. Elas vão contadas à parte, em `celulas_de_formula`.
  - Por que fora de `documentos`: `medir-custo-book.mjs` reprova documento com `paginas` zerada, e
    planilha não tem página. Gravar `paginas: 0` seria apresentar ausência como dado (regra 1).

## O que NÃO reproduz

- **Os números e o texto exatos dos reais.** Os 493 / 223 / 1.500 / 2.500 viram aqui 432 / — /
  614×4 / 178×12. A forma é a mesma, a escala é próxima.
- **PDF escaneado ou com fonte embutida estranha.** Todo PDF aqui tem texto nativo do reportlab.
  Se a falha real veio de OCR ou de ordem de desenho do PDF de origem, este book não a pega.
- **Valor em cache das fórmulas.** Um .xlsx salvo pelo Excel traz o último valor calculado; os
  daqui não trazem. Um leitor que confie no cache verá o total em branco aqui e preenchido no
  real.
- **Aba relevante fora da primeira posição.** A aba extra é sempre a segunda.
- **Bytes estáveis nas planilhas.** O zip do .xlsx carimba a hora de gravação. O conteúdo é
  determinístico; os PDFs são iguais ao byte entre execuções.
- **Medição contra produção.** Nenhum destes documentos tem captura do n8n em
  `Dados de Teste/capturas/`. A régua de cobertura roda sobre o texto do gerador, que produção
  nunca vê, e por isso não afere nada (ver o cabeçalho de `medir-regua-cobertura.mjs`).
