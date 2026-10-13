# Arquitetura-alvo e roadmap — evolução para plataforma de inteligência financeira

**Data:** 15/09/2026 · **Base:** `main` em `de556c2` · **Origem:** derivado da
`Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_PROFUNDA_2026-09-15.md`, cujos números
foram medidos nesta árvore.

**Princípio central:** não é um projeto novo. É a **evolução do sistema existente** até que ele
opere como plataforma profissional de inteligência financeira para M&A e reestruturação. Nada do
que funciona é descartado.

> **A base andou enquanto este arquivo era escrito.** Ele nasceu sobre `de556c2`; o `main` passou a
> `f230cff` com `0175`–`0177` antes do merge. Os números da F0 abaixo já estão corrigidos para isso.
> **A lição é do próprio roadmap:** a defasagem contra produção não é um número deste arquivo — é o
> que a sonda responde, e ela cresce a cada rodada que fecha sem aplicar. É por isso que a F0 é
> primeira e que a fatia 0.1 mede antes de corrigir.

**Este arquivo não implementa nada.** Ele decide o desenho, a ordem e os critérios objetivos de
passagem. A execução começa pela F0, cujo plano está na §9.

---

## 1. Decisão por componente existente

Legenda: KEEP · REFACTOR · REBUILD · EXTEND · DEPRECATE · REMOVE · MISSING

### 1.1 Banco / domínio

| Componente | Decisão | Justificativa |
|---|---|---|
| `campo_extraido` | **KEEP + REFACTOR de papel** | Não migrar, não reescrever. **Promover a camada de evidência imutável**. O fato canônico nasce ACIMA dela. Assim nada quebra e as 10 reconciliações migram uma a uma |
| `entidade` + `fn_cnpj_*`, `fn_fundir_entidade`, `0169`–`0174` | **KEEP + EXTEND** | 80% do trabalho de identidade já foi feito e pago caro (6 migrations, um crash em produção). Falta FK no fato, papel societário tipado, participação |
| `periodo` | **REFACTOR** | Sem semana; `periodo_coluna` carrega dois conceitos. Precisa de `granularidade`, `data_inicio`, `data_fim` |
| `secao_canonica` (16 valores) | **KEEP + EXTEND** | Certo como seção de demonstração. Nunca foi plano de contas e não deve virar um: fica como atributo da conta canônica |
| **Plano de contas canônico** | **MISSING** | A ausência central |
| `classe_contabil_catalogo` (5 de recorrência) | **KEEP, novo papel** | É normalização de EBITDA e é exatamente o que valuation precisa. Vira atributo da conta canônica |
| `taxonomia_tipo_documento` (36) | **KEEP** | Ontologia excelente e já alinhada ao alvo. Não tocar |
| `taxonomia_linha_exigida` (14 linhas, 6 tipos vivos) | **EXTEND (agressivamente)** | 27 tipos ingeridos sem exigência = 27 formas de o dado sumir sem o placar mudar |
| `taxonomia_linha_localizador` (46) | **KEEP + EXTEND** | Mecanismo bom, cobertura estreita |
| As 3 exigências `origem='proposta'` | **EXTEND (promover a `codigo`)** | São o insumo da eliminação intragrupo, declaradas mortas há meses |
| `reconciliacao` + 10 `fn_reconciliar_*` | **KEEP** | Melhor ativo do sistema. Ganha FK real e fica melhor |
| `pendencia` | **KEEP** | É o mecanismo de "inconsistência explícita". Pronto |
| `evento_auditoria` + `decisao` | **KEEP + EXTEND** | Falta registrar LEITURA, não só decisão |
| `estagio_autonomia` + `fn_mudar_dial` | **KEEP** | Autonomia graduada é rara e correta |
| `golden_*` (7 tabelas, 16 funções) | **REFACTOR** | Trocar a fonte de rótulo para `fn_veredito_producao`, mantendo as tabelas |
| `documento_fato` + 9 tipos de fato | **KEEP + EXTEND** | Semente do Diagnóstico, com trecho literal obrigatório. Subutilizado |
| `checklist_item_status` | **KEEP + EXTEND** | **Já é a matriz de perímetro** — a camada existe em 70% |
| `caso_pergunta` + `pergunta_catalogo` | **KEEP** | Human-in-the-loop estruturado |
| `premissa_catalogo` (89, 7 fórmulas) | **KEEP — é o ISA do motor** | O conjunto de instruções do motor já está catalogado e versionado |
| `caso_premissa`, `caso_linha_premissa` | **REFACTOR** | Ligam por `rotulo_norm` texto e não têm cenário |
| `caso_modelagem` | **REFACTOR** | Uma por caso, sem versão nem cenário |
| `indice_macro_*` + workflow macro | **KEEP** | Pronto |
| `instalacao_requisito` / `fn_instalacao_conferir` | **KEEP + REFACTOR** | Precisa do par externo rodando contra PRODUÇÃO |
| RLS (47 policies `USING (true)`) | **REFACTOR (adiado)** | Correto para ferramenta interna; bloqueante como plataforma. Não é da F0 |

### 1.2 n8n

| Componente | Decisão | Justificativa |
|---|---|---|
| `workflow.e1-ingestao` (40 nós) | **KEEP + EXTEND** | Funciona. Ganha nós para os tipos hoje mudos |
| 17 libs (543 testes) | **KEEP** | Encapsulam aprendizado de produção caro |
| Duplicação inline + `espelho-inline.test.mjs` | **KEEP** | Imposta pela plataforma, contida por equivalência comportamental. Dívida MITIGADA |
| 4 geradores + `git diff --exit-code` | **KEEP** | Padrão correto de derivado versionado |
| Republicação manual | **REFACTOR — urgente** | Defasada desde 02/09; memória registra perda de toggles |
| `macro`, `erros`, `diagnostico-ia` | **KEEP** | |
| `medir-fase0-denominador.mjs` | **REMOVE ou adotar** | Órfão: fora do CI e do `CLAUDE.md` |

### 1.3 Portal / export

| Componente | Decisão | Justificativa |
|---|---|---|
| Telas | **KEEP** | `tsc`/`eslint` limpos, 7 suítes verdes |
| `export.ts` (3.482) — modo dados | **KEEP** | 721 verificações, proveniência por célula |
| `modelo-institucional.ts` (6.689) | **REFACTOR profundo → vira emissor** | Não é motor; é gerador de planilha que É o modelo. A fidelidade ao Modelo Base é ativo e fica |
| `export-modelagem.ts` (2.340) | **REFACTOR** | Mesma razão |
| `avaliar-formula.mts` (630) | **KEEP → promover a portão de migração** | Prova célula a célula que o motor novo reproduz o Excel antes de trocar a fonte |
| `statement-templates.ts` | **KEEP + REFACTOR** | Passa a ler a conta canônica |
| `limite-de-envio.ts` | **KEEP** | Nasceu de HTTP 413 real |
| `/api/intake` | **KEEP (revisitar depois)** | Acoplamento deliberado e documentado |

### 1.4 Testes, CI, conhecimento, agentes

| Componente | Decisão | Justificativa |
|---|---|---|
| 26 portões / 13,9k SQL / 10,8k scripts | **KEEP — viabiliza tudo** | A regra 2 é o que torna esta cirurgia segura |
| 2 books + geradores sob `git diff` | **KEEP + EXTEND** | Falta um terceiro: **distress** (PL negativo, covenant rompido, aging, extrato) |
| Arnês de variações (25) | **KEEP + EXTEND** | Achou 5 defeitos que nenhuma outra suíte pega |
| CI (28 passos) | **KEEP + EXTEND** | Falta aplicar migration, conferir n8n publicado, Sonar Quality Gate |
| `.claude/conhecimento` | **KEEP** | Infraestrutura de sessão genuinamente boa |
| 7 agentes do projeto | **KEEP + EXTEND** | Faltam **`motor-financeiro`** e **`ontologia-contabil`** |
| 30 agentes `importado.*` + 52 comandos | **FEITO em 16/09/2026** | Removidos juntos; 7 agentes e 3 comandos escritos aqui. Procedência em `.claude/COMANDOS.md` |
| `ESTADO.md` + `HANDOFF.md` (11.587 linhas) | **REFACTOR** | Cabeçalho curto sob portão; histórico particionado |
| `PRONTIDAO_POR_ESTAGIO.md` | **REBUILD** | 35 sessões atrasado. Regerar do banco e do CI, não à mão |
| `00_VISAO_E_ESCOPO.md` | **REBUILD** | Declara escopo negativo que o próprio código já ultrapassou |

### 1.5 O que remover

~~Os 52 comandos importados + 30 agentes `importado.*`~~ — **removidos em 16/09/2026**;
`medir-fase0-denominador.mjs` se não for adotado. **Nada mais.** Não há código morto relevante: o que parece morto está DECLARADO como
não-lido, o que é honestidade, não lixo.

### 1.6 MISSING (novo de verdade)

`conta_canonica` · `fato_financeiro` · `lineage_aresta` · `cenario` · **motor de cálculo** ·
`instrumento_divida` · `credor` · `garantia` · `alavanca` · valuation · camada de apresentação ·
PPT · conversão cambial · granularidade semanal.

---

## 2. As 23 camadas, estágio real

🟢 pronto · 🟡 parcial · 🟠 embrionário · 🔴 ausente

| # | Camada | Estágio | Evidência | Decisão |
|---|---|---|---|---|
| 1 | Document/Data Ingestion | 🟢 80% | 40 nós, 4 formatos, fatiamento, orçamento por documento, fingerprint, guarda de 413 | KEEP+EXTEND |
| 2 | Extraction | 🟡 70% | schema forte, 543 testes; N2 `declarada`; 39% de falha na rodada de 190 | KEEP+EXTEND |
| 3 | Normalization | 🟡 60% | escala ✅; moeda sem FX; período sobrecarregado | REFACTOR |
| 4 | Classification | 🟠 30% | 16 seções + string; 5 classes de recorrência; dial N0 | REBUILD parcial |
| 5 | **Canonical Financial Data** | 🔴 15% | sem FK, sem `conta_id`, sem hierarquia | **REBUILD acima do existente** |
| 6 | Entity/Perimeter | 🟡 55% | `entidade`+CNPJ; **`checklist_item_status` já é a matriz** | KEEP+EXTEND |
| 7 | Provenance/Lineage | 🟡 50% | por (rótulo, seção, ano) — `0125` — mas como NOTA de célula; morre na projeção | EXTEND |
| 8 | Validation/Reconciliation | 🟢 75% | 10 funções com materialidade e precondições | KEEP+EXTEND |
| 9 | Financial Analysis / Diagnóstico | 🟠 20% | `documento_fato` + 9 fatos; `fn_diagnostico_modelagem` é de extração | EXTEND |
| 10 | Liquidity/Working Capital | 🟠 15% | `dias_de_giro` anual no Excel; **zero** 13-week/aging/extrato | MISSING (maior parte) |
| 11 | Forecast | 🟡 45% | 89 premissas, 7 fórmulas; projeção no Excel | REFACTOR |
| 12 | Integrated Financial Model | 🟡 50% | 14 abas, circularidade cortada e declarada; fora do sistema | REFACTOR→motor |
| 13 | Capital Structure | 🟠 25% | `MAPA_DIVIDA`, revolver no Excel; sem instrumento/garantia/covenant como dado | EXTEND |
| 14 | Operational Turnaround | 🔴 0% | — | **questionado — §4.3** |
| 15 | Restructuring Strategy | 🔴 5% | `haircut` só como parâmetro do Stress | MISSING |
| 16 | Valuation | 🔴 0% | 0 em código | MISSING |
| 17 | Creditor/Recovery | 🔴 0% | `credor` só como rótulo | MISSING |
| 18 | Scenario Engine | 🔴 10% | zero `cenario` no schema | MISSING |
| 19 | Stress/Red Team | 🟡 40% (em forma melhor) | 25 variantes + regra 2 + `revisor-defeito-silencioso` | **reenquadrar — §4.4** |
| 20 | Presentation Data Layer | 🔴 0% | — | MISSING |
| 21 | PPT Generation | 🔴 0% | — | MISSING |
| 22 | Governance/Audit | 🟢 70% | `evento_auditoria` append-only, `decisao`, dial, `lote_execucao` | KEEP+EXTEND |
| 23 | AI/Agent Orchestration | 🟡 60% | 7 agentes, conhecimento com grafo; frágil operacionalmente | KEEP+EXTEND |

**Em uma frase:** 1, 8 e 22 prontas; 2, 3, 6, 7, 11, 12, 19 a meio caminho; **a 5 é o buraco que
segura tudo**; 14–18, 20, 21 não existem.

---

## 3. FINAL ARCHITECTURE

```
╔══════════════════════════════════════════════════════════════════════════╗
║  L0  INGESTÃO                                            [KEEP+EXTEND]   ║
║      n8n e1-ingestao (40 nós) · 4 formatos · fatiamento · orçamento      ║
║      fingerprint · guarda de 413 · 17 libs / 543 testes                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L1  EVIDÊNCIA  (append-only, IMUTÁVEL)                [KEEP, novo papel]║
║      campo_extraido COMO ESTÁ + documento_fato + documento_versao        ║
║      rótulo como veio · página · confiança · aceite · moeda · unidade    ║
║      >>> esta camada não muda. Ela É a prova. <<<                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L2  RESOLUÇÃO  (estágio EXPLÍCITO, sob dial)                    [NOVO]  ║
║      evidência --> identidade: conta_id · entidade_id · periodo_id       ║
║                                pai_id · versao/restatement · moeda       ║
║      método ∈ {exata, catálogo, humana, heurística+pendência}            ║
║      >>> não resolveu => PENDÊNCIA. Nunca palpite silencioso. <<<        ║
║      reaproveita: fn_normalizar_texto, fn_radicais_rotulo, fn_cnpj_*,    ║
║                   fn_entidade_canonica, fn_periodo_canonico, o dial      ║
╠══════════════════════════════════════════════════════════════════════════╣
║  L3  CANONICAL FINANCIAL DATA                                    [NOVO]  ║
║      conta_canonica (plano de contas + secao_canonica + classe recorr.)  ║
║      fato_financeiro(conta, entidade, periodo, cenario, versao,          ║
║                      moeda, valor, evidencia_id[])                       ║
║      perimetro / consolidacao · eliminacao_intragrupo como FATO próprio  ║
║      lineage_aresta(origem -> transformação -> destino)  <-- L7 vive aqui║
╠══════════════════════════════════════════════════════════════════════════╣
║  L4  RECONCILIAÇÃO                                       [KEEP+EXTEND]   ║
║      as 10 fn_reconciliar_* de hoje, agora sobre FK real                 ║
║      + intercompany (MUTUOS/FAT_INTRAGRUPO promovidos) + consolidação    ║
╠═══════════════════════════ DATA GATE ════════════════════════════════════╣
║  L5  MOTOR DE CÁLCULO                             [NOVO — a peça-chave]  ║
║      interpretador sobre as 7 formas de premissa_catalogo:               ║
║        indice_macro · crescimento_composto · pct_de_linha · dias_de_giro ║
║        valor_por_ano · preco_x_volume · curva_mensal                     ║
║      grafo de dependências · resolve circularidade por iteração          ║
║      cenário e alavanca são PARÂMETRO · toda saída carrega lineage       ║
║      >>> fonte única da verdade aritmética do sistema <<<                ║
╠═══════════════════════════ MODEL GATE ═══════════════════════════════════╣
║  L6  CENÁRIOS E ALAVANCAS                                        [NOVO]  ║
║      cenario(id, caso, nome, base_de, autor, motivo)                     ║
║      alavanca(tipo, params, alvo, categoria ∈ {financeira, operacional}) ║
║      >>> "turnaround operacional" = categoria de alavanca, não camada <<<║
╠══════════════════════════ STRATEGY GATE ═════════════════════════════════╣
║  L7  ANÁLISE  (tudo CONSULTA o motor — nada recalcula)                   ║
║   ┌────────────────┬──────────────────┬────────────────────────────────┐ ║
║   │ Diagnóstico    │ Capital Structure│ Liquidez / 13-week             │ ║
║   │ (documento_fato│ instrumento_div. │ AGING_AP/AR · EXTRATO_BANCARIO │ ║
║   │  + índices)    │ credor·garantia  │ granularidade SEMANAL (nova)   │ ║
║   ├────────────────┼──────────────────┴────────────────────────────────┤ ║
║   │ Valuation      │ Recovery / Waterfall  (prioridade Lei 11.101)     │ ║
║   └────────────────┴───────────────────────────────────────────────────┘ ║
╠══════════════════════════ CREDITOR GATE ═════════════════════════════════╣
║  L8  PRESENTATION DATA LAYER   > é uma PROJEÇÃO, não uma camada < [NOVO] ║
║      sem estado · sem aritmética · regenerável · todo nº com fato_id     ║
╠════════════════════════ PRESENTATION GATE ═══════════════════════════════╣
║  L9  SAÍDAS                                                              ║
║      Excel (fórmula VIVA, como hoje — modelo-institucional vira emissor) ║
║      PPT · PDF · API      >>> nenhuma calcula nada <<<                   ║
╚══════════════════════════════════════════════════════════════════════════╝
   TRANSVERSAL — L10 GOVERNANÇA  [KEEP+EXTEND]
     evento_auditoria · decisao · pendencia · estagio_autonomia · dial
     lote_execucao (custo/cobertura) · fn_operacao_* · golden->veredito_producao
   TRANSVERSAL — L11 ORQUESTRAÇÃO IA/AGENTES  [KEEP+EXTEND]
     provedor.mjs · 7 agentes (+2: motor-financeiro, ontologia-contabil)
     .claude/conhecimento (grafo derivado + âncoras) · 26 portões · CI
```

**A restrição que sustenta o desenho:** L1–L4 respondem *"o que é verdade"*; L5 responde *"o que
acontece se"*; L7–L9 **só perguntam**. Nenhuma camada acima de L5 tem aritmética própria — e isso é
verificável por portão estático, não por disciplina.

---

## 4. Onde este documento discorda do desenho proposto

### 4.1 A ordem das fases estava invertida no começo

A proposta original punha Extração → Normalização/Classificação → Lineage/Reconciliação →
**Entidades/Perímetros**. A auditoria diz o contrário: **extração é o componente mais maduro** e
**reconciliação já funciona**. O que trava é identidade. E identidade de ENTIDADE vem antes da de
CONTA, porque (a) já está 80% pronta, (b) o perímetro define quais contas precisam existir, (c) sem
entidade no fato, o plano de contas não tem onde pousar num COMBINADO.

**Entidade/perímetro sobe para F1. Lineage é subproduto de F4, não fase autônoma.**

### 4.2 13-week cash flow não é fase de modelagem

Vem de **extrato bancário, aging de AP/AR, folha, calendário tributário e cronograma de dívida**, em
granularidade **semanal**, que não existe no sistema. É o insumo mais sujo que existe.

**Partir em duas:** a parte de DADOS (`AGING_AP`, `AGING_AR`, `EXTRATO_BANCARIO` — tipos que a
taxonomia já tem) entra cedo, na F2. A projeção semanal entra depois do motor. Juntas, produzem um
13-week bonito e falso.

### 4.3 "Operational Turnaround" como camada é um erro

É a camada menos orientada a dados da lista. Um motor de turnaround seria ou uma lista de
iniciativas com campos livres (CRM, não inteligência financeira) ou um modelo de operações sem dados
para alimentá-lo (não há headcount por função, capacidade, mix, margem por SKU).

**Eliminada como camada.** Turnaround operacional é um conjunto de **alavancas no motor de
cenários**, idênticas às financeiras. A diferença é o campo `categoria`, não a arquitetura. Remove
uma fase inteira sem perder nada.

### 4.4 "Stress/Red Team" deve ser reenquadrado, não construído

O repositório já tem o melhor red team disponível — e ele é de ENGENHARIA: 25 variantes de documento
sujo, a regra 2, o `revisor-defeito-silencioso`, a regra 7. O que falta é **aplicá-lo ao modelo**:
invariantes econômicos que reprovem um modelo absurdo (giro agregado impossível, margem fora de
faixa, dívida que amortiza sem caixa).

**Deixa de ser camada e vira o MODEL GATE + STRATEGY GATE.** Stress de cenário (choque de receita,
juros, câmbio) é só mais um cenário.

### 4.5 Valuation antes de recovery, e os dois depois de capital structure

Recovery DEPENDE de valuation e de estrutura de capital com prioridade e garantia. Ordem correta:
capital structure → valuation → recovery. E os três dependem do motor, não do diagnóstico.

### 4.6 O que se mantém sem ressalva

Os 10 princípios e as camadas 1–13, 15–18, 20–23. **O Princípio 8 é o mais importante dos dez** — é
ele que, transformado em restrição estrutural (P1 do PRESENTATION GATE), impede o desfecho que este
projeto já viveu uma vez com o Excel.

---

## 5. GATES

### DATA GATE — "o dado é confiável" · fecha em F6

| # | Critério | Medição |
|---|---|---|
| D1 | Repositório == produção | `fn_instalacao_conferir()` **contra produção** = 0 ausentes E `conferir-chamadas.mjs` verde contra produção E hash do workflow publicado == gerado |
| D2 | Todo fato tem identidade | `count(*) from fato_financeiro where conta_id is null or entidade_id is null or periodo_id is null` = **0** |
| D3 | Resolução nunca adivinha | 100% com `resolucao_metodo` ∈ {exata, catálogo, humana}; `heuristica` só com pendência aberta |
| D4 | Hierarquia bem-formada | todo `pai_id` fecha: Σ folhas == subtotal, ou divergência declarada; 0 ciclos |
| D5 | Ausência ≠ zero | suíte de regressão do Princípio 3 verde |
| D6 | Cobertura de tipos | todo tipo com documento ingerido tem ≥1 exigência VIVA ou está declarado `SEM_CONSUMIDOR` com motivo |
| D7 | Concordância medida | `estagio_autonomia.medicao_rodada_id` não nulo para todo estágio em N2 |
| D8 | Reconciliação fecha | Classe A sem divergência material aberta, ou pendência com dono |

**Sem D1–D4, nenhuma camada acima de L4 deve ser construída.**

### MODEL GATE — "a aritmética é auditável" · fecha em F7

| # | Critério |
|---|---|
| M1 | Motor reproduz **célula a célula** o `.xlsx` atual via `avaliar-formula.mts`, tolerância 0,01, nos dois books + caso real |
| M2 | Ativo − (Passivo+PL) = 0 em todo exercício, todo cenário, toda entidade |
| M3 | Δcaixa BP == caixa do DFC, todo período |
| M4 | 0 linhas projetadas sem `premissa_id` vinculada |
| M5 | Guarda de giro agregado: Σ dias ponderados ≤ limiar, senão pendência (**hoje 1.200 dias na fixture**) |
| M6 | Circularidade resolvida em ≤N iterações **ou** o corte está declarado na saída |
| M7 | Lineage completo: todo número projetado responde por SQL origem→transformação→premissa→utilização |
| M8 | Determinismo: mesma entrada ⇒ mesmo `.xlsx` byte a byte |

### STRATEGY GATE — "cenário e alavanca são dados" · fecha em F8

| # | Critério |
|---|---|
| S1 | Cenário é linha em tabela, versionado, com autor e motivo. **0 cenários hardcoded** |
| S2 | Cada cenário reprova M2–M4 por conta própria |
| S3 | Alavanca é dado (`tipo`, `parâmetros`, `alvo`), nunca ramo de código |
| S4 | Toda alavanca é reversível e diffável contra o Base |
| S5 | Comparação entre cenários sai do motor, nunca de recálculo em outra camada |

### CREDITOR GATE — "a recuperação é defensável" · fecha em F13

| # | Critério |
|---|---|
| C1 | Todo passivo financeiro é `instrumento_divida` com credor, garantia, prioridade e vencimento |
| C2 | Σ instrumentos == dívida do BP, ou divergência declarada com materialidade |
| C3 | Waterfall respeita prioridade legal (Lei 11.101), com a regra citável linha a linha |
| C4 | Σ recuperação por classe ≤ valor distribuível — **invariante duro** |
| C5 | Recovery rate reconciliado contra o valuation que o gerou |

### PRESENTATION GATE — "a apresentação não tem números próprios" · fecha em F15

| # | Critério |
|---|---|
| P1 | **0 aritmética fora do motor** — portão ESTÁTICO sobre a camada de apresentação |
| P2 | Todo número no deck tem `fato_id` ou `resultado_id` rastreável |
| P3 | Regenerar o deck do mesmo cenário dá o mesmo deck |
| P4 | Número no PPT == número no Excel == número no banco, conferido por suíte |
| P5 | Trocar uma premissa e regenerar move o deck inteiro |

---

## 6. DEPENDENCY GRAPH

```
                        ┌──────────────────────┐
                        │ F0 FUNDAÇÃO          │  fecha o fosso repo<->produção
                        │ deploy · escopo · ADR│  >> TUDO depende disto <<
                        └──────────┬───────────┘
          ┌────────────────────────┼────────────────────────┐
          v                        v                        v
   ┌─────────────┐         ┌──────────────┐         ┌──────────────┐
   │ F1 ENTIDADE │         │ F2 COBERTURA │         │ F3 EXTRAÇÃO  │
   │  PERÍMETRO  │         │   DE TIPOS   │         │ ESTABILIDADE │
   └──────┬──────┘         └──────┬───────┘         └──────┬───────┘
          └───────────┬───────────┘                        │
                      v                                    │
            ┌───────────────────┐                          │
            │ F4 CONTA CANÔNICA │ <-- intervenção central   │
            │  + HIERARQUIA     │                          │
            │  + RESOLUÇÃO (L2) │                          │
            └─────────┬─────────┘                          │
                      v                                    │
            ┌───────────────────┐                          │
            │ F5 LINEAGE        │ (subproduto de F4)       │
            └─────────┬─────────┘                          │
                      v                                    │
            ┌───────────────────┐                          │
            │ F6 RECONCILIAÇÃO  │ <────────────────────────┘
            │ + intercompany    │
            └─────────┬─────────┘
                ══ DATA GATE ══
                      v
            ┌───────────────────┐
            │ F7 MOTOR DE       │ <-- segunda intervenção central
            │    CÁLCULO        │
            └─────────┬─────────┘
                ══ MODEL GATE ══
          ┌───────────┼───────────┐
          v           v           v
   ┌──────────┐ ┌──────────┐ ┌──────────┐
   │ F8       │ │ F9       │ │ F10      │
   │ CENÁRIOS │ │ CAPITAL  │ │ LIQUIDEZ │  <- paralelizáveis
   │ ALAVANCAS│ │ STRUCTURE│ │ 13-WEEK  │
   └────┬─────┘ └────┬─────┘ └────┬─────┘
        │  ══ STRATEGY GATE ══    │
        └────────────┼────────────┘
                     v
        ┌───────────────────┐
        │ F11 DIAGNÓSTICO   │ (o factual sai já em F2)
        │     ANALÍTICO     │
        └─────────┬─────────┘
                  v
        ┌───────────────────┐      ┌───────────────────┐
        │ F12 VALUATION     │─────>│ F13 RECOVERY      │
        └───────────────────┘      │     WATERFALL     │
                                   └─────────┬─────────┘
                              ══ CREDITOR GATE ══
                                             v
                                   ┌───────────────────┐
                                   │ F14 RESTRUCTURING │
                                   └─────────┬─────────┘
                                             v
                                   ┌───────────────────┐
                                   │ F15 PRESENTATION  │
                                   │     DATA LAYER    │
                                   └─────────┬─────────┘
                            ══ PRESENTATION GATE ══
                                             v
                                   ┌───────────────────┐
                                   │ F16 PPT           │
                                   └───────────────────┘

   ┌──────────────────────────────────────────────────┐
   │ F17 HARDENING — CONTÍNUO, não uma fase final     │
   │ RLS · restauração · Sonar gate · proteção do main│
   └──────────────────────────────────────────────────┘
```

---

## 7. PHASE ROADMAP

Mapeamento contra a numeração originalmente proposta: F0→F0 · F1→F3 · F2→F4 · F3→F5+F6 ·
**F4→F1 (sobe)** · F5→F11 (+factual em F2) · F6→F10 (partida em dois) · F7→F7 · F8→F9 ·
**F9→eliminada (vira categoria de alavanca)** · F10→F12+F13 · F11→F8 · F12→F14 · F13→F15 ·
F14→F16 · F15→F17 (contínua).

> **Esforço:** P ≤ 1 rodada · M = 2–3 · G = 4–6 · GG > 6. Ordens de grandeza para sequenciar, não
> estimativas de prazo.

> **A passagem entre duas fases tem prompt próprio:** `5 Prompts/05-gate-de-fase.md`. Ele cobra, na
> ENTRADA, de quem a fase depende e o que ela custa em rodada paga — as duas coisas que, descobertas
> no meio, já pararam a linha por horas; e na SAÍDA, os seis veredictos com evidência. As tabelas
> abaixo trazem `Dono` e `Custo` só onde eles existem: campo vazio não se escreve.

### F0 — FUNDAÇÃO: fechar o fosso e decidir o escopo

| | |
|---|---|
| **Objetivo** | Que o sistema testado e o sistema em operação sejam o mesmo, e que o escopo pare de se contradizer |
| **Estado atual** | Repo **`0177`** (a base andou de `de556c2` para `f230cff` enquanto este plano era escrito: `0175`–`0177`), produção `0157`(+`0160`) · n8n de 02/09 · provedor divergente · `00_VISAO_E_ESCOPO` nega modelagem |
| **Gap** | **20 migrations** (era 17 em `de556c2`; o número é da sonda, não deste arquivo — ver a fatia 0.1), 1 republicação, 1 decisão de produto, 3 portões novos |
| **Dependências** | nenhuma |
| **Arquivos** | `.github/workflows/suites.yml` · `N8N/republicar.sh` · `preparar-republicacao.mjs` · `conferir-publicado.mjs` · `CLAUDE.md` · `00_VISAO_E_ESCOPO.md` · `PRONTIDAO_POR_ESTAGIO.md` |
| **Banco** | aplicar `0158`–`0177`; tabela de versão aplicada |
| **Workflows** | republicar os 4; portão de hash publicado × gerado |
| **Agentes** | `explorador`, `migrations-postgres`, `n8n-workflow`, `suites-invariantes`, `estado-e-handoff` |
| **Testes** | sonda contra PRODUÇÃO = 0 ausentes; `conferir-chamadas.mjs` contra produção; espelho `CLAUDE.md`×CI generalizado |
| **Risco** | Baixo técnico / **alto se não for feito** |
| **Impacto** | **Máximo** — sem ela nenhuma medição posterior significa nada |
| **Esforço** | **P** |
| **Entrada** | — |
| **Saída** | D1 verde |
| **Aceite** | sonda zero em produção; hash publicado == gerado; `PRONTIDAO` regerado automaticamente |
| **Decisão do dono (22/09/2026)** | F2.3 (checagem de FAT_INTRAGRUPO) VALE e é a próxima fatia após o apply; o aceite financeiro fica NÃO VERIFICADO até a F3 começar |
| **Aceite financeiro** | reprocessar os 75 documentos sem linha da rodada "Teste 00" e obter ≥95% com linha |
| **Aceite técnico** | CI aplica migration e falha se produção divergir; espelho cobre TODAS as categorias de portão; cada portão novo medido não-vazio |

### F1 — ENTIDADE E PERÍMETRO

| | |
|---|---|
| **Objetivo** | Entidade com identidade forte e perímetro explícito |
| **Estado** | 🟡 55% — `entidade`+CNPJ, `fn_fundir_entidade`, `checklist_item_status` |
| **Gap** | participação societária, papel tipado, escopo de consolidação, FK preparada |
| **Dep.** | F0 |
| **Banco** | `entidade.participacao`, `papel_no_grupo` enum, `perimetro(caso, entidade, escopo, desde, ate)` |
| **Testes** | estender `cnpj_identidade.test.sql`, `entidade_ambigua.test.sql`; novo `perimetro.test.sql` |
| **Risco** | Médio — mexe em código que já crashou em produção |
| **Impacto** | Alto — destrava consolidação e intercompany · **Esforço** M |
| **Saída** | toda entidade com papel e escopo; 0 `entidade_ambigua` não resolvida |
| **Aceite financeiro** | perímetro reproduz o COMBINADO do cliente, ou declara a diferença |
| **Dono** | o COMBINADO do cliente contra o qual o perímetro é conferido — sem ele o aceite financeiro não fecha |

### F2 — COBERTURA DE TIPOS: dar consumidor aos 27 tipos mudos

| | |
|---|---|
| **Objetivo** | Que nenhum tipo seja ingerido sem que alguém confira se o conteúdo chegou |
| **Estado** | 🟢 **D6 VERDE EM PRODUÇÃO desde 22/09/2026** (`0186`→`0187`→`0188` aplicadas; `fn_cobertura_de_tipos()` em produção: 6 exigência viva + 2 consumidor nomeado + 28 declarados, 0 ruins). Falta a F2.3 (decisão do dono: vale, próxima fatia); aceite financeiro espera a F3. Censo D6 medido contra produção em 22/09/2026: **24 tipos com documento**, **6 com exigência viva** (lida por alguma checagem: BALANCO, DRE, COMBINADO, FATURAMENTO_24M, MAPA_DIVIDA, FLUXO_CAIXA), **18 sem**. `0187` responde D6 por DECLARAÇÃO (`taxonomia_tipo_cobertura` + `fn_cobertura_de_tipos()`), não por exigência lexical nova — a `0185` (nove exigências itemizadas) foi DESCARTADA do repositório, nunca aplicada. **Migrations `0186`→`0187`→`0188` PRONTAS, TESTADAS e — a `0186` — MEDIDAS e LIBERADAS contra produção (22/09/2026), mas nenhuma aplicada**: a aplicação foi RECUSADA duas vezes pelo classificador de permissão do auto mode, mesmo com autorização do dono no chat |
| **Gap** | aplicar `0186`→`0187`→`0188` em produção e rodar `fn_cobertura_de_tipos()`; F2.2 (MAPA_DIVIDA fino) e F2.3 (consumidor real para FAT_INTRAGRUPO/CONTRATO_SOCIAL) medidas mas não construídas |
| **Dep.** | F0 |
| **Agentes** | `migrations-postgres`, `n8n-workflow`, **`ontologia-contabil`** (novo) |
| **Testes** | `cobertura_de_tipos.test.sql` (27 asserts, `0187`) · `motivo_especifico.test.sql` (28 asserts, `0188`) · **terceiro book: distress** (`book-distress`, F2.4) |
| **Risco** | Baixo — aditivo · **Impacto** Alto e subestimado · **Esforço** M |
| **Saída** | D6 verde EM PRODUÇÃO — ✅ atingido em 22/09/2026 |
| **Aceite financeiro** | mandato sem aging/extrato **não** é declarado pronto — **NÃO VERIFICADO** (ver linha "Aceite" abaixo) |
| | |
| **D6 medido em produção (22/09/2026)** | 24 tipos com documento, 6 com exigência viva (BALANCO, DRE, COMBINADO, FATURAMENTO_24M, MAPA_DIVIDA, FLUXO_CAIXA), 18 sem. `fn_cobertura_de_tipos()` (`0187`) responde D6 de forma ESTRITA sobre todos os tipos ativos, vereditos `SEM_COBERTURA`/`DECLARACAO_QUEBRADA` — roda igual em teste e em produção, mas ainda não foi executada contra o banco real porque a `0187` não foi aplicada |
| **F2.1 — Tipos variáveis (migration `0185`) — DESCARTADA, nunca aplicada** | Nove tipos itemizados (`AGING_AP`, `AGING_AR`, `EXTRATO_BANCARIO`, `GARANTIAS`, `AVAIS_FIANCAS`, `CONTINGENCIAS`, `DEBITOS_TRIB`, `ESTOQUE`, `HEADCOUNT`) ganhariam exigência lexical `origem='proposta'`. **Medida contra produção em 21/09/2026 e REPROVADA**: 190 documentos dos nove tipos em 14 casos, 64 pares caso×tipo com conteúdo, 17 abririam pendência — **os 17 TÊM o dado**. Causa-raiz: em relatório ITEMIZADO o conceito não está no rótulo — o rótulo é o item (`41518 - WELLA BRASIL LTDA.`, `2500 - ASSALA PRIME`), o conceito é o TIPO do documento. E o erro é simétrico: 22 dos 47 que "passam" se satisfazem por uma linha residual (`Demais fornecedores`), que é o agregado que o aging justamente não abre. **Decisão do dono (21/09/2026): os nove tipos ficam COMPLEMENTARES, não bloqueantes** — a `0185` foi DESCARTADA do repositório em 22/09/2026 (commit `37de0ba`); o número `0185` fica como lacuna, explicado no `Supabase/README.md`. Ficha completa: `.claude/conhecimento/fichas/f2-localizador-chave-pendencia-falsa.md` |
| **D6 por declaração (migration `0187`, escrita e testada 22/09/2026, NÃO aplicada)** | `taxonomia_tipo_cobertura`: 30 tipos ativos declarados — 3 `consumidor_nomeado` (MUTUOS→`fn_reconciliar_mutuos`, BALANCETE→`fn_reconciliar_arvore`, DF_AUDITADA→`fn_reconciliar_intragrupo`, cada um confirmado lendo o corpo vigente da função) e 27 `sem_consumidor`, sempre com motivo E efeito (regra 1). `fn_cobertura_de_tipos()` roda D6 estrito sobre todos os tipos ativos. 27 asserts; desligando: declaração 4 · desativação 2 (re-medida pela sessão principal: 2, os mesmos) · localizador de seção 4 · resolução dirigida 4 · `{saldo_mutuos}` 3+1 |
| **F2.2 — MAPA_DIVIDA fino** | **MEDIDO contra produção (22/09/2026), NÃO construído.** 51 mapas com conteúdo, 2.268 linhas; 12 com linha de juros, 12 com saldo, **0 com taxa, 0 com vencimento, 0 com covenant** — essas colunas não chegam como linha de conta no formato atual. Depende da F3 (schema da linha) para ter onde gravar taxa/vencimento/covenant como campo, não como texto solto |
| **F2.3 — consumidor real para MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL** | **NÃO fechada.** MUTUOS já tem consumidor (`fn_reconciliar_mutuos`, confirmado na `0187`). FAT_INTRAGRUPO e CONTRATO_SOCIAL ficaram declarados `sem_consumidor` (com efeito nomeado) na `0187` — CONTRATO_SOCIAL ganhou apenas um localizador de seção, não uma checagem. Escrever uma checagem que leia FAT_INTRAGRUPO (pares A→B por ano contra a eliminação do COMBINADO/FATURAMENTO_24M) é **desenho novo**, não decidido: subir qualquer tipo "complementar" a bloqueante continua sendo decisão do dono, não desta fase |
| **F2.4 — terceiro book: distress (commit `cc9f8f5`, 22/09/2026)** | `Dados de Teste/book-distress`, Grupo Piraquara (fictício): 3 entidades × 2023–2025, 14 PDFs, 262 linhas de conta. PL da Metalúrgica 10.641 → 11.006 → (7.355); covenant DL/EBITDA 1,72x → 2,89x → 12,25x contra limite 3,0x; aging AP de 12 fornecedores por nome, total 14.900 = Fornecedores do BP; extrato de 12 meses fecha em 676 = caixa do BP. **Determinístico** (md5 idêntico em 2 gerações); CI gera. **Achado:** A=P+PL e ΔPL valem por construção (+1 no imobilizado 2023 NÃO reprova o motor) — README corrigido para não prometer o que o gerador não confere. **Achado:** o `book-canastra` NÃO é determinístico ao byte (PDF muda de md5; `METRICAS.json` estável). **Sem fixture SQL ainda** — nenhuma checagem lê aging/extrato hoje (depende da F3) |
| **Suspeita F2.1 (MUTUOS/FAT_INTRAGRUPO) — CONFIRMADA e corrigida em 22/09/2026** | A suspeita aberta pela sessão 99 foi investigada nesta sessão: as 5 pendências `linha_exigida_ausente` ABERTAS em produção de MUTUOS (1), FAT_INTRAGRUPO (3) e CONTRATO_SOCIAL (1) foram conferidas UMA A UMA — **TODAS falsas** (o item está na chave, o conceito mora na seção ou no tipo, mesmo defeito da `0185`). Corrigido pela `0187`: MUTUOS/FAT_INTRAGRUPO desativadas (`ativo=false`), CONTRATO_SOCIAL ganhou localizador de seção. **Previsão medida do efeito em produção, após aplicar:** 5 pendências resolvidas, 0 abertas; a 1 `aceita_com_ressalva` de MUTUOS fica intocada pela migration (comportamento pré-existente para exigência desativada — só o próximo recompute daquele caso a fecha) |
| **Aceite financeiro da F2 — NÃO VERIFICADO** | "Mandato sem aging/extrato não é declarado pronto": nenhum indicador de prontidão implementa esse critério hoje. Os extratos reais do mandato AMO não passam pela ingestão — limite de tamanho, ~125–150 mil itens — então o aceite depende da F3/ingestão, não só da F2 |

*Entrega lateral barata: **Diagnóstico factual** — `documento_fato` já captura covenant rompido,
continuidade operacional e ressalva. Expor numa tela custa pouco e não depende de nada adiante.*

### F2T — TRILHA TRANSACIONAL E CAPTAÇÃO (Espec. 11 §4 + Espec. 12) · **PLANEJADA em 13/10/2026**

**Por que não é a F2:** a F2 dá consumidor aos tipos que JÁ chegam pela extração por IA. A F2T é um
segundo caminho de entrada, determinístico e sem IA, para arquivos de leiaute oficial (SPED,
eSocial, XML fiscal e de transporte, CNAB, OFX), mais a captação automática deles. O escopo inteiro
está em `Arquitetura do Sistema/2 Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md`. As lacunas
citadas abaixo (G1–G27) são as do §13 dela.

| | |
|---|---|
| **Objetivo** | Ler e usar todos os módulos e grupos de SPED, eSocial, logística e CNAB, mais o CNAE, com proveniência por arquivo e linha, e captar esses arquivos com o mínimo de ação humana |
| **Estado** | 🟡 **Etapa 1 FEITA em 13/10/2026 (sessão 107, PR #257), sem ligação ao n8n.** O `Leitor/` reconhece as famílias (G5) e lê o envelope em fluxo (G6), com registro de leiautes (G7), formatos (G10) e zip com limites. A `0206` registra o envelope, a releitura e a versão vigente (G9) e liga/desliga por caso (G25); está **escrita e não aplicada em produção**. Testes: 32 do leitor e 65 asserts da `0206`, medidos não-vazios. **Falta da etapa 1:** hospedar o leitor (P5) e a rota no n8n (Preparar Conteúdo: família oficial + trilha ligada → leitor). Zero SPED em produção |
| **Gap** | Etapa 0 **quase fechada em 13/10/2026**: 10 de 11 decisões tomadas (tabela no fim da Espec. 12). Sobra a D12.3 (Integra Contador, aguarda cotação), que não bloqueia a etapa 1 nem a onda 1, e os [A CONFIRMAR]. Open Finance foi recusado (D12.4 = D6), e o extrato vem sempre por arquivo |
| **Dep.** | Etapa 1 depende só da F0. As ondas dependem de **F1** (CNPJ por entidade e perímetro). As reconciliações conta a conta (S2, por exemplo) esperam **F4**. A eliminação intragrupo das notas (G11) espera **F6**. Ver a tabela de etapas |
| **Agentes** | `migrations-postgres` (tabelas, tipos, reconciliações), `n8n-workflow` (roteador, coletores, republicação), `portal-export` (saída no book, envio direto ao Storage, painel), `suites-invariantes` (cada reconciliação medida não-vazia), `revisor-defeito-silencioso` (todo diff) |
| **Testes** | Um gerador sintético por família, que fecha no BP (padrão `book-distress`), mais um portão no CI por onda. Amostras reais anonimizadas de 3 mandatos para o aceite (G15) |
| **Risco** | **Médio.** É aditivo, mas o volume já derrubou o n8n uma vez (G6), e a captação mexe em credencial fiscal do cliente (G19–G21) · **Impacto** Alto: é o que a Espec. 11 chama de "o principal fator que muda a análise como um todo" · **Esforço** G |
| **Saída** | Por onda: o leitor lê 100% dos registros do arquivo (contagem lida = controle do próprio arquivo); as reconciliações da onda rodam em 3 casos reais com toda divergência acima da tolerância explicada; o resultado aparece no book |
| **Contribui para** | **DATA GATE** (F6): dá a fonte independente que confere o dado declarado |

**As etapas, em ordem.** Uma etapa só começa com a anterior aceita.

| Etapa | Escopo | Depende de | Pode rodar em paralelo com | Critério de pronto |
|---|---|---|---|---|
| **0 — Decisões e confirmações** | D12.1–D12.11; D5 e D6 da Espec. 11; cada [A CONFIRMAR] com quem verifica (G26, G27) | dono | qualquer fase | Toda decisão que bloqueia a etapa 1 e a onda 1 tem resposta escrita na Espec. 12 |
| **1 — Fundação sem cliente** | Roteador reconhece as famílias e abre zip com limites (G5); leitor fora do grafo item a item do n8n, gravando em lote (G6, D12.9); registro de leiautes versionado (G7); particularidades de formato (G10); regras de período (G12), de precedência (G2) e de tolerância (G3); chave contra duplicidade e versão vigente (G9); desligável por caso (G25) | F0 · etapa 0 | **F1, F3, F3b** (arquivos disjuntos: `N8N/lib/formato.mjs` e o leitor novo) | Os geradores sintéticos de todas as famílias passam pelo roteador e pelo leitor com contagem = controle; arquivo de versão desconhecida reprova alto; todas as suítes existentes verdes |
| **2 — Jurídico e segurança** | P3 (termo, RIPD, retenção), escopo só de consulta na procuração (G21), desenho do cofre e RLS (G19, G20) | etapa 0 | etapa 1 | Revisão jurídica assinada e revisão de segurança feita. **Nada é coletado antes** |
| **Onda 1** | ECD + ECF + CNAE da entidade (Simples fora por D12.10, com nota de efeito); medir o `I051` em 3 ECDs reais; captação peças 1–3 | etapa 1 · **F1** | F3, F3b | S1, S6 e o segmento real (`Y540`) em 3 casos reais; S2 só depois da F4 |
| **Onda 2** | OFX, CNAB `E`, CNAB de cobrança e pagamentos (240, 400, 150) | onda 1 | — | C1, C2, C3, C4 e C6 em 3 casos reais; caixa realizado mensal no book |
| **Onda 3** | EFD ICMS/IPI, Contribuições, Reinf, XML de NF-e e NFS-e, inclusive a municipal por demanda (D12.10) (regra da reforma tributária, G8) | onda 2 · **F6** para a eliminação intragrupo (G11) | — | S3, S4, S5 e S7 em 3 casos reais; nota intragrupo nunca somada como receita |
| **Onda 4** | eSocial (todos os grupos), DCTFWeb, FGTS Digital | onda 3 · etapa 2 · D12.7 | — | E1 a E5 em 3 casos reais; nenhum CPF além do que a D12.7 permite |
| **Onda 5** | CT-e, MDF-e, DU-E, DI/DUIMP, CE-Mercante, B/L, AWB, CRT, contratos de câmbio (D12.10) | onda 3 (chave da NF-e) | onda 4 | L1 a L6 em 3 casos reais |
| **Captação 4–6** | Cofre (só o A1 da Oria), robô no ReceitaNet BX com queda para o contador, Integra se a D12.3 aprovar, painel de cobertura (G17, G18, G22, G23) | etapa 2 · D12.3 para o Integra | ondas 2–5 | Cada coletor grava rodou/falhou/vazio/não configurado; um mandato-piloto abastecido sem envio manual das fontes do canal B |

**O que a F2T NÃO faz:** não altera `campo_extraido` nem a extração por IA; não substitui em
silêncio nenhum número do book (D12.8); não liga coleta automática antes da etapa 2.

### F3 — ESTABILIDADE E CONCORDÂNCIA DA EXTRAÇÃO

| | |
|---|---|
| **Objetivo** | Parar de perder documento por causa operacional; autonomia N2 deixar de ser declarada |
| **Estado** | 🟡 schema forte; 39% de falha na rodada de 190; `medicao_*` nulos |
| **Gap** | fallback de provedor, fila de reprocesso, concordância por veredito de produção |
| **Dep.** | F0 · **Risco** Médio (toca o dial) · **Impacto** Alto · **Esforço** M |
| **Saída** | D7 verde |
| **Aceite financeiro** | concordância ≥ limiar do estágio, **publicada como piso enviesado** |
| **Aceite técnico** | lote com falha parcial retoma sem reprocessar o que já custou |
| **Dono** | as rodadas reais — concordância se mede contra veredito de PRODUÇÃO, e só o dono dispara o formulário |
| **Custo** | rodada paga e repetida por definição (a mesma entrada, várias vezes). Estime com `N8N/medir-custo-book.mjs` e fixe o teto de rodadas ANTES de começar |

### F3b — COMPLETUDE POR LINHA: nenhuma linha faltando, nenhuma linha inventada

**ESTA FASE NÃO É NOVA — ela estava ÓRFÃ.** O plano inteiro existe desde 01/09/2026 em
`PLANO_LINHA_A_LINHA.md`, escrito a pedido do dono depois da rodada do araucária, e **este
roadmap nunca o citou**. Um plano correto que o arquivo de "o que falta, em que ordem" não
conhece tem exatamente a mesma aparência de um plano que não existe — é a regra 7 aplicada a
documento em vez de a estágio. Encaixado aqui em 18/09/2026, quando o dono descreveu de novo,
com outras palavras, o mecanismo que o plano já desenhava.

| | |
|---|---|
| **Objetivo** | Que "todas as linhas foram extraídas" deixe de ser estatística e vire **aritmética** |
| **Estado** | 🟡 Fase 0 do plano PARCIALMENTE FECHADA (01/09); Fases 1–5 não começaram |
| **Dep.** | F0 · **paralelizável com F1/F2**, e é a única fase que toca o `SYSTEM_PROMPT` e o schema da linha |
| **Risco** | Médio-alto — toca extração, fatiamento, schema, migration e guardas · **Esforço** G |
| **Aceite financeiro** | os 3 documentos do araucária acusam buraco NOMEADO, e o número de linhas sem destino bate com 97−68, 150−102 e 20−13 |

**Por que ela é a resposta ao que o aceite da 0.5 não mede.** O aceite conta documentos que
produziram alguma linha. A pergunta do dono — *"a cada 100.000 que entram, pelo menos 99.900
extraídas"* — é sobre LINHAS dentro de cada documento, e hoje isso é indecidível: não há
coordenada comum entre o texto que entra e as linhas que saem, então nenhuma afirmação da forma
"a linha 42 do documento virou esta conta" pode ser feita. **O limiar de 85%, a régua e o
instrumento de blocos são todos substitutos trabalhando em volta dessa coordenada que falta.**

As cinco fases, na ordem do plano (o detalhe, com os números medidos, está lá — não duplicar aqui):

| Fase | O que entrega |
|---|---|
| **1** | A coordenada: texto NUMERADO ao lado do PDF (não no lugar dele), e `ln` obrigatório no schema da linha |
| **2** | A bijeção: o modelo declara `descartadas` com motivo, e a guarda vira aritmética — buraco, duplicação e invenção de origem viram BLOQUEANTE nomeado pelo número da linha |
| **3** | A literalidade: `vt` cobrado como o `tr` dos fatos — trecho literal da linha citada. É a primeira vez que "criar dado" fica detectável |
| **4** | **Re-perguntar só o buraco** — "leia SÓ as linhas 23 a 51", com teto de 1 re-pergunta por documento |
| **5** | Medir cada guarda não-vazia (regra 2) |

**A Fase 4 é o fallback que o dono pediu em 18/09, e o plano a desenha melhor do que o pedido.**
O pedido era: quando a régua conta 50 e a IA devolve 30, extrair de novo. O plano re-pergunta
**só as linhas sem destino** — bloco pequeno, resposta pequena, custo proporcional ao defeito, em
vez de pagar o documento inteiro de novo e poder voltar com outro buraco. **Mas ela depende das
Fases 2 e 3**: sem a bijeção não existe "o buraco", existe só uma diferença entre dois números,
e re-perguntar contra uma diferença é re-extrair o documento inteiro com outro nome.

**E há um ganho que responde à desconfiança do dono sobre qual das duas partes está errada.** Hoje,
quando a régua diz 50 e a IA diz "não havia número", não há como saber quem errou — foi
exatamente o impasse dos três documentos da fatia 0.5. Com a Fase 2, **a régua deixa de ser
juíza**: o modelo declara linha a linha o que é conta e o que é cabeçalho, e a régua vira uma
segunda opinião sobre a MESMA linha. Onde as duas discordam é o sinal, e o sinal aponta para uma
linha específica que um humano abre e confere em segundos — em vez de um percentual sobre o
documento todo.

**O que ela explicitamente NÃO resolve** (está no plano, e vale repetir para não vender demais):
não garante que o modelo LEIA certo. Garante que ele declare o destino de cada linha e que o
valor seja literal. Valor lido errado, mas literalmente copiado da linha certa, passa — e
continua sendo trabalho das guardas de valor.

### F4 — CONTA CANÔNICA, HIERARQUIA E RESOLUÇÃO (intervenção central)

| | |
|---|---|
| **Objetivo** | Dar identidade tipada ao fato financeiro |
| **Estado** | 🔴 identidade é `(secao_canonica, rótulo_norm)`; sem hierarquia; sem FK |
| **Dep.** | **F0, F1, F2** |
| **Banco** | `conta_canonica(codigo, nome, secao_canonica, classe_recorrencia, pai, natureza)` · `fato_financeiro(conta_id, entidade_id, periodo_id, cenario_id, versao, moeda, valor, evidencia_id[], resolucao_metodo)` |
| **Agentes** | `migrations-postgres`, **`ontologia-contabil`**, `revisor-defeito-silencioso` |
| **Risco** | **Alto.** Mitigação: `campo_extraido` **não muda**; canônico acima; cada reconciliação migra sozinha com os dois caminhos rodando em paralelo até baterem |
| **Impacto** | **Máximo** — extingue a família de bugs de rótulo · **Esforço** GG |
| **Saída** | D2, D3, D4 verdes |
| **Aceite financeiro** | subtotal == Σ folhas em todo documento dos books, ou divergência declarada; **0 duplicidades por subtotal+filho** |
| **Aceite técnico** | 0 fatos sem identidade; heurística sempre com pendência; **as 10 reconciliações dão o mesmo resultado nos dois caminhos antes de o antigo sair** |

### F5 — LINEAGE EXPLÍCITO

Objetivo: "de onde veio este número" por SQL, não por nota de célula. Dep. F4. Banco:
`lineage_aresta(origem_tipo, origem_id, transformacao, destino_tipo, destino_id, regra)`. A nota do
Excel vira **render**. Risco baixo · Impacto alto (Princípio 1 completo) · Esforço M.
**Aceite financeiro:** qualquer número do 1º export responde origem, período, entidade, moeda,
transformação e regra.

### F6 — RECONCILIAÇÃO SOBRE IDENTIDADE + INTERCOMPANY

Migrar as 10 funções para FK real; `eliminacao_intragrupo` como fato próprio. Dep. F4, F5, F2.
Risco médio · Impacto alto (fecha o Princípio 2) · Esforço M. **Saída: DATA GATE completo.**
**Aceite financeiro:** o combinado das 6 empresas do book-canastra fecha com eliminação explícita;
crédito de A == débito de B.

### F7 — MOTOR DE CÁLCULO (segunda intervenção central)

| | |
|---|---|
| **Objetivo** | Trazer a aritmética da projeção para dentro do sistema |
| **Estado** | 🔴 calculada pelo Excel; **89 premissas e 7 fórmulas já catalogadas** |
| **Gap** | o interpretador — **menor do que parece**: 7 opcodes, não uma plataforma |
| **Dep.** | **DATA GATE** |
| **Arquivos** | módulo novo · `modelo-institucional.ts` vira emissor · `avaliar-formula.mts` vira portão |
| **Banco** | `resultado_calculo(cenario, conta, entidade, periodo, valor, lineage)` |
| **Agentes** | **`motor-financeiro`** (novo), `revisor-defeito-silencioso` |
| **Risco** | **Alto** — mitigado pelo portão de paridade (regra 2 aplicada a troca de arquitetura) |
| **Impacto** | **Máximo** — destrava 6 dos 15 estágios · **Esforço** GG |
| **Saída** | **MODEL GATE** |
| **Aceite financeiro** | balanço fecha em todo exercício e cenário; DFC amarra; **a guarda de giro reprova os 1.200 dias que a fixture produz hoje** |
| **Aceite técnico** | `.xlsx` continua com fórmula viva e idêntico ao atual dentro de 0,01; determinismo byte a byte |

### F8 — CENÁRIOS E ALAVANCAS

Cenário e alavanca como dado versionado. Dep. F7. Banco: `cenario`, `alavanca`, `cenario_id` em
`caso_premissa`/`caso_linha_premissa`. Risco médio · Impacto alto · Esforço G.
**Saída: STRATEGY GATE.** Aqui entram as alavancas **operacionais** — a fase "Operational
Turnaround" eliminada vive aqui, como `categoria`, sem arquitetura própria.

### F9 · F10 · F11 — paralelizáveis após o MODEL GATE

| | **F9 Capital Structure** | **F10 Liquidez/13-week** | **F11 Diagnóstico analítico** |
|---|---|---|---|
| Objetivo | Dívida como instrumento | Caixa semanal a partir do dado sujo | Índices, tendências, sinais |
| Hoje | 🟠 `MAPA_DIVIDA` + revolver no Excel | 🟠 `dias_de_giro` anual; sem semana | 🟠 9 fatos materiais (factual em F2) |
| Gap | `instrumento_divida`, `credor`, `garantia`, `covenant` | granularidade semanal + AGING/EXTRATO ligados | motor de índices sobre o canônico |
| Dep. | F7, F2 | F7, **F2** | F7, F6 |
| Risco | Médio | **Alto** — dado mais sujo | Baixo |
| Esforço | G | G | M |
| Aceite fin. | Σ instrumentos == dívida do BP ou divergência declarada | 13-week reconcilia com saldo do extrato; **nunca preenche semana ausente com zero** | índice sem base não é exibido como 0 |

### F12 → F13 → F14

| | **F12 Valuation** | **F13 Recovery** | **F14 Restructuring** |
|---|---|---|---|
| Hoje | 🔴 0% | 🔴 0% | 🔴 5% |
| Gap | DCF sobre o motor, múltiplos, ajuste de EBITDA (usa `classe_contabil_catalogo`) | waterfall por prioridade legal | alongamento, carência, haircut, new money |
| Dep. | F7, F9 | **F12, F9** | F8, F13 |
| Esforço | G | G | M |
| Aceite fin. | reconciliado com o modelo que o gerou | Σ recuperação ≤ distribuível (**invariante duro**); prioridade citável | toda alavanca reversível e diffável contra o Base |
| Saída | | **CREDITOR GATE** | |

### F15 → F16

| | **F15 Presentation Data Layer** | **F16 PPT** |
|---|---|---|
| Objetivo | Projeção sem estado sobre o motor | Geração do deck |
| Dep. | CREDITOR GATE | F15 |
| Esforço | M | P |
| Risco | **Médio — de disciplina**: se ganhar estado, vira a segunda fonte que o Princípio 8 proíbe | Baixo |
| Aceite téc. | **portão estático: 0 aritmética fora do motor** | número no PPT == Excel == banco |

*F16 é pequena PORQUE F15 foi feita direito. Se parecer grande, F15 está errada.*

### F17 — HARDENING (contínuo)

RLS por caso e papel · teste de restauração executado · Sonar com Quality Gate no CI · proteção do
`main` · registro de leitura no `evento_auditoria` · conversão cambial. **Distribuir ao longo do
roadmap** — deixar para o fim é o padrão que produz a dívida que este projeto passa o tempo pagando.

---

## 8. CRITICAL PATH, paralelização, MVP

### Critical path

```
F0 --> F1 --> F4 --> F6 --> [DATA GATE] --> F7 --> [MODEL GATE] -->
   --> F9 --> F12 --> F13 --> [CREDITOR GATE] --> F15 --> F16
       |__ F2 __|
```

Dez fases no caminho crítico. **Duas dominam o custo: F4 e F7.** Tudo mais é acessório ou
paralelizável.

### Paralelização POSSÍVEL
- **F1 ∥ F2 ∥ F3 ∥ F3b** — conjuntos de arquivos disjuntos (entidade / taxonomia / provedor /
  contrato de extração). Onda paralela legítima pelo critério de
  `Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`. **A F3b tem a ressalva de ser a única
  das quatro que toca o `SYSTEM_PROMPT` e o schema da linha** — se a F3 (provedor) mexer no
  mesmo prompt na mesma onda, os conjuntos deixam de ser disjuntos e as duas param de ser
  paralelizáveis. Conferir antes de despachar, não durante.
- **F9 ∥ F10 ∥ F11** após o MODEL GATE.
- **F5** ∥ final de F4.
- **F17** distribuída, sempre.
- **Terceiro book (distress)** ∥ qualquer coisa.
- **F2T etapa 1** (roteador e leitor novo) ∥ **F1 ∥ F3 ∥ F3b**: conjuntos disjuntos, desde que a
  etapa 1 não toque o `SYSTEM_PROMPT` nem o schema da linha. **F2T etapas 0 e 2** (decisão,
  jurídico) ∥ qualquer coisa.

### Paralelização PROIBIDA
- **F4 com qualquer coisa que toque `campo_extraido` ou as reconciliações.** Arquivos não disjuntos;
  consequência é divergência silenciosa no núcleo.
- **F7 com F8.** Cenário é parâmetro do motor; juntos, cenário fica hardcoded dentro do motor.
- **F12 com F13.** Recovery consome valuation; paralelos, inventa o valor que distribui.
- **F15 com F16.** PPT antes da camada de apresentação lê dados por conta própria e vira a segunda
  fonte. **É o erro mais provável do roadmap inteiro**, porque PPT é o que mais se quer ver.
- **Qualquer fase com F0 aberta.**
- **Uma onda da F2T que crie reconciliação junto com a F4.** As duas tocam as reconciliações. A
  onda espera, ou a reconciliação dela fica por total, sem conta a conta.
- **Coleta automática (F2T captação 4–6) antes da F2T etapa 2.** Credencial fiscal sem termo e sem
  cofre é risco jurídico, não dívida técnica.

### MVP

**F0 → F7, mais F9 e o diagnóstico factual.** É o ponto em que o sistema passa a SABER os números
que produz. Antes dele, valuation e recovery são aritmética sobre um modelo que o sistema não lê.

| Entrega | Fase |
|---|---|
| Sistema testado == implantado | F0 |
| Perímetro e entidades resolvidos | F1 |
| Nenhum tipo de documento some em silêncio | F2 |
| Dado canônico com identidade, hierarquia e lineage | F4, F5 |
| Reconciliação com intercompany | F6 |
| **Modelo dentro do sistema, com paridade provada** | F7 |
| Estrutura de capital como instrumento | F9 |
| Diagnóstico factual | F2 (lateral) |
| Excel como hoje — fórmula viva | mantido |

**Obrigatório:** F0 · F1 · F2 · F4 · F5 · F6 · F7 · governança contínua · terceiro book distress.

**Nice-to-have:** diagnóstico analítico com índices setoriais · 13-week completo (a parte de DADOS é
obrigatória; a projeção semanal não) · PPT · conversão cambial · múltiplos de mercado · comparação
entre mandatos.

**Adiar:** multi-tenancy real · API pública · comparação entre setores · integrações com ERP ·
granularidade semanal de projeção · `golden_set` reconstruído com rotulagem manual.

---

## 9. DO NOT BUILD YET

Cada linha é algo que, construído agora, ficaria **errado** ou **descartado** — não apenas "cedo".

| # | Não construir | Por quê |
|---|---|---|
| 1 | **Qualquer coisa acima do DATA GATE** | Construir sobre `(secao_canonica, rótulo_norm)` é herdar toda a família de bugs de string. Será refeito |
| 2 | **PowerPoint / geração de deck** | Sem camada de apresentação ele lê dados por conta própria e **vira a terceira fonte de números**. Viola o Princípio 8 de forma difícil de desfazer. O risco mais provável do plano |
| 3 | **Valuation** | Sem motor, é aritmética sobre números que o sistema não lê |
| 4 | **Recovery / waterfall** | Sem `instrumento_divida` com garantia e prioridade, é planilha com cara de sistema |
| 5 | **Projeção semanal do 13-week** | Semana não existe no eixo de período e os insumos não têm consumidor. Produziria um 13-week bonito e falso — o pior desfecho numa mesa de reestruturação |
| 6 | **"Motor de turnaround operacional"** | Não há dado (headcount por função, capacidade, mix). Seria CRM com nome de motor. É categoria de alavanca em F8 |
| 7 | **Camada de "Stress/Red Team" separada** | O red team já existe e é bom; falta apontá-lo ao modelo via MODEL GATE. Camada nova duplicaria um ativo |
| 8 | **Multi-tenancy / RLS por caso** | Real e documentado, mas não bloqueia o caminho crítico. Faria F4 e F7 custarem mais |
| 9 | **Reescrever `campo_extraido`** | A tentação óbvia em F4 e o erro mais caro possível: descarta a camada de evidência e a proveniência junto. Construir **acima**, nunca no lugar |
| 10 | **Golden set com rotulagem manual** | Saiu do produto por decisão do dono (PR #153). `fn_veredito_producao` é o caminho e já existe |
| 11 | **Migrar o Excel para saída de valores** | O `.xlsx` com fórmula viva é ativo comercial, não dívida. O motor muda a FONTE da verdade, não o formato da entrega |
| 12 | **Conversão cambial** | Só quando houver mandato multimoeda real. Hoje o export se recusa a totalizar — comportamento correto |
| 13 | **Novos tipos de documento** | 27 dos 36 existentes ainda não têm consumidor. Acrescentar tipo antes de F2 aumenta o silêncio |
| 14 | **Refatorar `modelo-institucional.ts` antes de F7** | Ele encolhe naturalmente quando vira emissor. Antes, é trabalho jogado fora |
| 15 | **Comparação entre mandatos / benchmark setorial** | Exige conta canônica estável entre casos. Depois de F4 é quase de graça; antes, impossível |

---

## 10. RISCOS DO ROADMAP

| # | Risco | P | Impacto | Mitigação |
|---|---|---|---|---|
| R1 | **F4 quebra o que funciona** | Média | **Crítico** | `campo_extraido` não muda; canônico acima; cada reconciliação migra sozinha com os dois caminhos em paralelo até baterem |
| R2 | **F7 não alcança paridade com o Excel** | Média | **Crítico** | `avaliar-formula.mts` como portão célula a célula ANTES de trocar a fonte. Se não bater, o Excel continua mandando e nada se perde |
| R3 | **O fosso repo↔produção reabre** | **Alta** (é o padrão: já aconteceu com a `0133`, com o n8n e com o provedor) | Alto | F0 cria portão automático. Sem automação, reabre |
| R4 | **PPT construído antes da camada de apresentação** | **Alta** — é o que todos querem ver | Alto | DO NOT BUILD #2 + portão estático P1 |
| R5 | Provedor de IA derruba rodada | **Alta** (já ocorreu: 72 documentos) | Médio | F3: fallback + retomada |
| R6 | Escopo não decidido; roadmap priorizado contra visão contraditória | Média | Alto | F0 inclui reescrever `00_VISAO_E_ESCOPO`. É decisão do dono |
| R7 | Documentação consome a capacidade | Média | Médio | F0: `PRONTIDAO` gerado, não escrito; cabeçalho sob portão |
| R8 | **Rodadas de correção pontual consomem o tempo das duas mudanças estruturais** | **Alta** — padrão visível em 8 migrations sobre a mesma causa | **Alto** | Congelar correções de identidade por string fora de F4 |
| R9 | 13-week sobre dado que não chegou | Média | Alto | F10 depende de F2. Semana ausente é pendência, nunca zero |
| R10 | Autonomia N2 nunca confirmada | Média | Médio | F3 via veredito de produção, publicando que é piso enviesado |

---

## 11. FIRST PHASE EXECUTION PLAN — F0

**Objetivo:** que o sistema testado e o sistema em operação sejam o mesmo, e que o escopo do produto
pare de se contradizer. **Nada de arquitetura nova nesta fase.**

**Entrada:** nenhuma. **Saída:** D1 verde e a decisão de escopo registrada.

### Fatia 0.1 — Inventário do fosso (medir antes de corrigir) · **FEITA em 16/09/2026**
- `fn_instalacao_conferir()` **contra produção** — 0 ausências (via API de gerenciamento do
  Supabase; a sessão não alcança a porta do Postgres direto neste ambiente).
- Migrations pendentes confirmadas por comparação de CORPO, byte a byte, não por suposição:
  `fn_entidade_aprender_cnpj` e `fn_registrar_diagnostico` bateram EXATAMENTE com a `0174` antes
  de qualquer aplicação. **O número real era 3 (`0175`–`0177`), não os 20 que uma estimativa
  anterior, errada, tinha calculado** — o total de migrations no repositório também estava errado
  (122, não 177; o 177 é só o maior número de arquivo, com um pulo de 0044 para 0100).
- Hash do workflow publicado × gerado: `conferir-publicado.mjs` alimentado com os 4 workflows
  reais via API do n8n. Achado grave: a ingestão tinha perdido `multipleFiles: true` no formulário
  (detalhado na fatia 0.3, abaixo).
- **Entregável:** tabela medida, não lembrada — ver `ESTADO.md`, linhas "Aplicadas no Supabase" e
  "Workflow PUBLICADO no n8n".
- *Risco: nenhum — foi leitura.*

### Fatia 0.2 — Aplicar as migrations pendentes · **FEITA em 16/09/2026**
- `0175`, `0176`, `0177` aplicadas EM ORDEM, sonda conferida depois de cada uma (0 ausências nas
  três vezes). Nenhuma DDL estrutural nas três — só `create or replace function` e registro no
  catálogo (`insert into instalacao_requisito`); os `insert`/`update` de dado real que aparecem
  nos arquivos moram DENTRO de corpo de função, e só rodam quando a função for chamada depois —
  não na hora de aplicar a migration. Verificado ANTES de aplicar, não suposto.
- Verificação final: corpo de `fn_entidade_aprender_cnpj` bate byte a byte com a `0177`, e
  `fn_pendencia_cnpj_colide_balcao` (nascida na `0176`) existe.
- **Entregável:** sonda com 0 ausentes — ATINGIDO.
- *Risco medido como baixo na prática: sem DDL estrutural, reversível reaplicando a versão
  anterior da função se algo saísse errado. Nada saiu.*

### Fatia 0.3 — Republicar os workflows e alinhar o provedor · **FEITA em 16/09/2026**
- Os 4 republicados: macro já batia (0 divergências, não precisou); erros e diagnóstico
  republicados com a ferramenta generalizada nesta rodada; ingestão republicada corrigindo o
  achado grave — `multipleFiles: true` void no formulário de upload (o cliente só conseguia subir
  um documento por vez). Confirmado por três fontes antes de agir: o gerador declara o campo de
  propósito, é defeito já nomeado em `.claude/memory/republicacao-do-n8n-perde-toggles.md`, e o
  JSON buscado era fresco (`updatedAt` do dia).
- **Achado no caminho:** `preparar-republicacao.mjs`/`republicar.sh` só sabiam publicar a
  ingestão — hardcoded. Generalizados com `N8N_ARQUIVO_REPO`, com o padrão preservando quem já
  automatizou sem a variável. Uma segunda trava (o script assumia gatilho de formulário em TODO
  workflow) quebrou ao tentar publicar `erros` e foi corrigida na hora — condicional à existência
  do gatilho.
- `Gravar Uso do Lote` presente no canvas — confirmado ao vivo, `disabled: false`.
- Provedor confirmado ao vivo no nó `IA Extrair`: `api.openai.com`, batendo com
  `PROVEDOR_PADRAO = 'openai'` do repositório.
- `FINGERPRINT_EXTRACAO` conferido ANTES e DEPOIS da republicação: `6f5a9374a9d2b1ae` nos dois —
  não mudou, então a próxima rodada não reprocessa nenhum documento à toa.
- **Entregável:** os 4 workflows batem 100% com o repositório — `conferir-publicado.mjs` OK nos
  quatro, verificado depois de cada publicação.
- *Risco realizado: um, achado e corrigido na hora (a trava do formulário). Nenhum PUT feito sem
  `--dry-run` antes.*

### Fatia 0.4 — Portões que impedem o fosso de reabrir (valor permanente) · **FEITA em 16/09/2026**
1. **Sonda contra produção** em agenda, não só contra o banco do CI — fecha o ponto cego de
   `sonda-so-conhece-o-catalogo-que-o-banco-tem`.
2. **Hash do workflow publicado × gerado** — estende `conferir-publicado.mjs`.
3. **Espelho `CLAUDE.md` × CI completo** — hoje o auto-check cobre só `verificar-*.mts` e
   `medir-*.mjs`; ficaram de fora `.claude/hooks/test/` e o passo de regeneração de fixtures.
   Generalizar para TODA categoria de portão.
- **Medição (regra 2):** desligar cada portão e registrar quantos asserts reprovam. Portão que nasce
  vazio não é portão.
- *Agentes: `suites-invariantes` + `revisor-defeito-silencioso`. Risco: baixo.*

### Fatia 0.5 — Reprocessar a rodada "Teste 00"
- Reprocessar os 75 documentos sem linha (73 `extracao_falhou`, 72 por billing).
- **É o primeiro dado honesto do sistema:** a primeira rodada em que o código testado é o executado.
- **Entregável:** ≥95% dos documentos com linha; o que falhar, falha por razão nova e documentada.

> **O 98% foi levantado e DEVOLVIDO a 95% no mesmo dia (18/09/2026), e o motivo é a parte que
> interessa.** O dono subiu para 98%, depois reverteu com o argumento certo: *"ele não serve de
> nada se estiver faltando linhas nos documentos que conseguiu extrair"*. Está correto, e nomeia
> o limite deste aceite — **ele conta DOCUMENTOS que produziram alguma linha, e é cego para
> quantas linhas faltaram dentro de cada um.** Um documento de 97 linhas que devolveu 68 conta
> aqui como sucesso, exatamente igual a um que devolveu as 97.
>
> Subir 95 → 98 apertaria a régua que já é a certa para o que ela mede (a fatia 0.2/0.3
> funcionaram: zero silencioso, zero não processado) e continuaria sem medir o que o dono quer
> garantir. **A garantia que ele descreveu — "a cada 100.000 que entram, pelo menos 99.900
> extraídas" — não é este número, é outro, e já tem plano escrito:
> `PLANO_LINHA_A_LINHA.md`.** Ver a seção "A completude por linha" abaixo.
>
> A unidade também ficou decidida: é o DOCUMENTO. "98% das linhas extraídas" exigiria gabarito
> por documento, que num mandato real não existe — só nos dois books sintéticos. Aceite cujo
> número ninguém consegue conferir é pior que um aceite mais frouxo.
- *Risco: baixo. É a validação de que 0.2 e 0.3 funcionaram.*

> **ACEITE DADO PELO DONO em 18/09/2026, com a medição abaixo na mesa.** Os 94,9% ficam 0,1 ponto
> abaixo do critério, e o dono julgou que isso cai na margem de erro — decisão dele, tomada vendo
> o número e a decomposição, não por arredondamento de ninguém. O que sustenta o julgamento não é
> o 0,1: é que **as duas colunas que importam são ZERO** (nenhuma falha silenciosa, nenhum
> documento não processado), e toda a diferença é declarada e nominada.
>
> **Os 6 documentos NÃO ficam perdoados — ficam DIFERIDOS, com endereço.** Decisão do dono na
> mesma passada: "devem ser corrigidos sim, e toda a rodada também deve ser otimizada e corrigida
> ao extremo, mas não agora, e sim nas outras fases específicas". Endereço de cada um:
> os 4 artefatos de planilha e as 2 certidões com contradição régua × IA são **F3b** (completude
> por linha, que é o que torna a contradição decidível); a classificação errada dos 3 arquivos como
> `EXTRATO_BANCARIO` é **F2**; e o `padrao_suspeito` que gera o falso-positivo é **F4**.
>
> **A F0 está FECHADA.** Os quatro critérios: geral (sonda verde em produção, execução #10),
> técnico (portões medidos, CI reprova se produção divergir), de produto (escopo + duas ADRs) e
> financeiro (este, aceito acima).

**MEDIDO EM PRODUÇÃO, 18/09/2026 — o aceite fica 0,1 ponto abaixo, e o dono o concedeu.** Primeira vez que a cobertura do lote
foi lida do banco do cliente, com `Supabase/test/cobertura-do-lote.sql` contra o caso
`AMO teste 00` (`1be52ab4-9692-4e17-b332-1dc05dcc8c70`):

| | |
|---|---|
| documentos | **118** |
| com linha | **112** |
| sem linha, DECLARADO (`tem_dado_financeiro = false`, regra da `0111`) | **6** |
| sem linha, SILENCIOSO (a extração voltou vazia e ninguém assumiu) | **0** |
| extração nunca chamada | **0** |
| `pct_com_linha` | **94,9%** |

**94,9% reprova os 98% e reprovava também os 95% anteriores** — e o instrumento existe justamente
para que esse número não seja lido sozinho. As duas outras colunas são a notícia boa e elas são
fortes: **zero falha silenciosa e zero documento não processado.** Toda a diferença é declarada,
o que quer dizer que a 0.2 e a 0.3 fizeram o que prometiam. Soma de linhas: **7.670**, que bate
com os 7.670 campos do book entregue ao dono — a consulta conta a mesma coisa que o export.

Os seis, nomeados (o aceite exige documento a documento):

| Tipo | Arquivo | O que o sistema registrou |
|---|---|---|
| ORGANOGRAMA | `Organograma societário.xlsx` | sem `falha_motivo` — documento que por natureza não tem linha financeira |
| EXTRATO_BANCARIO | `Controle_Extratos e OFX.xlsx` | sem `falha_motivo` |
| EXTRATO_BANCARIO | `Status Extratos (2024,2025 e 2026).xlsx` | sem `falha_motivo` |
| EXTRATO_BANCARIO | `Relação_Contas_AMO.xlsx` | **`falha_motivo` de cobertura: 0 de 30 linhas de conta vistas no texto** |
| CONTRATO_SOCIAL | `Certidão 4ª Alteração - CORPORATE.pdf` | **`falha_motivo` de cobertura: 0 de 50** |
| CONTRATO_SOCIAL | `Certidão 5ª Alteração - AMOBELEZA.pdf` | **`falha_motivo` de cobertura: 0 de 50** |

**Três deles carregam uma CONTRADIÇÃO que esta medição expõe e não resolve.** O diagnóstico da IA
disse `tem_dado_financeiro = false` ("não havia número para dar") e a régua de cobertura, que lê o
texto do PDF sem IA, contou 30 e 50 linhas de conta nos mesmos arquivos. As duas afirmações não
podem estar certas ao mesmo tempo. Ou a régua conta como conta o que não é (é a classe do **Bug A**,
medido em 11/12 de falso-positivo nesta mesma rodada, diferido para F4), ou a extração deixou dado
para trás e o `tem_dado_financeiro` está errado. **Não é decidível sem abrir os três arquivos**, e
afirmar qualquer um dos lados aqui seria exatamente o que a regra 1 proíbe.

**E há um achado que não é da F0, mas que a F2 vai cobrar:** `EXTRATO_BANCARIO` tem **3 documentos
e ZERO linha** no mandato inteiro. O aceite financeiro da F2 diz, com todas as letras, que
"mandato sem aging/extrato **não** é declarado pronto".

**O dono respondeu, 18/09/2026, e a resposta corrige duas coisas.** Primeira: os três arquivos
**não são extratos bancários** — "Status Extratos" tem relação com pagamento de dívidas, e os
outros dois são controles. Estão CLASSIFICADOS como `EXTRATO_BANCARIO` e não são: é
`tipo_incorreto`, que já tem 5 pendências abertas neste caso. Zero linha neles não é falha de
extração. Segunda, e mais séria: **os extratos de verdade nunca foram enviados** — são os
arquivos que começam com `CR` e `CP`, com centenas de milhares de linhas, e não passam pelo n8n.
Isso liga direto ao limite medido na fatia 0.5 (o estouro de pilha em `push(...arr)` do nó de
merge nativo, ~125.000–150.000 itens): o mandato não tem extrato porque a ingestão não aguenta
o tamanho deles, não porque alguém esqueceu. **É requisito de F2 com dependência técnica não
resolvida**, e não uma pendência administrativa. Registrado aqui para a F2 não começar supondo
que basta pedir o arquivo ao cliente.

**Pendências ainda abertas no caso: 79.** As três maiores: `divergencia_reconciliacao` 28,
`extracao_padrao_suspeito` 12 (o Bug A), `extracao_falhou` 12. As 12 de `extracao_falhou` são
ANTERIORES à republicação do fix do Bug C (18/09) e não se resolvem sozinhas: a função resolve a
pendência quando o documento é reprocessado, e nenhum foi.

**Achado, 16/09/2026 — o lote precisa ser dividido, e é limitação conhecida, não bug.** O dono
tentou subir os 127 arquivos do lote em uma execução só (126,6 MB). A execução `#7834` do
workflow de ingestão morreu aos 3m58s com `status: error`, `290MB` de dados de execução, e nem
a interface do n8n consegue mostrar o node/mensagem exata ("This execution's data is too large
to display") — evidência de que o processo estourou memória, não de um documento específico
corrompido (não dá para provar qual node, e por doutrina não afirmamos o que não foi medido).

**Causa provável (hipótese, não confirmada por falta de acesso ao painel):** o n8n roda no
PikaPods (`HANDOFF.md`, RAM fixa por contêiner) e mantém TODO o lote — cada item, cada binário —
na memória do processo durante a execução inteira. Um lote de 126 MB de binário mais a sobra do
Node.js pode estourar o teto de RAM do plano contratado, e o SO mata o contêiner no meio —
por isso nem um erro decente sobra para ler.

**Decisão do dono, 16/09/2026: não redesenhar o workflow agora.** As duas saídas técnicas —
(a) aumentar o plano do PikaPods (rápido, mas só empurra o teto: um lote maior no futuro estoura
de novo) e (b) reescrever o grafo para processar item a item, memória plana independente do
tamanho do lote (correção de raiz, mas é engenharia real com risco de republicação) — ficam
registradas aqui para quando isso voltar a doer. Por ora: **conviver com o limite**, dividindo
lotes grandes em partes de ~90 MB (o `caso_id` é o mesmo entre envios — `fn_upsert_caso` reaproveita
pelo nome do mandato, então dividir em vários envios não perde nem duplica nada).

**Correção da causa, 17/09/2026 — não era RAM.** A hipótese acima ("esgotamento de RAM do
PikaPods") foi medida e refutada na rodada real "AMO teste 00" (ver `ESTADO.md`). A causa real é
**stack overflow em JS** no nó de merge nativo do n8n: o operador de espalhamento `push(...arr)`
estoura a pilha de argumentos do V8 no Node 22 com aproximadamente **125.000–150.000 itens**
(limite empírico, medido por falhas e sucessos consecutivos) — não com megabytes de binário. Isso
não muda a decisão do dono (dividir em lotes menores continua sendo a mitigação certa, porque
reduz o número de itens, não só o peso em MB), mas muda a saída técnica (b): reescrever o grafo
para memória plana não resolveria uma pilha de chamadas — precisaria trocar `push(...arr)` por
um laço ou `arr.push.apply` em lotes, dentro do próprio nó de merge nativo do n8n (fora do
controle do repositório) ou substituí-lo por um nó Code que acumule sem espalhar argumentos.

### Fatia 0.6 — Decisão de escopo e estado regerado · **as duas ADRs: FEITAS em 16/09/2026**
- Reescrever `00_VISAO_E_ESCOPO.md`: o escopo negativo *"não é ferramenta de modelagem financeira"*
  precisa sair ou ser reafirmado. **É decisão do dono** — a engenharia não pode tomá-la, e o roadmap
  inteiro depende dela.
- `PRONTIDAO_POR_ESTAGIO.md` passa a ser **gerado** do banco e do CI.
- ~~Registrar as duas ADRs que governam tudo o que vem depois~~ — **FEITO**:
  `1 Visão e Doutrina/04_ADR_01_EVIDENCIA_IMUTAVEL.md` e `05_ADR_02_ARITMETICA_NO_MOTOR.md`.
  As duas trazem o estado de conformidade MEDIDO, e nenhuma se declara cumprida: a L2/L3 da
  ADR-01 é conteúdo de F1–F4, e a ADR-02 mediu a aritmética em QUATRO casas hoje (n8n 191
  linhas · 44 migrations com soma e 15 `fn_reconciliar_*` · 4 libs do portal · 30 pontos de
  fórmula no Excel). **E a ADR-02 deixa uma fronteira aberta que é do dono**: "planilha viva"
  e "toda aritmética no motor" só convivem sob uma de duas leituras, e escolher é decisão de
  produto — está escrita lá, não resolvida em silêncio.
- *Agente: `estado-e-handoff`. Risco: nenhum técnico.*

### Ordem e commits

```
0.1 --> 0.2 --> 0.3 --> 0.5
   |--> 0.4 (paralela a 0.2/0.3 — arquivos disjuntos)
   |--> 0.6 (paralela a tudo — só docs)
```

Uma fatia por commit, com a mensagem contando defeito, causa e medição (regra 6). Commit sempre pela
sessão principal, capturando o `HEAD` na hora.

### Aceite da F0

| Tipo | Critério |
|---|---|
| **Geral** | `fn_instalacao_conferir()` **em produção** devolve 0 ausentes |
| **Técnico** | hash publicado == gerado · CI falha se produção divergir · espelho `CLAUDE.md`×CI cobre todas as categorias · cada portão novo medido não-vazio |
| **Financeiro** | rodada "Teste 00" reprocessada com ≥95% dos documentos produzindo linha; a diferença de cobertura explicada documento a documento |
| **De produto** | `00_VISAO_E_ESCOPO.md` diz o que o produto é em 2026, e as duas ADRs estão registradas |

### O que a F0 explicitamente NÃO faz

Nenhuma tabela nova. Nenhuma refatoração. Nenhuma migration de arquitetura. Nenhuma camada nova.
**F0 não constrói — ela faz com que medir volte a significar alguma coisa.**

---

## 12. SECOND PHASE EXECUTION PLAN — F1 (entidade e perímetro)

**Escrito em 18/09/2026, com a F0 fechada.** O mesmo formato da seção 11, e pela mesma razão: uma
fase sem fatias declaradas vira uma lista de desejos que ninguém sabe quando acabou.

### 12.1 O estado REAL, medido — e ele não é o "55%" desta página

O cabeçalho da F1 estima `🟡 55%` desde 09/09. **Medido em 18/09 contra o schema e contra o banco
de produção**, o quadro é outro, e em dois pontos é pior do que a estimativa sugeria:

| O que | Medido |
|---|---|
| Colunas de `entidade` | **cinco**: `id`, `caso_id`, `razao_social`, `cnpj`, `papel_no_grupo` |
| `papel_no_grupo` | **existe desde a `0001`**, é `text` livre, e está **NULL nas 13 entidades** do mandato real |
| `perimetro` (tabela) | **não existe** |
| `participacao` (coluna) | **não existe** |
| Funções `fn_*` sobre entidade | **15** já escritas (`fn_upsert_entidade`, `fn_fundir_entidade`, `fn_entidade_canonica_forte`, `fn_entidade_aprender_cnpj`, …) |
| `entidade_ambigua` aberta em produção | **0** — a frente `0169`–`0177` fechou isso, e a "saída" que a F1 declarava já está atingida |
| `entidade_incorreta` aberta em produção | **71** (e 29 resolvidas) |

**Duas leituras mudam o plano.**

Primeira: **`papel_no_grupo` não é um gap de schema, é um estágio desligado.** A coluna está lá há
177 migrations e nunca foi escrita. Isso tem exatamente a aparência de "campo que existe, logo o
papel está modelado" — a regra 7 na forma mais cara, porque quem lê o schema conclui o contrário
do que o dado diz. Tipá-la em enum sem resolver QUEM a preenche entrega o mesmo vazio com tipo
mais forte.

Segunda, e é um defeito que esta medição descobriu: **4 das 13 entidades do mandato real não são
entidades.** São `Empresas`, `Vencidos`, `Status Extratos` e `Controle Extratos Ofx` — cabeçalhos
e abas de planilha que viraram pessoa jurídica. Todas com 1 documento, todas sem CNPJ. O
`fn_upsert_entidade` aceita qualquer string que a extração chame de entidade, e não há guarda
entre "nome próprio de empresa" e "título de coluna". As 8 entidades reais do grupo têm CNPJ; as
4 artefatos não têm nenhum — **o sinal que as separa já está no dado**, e é isso que torna a
fatia barata.

Há ainda um caso que a medição levanta e NÃO decide: `OMNIBEAUTY … GESTAO DE MARCAS LTDA` (com
CNPJ, 17 documentos) e `OMNIBEAUTY … GESTAO DE NEGOCIOS LTDA` (sem CNPJ, 1 documento). Ou são
duas empresas do grupo, ou é um nome lido errado. Só o contrato social responde, e afirmar
qualquer um dos lados aqui seria ausência virando dado.

### 12.2 As fatias, em ordem, com o que destrava o quê

```
1.1 --> 1.2 --> 1.3 --> 1.4 --> 1.5
              |--> 1.6 (paralela: só aceite, depende do dono)
```

#### Fatia 1.1 — Inventário do perímetro (medir antes de construir) · **FEITA em 18/09/2026**
**Entregável:** `Supabase/test/perimetro-inventario.mjs` (irmão da `cobertura-do-lote.sql`, mas em
JS porque a triagem exige normalização e distância de edição, que SQL puro não faz sem custar
legibilidade) + `perimetro-inventario.test.mjs`, provado contra as 71 descrições REAIS lidas de
produção em 18/09 (`Supabase/test/fixtures/entidade_incorreta_18-09-2026.json`, regra 4). Roda
manual via `.github/workflows/perimetro-inventario.yml` (`workflow_dispatch`, não agendado — a
entidade de um mandato muda quando o mandato muda, não no relógio, ao contrário do schema que a
sonda confere todo dia).

**As 71, 100% categorizadas — nenhuma "residual":**

| Causa | N | É bug de comparação? |
|---|---|---|
| `normalizacao_acento_caixa_sufixo` (mesma empresa, acento/caixa/"Ltda." diferentes) | 20 | **sim** |
| `nome_de_arquivo_ou_titulo_virou_entidade` ("Comparativo Araucaria X", "Canastra 2025x2024x2023") | 16 | não |
| `apelido_ou_nome_fantasia_com_palavra_em_comum` ("Grupo Canastra" × razão social) | 12 | não |
| `prefixo_comum_truncado` (nome cadastrado é prefixo do nome completo) | 10 | **sim** |
| `sem_relacao_aparente_revisar_manualmente` ("Ar Log" × "AR TRANSPORTES…") | 4 | não |
| `quase_igual_1_2_chars` ("ARAUGÁRIA" × "ARAUCÁRIA", 1 caractere) | 3 | **sim** |
| `ambigua_ja_correta` (já é `entidade_ambigua`, funcionando como desenhado) | 2 | não |
| `apelido_curto_sem_mapeamento` | 2 | não |
| `mojibake` (encoding) | 1 | **sim** |
| `fixture_sonda` (não é bug, não mexer — a `0162` depende dela) | 1 | não |

**34 das 71 (48%) são bug de comparação** — a mesma empresa, escrita de duas formas, que deveria
ter fechado sozinha. São as candidatas diretas da fatia 1.2. As outras 37 não são defeito de
código: são gap de dado (apelido nunca mapeado, nome de arquivo virando cadastro) ou o sistema
funcionando como desenhado — nenhuma das duas se resolve com a mesma correção.

**Achado que muda o "por caso": não é só o AMO.** `papel_no_grupo` está NULL em **todo** caso do
banco, inclusive os de teste — confirma que não é lacuna do mandato real, é ausência de caminho de
escrita em qualquer lugar do pipeline (ver fatia 1.3). E os dois únicos lugares do repositório
onde a coluna tem valor não-nulo são fixtures SQL **literais** dos books (`fixture_book_canastra.sql`,
`fixture_book_vertentes.sql`) — dado escrito à mão para o export, não produzido por função nenhuma.

**Achado fora do escopo da F1, registrado para a 1.2 não repetir a medição:** rodando o script
contra o banco de TESTE local (122 migrations, fixtures da suíte), o classificador aplicado às
23 pendências sintéticas ali (formato diferente das de produção) reprovou 5 como "residual" —
corretamente: são descrições escritas para testes de migration específicos, não o formato do
diagnóstico de IA. O script **avisa** quando isso acontece em vez de calar (regra 7).

#### Fatia 1.2 — A entidade que não é entidade
Guarda em `fn_upsert_entidade` para que cabeçalho de planilha não vire pessoa jurídica, e a
decisão do que fazer com as 4 que já existem (fundir? marcar? apagar é perda de proveniência).
**Medição não-vazia (regra 2):** com a guarda desligada, as 4 do mandato real têm de passar; com
ela ligada, as 4 têm de ser recusadas ou marcadas — e o número vai na mensagem do commit.
**A armadilha, dita antes:** o critério NÃO pode ser "sem CNPJ" sozinho. Entidade real sem CNPJ
conhecido existe (é o caso do balcão, e as `0175`–`0177` inteiras nasceram disso). O sinal é a
conjunção — sem CNPJ **e** com 1 documento **e** com nome que não tem forma de razão social.
*Agente: `migrations-postgres`. Risco: médio — mexe na porta de entrada que já quebrou em produção.*
**FEITA EM 18/09/2026** — migration `0178`, commit `ad431b9`. **APLICADA EM PRODUÇÃO em
18/09/2026** (sonda: 0 ausentes). O backfill marcou **7** entidades no banco inteiro — previsto 7
antes de aplicar, conferido 7 depois. A conjunção de sinais é o que segura o número: o critério
frouxo ("sem CNPJ e 1 documento", sem o léxico) alcançaria 145.

#### Fatia 1.3 — `papel_no_grupo` tipado E preenchido
Enum (`holding`, `operacional`, `veiculo`, `coligada`, `fora_do_perimetro`), migration de
tipagem, e — a parte que não pode ficar de fora — **quem escreve**. Sem um caminho de escrita, a
fatia entrega o vazio de hoje com tipo mais forte.
**Pronto quando:** as 8 entidades reais do mandato têm papel, ou têm pendência dizendo por que não.
*Agente: `migrations-postgres`. Risco: médio.*
**FEITA EM 18/09/2026** — migration `0179`, verificação independente concluída (banco reconstruído do zero, correção desligada/religada). Commit `14e80da`. **APLICADA EM PRODUÇÃO em 18/09/2026** (sonda: 0 ausentes). Abriu 365 pendências `papel_no_grupo_indefinido` — uma por entidade de TODO o banco, não só do mandato; 347 resolvidas em lote como ruído de caso de teste, 18 seguem abertas. Ver `.claude/memory/aplicar-migration-em-producao-pela-api.md`.

#### Fatia 1.4 — `perimetro(caso, entidade, escopo, desde, ate)`
A tabela nova. Escopo = o conjunto que entra no COMBINADO. `desde`/`ate` porque perímetro muda
no meio do mandato, e um perímetro sem data mente sobre o exercício anterior.
*Agente: `migrations-postgres`. Risco: baixo — aditivo.*
**FEITA EM 18/09/2026** — migration `0180`, verificação independente concluída (idem 1.3). Colisão de duas sessões paralelas resolvida por merge (commits `5c6916a`, base `57a1814`). **APLICADA EM PRODUÇÃO em 18/09/2026** (sonda: 0 ausentes). `perimetro` nasce com 0 linhas: a tabela existe, ninguém declarou perímetro nenhum ainda — isso é decisão humana, não código faltando.

#### Fatia 1.5 — Participação societária
`entidade.participacao`, e a FK preparada que a F4 vai consumir. É a fatia que destrava
consolidação e intercompany.
*Agente: `migrations-postgres`. Risco: médio.*
**FEITA EM 18/09/2026** — migration `0181`, verificação independente concluída (idem 1.3). 29 asserts novos, 4 medidos reprovando (sem a guarda de ciclo). Commit `a3381d8`. **APLICADA EM PRODUÇÃO em 18/09/2026** (sonda: 0 ausentes). `controladora_id` segue NULL nas 365 entidades — e no mandato real isso está CERTO (não há holding, ver fatia 1.6 e a memória do controle comum).

#### Fatia 1.6 — O aceite financeiro (paralela, e depende do dono)
O perímetro tem de reproduzir o COMBINADO do cliente, ou declarar a diferença.

**CORRIGIDO em 18/09/2026 — a "notícia boa" registrada ontem estava ERRADA, e a medição de hoje
a desfaz.** O único documento `COMBINADO` do mandato AMO é, na verdade, `GENERAL TABACO - BALANÇO
2024.pdf`, ligado a **uma única entidade** (`General Tabaco Negócios e Logística Ltda`) — não ao
grupo. O próprio sistema já tinha aberto a pendência certa (`tipo_incorreto`, aberta, "o
documento identifica uma única entidade e um único CNPJ… não se trata de um documento
combinado") ANTES desta sessão perguntar; a medição de ontem só não tinha olhado. **O mandato AMO
não tem combinado real ingerido**, mesma conclusão da classe `EXTRATO_BANCARIO` (F2): o que
existe rotulado como "o documento certo" às vezes não é. **1.6 depende do dono de verdade** —
precisa do combinado do cliente para conferir o perímetro contra ele, como o cabeçalho da F1 já
dizia antes de qualquer medição.

**E EM 18/09/2026, À NOITE, A CAUSA DA AUSÊNCIA FOI MEDIDA — ela não é descuido do cliente.** O
dono informou não conseguir o combinado; a investigação foi então para os CONTRATOS SOCIAIS já
ingeridos, e eles explicam por quê: **não há holding neste grupo.** Nos 4 contratos legíveis,
TODOS os sócios são pessoas físicas e nenhuma empresa é sócia de outra — GENERAL BUSINESS CENTER
(Karina Souto Damasio Tascino ~50% + Rafael Teles ~50%), GENERAL TABACO (Igor Souto Damasio
100%), GLOBAL STORE (Rafael Teles 100%), OMNIBEAUTY MARCAS (Igor Souto Damasio 60% + Leandro
Morales Lima 20% + Roney Thiago Costa 20%). São **empresas irmãs sob controle comum**, e
"demonstração COMBINADA" é exatamente a forma contábil desse arranjo — não exigida em formato
padrão, logo **um grupo assim frequentemente nunca preparou uma**. A 1.6 presumia que o
documento existiria em algum lugar; a medição diz que provavelmente nunca existiu.
Ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`.

**O que a 1.6 vira, então:** enquanto o combinado do cliente não aparecer, o aceite financeiro
da F1 fica **NÃO VERIFICADO, com o motivo declarado** (regra 1 — nunca "passou" por omissão).
Não medido, não estimado, não substituído por uma soma que o próprio sistema faria (essa seria
circular: compararia a nossa conta com ela mesma, e um erro de perímetro atravessaria os dois
lados igual).

**Lacunas nomeadas na mesma medição**, para não virarem buraco silencioso:
`Certidão 5ª Alteração - AMOBELEZA.pdf` e `Certidão 4ª Alteração - CORPORATE.pdf` vieram com ZERO
campos extraídos (as duas já tinham `extracao_falhou` aberta; a da AMOBELEZA também
`tipo_incorreto` dizendo que é certidão, não contrato — o sistema detectou sozinho). Certidão de
Junta não traz distribuição de quotas, mas o nome não prevê o resultado: `Certidão 5ª alteração -
OMNIBEAUTY.pdf` extraiu 54 campos, por ser de inteiro teor. E OMNIBEAUTY DISTRIBUIDORA PR e RS
**não têm contrato social nenhum** — pendências `item_faltante` abertas nesta rodada, motivo
`contrato_social_ausente:<entidade_id>`. Resultado: estrutura societária medida em **4 de 8**
entidades reais.

#### Fatia 1.7 — Grupo econômico por controle comum (NOVA, nasceu da medição da 1.6)
A `0181` modela participação como `entidade.controladora_id` — FK de EMPRESA para EMPRESA. No
mandato real **nenhuma empresa controla outra**, então essa coluna fica NULL nas 8 por estar
CERTA, e o sistema fica sem onde registrar que elas são um grupo. É a regra 7 outra vez: NULL
por "o grupo é horizontal" é hoje indistinguível de NULL por "ninguém cadastrou".
**O que falta:** uma forma de registrar o vínculo que existe de fato — controle comum por
sócio/controlador — sem inventar uma holding que não existe.
**Pronto quando (como estava escrito em 18/09):** as 8 entidades do mandato real podem ser
reconhecidas como um grupo, e um `controladora_id` vazio passa a ser distinguível de um não
preenchido.
*Agente: `migrations-postgres`. Risco: médio — mexe no mesmo modelo que a 1.5 acabou de criar.*

**CONSTRUÍDA, MEDIDA E REVISADA (21–23/09/2026, PR #238) — `0182` APLICADA em produção em 23/09,
`0183` PENDENTE de aplicação pelo dono.** A 1.5 continua válida para mandatos COM holding; esta
fatia a complementa. `0182`: `controlador` + `entidade_controlador` + `fn_grupo_por_controle_comum`
(fecho transitivo). `0183`: `entidade.forma_de_controle` (`indefinido` · `controlada_por_entidade`
· `controle_comum`), com check de coerência e gatilho de vínculo. Números e achados em
`.claude/conhecimento/fichas/f1-controle-comum-0182-0183.md`.

**A metade "distinguível" está entregue** (na `0183`): `indefinido`/NULL e `controle_comum`/NULL
são estados diferentes por consulta, provado por teste.

**A metade "as 8 como um grupo" NÃO é alcançável pelo dado medido, e isso é achado, não atraso.**
MEDIDO em 23/09 rodando o modelo sobre os sócios e quotas EXATOS dos 4 contratos legíveis (banco
local, transação desfeita): **dois grupos de dois**, cada um ligado por um sócio pessoa física, e as
quatro entidades sem contrato lido fora da saída. Unir os dois grupos exigiria afirmar que sócios de
MESMO SOBRENOME formam um bloco de controle familiar — juízo, não medição, e o modelo se recusa a
fabricá-lo (regra 1). É o padrão da 1.6 de novo: o critério presumiu algo que o dado não mostra.

**Pronto quando (revisado em 23/09, com a medição acima):** (a) `0183` aplicada em produção; (b)
os sócios dos contratos LEGÍVEIS registrados, e a forma de controle das entidades com base nisso —
o que dá os dois grupos que o dado sustenta. "As 8 como um grupo" sai deste critério e passa a
depender de duas coisas que não são código: **os 4 contratos que faltam** (AMOBELEZA e CORPORATE
vieram com zero campos; DISTRIBUIDORAS PR/RS não têm contrato) e **uma decisão do dono sobre se
controle familiar conta como controle comum** — relevante na prática de grupo econômico, mas sem
conceito correspondente no modelo (não há "bloco familiar"; `controlador` é uma pessoa). Se o dono
decidir que conta, é uma fatia nova de modelo, não um cadastro.

### 12.3 O que a F1 NÃO faz, dito de propósito

- **Não cria `conta_canonica`.** Identidade de CONTA é F4, e misturar as duas é o caminho mais
  curto para uma migration que ninguém consegue reverter.
- **Não resolve o caso OMNIBEAUTY MARCAS × NEGOCIOS.** Isso é leitura de contrato social, não
  engenharia — a 1.1 o deixa nomeado na triagem, e alguém decide com o documento na mão.
- **Não toca `campo_extraido`.** O roadmap proíbe paralelizar qualquer coisa que toque esse
  caminho com a F4, e antecipar isso na F1 cria a dependência que a proibição existe para evitar.
