# Linha de base da leitura — P4 (07/11/2026)

Medida em produção depois da 0229 e da republicação do n8n (`versao_medicao = p4-1` em todos os documentos), com os 4 books sintéticos enviados pelo portal como Sócio (`Verificação/enviar-book.mts`) e cruzados com a verdade do gerador (`Verificação/linha-de-base.mts`). Custo total dos 4 lotes: US$ 0,61.

**Como ler:** *Verdade* = linhas de conta que o gerador escreveu. *Régua* = o que o n8n contou no texto (o denominador de produção). *Lidas* = o que a IA devolveu. *Lidas/verdade* é a completude real; *Régua/verdade* diz se a régua conta certo.

## Resumo

| Book | Docs | 100% lidos | < 95% | > 105% | Régua errada (>5%) | Sem número |
|---|---|---|---|---|---|---|
| Vertentes | 14 | 9 | 3 | 1 | 1 | 1 |
| Canastra | 38 | 26 | 3 | 1 | 4 | 5 |
| Distress | 14 | 8 | 3 | 2 | 4 | 1 |
| Espelho | **3 de 11** | 1 | 0 | 0 | 0 | 0 |

## Achados (medidos, causa ainda NÃO investigada — é a P5 em diante)

1. **ALTO — 8 de 11 arquivos do book-espelho sumiram sem rastro.** O Form do n8n (execução 9508, "success") recebeu só 3 arquivos: os 3 com nome só ASCII. Os 8 perdidos têm acento/ç no nome. Nenhuma linha em `execucao_falha`, nenhum documento. A perda é ENTRE o portal e o Form. NÃO verificado se é defeito do portal ou do upload pelo navegador automatizado (Playwright `setInputFiles`) — é a primeira coisa a investigar, porque cliente real manda nome com acento.
2. **Colunas desalinhadas:** o Balanço COMBINADO do Vertentes saiu com 0 de 32 linhas (todas descartadas por desalinhamento); os COMBINADOS do Canastra e o Aging a receber perderam 1 linha cada pelo mesmo motivo. É a falha real do Krauspenhar.
3. **Leitura que infla (> 100%):** DMPL Vertentes 14/3, DMPL Canastra 29/9, BP Piraquara Montagens 43/32, Notas Piraquara 20/5. A régua contou certo nesses; quem duplica é a leitura. É a origem das coberturas 1,31/1,43/2,25 de produção.
4. **Régua errada:** conta linhas em notas explicativas (9 onde há 0 no Vertentes) e na procuração (medido no gerador). Cobertura do sistema acima de 1 nem sempre é leitura duplicando.
5. **Custo:** a DRE analítica e o balancete grandes custam ~US$ 0,08/chamada contra a estimativa de 0,055 que sustenta o teto (`medir-custo-book`, rc 1 no espelho).


## Tabela — vertentes

| Documento | Verdade | Régua | Lidas | Lidas/verdade | Régua/verdade | Motivo | Blocos (resp./total) | Falha |
|---|---|---|---|---|---|---|---|---|
| 01_BP_Vertentes_Metalurgica_2025x2024.pdf | 99 | 99 | 99 | 1.00 | 1.00 |  | 1/1 |  |
| 02_BP_Vertentes_Componentes_2025x2024.pdf | 61 | 61 | 56 | 0.92 | 1.00 |  | 1/1 |  |
| 03_BP_Vertentes_Participacoes_2025x2024.pdf | 33 | 33 | 33 | 1.00 | 1.00 |  | 1/1 |  |
| 04_BP_VT_Logistica_2025x2024.pdf | 40 | 40 | 40 | 1.00 | 1.00 |  | 1/1 |  |
| 05_BP_Vertentes_Imoveis_SPE_2025x2024.pdf | 28 | 28 | 28 | 1.00 | 1.00 |  | 1/1 |  |
| 06_BP_COMBINADO_Grupo_Vertentes_2025.pdf | 32 | 32 | 0 | 0.00 | 1.00 |  | 1/1 | bloco 1: 32 conta(s) descartada(s) por desalinhamento entre colunas e valores (a |
| 07_DRE_Vertentes_Metalurgica_2025x2024.pdf | 28 | 28 | 28 | 1.00 | 1.00 |  | 1/1 |  |
| 08_DFC_Vertentes_Metalurgica_2025.pdf | 29 | 29 | 29 | 1.00 | 1.00 |  | 1/1 |  |
| 09_DMPL_Vertentes_Metalurgica_2025.pdf | 3 | 3 | 14 | 4.67 | 1.00 |  | 1/1 |  |
| 10_Faturamento_24M_Vertentes_Metalurgica.pdf | 16 | 15 | 15 | 0.94 | 0.94 |  | 1/1 |  |
| 11_Mapa_Divida_Vertentes_Metalurgica_2025.pdf | 10 | 10 | 10 | 1.00 | 1.00 |  | 1/1 |  |
| 12_Mutuos_Intragrupo_Grupo_Vertentes_2025.pdf | 5 | 5 | 5 | 1.00 | 1.00 |  | 1/1 |  |
| 13_Balancete_Analitico_Componentes_2025.pdf | 34 | 34 | 34 | 1.00 | 1.00 |  | 1/1 |  |
| 14_Notas_Explicativas_Grupo_Vertentes_2025.pdf | 0 | 9 | 4 | — | — |  | 1/1 |  |

## Tabela — canastra

| Documento | Verdade | Régua | Lidas | Lidas/verdade | Régua/verdade | Motivo | Blocos (resp./total) | Falha |
|---|---|---|---|---|---|---|---|---|
| 01_Balanco_Patrimonial_Canastra_Industria_2025x2024x2023.pdf | 114 | 114 | 114 | 1.00 | 1.00 |  | 2/2 |  |
| 02_DRE_Canastra_Industria_2025x2024x2023.pdf | 39 | 39 | 39 | 1.00 | 1.00 |  | 1/1 |  |
| 03_DFC_Canastra_Industria_12M25.pdf | 18 | 18 | 18 | 1.00 | 1.00 |  | 1/1 |  |
| 04_DMPL_Canastra_Industria_2023_a_2025.pdf | 9 | 9 | 29 | 3.22 | 1.00 |  | 1/1 |  |
| 05_DVA_Canastra_Industria_12M25.pdf | 16 | 16 | 16 | 1.00 | 1.00 |  | 1/1 |  |
| 06_Balanco_Patrimonial_Canastra_Comercial_2025x2024.pdf | 49 | 49 | 49 | 1.00 | 1.00 |  | 1/1 |  |
| 07_DRE_Canastra_Comercial_2025x2024.pdf | 10 | 10 | 10 | 1.00 | 1.00 |  | 1/1 |  |
| 08_Balanco_Patrimonial_Canastra_Participacoes_2025x2024.pdf | 29 | 29 | 29 | 1.00 | 1.00 |  | 1/1 |  |
| 09_Balanco_Patrimonial_CN_Transportes_2025x2024.pdf | 38 | 38 | 38 | 1.00 | 1.00 |  | 1/1 |  |
| 10_DRE_CN_Transportes_2025x2024.pdf | 10 | 10 | 10 | 1.00 | 1.00 |  | 1/1 |  |
| 11_Balanco_Patrimonial_Canastra_Agroflorestal_2025x2024.pdf | 34 | 34 | 34 | 1.00 | 1.00 |  | 1/1 |  |
| 12_Balanco_Patrimonial_Canastra_Imobiliaria_SPE_2025x2024.pdf | 28 | 28 | 28 | 1.00 | 1.00 |  | 1/1 |  |
| 13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf | 15 | 15 | 14 | 0.93 | 1.00 |  | 1/1 | bloco 1: 1 conta(s) descartada(s) por desalinhamento entre colunas e valores (a  |
| 14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf | 15 | 15 | 14 | 0.93 | 1.00 |  | 1/1 | bloco 1: 1 conta(s) descartada(s) por desalinhamento entre colunas e valores (a  |
| 15_Balancete_Analitico_Canastra_Industria_12M25.pdf | 78 | 78 | 79 | 1.01 | 1.00 |  | 2/2 |  |
| 16_Balancete_Analitico_Canastra_Industria_12M24.pdf | 73 | 73 | 73 | 1.00 | 1.00 |  | 1/1 |  |
| 17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf | 99 | 99 | 102 | 1.03 | 1.00 |  | 4/4 | total da série não fecha em "TOTAIS DO PERÍODO" (coluna "Saldo"): total declarad |
| 18_Faturamento_36_meses_Canastra_Industria_2023_a_2025.pdf | 39 | 39 | 39 | 1.00 | 1.00 |  | 1/1 |  |
| 19_Faturamento_Intragrupo_Grupo_Canastra_2023_a_2025.pdf | 15 | 15 | 15 | 1.00 | 1.00 |  | 1/1 |  |
| 20_Mapa_de_Divida_Canastra_Industria_2025.pdf | 12 | 12 | 12 | 1.00 | 1.00 |  | 1/1 |  |
| 21_Mutuos_Intragrupo_Grupo_Canastra_2025.pdf | 3 | 3 | 3 | 1.00 | 1.00 |  | 1/1 |  |
| 22_Aging_de_Contas_a_Receber_Canastra_Industria_2025.pdf | 14 | 15 | 13 | 0.93 | 1.07 |  | 1/1 | bloco 1: 1 conta(s) descartada(s) por desalinhamento entre colunas e valores (a  |
| 23_Aging_de_Contas_a_Pagar_Canastra_Industria_2025.pdf | 10 | 13 | 10 | 1.00 | 1.30 |  | 1/1 |  |
| 24_Posicao_de_Estoques_Canastra_Industria_2025.pdf | 17 | 17 | 17 | 1.00 | 1.00 |  | 1/1 |  |
| 25_Situacao_Fiscal_e_Parcelamentos_Grupo_Canastra_2025.pdf | 10 | 14 | 10 | 1.00 | 1.40 |  | 1/1 |  |
| 26_Contingencias_e_Processos_Judiciais_Canastra_Industria_2025.pdf | 8 | 10 | 8 | 1.00 | 1.25 |  | 1/1 |  |
| 27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf | 9 | 9 | 9 | 1.00 | 1.00 |  | 1/1 |  |
| 28_Folha_de_Pagamento_Canastra_Industria_2025.pdf | 9 | 9 | 9 | 1.00 | 1.00 |  | 1/1 |  |
| 29_Extrato_Bancario_Consolidado_Canastra_Industria_2025.pdf | 6 | 6 | 6 | 1.00 | 1.00 |  | 1/1 |  |
| 30_Certidoes_Negativas_Grupo_Canastra.pdf | 0 | 0 | 0 | — | — | documento_sem_dado_financeiro | 1/1 |  |
| 31_Contrato_Social_Consolidado_Canastra_Industria.pdf | 0 | 7 | 4 | — | — |  | 1/1 |  |
| 32_Organograma_Societario_Grupo_Canastra.pdf | 0 | 6 | 0 | — | — | documento_sem_dado_financeiro | 1/1 |  |
| 33_Notas_Explicativas_Grupo_Canastra_12M25.pdf | 0 | 14 | 9 | — | — |  | 1/1 |  |
| 34_Relatorio_do_Auditor_Independente_2025.pdf | 0 | 1 | 0 | — | — | documento_sem_dado_financeiro | 1/1 |  |
| 35_Demonstracoes_Contabeis_Canastra_Industria_2024x2023.pdf | 159 | 163 | 161 | 1.01 | 1.03 |  | 2/2 |  |
| ANEXO IV - planilha final REV3.pdf | 18 | 18 | 18 | 1.00 | 1.00 |  | 1/1 |  |
| digitalizado_20260115_0003.pdf | 26 | 26 | 26 | 1.00 | 1.00 |  | 1/1 |  |
| Doc1.pdf | 34 | 34 | 34 | 1.00 | 1.00 |  | 1/1 |  |

## Tabela — distress

| Documento | Verdade | Régua | Lidas | Lidas/verdade | Régua/verdade | Motivo | Blocos (resp./total) | Falha |
|---|---|---|---|---|---|---|---|---|
| 01_Balanco_Patrimonial_Piraquara_Metalurgica_2025x2024x2023.pdf | 61 | 61 | 61 | 1.00 | 1.00 |  | 1/1 |  |
| 02_DRE_Piraquara_Metalurgica_2025x2024x2023.pdf | 34 | 34 | 34 | 1.00 | 1.00 |  | 1/1 |  |
| 03_DFC_Piraquara_Metalurgica_2025x2024.pdf | 25 | 25 | 25 | 1.00 | 1.00 |  | 1/1 |  |
| 04_Balanco_Patrimonial_Piraquara_Montagens_2025x2024x2023.pdf | 32 | 32 | 43 | 1.34 | 1.00 |  | 1/1 |  |
| 05_DRE_Piraquara_Montagens_2025x2024x2023.pdf | 13 | 13 | 13 | 1.00 | 1.00 |  | 1/1 |  |
| 06_Balanco_Patrimonial_Piraquara_Participacoes_2025x2024x2023.pdf | 24 | 24 | 24 | 1.00 | 1.00 |  | 1/1 |  |
| 07_DRE_Piraquara_Participacoes_2025x2024x2023.pdf | 5 | 5 | 5 | 1.00 | 1.00 |  | 1/1 |  |
| 08_Mapa_de_Divida_e_Covenant_Piraquara_Metalurgica_2025.pdf | 18 | 17 | 17 | 0.94 | 0.94 |  | 1/1 |  |
| 09_Mutuos_Intragrupo_Grupo_Piraquara_2025.pdf | 4 | 4 | 3 | 0.75 | 1.00 |  | 1/1 |  |
| 10_Aging_de_Contas_a_Pagar_Piraquara_Metalurgica_2025.pdf | 15 | 15 | 14 | 0.93 | 1.00 |  | 1/1 |  |
| 11_Aging_de_Contas_a_Receber_Piraquara_Metalurgica_2025.pdf | 13 | 14 | 13 | 1.00 | 1.08 |  | 1/1 |  |
| 12_Extrato_Bancario_Banco_Tapajos_cc_20417-3_Piraquara_Metalurgica_2025.pdf | 13 | 14 | 13 | 1.00 | 1.08 |  | 1/1 | total da série não fecha em "TOTAL DO PERÍODO" (coluna "Saldo inicial"): total d |
| 13_Notas_Explicativas_Piraquara_Metalurgica_12M25.pdf | 5 | 24 | 20 | 4.00 | 4.80 |  | 1/1 | bloco 1: Cobertura do bloco 1 de 1 abaixo do minimo de 85% mesmo apos 2 tentativ |
| 14_Relatorio_do_Auditor_Independente_Piraquara_Metalurgica_2025.pdf | 0 | 1 | 0 | — | — | documento_sem_dado_financeiro | 1/1 |  |

## Tabela — espelho

| Documento | Verdade | Régua | Lidas | Lidas/verdade | Régua/verdade | Motivo | Blocos (resp./total) | Falha |
|---|---|---|---|---|---|---|---|---|
| balancete_janaago26.pdf | 614 | 621 | 594 | 0.97 | 1.01 |  | 16/16 |  |
| DRE_janaago26.pdf | 432 | 439 | 438 | 1.01 | 1.02 |  | 16/16 | bloco 5: 1 conta(s) descartada(s) por desalinhamento entre colunas e valores (a  |
| Extrato cc 41.207-3 agosto 2026.xlsx | 136 | 136 | 136 | 1.00 | 1.00 |  | 4/4 | bloco 1: O arquivo .xlsx tem 2 abas e o extrator nativo leu SO a primeira (142 l |
