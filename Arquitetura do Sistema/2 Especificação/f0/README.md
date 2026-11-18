# F0 — Fundação: kit de execução

Este diretório contém os **artefatos concretos da F0**, a fase que precede qualquer linha de
código. Nada aqui é implementação — é o que precisa estar **fechado com o time** para que a
construção do workflow (F1 em diante) não seja feita sobre premissas.

> **Regra de ouro (do plano de execução original, `09_PLANO_DE_EXECUCAO.md`, removido em 18/11/2026 e recuperável pelo histórico do git):** nada de código antes de
> taxonomia, modelo de status e schema conceitual fechados. A F0 existe para fechar isso.

## Como usar este kit

Cada arquivo tem um estado: **[DECISÃO]** (proposta minha, pronta para o time aprovar/editar),
**[PREENCHER]** (template que só o time pode completar com dados reais) ou **[DRAFT v0]**
(rascunho meu que acelera o time, para cortar/refinar).

| # | Artefato | Arquivo | Estado | Dono |
|---|---|---|---|---|
| 0.1 | Baseline quantitativo | `01_baseline_quantitativo.md` | ⏳ PARCIAL | Rodrigo Varoto |
| 0.2 | Decisão build-vs-buy + dono | `02_build_vs_buy.md` | ✅ DECISÃO REGISTRADA | Rodrigo Varoto |
| 0.3 | Taxonomia documental + checklist (Reestruturação) | `03_taxonomia_reestruturacao.md` | ✅ v1 | Rodrigo Varoto (dono único) |
| 0.4 | Modelo de status + pendências + regra do portão | `04_status_e_pendencias_spec.md` | ✅ APROVADO | Rodrigo Varoto |
| 0.5 | Schema conceitual + política LGPD | `05_schema_conceitual.md` | ✅ APROVADO | Rodrigo Varoto |
| 0.6 | Golden set + protocolo de medição | `06_golden_set_protocolo.md` | ✅ PROTOCOLO v1 (montagem = execução) | Rodrigo Varoto |
| 0.7 | Especificação do output para o analista | `07_output_spec.md` | ✅ DECISÃO v0 | Rodrigo Varoto |

## Ordem de execução (dependências e portões)

```
0.1 Baseline ─┐
0.2 Build/Buy ─┼─► decisão GO/NO-GO de construir ──┐
              │                                     │
0.3 Taxonomia (CAMINHO CRÍTICO) ───────────────────┼─► 0.5 Schema ─► 0.6 Golden set ─► GATE F0
              │                                     │        ▲
0.4 Status/Pendências ──────────────────────────────┘────────┘
```

- **0.1 + 0.2 primeiro.** Sem número e sem decisão de construir (e um dono nomeado), não se
  começa. Se o build-vs-buy apontar "buy", grande parte do resto muda de natureza.
- **0.3 é o caminho crítico.** É o trabalho mais difícil e mais político (analistas discordam
  sobre o que é obrigatório). Começa em paralelo com 0.1/0.2 e provavelmente é o que demora.
- **0.4 pode correr em paralelo** — é decisão de desenho, já proposta pronta neste kit.
- **0.5 depende de 0.3 e 0.4** (o schema materializa taxonomia + status).
- **0.6 depende de 0.3** (só se rotula contra uma taxonomia fechada).

## Critério de saída da F0 (GATE para F1)

A F0 está pronta para virar código quando **todos** forem verdade:

1. ⏳ Baseline quantitativo preenchido com números reais de casos passados. *(Parcial: seção A
   com dado real + estimativa; B–E pendentes de levantamento. Não bloqueia o esqueleto da F1,
   mas é pré-requisito da calibração — F4.)*
2. ✅ Decisão build-vs-buy registrada e assinada; **dono de operação nomeado** (Rodrigo).
3. ✅ Taxonomia + checklist de Reestruturação **v1** fechados (Kit Básico obrigatório +
   Variáveis complementares), critério "bom o suficiente para começar".
4. ✅ Máquina de status + tipos de pendência + regra do Portão 2 aprovados.
5. ✅ Schema conceitual revisado; sensibilidade LGPD mapeada por tipo de documento.
6. ✅ Golden set — **protocolo v1 fechado** (dimensionamento, métricas, rotulagem, laço de
   calibração). A **montagem física** do conjunto rotulado é tarefa de execução que roda em
   paralelo à F1 (começa com os casos disponíveis; não bloqueia o esqueleto).
7. ✅ **Output para o analista especificado** (`07_output_spec.md`) — schema-alvo definido.

**Situação (2026-07-14):** F0 **completa em design** — todas as decisões estruturais travadas.
Itens de execução que correm em paralelo à F1, **sem bloquear** o esqueleto (que nasce em
N0/N1): montagem física do **golden set (0.6)** e preenchimento do **baseline fino (0.1)**.

> **Gate F1 destravado.** Próximo passo: desenhar o plano técnico do **Walking Skeleton** —
> Supabase + N8N + Vercel, workflow inteiro ponta a ponta em N0/N1, 1 caso real do intake ao
> Portão 2. Ver `Arquitetura do Sistema/1 Visão e Doutrina/03_MVP_E_ROADMAP.md`.

## Depois da F0 (prévia da F1)

F1 = **walking skeleton**: o workflow inteiro conectado ponta a ponta, **todos os estágios em
N0/N1** (sombra/sugestão), 1 caso real atravessando do intake ao Portão 2. Sem autonomia
interpretativa. Só então F2 encorpa cada estágio. Ver `Arquitetura do Sistema/1 Visão e Doutrina/03_MVP_E_ROADMAP.md`.
