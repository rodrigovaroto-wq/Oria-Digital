# Status por etapa — 11/11/2026

> **O que é este arquivo.** Um retrato do plano de execução em três contas, conferido contra o banco de produção, o n8n e o `ESTADO.md` em **11/11/2026**. Ele não substitui o `ESTADO.md` nem o `MAPA_DE_EXECUCAO.md`: responde "onde cada etapa está e quando deve acabar". O painel visual equivalente está no Miro, no quadro "Planejamento Oria Digital".

## Como ler

- **Etapa** = linha da tabela, numerada **Fase.Etapa** (por exemplo 3.2). A coluna "Código antigo" aponta para o nome que o roadmap e o plano usam (F4, P27, F2T onda 1…).
- **Percentual**: 100 para completo e 0 para não iniciado. Para as 5 etapas em andamento é **estimativa**, com a base escrita na observação. Cada etapa pesa igual; o peso por esforço não foi calculado.
- **Fim estimado**: data em que a etapa acaba se cada conta mantiver **5 sessões por semana** a partir de 16/11/2026, sem folga de feriado e sem atrito de integração. Com ~15% de atrito, some cerca de uma semana ao fim do projeto.
- Data de etapa completa é a data em que ela foi concluída, quando o repositório registra.

## Resumo

| Status | Etapas |
|---|---|
| Completo | 20 |
| Em andamento | 5 |
| Não iniciado | 86 |
| **Total** | **111** |

Percentual médio do plano (etapas com peso igual): **21.2%**. Fim previsto do projeto: **19/01/2027** (cerca de 29/01 com atrito).

## Sonda do banco de produção (11/11/2026, só leitura)

- **364 de 365** itens presentes. O ausente é `envio_segredo_no_vault`: a API de leitura não alcança o Vault, o segredo não está faltando.
- Migrations **0232, 0233 e 0234** aplicadas (4, 4 e 8 itens). Backfill da 0234: **38** pendências resolvidas. 80 mandatos.
- n8n: **63 de 63** nós iguais a `N8N/workflow.e1-ingestao.json` no `main` (`17176af`), conferido com `N8N/conferir-publicado.mjs`.
- A tabela `perimetro` tem **0 linhas**. Não existem ainda `conta_canonica`, `fato_financeiro`, `lineage_aresta`, `resultado_calculo`, `cenario`, `alavanca`, `instrumento_divida`, `consulta_externa` e `organizacao`; `campo_extraido` não tem a coluna `ln`.

## Resumo por fase

| Fase | Nome | Etapas | Completo | Em andamento | Não iniciado | % | Status da fase |
|---|---|---|---|---|---|---|---|
| 0 | Alicerce já construído antes deste plano | 19 | 17 | 2 | 0 | 99% | Em andamento |
| 1 | Colocar no ar o que está pronto | 3 | 3 | 0 | 0 | 100% | Completo |
| 2 | Extração que não perde linha | 6 | 0 | 1 | 5 | 6% | Em andamento |
| 3 | Conta canônica | 6 | 0 | 0 | 6 | 0% | Não iniciado |
| 4 | Rastreabilidade | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 5 | Perímetro e grupo | 5 | 0 | 1 | 4 | 12% | Em andamento |
| 6 | Motor de cálculo | 5 | 0 | 0 | 5 | 0% | Não iniciado |
| 7 | Cenários e alavancas | 4 | 0 | 0 | 4 | 0% | Não iniciado |
| 8 | Estrutura de capital | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 9 | Liquidez de 13 semanas | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 10 | Diagnóstico analítico | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 11 | Valuation | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 12 | Recuperação de credores | 3 | 0 | 0 | 3 | 0% | Não iniciado |
| 13 | Reestruturação | 4 | 0 | 0 | 4 | 0% | Não iniciado |
| 14 | Apresentação de crédito | 4 | 0 | 1 | 3 | 20% | Em andamento |
| 15 | Portal e área do cliente | 9 | 0 | 0 | 9 | 0% | Não iniciado |
| 16 | Fontes oficiais | 9 | 0 | 0 | 9 | 0% | Não iniciado |
| 17 | Fontes externas e pré-mandato | 7 | 0 | 0 | 7 | 0% | Não iniciado |
| 18 | Análise comparativa do setor | 8 | 0 | 0 | 8 | 0% | Não iniciado |
| 19 | Segurança e operação contínua | 4 | 0 | 0 | 4 | 0% | Não iniciado |

Status da fase: completo se todas as etapas estão completas; não iniciado se nenhuma começou; em andamento nos demais casos.

## Etapas

### Fase 0 — Alicerce já construído antes deste plano

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 0.1 | Fundação: inventário, migrations, workflows, portões | F0 | todas | Completo | 100% | concluída |  |
| 0.2 | Reprocessar a rodada Teste 00 | fatia 0.5 | Claude Oria 2 | Em andamento | 90% | após o Portão da extração (24/11), a medir de novo | 94,9% contra a meta de 95% em 18/09; o número mede qualidade, o percentual é estimativa |
| 0.3 | Entidade, papel e perímetro no banco | F1 1.1 a 1.5, 1.8 | todas | Completo | 100% | concluída em 15/10 | a declaração do perímetro é a etapa 5.1 |
| 0.4 | Cobertura de tipos em produção | F2 | todas | Completo | 100% | concluída em 22/09 |  |
| 0.5 | Terceiro book de teste, o distress | F2.4 | todas | Completo | 100% | concluída em 22/09 |  |
| 0.6 | Deploy, dial e recusas | P1 a P1d | todas | Completo | 100% | concluída em 09/11 |  |
| 0.7 | Usuários de teste e vistoria por papel | P2 | todas | Completo | 100% | concluída em 04/11 |  |
| 0.8 | Envio roteado pelo caso | P3 | todas | Completo | 100% | concluída em 04/11 |  |
| 0.9 | Linha de base e corpus de regressão | P4 | todas | Completo | 100% | concluída em 09/11 |  |
| 0.10 | Estouro de pilha na junção | P5 | todas | Completo | 100% | concluída em 09/11 |  |
| 0.11 | Desalinhamento de colunas | P6, P6b | todas | Completo | 100% | concluída em 10/11 |  |
| 0.12 | Fila de reprocesso | P7, P7b | todas | Completo | 100% | no ar em 11/11 |  |
| 0.13 | Retentativa classificada | P8 | todas | Completo | 100% | no ar em 11/11 |  |
| 0.14 | Período e entidade errados | P9 | todas | Completo | 100% | no ar em 11/11 |  |
| 0.15 | Defeitos do portal, lote 1 | P16 | todas | Completo | 100% | concluída em 07/11 |  |
| 0.16 | Acesso por mandato: RLS e papéis | 0216 | todas | Completo | 100% | concluída em 30/10 |  |
| 0.17 | Entregáveis e capítulos no portal | F15/F16 parte | todas | Completo | 100% | concluída |  |
| 0.18 | Roteador e leitor de arquivos oficiais, sem cliente | F2T etapa 1 | todas | Completo | 100% | concluída em 13/10 |  |
| 0.19 | Decisões D12 da trilha de arquivos oficiais | F2T etapa 0 | dono | Em andamento | 91% | depende da sua decisão | 10 de 11 respondidas |

### Fase 1 — Colocar no ar o que está pronto

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 1.1 | Aplicar 0232, 0233 e 0234 | A0 | Claude Oria 2 | Completo | 100% | concluída em 11/11 | sonda: 4, 4 e 8 itens presentes |
| 1.2 | Republicar a ingestão | A0 | Claude Oria 2 | Completo | 100% | concluída em 11/11 | 63 de 63 nós iguais ao main (17176af) |
| 1.3 | Conferir a sonda | A0 | Claude Oria 2 | Completo | 100% | concluída em 11/11 | 364 de 365; o ausente é o limite de leitura do Vault |

### Fase 2 — Extração que não perde linha

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 2.1 | Rodada de regressão paga | P10 | Claude Oria 2 | Em andamento | 35% | 17/11 | sintéticos rodados (66 de ~206 documentos do corpus, US$ 0,28); faltam os reais e 2 regressões silenciosas no Canastra |
| 2.2 | Numerar as linhas do documento | P11 | Claude Oria 2 | Não iniciado | 0% | 18/11 |  |
| 2.3 | Toda linha com destino declarado | P12 | Claude Oria 2 | Não iniciado | 0% | 19/11 |  |
| 2.4 | Valor igual ao texto da linha | P13 | Claude Oria 2 | Não iniciado | 0% | 20/11 |  |
| 2.5 | Re-perguntar só o buraco | P14 | Claude Oria 2 | Não iniciado | 0% | 23/11 |  |
| 2.6 | Guardas medidas e portão da extração | P15 | Claude Oria 2 | Não iniciado | 0% | 24/11 |  |

### Fase 3 — Conta canônica

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 3.1 | Catálogo de contas | P26 | Claude Oria | Não iniciado | 0% | 16/11 |  |
| 3.2 | Fato financeiro com identidade | P27 | Claude Oria | Não iniciado | 0% | 17/11 |  |
| 3.3 | Subtotal igual à soma das folhas | P28 | Claude Oria | Não iniciado | 0% | 18/11 |  |
| 3.4 | Primeira reconciliação migrada | P29 | Claude Oria | Não iniciado | 0% | 19/11 |  |
| 3.5 | Portão das seis semanas | P30 | Claude Oria | Não iniciado | 0% | 25/11 |  |
| 3.6 | Nove reconciliações migradas | F4 2ª metade | Claude Oria | Não iniciado | 0% | 03/12 |  |

### Fase 4 — Rastreabilidade

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 4.1 | Registro de origem e transformação | F5 | Claude Oria | Não iniciado | 0% | 20/11 |  |
| 4.2 | Consulta "de onde veio" por SQL | F5 | Claude Oria | Não iniciado | 0% | 23/11 |  |
| 4.3 | Nota do Excel gerada da origem | F5 | Claude Oria | Não iniciado | 0% | 24/11 |  |

### Fase 5 — Perímetro e grupo

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 5.1 | Fechar o perímetro | F1 final | Claude Oria 2 | Em andamento | 60% | 26/11 | código, tela e RLS no ar; a tabela perimetro tem 0 linhas; faltam decisões D2 a D4 |
| 5.2 | Aceite financeiro nos books de teste | (b) | Claude Oria 2 | Não iniciado | 0% | 30/11 |  |
| 5.3 | Eliminação intragrupo como fato | F6 | Claude Oria | Não iniciado | 0% | 04/12 |  |
| 5.4 | Combinado de 6 empresas fechando | F6 | Claude Oria | Não iniciado | 0% | 07/12 |  |
| 5.5 | Consumidor real de intragrupo e contrato social | F2.3 | Claude Oria | Não iniciado | 0% | 08/12 | depende da sua decisão |

### Fase 6 — Motor de cálculo

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 6.1 | Interpretador das 7 fórmulas | F7 | Claude Oria | Não iniciado | 0% | 10/12 |  |
| 6.2 | 89 premissas dentro do motor | F7 | Claude Oria | Não iniciado | 0% | 14/12 |  |
| 6.3 | Excel emitido pelo motor | F7 | Claude Oria | Não iniciado | 0% | 16/12 |  |
| 6.4 | Guarda de dias de giro | F7 | Claude Oria | Não iniciado | 0% | 17/12 |  |
| 6.5 | Portão de paridade | F7 | Claude Oria | Não iniciado | 0% | 18/12 |  |

### Fase 7 — Cenários e alavancas

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 7.1 | Tabela de cenários | F8 | Claude Oria 2 | Não iniciado | 0% | 22/12 |  |
| 7.2 | Tabela de alavancas | F8 | Claude Oria 2 | Não iniciado | 0% | 23/12 |  |
| 7.3 | Cenário ligado às premissas | F8 | Claude Oria 2 | Não iniciado | 0% | 25/12 |  |
| 7.4 | Alavanca operacional como categoria | F8 | Claude Oria 2 | Não iniciado | 0% | 28/12 |  |

### Fase 8 — Estrutura de capital

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 8.1 | Instrumento de dívida e mapa fino | F9 | Claude Oria | Não iniciado | 0% | 22/12 |  |
| 8.2 | Credor e garantia | F9 | Claude Oria | Não iniciado | 0% | 24/12 |  |
| 8.3 | Covenant | F9 | Claude Oria | Não iniciado | 0% | 25/12 |  |

### Fase 9 — Liquidez de 13 semanas

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 9.1 | Granularidade semanal | F10 | Claude Pessoal | Não iniciado | 0% | 30/12 |  |
| 9.2 | Aging e extrato ligados | F10 | Claude Pessoal | Não iniciado | 0% | 01/01 |  |
| 9.3 | Projeção de 13 semanas | F10 | Claude Pessoal | Não iniciado | 0% | 04/01 |  |

### Fase 10 — Diagnóstico analítico

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 10.1 | Motor de índices | F11 | Claude Pessoal | Não iniciado | 0% | 05/01 |  |
| 10.2 | Tendências | F11 | Claude Pessoal | Não iniciado | 0% | 06/01 |  |
| 10.3 | Sinais e diagnóstico factual | F11 | Claude Pessoal | Não iniciado | 0% | 07/01 |  |

### Fase 11 — Valuation

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 11.1 | DCF | F12 | Claude Oria | Não iniciado | 0% | 29/12 |  |
| 11.2 | Múltiplos | F12 | Claude Oria | Não iniciado | 0% | 31/12 |  |
| 11.3 | Ajuste de EBITDA | F12 | Claude Oria | Não iniciado | 0% | 01/01 |  |

### Fase 12 — Recuperação de credores

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 12.1 | Prioridade legal dos credores | F13 | Claude Oria | Não iniciado | 0% | 05/01 |  |
| 12.2 | Waterfall de recuperação | F13 | Claude Oria | Não iniciado | 0% | 07/01 |  |
| 12.3 | Trava: recuperado nunca passa do distribuível | F13 | Claude Oria | Não iniciado | 0% | 08/01 |  |

### Fase 13 — Reestruturação

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 13.1 | Alongamento e carência | F14 | Claude Oria | Não iniciado | 0% | 11/01 |  |
| 13.2 | Haircut | F14 | Claude Oria | Não iniciado | 0% | 12/01 |  |
| 13.3 | New money | F14 | Claude Oria | Não iniciado | 0% | 12/01 |  |
| 13.4 | Comparação com o cenário Base | F14 | Claude Oria | Não iniciado | 0% | 13/01 |  |

### Fase 14 — Apresentação de crédito

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 14.1 | Camada sem estado sobre o motor | F15 | Claude Oria | Não iniciado | 0% | 15/01 |  |
| 14.2 | Portão: zero aritmética fora do motor | F15 | Claude Oria | Não iniciado | 0% | 18/01 |  |
| 14.3 | Gerador do .pptx | F16 | Claude Oria | Em andamento | 80% | 19/01 | implementado; falta aplicar em produção |
| 14.4 | Aplicar em produção e conferir PPT, Excel e banco | F16 | Claude Oria | Não iniciado | 0% | 19/01 |  |

### Fase 15 — Portal e área do cliente

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 15.1 | Lote 2 de defeitos | P17 | Claude Oria 2 | Não iniciado | 0% | 01/12 |  |
| 15.2 | Mandato com Produto e Responsável | P18 | Claude Oria 2 | Não iniciado | 0% | 02/12 | a coluna produto já existe em caso; responsável não |
| 15.3 | Tempo até aprovar e testes | P19 | Claude Oria 2 | Não iniciado | 0% | 03/12 |  |
| 15.4 | Senha e vistoria final | P20 | Claude Oria 2 | Não iniciado | 0% | 04/12 |  |
| 15.5 | Desenho da organização e do cliente | P21 | Claude Oria 2 | Não iniciado | 0% | 07/12 |  |
| 15.6 | RLS por organização | P22 | Claude Oria 2 | Não iniciado | 0% | 08/12 |  |
| 15.7 | Papel Cliente | P23 | Claude Oria 2 | Não iniciado | 0% | 09/12 |  |
| 15.8 | Telas da área do cliente | P24 | Claude Oria 2 | Não iniciado | 0% | 10/12 |  |
| 15.9 | Revisão de segurança | P25 | Claude Oria 2 | Não iniciado | 0% | 11/12 |  |

### Fase 16 — Fontes oficiais

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 16.1 | Jurídico e segurança | F2T etapa 2 | Claude Pessoal | Não iniciado | 0% | 02/12 | depende do jurídico |
| 16.2 | Onda 1: ECD, ECF e CNAE (sintético) | F2T onda 1 | Claude Pessoal | Não iniciado | 0% | 01/12 | com dado real, bloqueada pelos 3 ECDs (D14) |
| 16.3 | Onda 2: OFX e CNAB | F2T onda 2 | Claude Pessoal | Não iniciado | 0% | 08/12 |  |
| 16.4 | Onda 3: EFD, Reinf e NF-e | F2T onda 3 | Claude Pessoal | Não iniciado | 0% | 15/12 |  |
| 16.5 | Reconciliações por conta das ondas | F2T | Claude Pessoal | Não iniciado | 0% | 16/12 |  |
| 16.6 | Intragrupo das notas (G11) | F2T | Claude Pessoal | Não iniciado | 0% | 17/12 |  |
| 16.7 | Onda 4: eSocial, DCTFWeb, FGTS | F2T onda 4 | Claude Pessoal | Não iniciado | 0% | 23/12 |  |
| 16.8 | Onda 5: logística e câmbio | F2T onda 5 | Claude Pessoal | Não iniciado | 0% | 28/12 |  |
| 16.9 | Captação: cofre, robô e painel | F2T captação | Claude Oria 2 | Não iniciado | 0% | 04/01 |  |

### Fase 17 — Fontes externas e pré-mandato

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 17.1 | Consulta externa: tabelas e coletor público | F2E 2 | Claude Pessoal | Não iniciado | 0% | 17/11 | a tabela consulta_externa não existe |
| 17.2 | Momento pré-mandato | F2E 3 | Claude Pessoal | Não iniciado | 0% | 18/11 |  |
| 17.3 | Processos | F2E 4 | Claude Oria 2 | Não iniciado | 0% | 08/01 | depende de D13.3 |
| 17.4 | Bureau | F2E 5 | Claude Oria 2 | Não iniciado | 0% | 11/01 | depende de D13.6 |
| 17.5 | Deck pré-mandato | F2E 6 | Claude Oria 2 | Não iniciado | 0% | 12/01 |  |
| 17.6 | Open Finance | F2E 7 | Claude Oria 2 | Não iniciado | 0% | 13/01 |  |
| 17.7 | Núclea | F2E 8 | Claude Oria 2 | Não iniciado | 0% | 14/01 |  |

### Fase 18 — Análise comparativa do setor

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 18.1 | Conferir as fontes | F6C 0 | Claude Pessoal | Não iniciado | 0% | 19/11 |  |
| 18.2 | Coletores públicos | F6C 1 | Claude Pessoal | Não iniciado | 0% | 23/11 |  |
| 18.3 | Referência por setor e região | F6C 2 | Claude Pessoal | Não iniciado | 0% | 24/11 |  |
| 18.4 | Mercado, receita e índices | F6C 3 | Claude Oria 2 | Não iniciado | 0% | 21/12 |  |
| 18.5 | Unidades e despesas | F6C 4 | Claude Oria 2 | Não iniciado | 0% | 06/01 |  |
| 18.6 | Dívida contra o Banco Central | F6C 5 | Claude Pessoal | Não iniciado | 0% | 25/11 |  |
| 18.7 | Oportunidades que viram alavanca | F6C 6 | Claude Oria 2 | Não iniciado | 0% | 07/01 |  |
| 18.8 | Capítulo na apresentação | F6C 7 | Claude Oria 2 | Não iniciado | 0% | 19/01 |  |

### Fase 19 — Segurança e operação contínua

| Etapa | Nome | Código antigo | Conta | Status | % | Fim estimado | Observação |
|---|---|---|---|---|---|---|---|
| 19.1 | Proteção do main e Sonar no CI | F17 | Claude Oria 2 | Não iniciado | 0% | 14/12 |  |
| 19.2 | Teste de restauração do backup | F17 | Claude Oria 2 | Não iniciado | 0% | 15/12 |  |
| 19.3 | Registro de leitura na auditoria | F17 | Claude Oria 2 | Não iniciado | 0% | 16/12 |  |
| 19.4 | Conversão cambial | F17 | Claude Oria 2 | Não iniciado | 0% | 17/12 |  |

## O que ainda depende de você

- **Antes de 25/11:** D5 (autonomia); D2, D3, D4 (perímetro); substituto do COMBINADO do cliente no aceite 5.2; decidir se a etapa 5.5 (F2.3) entra.
- **Antes de 04/12:** D8 (SMTP) ou aceitar a limitação do link de recuperação; D9, D10, D11 (área do cliente).
- **Antes de 18/12:** termo e RIPD do jurídico, D12.7 e D12.3; cortes de covenant (D12).
- **Antes de 08/01:** D13.3 a D13.6 e o piloto 13C.
- **Já:** reenviar os originais reais do corpus (AMO, Valtra, Krauspenhar) para a etapa 2.1, e proteger o `main` no GitHub.

## O que este retrato não conferiu

- A tela do portal com sessão de usuário (o `ESTADO.md` registra que ninguém a abriu).
- As tabelas de credor, garantia, covenant e autorizacao, e as da Fase 18: tratadas como não iniciadas pelo `ESTADO.md` e pelo roadmap.
- Os percentuais das 5 etapas em andamento são julgamento, não medição.
