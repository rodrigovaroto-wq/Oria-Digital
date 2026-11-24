# Arquitetura do Sistema — índice da documentação

Esta pasta guarda o **porquê** do sistema: a visão, as decisões, a especificação de cada
estágio, o plano e as auditorias. O **como** está no código e nos READMEs de cada camada
([`Supabase/`](../Supabase/README.md), [`N8N/`](../N8N/README.md), [`portal/`](../portal/README.md),
[`Leitor/`](../Leitor/README.md)). A visão geral do repositório está no [`README.md`](../README.md) da raiz.

**Por onde começar:**
1. [`Como o sistema funciona`](3%20Estado%20e%20Execução/COMO_O_SISTEMA_FUNCIONA.md): o fluxo inteiro em linguagem simples.
2. [`00 — Visão e Escopo`](1%20Visão%20e%20Doutrina/00_VISAO_E_ESCOPO.md) e [`01 — Doutrina de Autonomia`](1%20Visão%20e%20Doutrina/01_DOUTRINA_DE_AUTONOMIA.md): o problema e a regra que governa a IA.
3. [`Business Plan/06_execucao/PLANO_DE_EXECUCAO.md`](../Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md): o plano em vigor (único, sem datas).

Esta pasta é a fonte oficial **técnica**. A fonte oficial de **negócio e produto** (decisões, agentes,
regras, governança, plano) é a pasta [`Business Plan/`](../Business%20Plan/README.md) (decisão K5).

Os documentos numerados de `00` a `14` são a série original da especificação. Eles estão
distribuídos pelas pastas conforme o tipo; o número continua sendo a forma de citá-los.

---

## 1 Visão e Doutrina

O que o sistema é, o que ele não é, e as decisões que não se reabrem.

| Documento | Conteúdo |
|---|---|
| [`00_VISAO_E_ESCOPO.md`](1%20Visão%20e%20Doutrina/00_VISAO_E_ESCOPO.md) | o problema, a redefinição do escopo e o escopo negativo |
| [`01_DOUTRINA_DE_AUTONOMIA.md`](1%20Visão%20e%20Doutrina/01_DOUTRINA_DE_AUTONOMIA.md) | os níveis N0 (sombra) a N3 (autônomo); cada estágio só sobe com concordância medida |
| [`02_ARQUITETURA_FUNCIONAL.md`](1%20Visão%20e%20Doutrina/02_ARQUITETURA_FUNCIONAL.md) | estágios, portões, componentes transversais e as travas de stack |
| [`03_MVP_E_ROADMAP.md`](1%20Visão%20e%20Doutrina/03_MVP_E_ROADMAP.md) | **superado** (histórico): o MVP como workflow completo; o roadmap construir → calibrar |
| [`04_ADR_01_EVIDENCIA_IMUTAVEL.md`](1%20Visão%20e%20Doutrina/04_ADR_01_EVIDENCIA_IMUTAVEL.md) | ADR-01: o que foi extraído nunca muda; o canônico é construído acima |
| [`05_ADR_02_ARITMETICA_NO_MOTOR.md`](1%20Visão%20e%20Doutrina/05_ADR_02_ARITMETICA_NO_MOTOR.md) | ADR-02: toda conta que chega ao cliente é feita no banco, não na tela nem no Excel |

## 2 Especificação

Como cada parte deve se comportar.

| Documento | Conteúdo |
|---|---|
| [`04_RECONCILIACAO.md`](2%20Especificação/04_RECONCILIACAO.md) | conciliação cruzada: classes A/B/C, materialidade, o que é automático |
| [`05_CLASSIFICACAO_CONTABIL.md`](2%20Especificação/05_CLASSIFICACAO_CONTABIL.md) | taxonomia fechada, sugestão, override, anti-ancoragem |
| [`06_HUMAN_IN_THE_LOOP.md`](2%20Especificação/06_HUMAN_IN_THE_LOOP.md) | pontos de revisão humana, papéis, calibração e auditoria |
| [`07_STATUS_E_PENDENCIAS.md`](2%20Especificação/07_STATUS_E_PENDENCIAS.md) | máquina de status do mandato, severidades e limites do portão |
| [`10_DADOS_RETENCAO_E_LGPD.md`](2%20Especificação/10_DADOS_RETENCAO_E_LGPD.md) | onde o dado do cliente mora, retenção, recuperação e quem vê o quê |
| [`11_ANALISE_DE_CREDITO_ASSESSORIA.md`](2%20Especificação/11_ANALISE_DE_CREDITO_ASSESSORIA.md) | análise de crédito pela ótica da assessoria, etapas 1 a 4 |
| [`12_FONTES_OFICIAIS_E_CAPTACAO.md`](2%20Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md) | SPED, eSocial, CNAB e a captação automática (é a especificação do [`Leitor/`](../Leitor/)) |
| [`13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md`](2%20Especificação/13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md) | parceiros de dados e o momento pré-mandato; anexos em [`13_anexos/`](2%20Especificação/13_anexos/) |
| [`14_COMPARATIVOS_SETORIAIS.md`](2%20Especificação/14_COMPARATIVOS_SETORIAIS.md) | análise comparativa: onde cortar custo e onde crescer receita |
| [`15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md`](2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md) | score de confiabilidade do dado captado fora e os portões por agente (v2; no plano: 0.13, Trilha K, 2.18, 2.19, 3.8, 3.9); anexos em [`15_anexos/`](2%20Especificação/15_anexos/): os 13 casos recalculáveis e a proposta em página |
| [`f0/`](2%20Especificação/f0/README.md) | o kit da fundação: baseline, build-vs-buy, taxonomia, schema conceitual, golden set e especificação do output |

## 3 Estado e Execução

Para onde o projeto vai e como chegar lá. O estado do dia está no [`ESTADO.md`](../ESTADO.md), na raiz.

| Documento | Conteúdo |
|---|---|
| [`PLANO_MVP_2026-11.md`](3%20Estado%20e%20Execução/PLANO_MVP_2026-11.md) | superado pelo [plano único](../Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md); era o mínimo para o primeiro mandato real (11/11/2026) |
| [`PLANO_DE_EXECUCAO_2026-11.md`](3%20Estado%20e%20Execução/PLANO_DE_EXECUCAO_2026-11.md) | **superado** (histórico): o mapa da aplicação completa, etapa por etapa |
| [`ARQUITETURA_ALVO_E_ROADMAP.md`](3%20Estado%20e%20Execução/ARQUITETURA_ALVO_E_ROADMAP.md) | a arquitetura-alvo: decisão por componente e camadas (referência técnica); **portões e fases superados** pelo plano único |
| [`COMO_O_SISTEMA_FUNCIONA.md`](3%20Estado%20e%20Execução/COMO_O_SISTEMA_FUNCIONA.md) | o fluxo inteiro em linguagem simples |
| [`MAPA_DE_EXECUCAO.md`](3%20Estado%20e%20Execução/MAPA_DE_EXECUCAO.md) | **superado** (histórico): quadro de blocos com critério de pronto (setembro a novembro de 2026) |
| [`PRONTIDAO_POR_ESTAGIO.md`](3%20Estado%20e%20Execução/PRONTIDAO_POR_ESTAGIO.md) | **superado** (histórico): o projeto medido contra o objetivo, estágio por estágio (20/08/2026) |
| [`PLANO_LINHA_A_LINHA.md`](3%20Estado%20e%20Execução/PLANO_LINHA_A_LINHA.md) | **superado** (histórico): plano para nenhuma linha faltar nem ser inventada na extração (absorvido nos itens 1.A5 e 1.A6) |
| [`DESENHO_QUATRO_FUNCOES_2026-11.md`](3%20Estado%20e%20Execução/DESENHO_QUATRO_FUNCOES_2026-11.md) | desenho técnico das quatro funções aprovadas em novembro (segue válido; ordem e data superadas) |
| [`DESENHO_LEITOR_TRANSACIONAL.md`](3%20Estado%20e%20Execução/DESENHO_LEITOR_TRANSACIONAL.md) | desenho do leitor transacional por código |
| [`DESENHO_P3_ROTEAR_POR_CASO_ID.md`](3%20Estado%20e%20Execução/DESENHO_P3_ROTEAR_POR_CASO_ID.md) | o envio roteado pelo `caso_id` |
| [`LINHA_DE_BASE_P4.md`](3%20Estado%20e%20Execução/LINHA_DE_BASE_P4.md) | a linha de base da leitura por IA (07/11/2026) |

## 4 Análises e Auditorias

Medições do sistema real, cada uma datada.

| Documento | Conteúdo |
|---|---|
| [`08_RISCOS.md`](4%20Análises%20e%20Auditorias/08_RISCOS.md) | riscos e falhas prováveis, com mitigação |
| [`AUDITORIA_PROFUNDA_2026-09-15.md`](4%20Análises%20e%20Auditorias/AUDITORIA_PROFUNDA_2026-09-15.md) | auditoria completa com o CI inteiro rodado antes de concluir; deu origem à arquitetura-alvo |
| [`DIAGNOSTICO_SISTEMA_2026-08-11.md`](4%20Análises%20e%20Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md) | diagnóstico de agosto |
| [`VISTORIA_P2.md`](4%20Análises%20e%20Auditorias/VISTORIA_P2.md) | o portal por papel (quem vê e altera o quê), medido em produção |
| [`CUSTO_IA.md`](4%20Análises%20e%20Auditorias/CUSTO_IA.md) | para onde vai o custo de IA e como reduzir sem perder qualidade |
| [`SONARCLOUD.md`](4%20Análises%20e%20Auditorias/SONARCLOUD.md) | como o SonarCloud está ligado, o que mede e o que não mede |

## 5 Prompts

Roteiros de trabalho para o desenvolvimento assistido por IA. Nenhum guarda estado. Ver o
[`README`](5%20Prompts/README.md) da pasta.

## 6 Referência

Material de consulta: o [`modelo-base.xlsx`](6%20Referência/modelo-base.xlsx) que o export
reconstrói e o seu [`mapa`](6%20Referência/MAPA_MODELO_BASE.md), a
[`conformidade`](6%20Referência/CONFORMIDADE.md) do export com ele, o
[`aceite`](6%20Referência/ACEITE.md) de um `.xlsx` exportado, o
[`teste de restauração`](6%20Referência/RESTAURACAO.md) do backup, o
[`passo a passo pós-rodada`](6%20Referência/POS_RODADA.md), o `onboarding.pdf` e a
[`apresentação de crédito`](6%20Referência/apresentacao-credito/README.md). Ver o
[`README`](6%20Referência/README.md) da pasta.

## 7 Marca

[`DESIGN.md`](7%20Marca/DESIGN.md) (design system do portal), [`PRODUCT.md`](7%20Marca/PRODUCT.md),
[`REDESENHO_DO_PORTAL.md`](7%20Marca/REDESENHO_DO_PORTAL.md) e as pranchas e o benchmark do
redesenho de novembro em [`redesenho-2026-11/`](7%20Marca/redesenho-2026-11/).
