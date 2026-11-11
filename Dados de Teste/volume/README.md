# Bases volumosas sintéticas — contas a receber, contas a pagar e OFX (MB0)

Fatia **MB0** do `Arquitetura do Sistema/3 Estado e Execução/PLANO_MVP_2026-11.md`: o insumo
para medir o leitor tabular (MB1), o aging (MB3, MB4) e o OFX (MB5) com 10 mil, 100 mil e 1 milhão
de linhas, antes de existir arquivo real.

```bash
cd "Dados de Teste"/volume
python3 gerar_volume.py             # saida/: 3 tamanhos × (AR .csv e .xlsx, AP .csv, OFX) + GABARITO_<n>.json
python3 conferir_volume.py          # relê os ARQUIVOS e confronta com o book-distress
python3 test_volume.py -v           # prova que o conferidor reprova quando o arquivo mente (roda no CI)
```

`--linhas N` gera um tamanho só. Só biblioteca padrão: o `.xlsx` é escrito à mão. A saída é
determinística ao byte (o teste confere).

## Por que os totais vêm do book-distress

Um sintético que fecha consigo mesmo prova só que a soma funciona. O MVP precisa provar a
**conciliação**: o aging lido de um arquivo de 1M de linhas bate com o balanço que a extração por
IA leu de um PDF. Por isso a carteira **em aberto**, por contraparte e por faixa, é a do aging do
book-distress em 31/12/2025:

| Arquivo | Total que tem de bater | Origem no book |
|---|---|---|
| Contas a receber | Σ saldo = R$ 24.917.000,00 | Clientes brutos do BP da Metalúrgica (24.917 mil) |
| Contas a pagar | Σ saldo = R$ 14.900.000,00 | Fornecedores do mesmo BP (14.900 mil) |
| OFX | créditos e débitos de cada mês; saldo final R$ 676.317,46 | extrato do book; caixa do BP (676 mil) |

A carteira em aberto tem no máximo **2.000 títulos em qualquer tamanho** (título médio de ~R$ 12,5
mil no AR). O volume vem de **títulos liquidados** (saldo zero) de uma carteira pulverizada. O
liquidado é a armadilha de propósito: é linha lida e não pode entrar no aging. A primeira versão
escalava os em aberto com o arquivo, e o título médio caía para R$ 124 com 1M de linhas: um perfil
que não existe e que calibraria errado qualquer corte de materialidade.

## As armadilhas de formato, de propósito

- **Parcelas:** um título tem de 1 a 3 parcelas, com o mesmo número e `i/p`. Um leitor que indexa
  só pelo número descartaria 2/3 das linhas.
- **Fronteiras de faixa sempre presentes:** atraso 0 (vence na data-base = a vencer), 1, 30, 31,
  60, 61, 90, 91, 180, 181, 360 e 361 dias.
- **XLSX como o Excel grava:** texto em `sharedStrings.xml` (`t="s"`), data como serial com
  formato 14, linha em branco ausente do XML. A primeira versão usava o openpyxl em modo
  write_only, que grava `inlineStr`, formato que nenhum arquivo real tem.
- CSV em **windows-1252**, separador `;`, valor `1.234,56`, fim de linha CRLF.
- Duas linhas de título do relatório, uma em branco, o cabeçalho e uma linha **TOTAL GERAL** no
  fim. O leitor tem de contá-las por destino, não descartá-las em silêncio.
- Título **parcial** (20% dos em aberto): valor original = pago + saldo.
- OFX 1.02 SGML, `CHARSET:1252`, tag folha **sem fechamento** (`<TRNAMT>-50.00`), como os bancos
  brasileiros entregam. Memo com acento; tipos CREDIT, DEP, DEBIT, PAYMENT, FEE e XFER (este nos
  dois sentidos: o tipo não dá o sinal). Não há saldo inicial no OFX: o leitor deduz (final − Σ) e confere contra o
  caixa do BP de 2024.
- CNPJ com dígito verificador válido.

## O que o conferidor confere (92 por tamanho)

Contra o **book**: Σ saldo, saldo por faixa (calculada pela DATA de vencimento, não pelo rótulo
do gerador), saldo por contraparte, créditos e débitos por mês, saldo final, saldo inicial
deduzido. Contra o **próprio arquivo**: toda linha com destino, nenhuma não reconhecida, título +
parcela único, parcelas completas e da mesma contraparte, situação coerente com pago e saldo,
emissão até o vencimento e até a data-base, original = pago + saldo, linha TOTAL GERAL = Σ, ano e
período do OFX, FITID único, tipo coerente com o sinal. O **.xlsx** passa pelas mesmas
conferências do CSV (cada célula vira o texto que o CSV teria). O **GABARITO** é recalculado
inteiro do arquivo e comparado campo a campo. O conferidor não importa o `gerar_volume.py`.

`test_volume.py` (14 testes, ~5 s, no CI) estraga o arquivo ou o gabarito de 12 jeitos e exige a
conferência certa reprovando, mais o determinismo ao byte.

## Medido em 11/11/2026 (este container)

| Linhas | AR .csv (gzip) | AP .csv | AR .xlsx (gzip) | OFX (transações) |
|---|---|---|---|---|
| 10 mil | 1,3 MB (0,2) | 1,3 MB | 0,5 MB (0,5) | 0,2 MB (1.422) |
| 100 mil | 13,3 MB (2,1) | 13,3 MB | 5,6 MB (4,7) | 2,0 MB (14.280) |
| 1 milhão | **133,1 MB (21,9)** | 133,1 MB | **57,2 MB (47,5)** | 20,3 MB (142.851) |

- Gerar os três tamanhos: 1 min 6 s. Conferir os três: 2 min 14 s. Os três: 92 de 92.
- **O teto do Storage de produção é 50 MiB por arquivo** (`fileSizeLimit` = 52.428.800, lido pela
  API em 11/11/2026). Com 1M de linhas, nem o CSV (133 MB) nem o .xlsx (57 MB) cabem crus. Em gzip
  os dois cabem: o CSV com folga (21,9 MB), o .xlsx **por pouco** (47,5 MB contra 52,4 MB). Um .xlsx
  real com mais colunas passa do teto: guardar em partes tem de existir desde a MB7.
- A tabela de strings do .xlsx de 1M tem 622 mil entradas, porque o número do título é texto. É ela
  que o leitor em fluxo da MB1 tem de manter em memória.

## Limites declarados

- A concentração do AR é 100% nos 10 maiores, porque só os 10 clientes nomeados do book têm saldo
  em aberto (os pulverizados só têm liquidados). Serve para conciliar; não serve para medir a tela de
  concentração. A MB3 planta o caso pulverizado se precisar.
- Arquivo de uma conta bancária só, um ano. Várias contas e meses faltando ficam para a MB5.
- Sem saldo negativo (crédito de cliente, adiantamento) e sem linha de subtotal por cliente. Os
  dois existem em ERP real; entram quando a MB3 tiver o arquivo real (DM7) para copiar a forma.
- É sintético. Arquivo real de mandato (DM7) continua pendente do dono.
