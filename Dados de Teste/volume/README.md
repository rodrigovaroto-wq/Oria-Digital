# Bases volumosas sintéticas — contas a receber, contas a pagar e OFX (MB0)

Fatia **MB0** do `Arquitetura do Sistema/3 Estado e Execução/PLANO_MVP_2026-11.md`: o insumo
para medir o leitor tabular (MB1), o aging (MB3, MB4) e o OFX (MB5) com 10 mil, 100 mil e 1 milhão
de linhas, antes de existir arquivo real.

```bash
cd "Dados de Teste"/volume
python3 gerar_volume.py --xlsx      # saida/: 3 tamanhos × (AR .csv, AP .csv, OFX) + AR .xlsx + GABARITO_<n>.json
python3 conferir_volume.py          # relê os ARQUIVOS e confronta com o book-distress
python3 test_volume.py -v           # prova que o conferidor reprova quando o arquivo mente (roda no CI)
```

`--linhas N` gera um tamanho só. O `.xlsx` precisa do `openpyxl==3.1.5` (o mesmo do book-espelho).

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

O volume vem de partir cada célula contraparte × faixa em muitos títulos, e de **títulos
liquidados** (saldo zero) de uma carteira pulverizada. O liquidado é a armadilha de propósito: é
linha lida e não pode entrar no aging.

## As armadilhas de formato, de propósito

- CSV em **windows-1252**, separador `;`, valor `1.234,56`, fim de linha CRLF.
- Duas linhas de título do relatório, uma em branco, o cabeçalho e uma linha **TOTAL GERAL** no
  fim. O leitor tem de contá-las por destino, não descartá-las em silêncio.
- Título **parcial** (20% dos em aberto): valor original = pago + saldo.
- OFX 1.02 SGML, `CHARSET:1252`, tag folha **sem fechamento** (`<TRNAMT>-50.00`), como os bancos
  brasileiros entregam. Não há saldo inicial no OFX: o leitor deduz (final − Σ) e confere contra o
  caixa do BP de 2024.
- CNPJ com dígito verificador válido.

## O que o conferidor confere (41 por tamanho)

Contra o **book**: Σ saldo, saldo por faixa (calculada pela DATA de vencimento, não pelo rótulo
do gerador), saldo por contraparte, créditos e débitos por mês, saldo final, saldo inicial
deduzido. Contra o **próprio arquivo**: toda linha com destino, nenhuma não reconhecida, título
único, FITID único, original = pago + saldo, liquidado com saldo zero, linha TOTAL GERAL = Σ.
E o GABARITO contra o arquivo. Ele não importa o `gerar_volume.py`: se usasse a memória do
gerador, um arquivo escrito errado passaria pelos dois lados.

## Medido em 11/11/2026 (este container)

| Linhas | AR .csv (gzip) | AP .csv | AR .xlsx (gzip) | OFX (transações) |
|---|---|---|---|---|
| 10 mil | 1,3 MB (0,2) | 1,3 MB | 0,6 MB (0,6) | 0,2 MB (1.422) |
| 100 mil | 13,4 MB (2,1) | 13,1 MB | 6,2 MB (5,4) | 2,0 MB (14.280) |
| 1 milhão | **133,2 MB (21,2)** | 130,7 MB | **61,9 MB (54,3)** | 19,8 MB (142.851) |

- Gerar os três tamanhos com o .xlsx: 2 min 45 s. Conferir os três: 37 s. Os três: 41 de 41.
- **O teto do Storage de produção é 50 MiB por arquivo** (`fileSizeLimit` = 52.428.800, lido pela
  API em 11/11/2026). O CSV de 1M não cabe cru e cabe em gzip. **O .xlsx de 1M não cabe nem em
  gzip** (o .xlsx já é um zip): o original tem de ser guardado em partes.

## Limites declarados

- A concentração do AR é 100% nos 10 maiores, porque só os 10 clientes nomeados do book têm saldo
  em aberto (os pulverizados só têm liquidados). Serve para conciliar; não serve para medir a tela de
  concentração. A MB3 planta o caso pulverizado se precisar.
- Arquivo de uma conta bancária só, um ano. Várias contas e meses faltando ficam para a MB5.
- É sintético. Arquivo real de mandato (DM7) continua pendente do dono.
