---
id: quadro-de-imobilizado-classificado-como-balanco
tipo: defeito
toca:
  - Supabase/migrations/0002_seed_taxonomia_e_dial.sql
  - N8N/build-workflow.mjs
---

**O que parecia (S126, 11/11/2026):** 2 pendências "sem período par" no Canastra sintético
(`ativo_passivo_pl` e `caixa_bp_fluxo`, anual 2025) que a 0234 não alcançou, com "outra causa,
não diagnosticada".

**O que era (S127, 11/11, leitura de produção):** classificação, não período. O documento é
`27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf`. A IA o gravou como `BALANCO`, e a
justificativa dela já dizia: "Embora não seja um balanço completo, é um demonstrativo
patrimonial". As únicas linhas "TOTAL" dele estão nas colunas Custo, Depreciação acumulada e
Valor líquido. As duas checagens tomam o quadro como balanço e não acham nenhum exercício.

**Medido:** o balanço verdadeiro da mesma entidade (`01_Balanco_Patrimonial_..._2025x2024x2023`,
307 linhas) dá `ativo_passivo_pl: ok`. A taxonomia tem 36 tipos (`taxonomia_tipo_documento`),
e nenhum é "composição do imobilizado". A IA não tinha onde pôr o quadro.

**Por que ficou sem correção:** criar o tipo muda a lista que o prompt de classificação e o
`extractionSchema` carregam. O `FINGERPRINT_EXTRACAO` (`N8N/build-workflow.mjs`) muda junto, e o
próximo envio de cada mandato re-extrai e paga todos os documentos. A decisão é do dono, e o
código é da Claude Oria 2 (`SYSTEM_PROMPT`).

**A lição:** antes de investigar uma "sem período par", leia o `tipo_taxonomia` e a
`justificativa` do documento. Se a própria IA diz "não é um balanço completo", o defeito é a
falta de um tipo, não o casamento de período.
