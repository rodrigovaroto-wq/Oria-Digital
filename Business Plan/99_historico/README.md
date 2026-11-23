# Histórico do planejamento do Oria Digital

Esta pasta guarda o que **já foi superado ou serviu de trabalho**. Nada aqui é fonte oficial: a fonte
de cada assunto está no [índice da pasta `Business Plan/`](../README.md). Os arquivos foram movidos
para cá na Fase 4 sem nenhuma alteração de conteúdo (commit "Business Plan 1/7").

## O que está aqui

| Pasta ou arquivo | O que é | Substituído por |
|---|---|---|
| [`registro_de_decisoes/`](registro_de_decisoes/) | Registro de decisões **v0.1.2** (18/11/2026) | v0.1.3, em [`07_decisoes/`](../07_decisoes/) |
| [`workflow/oria_digital_workflow_fixo_v0.1.html`](workflow/oria_digital_workflow_fixo_v0.1.html) | Workflow original, anterior às decisões | v0.3.0, em [`02_workflow_e_arquitetura/`](../02_workflow_e_arquitetura/) |
| [`workflow/oria_digital_workflow_atualizado_v0.2.0.html`](workflow/oria_digital_workflow_atualizado_v0.2.0.html) | Workflow v0.2.0 (aplica a v0.1.2; anterior à entrevista) | v0.3.0 |
| [`entrevista/oria_entrevista_lote_01..03.html`](entrevista/) | Transcrições literais dos lotes 01–03 (entrevista por voz) | Seção 19 do registro v0.1.3 |
| [`entrevista/02_lista_de_perguntas.md`](entrevista/02_lista_de_perguntas.md) | Roteiro original de 68 perguntas | — |
| [`entrevista/03_rascunho_adendo_v0.1.3.md`](entrevista/03_rascunho_adendo_v0.1.3.md) | Registro de trabalho pergunta a pergunta, com a fala exata do dono. **Útil em dúvida de interpretação** de uma decisão | Seção 19 do registro v0.1.3 |
| [`entrevista/prompts/`](entrevista/prompts/) | Prompts da entrevista por voz e o banco de perguntas restantes | — |
| [`business_plan_v2_fase3/`](business_plan_v2_fase3/README.md) | Rascunhos do deck v2, comparativos e os scripts `editar_*.py` que o produziram, na ordem | Deck oficial em [`Apresentações/`](../../Apresentações/Business%20Plan%20Oria%20Digital/) |
| [`prompts_de_fase/PROMPT_FASE_4.md`](prompts_de_fase/PROMPT_FASE_4.md) | O prompt que abriu a Fase 4 | — |
| [`README_trabalho_fase1.md`](README_trabalho_fase1.md) | O índice provisório da Fase 1, como estava. Os caminhos citados nele são os de antes da mudança | Este README |

Os caminhos antigos e os novos:

| Antes (até a Fase 3) | Agora |
|---|---|
| `_trabalho_fase1/registro_de_decisoes/…v0.1.3.html` e `gerar_v013.py` | `07_decisoes/` |
| `_trabalho_fase1/registro_de_decisoes/…v0.1.2.html` | `99_historico/registro_de_decisoes/` |
| `_trabalho_fase1/workflow/…v0.3.0.html` e `gerar_workflow_v030.py` | `02_workflow_e_arquitetura/` |
| `_trabalho_fase1/workflow/…v0.1.html` e `…v0.2.0.html` | `99_historico/workflow/` |
| `_trabalho_fase1/01_sintese_da_pesquisa.md` | `09_pesquisa/SINTESE_DA_PESQUISA_FASE1.md` |
| `_trabalho_fase1/02_…`, `03_…`, `entrevista/`, `prompts_entrevista/` | `99_historico/entrevista/` (prompts em `prompts/`) |
| `_trabalho_fase3/*` | `99_historico/business_plan_v2_fase3/` |
| `PROMPT_FASE_4.md` | `99_historico/prompts_de_fase/` |

## Planos de execução anteriores

O plano em vigor é o [`06_execucao/PLANO_DE_EXECUCAO.md`](../06_execucao/PLANO_DE_EXECUCAO.md) (K1). Os
anteriores continuam em `Arquitetura do Sistema/`, com uma nota "superado por" no topo, e são
histórico:

- `Arquitetura do Sistema/3 Estado e Execução/`: `PLANO_MVP_2026-11.md`, `PLANO_DE_EXECUCAO_2026-11.md`,
  `MAPA_DE_EXECUCAO.md`, `PRONTIDAO_POR_ESTAGIO.md`, `PLANO_LINHA_A_LINHA.md` e o roadmap de
  `ARQUITETURA_ALVO_E_ROADMAP.md` (as decisões por componente desse arquivo seguem como referência técnica).
- `Arquitetura do Sistema/1 Visão e Doutrina/03_MVP_E_ROADMAP.md`.

Dois planos já tinham sido apagados na organização do repositório (PR #302, commit `54418af`) e
continuam no git:

```bash
git show "54418af^:Arquitetura do Sistema/3 Estado e Execução/STATUS_POR_ETAPA_2026-11-11.md"
```

```bash
git show "54418af^:Arquitetura do Sistema/3 Estado e Execução/09_PLANO_DE_EXECUCAO.md"
```

O `STATUS_POR_ETAPA_2026-11-11.md` é o retrato das **111 etapas** (20 completas em 11/11/2026) que o
plano novo aproveita como inventário.

## Como regerar as versões HTML

Os geradores leem só os caminhos passados na linha de comando. Medido na Fase 4: regerados, os dois
arquivos saem idênticos byte a byte aos versionados.

```bash
python3 -I "Business Plan/07_decisoes/gerar_v013.py" "Business Plan/99_historico/registro_de_decisoes/oria_digital_decisoes_e_pendencias_v0.1.2.html" /tmp/v013.html
```

```bash
python3 -I "Business Plan/02_workflow_e_arquitetura/gerar_workflow_v030.py" /tmp/workflow_v030.html
```
